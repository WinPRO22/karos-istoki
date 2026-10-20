unit Emulator.Progression.B1008;

interface

uses System.SysUtils;

type
  TB1008Progress = record
    TotalEXP: Int64;
    function Level: Word;
    function CurrentEXP: Int64;
    function NextEXP: Int64;
    procedure Validate;
  end;
  TB1008ProgressWire = class
  public
    class procedure ApplyPreview(var Packet: TBytes; const Progress: TB1008Progress); static;
    class procedure ApplyCharacterInfo(var Packet: TBytes; const Progress: TB1008Progress); static;
    class procedure ApplyAppearance(var Packet: TBytes; const Progress: TB1008Progress); static;
    class procedure ApplyVitals(var Packet: TBytes; HP,MP,MaxHP,MaxMP: Integer); static;
    class procedure ApplyBaseAttributes(var Packet: TBytes; ClassID: Word; Level:Word=1); static;
    class procedure ApplyCombatParameters(var Packet: TBytes; ClassID,Level: Word); static;
    class procedure ApplySkillPoints(var Packet:TBytes;Points:Cardinal);static;
    class function BuildParameters(Timestamp:Cardinal; ClassID,Level:Word):TBytes; static;
    class function BuildHeroGage(Timestamp: Cardinal; HP,MP: Integer;
      const Progress: TB1008Progress; MaxHP: Integer = 5000; MaxMP: Integer = 150): TBytes; static;
  end;

implementation

uses Emulator.Protocol.B1008, Emulator.Combat.B1008, Emulator.Balance.B1008;

class procedure TB1008ProgressWire.ApplySkillPoints(var Packet:TBytes;Points:Cardinal);
var Offset:Integer;
begin
  // 0x47DB0F/0x47DBF1 compares uint32 charData+618+4A against
  // skillLevel+8 (SP cost). This is separate from FP at +646.
  if Points>1000+TB1008Balance.LevelCap-1 then raise EKarosProtocol.Create('SP outside level/grant bounds');
  if (Length(Packet)=$4B3) and (Packet[0]=2) and (Packet[1]=5) then Offset:=$5E
  else if (Length(Packet)=101) and (Packet[0]=8) and (Packet[1]=1) then Offset:=$55
  else raise EKarosProtocol.Create('SP requires CharInfo or full player gage');
  Move(Points,Packet[Offset],4);
end;

class procedure TB1008ProgressWire.ApplyBaseAttributes(var Packet:TBytes; ClassID:Word;Level:Word);
var A:TB1008BaseAttributes; Critical:Single;
begin
  if (Length(Packet)<>$4B3) or (Packet[0]<>2) or (Packet[1]<>5) then
    raise EKarosProtocol.Create('Base attributes need initial CharInfo');
  A:=TB1008Balance.BaseAttributes(ClassID,Level);
  // b1008 0x52541C: 02/05+$373 -> charData+$4CE, 320 bytes.
  // 0x46B45F reads WORD +2/+6/+A/+4/+8; labels 21125..21129
  // from string.lod_eng confirm STR/VIT/Mentality/DEX/INT order.
  Move(A.Strength,Packet[$375],2);Move(A.Dexterity,Packet[$377],2);
  Move(A.Vitality,Packet[$379],2);Move(A.Intelligence,Packet[$37B],2);
  Move(A.Mentality,Packet[$37D],2);
  // 0x46B9FF: float +A0, label 21143 Critical Chance. This older UI
  // truncates the percentage to an integer. Combat uses the full basis points.
  Critical:=A.CriticalBasisPoints/100;
  Move(Critical,Packet[$413],4);
end;

class procedure TB1008ProgressWire.ApplyCombatParameters(var Packet:TBytes;ClassID,Level:Word);
var A:TB1008BaseAttributes;HP,MP:Integer;
  procedure Put(Offset:Integer;Value:Single);
  begin Move(Value,Packet[$373+Offset],4);end;
begin
  if (Length(Packet)<>$4B3) or (Packet[0]<>2) or (Packet[1]<>5) then
    raise EKarosProtocol.Create('Combat parameters need initial CharInfo');
  A:=TB1008Balance.BaseAttributes(ClassID,Level);
  HP:=TB1008Balance.ClassMaxHP(ClassID,Level);MP:=TB1008Balance.ClassMaxMP(ClassID,Level);
  // 0x46B621..0x46BA26 with string IDs 21130..21143 from 0x670F00.
  // Physical/magical attack is the common base for min/max. The client
  // adds the equipped weapon range itself; no invented equipment bonus.
  Put($B0,HP);Put($28,MP);Put($20,A.RegenHP);Put($2C,A.RegenMP);
  // 02/05 +373+34 -> charData+502; 0x5254EB also caches this in
  // player+4F8 for auto-approach (0x4FD3D6). Zero forced the hero
  // to close to the NPC's body radius before an ordinary strike.
  // Keep it in 08/02 too, so gear/Fletta/level updates cannot erase it.
  Put($34,B1008PlayerMeleeReach);
  Put($38,A.Evasion);Put($3C,A.BlockRate);
  Put($50,A.PhysicalAttack);Put($5C,A.PhysicalDefense);
  Put($6C,A.MagicalAttack);Put($74,A.MagicalDefense);
end;

class function TB1008ProgressWire.BuildParameters(Timestamp:Cardinal;ClassID,Level:Word):TBytes;
var Info:TBytes;
begin
  SetLength(Info,$4B3);Info[0]:=2;Info[1]:=5;
  ApplyBaseAttributes(Info,ClassID,Level);ApplyCombatParameters(Info,ClassID,Level);
  // 08/02: dispatch 0x520740, slot +1B0 -> 0x615DF0 -> vtable+78
  // -> 0x52BF57. Parser 0x5293FA requires 330 bytes; handler copies
  // +10,320 bytes to charData+4CE without changing level or playing FX.
  Result:=nil;SetLength(Result,$14A);Result[0]:=8;Result[1]:=2;
  Result[2]:=Byte(Timestamp shr 24);Result[3]:=Byte((Timestamp shr 16) and $FF);
  Result[4]:=Byte((Timestamp shr 8) and $FF);Result[5]:=Byte(Timestamp and $FF);
  Result[9]:=1;Move(Info[$373],Result[10],$140);
end;

class procedure TB1008ProgressWire.ApplyVitals(var Packet: TBytes; HP,MP,MaxHP,MaxMP: Integer);
var Offset: Integer;
begin
  if Length(Packet)<2 then raise EKarosProtocol.Create('Truncated player vitals packet');
  if (HP<0) or (MP<0) or (MaxHP<=0) or (MaxMP<0) or (HP>MaxHP) or (MP>MaxMP) then
    raise EKarosProtocol.Create('Invalid player vitals');
  if (Length(Packet)=$4B3) and (Packet[0]=2) and (Packet[1]=5) then Offset:=$14
  else if (Length(Packet)>=$D4) and (Packet[0]=4) and (Packet[1]=2) and (Packet[7]=0) then Offset:=28
  else if (Packet[0]=8) and (((Length(Packet)=101) and (Packet[1]=1)) or
    ((Length(Packet)=49) and (Packet[1]=0))) then Offset:=11
  else raise EKarosProtocol.Create('Unsupported player vitals packet');
  Move(HP,Packet[Offset],4);Move(MaxHP,Packet[Offset+4],4);
  Move(MP,Packet[Offset+8],4);Move(MaxMP,Packet[Offset+12],4);
end;

procedure TB1008Progress.Validate;
begin
  if (TotalEXP<0) or (TotalEXP>TB1008Balance.MaxEXP) then
    raise EKarosProtocol.Create('EXP outside the configured balance phase');
end;

function TB1008Progress.Level: Word;
var Remaining: Int64;
begin
  Validate; Result:=1; Remaining:=TotalEXP;
  while (Result<TB1008Balance.LevelCap) and (Remaining>=TB1008Balance.Threshold(Result)) do begin
    Dec(Remaining,TB1008Balance.Threshold(Result)); Inc(Result);
  end;
end;

function TB1008Progress.CurrentEXP: Int64;
var I,L: Word;
begin
  L:=Level; Result:=TotalEXP;
  for I:=1 to L-1 do Dec(Result,TB1008Balance.Threshold(I));
end;

function TB1008Progress.NextEXP: Int64;
begin Result:=TB1008Balance.Threshold(Level); end;

class procedure TB1008ProgressWire.ApplyPreview(var Packet: TBytes;
  const Progress: TB1008Progress);
var L: Word;
begin
  if (Length(Packet)<$152) or (Packet[0]<>2) or (Packet[1]<>1) then
    raise EKarosProtocol.Create('EXP needs a character preview');
  L:=Progress.Level; Move(L,Packet[15+$26],2);
end;

class procedure TB1008ProgressWire.ApplyCharacterInfo(var Packet: TBytes;
  const Progress: TB1008Progress);
var L: Word; XP,Next: Int64;
begin
  if (Length(Packet)<>$4B3) or (Packet[0]<>2) or (Packet[1]<>5) then
    raise EKarosProtocol.Create('EXP needs initial CharInfo');
  L:=Progress.Level; XP:=Progress.CurrentEXP; Next:=Progress.NextEXP;
  // 02/05 +10 -> characterData+60E. HUD 0x46400B/0x46402B reads
  // signed LE64 EXP at +64A and threshold at +652, independently of FP.
  Move(L,Packet[$30],2); Move(XP,Packet[$46],8); Move(Next,Packet[$4E],8);
end;

class procedure TB1008ProgressWire.ApplyAppearance(var Packet: TBytes;
  const Progress: TB1008Progress);
var L: Word;
begin
  if (Length(Packet)<$D4) or (Packet[0]<>4) or (Packet[1]<>2) or
    (Packet[7]<>0) then raise EKarosProtocol.Create('EXP needs self appearance');
  L:=Progress.Level; Move(L,Packet[56],2);
end;

class function TB1008ProgressWire.BuildHeroGage(Timestamp: Cardinal; HP,MP: Integer;
  const Progress: TB1008Progress; MaxHP,MaxMP:Integer): TBytes;
var XP,Next: Int64;
begin
  // Parser 0x5293D6 requires 101 bytes, 08/01. Handler 0x52B800 copies
  // 90 bytes at +11 to characterData+618, derives gained EXP and triggers
  // the original level-up effect only when the level word changes.
  // Reuse all current combat gage fields; do not heal or change speeds.
  Result:=TB1008CombatWire.BuildPlayerGageProbe(Timestamp,HP,MP,Progress.Level,MaxHP,MaxMP);
  SetLength(Result,101); Result[1]:=1;
  XP:=Progress.CurrentEXP; Next:=Progress.NextEXP;
  Move(XP,Result[$3D],8); Move(Next,Result[$45],8);
  // FP/attributes remain their existing neutral values for this milestone.
end;

end.
