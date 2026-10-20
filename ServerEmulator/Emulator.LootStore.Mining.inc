function TB1008LootStore.MineQuestItem(Owner:TObject;const Receipt:string;
  out Updated:TArray<TB1008BagItem>):Byte;
var Entry:TB1008QuestEntry;Gear:TB1008EquipmentItem;HasPick:Boolean;
begin
  Result:=$60;Updated:=nil;if Receipt='' then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      Entry:=ReadQuest(19003016);
      if (Entry.ID=0) or Entry.Completed then Exit;
      HasPick:=False;
      for Gear in ReadEquipment do if (Gear.Slot=7) and
        ((Gear.ItemID=30001) or (Gear.ItemID=30002)) then HasPick:=True;
      if not HasPick then begin Result:=$61;Exit;end;
      // Quest-only authored policy: one ore, capped at the objective's three.
      // No ordinary mining reward table has been established for this build.
      if (FindItem(70079).Amount>=3) or (Integer(FDB.ExecSQLScalar(
        'SELECT COUNT(*) FROM operations WHERE receipt=:r',['mine:'+Receipt]))<>0) then begin
        Result:=$5F;Exit;
      end;
      if not AddQuestItem(70079,1,Updated) then begin Result:=$0B;Exit;end;
      FDB.ExecSQL('INSERT INTO operations VALUES(:r)',['mine:'+Receipt]);
      FDB.Commit;Result:=$5F;
    finally
      if FDB.InTransaction then FDB.Rollback;
      if Result<>$5F then Updated:=nil;
    end;
  finally FLock.Release;end;
end;
