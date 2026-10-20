unit Emulator.Return.B1008;

interface

uses System.SysUtils,Emulator.WorldState.B1008;

const
  B1008ReturningStoneID=57104;
  B1008BerneoReturnPoint=190033;
  B1008ReturnCooldownMS=600000; // Authored ten-minute cooldown; local itemAttr agrees.

type
  TB1008ReturnSave=record
    Timestamp,NpcHandle,Slot,Destination:Cardinal;
    Code:Byte;
    class function Parse(const P:TBytes):TB1008ReturnSave;static;
    function Reply(Success:Boolean):TBytes;
  end;
  TB1008ReturnState=record
    Point:Cardinal;
    UntilMS:Int64;
    Pending:Boolean;
  end;
  TB1008ReturnWire=class
  public
    class function Position:TB1008Position;static;
    class procedure ApplyInfo(var P:TBytes;Point:Cardinal);static;
    class function Cooldown(Timestamp,RemainingSeconds:Cardinal):TBytes;static;
  end;

implementation

uses Emulator.Protocol.B1008;

procedure ReturnBE(var P:TBytes;O:Integer;V:Cardinal);
begin P[O]:=Byte(V shr 24);P[O+1]:=Byte((V shr 16) and 255);P[O+2]:=Byte((V shr 8) and 255);P[O+3]:=Byte(V and 255);end;

class function TB1008ReturnSave.Parse(const P:TBytes):TB1008ReturnSave;
begin
  if Length(P)<>19 then raise EKarosProtocol.Create('Invalid return binding size');
  if (P[0]<>6) or (P[1]<>$23) then raise EKarosProtocol.Create('Not return binding');
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2);Result.NpcHandle:=TB1008Wire.ReadBE32(P,6);
  Result.Slot:=TB1008Wire.ReadBE32(P,10);Result.Code:=P[14];Result.Destination:=TB1008Wire.ReadBE32(P,15);
end;

function TB1008ReturnSave.Reply(Success:Boolean):TBytes;
begin
  // 474753 sends the NPC HANDLE, not the hero ID, in this packet's first field.
  Result:=nil;SetLength(Result,19);Result[0]:=6;Result[1]:=$23;
  ReturnBE(Result,2,Timestamp);ReturnBE(Result,6,NpcHandle);ReturnBE(Result,10,Slot);
  if Success then begin Result[14]:=$5C;ReturnBE(Result,15,B1008BerneoReturnPoint);end
  else Result[14]:=$5D;
end;

class function TB1008ReturnWire.Position:TB1008Position;
begin
  // Reuse the already player-tested clearance south of Remember Stone 99001.
  // This is server placement policy, not mapWarpTargetPos's random landing area.
  Result.X:=7470.669922;Result.Z:=9023.019531;Result.Y:=692.872986;Result.Heading:=0;
end;

class procedure TB1008ReturnWire.ApplyInfo(var P:TBytes;Point:Cardinal);
var N:Cardinal;
begin
  if (Length(P)<>$4B3) or (P[0]<>2) or (P[1]<>5) or
    ((Point<>0) and (Point<>B1008BerneoReturnPoint)) then raise EKarosProtocol.Create('Invalid return info');
  // 52541C copies +14B to hero+74F; +2C counts unlocked slots, +30 is default.
  N:=1;Move(N,P[$177],4);Move(Point,P[$17B],4);
end;

class function TB1008ReturnWire.Cooldown(Timestamp,RemainingSeconds:Cardinal):TBytes;
var ID:Cardinal;
begin
  if RemainingSeconds>B1008ReturnCooldownMS div 1000 then raise EKarosProtocol.Create('Invalid stone cooldown');
  // 526CB9: no character ID, BE16 count, packed LE (item ID, seconds remaining).
  Result:=nil;SetLength(Result,16);Result[0]:=6;Result[1]:=$2B;
  ReturnBE(Result,2,Timestamp);Result[7]:=1;ID:=B1008ReturningStoneID;
  Move(ID,Result[8],4);Move(RemainingSeconds,Result[12],4);
end;

end.
