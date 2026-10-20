program B1008AITests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Math,
  Emulator.Content, Emulator.AI.B1008, Emulator.World.B1008,Emulator.MonsterBalance.B1008;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then raise Exception.Create(AMessage);
end;

procedure Run;
var
  Mob: TEmulatorMobDefinition;
  Spawn: TEmulatorSpawnDefinition;
  AI: TB1008SpiderAI;
  Movement: TB1008MobMovement;
  AttackPhase: TB1008MobAttackPhase;
  Packet: TBytes;
  Parsed: TB1008Movement;
  ResumeTick: Integer;
begin
  Mob:=Default(TEmulatorMobDefinition);
  Mob.PatrolRadius:=12; Mob.MovementSpeed:=150; Mob.ChaseSpeed:=150;
  Spawn:=Default(TEmulatorSpawnDefinition);
  Spawn.X:=8669.776367; Spawn.Z:=6668.010254; Spawn.Y:=604.350342;
  AI:=TB1008SpiderAI.Create;
  try
    AI.Configure(Mob,Spawn);
    AI.Reset(1000);
    Check(not AI.Poll(1249,Movement),'Patrol ignored initial delay');
    Check(AI.Poll(1250,Movement) and (Movement.Mode=1),
      'First patrol movement was not started');
    Check((Abs(Movement.FromX-Spawn.X)<0.001) and
      (Abs(Movement.ToX-(Spawn.X+12))<0.001) and
      (Abs(Movement.ToZ-Spawn.Z)<0.001) and not IsNan(Movement.Heading),
      'First patrol target is outside its deterministic radius');
    Check(Abs(Movement.Heading-Pi/2)<0.001,
      'Patrol model faces away from a +X destination');
    Packet:=TB1008World.BuildActorMovement(7,1,Movement.Mode,120,
      Movement.FromX,Movement.FromZ,Movement.FromY,
      Movement.ToX,Movement.ToZ,Movement.ToY,Movement.Heading);
    Parsed:=TB1008World.ParseMovement(Packet);
    Check((Parsed.Timestamp=7) and (Parsed.Kind=1) and (Parsed.Mode=1) and
      (Parsed.CharacterID=120) and (Abs(Parsed.ToX-Movement.ToX)<0.001),
      'NPC movement wire roundtrip');
    Check(not AI.Poll(1329,Movement),'Patrol stopped before travel time');
    Check(AI.Poll(1330,Movement) and (Movement.Mode=2) and
      (Abs(Movement.FromX-Movement.ToX)<0.001) and
      (Abs(Movement.Heading-3*Pi/2)<0.001),
      'Patrol did not emit an exact stop point');
    Check(not AI.Poll(2329,Movement),'Patrol ignored minimum endpoint pause');
    ResumeTick:=2330;
    while (ResumeTick<=6330) and not AI.Poll(ResumeTick,Movement) do Inc(ResumeTick);
    Check((ResumeTick<=6330) and (Movement.Mode=1) and
      (Abs(Movement.ToX-Spawn.X)<0.001) and
      (Abs(Movement.ToZ-(Spawn.Z+12))<0.001),
      'Second patrol point is not deterministic');
    AI.Reset(8000,1);
    Check(not AI.Poll(8386,Movement),
      'Alternate patrol ignored its staggered start');
    Check(AI.Poll(8387,Movement) and (Movement.Mode=1) and
      (Abs(Movement.ToX-Spawn.X)<0.001) and
      (Abs(Movement.ToZ-(Spawn.Z+12))<0.001) and
      (Abs(Movement.Heading)<0.001),
      'Alternate patrol did not start with an independent phase');
    Spawn.X:=Spawn.X+100;
    AI.Configure(Mob,Spawn);
    Check(Abs(AI.X-(Spawn.X))<12.001,
      'Live spawn translation lost the patrol-relative position');
    AI.Reset(10000);
    Check(AI.Engage(10000,Movement) and AI.Engaged and
      (Movement.Mode=2) and (Abs(Movement.FromX-Movement.ToX)<0.001),
      'Engagement did not immediately cancel patrol movement');
    Check(not AI.PollChase(10249,Spawn.X+11,Spawn.Z,Spawn.Y,3,25,Movement),
      'Engagement stop was followed by chase in the same visual frame');
    Check(not AI.PollAttack(10249,Spawn.X+11,Spawn.Z,3,1.0,AttackPhase),
      'Engagement stop was followed by attack in the same visual frame');
    Check(
      AI.PollChase(10250,Spawn.X+11,Spawn.Z,Spawn.Y,3,25,Movement) and
      (Movement.Mode=0) and
      (Abs(Movement.ToX-(Spawn.X+7.5))<0.01) and
      (AI.ActiveChaseSpeed=30),
      'Engaged spider did not select near speed 30');
    Check(not AI.PollChase(10499,Spawn.X+11,Spawn.Z,Spawn.Y,3,25,Movement) and
      (AI.X>Spawn.X) and (AI.X<Spawn.X+7.5),
      'Chase interpolation or travel duration is invalid');
    Check(AI.PollChase(10500,Spawn.X+11,Spawn.Z,Spawn.Y,3,25,Movement) and
      (Movement.Mode=0) and (Abs(Movement.ToX-(Spawn.X+8.6))<0.01),
      'Near chase did not publish the short final leg');
    Check(not AI.PollChase(10536,Spawn.X+11,Spawn.Z,Spawn.Y,3,25,Movement),
      'Near final leg stopped too early');
    Check(AI.PollChase(10537,Spawn.X+11,Spawn.Z,Spawn.Y,3,25,Movement) and
      (Movement.Mode=2) and (Abs(Movement.ToX-(Spawn.X+8.6))<0.01),
      'Chase did not stop at its authoritative endpoint');
    Check(not AI.PollChase(10538,Spawn.X+11,Spawn.Z,Spawn.Y,3,25,Movement),
      'Spider moved while already inside attack range');
    Check(AI.PollAttack(10538,Spawn.X+11,Spawn.Z,3,1.0,AttackPhase) and
      (AttackPhase=mapStart), 'Autonomous attack did not start in range');
    Check(not AI.PollAttack(11537,Spawn.X+11,Spawn.Z,3,1.0,AttackPhase),
      'Autonomous damage fired before the animation boundary');
    Check(AI.PollAttack(11538,Spawn.X+11,Spawn.Z,3,1.0,AttackPhase) and
      (AttackPhase=mapDamage), 'Autonomous attack did not reach damage phase');
    Check(AI.PollAttack(11539,Spawn.X+11,Spawn.Z,3,1.0,AttackPhase) and
      (AttackPhase=mapStart), 'Autonomous attack did not repeat');
    AI.Reset(20000);
    Check(AI.Engage(20000,Movement),'Second engagement did not start');
    Check(not AI.PollChase(20249,Spawn.X+90,Spawn.Z,Spawn.Y,3,100,Movement),
      'Long chase ignored engagement stop interval');
    Check(AI.PollChase(20250,Spawn.X+90,Spawn.Z,Spawn.Y,3,100,Movement) and
      (Movement.Mode=0) and (Abs(Movement.ToX-(Spawn.X+37.5))<0.01),
      'Speed 150 chase must use run mode and a 250 ms leg');
    Check(AI.PollChase(20500,Spawn.X+50,Spawn.Z,Spawn.Y,3,60,Movement) and
      (Movement.Mode=0) and (Abs(Movement.FromX-(Spawn.X+37.5))<0.01) and
      (Abs(Movement.ToX-(Spawn.X+45))<0.01) and (AI.ActiveChaseSpeed=30),
      'Segmented chase inserted a stop instead of chaining');
    Check(AI.PollChase(20750,Spawn.X+50,Spawn.Z,Spawn.Y,3,60,Movement) and
      (Movement.Mode=0) and (Abs(Movement.ToX-(Spawn.X+47.6))<0.01),
      'Near chase did not retain speed 30');
    Check(AI.PollChase(21000,Spawn.X+50,Spawn.Z,Spawn.Y,3,60,Movement) and
      (Movement.Mode=2), 'Chase did not stop once at attack range');
    AI.Reset(30000);
    Check(AI.Engage(30000,Movement),'Return engagement did not start');
    Check(not AI.PollChase(30249,Spawn.X+20,Spawn.Z,Spawn.Y,3,60,Movement),
      'Return scenario ignored engagement stop interval');
    Check(AI.PollChase(30250,Spawn.X+20,Spawn.Z,Spawn.Y,3,60,Movement) and
      (Movement.Mode=0), 'Return test chase did not start');
    Check(AI.PollChase(30350,Spawn.X+61,Spawn.Z,Spawn.Y,3,60,Movement) and
      Movement.ReturningHome and (Movement.Mode=2),
      'Spider did not stop its chase before ReturnHome');
    Check(AI.PollChase(30600,Spawn.X+61,Spawn.Z,Spawn.Y,3,60,Movement) and
      Movement.ReturningHome and (Movement.Mode=1) and AI.Engaged,
      'Spider did not walk back after the ReturnHome stop');
    Check(AI.PollChase(30620,Spawn.X+61,Spawn.Z,Spawn.Y,3,60,Movement) and
      Movement.ReturningHome and (Movement.Mode=2) and not AI.Engaged,
      'Spider did not finish ReturnHome at its spawn');
    Check(not AI.Poll(31619,Movement),'Patrol resumed before post-return idle');
    Check(AI.Poll(31620,Movement) and (Movement.Mode=1),
      'Patrol did not resume after ReturnHome');
    Mob.PatrolRadius:=22; Mob.MovementSpeed:=12; Mob.ChaseSpeed:=32;
    AI.Configure(Mob,Spawn);
    AI.Reset(40000);
    Check(AI.Engage(40000,Movement),'Video-speed engagement did not start');
    Check(AI.PollChase(40250,Spawn.X+80,Spawn.Z,Spawn.Y,3,100,Movement) and
      (Movement.Mode=0) and (Abs(Movement.ToX-(Spawn.X+8))<0.01),
      'Video-speed chase first leg is invalid');
    Check(not AI.PollChase(40499,Spawn.X+80,Spawn.Z,Spawn.Y,3,100,Movement),
      'Configured chase speed completed too early');
    Check(AI.PollChase(40500,Spawn.X+80,Spawn.Z,Spawn.Y,3,100,Movement) and
      (Movement.Mode=0) and (Abs(Movement.FromX-(Spawn.X+8))<0.01),
      'Configured chase speed was not applied');
    // High-speed regression: patrol 15, chase 150, radius 40. The return
    // destination must remain home for the whole walk, with no intermediate
    // eight-unit boundaries or artificial 250 ms minimum on the last step.
    Mob.PatrolRadius:=40; Mob.MovementSpeed:=15; Mob.ChaseSpeed:=150;
    AI.Configure(Mob,Spawn);
    AI.Reset(50000);
    Check(AI.Engage(50000,Movement),'Live-speed engagement did not start');
    Check(AI.PollChase(50250,Spawn.X+80,Spawn.Z,Spawn.Y,13,100,Movement) and
      (Movement.Mode=0),'Live chase did not select native run speed');
    Packet:=TB1008World.BuildActorMovement(50250,1,Movement.Mode,120,
      Movement.FromX,Movement.FromZ,Movement.FromY,
      Movement.ToX,Movement.ToZ,Movement.ToY,Movement.Heading);
    Parsed:=TB1008World.ParseMovement(Packet);
    Check((Parsed.Kind=1) and (Parsed.Mode=0),'Run mode lost on the wire');
    Check(AI.PollChase(50450,Spawn.X+101,Spawn.Z,Spawn.Y,13,100,Movement) and
      (Movement.Mode=2) and Movement.ReturningHome and
      (Abs(AI.X-(Spawn.X+30))<0.01),'Leash used walk speed during run');
    Check(AI.PollChase(50700,Spawn.X+101,Spawn.Z,Spawn.Y,13,100,Movement) and
      (Movement.Mode=1) and (Abs(Movement.ToX-Spawn.X)<0.01),
      'Return must publish the complete home destination');
    Check(not AI.PollChase(51700,Spawn.X+101,Spawn.Z,Spawn.Y,13,100,Movement) and
      (Abs(AI.X-(Spawn.X+15))<0.01),'Return walk has an intermediate pause');
    Check(not AI.PollAttack(51700,AI.X,AI.Z,13,1.0,AttackPhase),
      'Returning spider resumed combat before reaching home');
    Check(not AI.PollChase(52699,Spawn.X+101,Spawn.Z,Spawn.Y,13,100,Movement),
      'Return completed before the native walk duration');
    Check(AI.PollChase(52700,Spawn.X+101,Spawn.Z,Spawn.Y,13,100,Movement) and
      (Movement.Mode=2) and not AI.Engaged,'Return did not finish at home');
    Mob.ChaseSpeed:=50;
    AI.Configure(Mob,Spawn); AI.Reset(60000); AI.Engage(60000,Movement);
    Check(AI.PollChase(60250,Spawn.X+60,Spawn.Z,Spawn.Y,13,300,Movement) and
      (AI.ActiveChaseSpeed=30) and (Abs(Movement.ToX-(Spawn.X+7.5))<0.01),
      'Sixty-unit boundary did not select near speed');
    Check(AI.PollChase(60500,Spawn.X+68.5,Spawn.Z,Spawn.Y,13,300,Movement) and
      (AI.ActiveChaseSpeed=50) and (Abs(Movement.ToX-(Spawn.X+20))<0.01),
      'Moving target beyond sixty units did not restore far speed 50');
    Check(AI.PollChase(60750,Spawn.X+301,Spawn.Z,Spawn.Y,13,300,Movement) and
      Movement.ReturningHome,'Leaving 300-unit leash did not start return');
    Check(AI.PollChase(61000,Spawn.X+25,Spawn.Z,Spawn.Y,13,300,Movement) and
      Movement.ReturningHome and (Movement.Mode=1),
      'Re-entering leash without attacking interrupted return');
    Check(AI.Engage(61500,Movement) and (Movement.Mode=2) and
      (Abs(Movement.ToX-(Spawn.X+12.5))<0.01) and not AI.Moving,
      'Fresh attack failed to interrupt return at its interpolated position');
    Check(not AI.Engage(61501,Movement),
      'Repeated attack reset an already active engagement');
    Check(not AI.PollChase(61750,AI.X,AI.Z,AI.Y,13,300,Movement),
      'Re-engaged returning spider continued walking home');
    Check(AI.PollAttack(61750,AI.X,AI.Z,13,1,AttackPhase) and
      (AttackPhase=mapStart),'Interrupted return did not resume combat');
    AI.Stop;
    Check(not AI.Poll(High(UInt64),Movement),'Stopped AI emitted movement');
    Mob.PatrolRadius:=0;
    AI.Configure(Mob,Spawn);
    AI.Reset(0);
    Check(not AI.Poll(High(UInt64),Movement),'Zero-radius AI emitted movement');
  finally
    AI.Free;
  end;
end;

procedure IndependentPatrolTests;
const Count=101;StepMS=100;
var Mob:TEmulatorMobDefinition;Spawn:TEmulatorSpawnDefinition;
  Actors:array[0..Count-1] of TB1008SpiderAI;Shadow:TB1008SpiderAI;
  IdleSince,FirstPause,MoveSince,TravelMS:array[0..Count-1] of Integer;
  Varied:array[0..Count-1] of Boolean;
  DestX,DestZ:array[0..Count-1] of Single;
  M,CopyMove:TB1008MobMovement;Emitted,CopyEmitted:Boolean;
  I,T,Pause,MovingCount,StoppedNow,MaxBurst,AllIdleMS,MaxAllIdleMS,VariedCount:Integer;
  PauseSum:Int64;PauseCount:Integer;
begin
  Mob:=Default(TEmulatorMobDefinition);Spawn:=Default(TEmulatorSpawnDefinition);
  Mob.PatrolRadius:=40;Mob.MovementSpeed:=15;Mob.ChaseSpeed:=50;
  for I:=0 to Count-1 do begin
    Actors[I]:=nil;IdleSince[I]:=-1;FirstPause[I]:=-1;Varied[I]:=False;
  end;
  Shadow:=nil;MaxBurst:=0;AllIdleMS:=0;MaxAllIdleMS:=0;PauseSum:=0;PauseCount:=0;
  try
    for I:=0 to Count-1 do begin
      Actors[I]:=TB1008SpiderAI.Create;Actors[I].Configure(Mob,Spawn);Actors[I].Reset(0,I);
    end;
    Shadow:=TB1008SpiderAI.Create;Shadow.Configure(Mob,Spawn);Shadow.Reset(0,20);
    // Four minutes of simulation, no wall-clock sleeps. All spawns, radii,
    // speeds and poll timestamps identical: only per-actor scheduling differs.
    for T:=0 to 240000 div StepMS do begin
      MovingCount:=0;StoppedNow:=0;
      for I:=0 to Count-1 do begin
        Emitted:=Actors[I].Poll(UInt64(T)*StepMS,M);
        if I=20 then begin
          CopyEmitted:=Shadow.Poll(UInt64(T)*StepMS,CopyMove);
          Check(Emitted=CopyEmitted,'Another actor changed this patrol timer');
          if Emitted then Check((M.Mode=CopyMove.Mode) and
            (M.FromX=CopyMove.FromX) and (M.FromZ=CopyMove.FromZ) and
            (M.ToX=CopyMove.ToX) and (M.ToZ=CopyMove.ToZ),'Patrol depends on shared random state/order');
        end;
        if Emitted then begin
          if M.Mode=1 then begin
            Check(Abs(Sqrt(Sqr(M.ToX)+Sqr(M.ToZ))-40)<0.001,'Patrol radius changed');
            if IdleSince[I]>=0 then begin
              Pause:=T*StepMS-IdleSince[I];
              Check((Pause>=1000) and (Pause<5000+StepMS),'Independent pause outside 1..5 seconds');
              if FirstPause[I]<0 then FirstPause[I]:=Pause
              else if FirstPause[I]<>Pause then Varied[I]:=True;
              Inc(PauseSum,Pause);Inc(PauseCount);
            end;
            MoveSince[I]:=T*StepMS;
            TravelMS[I]:=Ceil(Sqrt(Sqr(M.ToX-M.FromX)+Sqr(M.ToZ-M.FromZ))/15*1000);
            DestX[I]:=M.ToX;DestZ[I]:=M.ToZ;
          end else begin
            Check(M.Mode=2,'Unexpected patrol mode');
            Check((T*StepMS-MoveSince[I]>=TravelMS[I]) and
              (T*StepMS-MoveSince[I]<TravelMS[I]+StepMS),'Patrol speed/timing changed');
            Check((Abs(M.FromX-DestX[I])<0.001) and (Abs(M.FromZ-DestZ[I])<0.001) and
              (M.FromX=M.ToX) and (M.FromZ=M.ToZ),'Endpoint stop teleported');
            IdleSince[I]:=T*StepMS;Inc(StoppedNow);
          end;
        end;
        if Actors[I].Moving then Inc(MovingCount);
      end;
      if T*StepMS>=10000 then begin
        MaxBurst:=Max(MaxBurst,StoppedNow);
        if MovingCount=0 then Inc(AllIdleMS,StepMS) else AllIdleMS:=0;
        MaxAllIdleMS:=Max(MaxAllIdleMS,AllIdleMS);
      end;
    end;
    VariedCount:=0;for I:=0 to Count-1 do if Varied[I] then Inc(VariedCount);
    Check(VariedCount=Count,'Actors retain constant per-cycle pauses');
    Check(FirstPause[0]<>FirstPause[20],'Full actor variant collapsed to four directions/ten offsets');
    Check(MaxBurst<Count div 2,'Population still stops in synchronized waves');
    Check(MaxAllIdleMS<1000,'Population shares a long global idle');
    Check((PauseCount>1000) and (PauseSum/PauseCount>2800) and
      (PauseSum/PauseCount<3300),'Patrol mean rest drifted away from three seconds');
    Shadow.Reset(0,Low(Integer));Shadow.Poll(2000,M);
    Writeln(Format('PASS: %d independent patrols, %d pauses, mean %.0f ms; max simultaneous stops %d, all-idle %d ms',
      [Count,PauseCount,PauseSum/PauseCount,MaxBurst,MaxAllIdleMS]));
  finally
    Shadow.Free;for I:=0 to Count-1 do Actors[I].Free;
  end;
end;

procedure FormationTests;
var Mob: TEmulatorMobDefinition; Spawn: TEmulatorSpawnDefinition;
  Actors: array[0..2] of TB1008SpiderAI; M: TB1008MobMovement;
  Phase: TB1008MobAttackPhase; I,J,T: Integer; A: Single;
begin
  Mob:=Default(TEmulatorMobDefinition); Spawn:=Default(TEmulatorSpawnDefinition);
  Mob.PatrolRadius:=40; Mob.MovementSpeed:=15; Mob.ChaseSpeed:=50;
  for I:=0 to 2 do Actors[I]:=nil;
  try
    for I:=0 to 2 do begin
      Spawn.X:=50+I*12; Actors[I]:=TB1008SpiderAI.Create;
      Actors[I].Configure(Mob,Spawn); Actors[I].Reset(1000);
      Actors[I].Engage(1000,M); A:=I*2*Pi/3;
      Actors[I].SetApproachOffset(10.4*Cos(A),10.4*Sin(A));
    end;
    for T:=1250 to 8000 do if T mod 50=0 then
      for I:=0 to 2 do Actors[I].PollChase(T,0,0,0,13,300,M);
    for I:=0 to 2 do begin
      Check(not Actors[I].Moving,'Formation actor did not settle');
      Check(Actors[I].PollAttack(8000,0,0,13,1,Phase),'Formation actor outside actual melee range');
      for J:=I+1 to 2 do
        Check(Sqrt(Sqr(Actors[I].X-Actors[J].X)+Sqr(Actors[I].Z-Actors[J].Z))>17,
          'Three attackers stacked at one endpoint');
    end;
    for T:=8050 to 14000 do if T mod 50=0 then
      for I:=0 to 2 do Actors[I].PollChase(T,50,50,0,13,300,M);
    for I:=0 to 2 do begin
      A:=I*2*Pi/3;
      Check((Abs(Actors[I].X-(50+10.4*Cos(A)))<0.3) and
        (Abs(Actors[I].Z-(50+10.4*Sin(A)))<0.3),'Formation did not follow a moving player');
    end;
    Actors[2].SetApproachOffset(31.2,0);
    for T:=14050 to 19000 do if T mod 50=0 then
      Actors[2].PollChase(T,50,50,0,13,300,M);
    Check(not Actors[2].PollAttack(19000,50,50,13,1,Phase),'Outer waiting slot granted ranged melee damage');
  finally for I:=0 to 2 do Actors[I].Free; end;
  Writeln('PASS: three distinct chase endpoints, moving formation, real melee range for outer waiting slots');
end;

procedure AvoidanceTests;
var Mob: TEmulatorMobDefinition; Spawn: TEmulatorSpawnDefinition;
  AI: TB1008SpiderAI; M: TB1008MobMovement;
begin
  Mob:=Default(TEmulatorMobDefinition); Spawn:=Default(TEmulatorSpawnDefinition);
  Mob.PatrolRadius:=40; Mob.MovementSpeed:=15; Mob.ChaseSpeed:=50;
  AI:=TB1008SpiderAI.Create;
  try
    AI.Configure(Mob,Spawn); AI.Reset(1000);
    Check(AI.Poll(1250,20,0,10,M) and (M.Mode=1) and
      (Abs(M.ToX)<0.001) and (Abs(M.ToZ-40)<0.001),'Patrol did not avoid player corridor');
    Check(not AI.Engaged,'Avoidance must not aggro');
    AI.Reset(1000); Check(AI.Poll(1250,M),'Prepare moving patrol');
    Check(AI.Poll(1500,20,0,10,M) and (M.Mode=2) and not AI.Moving and
      (Abs(M.FromX-3.75)<0.001) and (M.FromX=M.ToX),'Cancel corridor at current interpolated point');
    Check(not AI.Poll(1749,20,0,10,M),'Avoidance stop not isolated');
    Check(AI.Poll(1750,20,0,10,M) and (M.Mode=1) and (Abs(M.ToZ-40)<0.001),
      'Patrol did not resume on an alternate safe leg');
    AI.Reset(2000); Check(AI.Poll(2250,0,0,10,M) and (M.ToX=40),
      'Overlapping actor must be allowed to leave the player');
    AI.Reset(2000); Check(AI.Poll(2250,M),'Prepare approach-yield patrol');
    Check(AI.Poll(2500,15,0,20,M,True) and (M.Mode=2) and not AI.Moving and
      (Abs(M.FromX-3.75)<0.001),'Nearby patrol did not yield at current position');
    Check(not AI.Poll(3500,8,0,20,M,True) and not AI.Engaged,
      'Yielding passive mob ran away or aggroed without attack');
    Check(AI.Poll(4000,80,0,20,M,True) and (M.Mode=1),'Yielding mob did not resume when player left');
    AI.Engage(4050,M);
    Check(not AI.Poll(5000,20,0,10,M),'Avoidance replaced active combat');
  finally AI.Free; end;
  Writeln('PASS: passive patrol avoids player corridor, cancels interpolated leg, resumes without aggro');
end;

procedure SlowerAttackTests;
var Mob:TEmulatorMobDefinition;Spawn:TEmulatorSpawnDefinition;AI:TB1008SpiderAI;
  M:TB1008MobMovement;Phase:TB1008MobAttackPhase;Speed:Single;
begin
  Mob:=Default(TEmulatorMobDefinition);Mob.ChaseSpeed:=50;
  Spawn:=Default(TEmulatorSpawnDefinition);AI:=TB1008SpiderAI.Create;
  try
    Speed:=TB1008MonsterBalance.AttackSpeed(1);
    Check(Abs(Speed-1/1.4)<0.0001,'Cycle multiplier');
    Check(Abs(TB1008MonsterBalance.AttackSpeed(1.25)-1.25/1.4)<0.0001,'Relative species speed lost');
    AI.Configure(Mob,Spawn);AI.Reset(1000);AI.Engage(1000,M);
    Check(AI.PollAttack(1250,0,0,10,Speed,Phase) and (Phase=mapStart),'Slowed attack start');
    Check(not AI.PollAttack(2250,0,0,10,Speed,Phase),'Damage at old one-second timing');
    Check(not AI.PollAttack(2649,0,0,10,Speed,Phase),'Slowed impact too early');
    Check(AI.PollAttack(2650,0,0,10,Speed,Phase) and (Phase=mapDamage),'Slowed impact not delivered');
    Check(AI.PollAttack(2651,0,0,10,Speed,Phase) and (Phase=mapStart),'Slowed repeat stopped');
    Check(not AI.PollAttack(4050,0,0,10,Speed,Phase),'Repeated impact too early');
    Check(AI.PollAttack(4051,0,0,10,Speed,Phase) and (Phase=mapDamage),'Repeated impact not slowed');
  finally AI.Free;end;
  Writeln('PASS: mob1400ms windup, repeated attacks, relative species speed');
end;

procedure StunTests;
var Mob:TEmulatorMobDefinition;Spawn:TEmulatorSpawnDefinition;AI,Other:TB1008SpiderAI;
  M:TB1008MobMovement;Phase:TB1008MobAttackPhase;X:Single;T:Integer;
begin
  Mob:=Default(TEmulatorMobDefinition);Mob.PatrolRadius:=40;Mob.MovementSpeed:=15;Mob.ChaseSpeed:=50;
  Spawn:=Default(TEmulatorSpawnDefinition);AI:=TB1008SpiderAI.Create;Other:=TB1008SpiderAI.Create;
  try
    AI.Configure(Mob,Spawn);Other.Configure(Mob,Spawn);AI.Reset(1000);Other.Reset(1000);
    AI.Engage(1000,M);Other.Engage(1000,M);
    Check(AI.PollAttack(1250,0,0,10,1,Phase) and (Phase=mapStart),'Arm interrupted attack');
    Check(AI.Stun(1500,3000,M) and (M.Mode=2) and AI.Engaged,'Apply stun');
    Check(Other.PollAttack(1500,0,0,10,1,Phase),'Other actor frozen');
    for T:=1500 to 4499 do begin
      Check(not AI.PollAttack(T,0,0,10,1,Phase),'Damage/start during stun');
      Check(not AI.PollChase(T,80,0,0,10,300,M),'Chase during stun');
      Check(not AI.Poll(T,M),'Patrol during stun');
      AI.Engage(T,M); // A second player hit must not clear stun.
    end;
    Check(AI.PollAttack(4500,0,0,10,1,Phase) and (Phase=mapStart),'Old pending damage survived stun');
    Check(not AI.PollAttack(5499,0,0,10,1,Phase),'Post-stun attack shortened');
    Check(AI.PollAttack(5500,0,0,10,1,Phase) and (Phase=mapDamage),'Attack did not resume');
    AI.Reset(6000);Check(AI.Poll(6250,M),'Patrol before stun');
    AI.UpdatePosition(6500);X:=AI.X;
    Check(AI.Stun(6500,3000,M) and not AI.Moving and (Abs(M.FromX-X)<0.001),'Stun teleported actor');
    AI.UpdatePosition(8000);Check(Abs(AI.X-X)<0.001,'Stunned actor interpolated');
    Check(not AI.Poll(9499,M) and AI.Poll(9500,M),'Patrol stun expiry');
    AI.Stun(9600,3000,M);AI.Stop;
    Check(not AI.Stun(9700,3000,M),'Dead/stopped actor stunned');
    AI.Reset(10000);Check(AI.Poll(10250,M),'Respawn retained old stun');
  finally AI.Free;Other.Free;end;
  Writeln('PASS: stun cancels pending damage/movement, keeps aggro, independent actors, exact expiry, reset');
end;

procedure SlowMovementTests;
var AI:TB1008SpiderAI;Mob:TEmulatorMobDefinition;Spawn:TEmulatorSpawnDefinition;
  M:TB1008MobMovement;Failed:Boolean;
begin
  Mob:=Default(TEmulatorMobDefinition);Mob.PatrolRadius:=100;
  Mob.MovementSpeed:=10;Mob.ChaseSpeed:=100;Spawn:=Default(TEmulatorSpawnDefinition);
  AI:=TB1008SpiderAI.Create;
  try
    AI.Configure(Mob,Spawn);AI.Reset(1000);Check(AI.Poll(1250,M),'Slow fixture patrol');
    Check(AI.SetSpeedMultiplier(2250,0.5,M) and (M.Mode=1) and
      (Abs(M.FromX-10)<0.001) and (Abs(M.ToX-100)<0.001),
      'Slow did not reissue the remaining leg from its interpolated point');
    AI.UpdatePosition(3250);Check(Abs(AI.X-15)<0.001,'Slow interpolation disagrees with wire speed');
    Check(not AI.SetSpeedMultiplier(3250,0.5,M),'Identical multiplier restarted movement');
    Check(AI.SetSpeedMultiplier(3250,1,M) and (Abs(M.FromX-15)<0.001),'Expiry teleported actor');
    AI.UpdatePosition(4250);Check(Abs(AI.X-25)<0.001,'Expiry did not restore movement speed');
    AI.SetSpeedMultiplier(4500,0.5,M);AI.Reset(5000);
    Check((Abs(AI.ActiveChaseSpeed-100)<0.001) and AI.Poll(5250,M),'Respawn retained slow');
    AI.UpdatePosition(6250);Check(Abs(AI.X-10)<0.001,'Respawn patrol retained slow');
    Failed:=False;try AI.SetSpeedMultiplier(6300,0,M);except on E:EArgumentOutOfRangeException do Failed:=True;end;
    Check(Failed,'Invalid multiplier accepted');
  finally AI.Free;end;
  Writeln('PASS: slow changes an active leg without teleport, expiry restores speed, respawn clears slow');
end;

begin
  try
    Run;
    SlowMovementTests;
    SlowerAttackTests;
    StunTests;
    IndependentPatrolTests;
    AvoidanceTests;
    FormationTests;
    Writeln('PASS: deterministic Idle/Patrol scheduler and NPC movement wire');
  except
    on E:Exception do begin Writeln('FAIL: '+E.Message); Halt(1); end;
  end;
end.
