unit Emulator.Fletta.B1008;

interface

uses System.SysUtils;

const
  B1008FlettaThreshold = 10000;
  B1008FlettaMaxTotal: Int64 = 21474836479999;
  B1008FlettaMaxInvested = 1600;
  B1008FlettaStageThresholds:array[1..6] of Integer=(10,100,200,400,800,1600);

type
  TB1008FlettaInvestment = record
    Timestamp, CharacterID, Category, Attribute, Amount: Cardinal;
    Code: Word;
    class function Parse(const Packet:TBytes):TB1008FlettaInvestment; static;
    function Supported:Boolean;
    function Ack(Accepted:Boolean):TBytes;
  end;

  TB1008FlettaInvestmentResult = (firRejected, firInsufficient, firDuplicate, firApplied);

  // One selection per axis, six stages per branch. Reset is a separate,
  // still unmapped protocol; investment must never silently change a branch.
  TB1008FlettaAttributes = record
    YangInvested,FireInvested:Integer;
    YinInvested,AirInvested,WoodInvested,EarthInvested,WaterInvested:Integer;
    procedure Validate;
    function Selection(Category:Cardinal):Cardinal;
    function Stage(Category,Attribute:Cardinal):Integer;
    function CanInvest(const Request:TB1008FlettaInvestment):Boolean;
    function YangStage:Integer;
    function FireStage:Integer;
    function Invested(Category:Cardinal):Integer;
    function RemainingCapacity(Category:Cardinal):Integer;
    procedure AddInvestment(const Request:TB1008FlettaInvestment);
    function RegenHP(Base:Integer):Integer;
    function RegenMP(Base:Integer):Double;
    function MagicAttack(Base:Integer):Integer;
    function Defense(Base:Integer):Integer;
    function AttackSpeed:Single;
    function MovementMultiplier:Single;
    procedure PhysicalAttack(var Minimum,Maximum:Integer;BaseAttack:Integer);
    procedure ApplyAttackParameters(var Packet:TBytes;Base,Minimum,Maximum:Integer);
    procedure ApplyCharacterInfo(var Packet:TBytes);
    procedure ApplyRegeneration(var Packet:TBytes; BaseHP:Integer;BaseMP:Integer=-1);
    procedure ApplySecondaryParameters(var Packet:TBytes;BaseMagic,BaseDefense,GearDefense:Integer);
    procedure ApplySpeeds(var Packet:TBytes);
  end;

  TB1008Fletta = record
    Total: Int64;
    procedure Validate;
    function Points: Integer;
    function Progress: Integer;
    procedure Add(Amount: Integer);
    class function LevelCapacity(PlayerLevel:Integer;Rate:Integer=100):Int64; static;
    procedure CreditKill(Amount,Rate,PlayerLevel:Integer;var RateRemainder:Integer);
    class function KillGain(PlayerLevel,MobLevel: Integer): Integer; static;
    procedure Apply(var Packet: TBytes;PlayerLevel:Integer;Rate:Integer=100);
  end;

implementation

uses Emulator.Protocol.B1008, Emulator.World.B1008;

procedure FlettaBE32(var P:TBytes;Offset:Integer;V:Cardinal);
begin
  P[Offset]:=Byte(V shr 24);P[Offset+1]:=Byte(V shr 16);
  P[Offset+2]:=Byte(V shr 8);P[Offset+3]:=Byte(V);
end;

class function TB1008FlettaInvestment.Parse(const Packet:TBytes):TB1008FlettaInvestment;
begin
  // AMo b1008 serializer 0x4C0980; receiver 0x527F77.
  if (Length(Packet)<>24) then raise EKarosProtocol.Create('Invalid Fletta investment length');
  if (Packet[0]<>8) or (Packet[1]<>4) then raise EKarosProtocol.Create('Invalid Fletta investment opcode');
  Result.Timestamp:=TB1008Wire.ReadBE32(Packet,2);
  Result.CharacterID:=TB1008Wire.ReadBE32(Packet,6);
  Result.Category:=TB1008Wire.ReadBE32(Packet,10);
  Result.Attribute:=TB1008Wire.ReadBE32(Packet,14);
  Result.Amount:=TB1008Wire.ReadBE32(Packet,18);
  Result.Code:=TB1008Wire.ReadBE16(Packet,22);
end;

function TB1008FlettaInvestment.Supported:Boolean;
begin
  Result:=(CharacterID=1) and (Code=$87) and
    (((Category=1) and (Attribute>=1) and (Attribute<=2)) or
     ((Category=2) and (Attribute>=1) and (Attribute<=5))) and
    (Amount>=1) and (Amount<=B1008FlettaMaxInvested);
end;

function TB1008FlettaInvestment.Ack(Accepted:Boolean):TBytes;
begin
  if Accepted and not Supported then raise EKarosProtocol.Create('Unsafe Fletta acknowledgement');
  Result:=nil;SetLength(Result,24);Result[0]:=8;Result[1]:=4;
  FlettaBE32(Result,2,Timestamp);FlettaBE32(Result,6,1);
  if Accepted then begin
    FlettaBE32(Result,10,Category);FlettaBE32(Result,14,Attribute);
    FlettaBE32(Result,18,Amount);Result[23]:=$87;
  end else Result[23]:=$88;
  // Success ADDS amount to the selected axis and SUBTRACTS it from free FP.
  // Never replay this delta on reconnect or for a duplicate request.
end;

procedure TB1008FlettaAttributes.Validate;
var Values:TArray<Integer>;I:Integer;
begin
  Values:=TArray<Integer>.Create(YangInvested,YinInvested,AirInvested,FireInvested,
    WoodInvested,EarthInvested,WaterInvested);
  for I in Values do if (I<0) or (I>B1008FlettaMaxInvested) then
    raise EKarosProtocol.Create('Invalid Fletta investment state');
  if (Ord(YangInvested>0)+Ord(YinInvested>0)>1) or
    (Ord(AirInvested>0)+Ord(FireInvested>0)+Ord(WoodInvested>0)+Ord(EarthInvested>0)+Ord(WaterInvested>0)>1) then
    raise EKarosProtocol.Create('Multiple Fletta branches on one axis');
end;

function FlettaStage(Invested:Integer):Integer;
var I:Integer;
begin
  Result:=0;
  for I:=1 to High(B1008FlettaStageThresholds) do
    if Invested>=B1008FlettaStageThresholds[I] then Result:=I;
end;

function TB1008FlettaAttributes.YangStage:Integer;
begin Validate;Result:=FlettaStage(YangInvested);end;

function TB1008FlettaAttributes.FireStage:Integer;
begin Validate;Result:=FlettaStage(FireInvested);end;

function TB1008FlettaAttributes.Selection(Category:Cardinal):Cardinal;
begin
  Validate;Result:=0;
  case Category of
    1:if YangInvested>0 then Result:=1 else if YinInvested>0 then Result:=2;
    2:if AirInvested>0 then Result:=1 else if FireInvested>0 then Result:=2
      else if WoodInvested>0 then Result:=3 else if EarthInvested>0 then Result:=4
      else if WaterInvested>0 then Result:=5;
  else raise EKarosProtocol.Create('Unsupported Fletta category');end;
end;

function TB1008FlettaAttributes.Stage(Category,Attribute:Cardinal):Integer;
begin
  Result:=0;
  if Selection(Category)=Attribute then Result:=FlettaStage(Invested(Category));
end;

function TB1008FlettaAttributes.CanInvest(const Request:TB1008FlettaInvestment):Boolean;
begin
  Result:=False;
  if not Request.Supported then Exit;
  Result:=((Selection(Request.Category)=0) or (Selection(Request.Category)=Request.Attribute)) and
    (Request.Amount<=Cardinal(RemainingCapacity(Request.Category)));
end;

function TB1008FlettaAttributes.Invested(Category:Cardinal):Integer;
begin
  Validate;
  case Category of
    1:Result:=YangInvested+YinInvested;
    2:Result:=AirInvested+FireInvested+WoodInvested+EarthInvested+WaterInvested;
  else raise EKarosProtocol.Create('Unsupported Fletta category');end;
end;

function TB1008FlettaAttributes.RemainingCapacity(Category:Cardinal):Integer;
begin
  Result:=B1008FlettaMaxInvested-Invested(Category);
end;

procedure TB1008FlettaAttributes.AddInvestment(const Request:TB1008FlettaInvestment);
begin
  if not Request.Supported then raise EKarosProtocol.Create('Unsupported investment');
  // Investments are cumulative: one request may cross several stage thresholds.
  // Preserve every point, including the remainder above the last crossed threshold.
  if not CanInvest(Request) then
    raise EKarosProtocol.Create('Investment changes selected branch or exceeds capacity');
  if Request.Category=1 then begin
    if Request.Attribute=1 then Inc(YangInvested,Integer(Request.Amount))
    else Inc(YinInvested,Integer(Request.Amount));
  end else case Request.Attribute of
    1:Inc(AirInvested,Integer(Request.Amount));
    2:Inc(FireInvested,Integer(Request.Amount));
    3:Inc(WoodInvested,Integer(Request.Amount));
    4:Inc(EarthInvested,Integer(Request.Amount));
    5:Inc(WaterInvested,Integer(Request.Amount));
  end;
end;

procedure TB1008FlettaAttributes.PhysicalAttack(var Minimum,Maximum:Integer;BaseAttack:Integer);
var Bonus:Integer;
begin
  Validate;
  if (BaseAttack<0) or (BaseAttack>1000000) or (Minimum<0) or (Maximum<Minimum) or (Maximum>1000000) then
    raise EKarosProtocol.Create('Invalid attack range for Fletta');
  // Authored reconstruction from skillLevel 50022 descriptions: +5% per
  // stage to the shared character attack base, rounded to nearest integer.
  // Client 46B87F/46B8C1 adds unscaled local weapon endpoints to that base;
  // scaling endpoints separately cannot be represented by its stat packet.
  // This retains confirmed stage-1 damage for all supported starter weapons.
  Bonus:=(Int64(BaseAttack)*5*FireStage+50) div 100;
  Inc(Minimum,Bonus);Inc(Maximum,Bonus);
end;

procedure TB1008FlettaAttributes.ApplyAttackParameters(var Packet:TBytes;Base,Minimum,Maximum:Integer);
var Offset,Low,High:Integer;Value:Single;
begin
  if (Length(Packet)=$4B3) and (Packet[0]=2) and (Packet[1]=5) then Offset:=$373
  else if (Length(Packet)=$14A) and (Packet[0]=8) and (Packet[1]=2) then Offset:=10
  else raise EKarosProtocol.Create('Unsupported Fletta attack packet');
  Low:=Minimum;High:=Maximum;PhysicalAttack(Low,High,Base);
  Value:=Base+Low-Minimum;Move(Value,Packet[Offset+$50],4);
end;

function TB1008FlettaAttributes.RegenHP(Base:Integer):Integer;
begin
  Validate;
  if Base<0 then raise EKarosProtocol.Create('Negative HP regeneration');
  // skillLevel 50011 descriptions: HP regeneration x(1 + stage * 0.15).
  // Whole-HP floor is our reconstruction; the original rounding is unverified.
  Result:=Integer(Int64(Base)*(100+15*YangStage) div 100);
end;

function TB1008FlettaAttributes.RegenMP(Base:Integer):Double;
begin
  if Base<0 then raise EKarosProtocol.Create('Negative MP regeneration');
  Result:=Base*(100+15*Stage(1,2))/100.0;
end;

function TB1008FlettaAttributes.MagicAttack(Base:Integer):Integer;
begin
  if (Base<0) or (Base>1000000) then raise EKarosProtocol.Create('Invalid magic attack');
  // User-approved authored balance: +5% of base per stage, like Fire.
  Result:=Base+(Int64(Base)*5*Stage(2,3)+50) div 100;
end;

function TB1008FlettaAttributes.Defense(Base:Integer):Integer;
begin
  if (Base<0) or (Base>1000000) then raise EKarosProtocol.Create('Invalid defense');
  Result:=Base+(Int64(Base)*5*Stage(2,4)+50) div 100;
end;

function TB1008FlettaAttributes.AttackSpeed:Single;
begin Result:=B1008ProbeAttackSpeed*(1+0.02*Stage(2,1));end;

function TB1008FlettaAttributes.MovementMultiplier:Single;
begin Result:=1+0.04*Stage(2,5);end;

procedure TB1008FlettaAttributes.ApplySpeeds(var Packet:TBytes);
var Offset:Integer;Value:Single;
begin
  if (Length(Packet)=$4B3) and (Packet[0]=2) and (Packet[1]=5) then Offset:=$24
  else if (Length(Packet)>=$D4) and (Packet[0]=4) and (Packet[1]=2) and (Packet[7]=0) then Offset:=44
  else if (Packet[0]=8) and (((Length(Packet)=49) and (Packet[1]=0)) or
    ((Length(Packet)=101) and (Packet[1]=1))) then Offset:=27
  else raise EKarosProtocol.Create('Unsupported Fletta speed packet');
  // Gage +16/+20/+24 become charData+628/+62C/+630. Native movement
  // reads the first two; 0x4EC784 uses +630 for normal attack playback.
  Value:=B1008PlayerSpeedA*MovementMultiplier;Move(Value,Packet[Offset],4);
  Value:=B1008PlayerSpeedB*MovementMultiplier;Move(Value,Packet[Offset+4],4);
  Value:=AttackSpeed;Move(Value,Packet[Offset+8],4);
end;

procedure TB1008FlettaAttributes.ApplySecondaryParameters(var Packet:TBytes;
  BaseMagic,BaseDefense,GearDefense:Integer);
var Offset,Total:Integer;Value:Single;
begin
  if (Length(Packet)=$4B3) and (Packet[0]=2) and (Packet[1]=5) then Offset:=$373
  else if (Length(Packet)=$14A) and (Packet[0]=8) and (Packet[1]=2) then Offset:=10
  else raise EKarosProtocol.Create('Unsupported Fletta parameters packet');
  Value:=MagicAttack(BaseMagic);Move(Value,Packet[Offset+$6C],4);
  // Earth scales current base+equipment defense; the same total mitigates hits.
  Total:=Defense(BaseDefense+GearDefense);Value:=Total;Move(Value,Packet[Offset+$5C],4);
  Value:=Total-BaseDefense;Move(Value,Packet[Offset+$94],4);
end;

procedure TB1008FlettaAttributes.ApplyCharacterInfo(var Packet:TBytes);
var Selected,Amount:Integer;
begin
  Validate;
  if Length(Packet)<>$4B3 then raise EKarosProtocol.Create('Invalid Fletta character info');
  if (Packet[0]<>2) or (Packet[1]<>5) then raise EKarosProtocol.Create('Invalid Fletta character info opcode');
  // 02/05 payload+10 -> charData+60E. Handler 0x527F77 uses
  // selections at charData+957 and cumulative investments at +963 (3 axes).
  FillChar(Packet[$353],24,0);
  Selected:=Selection(1);Amount:=Invested(1);
  Move(Selected,Packet[$357],4);Move(Amount,Packet[$363],4);
  Selected:=Selection(2);Amount:=Invested(2);
  Move(Selected,Packet[$35B],4);Move(Amount,Packet[$367],4);
  ApplySpeeds(Packet);
end;

procedure TB1008FlettaAttributes.ApplyRegeneration(var Packet:TBytes;BaseHP,BaseMP:Integer);
var Offset:Integer;Value:Single;
begin
  if (Length(Packet)=$4B3) and (Packet[0]=2) and (Packet[1]=5) then Offset:=$393
  else if (Length(Packet)=$14A) and (Packet[0]=8) and (Packet[1]=2) then Offset:=42
  else raise EKarosProtocol.Create('Unsupported Fletta regeneration packet');
  Value:=RegenHP(BaseHP);Move(Value,Packet[Offset],4);
  if BaseMP>=0 then begin Value:=RegenMP(BaseMP);Move(Value,Packet[Offset+12],4);end;
end;

procedure TB1008Fletta.Validate;
begin
  if (Total<0) or (Total>B1008FlettaMaxTotal) then
    raise EKarosProtocol.Create('Fletta outside signed client counter range');
end;
function TB1008Fletta.Points: Integer;
begin Validate;Result:=Total div B1008FlettaThreshold;end;
function TB1008Fletta.Progress: Integer;
begin Validate;Result:=Total mod B1008FlettaThreshold;end;
procedure TB1008Fletta.Add(Amount: Integer);
begin
  Validate;
  if Amount<0 then
    raise EKarosProtocol.Create('Invalid Fletta gain');
  if Amount>B1008FlettaMaxTotal-Total then Total:=B1008FlettaMaxTotal
  else Inc(Total,Amount);
end;
class function TB1008Fletta.LevelCapacity(PlayerLevel:Integer;Rate:Integer):Int64;
var Minimum:Integer;
begin
  if (PlayerLevel<1) or (Rate<0) or (Rate>2000) then raise EKarosProtocol.Create('Invalid level/rate for Fletta capacity');
  Minimum:=(Rate+99) div 100;
  if PlayerLevel<Minimum then PlayerLevel:=Minimum;
  Result:=Int64(PlayerLevel)*B1008FlettaThreshold;
end;

procedure TB1008Fletta.CreditKill(Amount,Rate,PlayerLevel:Integer;var RateRemainder:Integer);
var Capacity:Int64;Charge,Reward:Integer;
begin
  Validate;Capacity:=LevelCapacity(PlayerLevel,Rate);
  if (Amount<0) or (Amount>B1008FlettaThreshold) or (RateRemainder<0) or (RateRemainder>99) then
    raise EKarosProtocol.Create('Invalid Fletta charge or rate remainder');
  if Total>=Capacity then begin Total:=Capacity;RateRemainder:=0;Exit;end;
  if Rate=0 then Exit;
  // Rate multiplies completed bars, not charging speed. Preserve fractional
  // rates across completions (x1.5 awards 1 then 2), separately from the bar.
  Charge:=Progress+Amount;
  Reward:=RateRemainder+(Charge div B1008FlettaThreshold)*Rate;
  Total:=Int64(Points+Reward div 100)*B1008FlettaThreshold+Charge mod B1008FlettaThreshold;
  RateRemainder:=Reward mod 100;
  if Total>=Capacity then begin Total:=Capacity;RateRemainder:=0;end;
end;

class function TB1008Fletta.KillGain(PlayerLevel,MobLevel: Integer): Integer;
const D:array[0..4] of Integer=(0,2,5,8,10);
  G:array[0..4] of Integer=(1150,950,650,350,150);
var Delta,I:Integer;
begin
  if (PlayerLevel<1) or (MobLevel<1) then
    raise EKarosProtocol.Create('Invalid level for Fletta');
  Delta:=PlayerLevel-MobLevel;
  if Delta<=0 then Exit(G[0]);
  if Delta>=10 then Exit(G[4]);
  // Authored midpoint/interpolation of user memory, not client constants.
  for I:=1 to High(D) do
    if Delta<=D[I] then
      Exit(G[I-1]+(G[I]-G[I-1])*(Delta-D[I-1]) div (D[I]-D[I-1]));
  raise EKarosProtocol.Create('Unmapped Fletta interval');
end;
procedure TB1008Fletta.Apply(var Packet:TBytes;PlayerLevel:Integer;Rate:Integer);
var Offset,P,FP,Threshold:Integer;
begin
  Validate;
  if (Length(Packet)=$4B3) and (Packet[0]=2) and (Packet[1]=5) then Offset:=$3A
  else if (Length(Packet)=101) and (Packet[0]=8) and (Packet[1]=1) then Offset:=$31
  else raise EKarosProtocol.Create('Unsupported Fletta packet');
  // HUD 0x46242A..0x4624CF reads charData+63E/642/646:
  // LE32 progress, positive threshold, unspent FP. 02/05 +10 -> +60E;
  // 08/01 +11 -> +618. Ordinary 08/00 stops BEFORE these fields.
  P:=Progress;FP:=Points;Threshold:=B1008FlettaThreshold;
  // Full capacity shows 100%, while the saved fractional balance stays zero.
  // Do not turn the display's full bar into another spendable Fletta point.
  if Total>=LevelCapacity(PlayerLevel,Rate) then P:=Threshold;
  Move(P,Packet[Offset],4);Move(Threshold,Packet[Offset+4],4);
  Move(FP,Packet[Offset+8],4);
end;

end.
