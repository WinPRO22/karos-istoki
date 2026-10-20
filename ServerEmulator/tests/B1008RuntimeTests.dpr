program B1008RuntimeTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils, Winapi.Windows,
  Emulator.Content, Emulator.Repository, Emulator.Repository.SQLite,
  Emulator.Runtime, Emulator.Server, Emulator.Login.B1008,
  Emulator.Session, Emulator.Character.B1008, Emulator.Protocol.B1008,
  Emulator.World.B1008,Emulator.Npcs.B1008;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure DeleteDatabaseFiles(const APath: string);
begin
  if FileExists(APath) then
    TFile.Delete(APath);
  if FileExists(APath+'-wal') then
    TFile.Delete(APath+'-wal');
  if FileExists(APath+'-shm') then
    TFile.Delete(APath+'-shm');
end;

procedure PutBE32(var AData: TBytes; AOffset: Integer; AValue: Cardinal);
begin
  AData[AOffset] := Byte(AValue shr 24);
  AData[AOffset+1] := Byte(AValue shr 16);
  AData[AOffset+2] := Byte(AValue shr 8);
  AData[AOffset+3] := Byte(AValue);
end;

function RegenPacket: TBytes;
var
  Value: Single;
begin
  SetLength(Result,28); Result[0]:=4; Result[1]:=0;
  PutBE32(Result,2,2); PutBE32(Result,7,1);
  Value:=8674.279; Move(Value,Result[11],4);
  Value:=6660.197; Move(Value,Result[15],4);
  Value:=607.879; Move(Value,Result[19],4);
  Value:=0; Move(Value,Result[23],4);
end;

function AttackPacket: TBytes;
var
  Value: Single;
begin
  SetLength(Result,53); Result[0]:=5; Result[1]:=0;
  PutBE32(Result,2,3); PutBE32(Result,7,1); PutBE32(Result,12,521);
  Value:=8674.279; Move(Value,Result[16],4);
  Value:=6660.197; Move(Value,Result[20],4);
  Value:=607.879; Move(Value,Result[24],4);
  Value:=0; Move(Value,Result[28],4);
  Result[32]:=1; PutBE32(Result,33,120);
  Value:=8669.776367; Move(Value,Result[37],4);
  Value:=6668.010254; Move(Value,Result[41],4);
  Value:=607.174; Move(Value,Result[45],4);
  Value:=0; Move(Value,Result[49],4);
end;

function DecidePacket(const AStart: TBytes): TBytes;
begin
  SetLength(Result,38); Result[0]:=5; Result[1]:=1;
  PutBE32(Result,2,TB1008Wire.ReadBE32(AStart,2)+1);
  Result[6]:=AStart[6]; PutBE32(Result,7,TB1008Wire.ReadBE32(AStart,7));
  Result[11]:=AStart[11]; PutBE32(Result,12,TB1008Wire.ReadBE32(AStart,12));
  Move(AStart[16],Result[16],16);
  Result[32]:=AStart[32]; Result[33]:=1;
  PutBE32(Result,34,TB1008Wire.ReadBE32(AStart,33));
end;

procedure Run;
var
  ID: TGUID;
  DirectoryPath, DatabasePath, Status: string;
  Repository: IEmulatorContentRepository;
  Runtime: TEmulatorRuntimeManager;
  OldSnapshot, NewSnapshot: IEmulatorContentSnapshot;
  Mob: TEmulatorMobDefinition;
  Spawn: TEmulatorSpawnDefinition;
  OldRevision, PublishedRevision: Int64;
  Server: TEmulatorServer;
  ServerPort: Word;
  Store: TB1008CharacterStore;
  Session: TEmulatorSession;
  Replies: TB1008Replies;
  Packet: TBytes;
  PackedValue: Integer;
  Speed: Single;
  Failed: Boolean;
  BaseTick: UInt64;
  Description: string;
  Found: Boolean;
  Seen: array[0..B1008GeneratedSpiderHandleLast] of Boolean;
  ActorHandle: Cardinal;
  Npc:TB1008Npc;
  NpcCount:Integer;
  EventCount, I, J, GroupIndex, RuntimeIndex: Integer;
  CenterX, CenterZ, RuntimeX, RuntimeZ: Single;
  GroupDistance, MaxGroupDistance: Double;
begin
  CreateGUID(ID);
  DirectoryPath := TPath.Combine(TPath.GetTempPath,
    'karos-runtime-'+Copy(GUIDToString(ID), 2, 36));
  ForceDirectories(DirectoryPath);
  DatabasePath := TPath.Combine(DirectoryPath, 'content.sqlite3');
  Runtime := nil;
  Server := nil;
  Store := nil;
  Session := nil;
  try
    Repository := TSQLiteContentRepository.Create(DatabasePath);
    Runtime := TEmulatorRuntimeManager.Create(Repository, 'b1008');
    Check(Runtime.Reload(Status), 'Initial reload failed: '+Status);
    Check(Runtime.Loaded and (Runtime.Revision=1), 'Initial revision');
    OldSnapshot := Runtime.AcquireSnapshot;
    Check((OldSnapshot.MobCount=1) and (OldSnapshot.SpawnCount=10),
      'Initial content counts');
    Check(OldSnapshot.TryGetMob(120, Mob), 'Little Spider is missing');
    Check((Mob.Name='Little Spider') and (Mob.MaxHP=500) and
      (Mob.AttackDamage=10) and (Abs(Mob.AttackSpeed-1.0)<0.001) and
      (Abs(Mob.MovementSpeed-12.0)<0.001) and
      (Abs(Mob.ChaseSpeed-32.0)<0.001) and
      (Abs(Mob.PatrolRadius-22.0)<0.001) and
      (Abs(Mob.LeashRadius-60.0)<0.001) and
      (Mob.RespawnMS=15000) and
      not Mob.Aggressive, 'Little Spider seed');
    Check(OldSnapshot.TryGetSpawn(120, Spawn), 'Little Spider spawn is missing');
    Check((Spawn.MapID=19003) and (Spawn.EntityHandle=120) and
      (Abs(Spawn.X-8669.776367)<0.01) and (Spawn.Population=5) and
      (Abs(Spawn.SpawnRadius-150)<0.001), 'Little Spider spawn seed');
    Check(OldSnapshot.TryGetSpawn(119, Spawn) and
      (Spawn.EntityHandle=119) and (Abs(Spawn.X-8246.011719)<0.01),
      'Second Little Spider spawn seed');

    OldRevision := OldSnapshot.Revision;
    Mob.MaxHP := 777;
    PublishedRevision := Repository.PublishMob(Mob);
    Check(PublishedRevision=OldRevision+1, 'Published revision did not advance');
    Check(OldSnapshot.TryGetMob(120, Mob) and (Mob.MaxHP=500),
      'Published change mutated active immutable snapshot');
    Check(Runtime.Reload(Status), 'Second reload failed: '+Status);
    NewSnapshot := Runtime.AcquireSnapshot;
    Check((NewSnapshot.Revision=PublishedRevision) and
      NewSnapshot.TryGetMob(120, Mob) and (Mob.MaxHP=777),
      'Reload did not atomically expose published content');
    Check(OldSnapshot.TryGetMob(120, Mob) and (Mob.MaxHP=500),
      'Old snapshot changed after atomic swap');

    Mob := Default(TEmulatorMobDefinition);
    NewSnapshot.TryGetMob(120, Mob);
    Mob.MaxHP := 0;
    Failed := False;
    try
      Repository.PublishMob(Mob);
    except
      on E: EEmulatorContent do
        Failed := True;
    end;
    Check(Failed, 'Invalid mob content was published');
    Check(Runtime.Revision=PublishedRevision,
      'Rejected content changed active revision');

    Server := TEmulatorServer.Create(emB1008, blObserveOnly, '', DatabasePath,False);
    Check(Server.ReloadContent(Status), 'Server initial content load failed: '+Status);
    Check(Server.ContentRevision=PublishedRevision, 'Server loaded wrong revision');
    Server.Start(0);
    ServerPort := Server.Port;
    Check(Server.Running and (ServerPort<>0), 'Runtime-enabled server did not start');
    Store:=TB1008CharacterStore.Create;
    Session:=TEmulatorSession.Create(blMapLoadingProbe,Store,nil,nil,Runtime);
    Packet:=TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,
      116,101,115,116,0,0);
    Session.HandlePacket(Packet,Replies);
    Packet:=TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
      72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);
    Session.HandlePacket(Packet,Replies);
    Packet:=TBytes.Create(2,4,1,2,3,4,0,0,0,1,0,0,0,0);
    Session.HandlePacket(Packet,Replies);

    NewSnapshot.TryGetMob(120, Mob);
    Mob.MaxHP := 888;
    Mob.AttackDamage := 37;
    Mob.AttackSpeed := 1.25;
    PublishedRevision := Repository.PublishMob(Mob);
    Check(PublishedRevision=NewSnapshot.Revision+1,
      'Published live mob revision did not advance');
    Check(NewSnapshot.TryGetSpawn(120, Spawn), 'Live spawn disappeared');
    Spawn.X := Spawn.X+2;
    Spawn.Z := Spawn.Z+1;
    Spawn.Heading := 0.5;
    PublishedRevision := Repository.PublishSpawn(Spawn);
    Check(PublishedRevision>OldRevision,
      'Published spawn revision did not advance');
    Check(NewSnapshot.TryGetSpawn(120, Spawn) and
      (Abs(Spawn.X-8669.776367)<0.01),
      'Published spawn change mutated active immutable snapshot');
    Spawn.X := 8671.776367;
    Spawn.Z := 6669.010254;
    Spawn.Heading := 0.5;
    Check(Server.ReloadContent(Status), 'Live server reload failed: '+Status);
    Check(Runtime.Reload(Status), 'Session runtime reload failed: '+Status);
    Check(Server.Running and (Server.Port=ServerPort) and
      (Server.ContentRevision=PublishedRevision),
      'Content reload restarted or changed the live listener');
    Session.HandlePacket(RegenPacket,Replies);
    Check(Length(Replies)=2+Length(TB1008Npcs.All)+3*B1008SpiderPopulationCount,
      'Runtime session did not expand spider groups and the complete NPC roster');
    for Npc in TB1008Npcs.All do begin
      NpcCount:=0;
      for I:=0 to High(Replies) do if (Length(Replies[I])=200) and
        (Replies[I][0]=4) and (Replies[I][1]=2) and (PCardinal(@Replies[I][8])^=Npc.Handle) then Inc(NpcCount);
      Check(NpcCount=1,'NPC appearance missing or duplicated: '+Npc.Name);
    end;
    RuntimeIndex:=4+Length(B1008SpiderHandles);
    for GroupIndex:=Low(B1008SpiderHandles) to High(B1008SpiderHandles) do
    begin
      Move(Replies[4+GroupIndex][12],CenterX,4);
      Move(Replies[4+GroupIndex][16],CenterZ,4);
      MaxGroupDistance:=0;
      for J:=1 to B1008SpiderGroupPopulations[GroupIndex]-1 do
      begin
        Move(Replies[RuntimeIndex][8],ActorHandle,4);
        Check(ActorHandle=Cardinal(B1008GeneratedSpiderHandleBase+
          RuntimeIndex-(4+Length(B1008SpiderHandles))),
          'Generated spider handle order is unstable');
        Move(Replies[RuntimeIndex][$46],ActorHandle,4);
        Check(ActorHandle=B1008SpiderHandles[GroupIndex],
          'Generated spider does not reference a renderable source template');
        Move(Replies[RuntimeIndex][12],RuntimeX,4);
        Move(Replies[RuntimeIndex][16],RuntimeZ,4);
        GroupDistance:=Sqrt(Sqr(RuntimeX-CenterX)+Sqr(RuntimeZ-CenterZ));
        if GroupDistance>MaxGroupDistance then MaxGroupDistance:=GroupDistance;
        Inc(RuntimeIndex);
      end;
      Check(Abs(MaxGroupDistance-B1008SpiderGroupRadii[GroupIndex])<0.02,
        Format('Generated group %d does not reach its source radius',
          [B1008SpiderHandles[GroupIndex]]));
    end;
    Check(RuntimeIndex=4+B1008SpiderPopulationCount,'Generated spider population mismatch');
    Check((Replies[9][8]=120) and (Length(Replies[9])=200),
      'Runtime spider order or count is invalid');
    Move(Replies[9][28],PackedValue,4);
    Check(PackedValue=888, 'Reloaded maximum HP did not reach appearance');
    Move(Replies[9][52],Speed,4);
    Check(Abs(Speed-1.25/1.4)<0.001, 'Global 140% attack cycle did not reach appearance');
    Move(Replies[9][12],Speed,4);
    Check(Abs(Speed-Spawn.X)<0.001, 'Reloaded spawn X did not reach appearance');
    Move(Replies[9][24],Speed,4);
    Check(Abs(Speed-Spawn.Heading)<0.001,
      'Reloaded spawn heading did not reach appearance');
    Packet:=AttackPacket;
    Speed:=Spawn.X; Move(Speed,Packet[37],4);
    Speed:=Spawn.Z; Move(Speed,Packet[41],4);
    Session.HandlePacket(Packet,Replies);
    Check(Length(Replies)=2,
      'Runtime first combat batch is missing the immediate patrol stop');
    Check((Replies[0][0]=4) and (Replies[0][1]=1) and (Replies[0][7]=2),
      'Runtime immediate patrol stop is invalid');
    Packet:=DecidePacket(Packet);
    Session.HandlePacket(Packet,Replies);
    Check(Length(Replies)=2,'Runtime matching impact did not commit');
    Move(Replies[1][15],PackedValue,4);
    Check(PackedValue=888, 'Reloaded maximum HP did not reach combat gage');
    Move(Replies[1][35],Speed,4);
    Check(Abs(Speed-1.25/1.4)<0.001,'Combat gage restored unscaled speed');
    Move(Replies[0][31],Speed,4);
    Check(Abs(Speed-Spawn.X)<0.001,
      'Reloaded spawn X did not reach damage result');

    Mob.MaxHP:=22; // One configured normal hit in the reconstruction profile.
    Mob.RespawnMS:=0;
    Repository.PublishMob(Mob);
    Check(Runtime.Reload(Status), 'Respawn content reload failed: '+Status);
    Packet:=AttackPacket;
    PutBE32(Packet,2,5);
    Speed:=Spawn.X; Move(Speed,Packet[37],4);
    Speed:=Spawn.Z; Move(Speed,Packet[41],4);
    Session.HandlePacket(Packet,Replies);
    Check(Length(Replies)=1, 'Live lethal attack start was not accepted');
    Packet:=DecidePacket(Packet);
    Session.HandlePacket(Packet,Replies);
    Check(Length(Replies)=2, 'Live maximum HP did not make the impact lethal');
    BaseTick:=GetTickCount64;
    Check(Pos('SPIDER DESPAWN',Session.PollWorld(BaseTick+10000,Replies))>0,
      'Session did not produce the scheduled despawn');
    Found:=False;
    for I:=0 to High(Replies) do
      if (Length(Replies[I])=11) and (Replies[I][0]=4) and
        (Replies[I][1]=3) and (TB1008Wire.ReadBE32(Replies[I],7)=120) then
        Found:=True;
    Check(Found,'Despawn packet is invalid');
    Check(Pos('SPIDER RESPAWN',Session.PollWorld(BaseTick+20000,Replies))>0,
      'Session did not produce the scheduled respawn');
    Found:=False; J:=-1;
    for I:=0 to High(Replies) do
      if (Length(Replies[I])=200) and
        (Cardinal(PCardinal(@Replies[I][8])^)=120) then
      begin Found:=True; J:=I; Break; end;
    Check(Found,'Respawn appearance batch is invalid');
    Move(Replies[J][28],PackedValue,4);
    Check(PackedValue=22, 'Respawn did not use current live maximum HP');
    Found:=False;
    for I:=0 to 1000 do
    begin
      Description:=Session.PollWorld(BaseTick+23000+UInt64(I)*10,Replies);
      for J:=0 to High(Replies) do
        if (Length(Replies[J])=42) and (Replies[J][0]=4) and
          (Replies[J][1]=1) and (Replies[J][6]=1) and
          (Replies[J][7]=1) and
          (TB1008Wire.ReadBE32(Replies[J],8)=120) then
        begin Found:=True; Break; end;
      if Found then Break;
    end;
    Check(Found, 'Handle 120 did not resume valid patrol after respawn');

    OldRevision:=Server.ContentRevision;
    Spawn.MapID:=1;
    Repository.PublishSpawn(Spawn);
    Check(not Server.ReloadContent(Status),
      'b1008 accepted an incompatible live spawn');
    Check(Server.Running and (Server.Port=ServerPort) and
      (Server.ContentRevision=OldRevision),
      'Rejected b1008 content disturbed the running listener or snapshot');
    Spawn.MapID:=19003;
    Repository.PublishSpawn(Spawn);
    Check(Server.ReloadContent(Status),
      'Server did not recover after compatible content was restored: '+Status);

    FillChar(Seen,SizeOf(Seen),0);
    EventCount:=0;
    for I:=0 to 6000 do
    begin
      Description:=Session.PollWorld(BaseTick+40000+UInt64(I)*10,Replies);
      for J:=0 to High(Replies) do
        if (Length(Replies[J])=42) and (Replies[J][0]=4) and
          (Replies[J][1]=1) and (Replies[J][6]=1) then
        begin
          ActorHandle:=TB1008Wire.ReadBE32(Replies[J],8);
          if ActorHandle<=High(Seen) then Seen[ActorHandle]:=True;
          Inc(EventCount);
        end;
    end;
    for J:=Low(B1008SpiderHandles) to High(B1008SpiderHandles) do
      Check(Seen[B1008SpiderHandles[J]],Format(
        'Patrol scheduler starved spider handle %d',[B1008SpiderHandles[J]]));
    for ActorHandle:=B1008GeneratedSpiderHandleBase to
      B1008GeneratedSpiderHandleLast do
      Check(Seen[ActorHandle],Format(
        'Patrol scheduler starved generated spider handle %d',[ActorHandle]));
    Check(EventCount>=400,
      '101-spider scheduler produced too few patrol events');
    Server.Stop;
  finally
    OldSnapshot := nil;
    NewSnapshot := nil;
    Session.Free;
    Store.Free;
    Runtime.Free;
    Server.Free;
    Repository := nil;
    DeleteDatabaseFiles(DatabasePath);
    if DirectoryExists(DirectoryPath) then
      RemoveDir(DirectoryPath);
  end;
end;

begin
  try
    Run;
    Writeln('PASS: SQLite migration, validation, revision and atomic live reload');
  except
    on E: Exception do
    begin
      Writeln('FAIL: '+E.Message);
      Halt(1);
    end;
  end;
end.
