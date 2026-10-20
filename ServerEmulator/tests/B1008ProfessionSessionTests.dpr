program B1008ProfessionSessionTests;
{$APPTYPE CONSOLE}
{$B-}

uses Emulator.Rates.B1008,System.SysUtils,System.IOUtils,Winapi.Windows,
  FireDAC.Comp.Client,Emulator.Character.B1008,Emulator.Login.B1008,
  Emulator.LootStore.B1008,Emulator.Loot.B1008,Emulator.Skills.B1008,
  Emulator.Profession.B1008,Emulator.ProfessionSkills.B1008,
  Emulator.QuickSlots.B1008,Emulator.Equipment.B1008,Emulator.Protocol.B1008,
  Emulator.Session,Emulator.World.B1008,Emulator.Combat.B1008,
  Emulator.Balance.B1008,Emulator.QuestState.B1008,Emulator.DropProfile.B1008,
  Emulator.MonsterBalance.B1008,Emulator.Berneo.B1008,Emulator.Items.B1008,
  Emulator.Runtime,Emulator.Content,Emulator.Repository,Emulator.Repository.SQLite;

{$I B1008UnitRates.inc}
{$I B1008PreInstances.inc}

procedure Check(B:Boolean;const Msg:string);
begin if not B then raise Exception.Create(Msg);end;
procedure BE(var P:TBytes;O:Integer;V:Cardinal);
begin P[O]:=Byte(V shr 24);P[O+1]:=Byte(V shr 16);P[O+2]:=Byte(V shr 8);P[O+3]:=Byte(V);end;
function LE(const P:TBytes;O:Integer):Cardinal;
begin Move(P[O],Result,4);end;
procedure PutFloat(var P:TBytes;O:Integer;V:Single);
begin Move(V,P[O],4);end;
function CreateRequest:TBytes;
begin
  Result:=TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
    72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);
end;
function Learn(ID:Cardinal):TB1008SkillLearn;
begin
  Result:=Default(TB1008SkillLearn);Result.CharacterID:=1;
  Result.SkillID:=ID;Result.Code:=$1A;
end;
function Upgrade(ID,Rank:Cardinal):TB1008SkillUpgrade;
begin
  Result:=Default(TB1008SkillUpgrade);Result.CharacterID:=1;
  Result.SkillID:=ID;Result.CurrentRank:=Rank;Result.Code:=$1A;
end;
procedure Promote(L:TB1008LootStore;Owner:TObject;ClassID:Word);
var R:TB1008ClassChange;State:TB1008ClassState;Updated:TArray<TB1008BagItem>;N:Cardinal;
begin
  Check(L.CollectItem(Owner,'class-money',999999,10000,N),'Promotion money');
  Check(L.CollectItem(Owner,'class-certificate',63007,1,N),'Promotion certificate');
  R:=Default(TB1008ClassChange);R.CharacterID:=1;R.TargetClass:=ClassID;R.Code:=$81;
  Check(L.ChangeClass(Owner,'first-profession',R,State,Updated)=$81,'Promotion');
end;
function OpenDB(const Path:string):TFDConnection;
begin
  Result:=TFDConnection.Create(nil);Result.LoginPrompt:=False;
  Result.Params.Values['DriverID']:='SQLite';Result.Params.Values['Database']:=Path;
  Result.Connected:=True;
end;
function NewDirectory:string;
var G:TGUID;
begin
  CreateGUID(G);Result:=TPath.Combine(TPath.GetTempPath,'KarosProfession-'+GUIDToString(G));
  TDirectory.CreateDirectory(Result);
end;

procedure SeedSkill(L:TB1008LootStore;Owner:TObject;ID:Cardinal);
var T:TB1008SkillTraining;S:TB1008LearnedSkill;I:Integer;
begin
  for S in L.LearnedSkills(Owner) do if S.ID=ID then Exit;
  T:=TB1008SkillTraining.Get(ID,1);
  for I:=0 to T.PrerequisiteCount-1 do if T.PrerequisiteRanks[I]>0 then
    SeedSkill(L,Owner,T.PrerequisiteIDs[I]);
  Check(L.LearnSkill(Owner,'seed-'+UIntToStr(ID),Learn(ID))=slrApplied,'Fixture learn '+UIntToStr(ID));
end;

procedure BranchStorageTests(ClassID:Word;ReversePrerequisites:Boolean);
var Dir,Path:string;L:TB1008LootStore;Owner:TObject;Preview:TBytes;
  BaseID,AreaID,FirstID,SecondID,ID,OtherID,R:Cardinal;I,BeforeSP,AfterSP,Count:Integer;
  Q:TB1008QuickSlotRequest;Skill:TB1008LearnedSkill;Entry:TB1008QuickSlot;Found:Boolean;
begin
  Dir:=NewDirectory;Path:=TPath.Combine(Dir,'branch.sqlite3');L:=nil;Owner:=TObject.Create;
  try
    Preview:=TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(CreateRequest),1);
    L:=TB1008LootStore.Create(Path,FixtureRates);Check(L.Acquire(Owner,Preview),'Branch fixture owner');
    L.GrantTestProgress(Owner,'cap30',30,60);Promote(L,Owner,ClassID);
    for I:=1002 to 1006 do SeedSkill(L,Owner,I);
    if ClassID=110 then begin BaseID:=1101;AreaID:=1106;FirstID:=1104;SecondID:=1103;end
    else begin BaseID:=1901;AreaID:=1906;FirstID:=1903;SecondID:=1904;end;
    if ReversePrerequisites then begin ID:=FirstID;FirstID:=SecondID;SecondID:=ID;end;
    BeforeSP:=L.SkillPoints(Owner);
    Check(L.LearnSkill(Owner,'none',Learn(AreaID))=slrRejected,'Area learned with neither prerequisite');
    SeedSkill(L,Owner,FirstID);
    if FirstID=1104 then begin
      Found:=False;for Skill in L.LearnedSkills(Owner) do if Skill.ID=1101 then Found:=True;
      Check(not Found,'Thunder rank-zero prerequisite manufactured Blade Crash');
    end;
    Check((L.LearnSkill(Owner,'one-only',Learn(AreaID))=slrRejected) and
      (Integer(L.SkillPoints(Owner))=BeforeSP-1),'Area accepted only one of two prerequisites');
    SeedSkill(L,Owner,SecondID);SeedSkill(L,Owner,AreaID);
    Check(Integer(L.SkillPoints(Owner))=BeforeSP-3,'Both prerequisites/area did not cost one SP each');
    if ReversePrerequisites then Exit;
    for I:=0 to 6 do begin
      ID:=BaseID+Cardinal(I);SeedSkill(L,Owner,ID);
      BeforeSP:=L.SkillPoints(Owner);
      Check((L.LearnSkill(Owner,'replay-'+UIntToStr(ID),Learn(ID))=slrAlreadyKnown) and
        (Integer(L.SkillPoints(Owner))=BeforeSP),'Branch acquisition replay charged SP');
      OtherID:=ID+800;if ClassID=120 then OtherID:=ID-800;
      Check((L.LearnSkill(Owner,'foreign-'+UIntToStr(ID),Learn(OtherID))=slrRejected) and
        (Integer(L.SkillPoints(Owner))=BeforeSP),'Opposite profession skill learned');
      Q:=Default(TB1008QuickSlotRequest);Q.CharacterID:=1;Q.Entry.Slot:=10+I;
      Q.Entry.ReferenceID:=ID;Q.Entry.SourcePage:=9;
      Q.Entry.SourceSlot:=TB1008QuickSlotWire.SkillSourceSlot(ID,ClassID);
      if TB1008ProfessionSkill.IsPassive(ID) then
        Check(not L.SetQuickSlot(Owner,Q),'Passive profession shortcut accepted')
      else Check(L.SetQuickSlot(Owner,Q),'Branch active shortcut refused');
      if (ID=AreaID) or (ID=BaseID+6) then
        Check(L.UpgradeSkill(Owner,'cap-'+UIntToStr(ID),Upgrade(ID,1),R)=surRejected,
          'Level30 bypassed future active rank requirement');
    end;
    AfterSP:=L.SkillPoints(Owner);Count:=0;
    for Skill in L.LearnedSkills(Owner) do if TB1008ProfessionSkill.Allowed(Skill.ID,ClassID) then begin
      Inc(Count);Check(Skill.Rank=1,'Unexpected branch rank');
    end;
    Check((Count=7) and (Length(L.QuickSlots(Owner))=6),'Incomplete branch skill/active shortcut set');
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,FixtureRates);Check(L.Acquire(Owner,Preview),'Branch reopen');
    Check((Integer(L.SkillPoints(Owner))=AfterSP) and (L.ClassState(Owner).ClassID=ClassID),
      'Branch reopen changed SP/profession');
    for I:=0 to 6 do begin
      ID:=BaseID+Cardinal(I);Found:=False;
      for Skill in L.LearnedSkills(Owner) do if Skill.ID=ID then Found:=Skill.Rank=1;
      Check(Found,'Branch rank missing after reopen');
      if TB1008ProfessionSkill.IsPassive(ID) then Continue;Found:=False;
      for Entry in L.QuickSlots(Owner) do if Entry.ReferenceID=ID then
        Found:=(Entry.Slot=Cardinal(10+I)) and (Entry.SourcePage=9) and
          (Entry.SourceSlot=TB1008QuickSlotWire.SkillSourceSlot(ID,ClassID));
      Check(Found,'Branch active shortcut missing/corrupted after reopen');
    end;
  finally L.Free;Owner.Free;TDirectory.Delete(Dir,True);end;
end;

procedure StorageTests;
var Dir,Path:string;L:TB1008LootStore;DB:TFDConnection;Owner:TObject;
  Preview:TBytes;R:Cardinal;Q:TB1008QuickSlotRequest;BeforeSP,Spent,I:Integer;
  BeforeEXP:Int64;Found:Boolean;Skill:TB1008LearnedSkill;Entry:TB1008QuickSlot;
begin
  Dir:=NewDirectory;Path:=TPath.Combine(Dir,'loot.sqlite3');
  Owner:=TObject.Create;L:=nil;DB:=nil;
  try
    Preview:=TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(CreateRequest),1);
    L:=TB1008LootStore.Create(Path,FixtureRates);Check(L.Acquire(Owner,Preview),'Store owner');
    L.GrantTestProgress(Owner,'level10',10,30);
    Check(L.LearnSkill(Owner,'base-class-denied',Learn(1101))=slrRejected,'Base class learned profession skill');
    Check(L.UpgradeSkill(Owner,'power2',Upgrade(1001,1),R)=surApplied,'Seed base rank');
    Check(L.LearnSkill(Owner,'frenzy',Learn(1004))=slrApplied,'Seed acquisition receipt');
    Check(L.CollectItem(Owner,'unrelated',80008,17,R),'Unrelated inventory');
    Q:=Default(TB1008QuickSlotRequest);Q.CharacterID:=1;Q.Entry.Slot:=3;
    Q.Entry.ReferenceID:=1001;Q.Entry.SourcePage:=9;Q.Entry.SourceSlot:=0;
    Check(L.SetQuickSlot(Owner,Q),'Seed base quickslot');
    Promote(L,Owner,110);BeforeSP:=L.SkillPoints(Owner);BeforeEXP:=L.Progress(Owner).TotalEXP;
    FreeAndNil(L);DB:=OpenDB(Path);
    // A closed, isolated v35 fixture: old rows and receipts precede widening.
    DB.ExecSQL('DROP TABLE learned_skills_v35_backup');
    DB.ExecSQL('DROP TABLE skill_acquisitions_v35_backup');
    DB.ExecSQL('DROP TABLE skill_upgrades_v35_backup');
    RestorePreInstanceSchema(DB);
    DB.ExecSQL('PRAGMA user_version=35');DB.Connected:=False;
    L:=TB1008LootStore.Create(Path,FixtureRates);Check(L.Acquire(Owner,Preview),'Migrated owner');
    DB.Connected:=True;
    Check(Integer(DB.ExecSQLScalar('PRAGMA user_version'))=39,'v35 migration version');
    Check((L.ClassState(Owner).ClassID=110) and (L.Progress(Owner).TotalEXP=BeforeEXP) and
      (Integer(L.SkillPoints(Owner))=BeforeSP) and (L.Item(Owner,80008).Amount=17),
      'Migration changed profession, progress, SP or inventory');
    Check(Integer(DB.ExecSQLScalar('SELECT COUNT(*) FROM learned_skills_v35_backup'))=2,
      'Migration omitted learned-skill recovery copy');
    Check((L.LearnedSkills(Owner)[0].Rank=2) and (Length(L.Equipment(Owner))=5),
      'Migration lost base rank or equipment');
    Check(L.UpgradeSkill(Owner,'power2',Upgrade(1001,1),R)=surDuplicate,'Migration lost upgrade receipt');
    Check(L.LearnSkill(Owner,'frenzy',Learn(1004))=slrAlreadyKnown,'Migration lost acquisition');
    Check((Integer(L.SkillPoints(Owner))=BeforeSP) and (Length(L.QuickSlots(Owner))>=1),
      'Migration replay spent SP or dropped quickslot');
    Check(L.LearnSkill(Owner,'missing-prerequisite',Learn(1101))=slrRejected,'Missing Provocation allowed');
    Check(L.LearnSkill(Owner,'wrong-branch',Learn(1901))=slrRejected,'Wrong profession allowed');
    Q.Entry.Slot:=7;Q.Entry.ReferenceID:=1101;Q.Entry.SourcePage:=9;Q.Entry.SourceSlot:=5;
    Check(not L.SetQuickSlot(Owner,Q),'Unlearned profession quickslot accepted');
    Check(L.LearnSkill(Owner,'provocation',Learn(1005))=slrApplied,'Profession lost base skills');
    Spent:=Integer(DB.ExecSQLScalar('SELECT spent FROM skill_points WHERE id=1'));
    DB.ExecSQL('UPDATE skill_points SET spent=earned+bonus WHERE id=1');
    Check(L.LearnSkill(Owner,'no-sp',Learn(1101))=slrRejected,'No-SP learn accepted');
    DB.ExecSQL('UPDATE skill_points SET spent=:n WHERE id=1',[Spent]);
    BeforeSP:=L.SkillPoints(Owner);
    Check(L.LearnSkill(Owner,'blade',Learn(1101))=slrApplied,'Blade Crash learn');
    Check((Integer(L.SkillPoints(Owner))=BeforeSP-1) and
      (L.LearnSkill(Owner,'blade',Learn(1101))=slrAlreadyKnown) and
      (Integer(L.SkillPoints(Owner))=BeforeSP-1),'Learn replay or cost');
    Check(L.SetQuickSlot(Owner,Q),'Learned Blade Crash quickslot');
    Q.Entry.Slot:=8;Q.Entry.SourcePage:=0;Q.Entry.SourceSlot:=7;
    Check(L.SetQuickSlot(Owner,Q),'Profession quickslot move');
    Check(L.UpgradeSkill(Owner,'too-young',Upgrade(1101,1),R)=surRejected,'Rank level bypass');
    for I:=1 to 4 do begin
      L.GrantTestProgress(Owner,'before-rank-'+IntToStr(I),9+4*I,30);
      Check(L.UpgradeSkill(Owner,'early-'+IntToStr(I),Upgrade(1101,I),R)=surRejected,
        'Rank granted one level early');
      L.GrantTestProgress(Owner,'rank-level-'+IntToStr(I),10+4*I,30);
      Check((L.UpgradeSkill(Owner,'rank-'+IntToStr(I),Upgrade(1101,I),R)=surApplied) and
        (R=Cardinal(I+1)) and (L.SkillPoints(Owner)=29),'Rank boundary or cost');
      Check((L.UpgradeSkill(Owner,'rank-'+IntToStr(I),Upgrade(1101,I),R)=surDuplicate) and
        (L.SkillPoints(Owner)=29),'Rank replay spent twice');
    end;
    Check(L.UpgradeSkill(Owner,'rank6',Upgrade(1101,5),R)=surRejected,'Rank six accepted');
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,FixtureRates);
    Check(L.Acquire(Owner,Preview),'Profession reopen');Found:=False;
    for Skill in L.LearnedSkills(Owner) do if Skill.ID=1101 then Found:=Skill.Rank=5;
    Check(Found and (L.SkillPoints(Owner)=29) and (L.ClassState(Owner).ClassID=110),
      'Profession ranks/SP lost on reopen');
    Found:=False;
    for Entry in L.QuickSlots(Owner) do
      if Entry.Slot=3 then Found:=(Entry.ReferenceID=1001) and (Entry.SourcePage=9);
    Check(Found,'Base quickslot lost on profession reopen');
    Found:=False;
    for Entry in L.QuickSlots(Owner) do
      if Entry.Slot=8 then Found:=(Entry.ReferenceID=1101) and
        (Entry.SourcePage=9) and (Entry.SourceSlot=5);
    Check(Found,'Moved profession quickslot lost canonical reference on reopen');
  finally L.Free;DB.Free;Owner.Free;TDirectory.Delete(Dir,True);end;
end;

function Ready(Timestamp,SkillID:Cardinal):TBytes;
begin
  Result:=nil;SetLength(Result,41);Result[0]:=5;Result[1]:=3;
  BE(Result,2,Timestamp);BE(Result,7,1);BE(Result,11,SkillID);BE(Result,15,1);
  PutFloat(Result,19,8674.279);PutFloat(Result,23,6660.197);PutFloat(Result,27,607.879);PutFloat(Result,31,1);
  Result[35]:=1;BE(Result,36,120);Result[40]:=$1A;
end;
function Action(Timestamp,SkillID:Cardinal):TBytes;
begin
  Result:=nil;SetLength(Result,53);Result[0]:=5;BE(Result,2,Timestamp);
  BE(Result,7,1);Result[11]:=1;BE(Result,12,TB1008ProfessionSkill.Get(SkillID,1).ActionID);
  PutFloat(Result,16,8674.279);PutFloat(Result,20,6660.197);PutFloat(Result,24,607.879);PutFloat(Result,28,1);
  Result[32]:=1;BE(Result,33,120);PutFloat(Result,37,8669.776367);
  PutFloat(Result,41,6668.010254);PutFloat(Result,45,607.174);
end;
function Impact(Timestamp,SkillID:Cardinal):TBytes;
begin
  Result:=Copy(Action(Timestamp,SkillID),0,38);Result[1]:=1;
  Result[33]:=1;BE(Result,34,120);BE(Result,12,SkillID);
end;
function BleedEffects(const Replies:TB1008Replies;Add:Boolean):Integer;
var P:TBytes;
begin
  Result:=0;
  for P in Replies do if (Length(P)=26) and (P[0]=5) and (P[1]=9) and
    (TB1008Wire.ReadBE32(P,14)=1901) then begin
    Check((P[6]=1) and (TB1008Wire.ReadBE32(P,7)=120) and
      (TB1008Wire.ReadBE32(P,18)=1),'Wind effect wrong target/rank');
    if P[11]=Ord(Add) then Inc(Result);
  end;
end;
function DamagePackets(const Replies:TB1008Replies;SkillID:Cardinal;ExpectedDamage:Integer=-1):Integer;
var P:TBytes;
begin
  Result:=0;
  for P in Replies do if (Length(P)=47) and (P[0]=5) and (P[1]=2) and
    (P[6]=0) and (TB1008Wire.ReadBE32(P,12)=SkillID) and (LE(P,18)=120) then begin
    if ExpectedDamage>=0 then Check(LE(P,23)=Cardinal(ExpectedDamage),'Unexpected periodic damage');
    Inc(Result);
  end;
end;
function DropPackets(const Replies:TB1008Replies):Integer;
var P:TBytes;
begin
  Result:=0;
  for P in Replies do if (Length(P)=74) and (P[0]=6) and (P[1]=4) then Inc(Result);
end;

type TFixture=class
  Dir:string;
  C:TB1008CharacterStore;
  L:TB1008LootStore;
  Q:TB1008QuestStore;
  S:TEmulatorSession;
  Runtime:TEmulatorRuntimeManager;
  Repo:IEmulatorContentRepository;
  DB:TFDConnection;
  Mob:TEmulatorMobDefinition;
  constructor Create(ClassID:Word;SkillID:Cardinal;CorrectWeapon:Boolean;HP:Integer;Level:Word=10);
  destructor Destroy;override;
  procedure SetMobHP(HP:Integer);
end;

constructor TFixture.Create(ClassID:Word;SkillID:Cardinal;CorrectWeapon:Boolean;HP:Integer;Level:Word);
var P:TBytes;Replies:TB1008Replies;Note:string;N:Cardinal;E:TB1008EquipmentRequest;Bag:TB1008BagItem;
  Secondary:TEmulatorMobDefinition;Spawn,OriginalSpawn:TEmulatorSpawnDefinition;
begin
  inherited Create;Dir:=NewDirectory;
  Repo:=TSQLiteContentRepository.Create(TPath.Combine(Dir,'content.sqlite3'));
  Runtime:=TEmulatorRuntimeManager.Create(Repo,'b1008');Check(Runtime.Reload(Note),'Fixture runtime: '+Note);
  Check(Runtime.AcquireSnapshot.TryGetMob(120,Mob),'Fixture spider');
  Mob.AttackDamage:=1;Mob.AttackMin:=0;Mob.PhysicalDefense:=0;Mob.Aggressive:=False;
  SetMobHP(HP);
  if (SkillID<>1101) and (SkillID<>1901) then begin
    Mob.PatrolRadius:=0;Repo.PublishMob(Mob);
    Secondary:=Default(TEmulatorMobDefinition);
    for OriginalSpawn in Runtime.AcquireSnapshot.GetSpawns do if OriginalSpawn.EntityHandle=119 then
      Check(Runtime.AcquireSnapshot.TryGetMob(OriginalSpawn.MobID,Secondary),'Fixture secondary mob');
    Check(Secondary.MobID<>0,'Fixture secondary spawn');
    Secondary.MaxHP:=HP;Secondary.AttackDamage:=1;Secondary.AttackMin:=0;
    Secondary.PhysicalDefense:=0;Secondary.Aggressive:=False;Secondary.PatrolRadius:=0;
    Repo.PublishMob(Secondary);
    for OriginalSpawn in Runtime.AcquireSnapshot.GetSpawns do if (OriginalSpawn.EntityHandle=120) or
      (OriginalSpawn.EntityHandle=119) then begin
      Spawn:=OriginalSpawn;
      Spawn.X:=8674.279;Spawn.Z:=6660.197;Spawn.Y:=607.879;Spawn.SpawnRadius:=0;
      if Spawn.EntityHandle=119 then begin Spawn.X:=Spawn.X+200;Spawn.Z:=Spawn.Z+3;end;
      Repo.PublishSpawn(Spawn);
    end;
    Check(Runtime.Reload(Note),'New-skill deterministic content fixture: '+Note);
  end;
  C:=TB1008CharacterStore.Create;L:=TB1008LootStore.Create(TPath.Combine(Dir,'loot.sqlite3'),FixtureRates);
  Q:=TB1008QuestStore.Create;C.CreateCharacter(CreateRequest,P);
  Check(L.Acquire(C,P),'Fixture store owner');L.GrantTestProgress(C,'fixture-level',Level,30);
  Promote(L,C,ClassID);
  Check(L.LearnSkill(C,'provocation',Learn(1005))=slrApplied,'Fixture prerequisite');
  SeedSkill(L,C,SkillID);
  if ((ClassID=120) and CorrectWeapon) or ((ClassID=110) and not CorrectWeapon) then begin
    Check(L.CollectItem(C,'polearm',3001,1,N),'Fixture polearm');
    E:=Default(TB1008EquipmentRequest);E.Wear:=True;E.CharacterID:=1;E.Page:=1;
    E.EquipSlot:=255;E.ItemID:=3001;E.Slot:=L.Item(C,3001).Slot;
    Check(L.TransferEquipment(C,'equip-polearm',100,E,Bag),'Fixture polearm equip');
  end;
  L.Release(C);Check(Q.Acquire(C,P),'Fixture quest owner');Check(Q.Accept(C),'Fixture quest');Q.Release(C);
  S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,Q,Runtime,L,42,42,42);
  S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),Replies);
  S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),Replies);
  P:=TBytes.Create(4,0,0,0,0,2,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
  PutFloat(P,11,8674.279);PutFloat(P,15,6660.197);PutFloat(P,19,607.879);S.HandlePacket(P,Replies);
  P:=TB1008World.BuildActorMovement(3,0,2,1,8674.279,6660.197,607.879,8674.279,6660.197,607.879,1);
  S.HandlePacket(P,Replies);DB:=OpenDB(TPath.Combine(Dir,'loot.sqlite3'));
end;
procedure TFixture.SetMobHP(HP:Integer);
var Note:string;
begin
  Mob.MaxHP:=HP;Repo.PublishMob(Mob);Check(Runtime.Reload(Note),'Fixture HP publication: '+Note);
end;
destructor TFixture.Destroy;
begin
  S.Free;DB.Free;L.Free;Q.Free;C.Free;Runtime.Free;Repo:=nil;
  if Dir<>'' then TDirectory.Delete(Dir,True);
  inherited;
end;

function ProfessionReady(Stamp,ID:Cardinal):TBytes;
begin
  Result:=Ready(Stamp,ID);
  if TB1008ProfessionSkill.IsSelf(ID) then begin Result[35]:=0;BE(Result,36,1);end;
end;
function ProfessionAction(Stamp,ID:Cardinal):TBytes;
begin
  Result:=Action(Stamp,ID);
  if TB1008ProfessionSkill.IsSelf(ID) then BE(Result,33,1);
end;
function ProfessionImpact(Stamp,ID:Cardinal;const Targets:array of Cardinal;SelfTarget:Boolean=False):TBytes;
var I:Integer;
begin
  Result:=Copy(ProfessionAction(Stamp,ID),0,33);SetLength(Result,33+5*Length(Targets));
  Result[1]:=1;BE(Result,12,ID);Result[32]:=Length(Targets);
  for I:=0 to High(Targets) do begin
    Result[33+I*5]:=Ord(not SelfTarget);BE(Result,34+I*5,Targets[I]);
  end;
end;
function EffectPackets(const Replies:TB1008Replies;ID,Actor:Cardinal;Kind:Byte;Add:Boolean):Integer;
var P:TBytes;
begin
  Result:=0;
  for P in Replies do if (Length(P)=26) and (P[0]=5) and (P[1]=9) and
    (TB1008Wire.ReadBE32(P,14)=ID) and (TB1008Wire.ReadBE32(P,7)=Actor) and
    (P[6]=Kind) and (P[11]=Ord(Add)) then begin
    Check(TB1008Wire.ReadBE32(P,18)=1,'Profession effect lost rank');Inc(Result);
  end;
end;
function TargetDamage(const Replies:TB1008Replies;ID,Target:Cardinal;out Total:Integer):Integer;
var P:TBytes;
begin
  Result:=0;Total:=0;
  for P in Replies do if (Length(P)=47) and (P[0]=5) and (P[1]=2) and (P[6]=0) and
    (TB1008Wire.ReadBE32(P,12)=ID) and (LE(P,18)=Target) then begin
    Inc(Result);Inc(Total,Integer(LE(P,23)));
  end;
end;
function TargetHP(const Replies:TB1008Replies;Target:Cardinal):Integer;
var P:TBytes;
begin
  Result:=-1;
  for P in Replies do if (Length(P)=49) and (P[0]=8) and (P[1]=0) and (P[6]=1) and
    (TB1008Wire.ReadBE32(P,7)=Target) then Result:=LE(P,11);
end;
function ParameterValue(const Replies:TB1008Replies;Offset:Integer):Single;
var P:TBytes;Found:Boolean;
begin
  Found:=False;Result:=0;
  for P in Replies do if (Length(P)>=Offset+4) and (P[0]=8) and (P[1]=2) then begin
    Move(P[Offset],Result,4);Found:=True;
  end;
  Check(Found,'Profession buff omitted parameter refresh');
end;
function ParameterAttack(const Replies:TB1008Replies):Single;
begin Result:=ParameterValue(Replies,90);end;
procedure FinishProfession(F:TFixture;var Stamp:Cardinal;ID:Cardinal);
var P:TBytes;Replies:TB1008Replies;Note:string;
begin
  Inc(Stamp);P:=ProfessionAction(Stamp,ID);P[11]:=5;
  Note:=F.S.HandlePacket(P,Replies);
  Check((Pos('END ACCEPTED',Note)>0) and (Length(Replies)=1) and (Replies[0][11]=5),
    'Profession native finish: '+Note);
end;
procedure ReenterFixture(F:TFixture;Stamp:Cardinal;out Replies:TB1008Replies);
var P:TBytes;Note:string;
begin
  P:=nil;SetLength(P,342);P[0]:=2;P[1]:=1;P[6]:=1;BE(P,2,Stamp);
  Note:=F.S.HandlePacket(P,Replies);
  Check((Pos('CHARACTER SELECT |',Note)>0) and not F.S.WorldState.Active,'Fixture selection: '+Note);
  F.S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),Replies);
  P:=TBytes.Create(4,0,0,0,0,2,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
  PutFloat(P,11,8674.279);PutFloat(P,15,6660.197);PutFloat(P,19,607.879);
  F.S.HandlePacket(P,Replies);Check(F.S.WorldState.Active,'Fixture reentry did not restore world');
end;

procedure SelfBuffSessionTests(ClassID:Word;Cleanup:Boolean);
var F:TFixture;RevengeID,DeathID,Stamp:Cardinal;P:TBytes;Replies:TB1008Replies;Note:string;
  BeforeTick,AfterTick:UInt64;BaselineAttack,BuffedAttack,FrenzyDefense:Single;
  Frenzy:TB1008FrenzyRank;Base:TB1008BaseAttributes;DeathDefensePenalty:Integer;
  procedure CastFrenzy;
  var A,D:TBytes;
  begin
    Inc(Stamp);P:=Ready(Stamp,1004);P[35]:=0;BE(P,36,1);
    Note:=F.S.HandlePacket(P,Replies);Check(Pos('READY ACCEPTED',Note)>0,'Frenzy collision fixture ready: '+Note);
    Inc(Stamp);A:=ProfessionAction(Stamp,RevengeID);BE(A,12,B1008FrenzyActionID);
    Note:=F.S.HandlePacket(A,Replies);Check(Pos('START ACCEPTED',Note)>0,'Frenzy collision fixture start: '+Note);
    Inc(Stamp);D:=Copy(A,0,38);D[1]:=1;D[32]:=1;D[33]:=0;BE(D,34,1);BE(D,12,1004);BE(D,2,Stamp);
    Note:=F.S.HandlePacket(D,Replies);Check(Pos('FRENZY APPLIED',Note)>0,'Frenzy collision fixture impact: '+Note);
    FrenzyDefense:=ParameterValue(Replies,102);
    Inc(Stamp);BE(A,2,Stamp);A[11]:=5;Note:=F.S.HandlePacket(A,Replies);
    Check(Pos('END ACCEPTED',Note)>0,'Frenzy collision fixture finish: '+Note);
  end;
  procedure CastBuff(ID:Cardinal);
  var A,D:TBytes;
  begin
    Inc(Stamp);Note:=F.S.HandlePacket(ProfessionReady(Stamp,ID),Replies);
    Check(Pos('READY ACCEPTED',Note)>0,'Self buff ready: '+Note);
    Inc(Stamp);A:=ProfessionAction(Stamp,ID);Note:=F.S.HandlePacket(A,Replies);
    Check((Pos('START ACCEPTED',Note)>0) and (Length(Replies)=2) and (Replies[0][32]=0) and
      (TB1008Wire.ReadBE32(Replies[0],33)=1),'Self buff canonical start/1019: '+Note);
    F.S.HandlePacket(A,Replies);Check(Length(Replies)=0,'Self buff action replay');
    Inc(Stamp);D:=ProfessionImpact(Stamp,ID,[1],True);Note:=F.S.HandlePacket(D,Replies);
    Check((Pos('BUFF APPLIED',Note)>0) and (EffectPackets(Replies,ID,1,0,True)=1),
      'Self buff native impact: '+Note);
    if ID=RevengeID then BaselineAttack:=ParameterAttack(Replies)
    else begin
      BuffedAttack:=ParameterAttack(Replies);
      Check(Abs(BuffedAttack-BaselineAttack-(Base.PhysicalAttack*20+50) div 100)<0.001,
        'Death Leap changed authored percent-of-base attack formula');
      Check(Abs(ParameterValue(Replies,102)-FrenzyDefense+DeathDefensePenalty)<0.001,
        'Death Leap defense penalty did not use remaining defense after Frenzy');
    end;
    F.S.HandlePacket(D,Replies);Check(Length(Replies)=0,'Self buff impact replay');
    FinishProfession(F,Stamp,ID);
  end;
begin
  if ClassID=110 then begin RevengeID:=1105;DeathID:=1107;end
  else begin RevengeID:=1905;DeathID:=1907;end;
  F:=TFixture.Create(ClassID,RevengeID,True,10000,30);
  try
    Stamp:=400;SeedSkill(F.L,F.S,DeathID);BeforeTick:=GetTickCount64;
    Frenzy:=TB1008FrenzyRank.Get(1);Base:=TB1008Balance.ProfessionAttributes(100,ClassID,0,30);
    DeathDefensePenalty:=((TB1008Balance.ProfessionPhysicalDefense(ClassID,
      Base.PhysicalDefense+TB1008Equipment.Defense(F.L.Equipment(F.S)))-
      Frenzy.DefensePenalty)*30+50) div 100;
    CastFrenzy;
    CastBuff(RevengeID);CastBuff(DeathID);AfterTick:=GetTickCount64;
    if Cleanup then begin
      ReenterFixture(F,Stamp+10,Replies);
      Check((EffectPackets(Replies,RevengeID,1,0,True)=0) and
        (EffectPackets(Replies,DeathID,1,0,True)=0),'Scene reload restored transient buffs');
      F.S.PollWorld(AfterTick+31000,Replies);
      Check((EffectPackets(Replies,RevengeID,1,0,False)=0) and
        (EffectPackets(Replies,DeathID,1,0,False)=0),'Scene reload retained old buff deadlines');Exit;
    end;
    F.S.PollWorld(BeforeTick+19999,Replies);
    Check((EffectPackets(Replies,RevengeID,1,0,False)=0) and
      (EffectPackets(Replies,DeathID,1,0,False)=0),'Independent buffs expired early');
    F.S.PollWorld(AfterTick+20000,Replies);
    Check((EffectPackets(Replies,DeathID,1,0,False)=1) and
      (EffectPackets(Replies,RevengeID,1,0,False)=0) and
      (Abs(ParameterAttack(Replies)-BaselineAttack+Frenzy.AttackBonus)<0.001),
      'Death Leap expiry removed Revenge or retained expired Frenzy/attack bonus');
    F.S.PollWorld(AfterTick+20000,Replies);
    Check(EffectPackets(Replies,DeathID,1,0,False)=0,'Death Leap removal replay');
    F.S.PollWorld(AfterTick+30000,Replies);
    Check(EffectPackets(Replies,RevengeID,1,0,False)=1,'Revenge independent expiry');
    F.S.PollWorld(AfterTick+30000,Replies);
    Check(EffectPackets(Replies,RevengeID,1,0,False)=0,'Revenge removal replay');
    Inc(Stamp);P:=ProfessionReady(Stamp,DeathID);Note:=F.S.HandlePacket(P,Replies);
    Check(Pos('REJECTED',Note)>0,'Buff expiry reset actual cooldown authority');
  finally F.Free;end;
end;

procedure NewAttackSessionTests(ID:Cardinal;Cleanup:Boolean=False);
var F:TFixture;ClassID:Word;Member,Stamp:Cardinal;Targets:TArray<Cardinal>;
  A,D,P:TBytes;Replies:TB1008Replies;Note:string;BeforeTick,AfterTick:UInt64;
  I,Hits,Damage,HP,TotalTicks,Removes,MemberRemoves,Minimum,Maximum,ExpectedMulti,Bonus:Integer;
  IsArea,IsStatus:Boolean;Value:Single;Seed:Cardinal;Skill:TB1008LearnedSkill;Stats:TB1008ProfessionSkill;
begin
  if ID<1900 then ClassID:=110 else ClassID:=120;
  F:=TFixture.Create(ClassID,ID,True,10000,30);
  try
    ExpectedMulti:=0;
    if (ID=1904) or (ID=1906) then begin
      F.Mob.PhysicalDefense:=7;F.SetMobHP(10000);
      TB1008Equipment.PhysicalAttack(100,F.L.Equipment(F.S),Minimum,Maximum,30);
      Minimum:=TB1008Balance.ProfessionPhysicalAttack(ClassID,Minimum-
        TB1008Balance.BaseAttributes(100,30).PhysicalAttack)+
        TB1008Balance.ProfessionPhysicalAttack(ClassID,TB1008Balance.ProfessionAttributes(100,ClassID,0,30).PhysicalAttack);
      Maximum:=TB1008Balance.ProfessionPhysicalAttack(ClassID,Maximum-
        TB1008Balance.BaseAttributes(100,30).PhysicalAttack)+
        TB1008Balance.ProfessionPhysicalAttack(ClassID,TB1008Balance.ProfessionAttributes(100,ClassID,0,30).PhysicalAttack);
      Bonus:=0;
      for Skill in F.L.LearnedSkills(F.S) do begin
        if Skill.ID=1006 then Inc(Bonus,Skill.Rank);
        if TB1008ProfessionSkill.IsPassive(Skill.ID) then begin
          Stats:=TB1008ProfessionSkill.Get(Skill.ID,Skill.Rank);
          Inc(Bonus,Stats.AttackBonus+(TB1008Balance.ProfessionAttributes(100,ClassID,0,30).PhysicalAttack*Stats.AttackPercent+50) div 100);
        end;
      end;
      Stats:=TB1008ProfessionSkill.Get(ID,1);Seed:=42;
      for I:=1 to Stats.HitCount do Inc(ExpectedMulti,TB1008MonsterBalance.PhysicalDamage(
        TB1008CombatDamage.Roll(Seed,Minimum+Bonus+Stats.BonusMin,Maximum+Bonus+Stats.BonusMax),7));
    end;
    // Admission is bounded per poll; stream the nearby distant test actor too.
    for I:=1 to 12 do F.S.PollWorld(GetTickCount64+UInt64(I),Replies);
    Member:=TB1008Berneo.MemberHandle(120,1);Stamp:=600;
    IsArea:=TB1008ProfessionSkill.IsArea(ID);IsStatus:=(ID=1103) or (ID=1106) or (ID=1906);
    SetLength(Targets,1+Ord(IsArea));Targets[0]:=120;if IsArea then Targets[1]:=Member;
    Note:=F.S.HandlePacket(ProfessionReady(Stamp,ID),Replies);
    Check(Pos('READY ACCEPTED',Note)>0,'New attack ready: '+Note);
    Inc(Stamp);A:=ProfessionAction(Stamp,ID);Note:=F.S.HandlePacket(A,Replies);
    Check(Pos('START ACCEPTED',Note)>0,'New attack start: '+Note);
    F.S.HandlePacket(A,Replies);Check(Length(Replies)=0,'New attack action replay');
    Inc(Stamp);
    if IsArea then begin
      D:=ProfessionImpact(Stamp,ID,[120,119]);Note:=F.S.HandlePacket(D,Replies);
      Check((Pos('outside',Note)>0) and (Length(Replies)=0),'Area accepted authoritative out-of-geometry NPC: '+Note);
      Inc(Stamp);D:=ProfessionImpact(Stamp,ID,[120,Member]);D[38]:=0;
      Note:=F.S.HandlePacket(D,Replies);
      Check((Pos('REJECTED',Note)>0) and (Length(Replies)=0),'Area partially applied invalid native target list');
      Inc(Stamp);
    end;
    D:=ProfessionImpact(Stamp,ID,Targets);
    if IsArea then begin PutFloat(D,16,9000);PutFloat(D,20,9000);PutFloat(D,24,9000);PutFloat(D,28,0);end;
    BeforeTick:=GetTickCount64;Note:=F.S.HandlePacket(D,Replies);AfterTick:=GetTickCount64;
    Check((Pos('HIT ACCEPTED',Note)>0) or (Pos('AREA APPLIED',Note)>0),'New attack impact: '+Note);
    for I:=0 to High(Targets) do begin
      Hits:=TargetDamage(Replies,ID,Targets[I],Damage);HP:=TargetHP(Replies,Targets[I]);
      if (I=0) and (ExpectedMulti>0) then Check(Damage=ExpectedMulti,'Multi-hit defense was not applied separately to each roll');
      if ID=1104 then Check((Hits=0) and (HP=10000),'Thunder Howl dealt fabricated physical damage')
      else Check((Hits=1) and (Damage>0) and (HP=10000-Damage) and (HP>0),
        'Native area/single target HP or surviving minion damage disagreed');
      if IsStatus then Check(EffectPackets(Replies,ID,Targets[I],1,True)=1,
        'New status omitted target/minion effect');
      if (ID=1103) or (ID=1906) then begin
        Value:=0;
        for P in Replies do if (Length(P)=49) and (P[0]=8) and (P[6]=1) and
          (TB1008Wire.ReadBE32(P,7)=Targets[I]) then Move(P[35],Value,4);
        if ID=1103 then Check(Abs(Value-TB1008MonsterBalance.AttackSpeed(F.Mob.AttackSpeed)*0.95)<0.001,'Spine attack slow not synchronized')
        else Check(Abs(Value-TB1008MonsterBalance.AttackSpeed(F.Mob.AttackSpeed))<0.001,'Phantom movement-only slow changed attack speed');
      end;
    end;
    Check((F.Q.Progress(F.S)=0) and (Integer(F.DB.ExecSQLScalar('SELECT COUNT(*) FROM exp_receipts'))=0) and
      (DropPackets(Replies)=0),'Surviving multi-target attack awarded kill');
    F.S.HandlePacket(D,Replies);Check(Length(Replies)=0,'New skill impact replay');
    Inc(Stamp);BE(D,2,Stamp);F.S.HandlePacket(D,Replies);Check(Length(Replies)=0,'New timestamp replayed admitted targets');
    FinishProfession(F,Stamp,ID);
    if Cleanup then begin
      ReenterFixture(F,Stamp+10,Replies);F.S.PollWorld(AfterTick+6000,Replies);
      Check((TargetDamage(Replies,ID,120,Damage)=0) and
        (EffectPackets(Replies,ID,120,1,False)=0),'Reentry retained old NPC status/periodic damage');Exit;
    end;
    if (ID=1106) or (ID=1906) then begin
      Stats:=TB1008ProfessionSkill.Get(ID,1);
      F.S.PollWorld(BeforeTick+999,Replies);
      Check(TargetDamage(Replies,ID,120,Damage)=0,'Slater periodic damage fired early');
      TotalTicks:=0;Removes:=0;MemberRemoves:=0;
      for I:=1 to 5 do begin
        F.S.PollWorld(AfterTick+UInt64(I)*1000,Replies);
        Check((TargetDamage(Replies,ID,120,Damage)=1) and (Damage=Stats.PeriodicDamage),'One-second periodic tick');
        Check((TargetDamage(Replies,ID,Member,Damage)=1) and (Damage=Stats.PeriodicDamage),'Surviving minion lost periodic tick');
        Inc(Removes,EffectPackets(Replies,ID,120,1,False));
        Inc(MemberRemoves,EffectPackets(Replies,ID,Member,1,False));
        Inc(TotalTicks);F.S.PollWorld(AfterTick+UInt64(I)*1000,Replies);
        Check(TargetDamage(Replies,ID,120,Damage)=0,'Slater repeated poll periodic damage');
      end;
      Check((TotalTicks=5) and (Removes=1) and (MemberRemoves=1),
        'Slater five ticks did not remove each target/minion status exactly once');
    end;
    if IsStatus then begin
      F.S.PollWorld(AfterTick+6000,Replies);
      if ID=1103 then Check(EffectPackets(Replies,ID,120,1,False)=1,'Status expiry omitted native remove');
      F.S.PollWorld(AfterTick+6000,Replies);
      Check((EffectPackets(Replies,ID,120,1,False)=0) and (TargetDamage(Replies,ID,120,Damage)=0),
        'Expired status replayed remove/damage');
    end;
  finally F.Free;end;
end;

procedure ProfessionPeriodicKillTests(ID:Cardinal);
var F:TFixture;ClassID:Word;Stats:TB1008ProfessionSkill;Minimum,Maximum,Direct,I,Damage:Integer;
  Seed,Stamp:Cardinal;NowTick:UInt64;Replies:TB1008Replies;Note:string;
begin
  if ID=1106 then ClassID:=110 else ClassID:=120;
  F:=TFixture.Create(ClassID,ID,True,10000,30);
  try
    Stats:=TB1008ProfessionSkill.Get(ID,1);
    TB1008Equipment.PhysicalAttack(100,F.L.Equipment(F.S),Minimum,Maximum,30);
    Minimum:=TB1008Balance.ProfessionPhysicalAttack(ClassID,Minimum-
      TB1008Balance.BaseAttributes(100,30).PhysicalAttack)+
      TB1008Balance.ProfessionPhysicalAttack(ClassID,TB1008Balance.ProfessionAttributes(100,ClassID,0,30).PhysicalAttack);
    Maximum:=TB1008Balance.ProfessionPhysicalAttack(ClassID,Maximum-
      TB1008Balance.BaseAttributes(100,30).PhysicalAttack)+
      TB1008Balance.ProfessionPhysicalAttack(ClassID,TB1008Balance.ProfessionAttributes(100,ClassID,0,30).PhysicalAttack);
    Seed:=42;Direct:=0;
    for I:=1 to Stats.HitCount do Inc(Direct,TB1008CombatDamage.Roll(Seed,
      Minimum+Stats.BonusMin,Maximum+Stats.BonusMax));
  finally F.Free;end;
  F:=TFixture.Create(ClassID,ID,True,Direct+2*Stats.PeriodicDamage,30);
  try
    Check(Pos('READY ACCEPTED',F.S.HandlePacket(ProfessionReady(900,ID),Replies))>0,'Periodic lethal ready');
    Check(Pos('START ACCEPTED',F.S.HandlePacket(ProfessionAction(901,ID),Replies))>0,'Periodic lethal start');
    Note:=F.S.HandlePacket(ProfessionImpact(902,ID,[120]),Replies);NowTick:=GetTickCount64;
    Check((TargetDamage(Replies,ID,120,Damage)=1) and (Damage=Direct) and
      (TargetHP(Replies,120)=2*Stats.PeriodicDamage),'Periodic lethal direct fixture: '+Note);
    Stamp:=903;FinishProfession(F,Stamp,ID);
    F.S.PollWorld(NowTick+1000,Replies);
    Check((TargetDamage(Replies,ID,120,Damage)=1) and (Damage=Stats.PeriodicDamage) and
      (TargetHP(Replies,120)=Stats.PeriodicDamage),'First periodic tick killed too early');
    F.S.PollWorld(NowTick+2000,Replies);
    Check((TargetDamage(Replies,ID,120,Damage)=1) and (TargetHP(Replies,120)=0) and
      (EffectPackets(Replies,ID,120,1,False)=1) and (F.Q.Progress(F.S)=1) and
      (Integer(F.DB.ExecSQLScalar('SELECT COUNT(*) FROM exp_receipts'))=1) and (DropPackets(Replies)>0),
      'Periodic lethal did not reward once or remove effect');
    F.S.PollWorld(NowTick+5000,Replies);
    Check((TargetDamage(Replies,ID,120,Damage)=0) and (DropPackets(Replies)=0) and
      (Integer(F.DB.ExecSQLScalar('SELECT COUNT(*) FROM exp_receipts'))=1),'Dead target repeated periodic rewards');
  finally F.Free;end;
end;

procedure SessionTest(SkillID:Cardinal;WrongWeapon,LethalDOT,DirectLethal:Boolean);
var F:TFixture;ClassID:Word;A,D,P:TBytes;Replies:TB1008Replies;Note:string;
  BeforeHit,AfterHit,NowTick:UInt64;BeforeEXP,AfterEXP:Int64;
  I,Ticks,Removes,Drops,MP:Integer;SawMP,Respawned:Boolean;
  DropSeed:Cardinal;ExpectedDrops:TArray<TB1008RolledDrop>;
begin
  if SkillID=1101 then ClassID:=110 else ClassID:=120;
  if DirectLethal then I:=1 else I:=1000;
  F:=TFixture.Create(ClassID,SkillID,not WrongWeapon,I);
  try
    Note:=F.S.HandlePacket(Ready(100,SkillID),Replies);
    if WrongWeapon then begin
      Check((Pos('REJECTED',Note)>0) and (Length(Replies)=1) and
        (Replies[0][0]=5) and (Replies[0][1]=4),'Wrong weapon did not cancel ready: '+Note);
      F.S.HandlePacket(Action(101,SkillID),Replies);Check(Length(Replies)=0,'Wrong weapon accepted action');
      F.S.HandlePacket(Impact(102,SkillID),Replies);Check(Length(Replies)=0,'Wrong weapon caused impact');
      Check((F.Q.Progress(F.S)=0) and
        (Integer(F.DB.ExecSQLScalar('SELECT COUNT(*) FROM exp_receipts'))=0),'Rejected cast awarded kill');
      Exit;
    end;
    Check(Pos('READY ACCEPTED',Note)>0,'Profession ready: '+Note);
    A:=Action(101,SkillID);Note:=F.S.HandlePacket(A,Replies);
    Check(Pos('SKILL START ACCEPTED',Note)>0,'Profession action: '+Note);
    MP:=TB1008Balance.ProfessionMaxMP(100,ClassID,10)-7;SawMP:=False;
    for P in Replies do if (Length(P)>=27) and (P[0]=8) and (P[1]=0) and (P[6]=0) then begin
      Check(LE(P,19)=Cardinal(MP),'Profession wrong MP debit');SawMP:=True;
    end;Check(SawMP,'Profession action omitted MP update');
    F.S.HandlePacket(A,Replies);Check(Length(Replies)=0,'Action replay debited MP twice');
    D:=Impact(102,SkillID);BE(D,34,122);F.S.HandlePacket(D,Replies);
    Check(Length(Replies)=0,'Impact changed prepared target');
    BE(D,34,120);BeforeEXP:=F.L.Progress(F.S).TotalEXP;
    BeforeHit:=GetTickCount64;Note:=F.S.HandlePacket(D,Replies);AfterHit:=GetTickCount64;
    Check((Pos('HIT ACCEPTED',Note)>0) and (DamagePackets(Replies,SkillID)=1),'Profession direct impact: '+Note);
    if SkillID=1901 then Check(BleedEffects(Replies,True)=Ord(not DirectLethal),'Wind direct effect admission');
    F.S.HandlePacket(D,Replies);Check(Length(Replies)=0,'Duplicate callback damaged target');
    BE(D,2,103);F.S.HandlePacket(D,Replies);Check(Length(Replies)=0,'New timestamp repeated same cast impact');
    A[11]:=5;BE(A,2,104);F.S.HandlePacket(A,Replies);
    Check((Length(Replies)=1) and (Replies[0][11]=5),'Direct skill finish not accepted');
    F.S.HandlePacket(A,Replies);Check(Length(Replies)=0,'Finish replay');
    if DirectLethal then begin
      Check((F.L.Progress(F.S).TotalEXP=BeforeEXP+TB1008Balance.SpiderEXP) and
        (F.Q.Progress(F.S)=1) and
        (Integer(F.DB.ExecSQLScalar('SELECT COUNT(*) FROM exp_receipts'))=1),
        'Direct lethal reward not exactly once');Exit;
    end;
    if SkillID<>1901 then Exit;
    // Change only the temporary content fixture: cap the injured spider to
    // six HP, so the third rank-one DOT tick is unambiguously the lethal hit.
    if LethalDOT then F.SetMobHP(6);
    Note:=F.S.PollWorld(BeforeHit+1999,Replies);
    Check(DamagePackets(Replies,1901)=0,'Wind periodic damage fired early');
    Ticks:=0;Removes:=0;Drops:=0;
    DropSeed:=42;ExpectedDrops:=TB1008DropProfile.RollMob(DropSeed,100,120,FixtureRates);
    for I:=1 to 6 do begin
      NowTick:=AfterHit+UInt64(I)*2000;Note:=F.S.PollWorld(NowTick,Replies);
      if DamagePackets(Replies,1901)>0 then Check(Note<>'','DOT packets would be silently discarded');
      Inc(Ticks,DamagePackets(Replies,1901,2));Inc(Removes,BleedEffects(Replies,False));
      Inc(Drops,DropPackets(Replies));
      F.S.PollWorld(NowTick,Replies);
      Check((DamagePackets(Replies,1901)=0) and (BleedEffects(Replies,False)=0) and
        (DropPackets(Replies)=0),'Repeated poll replayed DOT/removal/drop');
    end;
    if LethalDOT then begin
      Check((Ticks=3) and (Removes=1),'Lethal DOT continued after death or omitted removal');
      AfterEXP:=F.L.Progress(F.S).TotalEXP;
      Check((AfterEXP=BeforeEXP+TB1008Balance.SpiderEXP) and (F.Q.Progress(F.S)=1) and
        (Integer(F.DB.ExecSQLScalar('SELECT COUNT(*) FROM exp_receipts'))=1),
        'DOT lethal EXP/quest not exactly once');
      Check(Drops=Length(ExpectedDrops),'DOT kill did not roll exactly one deterministic drop batch');
      // A dead incarnation cannot regain the old effect when its handle is reused.
      F.S.PollWorld(AfterHit+30000,Replies);Respawned:=False;
      for P in Replies do if (Length(P)=200) and (P[0]=4) and (P[1]=2) and
        (LE(P,8)=120) then Respawned:=True;
      Check(Respawned,'DOT victim did not respawn');
      Check((DamagePackets(Replies,1901)=0) and (DropPackets(Replies)=0),'Old bleed/drop reached respawn');
      F.S.PollWorld(AfterHit+34000,Replies);
      Check((DamagePackets(Replies,1901)=0) and (F.Q.Progress(F.S)=1) and
        (F.L.Progress(F.S).TotalEXP=AfterEXP) and
        (Integer(F.DB.ExecSQLScalar('SELECT COUNT(*) FROM exp_receipts'))=1) and
        (DropPackets(Replies)=0),'Respawn repeated DOT rewards/drop');
    end else begin
      Check((Ticks=6) and (Removes=1),'Wind duration is not six ticks and one removal');
      Check((F.L.Progress(F.S).TotalEXP=BeforeEXP) and (F.Q.Progress(F.S)=0),
        'Nonlethal DOT awarded kill');
      F.S.PollWorld(AfterHit+14000,Replies);
      Check((DamagePackets(Replies,1901)=0) and (BleedEffects(Replies,False)=0),'Expired DOT resumed');
    end;
  finally F.Free;end;
end;

procedure MasteryStorageTests(MasteryID:Cardinal;ClassID:Word);
var Dir,Path:string;L:TB1008LootStore;DB:TFDConnection;Owner:TObject;
  Preview:TBytes;Rank,OtherID:Cardinal;I,Spent,BeforeSP:Integer;
  Found:Boolean;Skill:TB1008LearnedSkill;
begin
  Dir:=NewDirectory;Path:=TPath.Combine(Dir,'mastery.sqlite3');
  L:=nil;DB:=nil;Owner:=TObject.Create;
  try
    Preview:=TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(CreateRequest),1);
    L:=TB1008LootStore.Create(Path,FixtureRates);Check(L.Acquire(Owner,Preview),'Mastery owner');
    L.GrantTestProgress(Owner,'level18',18,40);Promote(L,Owner,ClassID);
    Check(L.LearnSkill(Owner,'early',Learn(MasteryID))=slrRejected,'Mastery learned below level19');
    L.GrantTestProgress(Owner,'level19',19,40);
    Check(L.LearnSkill(Owner,'missing-strength',Learn(MasteryID))=slrRejected,'Mastery ignored Strength prerequisite');
    Check(L.LearnSkill(Owner,'frenzy',Learn(1004))=slrApplied,'Mastery Frenzy prerequisite');
    Check(L.LearnSkill(Owner,'strength',Learn(1006))=slrApplied,'Mastery Strength prerequisite');
    OtherID:=1102;if MasteryID=1102 then OtherID:=1902;
    Check(L.LearnSkill(Owner,'other-profession',Learn(OtherID))=slrRejected,'Opposite mastery learned');
    BeforeSP:=L.SkillPoints(Owner);
    Check(L.LearnSkill(Owner,'mastery',Learn(MasteryID))=slrApplied,'Mastery level19 learn');
    Check((Integer(L.SkillPoints(Owner))=BeforeSP-1) and
      (L.LearnSkill(Owner,'mastery',Learn(MasteryID))=slrAlreadyKnown) and
      (Integer(L.SkillPoints(Owner))=BeforeSP-1),'Mastery learn/replay SP');
    DB:=OpenDB(Path);
    for I:=1 to 2 do begin
      L.GrantTestProgress(Owner,'early-level-'+IntToStr(I),18+4*I,40);
      Check(L.UpgradeSkill(Owner,'early-rank-'+IntToStr(I),Upgrade(MasteryID,I),Rank)=surRejected,
        'Mastery upgrade below required level');
      L.GrantTestProgress(Owner,'rank-level-'+IntToStr(I),19+4*I,40);
      Spent:=Integer(DB.ExecSQLScalar('SELECT spent FROM skill_points WHERE id=1'));
      DB.ExecSQL('UPDATE skill_points SET spent=earned+bonus WHERE id=1');
      Check(L.UpgradeSkill(Owner,'no-sp-'+IntToStr(I),Upgrade(MasteryID,I),Rank)=surRejected,
        'Mastery upgrade accepted without SP');
      DB.ExecSQL('UPDATE skill_points SET spent=:n WHERE id=1',[Spent]);
      Check((L.UpgradeSkill(Owner,'rank-'+IntToStr(I),Upgrade(MasteryID,I),Rank)=surApplied) and
        (Rank=Cardinal(I+1)) and (L.SkillPoints(Owner)=39),'Mastery level23/27 rank or SP');
      Check((L.UpgradeSkill(Owner,'rank-'+IntToStr(I),Upgrade(MasteryID,I),Rank)=surDuplicate) and
        (L.SkillPoints(Owner)=39),'Mastery upgrade replay spent SP');
    end;
    // The production curve currently stops at30. Keep the native31/35
    // requirements without raising the cap or manufacturing future EXP data.
    Check((TB1008SkillTraining.Get(MasteryID,4).RequiredLevel=31) and
      (TB1008SkillTraining.Get(MasteryID,5).RequiredLevel=35),'Future mastery level gates');
    L.GrantTestProgress(Owner,'cap30',30,40);
    Check((L.UpgradeSkill(Owner,'rank4-at-cap',Upgrade(MasteryID,3),Rank)=surRejected) and
      (L.SkillPoints(Owner)=40),'Current cap bypassed level31 mastery requirement');
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,FixtureRates);
    Check(L.Acquire(Owner,Preview),'Mastery reopen owner');Found:=False;
    for Skill in L.LearnedSkills(Owner) do if Skill.ID=MasteryID then Found:=Skill.Rank=3;
    Check(Found and (L.SkillPoints(Owner)=40) and (L.ClassState(Owner).ClassID=ClassID),
      'Mastery rank/SP/class lost on reopen');
    Check(L.UpgradeSkill(Owner,'rank-2',Upgrade(MasteryID,2),Rank)=surDuplicate,
      'Mastery upgrade receipt lost on reopen');
  finally L.Free;DB.Free;Owner.Free;TDirectory.Delete(Dir,True);end;
end;

procedure MasterySessionTest(MasteryID:Cardinal;ClassID:Word);
const Level=27;
var F:TFixture;Replies:TB1008Replies;P,A,D:TBytes;Note:string;
  SkillID,Timestamp,Seed,CorrectWeapon,WrongWeapon,N:Cardinal;
  BaseAttack,BeforeSP,I:Integer;
  LR:TB1008SkillLearn;UR:TB1008SkillUpgrade;
  function Bonus(Rank:Integer):Integer;
  begin
    if MasteryID=1102 then Result:=Rank else Result:=(BaseAttack*Rank+50) div 100;
  end;
  procedure CheckParameters(Expected:Integer;const Context:string);
  var Packet:TBytes;Value:Single;Count:Integer;
  begin
    Count:=0;
    for Packet in Replies do if (Length(Packet)>94) and (Packet[0]=8) and (Packet[1]=2) then begin
      Move(Packet[90],Value,4);
      Check(Abs(Value-Expected-TB1008Balance.ProfessionPhysicalAttack(ClassID,BaseAttack)+BaseAttack)<0.001,
        Context+' C physical attack');Inc(Count);
    end;
    Check(Count=1,Context+' omitted/duplicated C refresh');
  end;
  procedure NativeLearn(ID:Cardinal;Refresh:Boolean;ExpectedAttack:Integer);
  begin
    Inc(Timestamp);LR:=Learn(ID);LR.Timestamp:=Timestamp;P:=LR.Ack;
    BeforeSP:=F.L.SkillPoints(F.S);Note:=F.S.HandlePacket(P,Replies);
    Check((Length(Replies)>=2) and (Replies[0][0]=5) and (Replies[0][1]=6) and
      (Integer(F.L.SkillPoints(F.S))=BeforeSP-1),'Native mastery prerequisite/learn: '+Note);
    if Refresh then CheckParameters(ExpectedAttack,'Learn '+UIntToStr(ID));
    F.S.HandlePacket(P,Replies);
    Check((Integer(F.L.SkillPoints(F.S))=BeforeSP-1) and (Length(Replies)=2) and
      (Replies[0][1]<>6),'Native mastery learn replay');
  end;
  procedure Equip(ItemID:Cardinal;Wear:Boolean;ExpectedAttack:Integer);
  var Packet:TBytes;Speed,ExpectedSpeed:Single;Found:Boolean;
  begin
    Inc(Timestamp);P:=nil;SetLength(P,17+Ord(Wear));P[0]:=6;P[1]:=Ord(not Wear);
    BE(P,2,Timestamp);BE(P,6,1);BE(P,13,ItemID);
    if Wear then begin P[10]:=1;P[11]:=F.L.Item(F.S,ItemID).Slot;P[12]:=255;end
    else begin P[10]:=0;P[11]:=7;P[12]:=7;end;
    Note:=F.S.HandlePacket(P,Replies);Check(Pos('EQUIPMENT COMMITTED',Note)>0,'Mastery equipment: '+Note);
    CheckParameters(ExpectedAttack,'Equipment '+UIntToStr(ItemID));
    ExpectedSpeed:=1;
    if Wear then ExpectedSpeed:=TB1008Balance.WeaponAutoAttackSpeed(TB1008Items.Get(ItemID).Subtype);
    Found:=False;
    for Packet in Replies do if (Length(Packet)=49) and (Packet[0]=8) and (Packet[6]=0) then begin
      Move(Packet[35],Speed,4);Check(Abs(Speed-ExpectedSpeed)<0.0001,'Weapon swap speed independent of profession');
      Found:=True;
    end;
    Check(Found,'Equipment change omitted immediate speed refresh');
  end;
  procedure CastAndCheck(ID:Cardinal;ExpectedMastery:Integer);
  var Stats:TB1008AttackSkillStats;MinAttack,MaxAttack,Expected,Count:Integer;Packet:TBytes;
  begin
    Stats:=TB1008AttackSkillStats.Get(ID,1);
    TB1008Equipment.PhysicalAttack(100,F.L.Equipment(F.S),MinAttack,MaxAttack,Level);
    MinAttack:=TB1008Balance.ProfessionPhysicalAttack(ClassID,MinAttack-
      TB1008Balance.BaseAttributes(100,Level).PhysicalAttack)+
      TB1008Balance.ProfessionPhysicalAttack(ClassID,BaseAttack);
    MaxAttack:=TB1008Balance.ProfessionPhysicalAttack(ClassID,MaxAttack-
      TB1008Balance.BaseAttributes(100,Level).PhysicalAttack)+
      TB1008Balance.ProfessionPhysicalAttack(ClassID,BaseAttack);
    Expected:=TB1008CombatDamage.Roll(Seed,MinAttack+1+ExpectedMastery+Stats.BonusMin,
      MaxAttack+1+ExpectedMastery+Stats.BonusMax);
    Expected:=TB1008MonsterBalance.PhysicalDamage(Expected,0);
    Inc(Timestamp);Note:=F.S.HandlePacket(Ready(Timestamp,ID),Replies);
    Check(Pos('READY ACCEPTED',Note)>0,'Mastery combat ready: '+Note);
    Inc(Timestamp);A:=Action(Timestamp,SkillID);BE(A,12,Stats.ActionID);
    Note:=F.S.HandlePacket(A,Replies);Check(Pos('SKILL START ACCEPTED',Note)>0,'Mastery combat start: '+Note);
    Inc(Timestamp);D:=Impact(Timestamp,SkillID);BE(D,12,ID);
    Note:=F.S.HandlePacket(D,Replies);Count:=0;
    for Packet in Replies do if (Length(Packet)=47) and (Packet[0]=5) and (Packet[1]=2) and
      (TB1008Wire.ReadBE32(Packet,12)=ID) then begin
      Check(Integer(LE(Packet,23))=Expected,'Combat disagrees with mastery C bonus');Inc(Count);
    end;
    Check(Count=1,'Mastery combat omitted hit: '+Note);
    Inc(Timestamp);BE(A,2,Timestamp);A[11]:=5;F.S.HandlePacket(A,Replies);
    Check((Length(Replies)=1) and (Replies[0][11]=5),'Mastery combat finish');
  end;
begin
  if ClassID=110 then begin SkillID:=1101;CorrectWeapon:=1001;WrongWeapon:=3001;end
  else begin SkillID:=1901;CorrectWeapon:=3001;WrongWeapon:=1001;end;
  // At27, base94 makes Polearm rank2 half-up=2 distinguishable from floor=1.
  BaseAttack:=TB1008Balance.ProfessionAttributes(100,ClassID,0,Level).PhysicalAttack;
  F:=TFixture.Create(ClassID,SkillID,True,10000,Level);
  try
    Timestamp:=200;Seed:=42;
    NativeLearn(1004,False,0);
    NativeLearn(1006,True,BaseAttack+1);
    NativeLearn(MasteryID,True,BaseAttack+1+Bonus(1));
    for I:=1 to 2 do begin
      Inc(Timestamp);UR:=Upgrade(MasteryID,I);UR.Timestamp:=Timestamp;
      P:=UR.Ack(I+1);BE(P,14,I);BeforeSP:=F.L.SkillPoints(F.S);
      Note:=F.S.HandlePacket(P,Replies);
      Check((Length(Replies)=3) and (Replies[0][1]=7) and
        (TB1008Wire.ReadBE32(Replies[0],14)=Cardinal(I+1)) and
        (Integer(F.L.SkillPoints(F.S))=BeforeSP-1),'Native mastery rank upgrade: '+Note);
      CheckParameters(BaseAttack+1+Bonus(I+1),'Mastery upgrade');
      F.S.HandlePacket(P,Replies);
      Check((Length(Replies)=2) and (Replies[0][1]<>7) and
        (Integer(F.L.SkillPoints(F.S))=BeforeSP-1),'Native mastery upgrade replay');
    end;
    NativeLearn(1003,False,0);
    CastAndCheck(1001,Bonus(3));
    if F.L.Item(F.S,WrongWeapon).Amount=0 then
      Check(F.L.CollectItem(F.S,'wrong-weapon',WrongWeapon,1,N),'Mastery alternate weapon');
    Equip(CorrectWeapon,False,BaseAttack+1);
    Equip(WrongWeapon,True,BaseAttack+1);
    Equip(CorrectWeapon,True,BaseAttack+1+Bonus(3));
    Equip(WrongWeapon,True,BaseAttack+1);
    // Body Blow permits either weapon family; its damage must retain Strength
    // while dropping this profession's weapon-specific mastery contribution.
    CastAndCheck(1003,0);
  finally F.Free;end;
end;

begin
  try
    StorageTests;
    BranchStorageTests(110,False);BranchStorageTests(110,True);
    BranchStorageTests(120,False);BranchStorageTests(120,True);
    MasteryStorageTests(1102,110);
    MasteryStorageTests(1902,120);
    MasterySessionTest(1102,110);
    MasterySessionTest(1902,120);
    SessionTest(1101,True,False,False);
    SessionTest(1901,True,False,False);
    SessionTest(1101,False,False,False);
    SessionTest(1101,False,False,True);
    SessionTest(1901,False,False,True);
    SessionTest(1901,False,False,False);
    SessionTest(1901,False,True,False);
    SelfBuffSessionTests(110,False);SelfBuffSessionTests(120,False);
    SelfBuffSessionTests(110,True);SelfBuffSessionTests(120,True);
    NewAttackSessionTests(1103);NewAttackSessionTests(1104);
    NewAttackSessionTests(1106);NewAttackSessionTests(1903);
    NewAttackSessionTests(1904);NewAttackSessionTests(1906);
    NewAttackSessionTests(1103,True);NewAttackSessionTests(1106,True);
    NewAttackSessionTests(1906,True);
    ProfessionPeriodicKillTests(1106);ProfessionPeriodicKillTests(1906);
    Writeln('PASS: profession migration/training/reopen; mastery C/combat/weapon gates; direct casts/replay; Wind DOT/death/respawn');
  except on E:Exception do begin Writeln('FAIL: ',E.ClassName,': ',E.Message);ExitCode:=1;end;end;
end.
