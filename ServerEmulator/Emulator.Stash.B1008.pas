unit Emulator.Stash.B1008;

interface

uses System.SysUtils,Emulator.Loot.B1008;

const B1008StashSlots=32; // 511CF7: four rows of eight, then three paid rows.

type
  TB1008StashRequest=record
    Kind,Code:Byte;
    Timestamp,CharacterID,NpcHandle,Page,Slot,ItemID,TargetPage,TargetSlot,TargetID:Cardinal;
    Amount,TargetAmount:Int64;
    class function Parse(const P:TBytes):TB1008StashRequest;static;
    function Reply(Success:Boolean;NewAmount:Cardinal=0):TBytes;
  end;
  TB1008StashWire=class
  public
    class function List(const Request:TB1008StashRequest;const Items:TArray<TB1008BagItem>):TBytes;static;
    class function Capacity(Timestamp,CharacterID:Cardinal):TBytes;static;
  end;

implementation

uses Emulator.Protocol.B1008;

procedure StashBE(var P:TBytes;O:Integer;V:Cardinal);
begin P[O]:=Byte(V shr 24);P[O+1]:=Byte((V shr 16) and 255);P[O+2]:=Byte((V shr 8) and 255);P[O+3]:=Byte(V and 255);end;

procedure Stash64(var P:TBytes;O:Integer;V:Int64);
var U:UInt64;
begin Move(V,U,8);StashBE(P,O,Cardinal(U shr 32));StashBE(P,O+4,Cardinal(U and $FFFFFFFF));end;

function StashRead64(const P:TBytes;O:Integer):Int64;
var U:UInt64;
begin U:=(UInt64(TB1008Wire.ReadBE32(P,O)) shl 32) or TB1008Wire.ReadBE32(P,O+4);Move(U,Result,8);end;

class function TB1008StashRequest.Parse(const P:TBytes):TB1008StashRequest;
var N:Integer;
begin
  Result:=Default(TB1008StashRequest);
  if Length(P)<2 then raise EKarosProtocol.Create('Short stash header');
  if P[0]<>6 then raise EKarosProtocol.Create('Not stash family');
  case P[1] of $1A:N:=39;$1B,$1C:N:=27;$28:N:=51;
    else raise EKarosProtocol.Create('Unsupported stash command');end;
  if Length(P)<>N then raise EKarosProtocol.Create('Invalid stash size');
  Result.Kind:=P[1];Result.Code:=P[N-1];
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2);Result.CharacterID:=TB1008Wire.ReadBE32(P,6);
  if Result.Kind=$28 then begin
    Result.Page:=TB1008Wire.ReadBE32(P,10);Result.Slot:=TB1008Wire.ReadBE32(P,14);
    Result.ItemID:=TB1008Wire.ReadBE32(P,18);Result.Amount:=StashRead64(P,22);
    Result.TargetPage:=TB1008Wire.ReadBE32(P,30);Result.TargetSlot:=TB1008Wire.ReadBE32(P,34);
    Result.TargetID:=TB1008Wire.ReadBE32(P,38);Result.TargetAmount:=StashRead64(P,42);
  end else begin
    Result.NpcHandle:=TB1008Wire.ReadBE32(P,10);
    if Result.Kind=$1A then begin
      Result.Page:=TB1008Wire.ReadBE32(P,14);Result.Slot:=TB1008Wire.ReadBE32(P,18);
      Result.ItemID:=TB1008Wire.ReadBE32(P,22);Result.Amount:=StashRead64(P,26);
      Result.TargetSlot:=TB1008Wire.ReadBE32(P,34);
    end else if Result.Kind=$1B then begin
      Result.Slot:=TB1008Wire.ReadBE32(P,14);Result.Amount:=StashRead64(P,18);
    end else begin
      Result.Page:=TB1008Wire.ReadBE32(P,14);Result.Slot:=TB1008Wire.ReadBE32(P,18);
      Result.Amount:=TB1008Wire.ReadBE32(P,22);
    end;
  end;
end;

function TB1008StashRequest.Reply(Success:Boolean;NewAmount:Cardinal):TBytes;
var N:Integer;
begin
  case Kind of $1A:N:=39;$1B,$1C:N:=27;$28:N:=51;
    else raise EKarosProtocol.Create('Invalid stash reply');end;
  Result:=nil;SetLength(Result,N);Result[0]:=6;Result[1]:=Kind;
  StashBE(Result,2,Timestamp);StashBE(Result,6,CharacterID);
  Result[N-1]:=$92;
  if Success then begin if Kind=$28 then Result[N-1]:=$93 else Result[N-1]:=$91;end;
  if Kind=$28 then begin
    StashBE(Result,10,Page);StashBE(Result,14,Slot);StashBE(Result,18,ItemID);Stash64(Result,22,Amount);
    StashBE(Result,30,TargetPage);StashBE(Result,34,TargetSlot);StashBE(Result,38,TargetID);Stash64(Result,42,TargetAmount);
  end else begin
    StashBE(Result,10,NpcHandle);
    if Kind=$1A then begin
      StashBE(Result,14,Page);StashBE(Result,18,Slot);StashBE(Result,22,ItemID);
      Stash64(Result,26,NewAmount);StashBE(Result,34,TargetSlot);
    end else if Kind=$1B then begin
      StashBE(Result,14,Slot);
      // 511E2F subtracts the withdrawn count; -1 clears the whole cell.
      // Unlike deposit, this is NOT the new amount remaining in storage.
      if Success then Stash64(Result,18,Amount);
    end;
  end;
end;

class function TB1008StashWire.List(const Request:TB1008StashRequest;const Items:TArray<TB1008BagItem>):TBytes;
var A:TB1008BagItem;O:Integer;V:Word;Count:UInt64;
begin
  if (Request.Kind<>$1C) or (Length(Items)>B1008StashSlots) then raise EKarosProtocol.Create('Invalid stash list');
  Result:=Request.Reply(True);StashBE(Result,22,Length(Items));
  // 525A8C/511CF7: 35-byte packed LE records, unlike the 36-byte bag records.
  for A in Items do begin
    if (A.Slot>=B1008StashSlots) or (A.Amount=0) then raise EKarosProtocol.Create('Invalid stash record');
    O:=Length(Result);SetLength(Result,O+35);Move(A.ItemID,Result[O],4);
    V:=A.Slot;Move(V,Result[O+4],2);Count:=A.Amount;Move(Count,Result[O+15],8);
    A.Properties.WriteStash(Result,O);
  end;
end;

class function TB1008StashWire.Capacity(Timestamp,CharacterID:Cardinal):TBytes;
var V:Cardinal;
begin
  // 529199 -> 50B37D: personal storage kind=1, paid extension level=0.
  Result:=nil;SetLength(Result,24);Result[0]:=6;Result[1]:=$2A;
  StashBE(Result,2,Timestamp);StashBE(Result,6,CharacterID);Result[15]:=1;
  V:=1;Move(V,Result[16],4);
end;

end.
