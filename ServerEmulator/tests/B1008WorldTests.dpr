program B1008WorldTests;
{$APPTYPE CONSOLE}
{$R+}
{$Q+}
uses System.SysUtils, IdTCPClient, IdGlobal, Emulator.World.B1008,
  Emulator.Protocol.B1008, Emulator.Character.B1008, Emulator.Login.B1008,
  Emulator.Session, Emulator.Server;

procedure Check(Value: Boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;

function Login: TBytes;
begin Result := TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0); end;

function CreateHero: TBytes;
begin
  Result := TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
    72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);
end;

function Start: TBytes;
begin Result := TBytes.Create(2,4,1,2,3,4,0,0,0,1,0,0,0,0); end;

function RegenPacket: TBytes;
begin
  Result := TBytes.Create(4,0,1,2,3,4,0,0,0,0,1,
    0,0,$80,$3F, 0,0,0,$40, 0,0,$40,$40, 0,0,$80,$40, 0);
end;

function MovePacket: TBytes;
var I: Integer; F: Single;
begin
  Result := nil; SetLength(Result,42);
  Result[0] := 4; Result[1] := 1; Result[5] := 42; Result[7] := 8; Result[11] := 1;
  for I := 0 to 6 do begin F := I+1; Move(F,Result[12+4*I],4); end;
  Result[40] := 13; Result[41] := 14;
end;

procedure CheckVitals(const P: TBytes; Offset: Integer);
var I, Value: Integer;
begin
  for I := 0 to 3 do
  begin
    Move(P[Offset+4*I],Value,4);
    if I<2 then Check(Value=B1008ProbeHP,'Full-width HP current/max')
    else Check(Value=B1008ProbeMP,'Full-width MP current/max');
  end;
  // Explicit byte-order check, independent of Move/host representation.
  Check((P[Offset]=$88) and (P[Offset+1]=$13) and
    (P[Offset+2]=0) and (P[Offset+3]=0),'HP=5000 signed LE32');
  Check((P[Offset+8]=$96) and (P[Offset+9]=0) and
    (P[Offset+10]=0) and (P[Offset+11]=0),'MP=150 signed LE32');
end;

procedure MovementTests;
var P, Bad: TBytes; R: TB1008Movement; I,J: Integer; Failed: Boolean;
  S: TEmulatorSession; Store: TB1008CharacterStore; Replies: TB1008Replies; Desc: string;
begin
  P := MovePacket; R := TB1008World.ParseMovement(P);
  Check((R.Timestamp=42) and (R.CharacterID=1) and (R.Kind=0) and (R.Mode=8) and
    (R.FromX=1) and (R.FromZ=2) and (R.FromY=3) and (R.ToX=4) and (R.ToZ=5) and
    (R.ToY=6) and (R.Parameter=7) and (R.FlagA=13) and (R.FlagB=14),'Move layout/endian');
  for I := 0 to 44 do
  begin
    Bad := Copy(P);
    if I<42 then SetLength(Bad,I);
    if I=42 then SetLength(Bad,43);
    if I=43 then Bad[0] := 3;
    if I=44 then Bad[1] := 0;
    Failed := False;
    try TB1008World.ParseMovement(Bad); except on E: EKarosProtocol do Failed := True; end;
    Check(Failed,'Malformed Move accepted');
  end;
  for I := 0 to 6 do for J := 0 to 2 do
  begin
    Bad := Copy(P); Bad[12+4*I] := 0; Bad[13+4*I] := 0;
    case J of
      0: begin Bad[14+4*I] := $C0; Bad[15+4*I] := $7F; end;
      1: begin Bad[14+4*I] := $80; Bad[15+4*I] := $7F; end;
      2: begin Bad[14+4*I] := $80; Bad[15+4*I] := $4F; end;
    end;
    Failed := False;
    try TB1008World.ParseMovement(Bad); except on E: EKarosProtocol do Failed := True; end;
    Check(Failed,'Invalid movement float accepted');
  end;
  Store := TB1008CharacterStore.Create(''); S := TEmulatorSession.Create(blMapLoadingProbe,Store);
  try
    Desc := S.HandlePacket(P,Replies); Check(Pos('SKIPPED',Desc)>0,'Move before login');
    S.HandlePacket(Login,Replies); S.HandlePacket(CreateHero,Replies); S.HandlePacket(Start,Replies);
    Desc := S.HandlePacket(P,Replies); Check(Pos('SKIPPED',Desc)>0,'Move before appearance');
    S.HandlePacket(RegenPacket,Replies);
    Bad := Copy(P); Bad[11] := 2;
    Desc := S.HandlePacket(Bad,Replies); Check(Pos('SKIPPED',Desc)>0,'Wrong Move ID');
    Bad := Copy(P); Bad[6] := 1;
    Desc := S.HandlePacket(Bad,Replies); Check(Pos('SKIPPED',Desc)>0,'Wrong Move kind');
    Desc := S.HandlePacket(P,Replies);
    Check((Pos('MOVE OBSERVED',Desc)>0) and (Length(Replies)=0) and (S.Stage=ssAppearanceProbe),'Move observation/no echo');
    Check(Pos('from=(1.000,2.000,3.000)',Desc)>0,'Movement log locale');
  finally S.Free; Store.Free; end;
  Writeln('PASS: movement fields, truncations, seven finite/bounded floats, admission, no self echo');
end;

procedure AppearanceTests;
var P, Bad, Preview, Appear, Info: TBytes; R: TB1008Regen;
  I: Integer; Failed: Boolean; S: TEmulatorSession; Store: TB1008CharacterStore;
  Replies: TB1008Replies;
begin
  P := RegenPacket; R := TB1008World.ParseRegen(P);
  Check((R.CharacterID=1) and (R.X=1) and (R.Z=2) and (R.Y=3) and (R.Heading=4),'Regen endian/order');
  for I := 0 to 31 do
  begin
    Bad := Copy(P);
    if I<28 then SetLength(Bad,I);
    if I=28 then SetLength(Bad,29);
    if I=29 then Bad[1] := 1;
    if I=30 then begin Bad[13] := $C0; Bad[14] := $7F; end;
    if I=31 then begin Bad[13] := $80; Bad[14] := $7F; end;
    Failed := False;
    try TB1008World.ParseRegen(Bad); except on E: EKarosProtocol do Failed := True; end;
    Check(Failed,'Malformed Regen accepted');
  end;
  Preview := TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(CreateHero),0);
  Appear := TB1008World.BuildAppearProbe(Preview,R);
  Check((Length(Appear)=217) and (Appear[0]=4) and (Appear[1]=2) and
    (Appear[6]=1) and (Appear[7]=0) and
    (Appear[8]=1) and (Appear[9]=0) and (Appear[11]=0),'Appear idle flag/LE ID/header');
  Check(CompareMem(@Appear[12],@P[11],16),'Appear coordinates reordered');
  CheckVitals(Appear,28);
  Info := TB1008World.BuildCharacterInfoProbe(Preview,R.Timestamp);
  Check(CompareMem(@Appear[28],@Info[20],$26),'Appear/CharInfo shared stats diverged');
  Check((Appear[56]=1) and (Appear[57]=0),'Level');
  Check(CompareMem(@Appear[$C8],@Preview[15],10),'Appear appearance');
  Check(CompareMem(@Appear[44],@B1008PlayerSpeedA,4) and
    CompareMem(@Appear[48],@B1008PlayerSpeedB,4),'Appear player speeds');
  Check((Appear[$D4]=72) and (Appear[$D7]=111) and (Appear[$D8]=0),'UTF-8 name terminator');
  Store := TB1008CharacterStore.Create(''); S := TEmulatorSession.Create(blMapLoadingProbe,Store);
  try
    S.HandlePacket(P,Replies); Check(Length(Replies)=0,'Regen before login');
    S.HandlePacket(Login,Replies); S.HandlePacket(CreateHero,Replies);
    S.HandlePacket(P,Replies); Check(Length(Replies)=0,'Regen before Play');
    S.HandlePacket(Start,Replies);
    Bad := Copy(P); Bad[10] := 2; S.HandlePacket(Bad,Replies); Check(Length(Replies)=0,'Wrong Regen ID');
    Bad := Copy(P); Bad[6] := 1; S.HandlePacket(Bad,Replies); Check(Length(Replies)=0,'Wrong Regen kind');
    Bad := Copy(P); Bad[27] := 1; S.HandlePacket(Bad,Replies); Check(Length(Replies)=0,'Wrong Regen option');
    S.HandlePacket(P,Replies); Check((Length(Replies)=10) and (S.Stage=ssAppearanceProbe),'Appearance admission');
    Check((Replies[2][8]=136) and (Length(Replies[2])=200),'Sullibent after Domingo');
    Check((Replies[3][0]=6) and (Replies[3][1]=5),'Inventory before spider');
    Check((Replies[4][8]=120) and (Length(Replies[4])=200),'Spider after admitted appearance');
    Check((Replies[5][8]=119) and (Length(Replies[5])=200),
      'Second spider after admitted appearance');
    Check((Replies[0][6]=1) and (Replies[0][7]=0) and
      (Replies[1][6]=0) and (Replies[1][7]=1) and (Replies[1][8]=121),'Self idle before unchanged Domingo');
    for I:=6 to 9 do
    begin
      Check((Replies[I][0]=4) and (Replies[I][1]=1) and (Replies[I][6]=1) and
        (Replies[I][7]=Byte((I mod 2)*2)), 'NPC initialize then stop ordering');
      Check(CompareMem(@Replies[I][12],@Replies[I][24],12),
        'NPC admission initialization must have zero displacement');
      Check(CompareMem(@Replies[I][12],@Replies[4+(I-6) div 2][12],12),
        'NPC initialization must preserve appearance coordinates');
      Check(TB1008Wire.ReadBE32(Replies[I],8)=Cardinal(120-(I-6) div 2),
        'NPC initialization handle mismatch');
    end;
    S.HandlePacket(P,Replies); Check(Length(Replies)=0,'Duplicate appearance');
    S.HandlePacket(Login,Replies); Check(Length(Replies)=0,'Login after appearance');
    S.HandlePacket(Start,Replies); Check(Length(Replies)=0,'Play after appearance');
    Appear := Store.Preview(0);
    Check(CompareMem(@Appear[0],@Preview[0],Length(Preview)),'Appearance changed saved hero');
  finally S.Free; Store.Free; end;
  Writeln('PASS: Regen bounds/NaN/infinity, endian/order, Appear layout/name/HP, admission/duplicates, immutable hero');
end;

procedure LayoutTests;
var P, Bad, Preview, Info, Zone: TBytes; I: Integer; Failed: Boolean;
  R: TB1008StartCharacter;
begin
  P := Start; R := TB1008World.ParseStart(P);
  Check((R.Timestamp=$01020304) and (R.CharacterID=1) and (R.Option=0),'Start layout');
  for I := 0 to 16 do
  begin
    Bad := Copy(P);
    if I < 14 then SetLength(Bad,I);
    if I = 14 then SetLength(Bad,15);
    if I = 15 then Bad[0] := 3;
    if I = 16 then Bad[1] := 5;
    Failed := False;
    try TB1008World.ParseStart(Bad); except on E: EKarosProtocol do Failed := True; end;
    Check(Failed,'Malformed Start accepted');
  end;
  Preview := TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(CreateHero),0);
  Info := TB1008World.BuildCharacterInfoProbe(Preview,$01020304);
  Check((Length(Info)=$4B3) and (Info[0]=2) and (Info[1]=5) and
    (TB1008Wire.ReadBE32(Info,2)=$01020304) and (TB1008Wire.ReadBE32(Info,6)=1),'Info header');
  for I := 0 to $140 do
    if (I<$0A) or (I>$25) then Check(Info[10+I]=Preview[15+I],'Info non-probe field changed');
  CheckVitals(Info,$14);
  Check(CompareMem(@Info[$24],@B1008PlayerSpeedA,4) and
    CompareMem(@Info[$28],@B1008PlayerSpeedB,4),'Half-speed player movement');
  Check((B1008PlayerSpeedA=75) and (B1008PlayerSpeedB=150),
    'Player movement multiplier is not 0.5');
  Check(CompareMem(@Info[$2C],@B1008ProbeAttackSpeed,4),'Attack playback speed');
  for I := $14B to High(Info) do Check(Info[I]=0,'Unexpected placeholder data');
  Zone := TB1008World.BuildZoneProbe($01020304);
  Check((Length(Zone)=15) and (Zone[0]=4) and (Zone[1]=4) and
    (TB1008Wire.ReadBE32(Zone,2)=$01020304) and (TB1008Wire.ReadBE32(Zone,6)=1) and
    (TB1008Wire.ReadBE32(Zone,10)=19003) and (Zone[14]=0),'Zone fields');
  Writeln('PASS: Play exact layout, all truncations, malformed headers, info record, Berneo zone');
end;

procedure SessionTests;
var Store: TB1008CharacterStore; S: TEmulatorSession; Replies: TB1008Replies;
  Saved, P, Reply: TBytes; Mode: TB1008LoginMode; Failed: Boolean;
begin
  Store := TB1008CharacterStore.Create('');
  try
    S := TEmulatorSession.Create(blMapLoadingProbe,Store);
    try
      S.HandlePacket(Start,Replies); Check(Length(Replies)=0,'Start before login');
      S.HandlePacket(Login,Replies);
      S.HandlePacket(Start,Replies); Check(Length(Replies)=0,'Start without character');
      S.HandlePacket(CreateHero,Replies); Check(Length(Replies)=1,'Create in probe mode');
      Saved := Store.Preview(0);
      P := Start; P[9] := 2;
      S.HandlePacket(P,Replies); Check(Length(Replies)=0,'Wrong ID');
      P := Start; P[13] := 1;
      S.HandlePacket(P,Replies); Check(Length(Replies)=0,'Unsupported option');
      S.HandlePacket(Start,Replies);
      Check((Length(Replies)=2) and (Replies[0][0]=2) and (Replies[0][1]=5) and
        (Replies[1][0]=4) and (Replies[1][1]=4) and (S.Stage=ssMapLoadingProbe),'Start batch/order');
      S.HandlePacket(Start,Replies); Check(Length(Replies)=0,'Duplicate start');
      S.HandlePacket(Login,Replies); Check(Length(Replies)=0,'Duplicate login');
      S.HandlePacket(CreateHero,Replies); Check(Length(Replies)=0,'Create after start');
      P := TBytes.Create($0B,0,0,0,0,0,$FF,$FF,$FF,$FF,0,0,0,0);
      S.HandlePacket(P,Replies); Check(Length(Replies)=1,'Ping after start');
      Reply := Store.Preview(0);
      Check((Length(Reply)=Length(Saved)) and CompareMem(@Reply[0],@Saved[0],Length(Saved)),'Start mutated character');
      S.Close; Failed := False;
      try S.HandlePacket(Start,Replies); except on E: EKarosProtocol do Failed := True; end;
      Check(Failed,'Start after close');
    finally S.Free; end;
    for Mode := blObserveOnly to blCharacterPreview do
    begin
      S := TEmulatorSession.Create(Mode,Store);
      try S.HandlePacket(Login,Replies); S.HandlePacket(Start,Replies);
        Check(Length(Replies)=0,'World probe not opt-in');
      finally S.Free; end;
    end;
  finally Store.Free; end;
  Writeln('PASS: opt-in/admission, ID/option, duplicate suppression, closed state, ping, no store mutation');
end;

procedure NetworkTests;
var Server: TEmulatorServer; C: TIdTCPClient; D: TB1008FrameDecoder;
  Incoming: TIdBytes; P: TBytes;
begin
  Server := TEmulatorServer.Create(emB1008,blMapLoadingProbe);
  C := TIdTCPClient.Create(nil); D := TB1008FrameDecoder.Create;
  try
    Server.Start(0); C.Host := '127.0.0.1'; C.Port := Server.Port; C.ReadTimeout := 3000; C.Connect;
    C.IOHandler.Write(TIdBytes(TB1008Wire.Encode(Login)));
    C.IOHandler.ReadBytes(Incoming,36,False);
    C.IOHandler.Write(TIdBytes(TB1008Wire.Encode(CreateHero)));
    Incoming := nil; C.IOHandler.ReadBytes(Incoming,364,False);
    C.IOHandler.Write(TIdBytes(TB1008Wire.Encode(Start)));
    Incoming := nil; C.IOHandler.ReadBytes(Incoming,1230,False); D.Append(TBytes(Incoming));
    Check(D.TryPop(P) and (Length(P)=1203) and (P[1]=5),'TCP char info');
    Check(D.TryPop(P) and (Length(P)=15) and (P[0]=4) and (P[1]=4),'TCP zone');
    Check(not D.TryPop(P),'Unexpected third packet');
    C.IOHandler.Write(TIdBytes(TB1008Wire.Encode(RegenPacket)));
    Incoming := nil; C.IOHandler.ReadBytes(Incoming,1257+5*36+26,False); D.Append(TBytes(Incoming));
    Check(D.TryPop(P) and (Length(P)=217) and (P[0]=4) and (P[1]=2),'TCP appearance');
    Check(D.TryPop(P) and (Length(P)=200) and (P[7]=1) and (P[8]=121),'TCP Domingo appearance');
    Check(D.TryPop(P) and (Length(P)=200) and (P[7]=1) and (P[8]=136),'TCP Sullibent appearance');
    Check(D.TryPop(P) and (Length(P)=12+5*36) and (P[0]=6) and (P[1]=5) and
      (P[11]=5),'TCP inventory list with five equipped starter items');
    Check(D.TryPop(P) and (Length(P)=20) and (P[0]=5) and (P[1]=5) and
      (P[11]=1) and (P[12]=$E9) and (P[13]=3) and (P[16]=1),'TCP free starter skill');
    Check(D.TryPop(P) and (Length(P)=200) and (P[7]=1) and (P[8]=120),'TCP spider appearance');
    Check(D.TryPop(P) and (Length(P)=200) and (P[7]=1) and (P[8]=119),
      'TCP second spider appearance');
    Check(D.TryPop(P) and (P[1]=1) and (P[7]=0),'First spider motion initialization');
    Check(D.TryPop(P) and (P[1]=1) and (P[7]=2),'First spider stationary state');
    Check(D.TryPop(P) and (P[1]=1) and (P[7]=0),'Second spider motion initialization');
    Check(D.TryPop(P) and (P[1]=1) and (P[7]=2),'Second spider stationary state');
    Check(not D.TryPop(P),'Unexpected extra NPC packet');
    C.IOHandler.Write(TIdBytes(TB1008Wire.Encode(MovePacket)));
    P := TBytes.Create($0B,0,0,0,0,0,$FF,$FF,$FF,$FF,0,0,0,0);
    C.IOHandler.Write(TIdBytes(TB1008Wire.Encode(P)));
    Incoming := nil; C.IOHandler.ReadBytes(Incoming,20,False); D.Append(TBytes(Incoming));
    Check(D.TryPop(P) and (P[0]=$0B) and (P[1]=0),'TCP movement echoed or lost following ping');
    Writeln('PASS: loopback login/create/Play and ordered encrypted 02/05 + 04/04 batch');
  finally C.Free; Server.Free; D.Free; end;
end;

procedure NpcAppearanceTests;
var P, Q: TBytes; F: Single; I: Integer; N: Cardinal;
begin
  P := TB1008World.BuildDomingoAppearProbe($01020304);
  Check((Length(P)=200) and (P[0]=4) and (P[1]=2) and (P[6]=0) and (P[7]=1),'NPC header/size/kind');
  Check(TB1008Login.ReplyName(P)='NpcAppearProbe','NPC log label');
  Check(TB1008Login.ReplyName(TBytes.Create(4,2))='invalid','Short appearance log label');
  Q := Copy(P); Q[7] := 2;
  Check(TB1008Login.ReplyName(Q)='UnknownAppearKind','Unknown kind log label');
  Q[7] := 0; Check(TB1008Login.ReplyName(Q)='SelfAppearProbe','Self log label');
  Check(TB1008Wire.ReadBE32(P,2)=$01020304,'NPC BE timestamp');
  Move(P[8],N,4); Check((N=121) and (P[8]=121) and (P[11]=0),'NPC LE handle');
  Move(P[$46],N,4); Check(N=121,'No clone fallback');
  Move(P[12],F,4); Check(Abs(F-8910.169921875)<0.001,'Domingo X');
  Move(P[16],F,4); Check(Abs(F-6723.4501953125)<0.001,'Domingo Z');
  Move(P[20],F,4); Check(Abs(F-627.7269897460938)<0.001,'Domingo Y');
  for I := 24 to High(P) do
    if I<>$46 then Check(P[I]=0,'Unexpected NPC data');
  Q := TB1008World.BuildDomingoAppearProbe(0); P[8] := 0;
  Check(Q[8]=121,'NPC packets share mutable bytes');
  Q := TB1008World.BuildSullibentAppearProbe($01020304);
  Move(Q[8],N,4); Check((N=136) and (Q[7]=1),'Sullibent original handle');
  Move(Q[$46],N,4); Check(N=136,'Sullibent template handle');
  Move(Q[12],F,4); Check(Abs(F-8495.849609375)<0.001,'Sullibent X');
  Move(Q[16],F,4); Check(Abs(F-7442.27001953125)<0.001,'Sullibent Z');
  Move(Q[20],F,4); Check(Abs(F-587.1530151367188)<0.001,'Sullibent Y');
  Writeln('PASS: stationary Domingo record, 194-byte body, LE handle and X/Z/Y, BE time, no cloning');
end;

procedure SpiderTests;
var P,Q,D:TBytes; F:Single; N:Cardinal; I:Integer;
begin
  P:=TB1008World.BuildSpiderAppearProbe($01020304);
  Check((Length(P)=200) and (P[0]=4) and (P[1]=2) and (P[6]=0) and (P[7]=1),'Spider header');
  Check(TB1008Wire.ReadBE32(P,2)=$01020304,'Spider timestamp');
  Move(P[8],N,4); Check(N=120,'Spider LE instance');
  Move(P[$46],N,4); Check(N=120,'Spider cannot clone another template');
  Move(P[12],F,4); Check(Abs(F-8669.7763671875)<0.001,'Spider original X');
  Move(P[16],F,4); Check(Abs(F-6668.01025390625)<0.001,'Spider original Z');
  Move(P[20],F,4); Check(Abs(F-604.350341796875)<0.001,'Spider original Y');
  Move(P[28],N,4); Check(N=B1008SpiderProbeHP,'Spider HP');
  Move(P[32],N,4); Check(N=B1008SpiderProbeHP,'Spider max HP');
  Move(P[44],F,4); Check(F=150,'Spider diagnostic speed A');
  Move(P[48],F,4); Check(F=300,'Spider diagnostic speed B');
  Move(P[52],F,4); Check(F=1.0,'Spider diagnostic attack speed');
  Check((P[56]=1) and (P[57]=0),'Spider level LE16');
  for I:=58 to High(P) do if I<>$46 then Check(P[I]=0,'Unexpected spider state');
  Check(TB1008Login.ReplyName(P)='LittleSpiderAppearProbe','Spider log name');
  Q:=TB1008World.BuildSpiderAppearProbe($01020304,119,500,8,1,
    8693.7763671875,6668.01025390625,604.350341796875,0);
  Move(Q[8],N,4); Check(N=119,'Second spider LE instance');
  Move(Q[12],F,4); Check(Abs(F-8693.7763671875)<0.001,
    'Second spider center');
  D:=TB1008World.BuildActorDisappear($01020304,1,120);
  Check((Length(D)=11) and (D[0]=4) and (D[1]=3) and (D[6]=1) and
    (TB1008Wire.ReadBE32(D,2)=$01020304) and
    (TB1008Wire.ReadBE32(D,7)=120),'Spider disappearance layout');
  Check(TB1008Login.ReplyName(D)='ActorDisappear','Disappear log name');
  Q:=TB1008World.BuildDomingoAppearProbe(0); Check(Q[8]=121,'Spider changed Domingo');
  Writeln('PASS: single spider appearance/disappearance, original coordinates and diagnostic vitals');
end;

begin
  try LayoutTests; MovementTests; AppearanceTests; NpcAppearanceTests; SpiderTests; SessionTests; NetworkTests;
  except on E: Exception do begin Writeln('FAIL: ',E.ClassName,': ',E.Message); ExitCode := 1; end; end;
end.
