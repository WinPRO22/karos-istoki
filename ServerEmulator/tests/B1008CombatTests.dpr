program B1008CombatTests;
{$APPTYPE CONSOLE}
uses System.SysUtils, Winapi.Windows, Emulator.Protocol.B1008, Emulator.Combat.B1008,
  Emulator.Session, Emulator.Login.B1008, Emulator.Character.B1008,
  Emulator.Server, Emulator.World.B1008, Emulator.Balance.B1008;

procedure Check(B: Boolean; const S: string);
begin if not B then raise Exception.Create(S); end;

procedure PutBE32(var P: TBytes; Offset: Integer; Value: Cardinal);
begin
  P[Offset]:=Byte(Value shr 24); P[Offset+1]:=Byte(Value shr 16);
  P[Offset+2]:=Byte(Value shr 8); P[Offset+3]:=Byte(Value);
end;

function Attack: TBytes;
var I: Integer; F: Single;
begin
  Result:=nil; SetLength(Result,53); Result[0]:=5;
  Result[2]:=$12; Result[3]:=$34; Result[4]:=$56; Result[5]:=$78;
  Result[10]:=1; Result[11]:=2; Result[14]:=$12; Result[15]:=$34;
  Result[32]:=1; Result[36]:=120;
  for I:=0 to 3 do begin F:=I+1; Move(F,Result[16+I*4],4);
    F:=I+5; Move(F,Result[37+I*4],4); end;
end;

function Decide(const A: TBytes): TBytes;
begin
  SetLength(Result,38); Result[0]:=5; Result[1]:=1;
  PutBE32(Result,2,TB1008Wire.ReadBE32(A,2)+1);
  Result[6]:=A[6]; PutBE32(Result,7,TB1008Wire.ReadBE32(A,7));
  Result[11]:=A[11]; PutBE32(Result,12,TB1008Wire.ReadBE32(A,12));
  Move(A[16],Result[16],16);
  Result[32]:=A[32]; Result[33]:=1;
  PutBE32(Result,34,TB1008Wire.ReadBE32(A,33));
end;

procedure Run;
var P,B,F: TBytes; R: TB1008AttackStart; Q: TB1008AttackDecide;
  A: TB1008ActionFlags;
  I,J,O: Integer; Failed: Boolean; Bits: Cardinal; Desc: string;
  S: TEmulatorSession; Store: TB1008CharacterStore; Replies: TB1008Replies;
  V: Single; Start,CounterStart,D,G,M,PD,PG: TBytes;
  BaseTick: UInt64;
begin
  P:=Attack; R:=TB1008CombatWire.ParseStart(P);
  Check((R.Timestamp=$12345678) and (R.ActorKind=0) and (R.ActorID=1) and
    (R.ActionKind=2) and (R.ActionID=$1234) and (R.TargetKind=1) and
    (R.TargetID=120),'Attack integer layout');
  Check((R.X=1) and (R.Z=2) and (R.Y=3) and (R.Heading=4) and
    (R.TargetX=5) and (R.TargetZ=6) and (R.TargetY=7) and
    (R.TargetParameter=8),'Attack float layout');
  for I:=0 to 55 do begin
    B:=Copy(P);
    if I<53 then SetLength(B,I);
    if I=53 then SetLength(B,54);
    if I=54 then B[0]:=4;
    if I=55 then B[1]:=1;
    Failed:=False; try TB1008CombatWire.ParseStart(B);
      except on E: EKarosProtocol do Failed:=True; end;
    Check(Failed,'Malformed attack accepted');
  end;
  for I:=0 to 7 do for J:=0 to 3 do begin
    B:=Copy(P); if I<4 then O:=16+I*4 else O:=37+(I-4)*4;
    case J of 0:Bits:=$7FC00000; 1:Bits:=$7F800000;
      2:Bits:=$FF800000; else Bits:=$4F800000; end;
    Move(Bits,B[O],4); Failed:=False;
    try TB1008CombatWire.ParseStart(B); except on E: EKarosProtocol do Failed:=True; end;
    Check(Failed,'Invalid float accepted');
  end;
  B:=Decide(P); Q:=TB1008CombatWire.ParseDecide(B);
  Check((Q.Timestamp=$12345679) and (Q.ActorID=1) and
    (Q.ActionID=$1234) and (Q.TargetCount=1) and (Q.TargetID=120) and
    (Q.X=1) and (Q.Heading=4),'AttackDecide layout');
  for I:=0 to 40 do begin
    F:=Copy(B);
    if I<38 then SetLength(F,I);
    if I=38 then SetLength(F,39);
    if I=39 then F[0]:=4;
    if I=40 then F[1]:=0;
    Failed:=False;
    try TB1008CombatWire.ParseDecide(F);
    except on E:EKarosProtocol do Failed:=True; end;
    Check(Failed,'Malformed AttackDecide accepted');
  end;
  F:=TBytes.Create(3,2,$12,$34,$56,$78,0,0,0,1,2,5);
  A:=TB1008CombatWire.ParseFlags(F);
  Check((A.Timestamp=$12345678) and (A.CharacterID=1) and
    (A.FlagA=2) and (A.FlagB=5),'Flags layout');
  for I:=0 to 14 do begin
    B:=Copy(F); if I<12 then SetLength(B,I);
    if I=12 then SetLength(B,13); if I=13 then B[0]:=5; if I=14 then B[1]:=3;
    Failed:=False; try TB1008CombatWire.ParseFlags(B);
      except on E: EKarosProtocol do Failed:=True; end;
    Check(Failed,'Malformed flags accepted');
  end;
  Store:=TB1008CharacterStore.Create;
  S:=TEmulatorSession.Create(blMapLoadingProbe,Store);
  try
    Desc:=S.HandlePacket(P,Replies); Check(Pos('SKIPPED',Desc)>0,'Early attack accepted');
    Check(Length(Replies)=0,'Early reply');
    S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),Replies);
    S.HandlePacket(TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
      72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0),Replies);
    S.HandlePacket(TBytes.Create(2,4,1,2,3,4,0,0,0,1,0,0,0,0),Replies);
    S.HandlePacket(TBytes.Create(4,0,1,2,3,4,0,0,0,0,1,
      0,0,$80,$3F,0,0,0,$40,0,0,$40,$40,0,0,$80,$40,0),Replies);
    Desc:=S.HandlePacket(P,Replies);
    Check(Pos('target=1/120',Desc)>0,'Target not decoded');
    Check(Length(Replies)=0,'Observer must not echo attack');
    Check(S.WorldState.Position.X=1,'Attack changed checkpoint');
    Desc:=S.HandlePacket(F,Replies); Check(Pos('flags=2/5',Desc)>0,'Flags log');
    B:=Copy(P); B[10]:=2; Desc:=S.HandlePacket(B,Replies);
    Check(Pos('SKIPPED',Desc)>0,'Foreign actor accepted');
    B:=Copy(P); B[6]:=1; Desc:=S.HandlePacket(B,Replies);
    Check(Pos('SKIPPED',Desc)>0,'NPC actor accepted');
    B:=Copy(F); B[9]:=2; Desc:=S.HandlePacket(B,Replies);
    Check(Pos('SKIPPED',Desc)>0,'Foreign flags accepted');
    P[11]:=0;
    Desc:=S.HandlePacket(P,Replies);
    Check((Pos('distance',Desc)>0) and (Length(Replies)=0),'Distant hit accepted');
    SetLength(M,42); M[0]:=4; M[1]:=1; M[7]:=2; M[11]:=1;
    V:=8674.279; Move(V,M[12],4); Move(V,M[24],4); Move(V,P[16],4);
    V:=6660.197; Move(V,M[16],4); Move(V,M[28],4); Move(V,P[20],4);
    V:=607.879; Move(V,M[20],4); Move(V,M[32],4); Move(V,P[24],4);
    V:=8669.776367; Move(V,P[37],4);
    V:=6668.010254; Move(V,P[41],4);
    V:=607.174; Move(V,P[45],4);
    S.HandlePacket(M,Replies);
    B:=Copy(P); B[36]:=121; Desc:=S.HandlePacket(B,Replies);
    Check(Length(Replies)=0,'Domingo damaged');
    B:=Copy(P); V:=9000; Move(V,B[16],4); Desc:=S.HandlePacket(B,Replies);
    Check((Pos('distance',Desc)>0) and (Length(Replies)=0),'Inconsistent attack accepted');
    Desc:=S.HandlePacket(P,Replies);
    Check((Pos('ATTACK START ACCEPTED',Desc)>0) and (Length(Replies)=2),
      'Accepted first start did not include immediate patrol stop');
    Check((Replies[0][0]=4) and (Replies[0][1]=1) and
      (Replies[0][7]=2) and (TB1008Wire.ReadBE32(Replies[0],8)=120),
      'Immediate engagement stop packet is invalid');
    Start:=Replies[1];
    Check((Start[0]=5) and (Start[1]=0),
      'Owner received wrong attack-start reply');
    Check((Length(Start)=53) and (Start[0]=5) and (Start[1]=0) and
      (TB1008Wire.ReadBE32(Start,2)=$12345678) and
      (TB1008Wire.ReadBE32(Start,7)=1) and
      (TB1008Wire.ReadBE32(Start,12)=$1234) and
      (Start[32]=1) and (TB1008Wire.ReadBE32(Start,33)=120),'Accepted Start layout');
    Move(Start[16],V,4); Check(Abs(V-8674.279)<0.01,'Start server actor X');
    Move(Start[37],V,4); Check(Abs(V-8669.776367)<0.01,'Start admitted target X');
    Check((Start[49]=0) and (Start[50]=0) and (Start[51]=0) and (Start[52]=0),
      'Start parameter not neutral');
    B:=Decide(P);
    Desc:=S.HandlePacket(B,Replies);
    Check((Pos('SPIDER HIT ACCEPTED',Desc)>0) and (Length(Replies)=2),
      'Matching impact did not commit damage');
    D:=Replies[0]; G:=Replies[1];
    Check((D[0]=5) and (D[1]=2) and (G[0]=8) and (G[1]=0),
      'Owner received wrong impact reply order');
    R:=TB1008CombatWire.ParseStart(P);
    D:=TB1008CombatWire.BuildSpiderDamageProbe(R);
    G:=TB1008CombatWire.BuildSpiderGageProbe(R.Timestamp,75);
    Check((Length(D)=47) and (D[0]=5) and (D[1]=2) and
      (TB1008Wire.ReadBE32(D,2)=$12345678) and (TB1008Wire.ReadBE32(D,7)=1) and
      (TB1008Wire.ReadBE32(D,12)=$1234) and (D[16]=1) and (D[17]=1),'Damage header');
    Check((D[18]=120) and (D[19]=0) and (D[20]=0) and (D[21]=0) and
      (D[23]=50) and (D[24]=0) and (D[25]=0) and (D[26]=0),'Damage LE fields');
    Check((Length(G)=49) and (G[0]=8) and (G[1]=0) and (G[6]=1) and
      (TB1008Wire.ReadBE32(G,7)=120) and (G[11]=75),'Gage HP layout');
    Move(G[15],O,4); Check(O=B1008SpiderProbeHP,'Gage maximum HP');
    Move(D[31],V,4); Check(Abs(V-8669.776367)<0.01,'Server-owned target coordinates');
    Move(G[27],V,4); Check(V=150,'Gage retains speed A');
    Move(G[31],V,4); Check(V=300,'Gage retains speed B');
    Move(G[35],V,4); Check(V=1.0,'Gage retains spider attack speed');
    V:=8671.776367; Move(V,M[12],4); Move(V,M[24],4);
    V:=6668.010254; Move(V,M[16],4); Move(V,M[28],4);
    V:=604.350342; Move(V,M[20],4); Move(V,M[32],4);
    S.HandlePacket(M,Replies);
    BaseTick:=GetTickCount64+10;
    Desc:=S.PollWorld(BaseTick,Replies);
    Check((Desc='') and (Length(Replies)=0),
      'Immediate engagement stop was not kept for one visual frame');
    Desc:=S.PollWorld(BaseTick+250,Replies);
    Check((Pos('SPIDER ATTACK | start',Desc)>0) and (Length(Replies)=1),
      'Autonomous spider attack did not start after immediate engagement stop');
    CounterStart:=Replies[0];
    Check((CounterStart[0]=5) and (CounterStart[1]=0) and
      (CounterStart[6]=1) and
      (TB1008Wire.ReadBE32(CounterStart,7)=B1008SpiderHandle) and
      (CounterStart[32]=0) and (TB1008Wire.ReadBE32(CounterStart,33)=1),
      'Autonomous counter-start actor/target layout');
    Desc:=S.PollWorld(BaseTick+1249,Replies);
    Check(Pos('SPIDER ATTACK | damage=',Desc)=0,
      'Autonomous spider damage fired early');
    Desc:=S.PollWorld(BaseTick+1250,Replies);
    Check((Pos('SPIDER ATTACK | damage=10',Desc)>0) and (Length(Replies)=2),
      'Autonomous spider damage did not fire');
    PD:=Replies[0]; PG:=Replies[1];
    Check((PD[0]=5) and (PD[1]=2) and (PD[23]=10),
      'Autonomous spider damage wire');
    Move(PG[11],O,4); Check(O=175,'Autonomous attack did not update level-one Blader HP');
    Move(PG[27],V,4); Check(V=75,'Damage gage reset player speed A');
    Move(PG[31],V,4); Check(V=150,'Damage gage reset player speed B');
    Move(PG[35],V,4); Check(V=1.0,'Movement tuning changed player attack speed');
    Desc:=S.PollWorld(BaseTick+1251,Replies);
    Check((Pos('SPIDER ATTACK | start',Desc)>0) and (Length(Replies)=1),
      'Autonomous spider attack did not repeat');
    Desc:=S.HandlePacket(P,Replies);
    Check((Length(Replies)=0) and (Pos('duplicate/stale',Desc)>0),'Repeated start acknowledged');
    P[15]:=$35; Desc:=S.HandlePacket(P,Replies);
    Check((Length(Replies)=0) and (Pos('duplicate/stale',Desc)>0),'Same-timestamp action accepted');
    B:=Copy(P); PutBE32(B,2,$1234567A);
    Desc:=S.HandlePacket(B,Replies);
    Check((Pos('ATTACK START ACCEPTED',Desc)>0) and (Length(Replies)=1),
      'New attack start was not armed');
    S.HandlePacket(M,Replies);
    B:=Decide(B); Desc:=S.HandlePacket(B,Replies);
    Check((Length(Replies)=0) and (Pos('no pending',Desc)>0),
      'Movement did not cancel the pending impact');
    // Verify speed updates and movement ordering through the real session,
    // including another independently patrolling NPC in the same batch.
    V:=8669.776367+20; Move(V,M[12],4); Move(V,M[24],4);
    S.HandlePacket(M,Replies);
    BaseTick:=GetTickCount64+2000;
    S.PollWorld(BaseTick,Replies);
    Check((Length(Replies)>=2) and (Replies[0][0]=8) and
      (TB1008Wire.ReadBE32(Replies[0],7)=120) and
      (Replies[1][0]=4) and (Replies[1][7]=0) and
      (TB1008Wire.ReadBE32(Replies[1],8)=120),
      'Near-speed gage must precede movement for the same NPC');
    Move(Replies[0][31],V,4); Check(V=30,'Near speed not sent to client');
    Move(Replies[0][27],V,4); Check(V=12,'Near speed changed patrol speed');
    S.PollWorld(BaseTick+250,Replies);
    for I:=0 to High(Replies) do
      Check(not ((Replies[I][0]=8) and (Replies[I][1]=0) and
        (TB1008Wire.ReadBE32(Replies[I],7)=120)),
        'Unchanged near speed was sent on every movement leg');
    // Across the spider: over 60 from it, still inside the 60-unit home leash.
    V:=8669.776367-59; Move(V,M[12],4); Move(V,M[24],4);
    S.HandlePacket(M,Replies);
    S.PollWorld(BaseTick+500,Replies);
    Check((Length(Replies)>=2) and (Replies[0][0]=8) and
      (Replies[1][0]=4) and (Replies[1][7]=0),
      'Far-speed gage must precede the next run leg');
    Move(Replies[0][31],V,4); Check(V=32,'Far speed not restored from content');
  finally S.Free; Store.Free; end;
  G:=TB1008CombatWire.BuildSpiderGageProbe(1,0);
  Check(G[11]=0,'Dead gage HP');
  Failed:=False; try TB1008CombatWire.BuildSpiderGageProbe(1,-1);
    except on E: EKarosProtocol do Failed:=True; end;
  Check(Failed,'Probe permits negative HP');
end;

procedure EncounterTests;
var E: TB1008SpiderEncounter; R: TB1008AttackStart; Reason: string;
begin
  E:=TB1008SpiderEncounter.Create(200);
  try
    R:=TB1008CombatWire.ParseStart(Attack); R.ActionKind:=0;
    R.X:=8669.776367; R.Z:=6668.010254; R.Y:=604.350342;
    R.TargetX:=R.X; R.TargetZ:=R.Z; R.TargetY:=R.Y;
    R.Timestamp:=$FFFFFFFE;
    Check(not E.TryHit(R,1,2,3,1000,Reason),'Distant encounter accepted');
    Check(E.HP=200,'Rejected hit changed HP');
    Check(E.TryHit(R,R.X,R.Z,R.Y,1000,Reason,False) and (E.HP=200),
      'Dry-run mutated encounter');
    Check(E.TryHit(R,R.X,R.Z,R.Y,1000,Reason) and (E.HP=150),'First encounter hit');
    Check(not E.TryHit(R,R.X,R.Z,R.Y,3000,Reason),'Duplicate timestamp accepted');
    R.Timestamp:=$FFFFFFFD;
    Check(not E.TryHit(R,R.X,R.Z,R.Y,3000,Reason),'Stale timestamp accepted');
    R.Timestamp:=$FFFFFFFF;
    Check(not E.TryHit(R,R.X,R.Z,R.Y,900,Reason),'Server clock rollback accepted');
    Check(E.TryHit(R,R.X,R.Z,R.Y,1001,Reason) and (E.HP=100),'Next monotonic hit');
    R.Timestamp:=0;
    Check(E.TryHit(R,R.X,R.Z,R.Y,1002,Reason) and (E.HP=50),'Timestamp wrap rejected');
    R.Timestamp:=1;
    Check(E.TryHit(R,R.X,R.Z,R.Y,1003,Reason) and (E.HP=0),'Lethal hit');
    R.Timestamp:=2;
    Check(not E.TryHit(R,R.X,R.Z,R.Y,5000,Reason),'Dead spider hit again');
    Check(E.HP=0,'HP underflow');
    Check(not E.TryDespawn(3502),'Spider despawned before death animation');
    Check(E.TryDespawn(3503),'Spider did not despawn after death animation');
    Check(not E.TryDespawn(3504),'Spider despawned twice');
    Check(not E.TryRespawn(8502,5000),'Spider respawned before configured delay');
    Check(E.TryRespawn(8503,5000) and (E.HP=200),
      'Spider did not respawn with full HP');
    Check(E.TryHit(R,R.X,R.Z,R.Y,7004,Reason) and (E.HP=150),
      'Respawn did not reset combat admission state');
  finally E.Free; end;
end;

procedure GroundEncounterTests;
var E: TB1008SpiderEncounter; R: TB1008AttackStart; Reason: string;
  Handle: Cardinal;
begin
  // Every source and generated spider, including estimated spawn heights on
  // hills. Only ground range ignores the estimate, not actor-position drift.
  for Handle:=0 to B1008GeneratedSpiderHandleLast do
    if IsB1008SpiderHandle(Handle) then
    begin
      E:=TB1008SpiderEncounter.Create(500);
      try
        R:=Default(TB1008AttackStart);
        R.ActorID:=1; R.TargetKind:=1; R.TargetID:=Handle;
        R.X:=100; R.Z:=200; R.Y:=350;
        R.TargetX:=110; R.TargetZ:=200; R.TargetY:=350;
        Check(E.TryHit(R,Handle,100,200,350,110,200,250,15,1000,Reason,False),
          'Ground attack rejected estimated height for handle '+IntToStr(Handle));
        Check(not E.TryHit(R,Handle,100,200,350,130,200,250,15,1000,Reason,False),
          'Ground fix admitted an out-of-range hit');
        Check(not E.TryHit(R,Handle,100,200,300,110,200,250,15,1000,Reason,False),
          'Ground fix disabled actor height validation');
        R.TargetX:=150;
        Check(not E.TryHit(R,Handle,100,200,350,110,200,250,15,1000,Reason,False),
          'Ground fix disabled target position validation');
        R.TargetX:=110;
        Check(E.TryHit(R,Handle,94,200,350,110,200,250,15,1000,Reason,False),
          'Admission used stale world point instead of validated attack point');
        Check(E.HP=500,'Dry-run admission changed HP');
      finally E.Free; end;
    end;
end;

procedure CriticalTests;
const Rates:array[0..2]of Integer=(520,710,800);
  Floored:array[18..24]of Integer=(21,22,24,25,26,27,28);
var State,Mirror,Before:Cardinal;Hit:TB1008ResolvedHit;
  I,J,N,Count,Normal,Chance:Integer;Failed:Boolean;A:TB1008AttackStart;P,Q:TBytes;
  procedure Reject(MinD,MaxD,Rate,Multiplier:Integer);
  begin
    Before:=State;Failed:=False;
    try TB1008CombatDamage.Resolve(State,MinD,MaxD,Rate,Multiplier);
    except on E:EKarosProtocol do Failed:=True;end;
    Check(Failed and (State=Before),'Invalid critical profile changed RNG or was accepted');
  end;
begin
  State:=12345;
  for I:=18 to 24 do begin
    Hit:=TB1008CombatDamage.Resolve(State,I,I,10000,120);
    Check(Hit.Critical and (Hit.NormalDamage=I) and (Hit.Damage=Floored[I]),'Critical multiplier/floor');
    Hit:=TB1008CombatDamage.Resolve(State,I,I,0,120);
    Check(not Hit.Critical and (Hit.Damage=I),'Zero critical chance');
  end;
  Hit:=TB1008CombatDamage.Resolve(State,16,16,10000,120);
  Check(Hit.Critical and (Hit.Damage=19),'Unarmed critical');
  Hit:=TB1008CombatDamage.Resolve(State,1,1,10000,120);Check(Hit.Damage=1,'Small critical damage');
  Hit:=TB1008CombatDamage.Resolve(State,1000000,1000000,10000,1000);
  Check(Hit.Damage=10000000,'Critical multiplication overflow');
  Reject(18,24,-1,120);Reject(18,24,10001,120);Reject(18,24,520,99);
  Reject(18,24,520,1001);Reject(0,24,520,120);Reject(24,18,520,120);
  Reject(18,1000001,520,120);
  State:=0;Hit:=TB1008CombatDamage.Resolve(State,16,16,520,120);
  Check((State<>0) and (Hit.Damage in [16,19]),'Unarmed critical RNG stuck');
  for J:=0 to High(Rates) do begin
    State:=12345;Mirror:=State;Count:=0;
    for I:=1 to 100000 do begin
      Hit:=TB1008CombatDamage.Resolve(State,18,24,Rates[J],120);
      Normal:=TB1008CombatDamage.Roll(Mirror,18,24);
      Chance:=TB1008CombatDamage.Roll(Mirror,1,10000);
      Check((Hit.NormalDamage=Normal) and (State=Mirror) and
        (Hit.Critical=(Chance<=Rates[J])),'Resolution rerolled or lost class chance precision');
      N:=Normal;if Hit.Critical then begin Inc(Count);N:=Normal*120 div 100;end;
      Check(Hit.Damage=N,'One critical applied more than once');
    end;
    Check(Abs(Count-Rates[J]*10)<300,'Critical rate outside statistical tolerance');
    Writeln('PASS: critical rate ',Rates[J]/100:0:2,'%, observed ',Count,' / 100000');
  end;
  A:=Default(TB1008AttackStart);A.ActorID:=1;A.TargetKind:=1;A.TargetID:=120;A.Timestamp:=17;A.ActionID:=43;
  P:=TB1008CombatWire.BuildSpiderDamageProbe(A,1,2,3,28);
  Q:=TB1008CombatWire.BuildSpiderDamageProbe(A,1,2,3,28,True);
  Check((Length(Q)=47) and (Q[22]=2) and (Q[27]=0),'Critical wire type or reaction');
  for I:=0 to High(P) do if I<>22 then Check(P[I]=Q[I],'Critical changed unrelated wire byte');
  Check(P[22]=0,'Critical changed ordinary packet');Move(Q[23],N,4);Check(N=28,'Critical LE damage');
  Writeln('PASS: critical 0/100% endpoints, floor, invalid profiles, independent RNG and isolated type-2 packet flag');
end;

procedure MissFailTests;
var I,Misses,Fails,Damage:Integer;State,Before,Mirror:Cardinal;Failed:Boolean;
  Hit,Expected:TB1008ResolvedHit;Outcome:TB1008HitOutcome;
  A:TB1008AttackStart;P,Q:TBytes;E:TB1008SpiderEncounter;Reason:string;
  procedure Reject(MinD,MaxD,Crit,Multiplier,Chance:Integer);
  begin
    Before:=State;Failed:=False;
    try TB1008CombatDamage.ResolveOrdinary(State,MinD,MaxD,Crit,Multiplier,Chance);
    except on E:EKarosProtocol do Failed:=True;end;
    Check(Failed and (State=Before),'Invalid hit profile consumed RNG');
  end;
begin
  Check(TB1008Balance.MissFailBasisPoints(10,10,0)=200,'Equal levels must be 2% TOTAL');
  Check(TB1008Balance.MissFailBasisPoints(11,10,0)=133,'Player +1 interpolation');
  Check(TB1008Balance.MissFailBasisPoints(12,10,0)=66,'Player +2 interpolation');
  Check(TB1008Balance.MissFailBasisPoints(13,10,0)=0,'Player +3 must always connect');
  Check(TB1008Balance.MissFailBasisPoints(14,10,0)=0,'Player +4 must always connect');
  Check(TB1008Balance.MissFailBasisPoints(30,20,0)=0,'Current Lv30 hero must not miss Berneo mobs');
  Check(TB1008Balance.MissFailBasisPoints(10,11,0)=900,'Higher mob +1 penalty');
  Check(TB1008Balance.MissFailBasisPoints(10,12,0)=1600,'Higher mob +2 penalty');
  Check(TB1008Balance.MissFailBasisPoints(10,13,0)=2300,'Higher mob +3 penalty');
  Check(TB1008Balance.MissFailBasisPoints(10,14,0)=3000,'User anchor: mob +4 must have 30% TOTAL');
  Check(TB1008Balance.MissFailBasisPoints(10,15,0)=3700,'Higher mob +5 penalty');
  Check(TB1008Balance.MissFailBasisPoints(10,20,0)=7200,'Higher mob +10 penalty');
  Check(TB1008Balance.MissFailBasisPoints(10,23,0)=9300,'Last uncapped level gap');
  Check(TB1008Balance.MissFailBasisPoints(10,24,0)=9500,'First capped level gap retains 5% hit chance');
  Check(TB1008Balance.MissFailBasisPoints(10,10,1)=198,'+1 rating modestly lowers both outcomes');
  Check(TB1008Balance.MissFailBasisPoints(10,10,2)=196,'Small rating bonus must not erase misses');
  Check(TB1008Balance.MissFailBasisPoints(10,14,5)=2857,'Diminishing rating at the 30% anchor');
  Check(TB1008Balance.MissFailBasisPoints(10,15,5)=3523,'Rating applies against higher mobs');
  Check(TB1008Balance.MissFailBasisPoints(10,10,-1)=202,'Negative modifier raises failure chance');
  Check(TB1008Balance.MissFailBasisPoints(20,20,38)=144,'Level20 rating progression');
  Check(TB1008Balance.MissFailBasisPoints(10,14,100)=1500,'+100 rating halves failure chance');
  Check(TB1008Balance.MissFailBasisPoints(13,10,-100000)=0,'Player +3 rule precedes rating');
  Check(TB1008Balance.MissFailBasisPoints(1,1000,-100000)=9500,'Maximum penalty clamp');
  Check(TB1008Balance.MissFailBasisPoints(1,20,100000)=9,'Large positive rating has bounded diminishing effect');
  for I:=0 to 2 do Check(TB1008Balance.BaseAttributes(100+I*200).AttackRatingBonus=0,'Unfounded base rating');
  Failed:=False;try TB1008Balance.MissFailBasisPoints(0,1,0);
  except on E:EArgumentOutOfRangeException do Failed:=True;end;
  Check(Failed,'Zero player level accepted');
  Failed:=False;try TB1008Balance.MissFailBasisPoints(1,1,100001);
  except on E:EArgumentOutOfRangeException do Failed:=True;end;
  Check(Failed,'Out-of-range rating accepted');
  Misses:=0;Fails:=0;
  for I:=1 to 10000 do begin
    Outcome:=TB1008CombatDamage.OutcomeForRoll(I,200);
    if Outcome=hoMiss then Inc(Misses);
    if Outcome=hoFail then Inc(Fails);
    Check(TB1008CombatDamage.OutcomeForRoll(I,0)=hoNormal,'Zero chance emitted MISS/FAIL');
  end;
  Check((Misses=100) and (Fails=100),'Equal levels must split 1% / 1% exactly');
  Check(TB1008CombatDamage.OutcomeForRoll(100,200)=hoMiss,'MISS inclusive boundary');
  Check(TB1008CombatDamage.OutcomeForRoll(101,200)=hoFail,'FAIL first boundary');
  Check(TB1008CombatDamage.OutcomeForRoll(200,200)=hoFail,'FAIL inclusive boundary');
  Check(TB1008CombatDamage.OutcomeForRoll(201,200)=hoNormal,'Normal first boundary');
  State:=12345;Mirror:=State;
  for I:=1 to 1000 do begin
    Hit:=TB1008CombatDamage.ResolveOrdinary(State,18,24,520,120,0);
    Expected:=TB1008CombatDamage.Resolve(Mirror,18,24,520,120);
    Check((Hit.Damage=Expected.Damage) and (Hit.Outcome=Expected.Outcome) and
      (State=Mirror),'Zero miss chance changed normal/critical resolution');
  end;
  Misses:=0;Fails:=0;
  for I:=1 to 1000 do begin
    Hit:=TB1008CombatDamage.ResolveOrdinary(State,18,24,10000,120,10000);
    Check((Hit.Damage=0) and (Hit.NormalDamage=0) and not Hit.Critical,'Failed hit dealt damage or crit');
    if Hit.Outcome=hoMiss then Inc(Misses) else if Hit.Outcome=hoFail then Inc(Fails);
  end;
  Check((Misses>0) and (Fails>0) and (Misses+Fails=1000),'Guaranteed failure endpoints');
  Reject(0,24,520,120,10000);Reject(18,17,520,120,10000);Reject(18,1000001,520,120,10000);
  Reject(18,24,-1,120,10000);Reject(18,24,10001,120,10000);
  Reject(18,24,520,99,10000);Reject(18,24,520,1001,10000);
  Reject(18,24,520,120,-1);Reject(18,24,520,120,10001);
  A:=Default(TB1008AttackStart);A.ActorID:=1;A.TargetKind:=1;A.TargetID:=120;A.ActionID:=521;
  A.X:=100;A.Z:=200;A.Y:=300;A.TargetX:=100;A.TargetZ:=200;A.TargetY:=300;A.Timestamp:=10;
  P:=TB1008CombatWire.BuildSpiderDamageProbe(A,100,200,300,0,hoMiss);
  Q:=TB1008CombatWire.BuildSpiderDamageProbe(A,100,200,300,0,hoFail);
  Check((Length(P)=47) and (P[22]=5) and (Q[22]=6) and (P[27]=0),'MISS/FAIL packet types');
  Move(P[23],Damage,4);Check(Damage=0,'MISS damage must be zero');
  for I:=0 to High(P) do if I<>22 then Check(P[I]=Q[I],'FAIL changed unrelated wire fields');
  Failed:=False;try TB1008CombatWire.BuildSpiderDamageProbe(A,100,200,300,1,hoMiss);
  except on E:EKarosProtocol do Failed:=True;end;Check(Failed,'MISS positive damage accepted');
  Failed:=False;try TB1008CombatWire.BuildSpiderDamageProbe(A,100,200,300,0,hoCritical);
  except on E:EKarosProtocol do Failed:=True;end;Check(Failed,'Critical zero damage accepted');
  E:=TB1008SpiderEncounter.Create(1);
  try
    Check(E.TryHit(A,120,100,200,300,100,200,300,15,1000,Reason,True,0),Reason);
    Check((E.HP=1) and not E.TryDespawn(100000),'Zero damage killed/despawned 1HP mob');
    Check(not E.TryHit(A,120,100,200,300,100,200,300,15,1001,Reason,True,1),
      'Failed hit could be replayed as damage');
    Inc(A.Timestamp);
    Check(not E.TryHit(A,120,100,200,300,100,200,300,15,1001,Reason,True,-2),
      'Invalid negative damage accepted');
    Check(E.TryHit(A,120,100,200,300,100,200,300,15,1001,Reason,True,1) and (E.HP=0),
      'Ordinary hit after MISS could not kill');
  finally E.Free;end;
  Writeln('PASS: MISS/FAIL level/rating curve, exact 1%+1% split, zero chance, critical isolation, zero damage and replay');
end;

procedure SchedulingTests;
var
  State: TB1008ConnectionState;
  StartTick, DamageTick: UInt64;
  P: TBytes;
begin
  State := TB1008ConnectionState.Create(blMapLoadingProbe,nil,nil,nil);
  try
    State.ReserveCombatCycle(100,StartTick,DamageTick);
    Check((StartTick=100) and (DamageTick=1100),'First combat cycle timing');
    State.Enqueue(TBytes.Create(5,2),DamageTick);
    State.ReserveCombatCycle(118,StartTick,DamageTick);
    Check((StartTick=1100) and (DamageTick=2100),'Overlapping combat cycles');
    State.Enqueue(TBytes.Create(5,0),StartTick);
    Check(not State.TryPopDue(1099,P),'Scheduled reply released early');
    Check(State.TryPopDue(1100,P) and (P[1]=2),'First damage order');
    Check(State.TryPopDue(1100,P) and (P[1]=0),'Second start order');
    Check(not State.TryPopDue(1100,P),'Unexpected scheduled reply');
  finally
    State.Free;
  end;
end;

begin
  try Run; EncounterTests; GroundEncounterTests; SchedulingTests; CriticalTests; MissFailTests;
    Writeln('PASS: b1008 combat packets, admission, distance, scheduling and one death');
  except on E: Exception do begin Writeln('FAIL: '+E.Message); Halt(1); end; end;
end.
