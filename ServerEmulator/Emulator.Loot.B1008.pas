unit Emulator.Loot.B1008;

interface

uses System.SysUtils, Emulator.ItemProperties.B1008;

const
  // itemBase.lod_eng: 751 records, stride 2184, record at 1408684.
  B1008BoneFragmentID = 90004;
  B1008CaratID = 999999;
  B1008CaratSlot = 3;
  B1008CaratLimit = High(Integer); // No gameplay stack cap; native UI uses signed 32-bit counts.
  B1008LootSlot = 2; // Slots 0/1 remain owned by the existing quest rewards.
  B1008LootStackLimit = 100; // Bone Fragment: user confirmed original stack size.
  B1008LootGroundLimit = 128;
  B1008PickupRange = 30.0; // Client pickup sender 0x51C250, double at 0x670618.
  B1008BagSlots = 20; // Visible first backpack: four columns, five rows.
  B1008MobLootLifetimeMS = 60000;
  B1008MobLootScatterRadius = 8.0; // Separate simultaneous boxes; same terrain height.
  B1008ThrownLootLifetimeMS = 60000;

type
  TB1008BagItem = record
    Slot: Byte;
    ItemID,Amount: Cardinal;
    Properties: TB1008ItemProperties;
  end;
  TB1008Pickup = record
    Timestamp, CharacterID, DropID, ItemID: Cardinal;
    Code: Byte;
  end;
  TB1008GroundDrop = record
    ID, ItemID, OwnerID, Amount: Cardinal;
    Properties: TB1008ItemProperties;
    X,Z,Y: Single;
    Receipt: string;
    Collected: Boolean;
    Sent: Boolean;
    ExpiresTick: UInt64;
    ExpiresUTC: Int64;
  end;
  TB1008LootWire = class
  public
    class function ParsePickup(const P: TBytes): TB1008Pickup; static;
    class function BuildPickup(const R: TB1008Pickup): TBytes; static;
    class function BuildDrop(Timestamp: Cardinal; const D: TB1008GroundDrop): TBytes; static;
    class function BuildRemove(Timestamp: Cardinal; const D: TB1008GroundDrop): TBytes; static;
  end;

function B1008UtcNowMS: Int64;

implementation

uses System.Math, System.DateUtils, Emulator.Protocol.B1008, Emulator.Items.B1008;

function B1008UtcNowMS: Int64;
var U: TDateTime;
begin
  U:=TTimeZone.Local.ToUniversalTime(Now);
  Result:=DateTimeToUnix(U,True)*1000+MilliSecondOfTheSecond(U);
end;

class function TB1008LootWire.BuildRemove(Timestamp: Cardinal;
  const D: TB1008GroundDrop): TBytes;
var R: TB1008Pickup;
begin
  // 0x51BF47: character -1 selects direct removal at 0x51BAF2, not pickup.
  R:=Default(TB1008Pickup); R.Timestamp:=Timestamp; R.CharacterID:=$FFFFFFFF;
  R.DropID:=D.ID; R.ItemID:=D.ItemID; R.Code:=$33; Result:=BuildPickup(R);
end;

procedure BE(var P: TBytes; O: Integer; V: Cardinal);
begin
  P[O]:=Byte(V shr 24); P[O+1]:=Byte(V shr 16);
  P[O+2]:=Byte(V shr 8); P[O+3]:=Byte(V);
end;

class function TB1008LootWire.ParsePickup(const P: TBytes): TB1008Pickup;
begin
  // CItemPickupPacket serializer 0x519D04: header, three BE IDs, one byte.
  if Length(P)<>19 then raise EKarosProtocol.Create('Invalid ItemPickup size');
  if (P[0]<>6) or (P[1]<>3) then raise EKarosProtocol.Create('Not ItemPickup');
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2);
  Result.CharacterID:=TB1008Wire.ReadBE32(P,6);
  Result.DropID:=TB1008Wire.ReadBE32(P,10);
  Result.ItemID:=TB1008Wire.ReadBE32(P,14);
  Result.Code:=P[18];
end;

class function TB1008LootWire.BuildPickup(const R: TB1008Pickup): TBytes;
begin
  // Receive handler 0x526268: code $33 calls 0x51BF47 (pickup animation/removal).
  Result:=nil; SetLength(Result,19); Result[0]:=6; Result[1]:=3;
  BE(Result,2,R.Timestamp); BE(Result,6,R.CharacterID);
  BE(Result,10,R.DropID); BE(Result,14,R.ItemID); Result[18]:=R.Code;
end;

class function TB1008LootWire.BuildDrop(Timestamp: Cardinal;
  const D: TB1008GroundDrop): TBytes;
var V: Cardinal;
begin
  if (D.ID=0) or (D.OwnerID<>1) or (TB1008Items.StackLimit(D.ItemID)=0) then
    raise EKarosProtocol.Create('Unsupported drop');
  if (D.Amount=0) or (D.Amount>TB1008Items.StackLimit(D.ItemID)) then
    raise EKarosProtocol.Create('Invalid drop amount');
  if IsNan(D.X) or IsInfinite(D.X) or (Abs(D.X)>100000) or
    IsNan(D.Z) or IsInfinite(D.Z) or (Abs(D.Z)>100000) or
    IsNan(D.Y) or IsInfinite(D.Y) or (Abs(D.Y)>100000) then
    raise EKarosProtocol.Create('Invalid drop position');
  // 06/04 handler 0x5263D9: BE owner/drop IDs; packed item at +26;
  // XYZ is read from +62/+70/+66. Unknown auxiliary integers remain neutral.
  Result:=nil; SetLength(Result,74); Result[0]:=6; Result[1]:=4;
  BE(Result,2,Timestamp); BE(Result,6,D.OwnerID); BE(Result,10,D.ID);
  V:=D.ItemID; Move(V,Result[28],4);
  V:=D.Amount; Move(V,Result[42],4);
  D.Properties.WritePacked(Result,26);
  Move(D.X,Result[62],4); Move(D.Z,Result[66],4); Move(D.Y,Result[70],4);
end;

end.
