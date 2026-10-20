// Included by Emulator.LootStore.B1008: the same lock, connection and transaction
// own quest state, inventory changes and rewards. No second save file is used.
procedure RememberQuestItem(var Updated:TArray<TB1008BagItem>;const Item:TB1008BagItem);
var I:Integer;
begin
  for I:=0 to High(Updated) do if (Updated[I].Slot=Item.Slot) and (Updated[I].ItemID=Item.ItemID) then begin Updated[I]:=Item;Exit;end;
  SetLength(Updated,Length(Updated)+1);Updated[High(Updated)]:=Item;
end;

function TB1008LootStore.ReadQuest(ID:Cardinal):TB1008QuestEntry;
var Q:TFDQuery;Status:Integer;D:TB1008QuestDefinition;O:TB1008QuestObjective;Amount:Int64;
begin
  Result:=Default(TB1008QuestEntry);
  Status:=Integer(FDB.ExecSQLScalar('SELECT COALESCE((SELECT status FROM quests WHERE quest_id=:q),0)',[Int64(ID)]));
  if Status=0 then Exit;
  Result.ID:=ID;Result.Completed:=Status=2;Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FDB;Q.Open('SELECT objective,count FROM quest_objectives WHERE quest_id=:q',[Int64(ID)]);
    while not Q.Eof do begin Result.Counts[Q.Fields[0].AsInteger]:=Q.Fields[1].AsLargeInt;Q.Next;end;
  finally Q.Free;end;
  // Collection progress is owned inventory, not kills or a client assertion.
  // Deriving it inside the reward transaction also covers items sold, dropped,
  // equipped or consumed by another quest without a stale cached completion.
  if not Result.Completed then begin
    D:=TB1008QuestCatalog.Get(ID);
    for O in D.Objectives do if (O.Kind=3) or
      ((O.Kind=9) and (Result.Counts[O.Index]>0)) then begin
      Amount:=QuestItemAmount(O.Target,O.RequiredGemID);
      if Amount>O.Required then Amount:=O.Required;
      Result.Counts[O.Index]:=Amount;
    end;
  end;
end;

function TB1008LootStore.RewardFarm(Owner:TObject;Healing,Mana:Cardinal;
  out Updated:TArray<TB1008BagItem>;out Progress:TB1008Progress):Boolean;
var Gain:Int64;R:TB1008QuestAward;
begin
  if (Healing>3) or (Mana>3) then raise EArgumentException.Create('Invalid legacy rewards');
  Result:=False;Updated:=nil;Progress:=Default(TB1008Progress);
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      Progress:=ReadProgress;
      // Retain the old import receipt: already granted/consumed potions must
      // never reappear when an existing character receives the missing Carat.
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM operations WHERE receipt=''quest-rewards-imported'''))=0 then begin
        if ((Healing>0) and not AddQuestItem(54006,Healing,Updated)) or
          ((Mana>0) and not AddQuestItem(54206,Mana,Updated)) then begin
          FDB.Rollback;Updated:=nil;Exit;
        end;
        FDB.ExecSQL('INSERT INTO operations VALUES(''quest-rewards-imported'')');
      end;
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM operations WHERE receipt=''farm-carat-reward'''))=0 then begin
        for R in TB1008QuestCatalog.Get(19003003).Rewards do if R.Kind=2 then
          if not AddQuestItem(B1008CaratID,R.Value,Updated) then begin
            FDB.Rollback;Updated:=nil;Exit;
          end;
        FDB.ExecSQL('INSERT INTO operations VALUES(''farm-carat-reward'')');
      end;
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM exp_receipts WHERE receipt=''quest/19003003'''))=0 then begin
        Gain:=TB1008Rates.Scale(TB1008Balance.QuestEXP(19003003),FRates.Experience,
          TB1008Balance.MaxEXP-Progress.TotalEXP);
        Inc(Progress.TotalEXP,Gain);Progress.Validate;
        FDB.ExecSQL('INSERT INTO exp_receipts(receipt,amount) VALUES(''quest/19003003'',:n)',[Gain]);
        FDB.ExecSQL('INSERT OR REPLACE INTO progression VALUES(1,:n)',[Progress.TotalEXP]);
        AwardSkillLevels(Progress.Level);LimitFletta(Progress.Level);
      end;
      FDB.Commit;Result:=True;
    except FDB.Rollback;Updated:=nil;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.QuestDropNeeds(Owner:TObject;ModelID:Cardinal):TArray<TB1008QuestDropNeed>;
var D:TB1008QuestDefinition;E:TB1008QuestEntry;O:TB1008QuestObjective;I:Integer;
  Missing:Cardinal;
begin
  Result:=nil;FLock.Acquire;
  try
    RequireOwner(Owner);
    for D in TB1008QuestCatalog.All do begin
      if not D.Enabled then Continue;
      E:=ReadQuest(D.ID);if (E.ID=0) or E.Completed then Continue;
      for O in D.Objectives do if (O.Kind=3) and (O.ItemSource='mob') and (O.SourceMob=ModelID) and
        (E.Counts[O.Index]<O.Required) then begin
        Missing:=O.Required-E.Counts[O.Index];I:=0;
        while (I<Length(Result)) and (Result[I].ItemID<>O.Target) do Inc(I);
        if I=Length(Result) then begin SetLength(Result,I+1);Result[I].ItemID:=O.Target;end;
        // Shared requirements use one inventory and one roll for each item.
        if Missing>Result[I].Missing then Result[I].Missing:=Missing;
        if O.DropChanceBP>Result[I].ChanceBP then Result[I].ChanceBP:=O.DropChanceBP;
      end;
    end;
  finally FLock.Release;end;
end;

function TB1008LootStore.QuestEntries(Owner:TObject):TArray<TB1008QuestEntry>;
var Q:TB1008QuestDefinition;E:TB1008QuestEntry;
begin
  Result:=nil;FLock.Acquire;
  try
    RequireOwner(Owner);
    for Q in TB1008QuestCatalog.All do begin
      E:=ReadQuest(Q.ID);if E.ID=0 then Continue;
      SetLength(Result,Length(Result)+1);Result[High(Result)]:=E;
    end;
  finally FLock.Release;end;
end;

function TB1008LootStore.AddQuestItem(ID,Amount:Cardinal;var Updated:TArray<TB1008BagItem>):Boolean;
var Limit,N:Cardinal;Slot:Integer;A:TB1008BagItem;
begin
  Result:=False;Limit:=TB1008Items.StackLimit(ID);if (Limit=0) or (Amount=0) then Exit;
  while Amount>0 do begin
    Slot:=Integer(FDB.ExecSQLScalar('SELECT COALESCE(MIN(slot),-1) FROM inventory WHERE item_id=:i AND amount<:n',
      [Int64(ID),Int64(Limit)]));
    if Slot>=0 then A:=FindSlot(Slot)
    else begin
      if (ID=B1008CaratID) and (FindItem(ID).Amount>0) then Exit;
      A:=Default(TB1008BagItem);A.Slot:=FreeSlot(255);if A.Slot=255 then Exit;
      A.ItemID:=ID;
    end;
    N:=Limit-A.Amount;if N>Amount then N:=Amount;
    Inc(A.Amount,N);Dec(Amount,N);SaveItem(A);RememberQuestItem(Updated,A);
  end;
  Result:=True;
end;

function TB1008LootStore.QuestItemAmount(ID,RequiredGemID:Cardinal):Int64;
begin
  if RequiredGemID=0 then
    Result:=Int64(FDB.ExecSQLScalar('SELECT COALESCE(SUM(amount),0) FROM inventory WHERE item_id=:i',[Int64(ID)]))
  else
    Result:=Int64(FDB.ExecSQLScalar('SELECT COALESCE(SUM(v.amount),0) FROM inventory v JOIN item_instances p ON p.instance_id=v.instance_id '+
      'WHERE v.item_id=:i AND (p.gem0=:g OR p.gem1=:g)',[Int64(ID),Int64(RequiredGemID)]));
end;

function TB1008LootStore.TakeQuestItem(ID,Amount:Cardinal;var Updated:TArray<TB1008BagItem>;RequiredGemID:Cardinal):Boolean;
var A:TB1008BagItem;N:Cardinal;
begin
  Result:=False;
  if QuestItemAmount(ID,RequiredGemID)<Amount then Exit;
  while Amount>0 do begin
    if RequiredGemID=0 then A:=FindItem(ID)
    else A:=FindSlot(Integer(FDB.ExecSQLScalar('SELECT MIN(v.slot) FROM inventory v JOIN item_instances p ON p.instance_id=v.instance_id '+
      'WHERE v.item_id=:i AND (p.gem0=:g OR p.gem1=:g)',[Int64(ID),Int64(RequiredGemID)])));
    N:=A.Amount;if N>Amount then N:=Amount;
    if N=0 then raise Exception.Create('Quest inventory changed in transaction');
    Dec(A.Amount,N);Dec(Amount,N);SaveItem(A);RememberQuestItem(Updated,A);
  end;
  Result:=True;
end;

function TB1008LootStore.AcceptQuest(Owner:TObject;ID:Cardinal;LegacyActive:Boolean;
  out Updated:TArray<TB1008BagItem>):Boolean;
var D:TB1008QuestDefinition;E:TB1008QuestEntry;O:TB1008QuestObjective;P:TB1008Progress;AcceptanceID:Cardinal;
begin
  Result:=False;Updated:=nil;
  if (ID=19003003) or not TB1008QuestCatalog.Find(ID,D) or not D.Enabled then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      E:=ReadQuest(ID);
      if (E.ID<>0) and (not E.Completed or not D.Repeatable) then begin FDB.Rollback;Exit(not E.Completed);end;
      P:=ReadProgress;
      if (P.Level<D.MinLevel) or (P.Level>D.MaxLevel) or
        ((D.Previous<>0) and not ReadQuest(D.Previous).Completed) or
        (Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM quests WHERE status=1'))+Ord(LegacyActive)>=20) then begin FDB.Rollback;Exit;end;
      for AcceptanceID in D.AcceptanceItems do if not AddQuestItem(AcceptanceID,1,Updated) then begin
        FDB.Rollback;Updated:=nil;Exit;
      end;
      if E.ID<>0 then begin
        FDB.ExecSQL('UPDATE quests SET status=1,choice=-1 WHERE quest_id=:q',[Int64(ID)]);
        FDB.ExecSQL('UPDATE quest_cycles SET cycle=cycle+1 WHERE quest_id=:q',[Int64(ID)]);
      end else begin
        FDB.ExecSQL('INSERT INTO quests(quest_id,status) VALUES(:q,1)',[Int64(ID)]);
        FDB.ExecSQL('INSERT INTO quest_cycles VALUES(:q,0)',[Int64(ID)]);
      end;
      for O in D.Objectives do FDB.ExecSQL('INSERT OR REPLACE INTO quest_objectives VALUES(:q,:o,0)',[Int64(ID),Int64(O.Index)]);
      FDB.Commit;Result:=True;
    except FDB.Rollback;Updated:=nil;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.PerformQuest(Owner:TObject;ID,Kind,Target,Count:Cardinal;
  out Update:TB1008QuestUpdate):Boolean;
var D:TB1008QuestDefinition;E:TB1008QuestEntry;O:TB1008QuestObjective;
begin
  Result:=False;Update:=Default(TB1008QuestUpdate);
  if not (Kind in [8,9]) or not TB1008QuestCatalog.Find(ID,D) or not D.Enabled then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      E:=ReadQuest(ID);
      if (E.ID=0) or E.Completed then begin FDB.Rollback;Exit;end;
      for O in D.Objectives do if (O.Kind=Kind) and (O.Target=Target) and (O.Required=Count) then begin
        if (Kind=9) and (QuestItemAmount(Target,O.RequiredGemID)<Count) then begin
          FDB.Rollback;Exit;
        end;
        FDB.ExecSQL('UPDATE quest_objectives SET count=:n WHERE quest_id=:q AND objective=:o',
          [Int64(O.Required),Int64(ID),Int64(O.Index)]);
        Update.QuestID:=ID;Update.Kind:=Kind;Update.Target:=Target;Update.Count:=O.Required;
        FDB.Commit;Exit(True);
      end;
      FDB.Rollback;
    except FDB.Rollback;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.RecordQuestKill(Owner:TObject;const Receipt:string;ModelID:Cardinal):TArray<TB1008QuestUpdate>;
var D:TB1008QuestDefinition;E:TB1008QuestEntry;O:TB1008QuestObjective;U:TB1008QuestUpdate;
begin
  Result:=nil;if (Receipt='') or (Length(Receipt)>512) then raise EArgumentException.Create('Missing quest kill receipt');
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM quest_kills WHERE receipt=:r',[Receipt]))<>0 then begin FDB.Rollback;Exit;end;
      for D in TB1008QuestCatalog.All do begin
        if not D.Enabled or (D.ID=19003003) then Continue;
        E:=ReadQuest(D.ID);if (E.ID=0) or E.Completed then Continue;
        for O in D.Objectives do if (O.Kind in [1,2]) and (O.Target=ModelID) and (E.Counts[O.Index]<O.Required) then begin
          Inc(E.Counts[O.Index]);FDB.ExecSQL('UPDATE quest_objectives SET count=:n WHERE quest_id=:q AND objective=:o',
            [Int64(E.Counts[O.Index]),Int64(D.ID),Int64(O.Index)]);
          U.QuestID:=D.ID;U.Kind:=O.Kind;U.Target:=O.Target;U.Count:=E.Counts[O.Index];
          SetLength(Result,Length(Result)+1);Result[High(Result)]:=U;
        end;
      end;
      FDB.ExecSQL('INSERT INTO quest_kills VALUES(:r,:m)',[Receipt,Int64(ModelID)]);
      FDB.Commit;
    except FDB.Rollback;Result:=nil;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.RewardQuest(Owner:TObject;ID,Choice:Cardinal;
  out Updated:TArray<TB1008BagItem>;out Progress:TB1008Progress):Boolean;
var D:TB1008QuestDefinition;E:TB1008QuestEntry;O:TB1008QuestObjective;R:TB1008QuestAward;
  Gain,Experience,SavedChoice,Cycle:Int64;Receipt:string;
begin
  Result:=False;Updated:=nil;Progress:=Default(TB1008Progress);
  if (ID=19003003) or not TB1008QuestCatalog.Find(ID,D) or not D.Enabled or not D.ValidChoice(Choice) then Exit;
  SavedChoice:=Choice;if Choice=High(Cardinal) then SavedChoice:=-1;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      Progress:=ReadProgress;E:=ReadQuest(ID);
      if E.ID=0 then begin FDB.Rollback;Exit;end;
      if E.Completed then begin
        Result:=Int64(FDB.ExecSQLScalar('SELECT choice FROM quests WHERE quest_id=:q',[Int64(ID)]))=SavedChoice;
        FDB.Rollback;Exit;
      end;
      if not TB1008QuestCatalog.Ready(E) then begin FDB.Rollback;Exit;end;
      for O in D.Objectives do if O.Kind in [3,9] then
        if not TakeQuestItem(O.Target,O.Required,Updated,O.RequiredGemID) then begin FDB.Rollback;Updated:=nil;Exit;end;
      Experience:=0;
      for R in D.Rewards do begin
        if R.Choice and (R.Index<>Choice) then Continue;
        case R.Kind of
          1:Inc(Experience,R.Value);
          2:if not AddQuestItem(B1008CaratID,R.Value,Updated) then begin FDB.Rollback;Updated:=nil;Exit;end;
          3:if not AddQuestItem(R.Value,R.Amount,Updated) then begin FDB.Rollback;Updated:=nil;Exit;end;
        end;
      end;
      Receipt:='quest/'+UIntToStr(ID);
      Cycle:=Int64(FDB.ExecSQLScalar('SELECT COALESCE((SELECT cycle FROM quest_cycles WHERE quest_id=:q),0)',[Int64(ID)]));
      if Cycle>0 then Receipt:=Receipt+'/repeat/'+IntToStr(Cycle);
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM exp_receipts WHERE receipt=:r',[Receipt]))<>0 then
        raise Exception.Create('Quest reward receipt without completed quest');
      Gain:=TB1008Rates.Scale(Experience,FRates.Experience,TB1008Balance.MaxEXP-Progress.TotalEXP);
      Inc(Progress.TotalEXP,Gain);Progress.Validate;
      FDB.ExecSQL('INSERT INTO exp_receipts(receipt,amount) VALUES(:r,:n)',[Receipt,Gain]);
      FDB.ExecSQL('INSERT OR REPLACE INTO progression VALUES(1,:n)',[Progress.TotalEXP]);
      AwardSkillLevels(Progress.Level);LimitFletta(Progress.Level);
      FDB.ExecSQL('UPDATE quests SET status=2,choice=:c WHERE quest_id=:q',[SavedChoice,Int64(ID)]);
      FDB.Commit;Result:=True;
    except FDB.Rollback;Updated:=nil;raise;end;
  finally FLock.Release;end;
end;
