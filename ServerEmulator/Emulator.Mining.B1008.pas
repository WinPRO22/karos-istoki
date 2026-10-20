unit Emulator.Mining.B1008;

interface

uses System.SysUtils;

const
  B1008MiningQuestID = 19003016;
  B1008MiningOreID = 70079;
  B1008MiningActionID = 900;
  B1008MiningMapID = 19003;
  B1008MiningNodeX:Single = 6126.90283203125;
  B1008MiningNodeZ:Single = 8807.5986328125;
  B1008MiningNodeY:Single = 541.9629516601562;
  // Authored quest-only admission policy, not recovered original frequency/reach.
  B1008MiningMinimumCycleMS = 1000;
  B1008MiningPlanarRange:Single = 100;
  B1008MiningVerticalRange:Single = 50;

type
  TB1008MiningRequest=record
    Timestamp,MapID,Parameter,ToolParameter:Cardinal;
    class function Parse(const P:TBytes):TB1008MiningRequest;static;
  end;
  TB1008Mining=class
  public
    class function Parse(const P:TBytes):TB1008MiningRequest;static;
    class function BuildResult(Timestamp,CharacterID:Cardinal;Code:Byte;
      const IDs:array of Cardinal):TBytes;static;
    class function Near(MapID:Cardinal;X,Z,Y:Single):Boolean;static;
    class function IsPick(ItemID:Cardinal):Boolean;static;
  end;

implementation

uses System.Math,Emulator.Protocol.B1008;

procedure MiningBE(var P:TBytes;Offset:Integer;Value:Cardinal);
begin
  P[Offset]:=Byte(Value shr 24);P[Offset+1]:=Byte((Value shr 16) and 255);
  P[Offset+2]:=Byte((Value shr 8) and 255);P[Offset+3]:=Byte(Value and 255);
end;

class function TB1008MiningRequest.Parse(const P:TBytes):TB1008MiningRequest;
begin
  Result:=Default(TB1008MiningRequest);
  if Length(P)<>18 then raise EKarosProtocol.Create('Invalid mining request size');
  if (P[0]<>$0A) or (P[1]<>2) then raise EKarosProtocol.Create('Not mining completion');
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2);
  Result.MapID:=TB1008Wire.ReadBE32(P,6);
  Result.Parameter:=TB1008Wire.ReadBE32(P,10);
  Result.ToolParameter:=TB1008Wire.ReadBE32(P,14);
end;

class function TB1008Mining.Parse(const P:TBytes):TB1008MiningRequest;
begin
  Result:=TB1008MiningRequest.Parse(P);
end;

class function TB1008Mining.BuildResult(Timestamp,CharacterID:Cardinal;Code:Byte;
  const IDs:array of Cardinal):TBytes;
var I,Offset:Integer;ID:Cardinal;
begin
  Result:=nil;
  if not (Code in [$5F,$60,$61,$0B]) then raise EKarosProtocol.Create('Invalid mining result code');
  if Length(IDs)>High(Word) then raise EKarosProtocol.Create('Too many mining result items');
  if (Code<>$5F) and (Length(IDs)<>0) then raise EKarosProtocol.Create('Failed mining result has items');
  for ID in IDs do if ID=0 then raise EKarosProtocol.Create('Invalid mining result item');
  SetLength(Result,13+4*Length(IDs));Result[0]:=$0A;Result[1]:=5;
  MiningBE(Result,2,Timestamp);MiningBE(Result,6,CharacterID);Result[10]:=Code;
  Result[11]:=Byte(Length(IDs) shr 8);Result[12]:=Byte(Length(IDs) and 255);
  // Native collection handler 52C4A9 reads raw little-endian IDs.
  for I:=0 to High(IDs) do begin
    ID:=IDs[I];Offset:=13+4*I;
    Result[Offset]:=Byte(ID and 255);Result[Offset+1]:=Byte((ID shr 8) and 255);
    Result[Offset+2]:=Byte((ID shr 16) and 255);Result[Offset+3]:=Byte(ID shr 24);
  end;
end;

class function TB1008Mining.Near(MapID:Cardinal;X,Z,Y:Single):Boolean;
var DX,DZ:Double;
begin
  Result:=False;
  if MapID<>B1008MiningMapID then Exit;
  if IsNan(X) or IsInfinite(X) or IsNan(Z) or IsInfinite(Z) or
    IsNan(Y) or IsInfinite(Y) then Exit;
  if Abs(Double(Y)-B1008MiningNodeY)>B1008MiningVerticalRange then Exit;
  DX:=Double(X)-B1008MiningNodeX;DZ:=Double(Z)-B1008MiningNodeZ;
  Result:=DX*DX+DZ*DZ<=Sqr(Double(B1008MiningPlanarRange));
end;

class function TB1008Mining.IsPick(ItemID:Cardinal):Boolean;
begin
  Result:=(ItemID=30001) or (ItemID=30002);
end;

end.
