program B1008FlettaProcTests;
{$APPTYPE CONSOLE}
uses Emulator.Rates.B1008,System.SysUtils,System.IOUtils,System.Math,Winapi.Windows,FireDAC.Comp.Client,
  Emulator.FlettaProc.B1008,Emulator.Fletta.B1008,Emulator.Skills.B1008,
  Emulator.LootStore.B1008,Emulator.Character.B1008,Emulator.Session,
  Emulator.Protocol.B1008,Emulator.Login.B1008,Emulator.Combat.B1008,
  Emulator.Balance.B1008;

{$I B1008UnitRates.inc}

procedure Check(B:Boolean;const Msg:string);
begin if not B then raise Exception.Create(Msg);end;
procedure BE(var P:TBytes;O:Integer;V:Cardinal);
begin P[O]:=Byte(V shr 24);P[O+1]:=Byte(V shr 16);P[O+2]:=Byte(V shr 8);P[O+3]:=Byte(V);end;
function LE(const P:TBytes;O:Integer):Integer;
begin Move(P[O],Result,4);end;
function Hero:TBytes;
begin Result:=TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
  72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);end;

procedure GateTests;
var A:TB1008FlettaAttributes;R:TB1008FlettaInvestment;C:TB1008FlettaProc;
  I,J,Hits:Integer;Seed,Before:Cardinal;P:TBytes;Failed:Boolean;
begin
  Check(TB1008FlettaProc.EligibleImpact(0,632,20,100),'Ordinary eligibility');
  Check(TB1008FlettaProc.EligibleImpact(1,1001,40,100),'Power Strike eligibility');
  Check(TB1008FlettaProc.EligibleImpact(1,1003,25,100),'Body Blow eligibility');
  Check(not TB1008FlettaProc.EligibleImpact(1,1004,0,100),'Utility skill triggered proc');
  Check(not TB1008FlettaProc.EligibleImpact(0,632,0,100),'Miss/fail triggered proc');
  Check(not TB1008FlettaProc.EligibleImpact(1,1001,40,0),'Lethal skill targeted corpse');
  for I:=50121 to 50225 do
    Check(not TB1008FlettaProc.EligibleImpact(1,I,200,100),'Recursive Fletta proc');
  for I:=1 to 2 do for J:=1 to 5 do begin
    A:=Default(TB1008FlettaAttributes);R:=Default(TB1008FlettaInvestment);
    R.CharacterID:=1;R.Code:=$87;R.Category:=1;R.Attribute:=I;R.Amount:=1600;A.AddInvestment(R);
    Check(TB1008FlettaProc.CombinedSkill(A)=0,'One axis unlocked combo');
    R.Category:=2;R.Attribute:=J;R.Amount:=1599;A.AddInvestment(R);
    Check(TB1008FlettaProc.CombinedSkill(A)=0,'Partial second axis unlocked combo');
    R.Amount:=1;A.AddInvestment(R);
    Check(TB1008FlettaProc.CombinedSkill(A)=Cardinal(50200+I*10+J),'Wrong pair');
  end;
  A:=Default(TB1008FlettaAttributes);A.YinInvested:=1600;A.AirInvested:=1599;
  C:=Default(TB1008FlettaProc);Seed:=8;
  Check(not C.TryQueue(A,120,1,1000,Seed) and (Seed=8),'Locked pair consumed random');
  A.AirInvested:=1600;
  Check(not C.TryQueue(A,120,1,1000,Seed,False,0) and (Seed=8),'Disabled chance consumed random');
  for I:=-1 to 1 do if I<>0 then begin
    Failed:=False;
    try C.TryQueue(A,120,1,1000,Seed,False,5000+I*5001);
    except on E:EArgumentOutOfRangeException do Failed:=True;end;
    Check(Failed and (Seed=8),'Invalid chance accepted');
  end;
  for I:=1 to 100 do begin
    C.Clear;Seed:=I;Check(C.TryQueue(A,120,1,1000,Seed,False,10000),'Forced chance missed');
    Before:=Seed;
    Check(not C.TryQueue(A,120,2,1001,Seed,False,10000) and (Seed=Before),'100 percent bypassed active gate');
  end;
  C.Clear;Seed:=8;
  Failed:=False;try C.TryQueue(A,120,1,1000,Seed,False,10000,NaN);
  except on E:EArgumentOutOfRangeException do Failed:=True;end;
  Check(Failed and (Seed=8),'Invalid range consumed random');
  Check(C.TryQueue(A,120,1,1000,Seed,False,10000,60) and (C.GrantedRange=60),'Source range not captured');
  Check(not C.TryQueue(A,120,2,1001,Seed,False,10000,130) and (C.GrantedRange=60),'Queued proc range changed');
  C.Clear;Check(C.GrantedRange=0,'Cancelled range retained');Seed:=8;
  Check(not C.TryQueue(A,120,1,1000,Seed,True) and (Seed=8),'Visual lifetime consumed random');
  Check(C.TryQueue(A,120,1,1000,Seed),'Deterministic positive roll');Before:=Seed;
  Check(not C.TryQueue(A,120,2,1001,Seed) and (Seed=Before),'Queued cast consumed random');
  Check(not C.Prepare(121,2,1001),'Changed target accepted');
  Check(not C.Prepare(120,0,1001),'Stale request accepted');
  Check(C.Prepare(120,2,1001),'Preparation');
  Check(not C.Prepare(120,3,1002),'Duplicate preparation');
  Check(C.Start(120,3,1002),'Start');
  Check(not C.TryQueue(A,120,4,1003,Seed) and (Seed=Before),'Active cast consumed random');
  Check(C.Impact(120,4,1003),'Impact');
  Check(not C.Impact(120,5,1004),'Repeated impact');
  Check(not C.TryQueue(A,120,5,1004,Seed) and (Seed=Before),'Unfinished cast consumed random');
  C.Clear;Check(not C.Active(1005),'Finish did not release proc');
  Seed:=8;Check(C.TryQueue(A,120,10,2000,Seed),'Second proc');
  Check(not C.Active(7000) and not C.Prepare(120,11,7000),'Expired proc admitted');
  P:=TB1008FlettaProc.BuildTrigger($12345678,50221);
  Check((Length(P)=14) and (P[0]=5) and (P[1]=8) and
    (TB1008Wire.ReadBE32(P,2)=$12345678) and (TB1008Wire.ReadBE32(P,6)=1) and
    (TB1008Wire.ReadBE32(P,10)=50221),'Native proc notification');
  P:=TB1008FlettaProc.BuildTrigger(15,High(Cardinal));
  Check(TB1008Wire.ReadBE32(P,10)=High(Cardinal),'Native queue cancellation sentinel');
  P:=TB1008FlettaProc.BuildVisual($12345678,True);
  Check((Length(P)=26) and (P[0]=5) and (P[1]=9) and (P[6]=0) and
    (TB1008Wire.ReadBE32(P,7)=1) and (P[11]=1) and (P[13]=1) and
    (TB1008Wire.ReadBE32(P,14)=50221) and (TB1008Wire.ReadBE32(P,18)=1) and
    (TB1008Wire.ReadBE32(P,22)=1),'Native timed player visual');
  P:=TB1008FlettaProc.BuildVisual(1,False);
  Check((P[11]=0) and (TB1008Wire.ReadBE32(P,14)=50221) and
    (TB1008Wire.ReadBE32(P,22)=0),'Visual removal');
  Seed:=12345;Hits:=0;
  for I:=1 to 100000 do begin
    C.Clear;if C.TryQueue(A,120,I,UInt64(I)*100,Seed) then Inc(Hits);
  end;
  Check((Hits>=12100) and (Hits<=12900),'Proc distribution outside 12.5% tolerance');
  Writeln('PASS: ten pair mappings, both 1600 thresholds, zero draws while locked/active, replay/expiry; procs=',Hits,'/100000');
end;

procedure SessionTests;
var G:TGUID;Path,Desc:string;L:TB1008LootStore;C:TB1008CharacterStore;
  S:TEmulatorSession;DB:TFDConnection;P,B,Ordinary,Decide:TBytes;
  Replies:TB1008Replies;A:TB1008AttackStart;Ready:TB1008SkillReady;
  HasList,HasProc:Boolean;XP:Int64;SP:Cardinal;I,SkillIndex,ExpectedMP:Integer;
  SourceSkill,SourceAction:Cardinal;Barrier:TB1008FlettaBarrier;
  TestTick:UInt64;HPBefore,LastHP,Incoming,HitsTaken,Removals:Integer;
  Stamp,BarrierID:Cardinal;
  procedure Enter(XOffset:Single=0);
  var Pose:Single;
  begin
    S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),Replies);
    S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),Replies);
    P:=TBytes.Create(4,0,0,0,0,2,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
    Pose:=8669.776367+XOffset;Move(Pose,P[11],4);Pose:=6668.010254;Move(Pose,P[15],4);
    Pose:=604.350342;Move(Pose,P[19],4);S.HandlePacket(P,Replies);
  end;
  function Impact(const Start:TBytes;Stamp,Skill:Cardinal):TBytes;
  begin
    Result:=nil;SetLength(Result,38);Result[0]:=5;Result[1]:=1;
    Move(Start[6],Result[6],27);BE(Result,2,Stamp);BE(Result,12,Skill);
    Result[32]:=1;Result[33]:=1;BE(Result,34,120);
  end;
  procedure CastFrenzy;
  begin
    Ready.SkillID:=1004;Ready.Timestamp:=Stamp;Inc(Stamp);Ready.TargetKind:=0;Ready.TargetID:=1;
    Desc:=S.HandlePacket(Ready.Ack,Replies);Check(Pos('READY ACCEPTED',Desc)>0,Desc);
    A.ActionKind:=1;A.ActionID:=1013;A.TargetKind:=0;A.TargetID:=1;A.Timestamp:=Stamp;Inc(Stamp);
    P:=TB1008CombatWire.BuildSelfSkillAction(A,A.X,A.Z,A.Y,0);
    Desc:=S.HandlePacket(P,Replies);Check(Pos('FRENZY START ACCEPTED',Desc)>0,Desc);
    Decide:=Impact(P,Stamp,1004);Inc(Stamp);Decide[33]:=0;BE(Decide,34,1);
    Desc:=S.HandlePacket(Decide,Replies);Check(Pos('FRENZY APPLIED',Desc)>0,Desc);
    A.ActionKind:=5;A.Timestamp:=Stamp;Inc(Stamp);
    Desc:=S.HandlePacket(TB1008CombatWire.BuildSelfSkillAction(A,A.X,A.Z,A.Y,0),Replies);
    Check(Pos('SKILL END ACCEPTED',Desc)>0,Desc);
  end;
  procedure TriggerBarrier(FrenzyWhileQueued:Boolean=False);
  var Packet:TBytes;
  begin
    A.ActionKind:=0;A.ActionID:=7;A.TargetKind:=1;A.TargetID:=120;A.Timestamp:=Stamp;Inc(Stamp);
    P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);S.HandlePacket(P,Replies);
    Desc:=S.HandlePacket(Impact(P,Stamp,7),Replies);Inc(Stamp);
    Check(Pos('FLETTA PROC QUEUED',Desc)>0,'Concurrent buff blocked server proc: '+Desc);
    if FrenzyWhileQueued then CastFrenzy;
    Ready.SkillID:=BarrierID;Ready.Timestamp:=Stamp;Inc(Stamp);Ready.TargetKind:=0;Ready.TargetID:=1;
    Desc:=S.HandlePacket(Ready.Ack,Replies);Check(Pos('FLETTA READY ACCEPTED',Desc)>0,Desc);
    A.ActionKind:=1;A.ActionID:=0;A.TargetKind:=0;A.TargetID:=1;A.Timestamp:=Stamp;Inc(Stamp);
    Desc:=S.HandlePacket(TB1008CombatWire.BuildSelfSkillAction(A,A.X,A.Z,A.Y,0),Replies);
    Check(Pos('FLETTA BARRIER APPLIED',Desc)>0,Desc);
    for Packet in Replies do if (Packet[0]=5) and (Packet[1]=9) then Check(Packet[11]=1,'Barrier removed another buff');
  end;
begin
  CreateGUID(G);Path:=TPath.Combine(TPath.GetTempPath,'KarosFlettaProc-'+GUIDToString(G)+'.sqlite3');
  C:=TB1008CharacterStore.Create;L:=nil;S:=nil;DB:=nil;
  try
    C.CreateCharacter(Hero,P);L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(C,P);FreeAndNil(L);
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;DB.Params.Values['DriverID']:='SQLite';
    DB.Params.Values['Database']:=Path;DB.Connected:=True;
    DB.ExecSQL('INSERT INTO fletta_attributes VALUES(1,2,1600)');
    DB.ExecSQL('INSERT INTO fletta_attributes VALUES(2,1,1600)');FreeAndNil(DB);
    L:=TB1008LootStore.Create(Path,FixtureRates);
    S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L,1,42,304);Enter;
    HasList:=False;for B in Replies do if (B[0]=5) and (B[1]=5) then begin
      HasList:=(B[11]=2) and (LE(B,12)=1001) and (LE(B,16)=50221) and (LE(B,24)=1);
    end;
    Check(HasList,'Derived Fletta rank absent');
    Check(Length(L.LearnedSkills(S))=1,'Fletta grant persisted as SP training');
    XP:=L.Progress(S).TotalEXP;SP:=L.SkillPoints(S);
    Ready:=Default(TB1008SkillReady);Ready.ActorID:=1;Ready.SkillID:=50221;Ready.Rank:=1;
    Ready.TargetKind:=1;Ready.TargetID:=120;Ready.Code:=$1A;
    Ready.X:=8669.776367;Ready.Z:=6668.010254;Ready.Y:=604.350342;Ready.Timestamp:=10;
    Desc:=S.HandlePacket(Ready.Ack,Replies);
    Check(Pos('FLETTA READY REJECTED',Desc)>0,'Manual activation bypassed proc: '+Desc);
    A:=Default(TB1008AttackStart);A.ActorID:=1;A.Timestamp:=20;A.ActionID:=7;
    A.TargetKind:=1;A.TargetID:=120;A.X:=Ready.X;A.Z:=Ready.Z;A.Y:=Ready.Y;
    A.TargetX:=A.X;A.TargetZ:=A.Z;A.TargetY:=A.Y;
    // The fixed proc seed selects hit 16; weaken the 500-HP diagnostic target
    // through admitted combat so Tornado exercises the existing lethal path.
    for I:=1 to 16 do begin
      A.Timestamp:=20+Cardinal(I)*2;
      Ordinary:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);
      Desc:=S.HandlePacket(Ordinary,Replies);Check(Pos('ATTACK START ACCEPTED',Desc)>0,Desc);
      Decide:=Impact(Ordinary,A.Timestamp+1,7);Desc:=S.HandlePacket(Decide,Replies);
      Check(Pos('SPIDER HIT ACCEPTED',Desc)>0,Desc);
      if I<16 then Check(Pos('FLETTA PROC QUEUED',Desc)=0,'Unexpected early proc');
    end;
    Check(Pos('FLETTA PROC QUEUED',Desc)>0,Desc);
    HasProc:=False;for B in Replies do if (B[0]=5) and (B[1]=8) then HasProc:=True;
    Check(HasProc and (L.Progress(S).TotalEXP=XP),'Proc did not wait for its own impact');
    S.HandlePacket(Decide,Replies);Check(Length(Replies)=0,'Ordinary replay emitted second proc');
    Ready.Timestamp:=100;Desc:=S.HandlePacket(Ready.Ack,Replies);
    Check((Pos('SKILL READY ACCEPTED',Desc)>0) and (Length(Replies)=1),Desc);
    A.Timestamp:=101;A.ActionKind:=1;A.ActionID:=0;
    P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);
    Desc:=S.HandlePacket(P,Replies);Check(Pos('FLETTA INSTANT RESOLVED',Desc)>0,Desc);
    Check(LE(Replies[1],19)=TB1008Balance.ClassMaxMP(100,1),'Fletta consumed MP');
    Check((Replies[2][1]=9) and (Replies[2][11]=1) and
      (TB1008Wire.ReadBE32(Replies[2],14)=50221),'Missing Tornado visual before lethal damage');
    Check((Replies[3][11]=1) and (TB1008Wire.ReadBE32(Replies[3],12)=50221) and
      (LE(Replies[3],23)>=200) and (LE(Replies[3],23)<=230) and (LE(Replies[4],11)=0),'Tornado damage/visual identity: '+Desc);
    B:=Replies[High(Replies)];
    Check((B[0]=5) and (B[1]=0) and (B[11]=5),'Instant proc omitted native finish');
    XP:=L.Progress(S).TotalEXP;Check((XP>0) and (L.SkillPoints(S)=SP),'Tornado reward/SP');
    S.HandlePacket(P,Replies);Check((Length(Replies)=0) and (L.Progress(S).TotalEXP=XP),'Repeated start duplicated proc');
    Decide:=Impact(P,102,50221);
    S.HandlePacket(Decide,Replies);Check((Length(Replies)=0) and (L.Progress(S).TotalEXP=XP),'Fletta replay reward');
    A.Timestamp:=103;A.ActionKind:=5;P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);
    Desc:=S.HandlePacket(P,Replies);Check((Pos('SKILL END SKIPPED',Desc)>0) and (Length(Replies)=0),Desc);
    S.HandlePacket(P,Replies);Check(Length(Replies)=0,'Repeated skill end');
    S.PollWorld(GetTickCount64+6000,Replies);
    HasProc:=False;
    for B in Replies do begin
      Check(not ((B[0]=5) and (B[1]=4)),'Finished proc timed out');
      if (B[0]=5) and (B[1]=9) then HasProc:=(B[11]=0) and (TB1008Wire.ReadBE32(B,14)=50221);
    end;
    Check(HasProc,'Finished visual did not expire');
    S.PollWorld(GetTickCount64+6100,Replies);
    for B in Replies do Check(not ((B[0]=5) and (B[1]=9)),'Repeated visual removal');
    FreeAndNil(S);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);Enter;
    Check((Length(L.LearnedSkills(S))=1) and (L.Progress(S).TotalEXP=XP),'Reconnect changed derived grant/reward');
    Ready.Timestamp:=30;Desc:=S.HandlePacket(Ready.Ack,Replies);
    Check(Pos('FLETTA READY REJECTED',Desc)>0,'Reconnect restored pending proc');
    FreeAndNil(S);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L,1,42,8);Enter;
    A.ActionKind:=0;A.ActionID:=7;A.Timestamp:=200;
    P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);S.HandlePacket(P,Replies);
    Desc:=S.HandlePacket(Impact(P,201,7),Replies);Check(Pos('FLETTA PROC QUEUED',Desc)>0,Desc);
    // Expiring a queue which never began must not cancel a newer ordinary hit.
    A.Timestamp:=202;P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);
    S.HandlePacket(P,Replies);S.PollWorld(GetTickCount64+6000,Replies);HasProc:=False;
    for B in Replies do begin
      Check(not ((B[0]=5) and (B[1]=4)),'Queue timeout interrupted ordinary attack');
      if (B[0]=5) and (B[1]=8) then HasProc:=TB1008Wire.ReadBE32(B,10)=High(Cardinal);
    end;
    Check(HasProc,'Timeout did not clear native queue');
    Desc:=S.HandlePacket(Impact(P,203,7),Replies);Check(Pos('SPIDER HIT ACCEPTED',Desc)>0,Desc);
    // One coherent trained-skill -> finish -> Fletta -> finish chain, for both
    // damage skills. Seed 8 guarantees the first eligible roll at normal 12.5%.
    for I:=1 to 6 do L.RecordSpiderEXP(S,'proc-skill-level/'+IntToStr(I));
    Check(L.LearnSkill(S,'proc-learn-body',TB1008SkillLearn.Parse(
      TBytes.Create(5,6,0,0,0,4,0,0,0,1,0,0,3,$EB,$1A)))=slrApplied,'Body Blow fixture');
    for SkillIndex:=0 to 1 do begin
      FreeAndNil(S);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L,1,42,8);
      // After a charge the stunned target can remain outside melee reach.
      // Reproduce that geometry, not a coincident hero/target fixture.
      Enter(SkillIndex*40);Ready.X:=8669.776367+SkillIndex*40;A.X:=Ready.X;
      if SkillIndex=0 then begin SourceSkill:=1001;SourceAction:=1004;end
      else begin SourceSkill:=1003;SourceAction:=1007;end;
      Ready.SkillID:=SourceSkill;Ready.Timestamp:=1000;
      Desc:=S.HandlePacket(Ready.Ack,Replies);Check(Pos('SKILL READY ACCEPTED',Desc)>0,Desc);
      A.ActionKind:=1;A.ActionID:=SourceAction;A.Timestamp:=1001;
      P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);
      Desc:=S.HandlePacket(P,Replies);Check(Pos('SKILL START ACCEPTED',Desc)>0,Desc);
      ExpectedMP:=TB1008Balance.ClassMaxMP(100,L.Progress(S).Level)-TB1008AttackSkillStats.Get(SourceSkill,1).MPCost;
      Decide:=Impact(P,1002,SourceSkill);Desc:=S.HandlePacket(Decide,Replies);
      Check((Pos('FLETTA PROC QUEUED',Desc)>0) and (Pos('sourceKind=1',Desc)>0),Desc);
      Check(LE(Replies[1],11)>0,'Trigger target must survive skill');
      S.HandlePacket(Decide,Replies);Check(Length(Replies)=0,'Skill replay queued another proc');
      A.ActionKind:=5;A.Timestamp:=1003;P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);
      Desc:=S.HandlePacket(P,Replies);Check(Pos('SKILL END ACCEPTED',Desc)>0,Desc);
      Ready.SkillID:=50221;Ready.Timestamp:=1004;
      Desc:=S.HandlePacket(Ready.Ack,Replies);Check(Pos('SKILL READY ACCEPTED',Desc)>0,'Skill finish lost proc: '+Desc);
      A.ActionKind:=1;A.ActionID:=0;A.Timestamp:=1005;
      P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);
      XP:=L.Progress(S).TotalEXP;
      Desc:=S.HandlePacket(P,Replies);Check(Pos('FLETTA INSTANT RESOLVED',Desc)>0,Desc);
      Check((LE(Replies[1],19)=ExpectedMP) and (LE(Replies[4],11)>0),'Proc mana/remaining target HP');
      for B in Replies do Check(not ((B[0]=5) and (B[1]=8)),'Tornado recursively queued Fletta');
      Check(L.Progress(S).TotalEXP=XP,'Nonlethal proc granted EXP');
      B:=Replies[High(Replies)];Check((B[1]=0) and (B[11]=5),'Skill-triggered proc omitted finish');
    end;
    // All five Yang pairs share the native self-targeting protocol. Verify the
    // whole chain per data row without changing the production character.
    for SkillIndex:=1 to 5 do begin
      FreeAndNil(S);FreeAndNil(L);
      DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;DB.Params.Values['DriverID']:='SQLite';
      DB.Params.Values['Database']:=Path;DB.Connected:=True;
      DB.ExecSQL('UPDATE fletta_attributes SET attribute=1 WHERE category=1');
      DB.ExecSQL('UPDATE fletta_attributes SET attribute='+IntToStr(SkillIndex)+' WHERE category=2');
      FreeAndNil(DB);L:=TB1008LootStore.Create(Path,FixtureRates);
      S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L,1,42,8);Enter;
      SourceSkill:=50210+SkillIndex;HasList:=False;
      for B in Replies do if (B[0]=5) and (B[1]=5) then
        for I:=0 to TB1008Wire.ReadBE16(B,10)-1 do
          if LE(B,12+I*4)=Integer(SourceSkill) then HasList:=True;
      Check(HasList,'Barrier derived grant missing');
      Ready.SkillID:=SourceSkill;Ready.Timestamp:=10;Ready.TargetKind:=0;Ready.TargetID:=1;
      Ready.X:=8669.776367;Ready.Z:=6668.010254;
      Desc:=S.HandlePacket(Ready.Ack,Replies);
      Check(Pos('FLETTA READY REJECTED',Desc)>0,'Manual barrier bypassed proc');
      A:=Default(TB1008AttackStart);A.ActorID:=1;A.Timestamp:=20;A.ActionID:=7;
      A.TargetKind:=1;A.TargetID:=120;A.X:=Ready.X;A.Z:=Ready.Z;A.Y:=Ready.Y;
      A.TargetX:=A.X;A.TargetZ:=A.Z;A.TargetY:=A.Y;
      P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);
      Desc:=S.HandlePacket(P,Replies);Check(Pos('ATTACK START ACCEPTED',Desc)>0,Desc);
      Desc:=S.HandlePacket(Impact(P,21,7),Replies);Check(Pos('FLETTA PROC QUEUED',Desc)>0,Desc);
      B:=Replies[High(Replies)];Check(TB1008Wire.ReadBE32(B,10)=SourceSkill,'Wrong barrier trigger');
      TestTick:=GetTickCount64;HPBefore:=TB1008Balance.ClassMaxHP(100,L.Progress(S).Level);Incoming:=0;
      for I:=1 to 12 do begin
        S.PollWorld(TestTick+UInt64(I)*250,Replies);
        for B in Replies do if (B[0]=5) and (B[1]=2) and (B[6]=1) then begin
          Incoming:=LE(B,23);Dec(HPBefore,Incoming);
        end;
      end;
      Check(Incoming>0,'Barrier fixture did not receive baseline damage');
      Ready.Timestamp:=30;Desc:=S.HandlePacket(Ready.Ack,Replies);
      Check(Pos('FLETTA READY ACCEPTED',Desc)>0,Desc);
      A.Timestamp:=31;A.ActionKind:=1;A.ActionID:=0;A.TargetID:=1;A.TargetKind:=0;
      P:=TB1008CombatWire.BuildSelfSkillAction(A,A.X,A.Z,A.Y,0);
      Desc:=S.HandlePacket(P,Replies);
      Check((Pos('FLETTA BARRIER APPLIED',Desc)>0) and (Length(Replies)=4),Desc);
      Check((Replies[0][11]=1) and (Replies[3][11]=5) and (Replies[3][32]=0), 'Barrier self action/finish');
      Check((Replies[1][1]=9) and (TB1008Wire.ReadBE32(Replies[1],14)=SourceSkill),'Barrier effect identity');
      Check(LE(Replies[2],19)=TB1008Balance.ClassMaxMP(100,L.Progress(S).Level),'Barrier consumed MP');
      LastHP:=Min(TB1008Balance.ClassMaxHP(100,L.Progress(S).Level),HPBefore+TB1008FlettaBarrier.Healing(SourceSkill));
      Check(LE(Replies[2],11)=LastHP,'Tree heal missing, repeated or unclamped');
      S.HandlePacket(P,Replies);Check(Length(Replies)=0,'Barrier start replay');
      A.TargetID:=120;A.TargetKind:=1;A.ActionKind:=0;A.ActionID:=7;A.Timestamp:=40;
      P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);S.HandlePacket(P,Replies);
      Desc:=S.HandlePacket(Impact(P,41,7),Replies);
      Check((Pos('HIT ACCEPTED',Desc)>0) and (Pos('FLETTA PROC QUEUED',Desc)=0),'Active barrier retriggered or blocked ordinary combat');
      Barrier.Start(SourceSkill,TestTick);HitsTaken:=0;Removals:=0;
      // Stay below the exact 10s boundary: the server starts the effect a few
      // real milliseconds after TestTick. Expiry is checked separately below.
      for I:=13 to 39 do begin
        S.PollWorld(TestTick+UInt64(I)*250,Replies);
        for B in Replies do begin
          if (B[0]=5) and (B[1]=2) and (B[6]=1) then begin
            Inc(HitsTaken);
            if B[22]=6 then Check((SkillIndex=1) and (LE(B,23)=0),'Invalid incoming barrier failure')
            else Check(LE(B,23)=Barrier.Mitigate(Incoming,TestTick+UInt64(I)*250),'Incoming barrier damage mismatch');
          end;
          if (B[0]=5) and (B[1]=9) and (B[11]=0) and
            (TB1008Wire.ReadBE32(B,14)=SourceSkill) then Inc(Removals);
        end;
      end;
      Check(HitsTaken>=5,'Barrier incoming chain too short');
      if SkillIndex=4 then Check(Removals=1,'Fifth hit did not remove rock barrier');
      S.PollWorld(GetTickCount64+190000,Replies);
      for B in Replies do if (B[0]=5) and (B[1]=9) and (B[11]=0) and
        (TB1008Wire.ReadBE32(B,14)=SourceSkill) then Inc(Removals);
      Check(Removals=1,'Barrier expiry missing/duplicated');
      FreeAndNil(S);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);Enter;
      for B in Replies do Check(not ((B[0]=5) and (B[1]=9)),'Reconnect restored temporary barrier');
    end;
    L.GrantTestProgress(S,'coexist-fixture',3,10);
    Check(L.LearnSkill(S,'coexist-frenzy',TB1008SkillLearn.Parse(
      TBytes.Create(5,6,0,0,0,4,0,0,0,1,0,0,3,$EC,$1A)))=slrApplied,'Frenzy coexist fixture');
    for SkillIndex:=0 to 3 do begin
      FreeAndNil(S);FreeAndNil(L);
      DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;DB.Params.Values['DriverID']:='SQLite';
      DB.Params.Values['Database']:=Path;DB.Connected:=True;
      I:=1;if SkillIndex=2 then I:=4;
      DB.ExecSQL('UPDATE fletta_attributes SET attribute='+IntToStr(I)+' WHERE category=2');
      FreeAndNil(DB);L:=TB1008LootStore.Create(Path,FixtureRates);
      S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L,1,42,8);Enter;
      BarrierID:=50210+I;Stamp:=1000;TestTick:=GetTickCount64;
      if SkillIndex=3 then TriggerBarrier(True)
      else if SkillIndex=0 then begin CastFrenzy;TriggerBarrier;end
      else begin TriggerBarrier;CastFrenzy;end;
      // Frenzy's additive attack survives a second buff; that hit cannot
      // reroll Fletta while the barrier is active.
      A.ActionKind:=0;A.ActionID:=7;A.TargetKind:=1;A.TargetID:=120;A.Timestamp:=Stamp;Inc(Stamp);
      P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);S.HandlePacket(P,Replies);
      Desc:=S.HandlePacket(Impact(P,Stamp,7),Replies);Inc(Stamp);
      Check((Pos('FLETTA PROC QUEUED',Desc)=0) and (LE(Replies[0],23)>=22),'Concurrent Frenzy attack bonus lost');
      S.PollWorld(TestTick+10100,Replies);
      Removals:=0;
      for B in Replies do if (B[0]=5) and (B[1]=9) and (B[11]=0) then begin
        Check(TB1008Wire.ReadBE32(B,14)=BarrierID,'Barrier expiry removed Frenzy');Inc(Removals);
      end;
      Check(Removals=Ord(SkillIndex<>2),'Barrier expiry/rock lifetime');
      S.PollWorld(TestTick+15100,Replies);Removals:=0;
      for B in Replies do if (B[0]=5) and (B[1]=9) and (B[11]=0) then begin
        Check(TB1008Wire.ReadBE32(B,14)=1004,'Frenzy expiry removed a different buff');Inc(Removals);
      end;
      Check(Removals=1,'Independent Frenzy expiry missing');
      if SkillIndex=2 then begin
        S.PollWorld(TestTick+180100,Replies);Removals:=0;
        for B in Replies do if (B[0]=5) and (B[1]=9) and (B[11]=0) then begin
          Check(TB1008Wire.ReadBE32(B,14)=50214,'Rock expiry identity');Inc(Removals);
        end;
        Check(Removals=1,'Frenzy expiry erased Rock barrier');
      end;
    end;
  finally
    DB.Free;S.Free;L.Free;C.Free;
    if FileExists(Path) then TFile.Delete(Path);
    if FileExists(Path+'-wal') then TFile.Delete(Path+'-wal');
    if FileExists(Path+'-shm') then TFile.Delete(Path+'-shm');
  end;
  Writeln('PASS: derived grant, forged manual request blocked, native trigger/ready/start, instant damage/finish without callback, lethal reward once, MP/SP unchanged, reconnect');
  Writeln('PASS: Power Strike/Body Blow impact -> native skill finish -> Tornado; no recursive proc or second MP cost');
  Writeln('PASS: five barrier pairs; derived rank -> trigger -> self ready/start -> buff/HP/rating -> finish -> incoming damage -> expiry/five hits -> reconnect');
  Writeln('PASS: Frenzy/Wind in both orders and queued proc during Frenzy; separate effects/expiry; Frenzy expires without removing Rock');
end;

procedure BarrierTests;
const Absorbed:array[1..5] of Integer=(30,50,30,100,20);
var Barrier:TB1008FlettaBarrier;A:TB1008FlettaAttributes;R:TB1008FlettaInvestment;
  Proc:TB1008FlettaProc;ID,Seed,SavedSeed:Cardinal;I,J,Failures:Integer;Buff:TBytes;
begin
  for I:=1 to 5 do begin
    ID:=50210+I;Barrier:=Default(TB1008FlettaBarrier);Barrier.Start(ID,1000);
    Check(Barrier.Active(1000) and Barrier.Active(Barrier.UntilTick-1),'Barrier duration');
    Check(not Barrier.Active(Barrier.UntilTick),'Barrier expiry boundary');
    Check(Barrier.Mitigate(100,1001)=100-Absorbed[I],'Barrier absorption');
    Check(Barrier.Mitigate(100,Barrier.UntilTick)=100,'Expired barrier mitigated');
    Check(Barrier.DefenseRatingBonus(1001)=4*Ord(I=1),'Wind numeric rating bonus');
    Seed:=42;SavedSeed:=Seed;
    Check(not Barrier.CausesFailure(Barrier.UntilTick,Seed) and (Seed=SavedSeed),'Expired rating consumed RNG');
    if I<>1 then Check(not Barrier.CausesFailure(1001,Seed) and (Seed=SavedSeed),'Other barrier consumed defense RNG');
    Check(Barrier.ResistsNegativeEffects(1001)=(I=5),'Water resistance lifetime');
    Check(TB1008FlettaBarrier.Healing(ID)=100*Ord(I=3),'Tree immediate heal');
    Buff:=TB1008FlettaProc.BuildBuff(55,ID,TB1008FlettaBarrier.DurationMS(ID),True);
    Check((Buff[6]=0) and (TB1008Wire.ReadBE32(Buff,14)=ID) and
      (TB1008Wire.ReadBE32(Buff,22)=TB1008FlettaBarrier.DurationMS(ID) div 1000),'Barrier buff target/time');
    A:=Default(TB1008FlettaAttributes);R:=Default(TB1008FlettaInvestment);
    R.CharacterID:=1;R.Code:=$87;R.Category:=1;R.Attribute:=1;R.Amount:=1600;A.AddInvestment(R);
    R.Category:=2;R.Attribute:=I;A.AddInvestment(R);
    Proc.Clear;Seed:=8;
    Check(Proc.TryQueue(A,120,1,1000,Seed) and (Proc.SkillID=ID) and (Proc.Target=1),'Barrier self proc grant');
    Check(not Proc.Prepare(120,2,1001) and Proc.Prepare(1,2,1001) and Proc.Start(1,3,1002),'Barrier self handshake');
    Proc.Clear;SavedSeed:=Seed;
    Check(not Proc.TryQueue(A,120,4,1003,Seed,Barrier.Active(1003)) and (Seed=SavedSeed),'Barrier lifetime consumed RNG');
    Barrier.Clear;Check(not Barrier.Active(1004),'Barrier reset');
  end;
  Barrier.Start(50214,1000);
  Check(Barrier.Mitigate(0,1001)=0,'Zero damage altered rock barrier');
  Check(Barrier.RemainingHits=5,'Zero damage spent shield charge');
  for J:=1 to 5 do begin
    Check(Barrier.Mitigate(100,1000+J)=0,'Rock barrier failed before fifth hit');
    Check(Barrier.Active(1000+J)=(J<5),'Rock charge boundary');
  end;
  Check(Barrier.Mitigate(100,1006)=100,'Rock barrier absorbed sixth hit');
  Barrier.Start(50212,1000);Check(Barrier.Mitigate(1,1001)=1,'Partial barrier erased minimum damage');
  Check((Barrier.FailureBasisPoints(4)=40) and (Barrier.FailureBasisPoints(20)=200) and
    (Barrier.FailureBasisPoints(30)=300),'Defense rating tenth-percent conversion');
  Barrier.Start(50211,1000);Seed:=12345;Failures:=0;
  for J:=1 to 100000 do if Barrier.CausesFailure(1001,Seed) then Inc(Failures);
  Check((Failures>=340) and (Failures<=460),'Wind +4 rating not 0.4 percent failures');
  Barrier.Start(50211,1000,500);Seed:=12345;Failures:=0;
  for J:=1 to 100000 do if Barrier.CausesFailure(1001,Seed) then Inc(Failures);
  Check((Failures>=49000) and (Failures<=51000),'Temporary 500 rating not 50 percent');
  Barrier.Clear;Seed:=12345;Failures:=0;
  for J:=1 to 100000 do if Barrier.CausesFailure(1001,Seed,19) then Inc(Failures);
  Check((Failures>=1700) and (Failures<=2100),'Level20 defense rating requires no active barrier');
  Barrier.Start(50211,1000);Seed:=12345;Failures:=0;
  for J:=1 to 100000 do if Barrier.CausesFailure(1001,Seed,19) then Inc(Failures);
  Check((Failures>=2100) and (Failures<=2500),'Level rating and wind rating must add');
  Seed:=12345;Failures:=0;
  for J:=1 to 100000 do if Barrier.CausesFailure(Barrier.UntilTick,Seed,19) then Inc(Failures);
  Check((Failures>=1700) and (Failures<=2100),'Barrier expiry removed permanent level rating');
  Buff:=TB1008CombatWire.BuildPlayerDamageProbe(1,120,0,0,0,0,True);
  Check((Buff[6]=1) and (Buff[17]=0) and (Buff[22]=6) and (LE(Buff,23)=0),'Incoming FAIL wire/zero damage');
  Writeln('PASS: all five barrier profiles; self proc, RNG lock, absorption, heal, rating, resistance, expiry and five-hit boundary');
end;

procedure RockSessionTests;
var G:TGUID;Path,Note:string;L:TB1008LootStore;C:TB1008CharacterStore;
  S:TEmulatorSession;DB:TFDConnection;P,B,D:TBytes;Replies:TB1008Replies;
  A:TB1008AttackStart;R:TB1008SkillReady;Pose:Single;Tick:UInt64;
  Damage,Adds,Removes:Integer;XP:Int64;
begin
  CreateGUID(G);Path:=TPath.Combine(TPath.GetTempPath,'KarosRock-'+GUIDToString(G)+'.sqlite3');
  L:=nil;S:=nil;DB:=nil;C:=TB1008CharacterStore.Create;
  try
    C.CreateCharacter(Hero,P);L:=TB1008LootStore.Create(Path,FixtureRates);Check(L.Acquire(C,P),'Rock seed');FreeAndNil(L);
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;DB.Params.Values['DriverID']:='SQLite';
    DB.Params.Values['Database']:=Path;DB.Connected:=True;
    DB.ExecSQL('INSERT INTO fletta_attributes VALUES(1,2,1600)');
    DB.ExecSQL('INSERT INTO fletta_attributes VALUES(2,4,1600)');FreeAndNil(DB);
    L:=TB1008LootStore.Create(Path,FixtureRates);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L,1,42,8);
    S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),Replies);
    S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),Replies);
    P:=TBytes.Create(4,0,0,0,0,2,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
    Pose:=8669.776367;Move(Pose,P[11],4);Pose:=6668.010254;Move(Pose,P[15],4);
    Pose:=604.350342;Move(Pose,P[19],4);S.HandlePacket(P,Replies);
    Adds:=0;for B in Replies do if (B[0]=5) and (B[1]=5) then
      if (B[11]=2) and (LE(B,16)=50224) then Inc(Adds);
    Check(Adds=1,'Rock derived skill list');
    R:=Default(TB1008SkillReady);R.ActorID:=1;R.SkillID:=50224;R.Rank:=1;
    R.TargetKind:=1;R.TargetID:=120;R.Code:=$1A;R.Timestamp:=10;
    R.X:=8669.776367;R.Z:=6668.010254;R.Y:=604.350342;
    Note:=S.HandlePacket(R.Ack,Replies);Check(Pos('FLETTA READY REJECTED',Note)>0,'Manual Rock bypass');
    A:=Default(TB1008AttackStart);A.ActorID:=1;A.Timestamp:=20;A.ActionID:=7;
    A.TargetKind:=1;A.TargetID:=120;A.X:=R.X;A.Z:=R.Z;A.Y:=R.Y;
    A.TargetX:=A.X;A.TargetZ:=A.Z;A.TargetY:=A.Y;
    P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);
    Note:=S.HandlePacket(P,Replies);Check(Pos('ATTACK START ACCEPTED',Note)>0,'Rock source start: '+Note);
    SetLength(D,38);D[0]:=5;D[1]:=1;Move(P[6],D[6],27);BE(D,2,21);
    D[32]:=1;D[33]:=1;BE(D,34,120);
    Note:=S.HandlePacket(D,Replies);Check(Pos('FLETTA PROC QUEUED',Note)>0,Note);
    Check(TB1008Wire.ReadBE32(Replies[High(Replies)],10)=50224,'Wrong queued Yin ID');
    R.Timestamp:=30;Note:=S.HandlePacket(R.Ack,Replies);Check(Pos('READY ACCEPTED',Note)>0,Note);
    A.Timestamp:=31;A.ActionKind:=1;A.ActionID:=0;
    P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);Tick:=GetTickCount64;
    Note:=S.HandlePacket(P,Replies);Check(Pos('FLETTA INSTANT RESOLVED',Note)>0,Note);
    Damage:=0;Adds:=0;
    for B in Replies do begin
      if (B[0]=5) and (B[1]=2) then begin
        Check(TB1008Wire.ReadBE32(B,12)=50224,'Rock replaced by Tornado');Damage:=LE(B,23);
      end;
      if (B[0]=5) and (B[1]=9) and (B[6]=1) then begin
        Check((B[11]=1) and (TB1008Wire.ReadBE32(B,14)=50224),'Wrong stun effect');Inc(Adds);
      end;
    end;
    Check((Damage>=130) and (Damage<=160) and (Adds=1),'Rock raw damage/stun');
    Check(Pos('stun=1300ms',Note)>0,'Rock duration');
    Check((Replies[High(Replies)][0]=5) and (Replies[High(Replies)][1]=0) and
      (Replies[High(Replies)][11]=5),'Rock missing native finish');
    XP:=L.Progress(S).TotalEXP;S.HandlePacket(P,Replies);
    Check((Length(Replies)=0) and (L.Progress(S).TotalEXP=XP),'Rock start replay');
    A.ActionKind:=0;A.ActionID:=7;A.Timestamp:=40;
    P:=TB1008CombatWire.BuildSpiderStartAccepted(A,A.X,A.Z,A.Y);
    Note:=S.HandlePacket(P,Replies);Check(Pos('ATTACK START ACCEPTED',Note)>0,'Rock followup start: '+Note);
    Move(P[6],D[6],27);BE(D,2,41);BE(D,12,7);
    Note:=S.HandlePacket(D,Replies);Check(Pos('FLETTA PROC QUEUED',Note)=0,'Active Rock retrigger');
    S.PollWorld(Tick+1000,Replies);
    for B in Replies do Check(not ((B[0]=5) and (B[1]=9) and (B[6]=1) and (B[11]=0)),
      'Rock stun removed before1300ms');
    S.PollWorld(Tick+1400,Replies);Removes:=0;
    for B in Replies do if (B[0]=5) and (B[1]=9) and (B[6]=1) and (B[11]=0) then begin
      Check(TB1008Wire.ReadBE32(B,14)=50224,'Removed wrong stun');Inc(Removes);
    end;
    Check(Removes=1,'Rock status not removed exactly once');
    S.PollWorld(Tick+1500,Replies);
    for B in Replies do Check(not ((B[0]=5) and (B[1]=9) and (B[6]=1) and (B[11]=0)),
      'Rock repeated removal');
    Writeln('PASS: Rock native proc/finish, standalone130..160, stun1300ms, RNG lock/replay/expiry');
  finally S.Free;L.Free;DB.Free;C.Free;TFile.Delete(Path);end;
end;

begin
  try GateTests;BarrierTests;SessionTests;RockSessionTests;
  except on E:Exception do begin Writeln('FAIL: ',E.ClassName,': ',E.Message);ExitCode:=1;end;end;
end.
