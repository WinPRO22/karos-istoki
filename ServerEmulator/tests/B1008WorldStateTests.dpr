program B1008WorldStateTests;
{$APPTYPE CONSOLE}
{$R+}
{$Q+}
uses System.SysUtils, System.IOUtils, Winapi.Windows,
  Emulator.WorldState.B1008, Emulator.World.B1008, Emulator.Character.B1008,
  Emulator.Protocol.B1008, Emulator.Login.B1008, Emulator.Session,
  Emulator.Server, IdTCPClient, IdGlobal, Emulator.Combat.B1008,
  Emulator.Fletta.B1008;

procedure Check(B: Boolean; const Msg: string);
begin if not B then raise Exception.Create(Msg); end;

function Hero: TBytes;
begin Result := TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
  72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0); end;
function Login: TBytes;
begin Result := TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0); end;
function Play: TBytes;
begin Result := TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0); end;
function Regen: TBytes;
begin Result := TBytes.Create(4,0,0,0,0,1,0,0,0,0,1,
  0,0,$80,$3F,0,0,0,$40,0,0,$40,$40,0,0,$80,$40,0); end;
function Movement(Mode: Byte; X: Single; SameTarget: Boolean = True): TBytes;
var Z,Y,Target: Single;
begin
  Result := nil; SetLength(Result,42); Result[0] := 4; Result[1] := 1;
  Result[7] := Mode; Result[11] := 1;
  Z := 20; Y := 30; Target := X;
  if not SameTarget then Target := X+100;
  Move(X,Result[12],4); Move(Z,Result[16],4); Move(Y,Result[20],4);
  Move(Target,Result[24],4); Move(Z,Result[28],4); Move(Y,Result[32],4);
end;
function FloatAt(const P: TBytes; Offset: Integer): Single;
begin Move(P[Offset],Result,4); end;
procedure Enter(S: TEmulatorSession; out Replies: TB1008Replies);
begin S.HandlePacket(Login,Replies); S.HandlePacket(Play,Replies); S.HandlePacket(Regen,Replies); end;

procedure PickupAdmissionTests;
var A:TB1008MovementAdmission;M:TB1008Movement;
begin
  A:=Default(TB1008MovementAdmission);M:=Default(TB1008Movement);
  M.Kind:=0;M.CharacterID:=1;M.Mode:=1;
  M.FromX:=7588.736;M.FromZ:=8134.582;M.ToX:=7581.665;M.ToZ:=8101.099;
  A.Observe(M,1000);
  Check(A.AllowsPickup(M.ToX,M.ToZ,30,75,1074),'Live pickup before stop report rejected');
  Check(not A.AllowsPickup(M.ToX,M.ToZ,30,75,999),'Pickup clock rollback');
  Check(not A.AllowsPickup(M.ToX,M.ToZ,30,75,3001),'Expired pickup movement');
  Check(not A.AllowsPickup(M.ToX+100,M.ToZ,30,75,1074),'Off-path pickup');
  M.FromX:=0;M.FromZ:=0;M.ToX:=1000;M.ToZ:=0;A.Observe(M,1000);
  Check(not A.AllowsPickup(1000,0,30,75,1074),'Unreached destination grants distant loot');
  Check(not A.AllowsPickup(-40,0,30,75,1500),'Movement away grants loot');
  Check(not A.AllowsPickup(50,0,30,75,1074),'Unreachable segment prefix');
  Check(A.AllowsPickup(50,0,30,75,1500),'Reachable prefix rejected');
  A.Reset;Check(not A.AllowsPickup(5,0,30,75,1500),'Stopped movement still admits pickup');
  M.Mode:=2;A.Observe(M,1000);
  Check(not A.AllowsPickup(5,0,30,75,1500),'Stop report opened movement window');
  Writeln('PASS: pickup path admission, recorded 74 ms race, reach/direction/time bounds and stop');
end;

procedure TestRunSpeedTests;
var A:TB1008MovementAdmission;M:TB1008Movement;F:TB1008FlettaAttributes;
  P,Preview:TBytes;
begin
  A:=Default(TB1008MovementAdmission);M:=Default(TB1008Movement);
  F:=Default(TB1008FlettaAttributes);
  M.Kind:=0;M.CharacterID:=1;M.Mode:=1;M.ToX:=1000;
  A.Observe(M,1000);
  Check(not A.Allows(900,0,0,1400),'Normal movement admits screenshot speed');
  ConfigureB1008TestPlayerSpeed(20);
  try
    Preview:=TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(Hero),1);
    P:=TB1008World.BuildCharacterInfoProbe(Preview,1);F.ApplySpeeds(P);
    Check((FloatAt(P,$24)=1500) and (FloatAt(P,$28)=3000),'Login lost temporary speed');
    P:=TB1008World.BuildAppearProbe(Preview,TB1008World.ParseRegen(Regen));F.ApplySpeeds(P);
    Check((FloatAt(P,44)=1500) and (FloatAt(P,48)=3000),'Appearance lost temporary speed');
    P:=TB1008CombatWire.BuildPlayerGageProbe(1,100,50);F.ApplySpeeds(P);
    Check((FloatAt(P,27)=1500) and (FloatAt(P,31)=3000) and
      (FloatAt(P,35)=1),'Gage lost temporary speed or accelerated attacks');
    Check(A.Allows(900,0,0,1400),'Valid accelerated movement rejected');
    Check(not A.Allows(900,100,0,1400),'Speed override bypassed path bounds');
    Check(A.AllowsPickup(900,0,30,B1008PlayerSpeedB,1400),'Accelerated pickup rejected');
    P:=TB1008World.BuildSpiderAppearProbe(1);
    Check((FloatAt(P,44)=150) and (FloatAt(P,48)=300),'Player override changed mob speed');
  finally ConfigureB1008TestPlayerSpeed(1);end;
  Check(not A.Allows(900,0,0,1400),'Normal movement was not restored');
  Writeln('PASS: temporary x20 login/appearance/gage, movement/pickup bounds, unchanged attack/mob speeds, reset');
end;

procedure SessionTests;
var W: TB1008WorldStore; C: TB1008CharacterStore; A,B: TEmulatorSession;
  Replies: TB1008Replies; P,Before: TBytes; Desc: string; T: UInt64;
begin
  W := TB1008WorldStore.Create; C := TB1008CharacterStore.Create;
  A := nil; B := nil;
  try
    C.CreateCharacter(Hero,P); Before := C.Preview(0);
    A := TEmulatorSession.Create(blMapLoadingProbe,C,W);
    B := TEmulatorSession.Create(blMapLoadingProbe,C,W);
    A.HandlePacket(Movement(2,10),Replies);
    Check(not A.WorldState.Active,'Early movement mutated state');
    Enter(A,Replies);
    Check(A.WorldState.Active and not A.WorldState.Restored and
      (A.WorldState.Position.X=1),'Initial session position');
    Check(Replies[0][6]=1,'Fresh appearance must initialize native idle');
    B.HandlePacket(Login,Replies);
    Desc := B.HandlePacket(Play,Replies);
    Check((Length(Replies)=0) and (Pos('another world session',Desc)>0),'Concurrent world entry');
    A.HandlePacket(Movement(1,10,False),Replies);
    Check(A.WorldState.Moving and (A.WorldState.Position.X=10) and
      not A.WorldState.HasCheckpoint,'Target saved as reached');
    A.HandlePacket(Movement(2,11,False),Replies);
    Check(A.WorldState.Moving and not A.WorldState.HasCheckpoint,'Inconsistent stop saved');
    P := Movement(2,12); P[11] := 2; A.HandlePacket(P,Replies);
    Check(A.WorldState.Position.X=10,'Wrong ID changed world state');
    A.HandlePacket(Movement(8,13),Replies);
    Check(A.WorldState.Position.X=10,'Unknown mode changed world state');
    Desc := A.HandlePacket(Movement(2,14),Replies);
    Check((Pos('checkpoint committed',Desc)>0) and (Length(Replies)=0) and
      not A.WorldState.Moving and A.WorldState.HasCheckpoint,'Stop not committed/no echo');
    A.HandlePacket(Movement(1,15,False),Replies); // Disconnect mid-route.
    A.Close; A.Close;
    Check(not A.WorldState.Active,'Closed session still active');
    B.HandlePacket(Play,Replies); B.HandlePacket(Regen,Replies);
    Check(B.WorldState.Restored and (B.WorldState.Position.X=14) and
      (FloatAt(Replies[0],12)=14) and (FloatAt(Replies[0],24)=4) and (Replies[0][6]=1),
      'Restore did not use last STOP/initial heading');
    for P in Replies do Check(not ((P[0]=4) and (P[1]=1) and (P[6]=0)),
      'Movement reset must not enter appearance/loading batch');
    T:=GetTickCount64;
    B.PollWorld(T+500,Replies); Check(Length(Replies)=0,'Early restore reset');
    B.PollWorld(T+1500,Replies);
    for P in Replies do Check(not ((P[0]=4) and (P[1]=1) and (P[6]=0)),
      'Unexpected self correction during loading');
    B.PollWorld(T+2100,Replies);
    for P in Replies do Check(not ((P[0]=4) and (P[1]=1) and (P[6]=0)),
      'Appearance idle must not be followed by a delayed self correction');
    Check((B.WorldState.Position.X=14) and (B.WorldState.Position.Z=20) and
      (B.WorldState.Position.Y=30) and not B.WorldState.Moving,
      'Idle polling changed the saved checkpoint');
    B.PollWorld(T+2101,Replies);
    for P in Replies do Check(not ((P[0]=4) and (P[1]=1) and (P[6]=0)),
      'Duplicate restore reset');
    P := C.Preview(0);
    Check(CompareMem(@P[0],@Before[0],Length(P)),'World state changed character preview');
    FreeAndNil(B); // Destructor releases lease too.
    B := TEmulatorSession.Create(blMapLoadingProbe,C,W); Enter(B,Replies);
    Check(B.WorldState.Active,'Destructor did not release world lease');
    B.HandlePacket(Movement(2,16),Replies); T:=GetTickCount64;
    B.PollWorld(T+2100,Replies);
    for P in Replies do Check(not ((P[0]=4) and (P[1]=1) and (P[6]=0)),
      'Self correction interrupted player movement');
    B.HandlePacket(Movement(1,17,False),Replies);
    Check((Length(Replies)=0) and B.WorldState.Moving,'Movement after idle entry not admitted');
    B.PollWorld(T+5000,Replies);
    for P in Replies do Check(not ((P[0]=4) and (P[1]=1) and (P[6]=0)),
      'Delayed correction snapped back an already moving player');
  finally A.Free; B.Free; C.Free; W.Free; end;
  Writeln('PASS: session state, exclusive world owner, from-not-target, stop-only checkpoint, reconnect, no echo, immutable hero');
end;

procedure DiskTests;
var Dir,Path: string; G: TGUID; W,Other: TB1008WorldStore; Owner,Intruder: TObject;
  Preview,Saved,Bad: TBytes; P,R: TB1008Position; Failed: Boolean; H: THandle;
begin
  CreateGUID(G); Dir := TPath.Combine(TPath.GetTempPath,'KarosWorld-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir); Path := TPath.Combine(Dir,'fixture.world');
  W := nil; Other := nil; Owner := TObject.Create; Intruder := TObject.Create;
  try
    Preview := TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(Hero),7);
    W := TB1008WorldStore.Create(Path); Check(W.Acquire(Owner,Preview),'Acquire');
    Failed := False;
    try Other := TB1008WorldStore.Create(Path); except on E: Exception do Failed := True; end;
    Check(Failed,'Second process/store acquired file lock');
    P.X := 9000; P.Z := 6500; P.Y := 627; P.Heading := 0.157;
    Failed := False;
    try W.Checkpoint(Intruder,P); except on E: Exception do Failed := True; end;
    Check(Failed and not FileExists(Path),'Non-owner saved checkpoint');
    W.Checkpoint(Owner,P); Saved := TFile.ReadAllBytes(Path);
    W.Checkpoint(Owner,P); Check(Length(Saved)=96,'Checkpoint size');
    // A handle denying DELETE allows reading but makes atomic replacement fail.
    H := CreateFile(PChar(Path),GENERIC_READ,FILE_SHARE_READ,nil,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
    Win32Check(H<>INVALID_HANDLE_VALUE);
    try
      P.X := 9100; Failed := False;
      try W.Checkpoint(Owner,P); except on E: Exception do Failed := True; end;
      Check(Failed and W.Restore(Owner,R) and (R.X=9000),'Failed write changed memory');
      Bad := TFile.ReadAllBytes(Path); Check(CompareMem(@Bad[0],@Saved[0],96),'Failed write changed disk');
    finally CloseHandle(H); end;
    // Successful replacement, then complete object restart.
    W.Checkpoint(Owner,P); FreeAndNil(W);
    W := TB1008WorldStore.Create(Path); Preview[5] := 99;
    Check(W.Acquire(Owner,Preview) and W.Restore(Owner,R) and (R.X=9100) and
      (R.Z=6500) and (R.Y=627) and (R.Heading=P.Heading),'Disk restart/identity timestamp');
    W.Release(Owner); Bad := Copy(Preview); Bad[15] := 101; Failed := False;
    try W.Acquire(Intruder,Bad); except on E: Exception do Failed := True; end;
    Check(Failed and W.Acquire(Owner,Preview),'Wrong character accepted or failed acquire leaked lease');
    Bad := TFile.ReadAllBytes(Path); Bad[88] := Bad[88] xor 1; TFile.WriteAllBytes(Path,Bad);
    P.X := 9200; Failed := False;
    try W.Checkpoint(Owner,P); except on E: Exception do Failed := True; end;
    Check(Failed and W.Restore(Owner,R) and (R.X=9100),'External edit overwritten');
    FreeAndNil(W); Failed := False;
    try W := TB1008WorldStore.Create(Path); except on E: Exception do Failed := True; end;
    Check(Failed,'Corrupt checkpoint loaded');
    Saved := TFile.ReadAllBytes(Path); Check(CompareMem(@Saved[0],@Bad[0],96),'Corrupt checkpoint erased');
    TFile.Delete(Path);
    W := TB1008WorldStore.Create(Path); Check(W.Acquire(Owner,Preview),'Acquire empty');
    TFile.WriteAllBytes(Path,Saved); Failed := False;
    try W.Checkpoint(Owner,P); except on E: Exception do Failed := True; end;
    Check(Failed and not W.Restore(Owner,R),'External new file overwritten/phantom checkpoint');
    // Reject NaN before any persistence.
    PCardinal(@P.X)^ := $7FC00000; Failed := False;
    try W.Checkpoint(Owner,P); except on E: EKarosProtocol do Failed := True; end;
    Check(Failed,'Non-finite checkpoint accepted');
  finally
    W.Free; Other.Free; Owner.Free; Intruder.Free;
    if FileExists(Path) then TFile.Delete(Path);
    if FileExists(Path+'.lock') then TFile.Delete(Path+'.lock');
    TDirectory.Delete(Dir,False); // Must be empty; leaked temp files fail this test.
  end;
  Writeln('PASS: atomic disk restart, file lock, hero identity, checksum corruption preserved, IO rollback, external edits, NaN, temp cleanup');
end;

procedure NetworkTests;
var Server: TEmulatorServer; Client: TIdTCPClient; Decoder: TB1008FrameDecoder;
  Incoming: TIdBytes; Packet,Ping: TBytes; Pass: Integer;
  procedure Send(const P: TBytes);
  begin Client.IOHandler.Write(TIdBytes(TB1008Wire.Encode(P))); end;
  procedure ReadBytes(N: Integer);
  begin Incoming := nil; Client.IOHandler.ReadBytes(Incoming,N,False); Decoder.Append(TBytes(Incoming)); end;
begin
  Server := TEmulatorServer.Create(emB1008,blMapLoadingProbe);
  Client := TIdTCPClient.Create(nil); Decoder := TB1008FrameDecoder.Create;
  try
    Server.Start(0); Client.Host := '127.0.0.1'; Client.Port := Server.Port; Client.ReadTimeout := 3000;
    Ping := TBytes.Create($0B,0,0,0,0,0,$FF,$FF,$FF,$FF,0,0,0,0);
    for Pass := 0 to 1 do
    begin
      Client.Connect; Send(Login);
      if Pass=0 then
      begin
        ReadBytes(36); Check(Decoder.TryPop(Packet) and Decoder.TryPop(Packet),'Empty login');
        Send(Hero); ReadBytes(364); Check(Decoder.TryPop(Packet),'Create');
      end
      else begin ReadBytes(383); Check(Decoder.TryPop(Packet) and Decoder.TryPop(Packet),'Saved login'); end;
      Send(Play); ReadBytes(1230); Check(Decoder.TryPop(Packet) and Decoder.TryPop(Packet),'Play');
      Send(Regen); ReadBytes(1257+5*36+26); // five equipped records and free starter skill list
      Check(Decoder.TryPop(Packet),'Appear');
      if Pass=1 then
      begin
        Check(FloatAt(Packet,12)=123,'TCP restore lost checkpoint');
      end;
      Check(Decoder.TryPop(Packet) and (Packet[7]=1) and (Packet[8]=121),'Domingo appear');
      Check(Decoder.TryPop(Packet) and (Packet[7]=1) and (Packet[8]=136),'Sullibent appear');
      Check(Decoder.TryPop(Packet) and (Packet[0]=6) and (Packet[1]=5),'Inventory list');
      Check(Decoder.TryPop(Packet) and (Length(Packet)=20) and
        (Packet[0]=5) and (Packet[1]=5),'Saved starter skill list');
      Check(Decoder.TryPop(Packet) and (Packet[7]=1) and (Packet[8]=120),'Spider appear');
      Check(Decoder.TryPop(Packet) and (Packet[7]=1) and (Packet[8]=119),
        'Second spider appear');
      Check(Decoder.TryPop(Packet) and (Packet[1]=1) and (Packet[7]=0),'First spider init');
      Check(Decoder.TryPop(Packet) and (Packet[1]=1) and (Packet[7]=2),'First spider stop');
      Check(Decoder.TryPop(Packet) and (Packet[1]=1) and (Packet[7]=0),'Second spider init');
      Check(Decoder.TryPop(Packet) and (Packet[1]=1) and (Packet[7]=2),'Second spider stop');
      Send(Movement(2,123)); Send(Ping); ReadBytes(20);
      Check(Decoder.TryPop(Packet) and (Packet[0]=$0B) and not Decoder.TryPop(Packet),'Checkpoint echoed or ping lost');
      Client.Disconnect; Server.Stop; Server.Start(0); Client.Port := Server.Port;
    end;
  finally Client.Free; Server.Free; Decoder.Free; end;
  Writeln('PASS: loopback checkpoint/restore across listener stop/start, no extra wire reply');
end;

begin
  try PickupAdmissionTests; TestRunSpeedTests; SessionTests; DiskTests; NetworkTests;
  except on E: Exception do begin Writeln('FAIL: ',E.ClassName,': ',E.Message); ExitCode := 1; end; end;
end.
