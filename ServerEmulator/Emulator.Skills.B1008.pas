unit Emulator.Skills.B1008;

interface

uses System.SysUtils, Emulator.Protocol.B1008;

const
  B1008PowerStrikeID = 1001;
  B1008CoerciveID = 1002;
  B1008CoerciveActionID = 1018;
  B1008CoerciveDurationMS = 20000;
  B1008BodyBlowID = 1003;
  B1008FrenzyID = 1004;
  B1008StrengthMasteryID = 1006;
  B1008FrenzyActionID = 1013;
  B1008ProvocationID = 1005;
  B1008ProvocationActionID = 1017;
  B1008ProvocationRanges:array[1..5] of Single=(35,51,68,84,100);
  B1008BodyBlowRequiredLevel = 2;
  B1008BodyBlowSP = 1;
  B1008BodyBlowActionID = 1007;
  B1008BodyBlowStunMS = 3000;
  B1008SlashID = 5001;
  B1008SupplementID = 9001;
  B1008PowerStrikeActionID = 1004; // skillBase +$149, NOT the skill ID.
  B1008PowerStrikeMP = 4;
  B1008PowerStrikeCooldownMS = 8000;
  B1008PowerStrikeRange = 20;
  B1008SkillHandshakeMS = 3000; // Server admission timeout, not original balance.

type
  TB1008SkillLearnResult=(slrRejected,slrAlreadyKnown,slrApplied);
  TB1008SkillUpgradeResult=(surRejected,surDuplicate,surApplied);
  TB1008PowerStrikeRank = record
    RequiredLevel,SPCost,MPCost,BonusMin,BonusMax:Integer;
    class function Get(Rank:Cardinal):TB1008PowerStrikeRank;static;
  end;
  TB1008SkillTraining = record
    RequiredLevel,SPCost:Integer;
    PrerequisiteID,PrerequisiteRank:Cardinal;
    PrerequisiteCount:Byte;
    PrerequisiteIDs,PrerequisiteRanks:array[0..2] of Cardinal;
    class function Get(ID,Rank:Cardinal):TB1008SkillTraining;static;
  end;
  TB1008FrenzyRank = record
    MPCost,AttackBonus,DefensePenalty:Integer;
    class function Get(Rank:Cardinal):TB1008FrenzyRank;static;
  end;
  TB1008FrenzyEffect = record
    Rank:Cardinal;
    UntilTick:UInt64;
    function Active(NowTick:UInt64):Boolean;
    procedure Start(ARank:Cardinal;NowTick:UInt64);
    function Remove:Boolean;
  end;
  TB1008CoerciveEffect = record
    Rank:Cardinal;
    UntilTick:UInt64;
    class function DefensePenalty(ARank:Cardinal):Integer;static;
    function Active(NowTick:UInt64):Boolean;
    function ActiveDefensePenalty(NowTick:UInt64):Integer;
    procedure Start(ARank:Cardinal;NowTick:UInt64);
    procedure Clear;
  end;
  TB1008AttackSkillStats = record
    ActionID,CooldownMS,StunMS:Cardinal;
    Range:Single;
    MPCost,BonusMin,BonusMax:Integer;
    class function Get(ID,Rank:Cardinal):TB1008AttackSkillStats;static;
    class function FromAction(ActionID:Cardinal):Cardinal;static;
    class function SelfFromAction(ActionID:Cardinal):Cardinal;static;
  end;
  TB1008LearnedSkill = record
    ID, Rank: Cardinal;
  end;
  TB1008SkillLearn = record
    Timestamp, CharacterID, SkillID: Cardinal;
    Code: Byte;
    class function Parse(const Packet:TBytes):TB1008SkillLearn;static;
    function IsStarterRequest(ClassID:Word):Boolean;
    function Supported:Boolean;
    function Ack:TBytes;
  end;
  TB1008SkillUpgrade = record
    Timestamp,CharacterID,SkillID,CurrentRank:Cardinal;
    Code:Byte;
    class function Parse(const Packet:TBytes):TB1008SkillUpgrade;static;
    function Supported:Boolean;
    function Ack(NewRank:Cardinal):TBytes;
  end;
  TB1008SkillReady = record
    Timestamp,ActorID,SkillID,Rank,TargetID:Cardinal;
    ActorKind,TargetKind,Code:Byte;
    X,Z,Y,Heading:Single;
    class function Parse(const Packet:TBytes):TB1008SkillReady;static;
    function Supported:Boolean;
    function Ack:TBytes;
  end;
  TB1008SkillCancel = record
    Timestamp,ActorID,SkillID:Cardinal;
    ActorKind:Byte;
    class function Parse(const Packet:TBytes):TB1008SkillCancel;static;
  end;
  TB1008ChargeAdmission = record
  private
    FArmed:Boolean;
    FTarget:Cardinal;
    FTick:UInt64;
    FX,FZ,FY,FTargetX,FTargetZ,FTargetY,FRange:Single;
  public
    procedure Arm(const Ready:TB1008SkillReady;TargetX,TargetZ,TargetY:Single;NowTick:UInt64);
    function Allows(Target:Cardinal;X,Z,Y:Single;NowTick:UInt64):Boolean;overload;
    function Allows(Target:Cardinal;X,Z,Y:Single;NowTick:UInt64;out Note:string):Boolean;overload;
  end;
  // Per-session server clock authority. Cancel never resets cooldown/replay state.
  TB1008AttackSkillCast = record
  private
    FPrepared,FHasRequest:Boolean;
    FTimestamp,FTarget,FPreparedRank,FActiveRank,FPreparedSkillID,FActiveSkillID:Cardinal;
    FPreparedTick:UInt64;
    FCooldownUntil:array[0..19] of UInt64;
  public
    function Prepare(Timestamp,Target:Cardinal;NowTick:UInt64;MP:Integer;Rank:Cardinal=1;SkillID:Cardinal=1001):Boolean;
    function Start(Timestamp,Target:Cardinal;NowTick:UInt64;var MP:Integer;SkillID:Cardinal=1001):Boolean;
    function RejectStart(Timestamp,Target,SkillID:Cardinal):Boolean;
    procedure Cancel;
    property PreparedSkillID:Cardinal read FPreparedSkillID;
    property ActiveRank:Cardinal read FActiveRank;
    property ActiveSkillID:Cardinal read FActiveSkillID;
  end;
  TB1008PowerStrikeCast = TB1008AttackSkillCast; // Existing callers default to 1001.
  TB1008SkillWire = record
    class function BuildProfessionEffect(Timestamp:Cardinal;ActorKind:Byte;
      ActorID,SkillID,Rank,DurationMS:Cardinal;Add:Boolean):TBytes;static;
    class function BuildMobStun(Timestamp,Handle:Cardinal;Add:Boolean;SkillID:Cardinal=B1008BodyBlowID):TBytes;static;
    class function BuildMobWindBlade(Timestamp,Handle,Rank:Cardinal;Add:Boolean):TBytes;static;
    class function BuildMobCoercive(Timestamp,Handle,Rank:Cardinal;Add:Boolean):TBytes;static;
    class function BuildFrenzy(Timestamp,Rank:Cardinal;Add:Boolean):TBytes;static;
    class function StarterID(ClassID:Word):Cardinal;static;
    class function SupportedRank(ID,Rank:Cardinal):Boolean;static;
    class function BuildList(Timestamp:Cardinal;
      const Skills:TArray<TB1008LearnedSkill>):TBytes;static;
    class function BuildCancel(Timestamp:Cardinal;X,Z,Y,Heading:Single;SkillID:Cardinal=1001):TBytes;static;
  end;

implementation

uses System.Math, Emulator.FlettaProc.B1008,Emulator.ProfessionSkills.B1008;

class function TB1008SkillTraining.Get(ID,Rank:Cardinal):TB1008SkillTraining;
const MasteryLevels:array[1..5] of Integer=(9,12,16,20,24);
var P:TB1008ProfessionSkill;I:Integer;
begin
  Result:=Default(TB1008SkillTraining);Result.SPCost:=1;
  if not TB1008SkillWire.SupportedRank(ID,Rank) then
    raise EKarosProtocol.Create('Unsupported training rank');
  if TB1008ProfessionSkill.Supported(ID) then begin
    P:=TB1008ProfessionSkill.Get(ID,Rank);Result.RequiredLevel:=P.RequiredLevel;
    Result.PrerequisiteCount:=P.PrerequisiteCount;
    for I:=0 to 2 do begin
      Result.PrerequisiteIDs[I]:=P.PrerequisiteIDs[I];
      Result.PrerequisiteRanks[I]:=P.PrerequisiteRanks[I];
    end;
    if Result.PrerequisiteCount>0 then begin
      Result.PrerequisiteID:=Result.PrerequisiteIDs[0];
      Result.PrerequisiteRank:=Result.PrerequisiteRanks[0];
    end;
    Exit;
  end;
  case ID of
    B1008PowerStrikeID:Result.RequiredLevel:=TB1008PowerStrikeRank.Get(Rank).RequiredLevel;
    B1008CoerciveID:begin
      Result.RequiredLevel:=3*Integer(Rank);Result.PrerequisiteID:=1001;Result.PrerequisiteRank:=1;
    end;
    B1008BodyBlowID:begin
      Result.RequiredLevel:=2+5*(Integer(Rank)-1);Result.PrerequisiteID:=1001;Result.PrerequisiteRank:=1;
    end;
    B1008FrenzyID:Result.RequiredLevel:=3*Integer(Rank);
    B1008ProvocationID:Result.RequiredLevel:=1+3*Integer(Rank);
    B1008StrengthMasteryID:begin
      Result.RequiredLevel:=MasteryLevels[Rank];Result.PrerequisiteID:=1004;Result.PrerequisiteRank:=1;
    end;
  else raise EKarosProtocol.Create('Unsupported training skill');end;
  if Result.PrerequisiteID<>0 then begin
    Result.PrerequisiteCount:=1;Result.PrerequisiteIDs[0]:=Result.PrerequisiteID;
    Result.PrerequisiteRanks[0]:=Result.PrerequisiteRank;
  end;
end;

class function TB1008FrenzyRank.Get(Rank:Cardinal):TB1008FrenzyRank;
const Attack:array[1..5] of Integer=(4,8,10,12,14);
  Defense:array[1..5] of Integer=(5,8,11,14,17);
begin
  if (Rank<1) or (Rank>5) then raise EKarosProtocol.Create('Unsupported Frenzy rank');
  // Original skillLevel MP +24, skillData type 6/17 additive double +18.
  Result.MPCost:=4+Integer(Rank);Result.AttackBonus:=Attack[Rank];Result.DefensePenalty:=Defense[Rank];
end;

function TB1008FrenzyEffect.Active(NowTick:UInt64):Boolean;
begin Result:=(Rank>0) and (NowTick<UntilTick);end;
procedure TB1008FrenzyEffect.Start(ARank:Cardinal;NowTick:UInt64);
begin
  TB1008FrenzyRank.Get(ARank);Rank:=ARank;UntilTick:=NowTick+15000;
end;
function TB1008FrenzyEffect.Remove:Boolean;
begin Result:=Rank<>0;Rank:=0;UntilTick:=0;end;

class function TB1008CoerciveEffect.DefensePenalty(ARank:Cardinal):Integer;
begin
  if (ARank<1) or (ARank>5) then raise EKarosProtocol.Create('Unsupported Coercive rank');
  Result:=3+2*Integer(ARank);
end;
function TB1008CoerciveEffect.Active(NowTick:UInt64):Boolean;
begin Result:=(Rank>0) and (NowTick<UntilTick);end;
function TB1008CoerciveEffect.ActiveDefensePenalty(NowTick:UInt64):Integer;
begin
  Result:=0;
  // Subtract from real target armor, clamped at zero, before mitigation.
  if Active(NowTick) then Result:=DefensePenalty(Rank);
end;
procedure TB1008CoerciveEffect.Start(ARank:Cardinal;NowTick:UInt64);
begin DefensePenalty(ARank);Rank:=ARank;UntilTick:=NowTick+B1008CoerciveDurationMS;end;
procedure TB1008CoerciveEffect.Clear;
begin Rank:=0;UntilTick:=0;end;

class function TB1008PowerStrikeRank.Get(Rank:Cardinal):TB1008PowerStrikeRank;
const Levels:array[1..5] of Integer=(1,3,5,7,9);
  Mana:array[1..5] of Integer=(4,5,5,6,7);
  LowBonus:array[1..5] of Integer=(15,20,25,30,35);
  HighBonus:array[1..5] of Integer=(20,25,30,35,41);
begin
  if (Rank<1) or (Rank>5) then raise EKarosProtocol.Create('Unsupported Power Strike rank');
  // skillLevel: +8 SP, +C required level, +24 MP, +B0/+B8 bonus.
  // Our integer balance rounds the original fractional bonus to nearest;
  // rank 1 retains the already confirmed 15..20 approximation.
  Result.RequiredLevel:=Levels[Rank];Result.SPCost:=1;Result.MPCost:=Mana[Rank];
  Result.BonusMin:=LowBonus[Rank];Result.BonusMax:=HighBonus[Rank];
end;

class function TB1008SkillWire.SupportedRank(ID,Rank:Cardinal):Boolean;
begin
  Result:=(((ID=B1008PowerStrikeID) or (ID=B1008CoerciveID) or (ID=B1008BodyBlowID) or
    (ID=B1008FrenzyID) or (ID=B1008ProvocationID) or (ID=B1008StrengthMasteryID) or
      TB1008ProfessionSkill.Supported(ID)) and (Rank>=1) and (Rank<=5)) or
    (((ID=B1008SlashID) or (ID=B1008SupplementID) or TB1008FlettaProc.Enabled(ID)) and (Rank=1));
end;

class function TB1008AttackSkillStats.FromAction(ActionID:Cardinal):Cardinal;
begin
  case ActionID of
    0:Result:=B1008TornadoID; // b1008 Fletta animation name is ASCII "0".
    B1008PowerStrikeActionID:Result:=B1008PowerStrikeID;
    B1008BodyBlowActionID:Result:=B1008BodyBlowID;
    1006:Result:=B1008BladeCrashID;
    1008:Result:=B1008WindBladeID;
    1021:Result:=B1008ThunderHowlID;
    1010:Result:=B1008SpineBreakerID;
    1012:Result:=B1008SlaterID;
    1005:Result:=B1008StunAttackID;
    1009:Result:=B1008CycloneID;
    1011:Result:=B1008PhantomThrustID;
  else Result:=0;end;
end;

class function TB1008AttackSkillStats.SelfFromAction(ActionID:Cardinal):Cardinal;
begin
  case ActionID of
    B1008FrenzyActionID:Result:=B1008FrenzyID;
    B1008ProvocationActionID:Result:=B1008ProvocationID;
    B1008CoerciveActionID:Result:=B1008CoerciveID;
    1021:Result:=B1008ThunderHowlID;
    1023:Result:=B1008SwordRevengeID;
    1005:Result:=B1008StunAttackID;
    // 1019 also belongs to class120 Revenge. Session resolves this alias
    // from the prepared SkillID or the native finish SkillID.
    1019:Result:=B1008SwordDeathLeapID;
    1020:Result:=B1008PolearmDeathLeapID;
  else Result:=0;end;
end;

class function TB1008AttackSkillStats.Get(ID,Rank:Cardinal):TB1008AttackSkillStats;
const BodyLow:array[1..5] of Integer=(1,5,9,13,18);
  BodyHigh:array[1..5] of Integer=(5,10,16,20,25);
var R:TB1008PowerStrikeRank;F:TB1008FrenzyRank;P:TB1008ProfessionSkill;
begin
  Result:=Default(TB1008AttackSkillStats);
  if TB1008ProfessionSkill.Supported(ID) and not TB1008ProfessionSkill.IsPassive(ID) then begin
    P:=TB1008ProfessionSkill.Get(ID,Rank);
    Result.ActionID:=P.ActionID;Result.CooldownMS:=P.CooldownMS;Result.Range:=P.Range;
    Result.MPCost:=P.MPCost;Result.BonusMin:=P.BonusMin;Result.BonusMax:=P.BonusMax;
    Result.StunMS:=P.StunMS;Exit;
  end;
  if TB1008FlettaProc.Enabled(ID) and (Rank=1) then begin
    Result.ActionID:=0;Result.Range:=B1008TornadoRange; // Native local range repair; no extra melee reach.
    if ID=B1008RockStraightID then Result.StunMS:=1300;
  end else if ID=B1008PowerStrikeID then begin
    R:=TB1008PowerStrikeRank.Get(Rank);Result.ActionID:=B1008PowerStrikeActionID;
    Result.MPCost:=R.MPCost;Result.BonusMin:=R.BonusMin;Result.BonusMax:=R.BonusMax;
    Result.CooldownMS:=B1008PowerStrikeCooldownMS;Result.Range:=B1008PowerStrikeRange;
  end else if (ID=B1008BodyBlowID) and (Rank>=1) and (Rank<=5) then begin
    // Original ranks: MP +24, cooldown +4C, range +64, duration +88.
    // Integer additive bonuses use the same nearest rounding as Power Strike.
    Result.ActionID:=B1008BodyBlowActionID;Result.MPCost:=2+2*Integer(Rank);
    Result.CooldownMS:=40000;Result.Range:=30+20*Integer(Rank);Result.StunMS:=B1008BodyBlowStunMS;
    Result.BonusMin:=BodyLow[Rank];Result.BonusMax:=BodyHigh[Rank];
  end else if ID=B1008FrenzyID then begin
    F:=TB1008FrenzyRank.Get(Rank);Result.ActionID:=B1008FrenzyActionID;
    Result.MPCost:=F.MPCost;Result.CooldownMS:=30000;
  end else if (ID=B1008CoerciveID) and (Rank>=1) and (Rank<=5) then begin
    Result.ActionID:=B1008CoerciveActionID;Result.MPCost:=4+Integer(Rank);
    Result.CooldownMS:=10000;Result.Range:=20;
  end else if (ID=B1008ProvocationID) and (Rank>=1) and (Rank<=5) then begin
    Result.ActionID:=B1008ProvocationActionID;Result.MPCost:=4+Integer(Rank);
    Result.CooldownMS:=20000;Result.Range:=B1008ProvocationRanges[Rank];
  end else raise EKarosProtocol.Create('Unsupported attack skill/rank');
end;

procedure BE(var P:TBytes;O:Integer;V:Cardinal);
begin
  P[O]:=Byte(V shr 24);P[O+1]:=Byte((V shr 16) and $FF);
  P[O+2]:=Byte((V shr 8) and $FF);P[O+3]:=Byte(V and $FF);
end;

class function TB1008SkillWire.BuildProfessionEffect(Timestamp:Cardinal;ActorKind:Byte;
  ActorID,SkillID,Rank,DurationMS:Cardinal;Add:Boolean):TBytes;
begin
  if not (ActorKind in [0,1]) or (ActorID=0) or
    not TB1008ProfessionSkill.Supported(SkillID) or TB1008ProfessionSkill.IsPassive(SkillID) or
    (Rank<1) or (Rank>5) or ((DurationMS mod 1000)<>0) then
    raise EKarosProtocol.Create('Invalid profession effect');
  // Shared 05/09 layout; native player duration is expressed in seconds.
  // NPC receiver still derives its visual duration from the skill definition.
  Result:=nil;SetLength(Result,26);Result[0]:=5;Result[1]:=9;
  BE(Result,2,Timestamp);Result[6]:=ActorKind;BE(Result,7,ActorID);
  Result[11]:=Ord(Add);Result[13]:=1;BE(Result,14,SkillID);BE(Result,18,Rank);
  if Add then BE(Result,22,DurationMS div 1000);
end;

class function TB1008SkillWire.BuildMobStun(Timestamp,Handle:Cardinal;Add:Boolean;SkillID:Cardinal):TBytes;
begin
  if Handle=0 then raise EKarosProtocol.Create('Missing stun target');
  if (SkillID<>B1008BodyBlowID) and (SkillID<>B1008RockStraightID) then
    raise EKarosProtocol.Create('Unsupported mob stun');
  // 05/09: 52069E -> member B8+9*4 -> 6159F0 -> vtable 679408 -> 52B5FA.
  // 5294E6 reads all three BE32 values even for removal. NPC 4DD9F2
  // ignores the third (time) value and uses skillLevel rank 1 duration/effect.
  // Keep this builder NPC/Body Blow specific; player time semantics differ.
  Result:=nil;SetLength(Result,26);Result[0]:=5;Result[1]:=9;
  BE(Result,2,Timestamp);Result[6]:=1;BE(Result,7,Handle);
  Result[11]:=Ord(Add);Result[13]:=1;
  BE(Result,14,SkillID);BE(Result,18,1);
end;

class function TB1008SkillWire.BuildMobWindBlade(Timestamp,Handle,Rank:Cardinal;Add:Boolean):TBytes;
begin
  if (Handle=0) or (Rank<1) or (Rank>5) then raise EKarosProtocol.Create('Invalid Wind Blade effect');
  Result:=nil;SetLength(Result,26);Result[0]:=5;Result[1]:=9;
  BE(Result,2,Timestamp);Result[6]:=1;BE(Result,7,Handle);
  Result[11]:=Ord(Add);Result[13]:=1;
  BE(Result,14,B1008WindBladeID);BE(Result,18,Rank);BE(Result,22,12);
end;

function FreshOrEqual(NewStamp,OldStamp:Cardinal):Boolean;
begin
  Result:=((Int64(NewStamp)-Int64(OldStamp)+$100000000) mod $100000000)<$80000000;
end;

class function TB1008SkillWire.BuildMobCoercive(Timestamp,Handle,Rank:Cardinal;Add:Boolean):TBytes;
begin
  if Handle=0 then raise EKarosProtocol.Create('Missing Coercive target');
  TB1008CoerciveEffect.DefensePenalty(Rank);
  // Same NPC buff receiver as Body Blow. All original Coercive ranks last
  // 20 seconds; 4DDAB4 refreshes existing duration/rank rather than stacking.
  Result:=nil;SetLength(Result,26);Result[0]:=5;Result[1]:=9;
  BE(Result,2,Timestamp);Result[6]:=1;BE(Result,7,Handle);
  Result[11]:=Ord(Add);Result[13]:=1;BE(Result,14,B1008CoerciveID);BE(Result,18,Rank);
  if Add then BE(Result,22,20);
end;

class function TB1008SkillWire.BuildFrenzy(Timestamp,Rank:Cardinal;Add:Boolean):TBytes;
begin
  TB1008FrenzyRank.Get(Rank);
  // 52B5FA -> player 4EB9D4. Duration is seconds, decremented by frame
  // delta in 4EB408; stats remain authoritative through 08/02.
  Result:=nil;SetLength(Result,26);Result[0]:=5;Result[1]:=9;
  BE(Result,2,Timestamp);BE(Result,7,1);Result[11]:=Ord(Add);Result[13]:=1;
  BE(Result,14,B1008FrenzyID);BE(Result,18,Rank);
  if Add then BE(Result,22,15);
end;

procedure TB1008ChargeAdmission.Arm(const Ready:TB1008SkillReady;TargetX,TargetZ,TargetY:Single;NowTick:UInt64);
begin
  FArmed:=Ready.Supported and (Ready.SkillID=B1008BodyBlowID);
  FRange:=0;
  if FArmed then FRange:=TB1008AttackSkillStats.Get(Ready.SkillID,Ready.Rank).Range;
  FTarget:=Ready.TargetID;FTick:=NowTick;FX:=Ready.X;FZ:=Ready.Z;FY:=Ready.Y;
  FTargetX:=TargetX;FTargetZ:=TargetZ;FTargetY:=TargetY;
end;

function TB1008ChargeAdmission.Allows(Target:Cardinal;X,Z,Y:Single;NowTick:UInt64):Boolean;
var Note:string;
begin Result:=Allows(Target,X,Z,Y,NowTick,Note);end;

function TB1008ChargeAdmission.Allows(Target:Cardinal;X,Z,Y:Single;NowTick:UInt64;out Note:string):Boolean;
var DX,DZ,PX,PZ,Len2,Along,Nearest:Double;
begin
  Result:=False;Note:='unarmed/target/time/invalid coordinate';
  if not FArmed or (Target<>FTarget) or (NowTick<FTick) or
    (NowTick-FTick>B1008SkillHandshakeMS) or
    IsNan(X) or IsNan(Z) or IsNan(Y) or IsInfinite(X) or IsInfinite(Z) or IsInfinite(Y) then Exit;
  DX:=FTargetX-FX;DZ:=FTargetZ-FZ;PX:=X-FX;PZ:=Z-FZ;Len2:=DX*DX+DZ*DZ;
  if Len2<0.001 then begin Note:='coincident prepared target';Exit;end;
  // Authored admission corridor for the original charge, not general movement.
  // No backwards/sideways jump, no travel beyond this prepared rank's reach.
  // Session still requires the matching unexpired preparation before committing.
  Along:=(PX*DX+PZ*DZ)/Len2;Nearest:=EnsureRange(Along,0.0,1.0);
  Result:=(Along>=0) and (Along<=1) and (PX*PX+PZ*PZ<=Sqr(FRange)) and
    (Sqr(PX-Nearest*DX)+Sqr(PZ-Nearest*DZ)<=Sqr(3.0)) and
    (Abs(Y-FY)<=30) and (Y>=Min(FY,FTargetY)-10) and (Y<=Max(FY,FTargetY)+10);
  Note:=Format('allowed=%d age=%ums range=%.2f travel=%.2f along=%.3f side=%.2f ready=(%.3f,%.3f,%.3f) target=(%.3f,%.3f,%.3f) start=(%.3f,%.3f,%.3f)',
    [Ord(Result),NowTick-FTick,FRange,Sqrt(PX*PX+PZ*PZ),Along,
     Sqrt(Sqr(PX-Nearest*DX)+Sqr(PZ-Nearest*DZ)),FX,FZ,FY,FTargetX,FTargetZ,FTargetY,X,Z,Y],TFormatSettings.Invariant);
end;

class function TB1008SkillReady.Parse(const Packet:TBytes):TB1008SkillReady;
begin
  // 0x500ABE / 0x52931E / 0x52ADCF: BE identifiers, raw LE float pose.
  if (Length(Packet)<>41) or (Packet[0]<>5) or (Packet[1]<>3) then
    raise EKarosProtocol.Create('Invalid skill ready packet');
  Result.Timestamp:=TB1008Wire.ReadBE32(Packet,2);
  Result.ActorKind:=Packet[6];Result.ActorID:=TB1008Wire.ReadBE32(Packet,7);
  Result.SkillID:=TB1008Wire.ReadBE32(Packet,11);Result.Rank:=TB1008Wire.ReadBE32(Packet,15);
  Move(Packet[19],Result.X,4);Move(Packet[23],Result.Z,4);
  Move(Packet[27],Result.Y,4);Move(Packet[31],Result.Heading,4);
  Result.TargetKind:=Packet[35];Result.TargetID:=TB1008Wire.ReadBE32(Packet,36);
  Result.Code:=Packet[40];
end;

function TB1008SkillReady.Supported:Boolean;
begin
  Result:=(ActorKind=0) and (ActorID=1) and
    ((((SkillID=B1008PowerStrikeID) or (SkillID=B1008BodyBlowID) or
      (TB1008ProfessionSkill.IsAttack(SkillID) and not TB1008ProfessionSkill.IsSelf(SkillID)) or
      TB1008FlettaProc.YinSupported(SkillID)) and (TargetKind=1) and (TargetID<>0)) or
     (((SkillID=B1008FrenzyID) or (SkillID=B1008ProvocationID) or (SkillID=B1008CoerciveID) or
       TB1008ProfessionSkill.IsSelf(SkillID) or TB1008FlettaBarrier.Supported(SkillID)) and
       (TargetKind=0) and (TargetID=1))) and
    TB1008SkillWire.SupportedRank(SkillID,Rank) and (Code=$1A) and
    not IsNan(X) and not IsNan(Z) and not IsNan(Y) and not IsNan(Heading) and
    not IsInfinite(X) and not IsInfinite(Z) and not IsInfinite(Y) and not IsInfinite(Heading);
end;

function TB1008SkillReady.Ack:TBytes;
begin
  if not Supported then raise EKarosProtocol.Create('Unsupported skill ready reply');
  Result:=nil;SetLength(Result,41);Result[0]:=5;Result[1]:=3;
  BE(Result,2,Timestamp);BE(Result,7,ActorID);BE(Result,11,SkillID);BE(Result,15,Rank);
  Move(X,Result[19],4);Move(Z,Result[23],4);Move(Y,Result[27],4);Move(Heading,Result[31],4);
  Result[35]:=TargetKind;BE(Result,36,TargetID);Result[40]:=$1A;
end;

class function TB1008SkillCancel.Parse(const Packet:TBytes):TB1008SkillCancel;
begin
  if (Length(Packet)<>31) or (Packet[0]<>5) or (Packet[1]<>4) then
    raise EKarosProtocol.Create('Invalid skill cancel packet');
  Result.Timestamp:=TB1008Wire.ReadBE32(Packet,2);Result.ActorKind:=Packet[6];
  Result.ActorID:=TB1008Wire.ReadBE32(Packet,7);Result.SkillID:=TB1008Wire.ReadBE32(Packet,11);
end;

class function TB1008SkillWire.BuildCancel(Timestamp:Cardinal;X,Z,Y,Heading:Single;SkillID:Cardinal):TBytes;
begin
  if (SkillID<>1001) and (SkillID<>1002) and (SkillID<>1003) and (SkillID<>1004) and (SkillID<>1005) and
    not TB1008ProfessionSkill.IsAttack(SkillID) and not TB1008ProfessionSkill.IsSelf(SkillID) and
    not TB1008FlettaProc.Enabled(SkillID) then
    raise EKarosProtocol.Create('Unsupported cancelled skill');
  // 0x500B72 / 0x529342 / 0x52B00F. Use server-admitted pose, not rejected input.
  Result:=nil;SetLength(Result,31);Result[0]:=5;Result[1]:=4;
  BE(Result,2,Timestamp);BE(Result,7,1);BE(Result,11,SkillID);
  Move(X,Result[15],4);Move(Z,Result[19],4);Move(Y,Result[23],4);Move(Heading,Result[27],4);
end;

function SkillCooldownIndex(SkillID:Cardinal):Integer;
begin
  case SkillID of
    1001:Exit(0);
    1003:Exit(1);
    1004:Exit(2);
    1005:Exit(3);
    1002:Exit(4);
  end;
  if TB1008FlettaProc.Enabled(SkillID) then Exit(5);
  if (SkillID>=1101) and (SkillID<=1107) then Exit(6+Integer(SkillID)-1101);
  if (SkillID>=1901) and (SkillID<=1907) then Exit(13+Integer(SkillID)-1901);
  Result:=-1;
end;

function TB1008AttackSkillCast.Prepare(Timestamp,Target:Cardinal;NowTick:UInt64;MP:Integer;Rank,SkillID:Cardinal):Boolean;
var Stats:TB1008AttackSkillStats;Index:Integer;
begin
  Result:=False;
  if ((SkillID<>1001) and (SkillID<>1002) and (SkillID<>1003) and (SkillID<>1004) and (SkillID<>1005) and
    not TB1008ProfessionSkill.IsAttack(SkillID) and not TB1008ProfessionSkill.IsSelf(SkillID) and
    not TB1008FlettaProc.Enabled(SkillID)) or
    not TB1008SkillWire.SupportedRank(SkillID,Rank) then Exit;
  Stats:=TB1008AttackSkillStats.Get(SkillID,Rank);Index:=SkillCooldownIndex(SkillID);
  if Index<0 then Exit;
  if ((SkillID=1004) or (SkillID=1005) or (SkillID=1002) or TB1008ProfessionSkill.IsSelf(SkillID) or
    TB1008FlettaBarrier.Supported(SkillID)) and (Target<>1) then Exit;
  if (Target=0) or (MP<Stats.MPCost) or (NowTick<FCooldownUntil[Index]) then Exit;
  if FPrepared and (NowTick>=FPreparedTick) and (NowTick-FPreparedTick<=B1008SkillHandshakeMS) then Exit;
  if FHasRequest and ((Timestamp=FTimestamp) or not FreshOrEqual(Timestamp,FTimestamp)) then Exit;
  FPrepared:=True;FHasRequest:=True;FTimestamp:=Timestamp;FTarget:=Target;FPreparedTick:=NowTick;
  FPreparedRank:=Rank;
  FPreparedSkillID:=SkillID;
  Result:=True;
end;

function TB1008AttackSkillCast.Start(Timestamp,Target:Cardinal;NowTick:UInt64;var MP:Integer;SkillID:Cardinal):Boolean;
var Stats:TB1008AttackSkillStats;Index:Integer;
begin
  Result:=False;
  if not FPrepared or (SkillID<>FPreparedSkillID) or (Target<>FTarget) or not FreshOrEqual(Timestamp,FTimestamp) or
    (NowTick<FPreparedTick) or (NowTick-FPreparedTick>B1008SkillHandshakeMS) then Exit;
  Stats:=TB1008AttackSkillStats.Get(SkillID,FPreparedRank);Index:=SkillCooldownIndex(SkillID);
  if Index<0 then Exit;
  if (NowTick<FCooldownUntil[Index]) or (MP<Stats.MPCost) then Exit;
  FPrepared:=False;FCooldownUntil[Index]:=NowTick+Stats.CooldownMS;
  FActiveRank:=FPreparedRank;FActiveSkillID:=FPreparedSkillID;
  Dec(MP,Stats.MPCost);Result:=True;
end;

procedure TB1008AttackSkillCast.Cancel;
begin FPrepared:=False;end;

function TB1008AttackSkillCast.RejectStart(Timestamp,Target,SkillID:Cardinal):Boolean;
begin
  // Only the matching prepared request may release the native client cast.
  // Expired preparation also needs cancellation; never debit MP/start cooldown.
  Result:=FPrepared and (SkillID=FPreparedSkillID) and (Target=FTarget) and
    FreshOrEqual(Timestamp,FTimestamp);
  if Result then FPrepared:=False;
end;

class function TB1008SkillLearn.Parse(const Packet:TBytes):TB1008SkillLearn;
begin
  // CAttackSkillLearnPacket serializer 0x47E46C, receiver 0x52B1D0.
  if (Length(Packet)<>15) or (Packet[0]<>5) or (Packet[1]<>6) then
    raise EKarosProtocol.Create('Invalid skill learn packet');
  Result.Timestamp:=TB1008Wire.ReadBE32(Packet,2);
  Result.CharacterID:=TB1008Wire.ReadBE32(Packet,6);
  Result.SkillID:=TB1008Wire.ReadBE32(Packet,10);
  Result.Code:=Packet[14];
end;

function TB1008SkillLearn.IsStarterRequest(ClassID:Word):Boolean;
begin
  Result:=(CharacterID=1) and (SkillID=TB1008SkillWire.StarterID(ClassID)) and (Code=$1A);
end;

function TB1008SkillLearn.Supported:Boolean;
begin
  Result:=(CharacterID=1) and ((SkillID=B1008BodyBlowID) or
    (SkillID=B1008FrenzyID) or (SkillID=B1008ProvocationID) or (SkillID=B1008CoerciveID) or
    (SkillID=B1008StrengthMasteryID) or TB1008ProfessionSkill.Supported(SkillID)) and (Code=$1A);
end;

function TB1008SkillLearn.Ack:TBytes;
begin
  // 0x52B2CE: add rank 1, subtract its SP cost, refresh the skill window.
  // Emit only for a new committed acquisition, never for a duplicate request.
  if not Supported then raise EKarosProtocol.Create('Unsupported skill learn reply');
  Result:=nil;SetLength(Result,15);Result[0]:=5;Result[1]:=6;
  BE(Result,2,Timestamp);BE(Result,6,CharacterID);BE(Result,10,SkillID);Result[14]:=$1A;
end;

class function TB1008SkillUpgrade.Parse(const Packet:TBytes):TB1008SkillUpgrade;
begin
  // 0x47E4BE serializer. 0x480A1A fetches CURRENT rank via 0x4FFF66;
  // success receiver 0x52B3ED expects the NEW rank at the same offset.
  if (Length(Packet)<>19) or (Packet[0]<>5) or (Packet[1]<>7) then
    raise EKarosProtocol.Create('Invalid skill upgrade packet');
  Result.Timestamp:=TB1008Wire.ReadBE32(Packet,2);Result.CharacterID:=TB1008Wire.ReadBE32(Packet,6);
  Result.SkillID:=TB1008Wire.ReadBE32(Packet,10);Result.CurrentRank:=TB1008Wire.ReadBE32(Packet,14);
  Result.Code:=Packet[18];
end;

function TB1008SkillUpgrade.Supported:Boolean;
begin
  Result:=(CharacterID=1) and ((SkillID=B1008PowerStrikeID) or
    (SkillID=B1008BodyBlowID) or (SkillID=B1008FrenzyID) or (SkillID=B1008ProvocationID) or (SkillID=B1008CoerciveID) or
    (SkillID=B1008StrengthMasteryID) or TB1008ProfessionSkill.Supported(SkillID)) and (Code=$1A) and
    (CurrentRank>=1) and (CurrentRank<=5);
end;

function TB1008SkillUpgrade.Ack(NewRank:Cardinal):TBytes;
begin
  if not Supported or (NewRank<>CurrentRank+1) or (NewRank>5) then
    raise EKarosProtocol.Create('Unsupported skill upgrade reply');
  Result:=nil;SetLength(Result,19);Result[0]:=5;Result[1]:=7;
  BE(Result,2,Timestamp);BE(Result,6,CharacterID);BE(Result,10,SkillID);
  BE(Result,14,NewRank);Result[18]:=$1A;
end;

class function TB1008SkillWire.StarterID(ClassID:Word):Cardinal;
begin
  // b1008 skillBase.classId +8 and skillLevel.requiredLevel +C.
  // User rule: first active skill is rank 1, free of SP for each class.
  // Never send 05/06 success for this grant: it subtracts SP locally.
  case ClassID of
    100:Result:=B1008PowerStrikeID;
    300:Result:=B1008SlashID;
    500:Result:=B1008SupplementID;
  else raise EKarosProtocol.Create('Unsupported starter skill class');end;
end;

class function TB1008SkillWire.BuildList(Timestamp:Cardinal;
  const Skills:TArray<TB1008LearnedSkill>):TBytes;
var I,J,N:Integer;
begin
  N:=Length(Skills);
  if N>14 then raise EKarosProtocol.Create('Unsupported learned skill list');
  // 0x529655: header 12, BE count at +10, then two separate LE32
  // arrays: IDs, ranks. 0x52B115 clears/reloads skills without spending SP.
  SetLength(Result,12+N*8);Result[0]:=5;Result[1]:=5;
  BE(Result,2,Timestamp);BE(Result,6,1);
  Result[10]:=Byte(N shr 8);Result[11]:=Byte(N and $FF);
  for I:=0 to N-1 do begin
    if not SupportedRank(Skills[I].ID,Skills[I].Rank) then
      raise EKarosProtocol.Create('Unsupported saved skill');
    if (N>1) and ((Skills[I].ID=5001) or (Skills[I].ID=9001)) then
      for J:=0 to N-1 do if (J<>I) and not TB1008FlettaProc.Enabled(Skills[J].ID) then
        raise EKarosProtocol.Create('Mixed-class learned skill list');
    for J:=0 to I-1 do if Skills[J].ID=Skills[I].ID then
      raise EKarosProtocol.Create('Duplicate saved skill');
    Move(Skills[I].ID,Result[12+I*4],4);
    Move(Skills[I].Rank,Result[12+N*4+I*4],4);
  end;
end;

end.
