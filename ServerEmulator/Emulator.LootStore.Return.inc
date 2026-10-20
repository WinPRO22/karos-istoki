function TB1008LootStore.ReturnState(Owner:TObject):TB1008ReturnState;
var Q:TFDQuery;
begin
  Result:=Default(TB1008ReturnState);FLock.Acquire;
  try
    RequireOwner(Owner);Q:=TFDQuery.Create(nil);
    try
      Q.Connection:=FDB;Q.Open('SELECT point,until_ms,pending FROM return_stone WHERE id=1');
      Result.Point:=Q.Fields[0].AsLargeInt;Result.UntilMS:=Q.Fields[1].AsLargeInt;
      Result.Pending:=Q.Fields[2].AsInteger=1;
    finally Q.Free;end;
  finally FLock.Release;end;
end;

procedure TB1008LootStore.BindReturn(Owner:TObject);
begin
  FLock.Acquire;
  try
    RequireOwner(Owner);
    // Rebinding never clears the existing cooldown or an interrupted transfer.
    FDB.ExecSQL('UPDATE return_stone SET point=190033 WHERE id=1');
  finally FLock.Release;end;
end;

function TB1008LootStore.UseReturn(Owner:TObject;const Receipt:string;Slot:Byte;NowMS:Int64):Boolean;
var A:TB1008BagItem;S:TB1008ReturnState;
begin
  Result:=False;if (Receipt='') or (Slot>=B1008BagSlots) then Exit;
  if NowMS=-1 then NowMS:=B1008UtcNowMS;
  if (NowMS<0) or (NowMS>High(Int64)-B1008ReturnCooldownMS) then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      S:=ReturnState(Owner);A:=FindSlot(Slot);
      if (S.Point<>B1008BerneoReturnPoint) or S.Pending or (S.UntilMS>NowMS) or
        (A.ItemID<>B1008ReturningStoneID) or (A.Amount=0) or
        (Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM operations WHERE receipt=:r',['return:'+Receipt]))<>0) then Exit;
      FDB.ExecSQL('UPDATE return_stone SET until_ms=:t,pending=1 WHERE id=1',[NowMS+B1008ReturnCooldownMS]);
      FDB.ExecSQL('INSERT INTO operations VALUES(:r)',['return:'+Receipt]);
      // Permanent stone: no inventory decrement. Pending transfer recovers after crash.
      FDB.Commit;Result:=True;
    finally if FDB.InTransaction then FDB.Rollback;end;
  finally FLock.Release;end;
end;

procedure TB1008LootStore.CompleteReturn(Owner:TObject);
begin
  FLock.Acquire;
  try RequireOwner(Owner);FDB.ExecSQL('UPDATE return_stone SET pending=0 WHERE id=1');
  finally FLock.Release;end;
end;
