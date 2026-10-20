unit Emulator.Combat.B1008;
{$B-}

interface

uses System.SysUtils;

const B1008DiagnosticHitDelayMS = 1000;
  // User-authored coordinate convention, not a recovered physical world scale.
  B1008WorldUnitsPerMeter = 40;
  B1008DiagnosticPlayerDamage = 50;
  B1008DiagnosticSpiderDamage = 10;
  B1008DiagnosticCorpseVisibleMS = 1500;
  // User tuning: +15% player melee admission; not NPC reach or client AI.
  B1008PlayerMeleeRangeScale = 1.15;
  // Authored weapon reach, not monster radius. b1008 0x4FB23D adds
  // NPCInfo+0x30 to charData+0x502 for ordinary attack admission.
  B1008PlayerMeleeReach: Single = 12.0;

type
  TB1008HitOutcome = (hoNormal,hoCritical,hoMiss,hoFail);
  TB1008ResolvedHit = record
    NormalDamage,Damage:Integer;
    Critical:Boolean;
    Outcome:TB1008HitOutcome;
  end;
  TB1008CombatDamage = class
  public
    class function Roll(var State:Cardinal;Minimum,Maximum:Integer):Integer;static;
    class function Resolve(var State:Cardinal;Minimum,Maximum,
      CriticalBasisPoints,CriticalDamagePercent:Integer):TB1008ResolvedHit;static;
    class function ResolveOrdinary(var State:Cardinal;Minimum,Maximum,
      CriticalBasisPoints,CriticalDamagePercent,MissFailBasisPoints:Integer):TB1008ResolvedHit;static;
    class function OutcomeForRoll(Roll,MissFailBasisPoints:Integer):TB1008HitOutcome;static;
    class function AgainstDefense(NominalDamage,Defense,Curve,ReferenceDefense:Integer):Integer;static;
  end;
  TB1008AttackStart = record
    Timestamp, ActorID, ActionID, TargetID: Cardinal;
    ActorKind, ActionKind, TargetKind: Byte;
    X, Z, Y, Heading, TargetX, TargetZ, TargetY, TargetParameter: Single;
  end;
  TB1008AttackDecide = record
    Timestamp, ActorID, ActionID, TargetID: Cardinal;
    ActorKind, ActionKind, TargetKind, TargetCount: Byte;
    X, Z, Y, Heading: Single;
  end;
  TB1008ActionFlags = record
    Timestamp, CharacterID: Cardinal;
    FlagA, FlagB: Byte; // Meaning intentionally not guessed from click timing.
  end;
  TB1008CombatWire = class
  public
    class function ParseStart(const P: TBytes): TB1008AttackStart; static;
    class function ParseDecide(const P: TBytes): TB1008AttackDecide; static;
    class function ParseAreaDecide(const P:TBytes):TArray<TB1008AttackDecide>;static;
    class function ParseFlags(const P: TBytes): TB1008ActionFlags; static;
    class function BuildSpiderStartAccepted(const R: TB1008AttackStart;
      WorldX,WorldZ,WorldY: Single): TBytes; static;
    class function BuildSelfSkillAction(const R:TB1008AttackStart;
      WorldX,WorldZ,WorldY,Heading:Single):TBytes;static;
    class function BuildSpiderCounterStart(const R: TB1008AttackStart;
      PlayerX,PlayerZ,PlayerY: Single): TBytes; overload; static;
    class function BuildSpiderCounterStart(const R: TB1008AttackStart;
      PlayerX,PlayerZ,PlayerY,SpiderX,SpiderZ,SpiderY: Single): TBytes; overload; static;
    class function BuildSpiderCounterStart(Timestamp: Cardinal;
      PlayerX,PlayerZ,PlayerY,SpiderX,SpiderZ,SpiderY: Single): TBytes; overload; static;
    class function BuildSpiderCounterStart(Timestamp, SpiderHandle: Cardinal;
      PlayerX,PlayerZ,PlayerY,SpiderX,SpiderZ,SpiderY: Single): TBytes; overload; static;
    class function BuildSpiderDamageProbe(const R: TB1008AttackStart): TBytes; overload; static;
    class function BuildSpiderDamageProbe(const R: TB1008AttackStart;
      SpiderX,SpiderZ,SpiderY: Single): TBytes; overload; static;
    class function BuildSpiderDamageProbe(const R: TB1008AttackStart;
      SpiderX,SpiderZ,SpiderY: Single; HitDamage: Integer;
      Critical:Boolean = False): TBytes; overload; static;
    class function BuildSpiderDamageProbe(const R: TB1008AttackStart;
      SpiderX,SpiderZ,SpiderY: Single; HitDamage: Integer;
      Outcome:TB1008HitOutcome): TBytes; overload; static;
    class function BuildSpiderGageProbe(Timestamp: Cardinal; HP: Integer): TBytes; overload; static;
    class function BuildSpiderGageProbe(Timestamp: Cardinal; HP, MaxHP: Integer;
      MovementSpeed, AttackSpeed: Single): TBytes; overload; static;
    class function BuildSpiderGageProbe(Timestamp, SpiderHandle: Cardinal;
      HP, MaxHP: Integer; MovementSpeed, AttackSpeed: Single): TBytes; overload; static;
    class function BuildSpiderGageProbe(Timestamp, SpiderHandle: Cardinal;
      HP, MaxHP: Integer; MovementSpeed, ChaseSpeed,
      AttackSpeed: Single): TBytes; overload; static;
    class function BuildPlayerDamageProbe(Timestamp: Cardinal;
      X,Z,Y: Single): TBytes; overload; static;
    class function BuildPlayerDamageProbe(Timestamp: Cardinal;
      X,Z,Y: Single; Damage: Integer): TBytes; overload; static;
    class function BuildPlayerDamageProbe(Timestamp, SpiderHandle: Cardinal;
      X,Z,Y: Single; Damage: Integer; Failed:Boolean=False): TBytes; overload; static;
    class function BuildPlayerGageProbe(Timestamp: Cardinal;
      HP,MP: Integer; Level: Word = 1; MaxHP: Integer = 5000; MaxMP: Integer = 150): TBytes; static;
  end;
  // One session-owned diagnostic encounter. No AI/persistence/respawn timer.
  TB1008SpiderEncounter = class
  private
    FHP: Integer;
    FHitDamage: Integer;
    FMaxHP: Integer;
    FHasHit: Boolean;
    FLastTick: UInt64;
    FLastTimestamp: Cardinal;
    FDeathTick: UInt64;
    FDespawnTick: UInt64;
    FDespawned: Boolean;
  public
    constructor Create; overload;
    constructor Create(AHP: Integer); overload;
    constructor Create(AHP, AHitDamage: Integer); overload;
    function TryHit(const R: TB1008AttackStart; WorldX,WorldZ,WorldY: Single;
      ServerTick: UInt64; out Reason: string; Commit: Boolean = True): Boolean; overload;
    function TryHit(const R: TB1008AttackStart; WorldX,WorldZ,WorldY,
      SpiderX,SpiderZ,SpiderY,LeashRadius: Single; ServerTick: UInt64;
      out Reason: string; Commit: Boolean = True): Boolean; overload;
    function TryHit(const R: TB1008AttackStart; ExpectedHandle: Cardinal;
      WorldX,WorldZ,WorldY,SpiderX,SpiderZ,SpiderY,LeashRadius: Single;
      ServerTick: UInt64; out Reason: string;
      Commit: Boolean = True; Damage:Integer = -1): Boolean; overload;
    procedure ReconfigureMaxHP(ANewMaxHP: Integer);
    function ApplyPeriodicDamage(Damage:Integer;ServerTick:UInt64):Boolean;
    function TryDespawn(ServerTick: UInt64): Boolean;
    function TryRespawn(ServerTick: UInt64; RespawnMS: Integer): Boolean;
    property HP: Integer read FHP;
    property MaxHP: Integer read FMaxHP;
  end;

implementation

uses System.Math, Emulator.Protocol.B1008, Emulator.World.B1008, Emulator.Berneo.B1008,
  Emulator.Skills.B1008;

function SupportedPlayerAction(const R:TB1008AttackStart):Boolean;
begin
  // Cast authorization/MP/cooldown live in Session, not in these wire helpers.
  Result:=(R.ActionKind=0) or ((R.ActionKind=1) and (TB1008AttackSkillStats.FromAction(R.ActionID)<>0));
end;

class function TB1008CombatDamage.Roll(var State:Cardinal;Minimum,Maximum:Integer):Integer;
var Span,Limit,Sample:Cardinal;
begin
  if (Minimum<=0) or (Maximum<Minimum) or (Maximum>1000000) then
    raise EKarosProtocol.Create('Invalid ordinary damage range');
  if Minimum=Maximum then Exit(Minimum);
  if State=0 then State:=$9E3779B9;
  Span:=Cardinal(Maximum-Minimum+1);
  // Session-local xorshift32; no shared RNG or player-supplied seed.
  // Its nonzero cycle has 2^32-1 values. Rejection avoids modulo bias.
  Limit:=High(Cardinal)-(High(Cardinal) mod Span);
  repeat
    State:=State xor (State shl 13);State:=State xor (State shr 17);
    State:=State xor (State shl 5);Sample:=State-1;
  until Sample<Limit;
  Result:=Minimum+Integer(Sample mod Span);
end;

class function TB1008CombatDamage.Resolve(var State:Cardinal;Minimum,Maximum,
  CriticalBasisPoints,CriticalDamagePercent:Integer):TB1008ResolvedHit;
begin
  // Validate before consuming either roll. Percent is TOTAL damage, not a bonus.
  if (CriticalBasisPoints<0) or (CriticalBasisPoints>10000) or
    (CriticalDamagePercent<100) or (CriticalDamagePercent>1000) then
    raise EKarosProtocol.Create('Invalid critical damage profile');
  Result.NormalDamage:=Roll(State,Minimum,Maximum);
  Result.Critical:=False;
  if CriticalBasisPoints=10000 then Result.Critical:=True
  else if CriticalBasisPoints>0 then
    Result.Critical:=Roll(State,1,10000)<=CriticalBasisPoints;
  Result.Damage:=Result.NormalDamage;
  Result.Outcome:=hoNormal;
  if Result.Critical then
  begin
    Result.Outcome:=hoCritical;
    // Floor is an authored integer convention, not a recovered server formula.
    Result.Damage:=(Int64(Result.NormalDamage)*CriticalDamagePercent) div 100;
  end;
end;

class function TB1008CombatDamage.OutcomeForRoll(Roll,MissFailBasisPoints:Integer):TB1008HitOutcome;
begin
  if (Roll<1) or (Roll>10000) or (MissFailBasisPoints<0) or (MissFailBasisPoints>10000) then
    raise EKarosProtocol.Create('Invalid miss/fail roll');
  // One mutually exclusive roll; odd basis point belongs to FAIL.
  if Roll<=MissFailBasisPoints div 2 then Exit(hoMiss);
  if Roll<=MissFailBasisPoints then Exit(hoFail);
  Result:=hoNormal;
end;

class function TB1008CombatDamage.ResolveOrdinary(var State:Cardinal;Minimum,Maximum,
  CriticalBasisPoints,CriticalDamagePercent,MissFailBasisPoints:Integer):TB1008ResolvedHit;
begin
  // Reject every invalid input before consuming RNG, including on a miss.
  if (Minimum<=0) or (Maximum<Minimum) or (Maximum>1000000) or
    (CriticalBasisPoints<0) or (CriticalBasisPoints>10000) or
    (CriticalDamagePercent<100) or (CriticalDamagePercent>1000) or
    (MissFailBasisPoints<0) or (MissFailBasisPoints>10000) then
    raise EKarosProtocol.Create('Invalid ordinary hit profile');
  Result:=Default(TB1008ResolvedHit);
  if MissFailBasisPoints>0 then
    Result.Outcome:=OutcomeForRoll(Roll(State,1,10000),MissFailBasisPoints);
  if Result.Outcome in [hoMiss,hoFail] then Exit;
  Result:=Resolve(State,Minimum,Maximum,CriticalBasisPoints,CriticalDamagePercent);
end;

class function TB1008CombatDamage.AgainstDefense(NominalDamage,Defense,Curve,ReferenceDefense:Integer):Integer;
var Numerator,Denominator,Damage:Int64;
begin
  if (NominalDamage<0) or (NominalDamage>1000000) or (Defense<0) or (Defense>1000000) or
    (Curve<1) or (Curve>1000000) or (ReferenceDefense<0) or (ReferenceDefense>1000000) then
    raise EKarosProtocol.Create('Invalid physical defense profile');
  if NominalDamage=0 then Exit(0);
  // Authored diminishing-return calibration, not historical server code.
  // attack_damage retains its previously verified meaning at reference armor.
  // At reference=0 this is the usual raw * K/(K+defense) curve.
  Numerator:=Int64(NominalDamage)*(Int64(Curve)+ReferenceDefense);
  Denominator:=Int64(Curve)+Defense;
  Damage:=(Numerator+Denominator div 2) div Denominator;
  if Damage>High(Integer) then raise EKarosProtocol.Create('Physical damage exceeds client range');
  if Damage<1 then Damage:=1;
  Result:=Integer(Damage);
end;

procedure BE(var P: TBytes; Offset: Integer; Value: Cardinal);
begin
  P[Offset]:=Byte(Value shr 24); P[Offset+1]:=Byte((Value shr 16) and 255);
  P[Offset+2]:=Byte((Value shr 8) and 255); P[Offset+3]:=Byte(Value and 255);
end;

function SupportedSpiderHandle(AHandle: Cardinal): Boolean;
begin
  Result:=TB1008Berneo.TemplateForHandle(AHandle)<>0;
end;

class function TB1008CombatWire.BuildSpiderDamageProbe(const R: TB1008AttackStart): TBytes;
begin
  Result:=BuildSpiderDamageProbe(R,8669.7763671875,6668.01025390625,
    604.350341796875);
end;

class function TB1008CombatWire.BuildSpiderDamageProbe(const R: TB1008AttackStart;
  SpiderX,SpiderZ,SpiderY: Single): TBytes;
begin Result:=BuildSpiderDamageProbe(R,SpiderX,SpiderZ,SpiderY,B1008DiagnosticPlayerDamage); end;

class function TB1008CombatWire.BuildSpiderDamageProbe(const R: TB1008AttackStart;
  SpiderX,SpiderZ,SpiderY: Single; HitDamage: Integer; Critical:Boolean): TBytes;
begin
  if Critical then Result:=BuildSpiderDamageProbe(R,SpiderX,SpiderZ,SpiderY,HitDamage,hoCritical)
  else Result:=BuildSpiderDamageProbe(R,SpiderX,SpiderZ,SpiderY,HitDamage,hoNormal);
end;

class function TB1008CombatWire.BuildSpiderDamageProbe(const R: TB1008AttackStart;
  SpiderX,SpiderZ,SpiderY: Single; HitDamage: Integer; Outcome:TB1008HitOutcome): TBytes;
var Damage, Target: Integer;
begin
  case Outcome of
    hoNormal,hoCritical:if HitDamage<=0 then raise EKarosProtocol.Create('Invalid hit damage');
    hoMiss,hoFail:if HitDamage<>0 then raise EKarosProtocol.Create('MISS/FAIL must deal zero damage');
  else raise EKarosProtocol.Create('Invalid hit outcome');end;
  if (R.ActorKind<>0) or (R.ActorID<>1) or not SupportedPlayerAction(R) or
    (R.TargetKind<>1) or not SupportedSpiderHandle(R.TargetID) then
    raise EKarosProtocol.Create('Unsupported diagnostic hit');
  // 0x52A8FB: 17-byte header + one 30-byte packed target record.
  // Target ID and damage are LE (no ntohl); attacker ID is BE.
  Result:=nil; SetLength(Result,47); Result[0]:=5; Result[1]:=2;
  BE(Result,2,R.Timestamp); BE(Result,7,R.ActorID); BE(Result,12,R.ActionID);
  if R.ActionKind=1 then BE(Result,12,TB1008AttackSkillStats.FromAction(R.ActionID));
  Result[11]:=R.ActionKind;Result[16]:=1; Result[17]:=1; Target:=R.TargetID;
  Move(Target,Result[18],4); Damage:=HitDamage;
  // 0x52A9E5 copies packet[22] to damage-info+17; the queued NPC hit
  // reaches 0x430B47, where type 2 selects the distinct damage-number widget
  // (0x46554B), instead of ordinary 0x465597. Reaction packet[27] stays zero.
  // GUI3610 AniImageOut: 2=CRITICAL, 5=MISS, 6=FAIL. Both result paths
  // (0x4655E3/0x465610) use this byte independently of numeric damage.
  case Outcome of
    hoCritical:Result[22]:=2;
    hoMiss:Result[22]:=5;
    hoFail:Result[22]:=6;
  end;
  Move(Damage,Result[23],4);
  // Unmapped hit/reaction flags remain zero. Never echo client target coordinates.
  Move(SpiderX,Result[31],4); Move(SpiderZ,Result[35],4);
  Move(SpiderY,Result[39],4);
end;

class function TB1008CombatWire.BuildSelfSkillAction(const R:TB1008AttackStart;
  WorldX,WorldZ,WorldY,Heading:Single):TBytes;
begin
  if (R.ActorKind<>0) or (R.ActorID<>1) or
    ((TB1008AttackSkillStats.SelfFromAction(R.ActionID)=0) and (R.ActionID<>0)) or
    not (R.ActionKind in [1,5]) then raise EKarosProtocol.Create('Unsupported self skill action');
  Result:=nil;SetLength(Result,53);Result[0]:=5;
  BE(Result,2,R.Timestamp);BE(Result,7,1);Result[11]:=R.ActionKind;BE(Result,12,R.ActionID);
  Move(WorldX,Result[16],4);Move(WorldZ,Result[20],4);Move(WorldY,Result[24],4);
  Move(Heading,Result[28],4);BE(Result,33,1);
  Move(WorldX,Result[37],4);Move(WorldZ,Result[41],4);Move(WorldY,Result[45],4);
end;

class function TB1008CombatWire.BuildSpiderStartAccepted(const R: TB1008AttackStart;
  WorldX,WorldZ,WorldY: Single): TBytes;
var V: Single;
begin
  if (R.ActorKind<>0) or (R.ActorID<>1) or
    not (SupportedPlayerAction(R) or ((R.ActionKind=5) and (TB1008AttackSkillStats.FromAction(R.ActionID)<>0))) or
    (R.TargetKind<>1) or not SupportedSpiderHandle(R.TargetID) then
    raise EKarosProtocol.Create('Unsupported diagnostic attack start');
  // Original client receiver 0x52AC4E / parser 0x5292D6 consumes the same
  // 53-byte mixed-endian record. This is an accepted action, not damage.
  Result:=nil; SetLength(Result,53); Result[0]:=5;
  BE(Result,2,R.Timestamp); Result[6]:=R.ActorKind; BE(Result,7,R.ActorID);
  Result[11]:=R.ActionKind; BE(Result,12,R.ActionID);
  Move(WorldX,Result[16],4); Move(WorldZ,Result[20],4); Move(WorldY,Result[24],4);
  Move(R.Heading,Result[28],4); Result[32]:=R.TargetKind; BE(Result,33,R.TargetID);
  // Client terrain-adjusted target point was admitted by TryHit's bounds.
  Move(R.TargetX,Result[37],4); Move(R.TargetZ,Result[41],4);
  Move(R.TargetY,Result[45],4); V:=0; Move(V,Result[49],4);
end;

class function TB1008CombatWire.BuildSpiderCounterStart(const R: TB1008AttackStart;
  PlayerX,PlayerZ,PlayerY: Single): TBytes;
begin
  Result:=BuildSpiderCounterStart(R,PlayerX,PlayerZ,PlayerY,
    8669.7763671875,6668.01025390625,607.174);
end;

class function TB1008CombatWire.BuildSpiderCounterStart(const R: TB1008AttackStart;
  PlayerX,PlayerZ,PlayerY,SpiderX,SpiderZ,SpiderY: Single): TBytes;
var Heading,V: Single;
begin
  // The NPC branch of the original 05/00 receiver resolves kind/id and calls
  // the creature's ordinary-attack method, which selects its own animation.
  // ActionID is intentionally neutral: that branch does not consume it.
  Result:=nil; SetLength(Result,53); Result[0]:=5;
  BE(Result,2,R.Timestamp); Result[6]:=1; BE(Result,7,R.TargetID);
  Result[11]:=0; BE(Result,12,0);
  Move(SpiderX,Result[16],4); Move(SpiderZ,Result[20],4);
  Move(SpiderY,Result[24],4);
  Heading:=R.Heading+Pi;
  if Heading>=2*Pi then Heading:=Heading-2*Pi;
  Move(Heading,Result[28],4);
  Result[32]:=0; BE(Result,33,1);
  Move(PlayerX,Result[37],4); Move(PlayerZ,Result[41],4);
  Move(PlayerY,Result[45],4); V:=0; Move(V,Result[49],4);
end;

class function TB1008CombatWire.BuildSpiderCounterStart(Timestamp: Cardinal;
  PlayerX,PlayerZ,PlayerY,SpiderX,SpiderZ,SpiderY: Single): TBytes;
begin
  Result:=BuildSpiderCounterStart(Timestamp,B1008SpiderHandle,
    PlayerX,PlayerZ,PlayerY,SpiderX,SpiderZ,SpiderY);
end;

class function TB1008CombatWire.BuildSpiderCounterStart(Timestamp,
  SpiderHandle: Cardinal; PlayerX,PlayerZ,PlayerY,SpiderX,SpiderZ,
  SpiderY: Single): TBytes;
var Heading,V: Single;
begin
  if not SupportedSpiderHandle(SpiderHandle) then
    raise EKarosProtocol.Create('Unsupported attacking spider');
  Result:=nil; SetLength(Result,53); Result[0]:=5;
  BE(Result,2,Timestamp); Result[6]:=1; BE(Result,7,SpiderHandle);
  Result[11]:=0; BE(Result,12,0);
  Move(SpiderX,Result[16],4); Move(SpiderZ,Result[20],4);
  Move(SpiderY,Result[24],4);
  Heading:=Pi+ArcTan2(PlayerX-SpiderX,PlayerZ-SpiderZ);
  while Heading>=2*Pi do Heading:=Heading-2*Pi;
  while Heading<0 do Heading:=Heading+2*Pi;
  Move(Heading,Result[28],4);
  Result[32]:=0; BE(Result,33,1);
  Move(PlayerX,Result[37],4); Move(PlayerZ,Result[41],4);
  Move(PlayerY,Result[45],4); V:=0; Move(V,Result[49],4);
end;

class function TB1008CombatWire.BuildSpiderGageProbe(Timestamp: Cardinal; HP: Integer): TBytes;
begin
  Result := BuildSpiderGageProbe(Timestamp, HP, B1008SpiderProbeHP,
    B1008ProbeSpeedA, B1008ProbeAttackSpeed);
end;

class function TB1008CombatWire.BuildSpiderGageProbe(Timestamp: Cardinal;
  HP, MaxHP: Integer; MovementSpeed, AttackSpeed: Single): TBytes;
begin
  Result:=BuildSpiderGageProbe(Timestamp,B1008SpiderHandle,HP,MaxHP,
    MovementSpeed,AttackSpeed);
end;

class function TB1008CombatWire.BuildSpiderGageProbe(Timestamp,
  SpiderHandle: Cardinal; HP, MaxHP: Integer; MovementSpeed,
  AttackSpeed: Single): TBytes;
begin
  Result:=BuildSpiderGageProbe(Timestamp,SpiderHandle,HP,MaxHP,
    MovementSpeed,MovementSpeed*2,AttackSpeed);
end;

class function TB1008CombatWire.BuildSpiderGageProbe(Timestamp,
  SpiderHandle: Cardinal; HP, MaxHP: Integer; MovementSpeed, ChaseSpeed,
  AttackSpeed: Single): TBytes;
var Appear: TBytes;
begin
  if not SupportedSpiderHandle(SpiderHandle) then
    raise EKarosProtocol.Create('Unsupported spider gage target');
  if (MaxHP<=0) or (HP<0) or (HP>MaxHP) then
    raise EKarosProtocol.Create('Probe HP outside range');
  // 0x52BB53 copies 38 bytes from +11 into NPC+0x37E (HP through flags).
  Appear:=TB1008World.BuildSpiderAppearProbe(Timestamp,SpiderHandle,MaxHP,
    MovementSpeed,ChaseSpeed,AttackSpeed,0,0,0,0);
  Result:=nil; SetLength(Result,49); Result[0]:=8;
  BE(Result,2,Timestamp); Result[6]:=1; BE(Result,7,SpiderHandle);
  Move(Appear[28],Result[11],38); Move(HP,Result[11],4);
end;

class function TB1008CombatWire.BuildPlayerDamageProbe(Timestamp: Cardinal;
  X,Z,Y: Single): TBytes;
begin
  Result := BuildPlayerDamageProbe(Timestamp,X,Z,Y,
    B1008DiagnosticSpiderDamage);
end;

class function TB1008CombatWire.BuildPlayerDamageProbe(Timestamp: Cardinal;
  X,Z,Y: Single; Damage: Integer): TBytes;
begin
  Result:=BuildPlayerDamageProbe(Timestamp,B1008SpiderHandle,X,Z,Y,Damage);
end;

class function TB1008CombatWire.BuildPlayerDamageProbe(Timestamp,
  SpiderHandle: Cardinal; X,Z,Y: Single; Damage: Integer; Failed:Boolean): TBytes;
var Target: Integer;
begin
  if not SupportedSpiderHandle(SpiderHandle) then
    raise EKarosProtocol.Create('Unsupported spider damage source');
  if Damage<0 then raise EKarosProtocol.Create('Negative incoming damage');
  if Failed and (Damage<>0) then raise EKarosProtocol.Create('Incoming FAIL must deal zero damage');
  // Same 05/02 target-record layout as player damage, with the spider as the
  // authoritative attacker and the local character as target kind zero.
  Result:=nil; SetLength(Result,47); Result[0]:=5; Result[1]:=2;
  BE(Result,2,Timestamp); Result[6]:=1; BE(Result,7,SpiderHandle);
  Result[16]:=1; Result[17]:=0; Target:=1; Move(Target,Result[18],4);
  Move(Damage,Result[23],4);
  if Failed then Result[22]:=6;
  Move(X,Result[31],4); Move(Z,Result[35],4); Move(Y,Result[39],4);
end;

class function TB1008CombatWire.BuildPlayerGageProbe(Timestamp: Cardinal;
  HP,MP: Integer; Level: Word; MaxHP,MaxMP:Integer): TBytes;
begin
  if Level=0 then raise EKarosProtocol.Create('Invalid player level');
  if (MaxHP<1) or (MaxHP>1000000) or (MaxMP<0) or (MaxMP>1000000) or
    (HP<0) or (HP>MaxHP) or (MP<0) or (MP>MaxMP) then
    raise EKarosProtocol.Create('Player gage outside range');
  // CCharGagePacket 08/00 copies 38 packed bytes from +11 into the selected
  // actor. Kind zero and ID one address the local character.
  Result:=nil; SetLength(Result,49); Result[0]:=8;
  BE(Result,2,Timestamp); Result[6]:=0; BE(Result,7,1);
  Move(HP,Result[11],4); Move(MaxHP,Result[15],4);
  Move(MP,Result[19],4); Move(MaxMP,Result[23],4);
  Move(B1008PlayerSpeedA,Result[27],4); Move(B1008PlayerSpeedB,Result[31],4);
  Move(B1008ProbeAttackSpeed,Result[35],4);
  // This block also contains the character level. Leaving it zero makes the
  // client display Lv.0 and play a false level-up transition on the first hit.
  Move(Level,Result[39],2);
end;

constructor TB1008SpiderEncounter.Create;
begin Create(B1008SpiderProbeHP,B1008DiagnosticPlayerDamage); end;

constructor TB1008SpiderEncounter.Create(AHP: Integer);
begin Create(AHP,B1008DiagnosticPlayerDamage); end;

constructor TB1008SpiderEncounter.Create(AHP, AHitDamage: Integer);
begin
  inherited Create;
  if (AHP<=0) or (AHitDamage<=0) then
    raise EArgumentOutOfRangeException.Create('Invalid initial spider HP');
  FMaxHP:=AHP; FHP:=AHP; FHitDamage:=AHitDamage;
end;

procedure TB1008SpiderEncounter.ReconfigureMaxHP(ANewMaxHP: Integer);
var
  WasFull: Boolean;
begin
  if ANewMaxHP<=0 then
    raise EArgumentOutOfRangeException.Create('Invalid new spider maximum HP');
  if ANewMaxHP=FMaxHP then Exit;
  WasFull:=FHP=FMaxHP;
  FMaxHP:=ANewMaxHP;
  if WasFull then FHP:=FMaxHP
  else if FHP>FMaxHP then FHP:=FMaxHP;
end;

function TB1008SpiderEncounter.TryHit(const R: TB1008AttackStart;
  WorldX,WorldZ,WorldY: Single; ServerTick: UInt64; out Reason: string; Commit: Boolean): Boolean;
begin
  Result:=TryHit(R,WorldX,WorldZ,WorldY,8669.7763671875,6668.01025390625,
    604.350341796875,50,ServerTick,Reason,Commit);
end;

function TB1008SpiderEncounter.TryHit(const R: TB1008AttackStart;
  WorldX,WorldZ,WorldY,SpiderX,SpiderZ,SpiderY,LeashRadius: Single;
  ServerTick: UInt64; out Reason: string; Commit: Boolean): Boolean;
begin
  Result:=TryHit(R,B1008SpiderHandle,WorldX,WorldZ,WorldY,
    SpiderX,SpiderZ,SpiderY,LeashRadius,ServerTick,Reason,Commit);
end;

function TB1008SpiderEncounter.TryHit(const R: TB1008AttackStart;
  ExpectedHandle: Cardinal; WorldX,WorldZ,WorldY,SpiderX,SpiderZ,
  SpiderY,LeashRadius: Single; ServerTick: UInt64; out Reason: string;
  Commit: Boolean;Damage:Integer): Boolean;
var Delta: Int64; Distance: Double;
begin
  Result:=False;
  if Damage<-1 then begin Reason:='negative damage';Exit;end;
  if Damage=-1 then Damage:=FHitDamage; // Omitted damage in standalone probes only.
  // Explicit zero still commits timestamp/replay state, without HP/death changes.
  if IsNan(WorldX) or IsNan(WorldZ) or IsNan(WorldY) or
    IsInfinite(WorldX) or IsInfinite(WorldZ) or IsInfinite(WorldY) or
    IsNan(R.X) or IsNan(R.Z) or IsNan(R.Y) or
    IsInfinite(R.X) or IsInfinite(R.Z) or IsInfinite(R.Y) or
    IsNan(R.TargetX) or IsNan(R.TargetZ) or IsNan(R.TargetY) or
    IsInfinite(R.TargetX) or IsInfinite(R.TargetZ) or IsInfinite(R.TargetY) then
    begin Reason:='invalid position'; Exit; end;
  if (R.ActorKind<>0) or (R.ActorID<>1) or not SupportedPlayerAction(R) or
    (R.TargetKind<>1) or not SupportedSpiderHandle(ExpectedHandle) or
    (R.TargetID<>ExpectedHandle) then
    begin Reason:='unsupported actor/action/target'; Exit; end;
  if FHP=0 then begin Reason:='spider already dead'; Exit; end;
  if IsNan(SpiderX) or IsNan(SpiderZ) or IsNan(SpiderY) or IsNan(LeashRadius) or
    IsInfinite(SpiderX) or IsInfinite(SpiderZ) or IsInfinite(SpiderY) or
    IsInfinite(LeashRadius) or (LeashRadius<0) then
    begin Reason:='invalid live spawn'; Exit; end;
  Distance:=Sqrt(Sqr(R.X-WorldX)+Sqr(R.Z-WorldZ)+Sqr(R.Y-WorldY));
  if Distance>10 then
    begin Reason:=Format('outside diagnostic distance/position tolerance: actor drift %.2f > 10',
      [Distance],TFormatSettings.Invariant); Exit; end;
  // The client projects ground NPCs onto terrain; generated spawn Y is only
  // an estimate until a server heightmap exists. Do not reject ground melee
  // using that estimate. Keep horizontal range, target identity and actor
  // position validation; use the admitted attack point, not an older report.
  Distance:=Sqrt(Sqr(R.X-SpiderX)+Sqr(R.Z-SpiderZ));
  if Distance>LeashRadius then
    begin Reason:=Format('outside diagnostic distance: ground range %.2f > %.2f',
      [Distance,LeashRadius],TFormatSettings.Invariant); Exit; end;
  Distance:=Sqrt(Sqr(R.TargetX-SpiderX)+Sqr(R.TargetZ-SpiderZ));
  if Distance>20 then
    begin Reason:=Format('outside diagnostic distance: target drift %.2f > 20',
      [Distance],TFormatSettings.Invariant); Exit; end;
  if FHasHit then
  begin
    Delta:=(Int64(R.Timestamp)-Int64(FLastTimestamp)+$100000000) mod $100000000;
    if (Delta=0) or (Delta>=$80000000) then
      begin Reason:='duplicate/stale timestamp'; Exit; end;
    if ServerTick<FLastTick then begin Reason:='server clock rollback'; Exit; end;
  end;
  if Commit then begin
    Dec(FHP,Damage); if FHP<0 then FHP:=0;
    FHasHit:=True; FLastTick:=ServerTick; FLastTimestamp:=R.Timestamp;
    if FHP=0 then
    begin
      FDeathTick:=ServerTick;
      FDespawnTick:=0;
      FDespawned:=False;
    end;
  end;
  Reason:='diagnostic hit'; Result:=True;
end;

function TB1008SpiderEncounter.ApplyPeriodicDamage(Damage:Integer;ServerTick:UInt64):Boolean;
begin
  Result:=(Damage>0) and (FHP>0);
  if not Result then Exit;
  FHP:=Max(0,FHP-Damage);
  if FHP=0 then begin
    FDeathTick:=ServerTick;FDespawnTick:=0;FDespawned:=False;
  end;
  // Server timer damage neither admits client movement nor advances hit stamps.
end;

function TB1008SpiderEncounter.TryDespawn(ServerTick: UInt64): Boolean;
var
  RequiredDelay: UInt64;
begin
  Result:=False;
  if (FHP<>0) or FDespawned or (ServerTick<FDeathTick) then Exit;
  RequiredDelay:=UInt64(B1008DiagnosticHitDelayMS)+
    UInt64(B1008DiagnosticCorpseVisibleMS);
  if ServerTick-FDeathTick<RequiredDelay then Exit;
  FDespawned:=True;
  FDespawnTick:=ServerTick;
  Result:=True;
end;

function TB1008SpiderEncounter.TryRespawn(ServerTick: UInt64;
  RespawnMS: Integer): Boolean;
var
  RequiredDelay: UInt64;
begin
  if RespawnMS<0 then
    raise EArgumentOutOfRangeException.Create('Invalid spider respawn delay');
  Result:=False;
  if (FHP<>0) or not FDespawned then Exit;
  if ServerTick<FDespawnTick then Exit;
  RequiredDelay:=UInt64(RespawnMS);
  if ServerTick-FDespawnTick<RequiredDelay then Exit;
  FHP:=FMaxHP;
  FHasHit:=False;
  FLastTick:=0;
  FLastTimestamp:=0;
  FDeathTick:=0;
  FDespawnTick:=0;
  FDespawned:=False;
  Result:=True;
end;

function Finite(const P: TBytes; Offset: Integer): Single;
begin
  Move(P[Offset],Result,4);
  if IsNan(Result) or IsInfinite(Result) or (Abs(Result)>1000000) then
    raise EKarosProtocol.Create('Invalid attack float');
end;

class function TB1008CombatWire.ParseStart(const P: TBytes): TB1008AttackStart;
begin
  // Original serializer 0x4FDE59, ordinary-action caller 0x4FEDC1.
  // Mixed wire format: byte/BE32 fields and raw LE float vectors.
  if Length(P)<>53 then raise EKarosProtocol.Create('Invalid AttackStart size');
  if (P[0]<>5) or (P[1]<>0) then raise EKarosProtocol.Create('Not AttackStart');
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2);
  Result.ActorKind:=P[6]; Result.ActorID:=TB1008Wire.ReadBE32(P,7);
  Result.ActionKind:=P[11]; Result.ActionID:=TB1008Wire.ReadBE32(P,12);
  Result.X:=Finite(P,16); Result.Z:=Finite(P,20); Result.Y:=Finite(P,24);
  Result.Heading:=Finite(P,28);
  Result.TargetKind:=P[32]; Result.TargetID:=TB1008Wire.ReadBE32(P,33);
  Result.TargetX:=Finite(P,37); Result.TargetZ:=Finite(P,41);
  Result.TargetY:=Finite(P,45); Result.TargetParameter:=Finite(P,49);
end;

class function TB1008CombatWire.ParseDecide(
  const P: TBytes): TB1008AttackDecide;
begin
  // Captured b1008 ordinary-hit decision. Unlike 05/00 this packet carries
  // the actor's impact-time position and a compact target list.
  if Length(P)<>38 then raise EKarosProtocol.Create('Invalid AttackDecide size');
  if (P[0]<>5) or (P[1]<>1) then raise EKarosProtocol.Create('Not AttackDecide');
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2);
  Result.ActorKind:=P[6]; Result.ActorID:=TB1008Wire.ReadBE32(P,7);
  Result.ActionKind:=P[11]; Result.ActionID:=TB1008Wire.ReadBE32(P,12);
  Result.X:=Finite(P,16); Result.Z:=Finite(P,20); Result.Y:=Finite(P,24);
  Result.Heading:=Finite(P,28);
    // 4FDFD4 writes count=1 at +20; 4FDFE9 then writes target kind.
    // 4FFAA7 increments +20 for extra targets. NPC/count=1 masked the
    // distinction; self buffs expose count=1, kind=0 at offsets 32/33.
    Result.TargetCount:=P[32]; Result.TargetKind:=P[33];
  Result.TargetID:=TB1008Wire.ReadBE32(P,34);
end;

class function TB1008CombatWire.ParseAreaDecide(const P:TBytes):TArray<TB1008AttackDecide>;
var I,J,Count:Integer;First:TBytes;
begin
  // 4FDF3D writes count at +20 followed by kind/BE32 handle pairs.
  // 4FFAA7 appends each 5-byte target. Client 4EDF12 caps its list at 100.
  if Length(P)<38 then raise EKarosProtocol.Create('Truncated area impact');
  Count:=P[32];
  if (Count<1) or (Count>100) or (Length(P)<>33+Count*5) then
    raise EKarosProtocol.Create('Invalid area target count/length');
  First:=Copy(P,0,38);SetLength(Result,Count);Result[0]:=ParseDecide(First);
  for I:=0 to Count-1 do begin
    if I>0 then Result[I]:=Result[0];
    Result[I].TargetKind:=P[33+I*5];Result[I].TargetID:=TB1008Wire.ReadBE32(P,34+I*5);
    for J:=0 to I-1 do if (Result[I].TargetKind=Result[J].TargetKind) and
      (Result[I].TargetID=Result[J].TargetID) then raise EKarosProtocol.Create('Duplicate area target');
  end;
end;

class function TB1008CombatWire.ParseFlags(const P: TBytes): TB1008ActionFlags;
begin
  // 0x4FDBC5 -> BE32 character ID + two bytes. Not a target ID packet.
  if Length(P)<>12 then raise EKarosProtocol.Create('Invalid ActionFlags size');
  if (P[0]<>3) or (P[1]<>2) then raise EKarosProtocol.Create('Not ActionFlags');
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2);
  Result.CharacterID:=TB1008Wire.ReadBE32(P,6);
  Result.FlagA:=P[10]; Result.FlagB:=P[11];
end;

end.
