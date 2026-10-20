function TB1008LootStore.ReadStashSlot(Slot:Byte):TB1008BagItem;
var Q:TFDQuery;
begin
  Result:=Default(TB1008BagItem);Result.Slot:=Slot;Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FDB;Q.Open('SELECT item_id,amount,COALESCE(instance_id,0) FROM personal_stash WHERE slot=:s',[Slot]);
    if not Q.Eof then begin Result.ItemID:=Q.Fields[0].AsLargeInt;Result.Amount:=Q.Fields[1].AsLargeInt;
      Result.Properties:=ReadProperties(Q.Fields[2].AsLargeInt);end;
  finally Q.Free;end;
end;

procedure TB1008LootStore.SaveStashItem(var Item:TB1008BagItem);
begin
  if Item.Amount=0 then FDB.ExecSQL('DELETE FROM personal_stash WHERE slot=:s',[Item.Slot])
  else begin
    EnsureProperties(Item.ItemID,Item.Properties);
    FDB.ExecSQL('INSERT INTO personal_stash(slot,item_id,amount,instance_id) VALUES(:s,:i,:a,NULLIF(:p,0)) ON CONFLICT(slot) DO UPDATE SET '+
      'item_id=excluded.item_id,amount=excluded.amount,instance_id=excluded.instance_id',
      [Item.Slot,Int64(Item.ItemID),Int64(Item.Amount),Item.Properties.InstanceID]);
  end;
end;

function TB1008LootStore.StashItems(Owner:TObject):TArray<TB1008BagItem>;
var Q:TFDQuery;N:Integer;
begin
  Result:=nil;FLock.Acquire;
  try
    RequireOwner(Owner);Q:=TFDQuery.Create(nil);
    try
      Q.Connection:=FDB;Q.Open('SELECT slot,item_id,amount,COALESCE(instance_id,0) FROM personal_stash ORDER BY slot');
      while not Q.Eof do begin
        N:=Length(Result);SetLength(Result,N+1);Result[N].Slot:=Q.Fields[0].AsInteger;
        Result[N].ItemID:=Q.Fields[1].AsLargeInt;Result[N].Amount:=Q.Fields[2].AsLargeInt;
        Result[N].Properties:=ReadProperties(Q.Fields[3].AsLargeInt);Q.Next;
      end;
    finally Q.Free;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.TransferStash(Owner:TObject;const Receipt:string;const Request:TB1008StashRequest;
  out NewAmount:Cardinal;out Updated:TArray<TB1008BagItem>):Boolean;
var StashUpdated:TArray<TB1008BagItem>;
begin Result:=TransferStash(Owner,Receipt,Request,NewAmount,Updated,StashUpdated);end;

function TB1008LootStore.TransferStash(Owner:TObject;const Receipt:string;const Request:TB1008StashRequest;
  out NewAmount:Cardinal;out Updated,StashUpdated:TArray<TB1008BagItem>):Boolean;
var A,B,C:TB1008BagItem;N:Int64;Limit,Remaining,Take:Cardinal;Slot:Integer;
  procedure PutIntoCell(S:Integer;ExistingOnly:Boolean);
  begin
    if Remaining=0 then Exit;
    C:=ReadStashSlot(S);
    if (C.Amount>0) and (C.ItemID<>A.ItemID) then Exit;
    if ExistingOnly and (C.Amount=0) then Exit;
    Take:=Limit-C.Amount;if Take>Remaining then Take:=Remaining;
    if Take=0 then Exit;
    if C.Amount=0 then C.Properties:=A.Properties;
    C.ItemID:=A.ItemID;Inc(C.Amount,Take);Dec(Remaining,Take);
    SaveStashItem(C);RememberQuestItem(StashUpdated,C);
  end;
begin
  Result:=False;NewAmount:=0;Updated:=nil;StashUpdated:=nil;
  if (Receipt='') or (Request.CharacterID<>1) then Exit;
  case Request.Kind of
    $1A:if (Request.Code<>$91) or (Request.Page<>1) or (Request.Slot>=B1008BagSlots) or
      (Request.TargetSlot>=B1008StashSlots) or (Request.ItemID=0) or
      TB1008Items.IsQuestItem(Request.ItemID) then Exit;
    $1B:if (Request.Code<>$91) or (Request.Slot>=B1008StashSlots) then Exit;
    $28:if (Request.Code<>$93) or (Request.Page<>0) or (Request.TargetPage<>0) or
      (Request.Slot>=B1008StashSlots) or (Request.TargetSlot>=B1008StashSlots) or
      (Request.Slot=Request.TargetSlot) then Exit;
    else Exit;
  end;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM operations WHERE receipt=:r',['stash:'+Receipt]))<>0 then Exit;
      case Request.Kind of
        $1A:begin
          A:=FindSlot(Request.Slot);B:=ReadStashSlot(Request.TargetSlot);
          if (A.Amount=0) or (A.ItemID<>Request.ItemID) or
            ((B.Amount>0) and (B.ItemID<>A.ItemID)) then Exit;
          N:=Request.Amount;if N=-1 then N:=A.Amount;
          Limit:=TB1008Items.StackLimit(A.ItemID);
          if (N<=0) or (N>A.Amount) then Exit;
          // Currency has one aggregate display even if old saves have several cells.
          if (A.ItemID=B1008CaratID) and
            (Int64(FDB.ExecSQLScalar('SELECT COALESCE(SUM(amount),0) FROM personal_stash WHERE item_id=999999'))>Int64(Limit)-N) then Exit;
          Remaining:=N;
          PutIntoCell(Request.TargetSlot,True);
          for Slot:=0 to B1008StashSlots-1 do PutIntoCell(Slot,True);
          PutIntoCell(Request.TargetSlot,False);
          for Slot:=0 to B1008StashSlots-1 do PutIntoCell(Slot,False);
          if Remaining<>0 then Exit; // rollback partial fills when the remainder cannot fit
          Dec(A.Amount,Cardinal(N));SaveItem(A);RememberQuestItem(Updated,A);
          NewAmount:=ReadStashSlot(Request.TargetSlot).Amount;
        end;
        $1B:begin
          A:=ReadStashSlot(Request.Slot);if A.Amount=0 then Exit;
          N:=Request.Amount;if N=-1 then N:=A.Amount;
          if (N<=0) or (N>A.Amount) then Exit;
          if TB1008Items.StackLimit(A.ItemID)=1 then begin
            C:=A;C.Slot:=FreeSlot(255);if C.Slot=255 then Exit;
            SaveItem(C);RememberQuestItem(Updated,C);
          end else if not AddQuestItem(A.ItemID,Cardinal(N),Updated) then Exit;
          Dec(A.Amount,Cardinal(N));SaveStashItem(A);NewAmount:=A.Amount;
        end;
        $28:begin
          A:=ReadStashSlot(Request.Slot);B:=ReadStashSlot(Request.TargetSlot);
          if (A.Amount=0) or (A.ItemID<>Request.ItemID) or (A.Amount<>Request.Amount) or
            (B.ItemID<>Request.TargetID) or (B.Amount<>Request.TargetAmount) then Exit;
          Limit:=TB1008Items.StackLimit(A.ItemID);
          if (A.ItemID=B.ItemID) and (Limit>1) then begin
            Take:=Limit-B.Amount;if Take>A.Amount then Take:=A.Amount;
            if Take=0 then Exit;
            Dec(A.Amount,Take);Inc(B.Amount,Take);SaveStashItem(A);SaveStashItem(B);
            RememberQuestItem(StashUpdated,A);RememberQuestItem(StashUpdated,B);
          end else begin
            A.Slot:=Request.TargetSlot;B.Slot:=Request.Slot;SaveStashItem(A);SaveStashItem(B);
          end;
        end;
      end;
      FDB.ExecSQL('INSERT INTO operations VALUES(:r)',['stash:'+Receipt]);
      FDB.Commit;Result:=True;
    finally
      if FDB.InTransaction then FDB.Rollback;
      if not Result then begin Updated:=nil;StashUpdated:=nil;NewAmount:=0;end;
    end;
  finally FLock.Release;end;
end;
