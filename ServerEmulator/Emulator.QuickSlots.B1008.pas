unit Emulator.QuickSlots.B1008;

interface

uses System.SysUtils;

const B1008QuickSlotCount=36;
  B1008QuickSlotsOffset=$19F;

type
  TB1008QuickSlot = record
    Slot,ReferenceID:Cardinal;
    SourcePage,SourceSlot:Integer;
    function Supported:Boolean;
  end;
  TB1008QuickSlotRequest = record
    Timestamp,CharacterID:Cardinal;
    Remove:Boolean;
    Entry:TB1008QuickSlot;
    class function Parse(const Packet:TBytes):TB1008QuickSlotRequest;static;
  end;
  TB1008QuickSlotWire = record
    class function SkillSourceSlot(ID:Cardinal;ClassID:Word):Integer;static;
    class procedure ApplyCharacterInfo(var Packet:TBytes;const Entries:TArray<TB1008QuickSlot>);static;
  end;

implementation

uses Emulator.Protocol.B1008,Emulator.Skills.B1008,Emulator.Loot.B1008,Emulator.ProfessionSkills.B1008;

class function TB1008QuickSlotWire.SkillSourceSlot(ID:Cardinal;ClassID:Word):Integer;
begin
  case ID of
    1001,5001,9001:Result:=0;
    1002:Result:=1;
    1004:Result:=2;
    1005:Result:=4;
    1003:if ClassID=110 then Result:=6 else Result:=5;
    1101:Result:=5;
    1901:Result:=6;
    1103,1903:Result:=8;
    1104,1904:Result:=9;
    1105,1905:Result:=10;
    1106,1906:Result:=11;
    1107,1907:Result:=12;
  else Result:=-1;end;
end;

function TB1008QuickSlot.Supported:Boolean;
begin
  // Live potion drags use signed -1, page 1 and a backpack cell.
  // Restore 0x512864 dispatches negative references as item links.
  if SourcePage=1 then Exit((Slot<B1008QuickSlotCount) and
    (ReferenceID=High(Cardinal)) and (SourceSlot>=0) and (SourceSlot<B1008BagSlots));
  // First supported references are learned starter skills. Live Power Strike
  // request: 06/0B, slot=0, LE triplet=1001/9/0. Other reference types are
  // observed, not replayed into the client's UI arrays until their bounds are mapped.
  // Live Body Blow from K: 1003/9/5. These are UI coordinates, not ranks.
  Result:=(Slot<B1008QuickSlotCount) and (SourcePage=9) and
    (((SourceSlot=0) and ((ReferenceID=B1008PowerStrikeID) or (ReferenceID=B1008SlashID) or
      (ReferenceID=B1008SupplementID))) or ((SourceSlot in [5,6]) and (ReferenceID=B1008BodyBlowID)) or
      ((SourceSlot=5) and (ReferenceID=B1008BladeCrashID)) or
      ((SourceSlot=6) and (ReferenceID=B1008WindBladeID)) or
      ((SourceSlot=8) and ((ReferenceID=B1008SpineBreakerID) or (ReferenceID=B1008StunAttackID))) or
      ((SourceSlot=9) and ((ReferenceID=B1008ThunderHowlID) or (ReferenceID=B1008CycloneID))) or
      ((SourceSlot=10) and ((ReferenceID=B1008SwordRevengeID) or (ReferenceID=B1008PolearmRevengeID))) or
      ((SourceSlot=11) and ((ReferenceID=B1008SlaterID) or (ReferenceID=B1008PhantomThrustID))) or
      ((SourceSlot=12) and ((ReferenceID=B1008SwordDeathLeapID) or (ReferenceID=B1008PolearmDeathLeapID))) or
      ((SourceSlot=2) and (ReferenceID=B1008FrenzyID)) or
      ((SourceSlot=4) and (ReferenceID=B1008ProvocationID)) or
      ((SourceSlot=1) and (ReferenceID=B1008CoerciveID)));
end;

class function TB1008QuickSlotRequest.Parse(const Packet:TBytes):TB1008QuickSlotRequest;
begin
  if not (Length(Packet) in [14,26]) then raise EKarosProtocol.Create('Invalid quickslot length');
  if (Packet[0]<>6) or not (Packet[1] in [$0B,$0C]) or
    ((Packet[1]=$0B) and (Length(Packet)<>26)) or
    ((Packet[1]=$0C) and (Length(Packet)<>14)) then raise EKarosProtocol.Create('Invalid quickslot command');
  Result:=Default(TB1008QuickSlotRequest);Result.Remove:=Packet[1]=$0C;
  // 0x51280F and 0x50C0D1: BE actor/index, raw LE 12-byte reference.
  Result.Timestamp:=TB1008Wire.ReadBE32(Packet,2);Result.CharacterID:=TB1008Wire.ReadBE32(Packet,6);
  Result.Entry.Slot:=TB1008Wire.ReadBE32(Packet,10);
  if not Result.Remove then begin
    Move(Packet[14],Result.Entry.ReferenceID,4);Move(Packet[18],Result.Entry.SourcePage,4);
    Move(Packet[22],Result.Entry.SourceSlot,4);
  end;
end;

class procedure TB1008QuickSlotWire.ApplyCharacterInfo(var Packet:TBytes;const Entries:TArray<TB1008QuickSlot>);
var E:TB1008QuickSlot;O:Integer;Used:array[0..35] of Boolean;
begin
  if (Length(Packet)<>$4B3) or (Packet[0]<>2) or (Packet[1]<>5) then
    raise EKarosProtocol.Create('Quickslots require CharInfo');
  FillChar(Used,SizeOf(Used),0);
  // 0x5254DC selects CharInfo+$14B, 0x5255B1 adds $54. 0x512864
  // restores 36 consecutive 12-byte records into the hotbar, no S2C echo needed.
  for E in Entries do begin
    if not E.Supported then raise EKarosProtocol.Create('Unsupported saved quickslot');
    if Used[E.Slot] then raise EKarosProtocol.Create('Duplicate saved quickslot');
    Used[E.Slot]:=True;
  end;
  FillChar(Packet[B1008QuickSlotsOffset],B1008QuickSlotCount*12,0);
  for E in Entries do begin
    O:=B1008QuickSlotsOffset+Integer(E.Slot)*12;
    Move(E.ReferenceID,Packet[O],4);Move(E.SourcePage,Packet[O+4],4);Move(E.SourceSlot,Packet[O+8],4);
  end;
end;

end.
