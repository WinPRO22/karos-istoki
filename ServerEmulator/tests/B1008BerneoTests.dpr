program B1008BerneoTests;
{$APPTYPE CONSOLE}
uses Emulator.Rates.B1008,System.SysUtils,System.IOUtils,System.Math,System.Diagnostics,Winapi.Windows,
  FireDAC.Comp.Client,
  Emulator.Content,Emulator.Repository,Emulator.Repository.SQLite,Emulator.Runtime,
  Emulator.Profile.B1008,Emulator.Berneo.B1008,Emulator.DropProfile.B1008,Emulator.Items.B1008,
  Emulator.Session,Emulator.Character.B1008,Emulator.Login.B1008,Emulator.Protocol.B1008,
  Emulator.World.B1008,Emulator.LootStore.B1008,Emulator.QuestState.B1008,Emulator.Fletta.B1008,
  Emulator.WorldState.B1008,Emulator.Combat.B1008,Emulator.MonsterBalance.B1008,
  Emulator.Skills.B1008,Emulator.Npcs.B1008;

{$I B1008UnitRates.inc}

procedure Check(B:Boolean;const Msg:string);
begin if not B then raise Exception.Create(Msg);end;
procedure BE(var P:TBytes;O:Integer;V:Cardinal);
begin P[O]:=Byte(V shr 24);P[O+1]:=Byte(V shr 16);P[O+2]:=Byte(V shr 8);P[O+3]:=Byte(V);end;
function LE(const P:TBytes;O:Integer):Cardinal;
begin Move(P[O],Result,4);end;
function Contains(const A:TArray<Integer>;ID:Cardinal):Boolean;
var I:Integer;
begin for I in A do if Cardinal(I)=ID then Exit(True);Result:=False;end;

procedure MovementAdmission;
var Track:TB1008MovementAdmission;M:TB1008Movement;
begin
  Track:=Default(TB1008MovementAdmission);M:=Default(TB1008Movement);
  Check(not Track.Allows(20,0,0,1000),'Unannounced movement admitted');
  M.Kind:=0;M.CharacterID:=1;M.Mode:=1;M.ToX:=100;
  Track.Observe(M,1000);
  Check(Track.Allows(30,0,0,1390),'Valid approach before stop rejected');
  Check(Track.Allows(30,6,3,1390),'Normal segment tolerance lost');
  Check(not Track.Allows(30,11,0,1390),'Off-path attack admitted');
  Check(not Track.Allows(30,0,11,1390),'Vertical teleport admitted');
  Check(not Track.Allows(100,0,0,1000),'Unreached destination admitted immediately');
  Check(not Track.Allows(111,0,0,2500),'Attack past destination admitted');
  Check(not Track.Allows(-11,0,0,1500),'Backwards attack admitted');
  Check(not Track.Allows(20,0,0,999),'Clock rollback admitted');
  Check(not Track.Allows(30,0,0,3001),'Stale movement admitted');
  Track.Reset;Check(not Track.Allows(30,0,0,1390),'Movement reused after reset');
  Track.Observe(M,1000);M.Mode:=2;Track.Observe(M,1100);
  Check(not Track.Allows(30,0,0,1390),'Stop/Esc did not clear movement admission');
  M.Mode:=1;Track.Observe(M,1000);M.Mode:=8;Track.Observe(M,1100);
  Check(not Track.Allows(30,0,0,1390),'Unmapped movement did not clear old segment');
  // Actual rejected live approach: 27.7 units in 391 ms, along declared path.
  M.Mode:=1;M.FromX:=8051.953;M.FromZ:=5476.292;M.FromY:=590.586;
  M.ToX:=8082.593;M.ToZ:=5452.509;M.ToY:=592.427;Track.Observe(M,1000);
  Check(Track.Allows(8073.827,5459.313,591.205,1391),'Live approach regression');
  Writeln('PASS: bounded movement admission, live approach, stale/off-path/teleport/stop guards');
end;

procedure Distribution;
var M:TB1008BerneoMob;D:TB1008RolledDrop;A:TArray<TB1008RolledDrop>;
  I,J,Ordinary,Craft,Potion,Gear,RegularCount,GearCount,TotalWeight:Integer;State:Cardinal;
begin
  for M in TB1008Berneo.Mobs do begin
    State:=M.ClientID;Ordinary:=0;Craft:=0;Potion:=0;Gear:=0;
    for I:=1 to 10000 do begin
      A:=TB1008DropProfile.RollMob(State,100,M.Definition.MobID,FixtureRates);
      Check((Length(A)>=2) and (Length(A)<=3) and (A[0].ItemID=999999) and
        (A[0].Amount>=Cardinal(M.CaratMin)) and (A[0].Amount<=Cardinal(M.CaratMax)),'Currency rule');
      RegularCount:=0;GearCount:=0;
      for J:=1 to High(A) do begin
        D:=A[J];Check(D.Amount=1,'Unexpected stack quantity');
        if D.Category='ordinary' then begin Inc(RegularCount);Inc(Ordinary);Check(Contains(M.IDs[0],D.ItemID),'Foreign ordinary drop');end
        else if D.Category='craft' then begin Inc(RegularCount);Inc(Craft);Check(Contains(M.IDs[1],D.ItemID),'Foreign craft drop');end
        else if D.Category='potion' then begin Inc(RegularCount);Inc(Potion);Check(Contains(M.IDs[2],D.ItemID),'Foreign potion');end
        else begin
          Inc(GearCount);Inc(Gear);Check(TB1008Items.Get(D.ItemID).RequiredLevel>=5,'Starter gear leaked');
          Check((TB1008Items.Get(D.ItemID).RequiredLevel=TB1008DropProfile.Tier(M.Level,0)) or
            (TB1008Items.Get(D.ItemID).RequiredLevel=TB1008DropProfile.Tier(M.Level,99)),'Wrong species gear tier');
        end;
      end;
      Check((RegularCount=1) and (GearCount<=1),'Species violated fixed bag/equipment limit');
    end;
    TotalWeight:=40;
    if Length(M.IDs[0])>0 then Inc(TotalWeight,80);
    if Length(M.IDs[1])>0 then Inc(TotalWeight,50);
    if Length(M.IDs[0])=0 then Check(Ordinary=0,'Unknown ordinary pool substituted')
    else Check(Abs(Ordinary-10000*80/TotalWeight)<250,'Ordinary category weight');
    if Length(M.IDs[1])=0 then Check(Craft=0,'Unknown craft pool substituted')
    else Check(Abs(Craft-10000*50/TotalWeight)<250,'Craft category weight');
    Check((Abs(Potion-10000*40/TotalWeight)<250) and (Abs(Gear-500)<150),'Potion weight and equipment 5%');
  end;
  Writeln('PASS: 180000 kills, all 18 species/level tables, exact regular bags, single equipment roll and tier-19 gear');
end;

procedure CombatCalibration;
const Defenses:array[0..4] of Integer=(21,36,51,59,67);
  MinDamage:array[0..4] of Integer=(9,6,3,1,1);
  MaxDamage:array[0..4] of Integer=(13,10,7,5,3);
var S,Previous:TB1008MonsterStats;I,J,Damage:Integer;E:TB1008CoerciveEffect;
begin
  S:=TB1008MonsterBalance.AtLevel(1);
  Check((S.HP=50) and (S.AttackMin=13) and (S.AttackMax=17) and (S.Defense=15),'Spider anchor');
  Check(TB1008MonsterBalance.PhysicalDamage(16,S.Defense)=13,'Classic unarmed hit');
  for I:=0 to 4 do begin
    Check(TB1008MonsterBalance.PhysicalDamage(13,Defenses[I])=MinDamage[I],'Classic armor minimum');
    Check(TB1008MonsterBalance.PhysicalDamage(17,Defenses[I])=MaxDamage[I],'Classic armor maximum');
  end;
  for I:=2 to 20 do begin
    Previous:=S;S:=TB1008MonsterBalance.AtLevel(I);
    Check((S.HP>Previous.HP) and (S.AttackMin>Previous.AttackMin) and
      (S.AttackMax>Previous.AttackMax) and (S.Defense>Previous.Defense),'Level growth stalled');
    Check((S.HP=Floor(50*Power(1.08,I-1)+0.5)) and
      (S.AttackMin=Floor(13*Power(1.08,I-1)+0.5)) and
      (S.AttackMax=Floor(17*Power(1.08,I-1)+0.5)) and
      (S.Defense=Floor(15*Power(1.08,I-1)+0.5)),'Growth rounded at intermediate levels');
  end;
  Check((S.HP=216) and (S.AttackMin=56) and (S.AttackMax=73) and (S.Defense=65),'Level20 curve');
  E:=Default(TB1008CoerciveEffect);E.Start(1,1000);
  Check(TB1008MonsterBalance.PhysicalDamage(16,15-E.ActiveDefensePenalty(20999))=14,'Coercive armor reduction');
  Check(TB1008MonsterBalance.PhysicalDamage(16,15-E.ActiveDefensePenalty(21000))=13,'Coercive expiry');
  for I:=0 to 1000 do begin
    Damage:=TB1008MonsterBalance.PhysicalDamage(40,I);
    Check((Damage>=1) and (Damage<=40),'Damage clamp');
    if I>0 then Check(Damage<=J,'Armor raised damage');J:=Damage;
    Check(TB1008MonsterBalance.PhysicalDamage(0,I)=0,'Zero damage became a hit');
  end;
  Writeln('PASS: Classic anchors, +20% all stats at levels1..20, real Coercive mitigation and clamps');
end;

procedure Run;
var ID:TGUID;Dir,Path,Status,Description:string;Repo:IEmulatorContentRepository;
  Runtime:TEmulatorRuntimeManager;Snap:IEmulatorContentSnapshot;M:TB1008BerneoMob;
  G,Target:TEmulatorSpawnDefinition;Def:TEmulatorMobDefinition;Seen:array[0..3999] of Boolean;
  I,J,Total,Hits,Adds,Packets,BeforeHP,Damage,Misses,Fails:Integer;H:Cardinal;V,CombatOffset:Single;Revision,BeforeEXP:Int64;Tick:UInt64;
  Store:TB1008CharacterStore;Session:TEmulatorSession;Loot:TB1008LootStore;Quests:TB1008QuestStore;
  P,Q,Reply:TBytes;Replies:TB1008Replies;Watch:TStopwatch;Admitted,Respawned:Boolean;
  Known:array[0..3999] of Boolean;
  MigrationDB:TFDConnection;
  procedure Observe;
  var Packet:TBytes;Actor:Cardinal;
  begin
    for Packet in Replies do begin
      if (Length(Packet)=200) and (Packet[0]=4) and (Packet[1]=2) then begin
        Actor:=LE(Packet,8);Check(Actor<=High(Known),'Invalid appearance actor');
        Check((LE(Packet,56) and $FFFF)=TB1008Berneo.LevelForHandle(Actor),'Appearance/respawn level lost');
        Check(not Known[Actor],'Duplicate visible actor admission');Known[Actor]:=True;
      end else if (Length(Packet)=42) and (Packet[0]=4) and (Packet[1]=1) and (Packet[6]=1) then begin
        Actor:=TB1008Wire.ReadBE32(Packet,8);
        Check((Actor<=High(Known)) and Known[Actor],'Movement sent before appearance/after removal');
      end else if (Length(Packet)=11) and (Packet[0]=4) and (Packet[1]=3) then begin
        Actor:=TB1008Wire.ReadBE32(Packet,7);
        Check((Actor<=High(Known)) and Known[Actor],'Removal for unknown actor');Known[Actor]:=False;
      end;
    end;
  end;
begin
  CreateGUID(ID);Dir:=TPath.Combine(TPath.GetTempPath,'karos-berneo-'+GUIDToString(ID));
  ForceDirectories(Dir);Path:=TPath.Combine(Dir,'content.sqlite3');Runtime:=nil;
  Store:=nil;Session:=nil;Loot:=nil;Quests:=nil;
  try
    Repo:=TSQLiteContentRepository.Create(Path);Snap:=Repo.LoadSnapshot('b1008');
    Snap.TryGetMob(120,Def);Def.MaxHP:=54;Def.AttackDamage:=1;Def.AttackRange:=14;Repo.PublishMob(Def);
    Repo:=nil;Repo:=TSQLiteContentRepository.Create(Path,True);Snap:=Repo.LoadSnapshot('b1008');
    Check((Snap.MobCount=18) and (Snap.SpawnCount=169),'Full map seed counts');
    Check(Snap.TryGetMob(120,Def) and (Def.MaxHP=50) and (Def.AttackMin=13) and
      (Def.AttackDamage=17) and (Def.PhysicalDefense=15),'Legacy spider not upgraded');
    // Simulate an installed v1 pack plus one manually tuned monster. The
    // spacing migration upgrades only placeholders, never custom values.
    Snap.TryGetMob(1005002,Def);Def.AttackRange:=14;Repo.PublishMob(Def);
    Snap.TryGetMob(1005003,Def);Def.AttackRange:=19;Repo.PublishMob(Def);Repo:=nil;
    MigrationDB:=TFDConnection.Create(nil);
    try
      MigrationDB.DriverName:='SQLite';MigrationDB.Params.Values['Database']:=Path;
      MigrationDB.LoginPrompt:=False;MigrationDB.Connected:=True;
      MigrationDB.ExecSQL('DELETE FROM content_packs WHERE name=''berneo-melee-spacing-v2''');
      MigrationDB.ExecSQL('DELETE FROM content_packs WHERE name=''berneo-combat-growth-v3''');
      MigrationDB.ExecSQL('UPDATE mob_definitions SET max_hp=59,attack_damage=1,attack_min=0,physical_defense=0 WHERE mob_id=1005002');
      MigrationDB.ExecSQL('UPDATE mob_definitions SET max_hp=999,attack_damage=30,attack_min=20,physical_defense=9 WHERE mob_id=1005003');
    finally MigrationDB.Free;end;
    Repo:=TSQLiteContentRepository.Create(Path,True);Snap:=Repo.LoadSnapshot('b1008');
    Check(Snap.TryGetMob(1005002,Def) and (Def.AttackRange=24),'Old shared reach not migrated');
    Check((Def.MaxHP=54) and (Def.AttackMin=14) and (Def.AttackDamage=18) and
      (Def.PhysicalDefense=16),'Installed legacy combat defaults not migrated');
    Check(Snap.TryGetMob(120,Def) and (Def.AttackRange=14),'Spider reach unexpectedly changed');
    Check(Snap.TryGetMob(1005003,Def) and (Def.AttackRange=19),'Custom reach overwritten');
    Check((Def.MaxHP=999) and (Def.AttackMin=20) and (Def.AttackDamage=30) and
      (Def.PhysicalDefense=9),'Custom combat settings overwritten');
    // Installed v3: exact 20% defaults migrate, an edited monster survives,
    // and the pre-migration data remain available for recovery.
    Repo:=nil;MigrationDB:=TFDConnection.Create(nil);
    try
      MigrationDB.DriverName:='SQLite';MigrationDB.Params.Values['Database']:=Path;
      MigrationDB.LoginPrompt:=False;MigrationDB.Connected:=True;
      MigrationDB.ExecSQL('DELETE FROM content_packs WHERE name=''berneo-combat-growth-v4''');
      MigrationDB.ExecSQL('DROP TABLE mob_definitions_growth_v3_backup');
      for M in TB1008Berneo.Mobs do if M.Definition.MobID<>1005003 then
        MigrationDB.ExecSQL('UPDATE mob_definitions SET max_hp=:hp,attack_min=:amin,'+
          'attack_damage=:amax,physical_defense=:def WHERE mob_id=:id',
          [Floor(50*Power(1.2,M.Level-1)+0.5),Floor(13*Power(1.2,M.Level-1)+0.5),
           Floor(17*Power(1.2,M.Level-1)+0.5),Floor(15*Power(1.2,M.Level-1)+0.5),M.Definition.MobID]);
    finally MigrationDB.Free;end;
    Repo:=TSQLiteContentRepository.Create(Path,True);Snap:=Repo.LoadSnapshot('b1008');
    for M in TB1008Berneo.Mobs do if M.Definition.MobID<>1005003 then begin
      Check(Snap.TryGetMob(M.Definition.MobID,Def),'Migration lost mob');
      Check((Def.MaxHP=M.Definition.MaxHP) and (Def.AttackMin=M.Definition.AttackMin) and
        (Def.AttackDamage=M.Definition.AttackDamage) and
        (Def.PhysicalDefense=M.Definition.PhysicalDefense),'Installed 20% profile not migrated');
    end;
    Check(Snap.TryGetMob(1005003,Def) and (Def.MaxHP=999) and (Def.AttackRange=19) and
      (Def.AttackMin=20) and (Def.AttackDamage=30) and (Def.PhysicalDefense=9),'v4 overwrote custom monster');
    MigrationDB:=TFDConnection.Create(nil);
    try
      MigrationDB.DriverName:='SQLite';MigrationDB.Params.Values['Database']:=Path;
      MigrationDB.LoginPrompt:=False;MigrationDB.Connected:=True;
      Check(Integer(MigrationDB.ExecSQLScalar('SELECT max_hp FROM mob_definitions_growth_v3_backup WHERE mob_id=1005002'))=60,
        'Missing pre-growth-migration backup');
    finally MigrationDB.Free;end;
    // Upgrade an installed one-actor miniboss exactly once, retaining backups.
    Repo:=nil;MigrationDB:=TFDConnection.Create(nil);
    try
      MigrationDB.DriverName:='SQLite';MigrationDB.Params.Values['Database']:=Path;
      MigrationDB.LoginPrompt:=False;MigrationDB.Connected:=True;
      MigrationDB.ExecSQL('DELETE FROM content_packs WHERE name=''berneo-miniboss-v5''');
      MigrationDB.ExecSQL('DROP TABLE miniboss_mobs_v4_backup');
      MigrationDB.ExecSQL('DROP TABLE miniboss_spawns_v4_backup');
      MigrationDB.ExecSQL('UPDATE mob_definitions SET max_hp=171 WHERE mob_id=1005717');
      MigrationDB.ExecSQL('UPDATE spawn_definitions SET population=1 WHERE spawn_id=23');
    finally MigrationDB.Free;end;
    Repo:=TSQLiteContentRepository.Create(Path,True);Snap:=Repo.LoadSnapshot('b1008');
    Check(Snap.TryGetMob(1005717,Def) and (Def.MaxHP=1197),'Miniboss HP not migrated');
    MigrationDB:=TFDConnection.Create(nil);
    try
      MigrationDB.DriverName:='SQLite';MigrationDB.Params.Values['Database']:=Path;
      MigrationDB.LoginPrompt:=False;MigrationDB.Connected:=True;
      Check(Integer(MigrationDB.ExecSQLScalar('SELECT population FROM spawn_definitions WHERE spawn_id=23'))=10,'Miniboss population');
      Check(Integer(MigrationDB.ExecSQLScalar('SELECT max_hp FROM miniboss_mobs_v4_backup'))=171,'Miniboss migration backup');
    finally MigrationDB.Free;end;
    for M in TB1008Berneo.Mobs do
      for var Other in TB1008Berneo.Mobs do
        // Ordinary progression is monotonic; miniboss rewards are separately
        // authored by species and do not constrain the ordinary level curve.
        if (M.Definition.MaxHP=TB1008MonsterBalance.AtLevel(M.Level).HP) and
          (Other.Definition.MaxHP=TB1008MonsterBalance.AtLevel(Other.Level).HP) and
          (M.Level>Other.Level) then
          Check(M.BaseEXP>Other.BaseEXP,'Higher-level ordinary monster grants less EXP');
    Def:=TB1008Berneo.Mob(1005003).Definition;Repo.PublishMob(Def);Snap:=Repo.LoadSnapshot('b1008');
    Revision:=Snap.Revision;Repo:=nil;Repo:=TSQLiteContentRepository.Create(Path,True);
    Snap:=Repo.LoadSnapshot('b1008');Check(Snap.Revision=Revision,'Seed was reapplied on restart');
    FillChar(Seen,SizeOf(Seen),0);Total:=0;
    for G in TB1008Berneo.Groups do for J:=0 to G.Population-1 do begin
      H:=TB1008Berneo.MemberHandle(G.EntityHandle,J);
      Check(not Seen[H],'Duplicate population handle');Seen[H]:=True;Inc(Total);
      M:=TB1008Berneo.Mob(G.MobID);
      P:=TB1008World.BuildSpiderAppearProbe(1,H,M.Definition.MaxHP,15,50,1,G.X,G.Z,G.Y,G.Heading);
      Check((LE(P,8)=H) and (LE(P,$46)=G.EntityHandle) and
        (LE(P,28)=Cardinal(M.Definition.MaxHP)),'Actor species/template/HP mismatch');
      Check((P[56]=M.Level) and (P[57]=0),'LE16 monster level at 04/02+56');
      Check(LE(P,52)=$3F800000,'Level overwrote attack playback multiplier');
      Q:=TB1008CombatWire.BuildSpiderGageProbe(1,H,1,M.Definition.MaxHP,15,50,1);
      Check((Q[39]=M.Level) and (Q[40]=0),'Level lost in 08/00 HP update');
    end;
    Check((Total=955) and not Seen[121] and not Seen[136] and
      not Seen[158] and not Seen[159],'NPCs counted as monsters');
    // Stationary isolated content fixture: combat tests do not advance a real game or wait for patrols.
    Misses:=0;Fails:=0;
    for M in TB1008Berneo.Mobs do begin
      Snap.TryGetMob(M.Definition.MobID,Def);Def.MovementSpeed:=0;Repo.PublishMob(Def);
    end;
    Runtime:=TEmulatorRuntimeManager.Create(Repo,'b1008',TB1008ContentValidator.Create);
    Check(Runtime.Reload(Status),Status);
    for M in TB1008Berneo.Mobs do begin
      Target:=Default(TEmulatorSpawnDefinition);
      // Exercise the actual original-client threshold for every species,
      // including the large Swampy/Sprinter models, not just point-blank hits.
      CombatOffset:=M.ClientRadius+B1008PlayerMeleeReach;
      if M.Definition.MobID=120 then CombatOffset:=Max(18.0,CombatOffset);
      if M.ClientID=1005002 then CombatOffset:=Max(26.0,CombatOffset);
      for G in TB1008Berneo.Groups do if G.MobID=M.Definition.MobID then begin Target:=G;Break;end;
      Store:=TB1008CharacterStore.Create;Loot:=TB1008LootStore.Create('',FixtureRates);Quests:=TB1008QuestStore.Create;
      Session:=TEmulatorSession.Create(blMapLoadingProbe,Store,nil,Quests,Runtime,Loot,12345,67890);
      P:=TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0);
      Session.HandlePacket(P,Replies);
      P:=TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
        72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);
      Session.HandlePacket(P,Replies);
      P:=TBytes.Create(2,4,1,2,3,4,0,0,0,1,0,0,0,0);Session.HandlePacket(P,Replies);
      P:=nil;SetLength(P,28);P[0]:=4;BE(P,2,2);BE(P,7,1);
      V:=Target.X+CombatOffset;Move(V,P[11],4);V:=Target.Z;Move(V,P[15],4);V:=Target.Y;Move(V,P[19],4);
      Session.HandlePacket(P,Replies);Check(Length(Replies)=3+Length(TB1008Npcs.All)+3*101,'Loading burst does not contain all NPCs and spider groups');
      FillChar(Known,SizeOf(Known),0);Observe;
      Check(Known[159] and Known[158],
        'Weapon/armor merchant activation missing from the real runtime');
      Quests.Accept(Session);BeforeEXP:=Loot.Progress(Session).TotalEXP;
      Tick:=GetTickCount64+300;Admitted:=M.Definition.MobID=120;
      for I:=1 to 80 do begin
        Session.PollWorld(Tick,Replies);Observe;Adds:=0;
        for Reply in Replies do if (Length(Reply)=200) and (Reply[0]=4) and (Reply[1]=2) then begin
          Inc(Adds);if LE(Reply,8)=Target.EntityHandle then Admitted:=True;
        end;
        Check(Adds<=8,'Unbounded visibility admission');
      end;
      Check(Admitted,'Target never entered interest area');
      Hits:=0;BeforeHP:=M.Definition.MaxHP;
      repeat
        Inc(Hits);P:=nil;SetLength(P,53);P[0]:=5;BE(P,2,100+Hits*2);BE(P,7,1);BE(P,12,521);
        V:=Target.X+CombatOffset;Move(V,P[16],4);V:=Target.Z;Move(V,P[20],4);V:=Target.Y;Move(V,P[24],4);
        P[32]:=1;BE(P,33,Target.EntityHandle);V:=Target.X;Move(V,P[37],4);
        V:=Target.Z;Move(V,P[41],4);V:=Target.Y;Move(V,P[45],4);
        if (Hits=1) and (M.ClientID=1005002) then begin
          // 05/00 reaches us before the stop report. The old code compared
          // against From and rejected this valid 20-unit approach.
          Q:=TB1008World.BuildActorMovement(99,0,1,1,
            Target.X+CombatOffset+20,Target.Z,Target.Y,Target.X+CombatOffset,Target.Z,Target.Y,0);
          Session.HandlePacket(Q,Replies);
          Check(Abs(Session.WorldState.Position.X-(Target.X+CombatOffset+20))<0.01,'Saved unreached destination');
          // A recent segment must NOT bypass the radius-aware upper bound.
          Q:=Copy(P);V:=Target.X+Ceil(Max(M.PlayerMeleeRange,
            M.ClientRadius+B1008PlayerMeleeReach)*B1008PlayerMeleeRangeScale)+1;Move(V,Q[16],4);
          Description:=Session.HandlePacket(Q,Replies);
          Check((Length(Replies)=0) and (Pos('ground range',Description)>0),'Melee admission has no upper bound');
          Check(Abs(Session.WorldState.Position.X-(Target.X+CombatOffset+20))<0.01,'Rejected attack changed position');
        end;
        Description:=Session.HandlePacket(P,Replies);Check(Length(Replies)>0,'Start rejected: '+Description);
        if Hits=1 then Check((Length(Replies)=2) and (Replies[0][0]=4) and
          (Replies[0][1]=1) and (Replies[0][7]=2),'First accepted attack failed to cancel patrol');
        Q:=nil;SetLength(Q,38);Q[0]:=5;Q[1]:=1;BE(Q,2,101+Hits*2);BE(Q,7,1);BE(Q,12,521);
        Move(P[16],Q[16],16);Q[32]:=1;Q[33]:=1;BE(Q,34,Target.EntityHandle);
        Description:=Session.HandlePacket(Q,Replies);
        Check(Pos('HIT ACCEPTED',Description)>0,'Impact rejected: '+Description);
        Damage:=LE(Replies[0],23);
        Check(Replies[0][22] in [0,2,5,6],'Unsupported hit outcome');
        if Replies[0][22] in [5,6] then begin
          Check((Damage=0) and (LE(Replies[1],11)=Cardinal(BeforeHP)),
            'MISS/FAIL changed HP');
          Check((Length(Replies)=2) and (Loot.Progress(Session).TotalEXP=BeforeEXP) and
            (Quests.Progress(Session)=0) and (Loot.Fletta(Session).Total=0),
            'MISS/FAIL granted kill rewards or extra effects');
          if Replies[0][22]=5 then Inc(Misses) else Inc(Fails);
        end else Check(Damage>=1,'Connected hit emitted zero damage');
        Check(LE(Replies[1],11)=Cardinal(Max(0,BeforeHP-Damage)),'Packet damage and committed HP differ');
        BeforeHP:=LE(Replies[1],11);
        Check(LE(Replies[0],23)<=Cardinal(TB1008MonsterBalance.PhysicalDamage(28,M.Definition.PhysicalDefense)),
          'Session ignored monster armor');
        if Replies[0][22] in [5,6] then begin
          Description:=Session.HandlePacket(Q,Replies);
          Check((Length(Replies)=0) and (Pos('no pending',Description)>0),
            'MISS/FAIL impact could be rerolled');
        end;
      // Lv1 versus the strongest mob can fail 95% of swings and deal 1 HP.
      // Fixed RNG seed; bound at twice the expected attempts for that worst case.
      until (Loot.Progress(Session).TotalEXP>BeforeEXP) or (Hits=M.Definition.MaxHP*40);
      Check(Loot.Progress(Session).TotalEXP-BeforeEXP=M.BaseEXP,'Wrong species EXP');
      Check(Quests.Progress(Session)=Cardinal(Ord(M.Definition.MobID=120)),'Non-spider credited to spider quest');
      Check(Loot.Fletta(Session).Total=TB1008Fletta.KillGain(1,M.Level),'Wrong mob level in Fletta');
      BeforeEXP:=Loot.Progress(Session).TotalEXP;Session.HandlePacket(Q,Replies);
      Check(Loot.Progress(Session).TotalEXP=BeforeEXP,'Duplicate lethal impact rewarded twice');
      // High failure rates make offline combat longer than the old 3s window.
      // Corpse/respawn delays must start after the actual lethal impact.
      Tick:=GetTickCount64;
      Session.PollWorld(Tick+3000,Replies);Observe;
      Check(not Known[Target.EntityHandle],'Corpse never removed');
      Session.PollWorld(Tick+20000,Replies);Observe;Respawned:=False;
      for Reply in Replies do if (Length(Reply)=200) and (LE(Reply,8)=Target.EntityHandle) then begin
        Check(LE(Reply,28)=Cardinal(M.Definition.MaxHP),'Respawn HP changed species');Respawned:=True;
      end;
      Check(Respawned,'Species never respawned');
      Writeln('PASS: ',M.Definition.Name,' Lv',M.Level,' admission/combat/EXP/Fletta/quest guard');
      FreeAndNil(Session);FreeAndNil(Quests);FreeAndNil(Loot);FreeAndNil(Store);
    end;
    Check((Misses>0) and (Fails>0),'Full-session combat never exercised both MISS and FAIL');
    Writeln('PASS: 955 unique actors; 18 full-session combat scenarios, MISS=',Misses,' FAIL=',Fails);
    // Real default AI settings in an offline session; simulate 10 minutes without sleeping.
    for M in TB1008Berneo.Mobs do begin
      Snap.TryGetMob(M.Definition.MobID,Def);Def.MovementSpeed:=15;Repo.PublishMob(Def);
    end;
    Check(Runtime.Reload(Status),Status);
    Store:=TB1008CharacterStore.Create;Session:=TEmulatorSession.Create(blMapLoadingProbe,Store,nil,nil,Runtime);
    P:=TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0);Session.HandlePacket(P,Replies);
    P:=TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);Session.HandlePacket(P,Replies);
    P:=TBytes.Create(2,4,1,2,3,4,0,0,0,1,0,0,0,0);Session.HandlePacket(P,Replies);
    P:=nil;SetLength(P,28);P[0]:=4;BE(P,2,2);BE(P,7,1);
    V:=8890;Move(V,P[11],4);V:=6705;Move(V,P[15],4);V:=627;Move(V,P[19],4);
    Session.HandlePacket(P,Replies);FillChar(Known,SizeOf(Known),0);Observe;
    Tick:=GetTickCount64;Packets:=0;Watch:=TStopwatch.StartNew;
    for I:=1 to 6000 do begin
      if I mod 300=0 then begin
        G:=TB1008Berneo.Groups[(I div 300) mod Length(TB1008Berneo.Groups)];
        P:=TB1008World.BuildActorMovement(I,0,2,1,G.X,G.Z,G.Y,G.X,G.Z,G.Y,0);
        Session.HandlePacket(P,Replies);Observe;
      end;
      Session.PollWorld(Tick+UInt64(I)*100,Replies);Observe;Inc(Packets,Length(Replies));
    end;
    Writeln('PASS: 955-actor scheduler, 600 simulated seconds / ',Watch.ElapsedMilliseconds,' ms CPU wall, ',Packets,' nearby packets');
  finally
    Session.Free;Quests.Free;Loot.Free;Store.Free;Runtime.Free;Repo:=nil;Snap:=nil;
    TDirectory.Delete(Dir,True);
  end;
end;
begin
  try CombatCalibration;MovementAdmission;Distribution;Run;Writeln('ALL BERNEO TESTS PASSED');
  except on E:Exception do begin Writeln(E.ClassName+': '+E.Message);Halt(1);end;end;
end.
