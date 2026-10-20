unit Emulator.Equipment.B1008;

interface

uses System.SysUtils, Emulator.ItemProperties.B1008;

type
  TB1008EquipmentRequest = record
    Timestamp,CharacterID,ItemID:Cardinal;
    Page,Slot,EquipSlot,Code:Byte;
    Wear:Boolean;
  end;
  TB1008EquipmentItem = record
    Slot: Byte;
    ItemID: Cardinal;
    Properties: TB1008ItemProperties;
  end;
  TB1008Equipment = class
  public
    class function Starter(ClassID: Word): TArray<TB1008EquipmentItem>; static;
    class function ItemSlot(ItemID:Cardinal;ClassID:Word=0):Byte; static;
    class procedure PhysicalAttack(ClassID:Word;const Items:TArray<TB1008EquipmentItem>;
      out Minimum,Maximum:Integer;Level:Word=1); static;
    class function ParseRequest(const Packet:TBytes):TB1008EquipmentRequest; static;
    class function BuildWear(const Request:TB1008EquipmentRequest):TBytes; static;
    class function BuildSlotUpdate(Timestamp:Cardinal;const Item:TB1008EquipmentItem;
      Present:Boolean):TBytes; static;
    class function Defense(const Items: TArray<TB1008EquipmentItem>): Integer; static;
    class function GemStrength(const Items:TArray<TB1008EquipmentItem>):Integer;static;
    class procedure Validate(const Items: TArray<TB1008EquipmentItem>; ClassID: Word = 0); static;
    class procedure ApplyPreview(var Packet: TBytes; const Items: TArray<TB1008EquipmentItem>); static;
    class procedure ApplyCharacterInfo(var Packet: TBytes; const Items: TArray<TB1008EquipmentItem>); static;
    class procedure ApplyParameters(var Packet: TBytes; ClassID: Word;
      const Items: TArray<TB1008EquipmentItem>); static;
    class function AppendList(const List: TBytes;
      const Items: TArray<TB1008EquipmentItem>): TBytes; static;
  end;

implementation

uses Emulator.Protocol.B1008, Emulator.Balance.B1008, Emulator.Items.B1008,Emulator.ItemEnhancement.B1008;

type TStarterDefinition = record
  ClassID: Word; Slot: Byte; ItemID: Cardinal; PhysicalDefense: Integer;
end;
const
  // Original b1008 itemBase.lod_eng: item ID +0, class +8, equip slot +32.
  // itemAttr.lod_eng, enchantment 0: physical defense double +0x3C.
  // No helm/accessories are present in these level-one sets.
  Definitions: array[0..14] of TStarterDefinition = (
    (ClassID:100;Slot:1;ItemID:32001;PhysicalDefense:15),
    (ClassID:100;Slot:2;ItemID:32401;PhysicalDefense:15),
    (ClassID:100;Slot:3;ItemID:32801;PhysicalDefense:8),
    (ClassID:100;Slot:4;ItemID:33201;PhysicalDefense:8),
    (ClassID:100;Slot:7;ItemID:1001;PhysicalDefense:0),
    (ClassID:300;Slot:1;ItemID:36001;PhysicalDefense:15),
    (ClassID:300;Slot:2;ItemID:36401;PhysicalDefense:14),
    (ClassID:300;Slot:3;ItemID:36801;PhysicalDefense:8),
    (ClassID:300;Slot:4;ItemID:37201;PhysicalDefense:7),
    (ClassID:300;Slot:7;ItemID:9001;PhysicalDefense:0),
    (ClassID:500;Slot:1;ItemID:40001;PhysicalDefense:14),
    (ClassID:500;Slot:2;ItemID:40401;PhysicalDefense:13),
    (ClassID:500;Slot:3;ItemID:40801;PhysicalDefense:8),
    (ClassID:500;Slot:4;ItemID:41201;PhysicalDefense:7),
    (ClassID:500;Slot:7;ItemID:13001;PhysicalDefense:0));

procedure BE(var P:TBytes;O:Integer;V:Cardinal);
begin P[O]:=Byte(V shr 24);P[O+1]:=Byte((V shr 16) and 255);
  P[O+2]:=Byte((V shr 8) and 255);P[O+3]:=Byte(V and 255);end;

class function TB1008Equipment.ItemSlot(ItemID:Cardinal;ClassID:Word):Byte;
var D:TB1008ItemDefinition;
begin
  if TB1008Items.Find(ItemID,D) and not D.InventoryOnly and
    ((ClassID=0) or (D.ClassID=0) or (ClassID=D.ClassID)) then Exit(D.Slot);
  Result:=0;
end;

class procedure TB1008Equipment.PhysicalAttack(ClassID:Word;
  const Items:TArray<TB1008EquipmentItem>;out Minimum,Maximum:Integer;Level:Word);
var Item:TB1008EquipmentItem;D:TB1008ItemDefinition;MinHundredths,MaxHundredths,UnusedDefense:Integer;
begin
  Validate(Items,ClassID);MinHundredths:=0;MaxHundredths:=0;
  for Item in Items do if Item.Slot=7 then begin
    D:=TB1008Items.Get(Item.ItemID);MinHundredths:=D.AttackMin100;MaxHundredths:=D.AttackMax100;
    if not TB1008ItemEnhancement.FindStats(Item.ItemID,Item.Properties.NativeGrade,MinHundredths,MaxHundredths,UnusedDefense) then begin
      MinHundredths:=D.AttackMin100;MaxHundredths:=D.AttackMax100;
    end;
  end;
  // Match the verified b1008 character window: truncate the weapon range,
  // then add the character's common attack base. No extra STR is added:
  // that base already represents the agreed unequipped class attack.
  Minimum:=TB1008Balance.BaseAttributes(ClassID,Level).PhysicalAttack+MinHundredths div 100;
  Maximum:=TB1008Balance.BaseAttributes(ClassID,Level).PhysicalAttack+MaxHundredths div 100;
end;

class function TB1008Equipment.ParseRequest(const Packet:TBytes):TB1008EquipmentRequest;
begin
  // Original serializers 0x50EF19 (06/00,18), 0x50EF89 (06/01,17).
  // Equip slot $FF requests the item's natural slot; do not echo $FF.
  if not (Length(Packet) in [17,18]) then raise EKarosProtocol.Create('Invalid wear packet length');
  if (Packet[0]<>6) or (Packet[1]>1) or (Length(Packet)<>18-Integer(Packet[1])) then
    raise EKarosProtocol.Create('Invalid wear packet type/length');
  Result:=Default(TB1008EquipmentRequest);Result.Wear:=Packet[1]=0;
  Result.Timestamp:=TB1008Wire.ReadBE32(Packet,2);Result.CharacterID:=TB1008Wire.ReadBE32(Packet,6);
  Result.Page:=Packet[10];Result.Slot:=Packet[11];Result.EquipSlot:=Packet[12];
  Result.ItemID:=TB1008Wire.ReadBE32(Packet,13);if Result.Wear then Result.Code:=Packet[17];
end;

class function TB1008Equipment.BuildWear(const Request:TB1008EquipmentRequest):TBytes;
begin
  if (Request.CharacterID<>1) or (Request.Code<>0) or
    (ItemSlot(Request.ItemID)<>Request.EquipSlot) or (Request.EquipSlot=0) then
    raise EKarosProtocol.Create('Invalid resolved equipment acknowledgement');
  Result:=nil;SetLength(Result,17+Ord(Request.Wear));Result[0]:=6;Result[1]:=Ord(not Request.Wear);
  BE(Result,2,Request.Timestamp);BE(Result,6,Request.CharacterID);
  Result[10]:=Request.Page;Result[11]:=Request.Slot;Result[12]:=Request.EquipSlot;
  BE(Result,13,Request.ItemID);
end;

class function TB1008Equipment.BuildSlotUpdate(Timestamp:Cardinal;const Item:TB1008EquipmentItem;
  Present:Boolean):TBytes;
begin
  Validate([Item]);Result:=nil;SetLength(Result,46);Result[0]:=6;Result[1]:=6;
  BE(Result,2,Timestamp);BE(Result,6,1);Result[11]:=Item.Slot;Result[16]:=Item.Slot;
  Move(Item.ItemID,Result[12],4);Result[26]:=Ord(Present);
  Item.Properties.WritePacked(Result,10);
  // 06/06 +16=0 removes the equipment cell AND visual slot (0x5267D1..526959).
end;

class function TB1008Equipment.Starter(ClassID: Word): TArray<TB1008EquipmentItem>;
var D:TStarterDefinition; N:Integer;
begin
  Result:=nil;
  for D in Definitions do if D.ClassID=ClassID then begin
    N:=Length(Result);SetLength(Result,N+1);
    Result[N].Slot:=D.Slot;Result[N].ItemID:=D.ItemID;
  end;
  if Length(Result)<>5 then raise EKarosProtocol.Create('Unsupported starter equipment class');
end;

class procedure TB1008Equipment.Validate(const Items:TArray<TB1008EquipmentItem>;ClassID:Word);
var Item:TB1008EquipmentItem;Seen:set of Byte;
begin
  Seen:=[];
  for Item in Items do begin
    if Item.Slot in Seen then raise EKarosProtocol.Create('Duplicate equipment slot');
    Include(Seen,Item.Slot);
    if (Item.Slot=0) or (ItemSlot(Item.ItemID,ClassID)<>Item.Slot) then
      raise EKarosProtocol.Create('Invalid equipment item/class/slot');
  end;
end;

class function TB1008Equipment.Defense(const Items:TArray<TB1008EquipmentItem>):Integer;
var Item:TB1008EquipmentItem;Minimum,Maximum,Bonus:Integer;
begin
  Validate(Items);Result:=0;
  for Item in Items do begin
    Bonus:=TB1008Items.Get(Item.ItemID).Defense;
    if not TB1008ItemEnhancement.FindStats(Item.ItemID,Item.Properties.NativeGrade,Minimum,Maximum,Bonus) then
      Bonus:=TB1008Items.Get(Item.ItemID).Defense;
    Inc(Result,Bonus);
  end;
end;

class function TB1008Equipment.GemStrength(const Items:TArray<TB1008EquipmentItem>):Integer;
var Item:TB1008EquipmentItem;I:Integer;
begin
  Validate(Items);Result:=0;
  for Item in Items do if Item.ItemID=51001 then
    for I:=0 to 1 do Inc(Result,TB1008ItemEnhancement.GemStrength(Item.Properties.GemIDs[I]));
end;

procedure PutVisual(var Packet:TBytes; Offset:Integer;const Items:TArray<TB1008EquipmentItem>);
var Item:TB1008EquipmentItem;
begin
  TB1008Equipment.Validate(Items);
  // charData+0x67F is 26 LE item IDs; 06/05 handler 0x5266CE and
  // 0x4F021D use the same slots to rebuild the actor's equipment models.
  FillChar(Packet[Offset],26*4,0);
  for Item in Items do Move(Item.ItemID,Packet[Offset+4*Item.Slot],4);
end;

class procedure TB1008Equipment.ApplyPreview(var Packet:TBytes;const Items:TArray<TB1008EquipmentItem>);
begin
  if (Length(Packet)<$152) or (Packet[0]<>2) or (Packet[1]<>1) then
    raise EKarosProtocol.Create('Equipment preview requires character list');
  PutVisual(Packet,$80,Items); // preview+15 -> charData+0x60E
end;

class procedure TB1008Equipment.ApplyCharacterInfo(var Packet:TBytes;const Items:TArray<TB1008EquipmentItem>);
begin
  if (Length(Packet)<>$4B3) or (Packet[0]<>2) or (Packet[1]<>5) then
    raise EKarosProtocol.Create('Equipment appearance requires CharInfo');
  PutVisual(Packet,$7B,Items); // CharInfo+10 -> charData+0x60E
end;

class procedure TB1008Equipment.ApplyParameters(var Packet:TBytes;ClassID:Word;
  const Items:TArray<TB1008EquipmentItem>);
var Offset:Integer;Bonus,Total:Single;A:TB1008BaseAttributes;
begin
  Validate(Items,ClassID);
  if (Length(Packet)=$4B3) and (Packet[0]=2) and (Packet[1]=5) then Offset:=$373
  else if (Length(Packet)=$14A) and (Packet[0]=8) and (Packet[1]=2) then Offset:=10
  else raise EKarosProtocol.Create('Equipment stats require CharInfo or Parameters');
  A:=TB1008Balance.BaseAttributes(ClassID);Bonus:=Defense(Items);Total:=A.PhysicalDefense+Bonus;
  // UI 0x46B903: +5C is TOTAL defense, +94 only the orange bonus annotation.
  // Weapon min/max are added by 0x46B621 from itemAttr; leave attack base alone.
  Move(Total,Packet[Offset+$5C],4);Move(Bonus,Packet[Offset+$94],4);
end;

class function TB1008Equipment.AppendList(const List:TBytes;
  const Items:TArray<TB1008EquipmentItem>):TBytes;
var Item:TB1008EquipmentItem;O:Integer;Count:Cardinal;
begin
  Validate(Items);
  if (Length(List)<12) or (List[0]<>6) or (List[1]<>5) or
    (Length(List)<>12+36*List[11]) or (Integer(List[11])+Length(Items)>127) then
    raise EKarosProtocol.Create('Invalid equipment inventory list');
  Result:=Copy(List);
  for Item in Items do begin
    O:=Length(Result);SetLength(Result,O+36);FillChar(Result[O],36,0);
    Inc(Result[11]);Result[O]:=0;Result[O+1]:=Item.Slot;Result[O+6]:=Item.Slot;
    Move(Item.ItemID,Result[O+2],4);
    // 0x526679 requires +6 in 1..25, independently of page/cell +0/+1.
    // 0x511A8E tests the 64-bit amount at +16: zero REMOVES equipped items.
    Count:=1;Move(Count,Result[O+16],4);
    Item.Properties.WritePacked(Result,O);
  end;
end;

end.
