program B1008QuestTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils, Winapi.Windows,
  Emulator.Protocol.B1008, Emulator.Quest.B1008, Emulator.QuestState.B1008,
  Emulator.Inventory.B1008,
  Emulator.Character.B1008, Emulator.Login.B1008, Emulator.Session,
  Emulator.WorldState.B1008, Emulator.Server, IdTCPClient, IdGlobal;

procedure Check(Value: Boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;

function StartQuest: TBytes;
begin
  // 19003003 = 0x0121F67B; fixture is independent of the parser.
  Result := TBytes.Create(9,0,1,2,3,4,0,0,0,1,1,$21,$F6,$7B,$2B);
end;

procedure Run;
var P, Bad, Hero, Saved, After: TBytes; I: Integer; Failed: Boolean;
  R: TB1008QuestStart; S: TEmulatorSession; Store: TB1008CharacterStore;
  Reward: TB1008QuestReward;
  Replies: TB1008Replies; Desc: string; Mode: TB1008LoginMode;
begin
  P := StartQuest; R := TB1008QuestWire.ParseStart(P);
  Check((R.Timestamp=$01020304) and (R.CharacterID=1) and
    (R.QuestID=B1008ProtectingTheFarmID) and (R.Code=$2B),'QuestStart BE layout');
  for I := 0 to 17 do
  begin
    Bad := Copy(P);
    if I<15 then SetLength(Bad,I);
    if I=15 then SetLength(Bad,16);
    if I=16 then Bad[0] := 8;
    if I=17 then Bad[1] := 1;
    Failed := False;
    try TB1008QuestWire.ParseStart(Bad); except on E: EKarosProtocol do Failed := True; end;
    Check(Failed,'Malformed QuestStart accepted');
  end;
  Bad := Copy(P); Bad[6] := $AB; Bad[7] := $CD; Bad[8] := $EF; Bad[9] := $12;
  R := TB1008QuestWire.ParseStart(Bad); Check(R.CharacterID=$ABCDEF12,'Full unsigned BE ID');
  P:=TBytes.Create(9,1,1,2,3,4,0,0,0,1,1,$21,$F6,$7B,
    $FF,$FF,$FF,$FF,0,0,0,$2B);
  Reward:=TB1008QuestWire.ParseReward(P);
  Check((Reward.Timestamp=$01020304) and (Reward.CharacterID=1) and
    (Reward.QuestID=B1008ProtectingTheFarmID) and
    (Reward.Choice=$FFFFFFFF) and (Reward.Code=$2B) and
    (Reward.WireSize=22),'QuestReward BE layout');
  SetLength(P,19); P[18]:=$2B; Reward:=TB1008QuestWire.ParseReward(P);
  Check((Reward.Choice=$FFFFFFFF) and (Reward.Code=$2B) and
    (Reward.WireSize=19),'Compact QuestReward layout');
  for I:=0 to 3 do begin
    Bad:=Copy(P);
    case I of 0:SetLength(Bad,18); 1:SetLength(Bad,20);
      2:SetLength(Bad,21); 3:Bad[1]:=0; end;
    Failed:=False;
    try TB1008QuestWire.ParseReward(Bad); except on E:EKarosProtocol do Failed:=True; end;
    Check(Failed,'Malformed QuestReward accepted');
  end;
  P:=StartQuest;
  Store := TB1008CharacterStore.Create('');
  try
    S := TEmulatorSession.Create(blMapLoadingProbe,Store);
    try
      Desc := S.HandlePacket(P,Replies); Check((Length(Replies)=0) and (Pos('SKIPPED',Desc)>0),'Early quest');
      S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),Replies);
      Hero := TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
        72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);
      S.HandlePacket(Hero,Replies); Saved := Store.Preview(0);
      S.HandlePacket(TBytes.Create(2,4,1,2,3,4,0,0,0,1,0,0,0,0),Replies);
      Desc := S.HandlePacket(P,Replies); Check((Length(Replies)=0) and (Pos('SKIPPED',Desc)>0),'Quest before appearance');
      S.HandlePacket(TBytes.Create(4,0,1,2,3,4,0,0,0,0,1,
        0,0,$80,$3F,0,0,0,$40,0,0,$40,$40,0,0,$80,$40,0),Replies);
      for I := 0 to 2 do
      begin
        Bad := Copy(P);
        case I of 0: Bad[9]:=2; 1: Bad[13]:=0; 2: Bad[14]:=0; end;
        Desc := S.HandlePacket(Bad,Replies);
        Check((Length(Replies)=0) and (Pos('SKIPPED',Desc)>0),'Unsupported quest fields');
      end;
      for I := 1 to 2 do
      begin
        Desc := S.HandlePacket(P,Replies);
        Check((Length(Replies)=0) and (Pos('QUEST START OBSERVED',Desc)>0) and
          (Pos('NOT accepted',Desc)>0),'Observation must not acknowledge a quest');
      end;
      After := Store.Preview(0);
      Check((Length(Saved)=Length(After)) and CompareMem(@Saved[0],@After[0],Length(Saved)),'Quest changed hero');
      S.Close; Failed:=False;
      try S.HandlePacket(P,Replies); except on E: EKarosProtocol do Failed:=True; end;
      Check(Failed,'Quest after close');
    finally S.Free; end;
    for Mode := blObserveOnly to blCharacterPreview do
    begin
      S := TEmulatorSession.Create(Mode,Store);
      try S.HandlePacket(P,Replies); Check(Length(Replies)=0,'Quest probe mode isolation');
      finally S.Free; end;
    end;
  finally Store.Free; end;
  Writeln('PASS: QuestStart size/header/BE IDs/code, admission, no false ack, repeats, immutable character');
end;

function HeroRequest: TBytes;
begin
  Result:=TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
    72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);
end;
function Login: TBytes;
begin Result:=TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0); end;
function Play: TBytes;
begin Result:=TBytes.Create(2,4,1,2,3,4,0,0,0,1,0,0,0,0); end;
function Regen: TBytes;
begin Result:=TBytes.Create(4,0,1,2,3,4,0,0,0,0,1,
  0,0,$80,$3F,0,0,0,$40,0,0,$40,$40,0,0,$80,$40,0); end;
function LE(const B: TBytes; Offset: Integer): Cardinal;
begin Move(B[Offset],Result,4); end;
procedure ValidateList(const B: TBytes);
var I: Integer;
begin
  Check((Length(B)=240) and (B[0]=9) and (B[1]=2),'QuestList header/size');
  Check((TB1008Wire.ReadBE32(B,2)=$01020304) and
    (TB1008Wire.ReadBE32(B,6)=1) and (TB1008Wire.ReadBE16(B,10)=1),'QuestList BE header');
  Check((LE(B,12)=19003003) and (LE(B,16)=1) and (LE(B,20)=10018),'QuestList LE record');
  for I:=24 to High(B) do Check(B[I]=0,'Zero progress/objective padding');
end;
procedure ValidateProgress(const B:TBytes; Count:Cardinal);
begin
  Check((Length(B)=27) and (B[0]=9) and (B[1]=3),'QuestProgress header/size');
  Check((TB1008Wire.ReadBE32(B,2)=$01020304) and
    (TB1008Wire.ReadBE32(B,6)=1) and
    (TB1008Wire.ReadBE32(B,10)=19003003) and
    (TB1008Wire.ReadBE32(B,14)=1) and
    (TB1008Wire.ReadBE32(B,18)=10018) and
    (TB1008Wire.ReadBE32(B,22)=Count) and (B[26]=0),'QuestProgress BE layout');
end;
procedure ValidateRewardPackets;
var B,A:TBytes; U:TB1008ItemUse;
begin
  B:=TB1008QuestWire.BuildRewardAck($01020304,1,B1008ProtectingTheFarmID,
    $FFFFFFFF,B1008QuestStartCode);
  Check((Length(B)=19) and (B[0]=9) and (B[1]=1) and
    (TB1008Wire.ReadBE32(B,2)=$01020304) and
    (TB1008Wire.ReadBE32(B,6)=1) and
    (TB1008Wire.ReadBE32(B,10)=B1008ProtectingTheFarmID) and
    (TB1008Wire.ReadBE32(B,14)=$FFFFFFFF) and (B[18]=$2B),'Reward ack');
  B:=TB1008QuestWire.BuildCompleteList($01020304,1);
  Check((Length(B)=18) and (B[0]=9) and (B[1]=4) and
    (TB1008Wire.ReadBE32(B,2)=$01020304) and
    (TB1008Wire.ReadBE32(B,6)=1) and
    (TB1008Wire.ReadBE16(B,10)=0) and
    (TB1008Wire.ReadBE16(B,12)=1) and
    (B[14]=$7B) and (B[15]=$F6) and (B[16]=$21) and (B[17]=1),'Complete list: second array, raw LE IDs');
  B:=TB1008InventoryWire.BuildPutIn($01020304,1,
    B1008BeginnerHealingPotionID,B1008FirstRewardCount,0);
  Check((Length(B)=46) and (B[0]=6) and (B[1]=6) and
    (TB1008Wire.ReadBE32(B,2)=$01020304) and
    (TB1008Wire.ReadBE32(B,6)=1) and (B[10]=1) and (B[11]=0) and
    (LE(B,12)=B1008BeginnerHealingPotionID) and (B[16]=0) and
    (LE(B,22)=0) and (LE(B,26)=B1008FirstRewardCount) and (LE(B,30)=0),
    'Inventory put-in packed record');
  B:=TB1008InventoryWire.BuildList($01020304,1,True);
  Check((Length(B)=84) and (B[0]=6) and (B[1]=5) and
    (TB1008Wire.ReadBE32(B,6)=1) and (B[10]=2) and (B[11]=2) and
    (B[12]=1) and (B[13]=0) and (LE(B,14)=B1008BeginnerHealingPotionID) and
    (LE(B,28)=3) and (B[48]=1) and (B[49]=1) and
    (LE(B,50)=B1008BeginnerManaPotionID) and (LE(B,64)=3),
    'Inventory reward list');
  B:=TB1008InventoryWire.BuildList($01020304,1,False);
  Check((Length(B)=12) and (B[10]=2) and (B[11]=0),'Empty inventory list');
  B:=TB1008InventoryWire.BuildList($01020304,1,2,0);
  Check((Length(B)=48) and (B[11]=1) and (B[12]=1) and (B[13]=0) and
    (LE(B,14)=B1008BeginnerHealingPotionID) and (LE(B,28)=2),
    'Inventory variable persistent counts');
  B:=TB1008InventoryWire.BuildPutOut($01020304,1,
    B1008BeginnerHealingPotionID,0);
  Check((Length(B)=24) and (B[0]=6) and (B[1]=7) and
    (TB1008Wire.ReadBE32(B,2)=$01020304) and
    (TB1008Wire.ReadBE32(B,6)=1) and (B[10]=1) and (B[11]=0) and
    (TB1008Wire.ReadBE32(B,12)=B1008BeginnerHealingPotionID) and
    (LE(B,16)=0) and (LE(B,20)=0),'Inventory final put-out');
  B:=TBytes.Create($06,$02,$01,$02,$03,$04,0,0,0,1,1,0,
    0,0,$D2,$F6,0,0,0,0,1);
  U:=TB1008InventoryWire.ParseUse(B);
  Check((U.Timestamp=$01020304) and (U.CharacterID=1) and (U.Page=1) and
    (U.Slot=0) and (U.ItemID=B1008BeginnerHealingPotionID) and
    (U.Parameter=0) and (U.Code=1),'Item use parse');
  A:=TB1008InventoryWire.BuildUseAck(U);
  Check((Length(A)=Length(B)) and CompareMem(@A[0],@B[0],Length(B)),
    'Item use ack roundtrip');
end;
procedure ProgressTests;
var Q:TB1008QuestStore; Owner:TObject; G:TGUID; Dir,Path:string;
  Preview,Data:TBytes; I:Integer; Failed:Boolean;
begin
  for I:=1 to 5 do ValidateProgress(TB1008QuestWire.BuildProgress($01020304,I),I);
  Data:=TB1008QuestWire.BuildActiveList($01020304,3);
  Check((LE(Data,16)=1) and (LE(Data,24)=3),'Restored in-progress QuestList');
  Data:=TB1008QuestWire.BuildActiveList($01020304,5);
  Check((LE(Data,16)=1) and (LE(Data,24)=5),'Restored complete QuestList objective');
  Failed:=False; try TB1008QuestWire.BuildActiveList(1,6);
    except on E:EKarosProtocol do Failed:=True; end;
  Check(Failed,'QuestList accepted progress >5');
  Failed:=False; try TB1008QuestWire.BuildProgress(1,0);
    except on E:EKarosProtocol do Failed:=True; end;
  Check(Failed,'QuestProgress accepted zero');
  CreateGUID(G); Dir:=TPath.Combine(TPath.GetTempPath,'KarosQuestProgress-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir); Path:=TPath.Combine(Dir,'fixture.quests');
  Owner:=TObject.Create; Q:=nil;
  try
    Preview:=TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(HeroRequest),0);
    Q:=TB1008QuestStore.Create(Path); Check(Q.Acquire(Owner,Preview),'Progress acquire');
    Check(Q.RecordSpiderKill(Owner)=0,'Kill advanced inactive quest');
    Check(Q.Accept(Owner),'Progress accept');
    Check(Q.RecordSpiderKill(Owner)=1,'First progress');
    Data:=TFile.ReadAllBytes(Path); Check(LE(Data,80)=0,'Acceptance file mutated');
    Check(FileExists(Path+'.progress.1'),'First progress not durable');
    FreeAndNil(Q); Q:=TB1008QuestStore.Create(Path);
    Check(Q.Acquire(Owner,Preview) and (Q.Progress(Owner)=1),'Progress restart');
    TDirectory.CreateDirectory(Path+'.progress.2'); Failed:=False;
    try Q.RecordSpiderKill(Owner); except on E:Exception do Failed:=True; end;
    Check(Failed and (Q.Progress(Owner)=1),'Failed progress IO mutated memory');
    TDirectory.Delete(Path+'.progress.2',False);
    for I:=2 to 5 do Check(Q.RecordSpiderKill(Owner)=Cardinal(I),'Progress chain');
    Check((Q.RecordSpiderKill(Owner)=5) and not FileExists(Path+'.progress.6'),'Progress cap');
    Check(Q.Active(Owner) and not Q.Rewarded(Owner),'Premature completed state');
    Check(Q.Complete(Owner) and Q.Rewarded(Owner) and not Q.Active(Owner),'Reward commit');
    Check(FileExists(Path+'.rewarded') and not Q.Complete(Owner),'Duplicate reward commit');
    Check((Q.RewardItemCount(Owner,B1008BeginnerHealingPotionID)=3) and
      (Q.RewardItemCount(Owner,B1008BeginnerManaPotionID)=3),'Initial reward-item counts');
    Check((Q.ConsumeRewardItem(Owner,B1008BeginnerHealingPotionID)=2) and
      FileExists(Path+'.used.healing.1'),'Durable reward-item use');
    FreeAndNil(Q); Q:=TB1008QuestStore.Create(Path);
    Check(Q.Acquire(Owner,Preview) and (Q.Progress(Owner)=5) and
      Q.Rewarded(Owner) and not Q.Active(Owner),'Completed restart');
    Check((Q.RewardItemCount(Owner,B1008BeginnerHealingPotionID)=2) and
      (Q.RewardItemCount(Owner,B1008BeginnerManaPotionID)=3),
      'Reward-item count restart');
    Q.Release(Owner); FreeAndNil(Q);
    Data:=TFile.ReadAllBytes(Path+'.progress.3'); Data[80]:=4;
    TFile.WriteAllBytes(Path+'.progress.3',Data); Failed:=False;
    try Q:=TB1008QuestStore.Create(Path); except on E:Exception do Failed:=True; end;
    Check(Failed,'Corrupt progress chain accepted');
  finally
    Q.Free; Owner.Free; TDirectory.Delete(Dir,True);
  end;
  Writeln('PASS: QuestProgress packet, append-only 1..5 chain, IO rollback, cap, restart and corruption');
end;
procedure StateTests;
var Q,Other: TB1008QuestStore; Owner,Intruder: TObject; G:TGUID; Dir,Path:string;
  Preview,Data,Bad:TBytes; Failed:Boolean; S:TEmulatorSession;
  W:TB1008WorldStore; C:TB1008CharacterStore; Replies:TB1008Replies; Desc:string;
begin
  ValidateList(TB1008QuestWire.BuildActiveList($01020304));
  Data:=TB1008QuestWire.BuildStartAck($01020304); Bad:=StartQuest;
  Check((Length(Data)=15) and CompareMem(@Data[0],@Bad[0],15),'Ack differs from audited fixture');
  CreateGUID(G); Dir:=TPath.Combine(TPath.GetTempPath,'KarosQuest-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir); Path:=TPath.Combine(Dir,'fixture.quests');
  Q:=nil; Other:=nil; Owner:=TObject.Create; Intruder:=TObject.Create;
  try
    Preview:=TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(HeroRequest),0);
    Q:=TB1008QuestStore.Create(Path); Check(Q.Acquire(Owner,Preview),'Acquire');
    Check(not Q.Active(Owner),'Empty store already active');
    Check(not Q.Acquire(Intruder,Preview),'Concurrent quest owner');
    Failed:=False;
    try Other:=TB1008QuestStore.Create(Path); except on E:Exception do Failed:=True; end;
    Check(Failed,'File lock not exclusive');
    Failed:=False;
    try Q.Accept(Intruder); except on E:Exception do Failed:=True; end;
    Check(Failed and not FileExists(Path),'Non-owner committed');
    // An existing DIRECTORY at the destination forces atomic publication to fail.
    TDirectory.CreateDirectory(Path); Failed:=False;
    try Q.Accept(Owner); except on E:Exception do Failed:=True; end;
    Check(Failed and not Q.Active(Owner),'Failed IO acknowledged or mutated memory');
    TDirectory.Delete(Path,False);
    Check(Q.Accept(Owner) and Q.Active(Owner),'Initial accept');
    Data:=TFile.ReadAllBytes(Path);
    Check((Length(Data)=84) and not Q.Accept(Owner),'Duplicate acceptance');
    Bad:=TFile.ReadAllBytes(Path); Check(CompareMem(@Data[0],@Bad[0],84),'Duplicate rewrote data');
    FreeAndNil(Q); Q:=TB1008QuestStore.Create(Path); Preview[5]:=99;
    Check(Q.Acquire(Owner,Preview) and Q.Active(Owner),'Restart / timestamp normalization');
    Q.Release(Owner); Bad:=Copy(Preview); Bad[15]:=101; Failed:=False;
    try Q.Acquire(Intruder,Bad); except on E:Exception do Failed:=True; end;
    Check(Failed and Q.Acquire(Owner,Preview),'Wrong hero accepted or acquire leaked owner');
    Bad:=Copy(Data); Bad[80]:=1; TFile.WriteAllBytes(Path,Bad); Failed:=False;
    try Q.Accept(Owner); except on E:Exception do Failed:=True; end;
    Check(Failed,'External file change ignored');
    FreeAndNil(Q); Failed:=False;
    try Q:=TB1008QuestStore.Create(Path); except on E:Exception do Failed:=True; end;
    Check(Failed,'Corrupt checksum accepted');
    Bad:=TFile.ReadAllBytes(Path); Check(Bad[80]=1,'Corrupt user data modified');
    SetLength(Bad,20); TFile.WriteAllBytes(Path,Bad); Failed:=False;
    try Q:=TB1008QuestStore.Create(Path); except on E:Exception do Failed:=True; end;
    Check(Failed,'Truncated store accepted');
    TFile.WriteAllBytes(Path,Data);
    Q:=TB1008QuestStore.Create(Path);
    C:=TB1008CharacterStore.Create; W:=TB1008WorldStore.Create;
    S:=nil;
    try
      C.CreateCharacter(HeroRequest,Bad);
      S:=TEmulatorSession.Create(blMapLoadingProbe,C,W,Q);
      Desc:=S.HandlePacket(StartQuest,Replies);
      Check((Length(Replies)=0) and (Pos('SKIPPED',Desc)>0),'Early accept with enabled store');
      S.HandlePacket(Login,Replies); S.HandlePacket(Play,Replies); S.HandlePacket(Regen,Replies);
      Check(Length(Replies)=11,'Restoration missing'); ValidateList(Replies[4]);
      Check(Replies[2][8]=136,'Sullibent precedes restored quest');
      Check((Replies[3][0]=6) and (Replies[3][1]=5),'Inventory list ordering');
      Check(Replies[5][8]=120,'Spider follows restored quest');
      Check(Replies[6][8]=119,'Second spider follows restored quest');
      S.HandlePacket(Regen,Replies); Check(Length(Replies)=0,'Duplicate Regen resent list');
      Desc:=S.HandlePacket(StartQuest,Replies);
      Check((Length(Replies)=1) and (Pos('already active',Desc)>0),'Idempotent acknowledged retry');
      S.Close; Check(Q.Acquire(Owner,Preview),'Close leaked quest lease'); Q.Release(Owner);
    finally S.Free; W.Free; C.Free; end;
  finally
    Q.Free; Other.Free; Owner.Free; Intruder.Free;
    // Only the unique test-owned temporary directory is removed.
    TDirectory.Delete(Dir,True);
  end;
  Writeln('PASS: QuestList LE objectives, atomic accept, duplicates, IO failure, restart, locks, identity, corruption, restore admission');
end;

procedure TcpTests;
var G:TGUID; Dir,Path:string; Server:TEmulatorServer; Client:TIdTCPClient;
  Decoder:TB1008FrameDecoder; P,Wire,Before,After:TBytes; Bytes:TIdBytes;
  Pass,I:Integer; C:TB1008CharacterStore;
  procedure Send(const B:TBytes);
  begin Wire:=TB1008Wire.Encode(B); SetLength(Bytes,Length(Wire));
    Move(Wire[0],Bytes[0],Length(Wire)); Client.IOHandler.Write(Bytes); end;
  function ReadPacket:TBytes;
  var Header:TIdBytes; N:Integer; B:TBytes;
  begin
    Client.IOHandler.ReadBytes(Header,4,False);
    SetLength(B,4); Move(Header[0],B[0],4); N:=TB1008Wire.ReadBE32(B,0);
    Check((N>=4) and (N<=8192),'TCP frame bound');
    Client.IOHandler.ReadBytes(Bytes,N,False); SetLength(B,N+4);
    Move(Bytes[0],B[4],N); Decoder.Append(B);
    Check(Decoder.TryPop(Result),'TCP decode');
  end;
begin
  CreateGUID(G); Dir:=TPath.Combine(TPath.GetTempPath,'KarosQuestTCP-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir); Path:=TPath.Combine(Dir,'hero.b1008');
  C:=TB1008CharacterStore.Create(Path);
  try C.CreateCharacter(HeroRequest,P); finally C.Free; end;
  Before:=TFile.ReadAllBytes(Path);
  try
    for Pass:=0 to 1 do
    begin
      Server:=TEmulatorServer.Create(emB1008,blMapLoadingProbe,Path);
      Client:=TIdTCPClient.Create(nil); Decoder:=TB1008FrameDecoder.Create;
      try
        Server.Start(0); Client.Host:='127.0.0.1'; Client.Port:=Server.Port;
        Client.ReadTimeout:=3000; Client.ConnectTimeout:=3000; Client.Connect;
        Send(Login); P:=ReadPacket; P:=ReadPacket;
        Send(Play); P:=ReadPacket; P:=ReadPacket;
        Send(Regen); P:=ReadPacket; P:=ReadPacket;
        P:=ReadPacket; Check((Length(P)=200) and (P[8]=136),'TCP Sullibent appearance');
        P:=ReadPacket; Check((P[0]=6) and (P[1]=5),'TCP inventory list');
        P:=ReadPacket; Check((Length(P)=20) and (P[0]=5) and (P[1]=5),'TCP starter skill list');
        if Pass=1 then begin P:=ReadPacket; ValidateList(P); end;
        P:=ReadPacket; Check((Length(P)=200) and (P[8]=120),'TCP spider after quest restore');
        P:=ReadPacket; Check((Length(P)=200) and (P[8]=119),
          'TCP second spider after quest restore');
        for I:=0 to 3 do begin
          P:=ReadPacket;
          Check((Length(P)=42) and (P[0]=4) and (P[1]=1) and
            (P[6]=1) and (P[7]=Byte((I mod 2)*2)), 'TCP spider admission reset');
        end;
        for I:=0 to 1 do begin
          Send(StartQuest); P:=ReadPacket;
          Check((Length(P)=15) and (TB1008QuestWire.ParseStart(P).QuestID=19003003),'TCP ack');
          Check(FileExists(Path+'.quests'),'Ack before durable state');
        end;
        Client.Disconnect;
      finally Client.Free; Decoder.Free; Server.Free; end;
    end;
    After:=TFile.ReadAllBytes(Path);
    Check((Length(Before)=Length(After)) and CompareMem(@Before[0],@After[0],Length(Before)),'TCP quests changed hero');
  finally TDirectory.Delete(Dir,True); end;
  Writeln('PASS: real TCP accept/retry, durable state before reply, complete server restart, QuestList restore, original hero unchanged');
end;

begin
  try Run; ValidateRewardPackets; ProgressTests; StateTests; TcpTests;
  except on E: Exception do begin Writeln('FAIL: ',E.Message); ExitCode:=1; end; end;
end.
