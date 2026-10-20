unit Emulator.FlettaProc.B1008;

interface

uses System.SysUtils, Emulator.Fletta.B1008;

const
  B1008TornadoID = 50221;
  B1008RockStraightID = 50224;
  B1008TornadoRange = 12;
  B1008TornadoVisualMS = 1000; // Presentation lifetime, not a damage-over-time effect.
  B1008FlettaProcBasisPoints = 1250;
  B1008FlettaProcHandshakeMS = 5000;

type
  TB1008FlettaBarrier = record
    SkillID:Cardinal;
    UntilTick:UInt64;
    RemainingHits:Integer;
    WindRatingBonus:Integer;
    class function Supported(ID:Cardinal):Boolean;static;
    class function DurationMS(ID:Cardinal):Cardinal;static;
    class function Healing(ID:Cardinal):Integer;static;
    function Active(NowTick:UInt64):Boolean;
    procedure Start(ID:Cardinal;NowTick:UInt64;RatingBonus:Integer=4);
    function Mitigate(Damage:Integer;NowTick:UInt64):Integer;
    function ResistsNegativeEffects(NowTick:UInt64):Boolean;
    function DefenseRatingBonus(NowTick:UInt64):Integer;
    class function FailureBasisPoints(RatingBonus:Integer):Integer;static;
    function CausesFailure(NowTick:UInt64;var RandomState:Cardinal;BaseRatingBonus:Integer=0):Boolean;
    procedure Clear;
  end;
  TB1008FlettaProcPhase = (fppIdle, fppQueued, fppPrepared, fppStarted, fppImpact);
  TB1008FlettaProc = record
  private
    FPhase:TB1008FlettaProcPhase;
    FTarget,FTimestamp,FSkillID:Cardinal;
    FUntilTick:UInt64;
    FGrantedRange:Single;
  public
    class function CombinedSkill(const Attributes:TB1008FlettaAttributes):Cardinal;static;
    class function Enabled(SkillID:Cardinal):Boolean;static;
    class function YinSupported(SkillID:Cardinal):Boolean;static;
    class function DirectMinimum(SkillID:Cardinal):Integer;static;
    class function DirectMaximum(SkillID:Cardinal):Integer;static;
    class function BuildTrigger(Timestamp,SkillID:Cardinal):TBytes;static;
    class function BuildVisual(Timestamp:Cardinal;Add:Boolean;SkillID:Cardinal=B1008TornadoID):TBytes;static;
    class function BuildBuff(Timestamp,SkillID,DurationMS:Cardinal;Add:Boolean):TBytes;static;
    class function EligibleImpact(ActionKind:Byte;SkillID:Cardinal;Damage,TargetHP:Integer):Boolean;static;
    function Active(NowTick:UInt64):Boolean;
    function TryQueue(const Attributes:TB1008FlettaAttributes;Target,Timestamp:Cardinal;
      NowTick:UInt64;var RandomState:Cardinal;EffectActive:Boolean=False;
      ChanceBasisPoints:Integer=B1008FlettaProcBasisPoints;
      GrantedRange:Single=B1008TornadoRange):Boolean;
    function Prepare(Target,Timestamp:Cardinal;NowTick:UInt64):Boolean;
    function Start(Target,Timestamp:Cardinal;NowTick:UInt64):Boolean;
    function Impact(Target,Timestamp:Cardinal;NowTick:UInt64):Boolean;
    procedure Clear;
    property Phase:TB1008FlettaProcPhase read FPhase;
    property Target:Cardinal read FTarget;
    property SkillID:Cardinal read FSkillID;
    property GrantedRange:Single read FGrantedRange;
  end;

implementation

uses Emulator.Protocol.B1008,System.Math;

class function TB1008FlettaBarrier.Supported(ID:Cardinal):Boolean;
begin Result:=(ID>=50211) and (ID<=50215);end;

class function TB1008FlettaBarrier.DurationMS(ID:Cardinal):Cardinal;
begin
  if not Supported(ID) then raise EArgumentException.Create('Unsupported Fletta barrier');
  if ID=50214 then Result:=180000 else Result:=10000;
end;

class function TB1008FlettaBarrier.Healing(ID:Cardinal):Integer;
begin if ID=50213 then Result:=100 else Result:=0;end;

function TB1008FlettaBarrier.Active(NowTick:UInt64):Boolean;
begin Result:=Supported(SkillID) and (NowTick<UntilTick) and ((SkillID<>50214) or (RemainingHits>0));end;

procedure TB1008FlettaBarrier.Start(ID:Cardinal;NowTick:UInt64;RatingBonus:Integer);
begin
  if (RatingBonus<0) or (RatingBonus>1000) then raise EArgumentOutOfRangeException.Create('Invalid Wind Barrier rating');
  UntilTick:=NowTick+DurationMS(ID);SkillID:=ID;RemainingHits:=0;
  WindRatingBonus:=RatingBonus;
  if ID=50214 then RemainingHits:=5;
end;

function TB1008FlettaBarrier.Mitigate(Damage:Integer;NowTick:UInt64):Integer;
var Percent:Integer;
begin
  if Damage<0 then raise EArgumentOutOfRangeException.Create('Negative incoming damage');
  Result:=Damage;
  if (Damage=0) or not Active(NowTick) then Exit;
  if SkillID=50214 then begin Dec(RemainingHits);Exit(0);end;
  case SkillID of
    50211,50213:Percent:=30;
    50212:Percent:=50;
    50215:Percent:=20;
  else Exit;end;
  // Apply after armor. Partial absorption keeps a minimum of one damage;
  // the five-hit rock barrier is the explicitly complete absorption effect.
  Result:=Max(1,Integer(Int64(Damage)*(100-Percent) div 100));
end;

function TB1008FlettaBarrier.ResistsNegativeEffects(NowTick:UInt64):Boolean;
begin Result:=(SkillID=50215) and Active(NowTick);end;

function TB1008FlettaBarrier.DefenseRatingBonus(NowTick:UInt64):Integer;
begin
  Result:=0;
  // User selected the numeric b1008 skillData +18 value, not tooltip +3.
  if (SkillID=50211) and Active(NowTick) then Result:=WindRatingBonus;
end;

class function TB1008FlettaBarrier.FailureBasisPoints(RatingBonus:Integer):Integer;
begin
  // User balance: one additional rating point is 0.1 percentage point.
  // Thus +4 = 0.4%, and future +20/+30 bonuses would give 2%/3%.
  Result:=Integer(EnsureRange(Int64(RatingBonus)*10,Int64(0),Int64(10000)));
end;

function TB1008FlettaBarrier.CausesFailure(NowTick:UInt64;var RandomState:Cardinal;BaseRatingBonus:Integer):Boolean;
var Chance:Integer;
begin
  Chance:=FailureBasisPoints(DefenseRatingBonus(NowTick)+BaseRatingBonus);Result:=False;
  if Chance=0 then Exit;
  RandomState:=Cardinal((UInt64(RandomState)*1664525+1013904223) and $FFFFFFFF);
  Result:=RandomState mod 10000<Cardinal(Chance);
end;

procedure TB1008FlettaBarrier.Clear;
begin Self:=Default(TB1008FlettaBarrier);end;

class function TB1008FlettaProc.Enabled(SkillID:Cardinal):Boolean;
begin Result:=YinSupported(SkillID) or TB1008FlettaBarrier.Supported(SkillID);end;

class function TB1008FlettaProc.YinSupported(SkillID:Cardinal):Boolean;
begin Result:=(SkillID=B1008TornadoID) or (SkillID=B1008RockStraightID);end;

class function TB1008FlettaProc.DirectMinimum(SkillID:Cardinal):Integer;
begin
  case SkillID of B1008TornadoID:Result:=200;B1008RockStraightID:Result:=130;
  else raise EArgumentException.Create('Unsupported direct Fletta damage');end;
end;

class function TB1008FlettaProc.DirectMaximum(SkillID:Cardinal):Integer;
begin
  case SkillID of B1008TornadoID:Result:=230;B1008RockStraightID:Result:=160;
  else raise EArgumentException.Create('Unsupported direct Fletta damage');end;
end;

class function TB1008FlettaProc.CombinedSkill(const Attributes:TB1008FlettaAttributes):Cardinal;
begin
  Attributes.Validate;Result:=0;
  if (Attributes.Invested(1)=1600) and (Attributes.Invested(2)=1600) then
    Result:=50200+Attributes.Selection(1)*10+Attributes.Selection(2);
end;

class function TB1008FlettaProc.BuildTrigger(Timestamp,SkillID:Cardinal):TBytes;
  procedure BE(Offset:Integer;Value:Cardinal);
  begin
    Result[Offset]:=Byte(Value shr 24);Result[Offset+1]:=Byte(Value shr 16);
    Result[Offset+2]:=Byte(Value shr 8);Result[Offset+3]:=Byte(Value);
  end;
begin
  if not Enabled(SkillID) and (SkillID<>High(Cardinal)) then
    raise EKarosProtocol.Create('Fletta proc not enabled');
  // 52B7A6 -> 4FFABD -> 5019B9. The queue contains a skill ID, not its action.
  // FFFFFFFF is the native empty-queue sentinel checked in 5019C5.
  Result:=nil;SetLength(Result,14);Result[0]:=5;Result[1]:=8;
  BE(2,Timestamp);BE(6,1);BE(10,SkillID);
end;

class function TB1008FlettaProc.BuildVisual(Timestamp:Cardinal;Add:Boolean;SkillID:Cardinal):TBytes;
begin
  if not YinSupported(SkillID) then raise EArgumentException.Create('Unsupported direct Fletta visual');
  Result:=BuildBuff(Timestamp,SkillID,1000,Add);
end;

class function TB1008FlettaProc.BuildBuff(Timestamp,SkillID,DurationMS:Cardinal;Add:Boolean):TBytes;
  procedure BE(Offset:Integer;Value:Cardinal);
  begin
    Result[Offset]:=Byte(Value shr 24);Result[Offset+1]:=Byte(Value shr 16);
    Result[Offset+2]:=Byte(Value shr 8);Result[Offset+3]:=Byte(Value);
  end;
begin
  if not Enabled(SkillID) then raise EKarosProtocol.Create('Unsupported Fletta buff');
  // Native player 05/09 -> 4EB9D4 -> skillLevel +43C (25605).
  // Body.pak defines this effect on every player model. Action 0 has no
  // animation callback, so damage alone cannot start it. No stat modifiers.
  Result:=nil;SetLength(Result,26);Result[0]:=5;Result[1]:=9;
  BE(2,Timestamp);BE(7,1);Result[11]:=Ord(Add);Result[13]:=1;
  BE(14,SkillID);BE(18,1);
  if Add then BE(22,DurationMS div 1000);
end;

class function TB1008FlettaProc.EligibleImpact(ActionKind:Byte;SkillID:Cardinal;Damage,TargetHP:Integer):Boolean;
begin
  // Ordinary and damaging trained skills can trigger. Fletta never triggers
  // itself or another Fletta skill; misses, utility casts and dead targets cannot.
  Result:=(Damage>0) and (TargetHP>0) and ((ActionKind=0) or
    ((ActionKind=1) and (SkillID>0) and ((SkillID<50000) or (SkillID>=60000))));
end;

function TB1008FlettaProc.Active(NowTick:UInt64):Boolean;
begin Result:=(FPhase<>fppIdle) and (NowTick<FUntilTick);end;

function TB1008FlettaProc.TryQueue(const Attributes:TB1008FlettaAttributes;
  Target,Timestamp:Cardinal;NowTick:UInt64;var RandomState:Cardinal;EffectActive:Boolean;
  ChanceBasisPoints:Integer;GrantedRange:Single):Boolean;
begin
  Result:=False;
  if (ChanceBasisPoints<0) or (ChanceBasisPoints>10000) then
    raise EArgumentOutOfRangeException.Create('Invalid Fletta proc chance');
  if IsNan(GrantedRange) or IsInfinite(GrantedRange) or (GrantedRange<=0) or (GrantedRange>1000) then
    raise EArgumentOutOfRangeException.Create('Invalid Fletta proc range');
  // Suppress the DRAW, not just the result, for the whole outstanding cast.
  if EffectActive or Active(NowTick) or (Target=0) or (ChanceBasisPoints=0) then Exit;
  if not Enabled(CombinedSkill(Attributes)) then Exit;
  RandomState:=Cardinal((UInt64(RandomState)*1664525+1013904223) and $FFFFFFFF);
  if RandomState mod 10000>=Cardinal(ChanceBasisPoints) then Exit;
  FPhase:=fppQueued;FTarget:=Target;FTimestamp:=Timestamp;
  FSkillID:=CombinedSkill(Attributes);
  if TB1008FlettaBarrier.Supported(FSkillID) then FTarget:=1;
  FGrantedRange:=GrantedRange;
  FUntilTick:=NowTick+B1008FlettaProcHandshakeMS;Result:=True;
end;

function Fresh(NewStamp,OldStamp:Cardinal):Boolean;
begin Result:=((Int64(NewStamp)-Int64(OldStamp)+$100000000) mod $100000000)<$80000000;end;

function TB1008FlettaProc.Prepare(Target,Timestamp:Cardinal;NowTick:UInt64):Boolean;
begin
  Result:=Active(NowTick) and (FPhase=fppQueued) and (Target=FTarget) and Fresh(Timestamp,FTimestamp);
  if Result then begin FPhase:=fppPrepared;FTimestamp:=Timestamp;end;
end;

function TB1008FlettaProc.Start(Target,Timestamp:Cardinal;NowTick:UInt64):Boolean;
begin
  Result:=Active(NowTick) and (FPhase=fppPrepared) and (Target=FTarget) and Fresh(Timestamp,FTimestamp);
  if Result then begin FPhase:=fppStarted;FTimestamp:=Timestamp;end;
end;

function TB1008FlettaProc.Impact(Target,Timestamp:Cardinal;NowTick:UInt64):Boolean;
begin
  Result:=Active(NowTick) and (FPhase=fppStarted) and (Target=FTarget) and Fresh(Timestamp,FTimestamp);
  if Result then begin FPhase:=fppImpact;FTimestamp:=Timestamp;end;
end;

procedure TB1008FlettaProc.Clear;
begin Self:=Default(TB1008FlettaProc);end;

end.
