unit Emulator.Profession.B1008;

interface

uses System.SysUtils;

const
  B1008ClassSuccess=$81;
  B1008ClassWrongSource=$82;
  B1008ClassInsufficientCarat=$83;
  B1008ClassInsufficientLevel=$84;
  B1008ClassMissingCertificate=$85;
  B1008ClassOtherFailure=$86;
  B1008ClassPromotionLevel=10;
  B1008ClassPromotionCarat=10000;
  B1008ClassPromotionCertificate=63007;
  B1008ClassRankPromotionLevel=25;
  B1008ClassRankPromotionCarat=100000;

type
  TB1008ClassState=record
    BaseClass,ClassID:Word;
    Rank:Byte;
  end;
  TB1008ClassChange=record
    Timestamp,CharacterID,TargetClass,TargetRank:Cardinal;
    Code:Word;
    class function Parse(const Payload:TBytes):TB1008ClassChange;static;
    function Ack(ResultCode:Word):TBytes;
    function Supported:Boolean;
  end;
  TB1008ClassWire=class
  public
    class function BaseClass(ClassID:Word):Word;static;
    class function CanPromote(CurrentClass,TargetClass:Word):Boolean;static;
    class function ChangeRule(const State:TB1008ClassState;const Request:TB1008ClassChange;
      out Level:Word;out Carat,Certificate:Cardinal):Boolean;static;
    class procedure ApplyPreview(var Payload:TBytes;const State:TB1008ClassState);static;
    class procedure ApplyCharacterInfo(var Payload:TBytes;const State:TB1008ClassState);static;
    class procedure ApplyAppearance(var Payload:TBytes;const State:TB1008ClassState);static;
  end;

implementation

uses Emulator.Protocol.B1008;

procedure PutBE32(var Payload:TBytes;Offset:Integer;Value:Cardinal);
begin
  Payload[Offset]:=Byte(Value shr 24);
  Payload[Offset+1]:=Byte((Value shr 16) and $FF);
  Payload[Offset+2]:=Byte((Value shr 8) and $FF);
  Payload[Offset+3]:=Byte(Value and $FF);
end;

class function TB1008ClassChange.Parse(const Payload:TBytes):TB1008ClassChange;
begin
  if Length(Payload)<>20 then raise EKarosProtocol.Create('Invalid class change size');
  if (Payload[0]<>8) or (Payload[1]<>3) then
    raise EKarosProtocol.Create('Not a class change packet');
  // CCharInfoClassChangePacket: 4A500D..4A5068 / parser 529416.
  Result.Timestamp:=TB1008Wire.ReadBE32(Payload,2);
  Result.CharacterID:=TB1008Wire.ReadBE32(Payload,6);
  Result.TargetClass:=TB1008Wire.ReadBE32(Payload,10);
  Result.TargetRank:=TB1008Wire.ReadBE32(Payload,14);
  Result.Code:=TB1008Wire.ReadBE16(Payload,18);
end;

function TB1008ClassChange.Ack(ResultCode:Word):TBytes;
begin
  if (ResultCode<B1008ClassSuccess) or (ResultCode>B1008ClassOtherFailure) then
    raise EKarosProtocol.Create('Unknown class change result');
  Result:=nil;SetLength(Result,20);Result[0]:=8;Result[1]:=3;
  PutBE32(Result,2,Timestamp);PutBE32(Result,6,CharacterID);
  PutBE32(Result,10,TargetClass);PutBE32(Result,14,TargetRank);
  Result[18]:=Byte(ResultCode shr 8);Result[19]:=Byte(ResultCode and $FF);
end;

function TB1008ClassChange.Supported:Boolean;
begin
  // Check the full DWORDs before callers narrow the class/rank for storage.
  Result:=(CharacterID=1) and (TargetRank<=1) and (Code=B1008ClassSuccess) and
    ((TargetClass=110) or (TargetClass=120) or (TargetClass=310) or
      (TargetClass=320) or (TargetClass=510) or (TargetClass=520));
end;

class function TB1008ClassWire.BaseClass(ClassID:Word):Word;
begin
  // Only the enabled base/first-profession IDs have a confirmed family here.
  // Arithmetic rounding would silently admit unimplemented later professions.
  case ClassID of
    100,110,120:Result:=100;
    300,310,320:Result:=300;
    500,510,520:Result:=500;
  else Result:=ClassID;end;
end;

class function TB1008ClassWire.CanPromote(CurrentClass,TargetClass:Word):Boolean;
begin
  // First profession rules use level 10, 10000 Carat and certificate 63007.
  // Payment, level and authoritative state checks belong to the store.
  case CurrentClass of
    100:Result:=(TargetClass=110) or (TargetClass=120);
    300:Result:=(TargetClass=310) or (TargetClass=320);
    500:Result:=(TargetClass=510) or (TargetClass=520);
  else Result:=False;end;
end;

class function TB1008ClassWire.ChangeRule(const State:TB1008ClassState;
  const Request:TB1008ClassChange;out Level:Word;out Carat,Certificate:Cardinal):Boolean;
begin
  Result:=False;Level:=0;Carat:=0;Certificate:=0;
  if not Request.Supported or (State.Rank<>0) then Exit;
  if (Request.TargetRank=0) and CanPromote(State.ClassID,Word(Request.TargetClass)) then begin
    Level:=B1008ClassPromotionLevel;Carat:=B1008ClassPromotionCarat;
    Certificate:=B1008ClassPromotionCertificate;Result:=True;
  end else if (Request.TargetRank=1) and (Request.TargetClass=State.ClassID) then begin
    // Confirmed same-profession 0 -> 1 rows: level 25, 100000 Carat, no item.
    Level:=B1008ClassRankPromotionLevel;Carat:=B1008ClassRankPromotionCarat;Result:=True;
  end;
end;

procedure ApplyClass(var Payload:TBytes;Offset:Integer;const State:TB1008ClassState);
begin
  Payload[Offset]:=Byte(State.ClassID and $FF);
  Payload[Offset+1]:=Byte(State.ClassID shr 8);
  Payload[Offset+2]:=State.Rank;
end;

class procedure TB1008ClassWire.ApplyPreview(var Payload:TBytes;const State:TB1008ClassState);
begin
  if (Length(Payload)<$152) or (Payload[0]<>2) or (Payload[1]<>1) then
    raise EKarosProtocol.Create('Class requires a character preview');
  ApplyClass(Payload,15,State);
end;

class procedure TB1008ClassWire.ApplyCharacterInfo(var Payload:TBytes;const State:TB1008ClassState);
begin
  if (Length(Payload)<>$4B3) or (Payload[0]<>2) or (Payload[1]<>5) then
    raise EKarosProtocol.Create('Class requires initial CharInfo');
  // 02/05+10 is copied to charData+60E; rank is the following byte.
  ApplyClass(Payload,10,State);
end;

class procedure TB1008ClassWire.ApplyAppearance(var Payload:TBytes;const State:TB1008ClassState);
begin
  if (Length(Payload)<$D4) or (Payload[0]<>4) or (Payload[1]<>2) or
    (Payload[7]<>0) then raise EKarosProtocol.Create('Class requires self appearance');
  ApplyClass(Payload,$C8,State);
end;

end.
