unit Emulator.Inventory.B1008;

interface

uses System.SysUtils, Emulator.Loot.B1008;

const
  B1008BeginnerHealingPotionID = 54006;
  B1008BeginnerManaPotionID = 54206;
  B1008FirstRewardCount = 3;
  // Exact restoration amounts in b1008 item descriptions.
  B1008BeginnerHealingAmount = 20;
  B1008BeginnerManaAmount = 10;

type
  TB1008PotionEffect = class
  private
    class var FCooldownMS:array[0..1] of Integer;
  public
    class constructor Create;
    class function Kind(ItemID:Cardinal):Integer;static;
    class function CooldownMS(ItemID:Cardinal):Integer;static;
    class procedure Apply(ItemID: Cardinal; var HP,MP: Integer;
      MaxHP,MaxMP: Integer); static;
  end;
  TB1008ItemSwap = record
    Timestamp,CharacterID,SourceID,TargetID: Cardinal;
    SourcePage,SourceSlot,TargetPage,TargetSlot: Byte;
  end;
  TB1008ItemThrow = record
    Timestamp,CharacterID,ItemID: Cardinal;
    Page,Slot: Byte;
    Amount: Int64; // -1 means the entire stack, confirmed at 0x50FF6E.
  end;
  TB1008ItemUse = record
    Timestamp, CharacterID, ItemID, Parameter: Cardinal;
    Page, Slot, Code: Byte;
  end;
  TB1008ItemSplit = record
    Timestamp, CharacterID, ItemID: Cardinal;
    Page, Slot, Code: Byte;
    SourceCount: UInt64;
    Amount: Int64;
  end;
  TB1008InventoryWire = class
  private
    class procedure PutItemRecord(var Payload: TBytes; Offset: Integer;
      ItemID, Count: Cardinal; Slot: Byte); static;
  public
    class function ParseSwap(const P: TBytes): TB1008ItemSwap; static;
    class function ParseThrow(const P: TBytes): TB1008ItemThrow; static;
    class function ParseSplit(const P: TBytes): TB1008ItemSplit; static;
    class function BuildSplitAck(Timestamp, CharacterID: Cardinal;
      Success: Boolean): TBytes; static;
    class function BuildBagList(Timestamp,CharacterID: Cardinal;
      const Items: TArray<TB1008BagItem>): TBytes; static;
    class function ParseUse(const Payload: TBytes): TB1008ItemUse; static;
    class function AppendLoot(const List: TBytes; Count: Cardinal): TBytes; static;
    class function AppendCarat(const List: TBytes; Balance: Cardinal): TBytes; static;
    class function BuildUseAck(const UseRequest: TB1008ItemUse): TBytes; static;
    class function BuildList(Timestamp, CharacterID: Cardinal;
      IncludeFirstReward: Boolean): TBytes; overload; static;
    class function BuildList(Timestamp, CharacterID, HealingCount,
      ManaCount: Cardinal): TBytes; overload; static;
    class function BuildPutIn(Timestamp, CharacterID, ItemID,
      Count: Cardinal; Slot: Byte): TBytes; overload; static;
    class function BuildPutIn(Timestamp,CharacterID:Cardinal;
      const Item:TB1008BagItem):TBytes; overload; static;
    class function BuildPutOut(Timestamp, CharacterID, ItemID: Cardinal;
      Slot: Byte): TBytes; static;
  end;

implementation

uses Emulator.Protocol.B1008, System.Math, Emulator.Items.B1008,System.IniFiles;

class constructor TB1008PotionEffect.Create;
var Ini:TMemIniFile;I:Integer;
begin
  Ini:=TMemIniFile.Create(TB1008Items.DataPath('potions-v1.ini'),TEncoding.UTF8);
  try
    FCooldownMS[0]:=Ini.ReadInteger('potions','hp_cooldown_ms',-1);
    FCooldownMS[1]:=Ini.ReadInteger('potions','mp_cooldown_ms',-1);
    for I:=0 to 1 do if (FCooldownMS[I]<100) or (FCooldownMS[I]>60000) then
      raise Exception.Create('Invalid potion cooldown profile');
  finally Ini.Free;end;
end;

class function TB1008PotionEffect.Kind(ItemID:Cardinal):Integer;
begin
  if not TB1008Items.IsPotion(ItemID) then raise EArgumentException.Create('Unsupported potion');
  if TB1008Items.Get(ItemID).HealHP>0 then Result:=0 else Result:=1;
end;

class function TB1008PotionEffect.CooldownMS(ItemID:Cardinal):Integer;
begin Result:=FCooldownMS[Kind(ItemID)];end;

class procedure TB1008PotionEffect.Apply(ItemID: Cardinal; var HP,MP: Integer;
  MaxHP,MaxMP: Integer);
var D:TB1008ItemDefinition;
begin
  if (HP<=0) or (MaxHP<=0) or (MaxMP<0) or (MP<0) or (HP>MaxHP) or (MP>MaxMP) then
    raise EKarosProtocol.Create('Invalid living character vitals for potion');
  if not TB1008Items.IsPotion(ItemID) then raise EKarosProtocol.Create('Unsupported potion effect');
  D:=TB1008Items.Get(ItemID);
  HP:=HP+Min(D.HealHP,MaxHP-HP);MP:=MP+Min(D.HealMP,MaxMP-MP);
end;

procedure PutBE32(var B: TBytes; Offset: Integer; Value: Cardinal);
begin
  B[Offset]:=Byte(Value shr 24); B[Offset+1]:=Byte((Value shr 16) and $FF);
  B[Offset+2]:=Byte((Value shr 8) and $FF); B[Offset+3]:=Byte(Value and $FF);
end;

class function TB1008InventoryWire.ParseSwap(const P: TBytes): TB1008ItemSwap;
begin
  // Serializer 0x50F0C8 and receive handler 0x526A24.
  if (Length(P)<>22) then raise EKarosProtocol.Create('Invalid inventory swap size');
  if (P[0]<>6) or (P[1]<>8) then raise EKarosProtocol.Create('Not inventory swap');
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2); Result.CharacterID:=TB1008Wire.ReadBE32(P,6);
  Result.SourcePage:=P[10]; Result.SourceSlot:=P[11]; Result.SourceID:=TB1008Wire.ReadBE32(P,12);
  Result.TargetPage:=P[16]; Result.TargetSlot:=P[17]; Result.TargetID:=TB1008Wire.ReadBE32(P,18);
end;

class function TB1008InventoryWire.ParseThrow(const P: TBytes): TB1008ItemThrow;
var V: UInt64;
begin
  // Serializer 0x50F05F: BE character, byte page/slot, BE item, signed BE64 count.
  if Length(P)<>24 then raise EKarosProtocol.Create('Invalid inventory putout size');
  if (P[0]<>6) or (P[1]<>7) then raise EKarosProtocol.Create('Not inventory putout');
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2); Result.CharacterID:=TB1008Wire.ReadBE32(P,6);
  Result.Page:=P[10]; Result.Slot:=P[11]; Result.ItemID:=TB1008Wire.ReadBE32(P,12);
  V:=(UInt64(TB1008Wire.ReadBE32(P,16)) shl 32) or TB1008Wire.ReadBE32(P,20);
  Move(V,Result.Amount,8);
end;

class function TB1008InventoryWire.BuildBagList(Timestamp,CharacterID: Cardinal;
  const Items: TArray<TB1008BagItem>): TBytes;
var Item: TB1008BagItem; O: Integer;
begin
  Result:=BuildList(Timestamp,CharacterID,0,0);
  for Item in Items do begin
    if Item.Slot>=B1008BagSlots then raise EKarosProtocol.Create('Invalid bag slot');
    // Carat is restored separately through 06/06 (verified loading-crash fix).
    if Item.ItemID=B1008CaratID then Continue;
    O:=Length(Result); SetLength(Result,O+36); Inc(Result[11]);
    PutItemRecord(Result,O,Item.ItemID,Item.Amount,Item.Slot);
    Item.Properties.WritePacked(Result,O);
  end;
end;

class function TB1008InventoryWire.ParseSplit(const P: TBytes): TB1008ItemSplit;
var V: UInt64;
begin
  // 0x47C2C1: header, raw packed 36-byte SOURCE record, signed BE64
  // quantity, code. No destination cell is serialized by the Shift dialog.
  if Length(P)<>55 then raise EKarosProtocol.Create('Invalid inventory split size');
  if (P[0]<>6) or (P[1]<>$0A) then raise EKarosProtocol.Create('Not inventory split');
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2);
  Result.CharacterID:=TB1008Wire.ReadBE32(P,6);
  Result.Page:=P[10];Result.Slot:=P[11];
  Move(P[12],Result.ItemID,4);Move(P[26],Result.SourceCount,8);
  V:=(UInt64(TB1008Wire.ReadBE32(P,46)) shl 32) or TB1008Wire.ReadBE32(P,50);
  Move(V,Result.Amount,8);Result.Code:=P[54];
end;

class function TB1008InventoryWire.BuildSplitAck(Timestamp, CharacterID: Cardinal;
  Success: Boolean): TBytes;
begin
  // 0x526D4A only consumes header/code; inventory is updated through 06/06.
  // string.lod_eng 23001: "The items are split."; 23002: split failed.
  // Never reflect the client's packed item properties into a server reply.
  Result:=nil;SetLength(Result,55);Result[0]:=6;Result[1]:=$0A;
  PutBE32(Result,2,Timestamp);PutBE32(Result,6,CharacterID);
  if Success then Result[54]:=$38 else Result[54]:=9;
end;

class function TB1008InventoryWire.AppendLoot(const List: TBytes; Count: Cardinal): TBytes;
var Offset: Integer;
begin
  if (Length(List)<12) or (List[0]<>6) or (List[1]<>5) then
    raise EKarosProtocol.Create('Invalid inventory list');
  if Count>B1008LootStackLimit then raise EKarosProtocol.Create('Invalid loot count');
  Result:=Copy(List);
  if Count=0 then Exit;
  Offset:=Length(Result); SetLength(Result,Offset+36); Inc(Result[11]);
  PutItemRecord(Result,Offset,B1008BoneFragmentID,Count,B1008LootSlot);
end;

class function TB1008InventoryWire.AppendCarat(const List: TBytes; Balance: Cardinal): TBytes;
var Offset: Integer;
begin
  if (Length(List)<12) or (List[0]<>6) or (List[1]<>5) then
    raise EKarosProtocol.Create('Invalid inventory list');
  if Balance>B1008CaratLimit then raise EKarosProtocol.Create('Invalid Carat balance');
  Result:=Copy(List);
  if Balance=0 then Exit;
  // The list handler calls 0x50EE7C: ID 999999 updates player+0x5C8.
  // On 06/06, 0x51107E -> 0x50EDCE adjusts it by new-old stack amount.
  Offset:=Length(Result); SetLength(Result,Offset+36); Inc(Result[11]);
  PutItemRecord(Result,Offset,B1008CaratID,Balance,B1008CaratSlot);
end;

class function TB1008InventoryWire.ParseUse(
  const Payload: TBytes): TB1008ItemUse;
begin
  // CItemUsePacket parser 0x50FC7A requires 21 bytes. A live b1008 request
  // identifies a packed inventory page/slot and keeps all integral IDs BE.
  if Length(Payload)<>21 then raise EKarosProtocol.Create('Invalid ItemUse size');
  if (Payload[0]<>$06) or (Payload[1]<>$02) then
    raise EKarosProtocol.Create('Not ItemUse');
  Result.Timestamp:=TB1008Wire.ReadBE32(Payload,2);
  Result.CharacterID:=TB1008Wire.ReadBE32(Payload,6);
  Result.Page:=Payload[10]; Result.Slot:=Payload[11];
  Result.ItemID:=TB1008Wire.ReadBE32(Payload,12);
  Result.Parameter:=TB1008Wire.ReadBE32(Payload,16);
  Result.Code:=Payload[20];
end;

class function TB1008InventoryWire.BuildUseAck(
  const UseRequest: TB1008ItemUse): TBytes;
begin
  // The same packet class is registered for the server-to-client 06/02 path.
  Result:=nil; SetLength(Result,21); Result[0]:=$06; Result[1]:=$02;
  PutBE32(Result,2,UseRequest.Timestamp);
  PutBE32(Result,6,UseRequest.CharacterID);
  Result[10]:=UseRequest.Page; Result[11]:=UseRequest.Slot;
  PutBE32(Result,12,UseRequest.ItemID);
  PutBE32(Result,16,UseRequest.Parameter); Result[20]:=UseRequest.Code;
end;

class procedure TB1008InventoryWire.PutItemRecord(var Payload: TBytes;
  Offset: Integer; ItemID, Count: Cardinal; Slot: Byte);
var V: Cardinal;
begin
  if Count=0 then raise EArgumentOutOfRangeException.Create('Item count must be positive');
  Payload[Offset]:=1;                 // First normal inventory page; zero is equipment.
  Payload[Offset+1]:=Slot;            // Linear cell index on that page.
  V:=ItemID; Move(V,Payload[Offset+2],4); // Packed fields use native little-endian.
  // 0x505594 reads packed +16 as the item's stack value. Zero is removal,
  // including equipment (0x511A8E), NOT a non-stackable item marker.
  V:=Count; Move(V,Payload[Offset+16],4);
end;

class function TB1008InventoryWire.BuildList(Timestamp,
  CharacterID: Cardinal; IncludeFirstReward: Boolean): TBytes;
begin
  if IncludeFirstReward then
    Exit(BuildList(Timestamp,CharacterID,B1008FirstRewardCount,B1008FirstRewardCount));
  Result:=BuildList(Timestamp,CharacterID,0,0);
end;

class function TB1008InventoryWire.BuildList(Timestamp, CharacterID,
  HealingCount, ManaCount: Cardinal): TBytes;
var RecordCount,Offset: Integer;
begin
  // CItemInvenListPacket 06/05, 0x52585D and handler before 0x526769:
  // byte +10 is page count, byte +11 is record count, records start at +12.
  // Page zero is equipment; page one (resource 0x36B7) is the first backpack.
  if (HealingCount>B1008FirstRewardCount) or
    (ManaCount>B1008FirstRewardCount) then
    raise EArgumentOutOfRangeException.Create('Reward-item count outside range');
  RecordCount:=Ord(HealingCount>0)+Ord(ManaCount>0);
  SetLength(Result,12+RecordCount*36);
  FillChar(Result[0],Length(Result),0); Result[0]:=$06; Result[1]:=$05;
  PutBE32(Result,2,Timestamp); PutBE32(Result,6,CharacterID);
  Result[10]:=2; Result[11]:=RecordCount; Offset:=12;
  if HealingCount>0 then begin
    PutItemRecord(Result,Offset,B1008BeginnerHealingPotionID,HealingCount,0);
    Inc(Offset,36);
  end;
  if ManaCount>0 then
    PutItemRecord(Result,Offset,B1008BeginnerManaPotionID,ManaCount,1);
end;

class function TB1008InventoryWire.BuildPutIn(Timestamp, CharacterID,
  ItemID, Count: Cardinal; Slot: Byte): TBytes;
var Item:TB1008BagItem;
begin
  Item:=Default(TB1008BagItem);Item.ItemID:=ItemID;
  Item.Amount:=Count;Item.Slot:=Slot;
  Result:=BuildPutIn(Timestamp,CharacterID,Item);
end;

class function TB1008InventoryWire.BuildPutIn(Timestamp,CharacterID:Cardinal;
  const Item:TB1008BagItem):TBytes;
begin
  // CItemInvenPutinPacket, 0x525898 / 0x526769: 10-byte BE packet header
  // followed by the client's packed 36-byte item record (0x480CC3/0x484AC3).
  Result:=nil; SetLength(Result,46); Result[0]:=$06; Result[1]:=$06;
  PutBE32(Result,2,Timestamp); PutBE32(Result,6,CharacterID);
  PutItemRecord(Result,10,Item.ItemID,Item.Amount,Item.Slot);
  Item.Properties.WritePacked(Result,10);
end;

class function TB1008InventoryWire.BuildPutOut(Timestamp, CharacterID,
  ItemID: Cardinal; Slot: Byte): TBytes;
begin
  // CItemInvenPutoutPacket parser 0x50FCB4 requires 24 bytes. Its receive
  // handler 0x52697E reads page +10, slot +11 and BE item ID +12, then calls
  // the inventory-cell removal path 0x51122C. The unused tail remains zero.
  Result:=nil; SetLength(Result,24); Result[0]:=$06; Result[1]:=$07;
  PutBE32(Result,2,Timestamp); PutBE32(Result,6,CharacterID);
  Result[10]:=1; Result[11]:=Slot; PutBE32(Result,12,ItemID);
end;

end.
