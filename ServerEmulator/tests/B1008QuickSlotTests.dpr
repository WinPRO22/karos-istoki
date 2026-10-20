program B1008QuickSlotTests;
{$APPTYPE CONSOLE}
uses Emulator.Rates.B1008,System.SysUtils,System.IOUtils,FireDAC.Comp.Client,
  Emulator.QuickSlots.B1008,Emulator.Protocol.B1008,Emulator.LootStore.B1008,
  Emulator.Character.B1008,Emulator.World.B1008,Emulator.Login.B1008,Emulator.Session,
  Emulator.Inventory.B1008,Emulator.Loot.B1008,Emulator.Skills.B1008;

{$I B1008UnitRates.inc}
{$I B1008PreInstances.inc}

procedure Check(B:Boolean;const Msg:string);
begin if not B then raise Exception.Create(Msg);end;
function LE(const P:TBytes;O:Integer):Cardinal;
begin Move(P[O],Result,4);end;
function CreateRequest:TBytes;
begin Result:=TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
  72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);end;
function Hero:TBytes;
begin Result:=TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(CreateRequest),1);end;
function AddPacket:TBytes;
begin
  // Live Power Strike slot 0, independent BE header + LE reference triplet.
  Result:=TBytes.Create(6,11,1,2,3,4,0,0,0,1,0,0,0,0,$E9,3,0,0,9,0,0,0,0,0,0,0);
end;
function DeletePacket:TBytes;
begin Result:=TBytes.Create(6,12,1,2,3,5,0,0,0,1,0,0,0,0);end;

procedure WireTests;
var P,Q,Before:TBytes;R:TB1008QuickSlotRequest;A:TArray<TB1008QuickSlot>;I:Integer;Failed:Boolean;
begin
  P:=AddPacket;R:=TB1008QuickSlotRequest.Parse(P);
  Check((R.Timestamp=$01020304) and (R.CharacterID=1) and not R.Remove and
    (R.Entry.ReferenceID=1001) and (R.Entry.Slot=0) and R.Entry.Supported,'Captured quickslot');
  for I:=0 to 25 do begin
    Failed:=False;try TB1008QuickSlotRequest.Parse(Copy(P,0,I));except on E:Exception do Failed:=True;end;
    Check(Failed,'Truncated add accepted');
  end;
  Q:=DeletePacket;R:=TB1008QuickSlotRequest.Parse(Q);
  Check(R.Remove and (R.Entry.Slot=0) and (R.Timestamp=$01020305),'Delete fields');
  for I:=0 to 13 do begin
    Failed:=False;try TB1008QuickSlotRequest.Parse(Copy(Q,0,I));except on E:Exception do Failed:=True;end;
    Check(Failed,'Truncated delete accepted');
  end;
  SetLength(A,2);A[0]:=TB1008QuickSlotRequest.Parse(P).Entry;A[1]:=A[0];A[1].Slot:=35;
  Q:=TB1008World.BuildCharacterInfoProbe(Hero,1);Before:=Copy(Q);
  TB1008QuickSlotWire.ApplyCharacterInfo(Q,A);
  Check((LE(Q,$19F)=1001) and (LE(Q,$1A3)=9) and (LE(Q,$1A7)=0) and
    (LE(Q,$19F+35*12)=1001),'Quickslot login offsets');
  for I:=0 to High(Q) do if (I<$19F) or (I>=$19F+432) then Check(Q[I]=Before[I],'CharInfo collateral change');
  for I:=$19F+12 to $19F+35*12-1 do Check(Q[I]=0,'Empty shortcut not cleared');
  Before:=Copy(Q);A[1].Slot:=0;Failed:=False;
  try TB1008QuickSlotWire.ApplyCharacterInfo(Q,A);except on E:Exception do Failed:=True;end;
  Check(Failed and CompareMem(@Q[0],@Before[0],Length(Q)),'Duplicate mutated packet');
  A[1].Slot:=36;Failed:=False;
  try TB1008QuickSlotWire.ApplyCharacterInfo(Q,A);except on E:Exception do Failed:=True;end;
  Check(Failed,'Out of range shortcut');
  A[1].Slot:=35;A[1].SourcePage:=-1;Check(not A[1].Supported,'Unsafe source page');
  TB1008QuickSlotWire.ApplyCharacterInfo(Q,nil);
  for I:=$19F to $19F+431 do Check(Q[I]=0,'Delete not restored');
end;

procedure StoreTests;
var L:TB1008LootStore;DB:TFDConnection;O,Other:TObject;G:TGUID;Dir,Path:string;
  R:TB1008QuickSlotRequest;A:TArray<TB1008QuickSlot>;N:Cardinal;Failed:Boolean;
begin
  CreateGUID(G);Dir:=TPath.Combine(TPath.GetTempPath,'KarosQuickSlots-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir);Path:=TPath.Combine(Dir,'hero.sqlite3');L:=nil;DB:=nil;
  O:=TObject.Create;Other:=TObject.Create;
  try
    L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Hero);L.CollectItem(O,'money',999999,123,N);
    L.RecordMobEXP(O,'level4',1000,1);FreeAndNil(L);
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;DB.Params.Values['DriverID']:='SQLite';
    DB.Params.Values['Database']:=Path;DB.Connected:=True;
    RestorePreInstanceSchema(DB);
    DB.ExecSQL('DROP TABLE quickslots');DB.ExecSQL('PRAGMA user_version=17');
    L:=TB1008LootStore.Create(Path,FixtureRates);Check(L.Acquire(O,Hero),'Migrated ownership');
    Check((Integer(DB.ExecSQLScalar('PRAGMA user_version'))=39) and
      (L.Balance(O)=123) and (L.SkillPoints(O)=3) and (Length(L.LearnedSkills(O))=1),
      'v17 migration changed inventory or skills');
    Check(Length(L.QuickSlots(O))=0,'Migration invented shortcut');R:=TB1008QuickSlotRequest.Parse(AddPacket);
    Failed:=False;try L.SetQuickSlot(Other,R);except on E:Exception do Failed:=True;end;
    Check(Failed,'Foreign owner write');
    Check(L.SetQuickSlot(O,R) and L.SetQuickSlot(O,R) and (Length(L.QuickSlots(O))=1),'Idempotent save');
    R.CharacterID:=2;Check(not L.SetQuickSlot(O,R),'Foreign actor');R.CharacterID:=1;
    R.Entry.ReferenceID:=5001;Check(not L.SetQuickSlot(O,R),'Unlearned skill');R.Entry.ReferenceID:=1001;
    R.Entry.SourceSlot:=1;Check(not L.SetQuickSlot(O,R),'Unknown reference');R.Entry.SourceSlot:=0;
    R.Entry.Slot:=36;Check(not L.SetQuickSlot(O,R),'Bad index');R.Entry.Slot:=35;
    R.Entry.SourcePage:=0;R.Entry.SourceSlot:=36;Check(not L.SetQuickSlot(O,R),'Bad hotbar source');
    R.Entry.SourceSlot:=0;Check(L.SetQuickSlot(O,R),'Hotbar-origin move');
    A:=L.QuickSlots(O);Check((A[1].SourcePage=9) and (A[1].SourceSlot=0),'Transient source not canonicalized');
    R.Entry.SourceSlot:=35;Check(L.SetQuickSlot(O,R),'Last source cell');
    R:=TB1008QuickSlotRequest.Parse(DeletePacket);
    Check(L.SetQuickSlot(O,R) and L.SetQuickSlot(O,R),'Idempotent remove');
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Hero);A:=L.QuickSlots(O);
    Check((Length(A)=1) and (A[0].Slot=35) and (A[0].ReferenceID=1001) and
      (L.Balance(O)=123) and (L.SkillPoints(O)=3),'Saved move or resources corrupted');
    DB.ExecSQL('CREATE TRIGGER fail_shortcut BEFORE INSERT ON quickslots BEGIN SELECT RAISE(ABORT,''test'');END');
    R:=TB1008QuickSlotRequest.Parse(AddPacket);Failed:=False;
    try L.SetQuickSlot(O,R);except on E:Exception do Failed:=True;end;
    A:=L.QuickSlots(O);Check(Failed and (Length(A)=1) and (A[0].Slot=35),'Failed save changed layout');
    DB.ExecSQL('DROP TRIGGER fail_shortcut');Check(L.SetQuickSlot(O,R),'Retry failed');
  finally L.Free;DB.Free;O.Free;Other.Free;TDirectory.Delete(Dir,True);end;
end;

procedure PotionStoreTests;
var L:TB1008LootStore;DB:TFDConnection;O:TObject;G:TGUID;Dir,Path:string;
  R:TB1008QuickSlotRequest;A:TArray<TB1008QuickSlot>;N:Cardinal;P:TBytes;
  Bag,Created:TB1008BagItem;HPCell,MPCell:Byte;Failed:Boolean;
begin
  CreateGUID(G);Dir:=TPath.Combine(TPath.GetTempPath,'KarosPotionSlots-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir);Path:=TPath.Combine(Dir,'hero.sqlite3');L:=nil;DB:=nil;O:=TObject.Create;
  try
    L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Hero);
    L.SetQuickSlot(O,TB1008QuickSlotRequest.Parse(AddPacket));FreeAndNil(L);
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;DB.Params.Values['DriverID']:='SQLite';
    DB.Params.Values['Database']:=Path;DB.Connected:=True;
    DB.ExecSQL('DROP TABLE quickslots');DB.ExecSQL('CREATE TABLE quickslots AS SELECT * FROM quickslots_v27_backup');
    RestorePreInstanceSchema(DB);
    DB.ExecSQL('INSERT INTO quickslots VALUES(0,1001,9,0)');DB.ExecSQL('PRAGMA user_version=27');
    L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Hero);Check(L.QuickSlots(O)[0].ReferenceID=1001,'v27 skill lost');
    L.CollectItem(O,'hp',54006,3,N);HPCell:=L.Item(O,54006).Slot;
    L.CollectItem(O,'mp',54206,3,N);MPCell:=L.Item(O,54206).Slot;
    // Exact live sentinel format, including the last legal bag cell.
    P:=AddPacket;P[13]:=4;FillChar(P[14],4,255);P[18]:=1;P[22]:=HPCell;
    R:=TB1008QuickSlotRequest.Parse(P);Check(R.Entry.Supported and L.SetQuickSlot(O,R),'Potion drag not saved');
    R.Entry.SourceSlot:=20;Check(not L.SetQuickSlot(O,R),'Out of bag link');
    R.Entry.SourceSlot:=19;Check(not L.SetQuickSlot(O,R),'Empty bag link');
    R.Entry.SourceSlot:=HPCell;R.Entry.ReferenceID:=54006;Check(not L.SetQuickSlot(O,R),'Item ID accepted as wire sentinel');
    Check(L.Swap(O,HPCell,19,54006,0),'Move saved potion');
    Check(L.Swap(O,MPCell,HPCell,54206,0),'Replace old cell with wrong potion');MPCell:=HPCell;HPCell:=19;
    R:=TB1008QuickSlotRequest.Parse(P);R.Entry.Slot:=5;R.Entry.SourcePage:=0;R.Entry.SourceSlot:=4;
    Check(L.SetQuickSlot(O,R),'Move potion on hotbar');R.Remove:=True;R.Entry.Slot:=4;L.SetQuickSlot(O,R);
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Hero);A:=L.QuickSlots(O);
    Check((Length(A)=2) and (A[1].Slot=5) and (A[1].ReferenceID=High(Cardinal)) and
      (A[1].SourcePage=1) and (A[1].SourceSlot=19),'Potion identity/reconnect restore');
    P:=TB1008World.BuildCharacterInfoProbe(Hero,1);TB1008QuickSlotWire.ApplyCharacterInfo(P,A);
    Check((LE(P,$19F+60)=High(Cardinal)) and (LE(P,$1A7+60)=19),'Potion login wire');
    Check(L.SplitItem(O,'split',19,54006,3,1,Bag,Created),'Split linked stack');
    Check(L.Consume(O,19,54006,N,10000) and (N=1),'First HP potion');
    Check(not L.Consume(O,Created.Slot,54006,N,10001),'Alternate stack bypassed cooldown');
    L.CollectItem(O,'stronger-hp',54004,1,N);
    Check(not L.Consume(O,L.Item(O,54004).Slot,54004,N,10002),'Different HP potion size bypassed shared cooldown');
    Check(L.Consume(O,MPCell,54206,N,10001),'HP blocked MP');
    Check((TB1008PotionEffect.CooldownMS(54006)=100) and
      (TB1008PotionEffect.CooldownMS(54206)=100),'Expected 100 ms HP/MP cooldown');
    Check(not L.Consume(O,19,54006,N,10099),'Cooldown expired early');
    Check(L.Consume(O,19,54006,N,10100) and (N=0),'Exact cooldown boundary');
    A:=L.QuickSlots(O);Check(A[1].SourceSlot=Created.Slot,'Depleted preferred stack did not resolve fallback');
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Hero);
    Check(not L.Consume(O,Created.Slot,54006,N,10101),'Reconnect reset cooldown');
    DB.ExecSQL('CREATE TRIGGER fail_potion BEFORE INSERT ON potion_cooldowns BEGIN SELECT RAISE(ABORT,''test'');END');
    Failed:=False;try L.Consume(O,Created.Slot,54006,N,11000);except on E:Exception do Failed:=True;end;
    Check(Failed and (L.Item(O,54006).Amount=1),'Failed cooldown write consumed item');
    DB.ExecSQL('DROP TRIGGER fail_potion');Check(L.Consume(O,Created.Slot,54006,N,11000),'Retry after rollback');
    Check(Length(L.QuickSlots(O))=1,'Exhausted potion points at unrelated cell');
    L.CollectItem(O,'refill',54006,1,N);A:=L.QuickSlots(O);
    Check((Length(A)=2) and (A[1].Slot=5),'Refilled potion preference lost');
    R.Remove:=True;R.Entry.Slot:=5;Check(L.SetQuickSlot(O,R),'Potion remove');
    Check(Length(L.QuickSlots(O))=1,'Potion removal lost skill');
  finally L.Free;DB.Free;O.Free;TDirectory.Delete(Dir,True);end;
end;

procedure OccupiedSkillSwapTests;
var L:TB1008LootStore;O:TObject;G:TGUID;Dir,Path:string;
  R:TB1008QuickSlotRequest;Learn:TB1008SkillLearn;
  A:TArray<TB1008QuickSlot>;P:TBytes;SP:Cardinal;
begin
  CreateGUID(G);Dir:=TPath.Combine(TPath.GetTempPath,'KarosSkillSwap-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir);Path:=TPath.Combine(Dir,'hero.sqlite3');L:=nil;O:=TObject.Create;
  try
    L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Hero);
    L.RecordMobEXP(O,'level4',1000,1);
    Learn:=TB1008SkillLearn.Parse(TBytes.Create(5,6,0,0,0,1,0,0,0,1,0,0,3,$EB,$1A));
    Check(L.LearnSkill(O,'body-blow',Learn)=slrApplied,'Swap fixture learn');
    R:=TB1008QuickSlotRequest.Parse(AddPacket);Check(L.SetQuickSlot(O,R),'Swap initial source');
    R.Entry.Slot:=35;R.Entry.ReferenceID:=1003;R.Entry.SourceSlot:=5;
    Check(L.SetQuickSlot(O,R),'Swap initial target');SP:=L.SkillPoints(O);
    // The authored native swap emits target add, then source add, with no delete.
    R.Entry.ReferenceID:=1001;R.Entry.SourceSlot:=0;
    Check(L.SetQuickSlot(O,R),'Occupied target add');
    R.Entry.Slot:=0;R.Entry.ReferenceID:=1003;R.Entry.SourceSlot:=5;
    Check(L.SetQuickSlot(O,R),'Displaced skill source add');
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Hero);A:=L.QuickSlots(O);
    Check((Length(A)=2) and (A[0].Slot=0) and (A[0].ReferenceID=1003) and
      (A[1].Slot=35) and (A[1].ReferenceID=1001) and (L.SkillPoints(O)=SP),
      'Occupied swap lost skill or changed SP after reopen');
    P:=TB1008World.BuildCharacterInfoProbe(Hero,1);TB1008QuickSlotWire.ApplyCharacterInfo(P,A);
    Check((LE(P,$19F)=1003) and (LE(P,$1A7)=5) and
      (LE(P,$19F+35*12)=1001) and (LE(P,$1A7+35*12)=0),'Cross-row swapped login layout');
  finally L.Free;O.Free;TDirectory.Delete(Dir,True);end;
end;

procedure SessionTests;
var S:TEmulatorSession;L:TB1008LootStore;C:TB1008CharacterStore;P:TBytes;Replies:TB1008Replies;
begin
  C:=TB1008CharacterStore.Create;L:=TB1008LootStore.Create('',FixtureRates);S:=nil;
  try
    C.CreateCharacter(CreateRequest,P);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);
    S.HandlePacket(AddPacket,Replies);Check(Length(Replies)=0,'Prelogin edit');
    S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),Replies);
    S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),Replies);
    Check(LE(Replies[0],$19F)=0,'Prelogin edit was stored');
    S.HandlePacket(TBytes.Create(4,0,0,0,0,2,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),Replies);
    S.HandlePacket(AddPacket,Replies);Check((Length(Replies)=0) and (Length(L.QuickSlots(S))=1),'Session save/unsafe echo');
    P:=AddPacket;P[13]:=3;P[18]:=0;
    S.HandlePacket(P,Replies);S.HandlePacket(DeletePacket,Replies);
    Check((Length(L.QuickSlots(S))=1) and (L.QuickSlots(S)[0].Slot=3),'Live move add/delete pair');
    FreeAndNil(S);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);
    S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),Replies);
    S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),Replies);
    Check((LE(Replies[0],$19F)=0) and (LE(Replies[0],$19F+36)=1001) and
      (LE(Replies[0],$1A3+36)=9),'Session moved shortcut restore');
    S.HandlePacket(TBytes.Create(4,0,0,0,0,2,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),Replies);
    P:=DeletePacket;P[13]:=3;
    S.HandlePacket(P,Replies);Check((Length(Replies)=0) and (Length(L.QuickSlots(S))=0),'Session delete');
  finally S.Free;L.Free;C.Free;end;
end;

begin
  try WireTests;StoreTests;PotionStoreTests;OccupiedSkillSwapTests;SessionTests;
    Writeln('PASS: skill/potion quickslots; v17/v27 migration; save/move/delete/replay; potion identity/stack fallback; shared cooldown boundary/reconnect/rollback; CharInfo restoration');
  except on E:Exception do begin Writeln('FAIL: ',E.ClassName,': ',E.Message);ExitCode:=1;end;end;
end.
