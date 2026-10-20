function TB1008LootStore.ReadClassState:TB1008ClassState;
var Q:TFDQuery;
begin
  Result:=Default(TB1008ClassState);Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FDB;Q.Open('SELECT base_class,class_id,rank FROM hero_class WHERE id=1');
    if Q.Eof then Exit;
    Result.BaseClass:=Q.Fields[0].AsInteger;Result.ClassID:=Q.Fields[1].AsInteger;
    Result.Rank:=Q.Fields[2].AsInteger;
    if (TB1008ClassWire.BaseClass(Result.ClassID)<>Result.BaseClass) or (Result.Rank>1) or
      ((Result.ClassID=Result.BaseClass) and (Result.Rank<>0)) then
      raise Exception.Create('Invalid saved profession; database preserved');
  finally Q.Free;end;
end;

function TB1008LootStore.ClassState(Owner:TObject):TB1008ClassState;
begin
  FLock.Acquire;
  try RequireOwner(Owner);Result:=ReadClassState;finally FLock.Release;end;
end;

function TB1008LootStore.PreviewClass(const Preview:TBytes):TB1008ClassState;
var Identity,Saved:string;Base:Word;
begin
  Identity:=PreviewIdentity(Preview);Move(Preview[15],Base,2);
  FLock.Acquire;
  try
    Saved:=VarToStr(FDB.ExecSQLScalar('SELECT identity FROM hero WHERE id=1'));
    if (Saved<>'') and (Saved<>Identity) then raise Exception.Create('Profession preview identity mismatch');
    Result:=ReadClassState;
    if Result.ClassID=0 then begin Result.BaseClass:=Base;Result.ClassID:=Base;end;
    if Result.BaseClass<>Base then raise Exception.Create('Profession preview base mismatch');
  finally FLock.Release;end;
end;

function TB1008LootStore.ChangeClass(Owner:TObject;const Receipt:string;
  const Request:TB1008ClassChange;out State:TB1008ClassState;
  out Updated:TArray<TB1008BagItem>):Word;
var Wallet:TB1008BagItem;RequiredLevel:Word;Price,Certificate:Cardinal;
begin
  Result:=$86;Updated:=nil;State:=Default(TB1008ClassState);
  if (Receipt='') or not Request.Supported then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      State:=ReadClassState;
      // Replay is checked before source validation, and never spends again.
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM class_receipts WHERE receipt=:r AND target=:c AND rank=:k',
        [Receipt,Int64(Request.TargetClass),Int64(Request.TargetRank)]))<>0 then begin
        FDB.Rollback;if (State.ClassID=Request.TargetClass) and (State.Rank=Request.TargetRank) then Result:=$81;Exit;
      end;
      if not TB1008ClassWire.ChangeRule(State,Request,RequiredLevel,Price,Certificate) then begin
        FDB.Rollback;Result:=$82;Exit;
      end;
      if ReadProgress.Level<RequiredLevel then begin FDB.Rollback;Result:=$84;Exit;end;
      Wallet:=FindItem(B1008CaratID);
      if Wallet.Amount<Price then begin FDB.Rollback;Result:=$83;Exit;end;
      if (Certificate<>0) and not TakeQuestItem(Certificate,1,Updated) then begin
        FDB.Rollback;Updated:=nil;Result:=$85;Exit;end;
      if not TakeQuestItem(B1008CaratID,Price,Updated) then raise Exception.Create('Profession payment changed');
      FDB.ExecSQL('UPDATE hero_class SET class_id=:c,rank=:k WHERE id=1',[Int64(Request.TargetClass),Int64(Request.TargetRank)]);
      FDB.ExecSQL('INSERT INTO class_receipts VALUES(:r,:c,:k)',[Receipt,Int64(Request.TargetClass),Int64(Request.TargetRank)]);
      FDB.Commit;State.ClassID:=Request.TargetClass;State.Rank:=Request.TargetRank;Result:=$81;
    except
      FDB.Rollback;Updated:=nil;raise;
    end;
  finally FLock.Release;end;
end;
