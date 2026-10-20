unit Emulator.AI.B1008;

interface

uses
  Emulator.Content;

type
  TB1008MobAttackPhase = (mapStart, mapDamage);

  TB1008MobMovement = record
    Mode: Byte;
    ReturningHome: Boolean;
    FromX, FromZ, FromY: Single;
    ToX, ToZ, ToY: Single;
    Heading: Single;
  end;

  // Deterministic, session-owned Idle/Patrol/Chase/Attack/ReturnHome scheduler.
  TB1008SpiderAI = class
  private
    FInitialized: Boolean;
    FEnabled: Boolean;
    FStopped: Boolean;
    FEngaged: Boolean;
    FReturning: Boolean;
    FChaseStopSent: Boolean;
    FMoving: Boolean;
    FHomeX, FHomeZ, FHomeY, FHomeHeading: Single;
    FX, FZ, FY, FHeading: Single;
    FMoveFromX, FMoveFromZ, FMoveFromY: Single;
    FMoveToX, FMoveToZ, FMoveToY: Single;
    FMoveStartTick, FMoveEndTick: UInt64;
    FAttackPending: Boolean;
    FAttackDamageTick, FNextAttackTick: UInt64;
    FStunUntilTick:UInt64;
    FPatrolRadius, FMovementSpeed, FChaseSpeed: Single;
    FActiveChaseSpeed: Single;
    FSpeedMultiplier:Single;
    FApproachX,FApproachZ: Single;
    FNextTick: UInt64;
    FPatrolIndex: Integer;
    FPatrolStep: Integer;
    FPatrolRandomState: Cardinal;
    function NextPatrolIdleMS: Cardinal;
    procedure BeginMovement(ANowTick: UInt64;
      const AMovement: TB1008MobMovement; ADurationMS: UInt64);
  public
    procedure UpdatePosition(ANowTick: UInt64);
    procedure PauseForAdmission(ANowTick:UInt64);
    procedure Configure(const AMob: TEmulatorMobDefinition;
      const ASpawn: TEmulatorSpawnDefinition);
    procedure Reset(ANowTick: UInt64); overload;
    procedure Reset(ANowTick: UInt64; APatrolVariant: Integer); overload;
    procedure Stop;
    function Stun(ANowTick:UInt64;DurationMS:Cardinal;out Movement:TB1008MobMovement):Boolean;
    function SetSpeedMultiplier(ANowTick:UInt64;Multiplier:Single;out Movement:TB1008MobMovement):Boolean;
    procedure SetApproachOffset(AX,AZ: Single);
    function Engage(ANowTick: UInt64;
      out AStopMovement: TB1008MobMovement): Boolean;
    function Poll(ANowTick: UInt64; out AMovement: TB1008MobMovement): Boolean; overload;
    function Poll(ANowTick: UInt64; APlayerX,APlayerZ,AClearance: Single;
      out AMovement: TB1008MobMovement; AYieldNearby:Boolean=False): Boolean; overload;
    function PollChase(ANowTick: UInt64; APlayerX,APlayerZ,APlayerY,
      AAttackRange,ALeashRadius: Single;
      out AMovement: TB1008MobMovement): Boolean;
    function PollAttack(ANowTick: UInt64; APlayerX,APlayerZ,
      AAttackRange,AAttackSpeed: Single;
      out APhase: TB1008MobAttackPhase): Boolean;
    property X: Single read FX;
    property Z: Single read FZ;
    property Y: Single read FY;
    property Heading: Single read FHeading;
    property Moving: Boolean read FMoving;
    property Engaged: Boolean read FEngaged;
    property StunUntilTick:UInt64 read FStunUntilTick;
    property ReturningHome: Boolean read FReturning;
    property ActiveChaseSpeed: Single read FActiveChaseSpeed;
  end;

implementation

uses
  System.Math,System.SysUtils;

const
  // Authored pacing: retain the old three-second mean, not a shared period.
  B1008PatrolIdleMinMS = 1000;
  B1008PatrolIdleMaxMS = 5000;
  B1008ReturnToPatrolMS = 1000;
  B1008MinimumAttackMS = 250;
  B1008EngagementStopMS = 250;
  B1008BaseAttackMS = 1000;
  // Appearance already places every actor at its authoritative spawn point.
  // Start the first patrol promptly, but retain a small per-actor offset so a
  // group does not begin moving in lockstep. Every subsequent endpoint pause
  // comes from the actor's own sequence, not the four directions/ten offsets.
  B1008InitialPatrolDelayMS = 250;
  // Coprime to the 1250 ms window: unlike 125, does not repeat every 10 mobs.
  B1008PatrolVariantDelayMS = 137;
  // Re-evaluate a moving target every quarter second. A fixed eight-unit
  // leg takes only 54 ms at speed 150 and magnifies transport polling delays.
  B1008ChaseLegMS = 250;
  B1008NearChaseDistance: Single = 60;
  B1008NearChaseSpeed: Single = 30;

function MovementHeading(AFromX,AFromZ,AToX,AToZ: Single): Single;
begin
  // b1008 faces zero toward +Z. Adding Pi made the model look directly away
  // from every destination (most obvious when walking left).
  Result:=ArcTan2(AToX-AFromX,AToZ-AFromZ);
  while Result>=2*Pi do Result:=Result-2*Pi;
  while Result<0 do Result:=Result+2*Pi;
end;

function StopHeading(AMovementHeading: Single): Single;
begin
  // In b1008 the mode-2 stop field uses the opposite visual basis from the
  // mode-1 movement field. Adding Pi preserves the actor's on-screen facing.
  Result:=AMovementHeading+Pi;
  while Result>=2*Pi do Result:=Result-2*Pi;
end;

procedure TB1008SpiderAI.UpdatePosition(ANowTick: UInt64);
var
  Part: Double;
begin
  if not FMoving then Exit;
  if (FMoveEndTick<=FMoveStartTick) or (ANowTick>=FMoveEndTick) then
  begin
    FX:=FMoveToX; FZ:=FMoveToZ; FY:=FMoveToY;
    Exit;
  end;
  if ANowTick<=FMoveStartTick then
  begin
    FX:=FMoveFromX; FZ:=FMoveFromZ; FY:=FMoveFromY;
    Exit;
  end;
  Part:=(ANowTick-FMoveStartTick)/(FMoveEndTick-FMoveStartTick);
  FX:=FMoveFromX+(FMoveToX-FMoveFromX)*Part;
  FZ:=FMoveFromZ+(FMoveToZ-FMoveFromZ)*Part;
  FY:=FMoveFromY+(FMoveToY-FMoveFromY)*Part;
end;

procedure TB1008SpiderAI.BeginMovement(ANowTick: UInt64;
  const AMovement: TB1008MobMovement; ADurationMS: UInt64);
begin
  FMoveFromX:=AMovement.FromX; FMoveFromZ:=AMovement.FromZ;
  FMoveFromY:=AMovement.FromY;
  FMoveToX:=AMovement.ToX; FMoveToZ:=AMovement.ToZ;
  FMoveToY:=AMovement.ToY;
  FHeading:=AMovement.Heading;
  FMoveStartTick:=ANowTick; FMoveEndTick:=ANowTick+ADurationMS;
  FMoving:=True; FNextTick:=FMoveEndTick;
end;

procedure TB1008SpiderAI.Configure(const AMob: TEmulatorMobDefinition;
  const ASpawn: TEmulatorSpawnDefinition);
var
  DeltaX, DeltaZ, DeltaY: Single;
begin
  FPatrolRadius:=AMob.PatrolRadius;
  FMovementSpeed:=AMob.MovementSpeed;
  FChaseSpeed:=AMob.ChaseSpeed;
  if FChaseSpeed<=0 then FChaseSpeed:=FMovementSpeed;
  FEnabled:=(FPatrolRadius>0) and (FMovementSpeed>0) and (FChaseSpeed>0);
  if not FInitialized then
  begin
    FSpeedMultiplier:=1;
    FActiveChaseSpeed:=FChaseSpeed;
    FHomeX:=ASpawn.X; FHomeZ:=ASpawn.Z; FHomeY:=ASpawn.Y;
    FHomeHeading:=ASpawn.Heading;
    FX:=FHomeX; FZ:=FHomeZ; FY:=FHomeY; FHeading:=FHomeHeading;
    FInitialized:=True;
  end
  else
  begin
    DeltaX:=ASpawn.X-FHomeX; DeltaZ:=ASpawn.Z-FHomeZ;
    DeltaY:=ASpawn.Y-FHomeY;
    FHomeX:=ASpawn.X; FHomeZ:=ASpawn.Z; FHomeY:=ASpawn.Y;
    FHomeHeading:=ASpawn.Heading;
    FX:=FX+DeltaX; FZ:=FZ+DeltaZ; FY:=FY+DeltaY;
    FMoveFromX:=FMoveFromX+DeltaX; FMoveFromZ:=FMoveFromZ+DeltaZ;
    FMoveFromY:=FMoveFromY+DeltaY;
    FMoveToX:=FMoveToX+DeltaX; FMoveToZ:=FMoveToZ+DeltaZ;
    FMoveToY:=FMoveToY+DeltaY;
  end;
end;

procedure TB1008SpiderAI.Reset(ANowTick: UInt64);
begin
  Reset(ANowTick,0);
end;

procedure TB1008SpiderAI.Reset(ANowTick: UInt64; APatrolVariant: Integer);
var
  Variant: Integer;
  Seed: UInt64;
begin
  FApproachX:=0; FApproachZ:=0;
  FSpeedMultiplier:=1;
  FActiveChaseSpeed:=FChaseSpeed;
  FX:=FHomeX; FZ:=FHomeZ; FY:=FHomeY; FHeading:=FHomeHeading;
  FMoving:=False;
  FEngaged:=False;
  FReturning:=False;
  FChaseStopSent:=False;
  FAttackPending:=False;
  FAttackDamageTick:=0;
  FNextAttackTick:=0;
  FStunUntilTick:=0;
  Seed:=UInt64(Abs(Int64(APatrolVariant)));
  Variant:=Seed mod 4;
  FPatrolRandomState:=Cardinal(Seed) xor $9E3779B9;
  FPatrolIndex:=Variant;
  if Odd(Variant) then FPatrolStep:=-1 else FPatrolStep:=1;
  FStopped:=False;
  FNextTick:=ANowTick+B1008InitialPatrolDelayMS+
    (Seed*B1008PatrolVariantDelayMS) mod 1250;
end;

function TB1008SpiderAI.NextPatrolIdleMS: Cardinal;
begin
  // Private xorshift32 state: independent of polling order, other actors,
  // wall clock and global Random. Reset's FULL variant seeds all 101 actors;
  // reducing it to a direction/initial-delay slot would synchronize groups.
  FPatrolRandomState:=FPatrolRandomState xor (FPatrolRandomState shl 13);
  FPatrolRandomState:=FPatrolRandomState xor (FPatrolRandomState shr 17);
  FPatrolRandomState:=FPatrolRandomState xor (FPatrolRandomState shl 5);
  Result:=B1008PatrolIdleMinMS+
    FPatrolRandomState mod (B1008PatrolIdleMaxMS-B1008PatrolIdleMinMS+1);
end;

procedure TB1008SpiderAI.SetApproachOffset(AX,AZ: Single);
begin
  FApproachX:=AX; FApproachZ:=AZ;
end;

procedure TB1008SpiderAI.PauseForAdmission(ANowTick:UInt64);
begin
  UpdatePosition(ANowTick);
  if FEngaged then Exit;
  FMoving:=False;FNextTick:=ANowTick+250;
end;

procedure TB1008SpiderAI.Stop;
begin
  FStunUntilTick:=0;
  FMoving:=False;
  FEngaged:=False;
  FReturning:=False;
  FChaseStopSent:=False;
  FAttackPending:=False;
  FStopped:=True;
end;

function TB1008SpiderAI.SetSpeedMultiplier(ANowTick:UInt64;Multiplier:Single;out Movement:TB1008MobMovement):Boolean;
var Old:Single;Duration:UInt64;
begin
  if IsNan(Multiplier) or IsInfinite(Multiplier) or (Multiplier<=0) or (Multiplier>1) then
    raise EArgumentOutOfRangeException.Create('Invalid mob speed multiplier');
  Result:=False;Movement:=Default(TB1008MobMovement);
  if SameValue(FSpeedMultiplier,Multiplier,0.00001) then Exit;
  UpdatePosition(ANowTick);Old:=FSpeedMultiplier;if Old<=0 then Old:=1;
  FSpeedMultiplier:=Multiplier;FActiveChaseSpeed:=FActiveChaseSpeed*Multiplier/Old;
  if not FMoving then Exit;
  Movement.FromX:=FX;Movement.FromZ:=FZ;Movement.FromY:=FY;
  Movement.ToX:=FMoveToX;Movement.ToZ:=FMoveToZ;Movement.ToY:=FMoveToY;
  Movement.Heading:=FHeading;Movement.ReturningHome:=FReturning;
  if FEngaged and not FReturning then Movement.Mode:=0 else Movement.Mode:=1;
  Duration:=Max(UInt64(1),UInt64(Ceil((FMoveEndTick-ANowTick)*Old/Multiplier)));
  BeginMovement(ANowTick,Movement,Duration);Result:=True;
end;

function TB1008SpiderAI.Stun(ANowTick:UInt64;DurationMS:Cardinal;out Movement:TB1008MobMovement):Boolean;
begin
  Movement:=Default(TB1008MobMovement);Result:=False;
  if not FInitialized or FStopped or (DurationMS=0) then Exit;
  UpdatePosition(ANowTick);
  if FStunUntilTick<ANowTick+DurationMS then FStunUntilTick:=ANowTick+DurationMS;
  FMoving:=False;FAttackPending:=False;FAttackDamageTick:=0;
  FNextTick:=FStunUntilTick;FNextAttackTick:=FStunUntilTick;FChaseStopSent:=True;
  // Cancel the published movement/attack, retaining aggro and current position.
  Movement.Mode:=2;Movement.FromX:=FX;Movement.FromZ:=FZ;Movement.FromY:=FY;
  Movement.ToX:=FX;Movement.ToZ:=FZ;Movement.ToY:=FY;Movement.Heading:=StopHeading(FHeading);
  Result:=True;
end;

function TB1008SpiderAI.Engage(ANowTick: UInt64;
  out AStopMovement: TB1008MobMovement): Boolean;
begin
  AStopMovement:=Default(TB1008MobMovement);
  Result:=False;
  // A fresh admitted player attack interrupts ReturnHome just like patrol.
  // Merely re-entering the leash without attacking still does not re-aggro.
  if FEngaged and not FReturning then Exit;
  UpdatePosition(ANowTick);
  // Engagement must cancel the client's last patrol destination immediately.
  // Merely clearing FMoving leaves the already-sent mode-1 interpolation alive
  // client-side until the next world poll, which lets the mob push the player.
  AStopMovement.Mode:=2;
  AStopMovement.FromX:=FX; AStopMovement.FromZ:=FZ;
  AStopMovement.FromY:=FY;
  AStopMovement.ToX:=FX; AStopMovement.ToZ:=FZ;
  AStopMovement.ToY:=FY;
  AStopMovement.Heading:=StopHeading(FHeading);
  FMoving:=False;
  FStopped:=False;
  FEngaged:=True;
  FReturning:=False;
  FChaseStopSent:=True;
  FAttackPending:=False;
  FNextAttackTick:=ANowTick;
  // Keep the stop packet isolated from the next movement/attack command. The
  // client otherwise consumes stop and a new chase in the same visual frame.
  FNextTick:=ANowTick+B1008EngagementStopMS;
  Result:=True;
end;

function TB1008SpiderAI.Poll(ANowTick: UInt64;
  out AMovement: TB1008MobMovement): Boolean;
begin
  Result:=Poll(ANowTick,0,0,0,AMovement);
end;

function TB1008SpiderAI.Poll(ANowTick: UInt64;
  APlayerX,APlayerZ,AClearance: Single;
  out AMovement: TB1008MobMovement; AYieldNearby:Boolean): Boolean;
const
  DirectionX: array[0..3] of Single = (1,0,-1,0);
  DirectionZ: array[0..3] of Single = (0,1,0,-1);
var
  Distance: Single;
  DurationMS: UInt64;
  Attempt: Integer;
  function Blocked(ToX,ToZ: Single): Boolean;
  var DX,DZ,PX,PZ,Len2,Along,Nearest,Start2: Double;
  begin
    Result:=False;
    if AClearance<=0 then Exit;
    DX:=ToX-FX; DZ:=ToZ-FZ; PX:=FX-APlayerX; PZ:=FZ-APlayerZ;
    Len2:=DX*DX+DZ*DZ; Start2:=PX*PX+PZ*PZ;
    if Len2<0.0001 then Exit;
    Along:=PX*DX+PZ*DZ;
    // If the player stepped onto an actor, allow it to move outwards, never
    // further through the player. This is avoidance, not an aggro trigger.
    if (Start2<AClearance*AClearance) and (Along>=0) then Exit;
    Nearest:=EnsureRange(-Along/Len2,0.0,1.0);
    Result:=Sqr(PX+Nearest*DX)+Sqr(PZ+Nearest*DZ)<Sqr(AClearance);
  end;
begin
  AMovement:=Default(TB1008MobMovement);
  Result:=False;
  if not FInitialized or not FEnabled or FStopped or FEngaged or (ANowTick<FStunUntilTick) then Exit;
  UpdatePosition(ANowTick);
  Distance:=Sqrt(Sqr(FX-APlayerX)+Sqr(FZ-APlayerZ));
  if AYieldNearby and (AClearance>0) and (Distance<=AClearance) and (Distance>=1) then begin
    // Yield locally instead of continually selecting a new outward patrol
    // leg while an armed player closes for melee. This is NOT aggro: only 05/00
    // engages combat. A truly overlapping actor can still walk out below.
    if FNextTick<ANowTick+250 then FNextTick:=ANowTick+250;
    if not FMoving then Exit;
    FNextTick:=ANowTick+250; // Discard the cancelled leg's former arrival time.
    AMovement.Mode:=2;
    AMovement.FromX:=FX; AMovement.FromZ:=FZ; AMovement.FromY:=FY;
    AMovement.ToX:=FX; AMovement.ToZ:=FZ; AMovement.ToY:=FY;
    AMovement.Heading:=StopHeading(FHeading);
    FMoving:=False;
    Exit(True);
  end;
  if FMoving and Blocked(FMoveToX,FMoveToZ) then begin
    // Cancel an already published leg if the player entered its corridor.
    // Use the interpolated point, not its old start/end (no teleport).
    AMovement.Mode:=2;
    AMovement.FromX:=FX; AMovement.FromZ:=FZ; AMovement.FromY:=FY;
    AMovement.ToX:=FX; AMovement.ToZ:=FZ; AMovement.ToY:=FY;
    AMovement.Heading:=StopHeading(FHeading);
    FMoving:=False; FNextTick:=ANowTick+250;
    Exit(True);
  end;
  if
    (ANowTick<FNextTick) then Exit;
  AMovement.FromX:=FX; AMovement.FromZ:=FZ; AMovement.FromY:=FY;
  if FMoving then
  begin
    AMovement.Mode:=2;
    AMovement.ToX:=FX; AMovement.ToZ:=FZ; AMovement.ToY:=FY;
    AMovement.Heading:=StopHeading(FHeading);
    FMoving:=False;
    FNextTick:=ANowTick+NextPatrolIdleMS;
    Exit(True);
  end;
  AMovement.Mode:=1;
  for Attempt:=0 to 3 do begin
    AMovement.ToX:=FHomeX+DirectionX[FPatrolIndex]*FPatrolRadius;
    AMovement.ToZ:=FHomeZ+DirectionZ[FPatrolIndex]*FPatrolRadius;
    FPatrolIndex:=(FPatrolIndex+FPatrolStep+Length(DirectionX)) mod Length(DirectionX);
    if not Blocked(AMovement.ToX,AMovement.ToZ) then Break;
    if Attempt=3 then begin FNextTick:=ANowTick+500; Exit(False); end;
  end;
  AMovement.ToY:=FHomeY;
  AMovement.Heading:=MovementHeading(FX,FZ,AMovement.ToX,AMovement.ToZ);
  Distance:=Sqrt(Sqr(AMovement.ToX-FX)+Sqr(AMovement.ToZ-FZ)+
    Sqr(AMovement.ToY-FY));
  DurationMS:=Ceil(Distance/(FMovementSpeed*FSpeedMultiplier)*1000);
  if DurationMS=0 then DurationMS:=1;
  BeginMovement(ANowTick,AMovement,DurationMS);
  Result:=True;
end;

function TB1008SpiderAI.PollChase(ANowTick: UInt64;
  APlayerX,APlayerZ,APlayerY,AAttackRange,ALeashRadius: Single;
  out AMovement: TB1008MobMovement): Boolean;
var
  DeltaX, DeltaZ, Distance, StopDistance, StepDistance, StepRatio: Single;
  ArrivalRange,PlayerDistance: Single;
  DurationMS: UInt64;
  OutsideLeash: Boolean;
begin
  AMovement:=Default(TB1008MobMovement);
  Result:=False;
  if not FInitialized or not FEnabled or FStopped or not FEngaged or (ANowTick<FStunUntilTick) then Exit;
  UpdatePosition(ANowTick);
  OutsideLeash:=Sqrt(Sqr(APlayerX-FHomeX)+Sqr(APlayerZ-FHomeZ))>
    ALeashRadius;
  if OutsideLeash and not FReturning then
  begin
    // Interrupt the current chase at its interpolated point. Once leashed, the
    // mob finishes returning home even if the player re-enters the boundary.
    FReturning:=True;
    FMoving:=False;
    FNextTick:=ANowTick+B1008EngagementStopMS;
    FAttackPending:=False;
    FNextAttackTick:=ANowTick;
    // Cancel combat before issuing the walk home. The mode-2 handler places
    // the actor at From, so this point must use the same speed as the client.
    AMovement.Mode:=2;
    AMovement.ReturningHome:=True;
    AMovement.FromX:=FX; AMovement.FromZ:=FZ; AMovement.FromY:=FY;
    AMovement.ToX:=FX; AMovement.ToZ:=FZ; AMovement.ToY:=FY;
    AMovement.Heading:=StopHeading(FHeading);
    Exit(True);
  end;
  if FReturning then
  begin
    if ANowTick<FNextTick then Exit;
    if FMoving then FMoving:=False;
    AMovement.FromX:=FX; AMovement.FromZ:=FZ; AMovement.FromY:=FY;
    AMovement.ReturningHome:=True;
    DeltaX:=FHomeX-FX; DeltaZ:=FHomeZ-FZ;
    Distance:=Sqrt(Sqr(DeltaX)+Sqr(DeltaZ));
    if Distance<=0.01 then
    begin
      FX:=FHomeX; FZ:=FHomeZ; FY:=FHomeY;
      AMovement.Mode:=2;
      AMovement.FromX:=FX; AMovement.FromZ:=FZ; AMovement.FromY:=FY;
      AMovement.ToX:=FX; AMovement.ToZ:=FZ; AMovement.ToY:=FY;
      AMovement.Heading:=StopHeading(FHeading);
      FReturning:=False;
      FEngaged:=False;
      FChaseStopSent:=False;
      FNextTick:=ANowTick+B1008ReturnToPatrolMS;
      Exit(True);
    end;
    AMovement.Mode:=1;
    // Home is stationary: send one continuous walk, not eight-unit segments
    // with a transport-sized gap at every intermediate destination.
    AMovement.ToX:=FHomeX;
    AMovement.ToZ:=FHomeZ;
    AMovement.ToY:=FHomeY;
    AMovement.Heading:=MovementHeading(FX,FZ,AMovement.ToX,AMovement.ToZ);
    Distance:=Sqrt(Sqr(AMovement.ToX-FX)+Sqr(AMovement.ToZ-FZ)+
      Sqr(AMovement.ToY-FY));
    DurationMS:=Ceil(Distance/(FMovementSpeed*FSpeedMultiplier)*1000);
    if DurationMS=0 then DurationMS:=1;
    BeginMovement(ANowTick,AMovement,DurationMS);
    Exit(True);
  end;
  if ANowTick<FNextTick then Exit;
  // A completed chase leg is immediately followed by the next mode-0 leg.
  // Only the final attack-range endpoint receives one mode-2 stop packet.
  if FMoving then FMoving:=False;
  AMovement.FromX:=FX; AMovement.FromZ:=FZ; AMovement.FromY:=FY;
  PlayerDistance:=Sqrt(Sqr(APlayerX-FX)+Sqr(APlayerZ-FZ));
  DeltaX:=APlayerX+FApproachX-FX; DeltaZ:=APlayerZ+FApproachZ-FZ;
  Distance:=Sqrt(Sqr(DeltaX)+Sqr(DeltaZ));
  ArrivalRange:=AAttackRange; StopDistance:=AAttackRange*0.8;
  if (Abs(FApproachX)>0.001) or (Abs(FApproachZ)>0.001) then begin
    ArrivalRange:=0.25; StopDistance:=0;
  end;
  if Distance<=ArrivalRange then
  begin
    if FChaseStopSent then Exit;
    AMovement.Mode:=2;
    AMovement.ToX:=FX; AMovement.ToZ:=FZ; AMovement.ToY:=FY;
    AMovement.Heading:=StopHeading(FHeading);
    FChaseStopSent:=True;
    Exit(True);
  end;
  FChaseStopSent:=False;
  FAttackPending:=False;
  FNextAttackTick:=ANowTick;
  FActiveChaseSpeed:=FChaseSpeed*FSpeedMultiplier;
  if PlayerDistance<=B1008NearChaseDistance then
    FActiveChaseSpeed:=Min(FChaseSpeed,B1008NearChaseSpeed)*FSpeedMultiplier;
  StepDistance:=Min(Distance-StopDistance,FActiveChaseSpeed*B1008ChaseLegMS/1000);
  if StepDistance<=0 then Exit;
  StepRatio:=StepDistance/Distance;
  // Original NPC dispatch 0x4E1451: 0=run (+$392), 1=walk (+$38E), 2=stop.
  // Using walk here made the client move at patrol speed while the server
  // advanced at chase speed, then snapped the actor on the final stop.
  AMovement.Mode:=0;
  AMovement.ToX:=FX+DeltaX*StepRatio;
  AMovement.ToZ:=FZ+DeltaZ*StepRatio;
  AMovement.ToY:=FY+(APlayerY-FY)*StepRatio;
  AMovement.Heading:=MovementHeading(FX,FZ,AMovement.ToX,AMovement.ToZ);
  Distance:=Sqrt(Sqr(AMovement.ToX-FX)+Sqr(AMovement.ToZ-FZ)+
    Sqr(AMovement.ToY-FY));
  DurationMS:=Ceil(Distance/FActiveChaseSpeed*1000);
  if DurationMS=0 then DurationMS:=1;
  BeginMovement(ANowTick,AMovement,DurationMS);
  Result:=True;
end;

function TB1008SpiderAI.PollAttack(ANowTick: UInt64;
  APlayerX,APlayerZ,AAttackRange,AAttackSpeed: Single;
  out APhase: TB1008MobAttackPhase): Boolean;
var
  CycleMS: UInt64;
begin
  APhase:=mapStart;
  Result:=False;
  if not FInitialized or FStopped or not FEngaged or FReturning or
    (AAttackSpeed<=0) or (ANowTick<FStunUntilTick) then Exit;
  UpdatePosition(ANowTick);
  if ANowTick<FNextTick then Exit;
  if FMoving or
    (Sqrt(Sqr(APlayerX-FX)+Sqr(APlayerZ-FZ))>AAttackRange) then
  begin
    FAttackPending:=False;
    FNextAttackTick:=ANowTick;
    Exit;
  end;
  CycleMS:=Round(B1008BaseAttackMS/AAttackSpeed);
  if CycleMS<B1008MinimumAttackMS then CycleMS:=B1008MinimumAttackMS;
  if FAttackPending then
  begin
    if ANowTick<FAttackDamageTick then Exit;
    FAttackPending:=False;
    FNextAttackTick:=ANowTick;
    APhase:=mapDamage;
    Exit(True);
  end;
  if ANowTick<FNextAttackTick then Exit;
  FAttackPending:=True;
  FAttackDamageTick:=ANowTick+CycleMS;
  APhase:=mapStart;
  Result:=True;
end;

end.
