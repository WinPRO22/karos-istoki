unit Emulator.Shop.B1008;

interface

uses System.SysUtils;

type
  TB1008Merchant = record
    Handle,NpcID,MapID,ShopID:Cardinal;
    Name:string;
    X,Z,Y:Single;
    Items:TArray<Cardinal>;
  end;
  TB1008ShopBuy = record
    Timestamp,CharacterID,NpcHandle,ItemID:Cardinal;
    Code:Byte;
    Amount:Int64;
    class function Parse(const P:TBytes):TB1008ShopBuy;static;
    function Quantity:Cardinal;
    function Supported:Boolean;
    function Ack:TBytes;
  end;
  TB1008ShopSell = record
    Timestamp,CharacterID,Page,Slot,ItemID,NpcHandle:Cardinal;
    Code:Byte;
    Amount:Int64;
    class function Parse(const P:TBytes):TB1008ShopSell;static;
    function Ack:TBytes;
    function Supported:Boolean;
  end;
  TB1008Shop = class
  private
    class var FMerchants:TArray<TB1008Merchant>;
  public
    class constructor Create;
    class function All:TArray<TB1008Merchant>;static;
    class function Find(Handle:Cardinal;out Merchant:TB1008Merchant):Boolean;static;
    class function IsMerchant(Handle:Cardinal):Boolean;static;
    class function BuildAppear(Timestamp,Handle:Cardinal):TBytes;static;
    class function CanSellAt(MapID,NpcHandle:Cardinal;X,Z,Y:Single):Boolean;static;
    class function Sells(NpcHandle,ItemID:Cardinal):Boolean;static;
  end;

implementation

uses System.Math,System.IOUtils,System.JSON,Emulator.Protocol.B1008,
  Emulator.World.B1008,Emulator.Loot.B1008,Emulator.Items.B1008;

class constructor TB1008Shop.Create;
var Root:TJSONObject;Rows,Items:TJSONArray;V:TJSONValue;M:TB1008Merchant;
  I,J,K,ItemID:Integer;D:TB1008ItemDefinition;
begin
  Root:=TJSONObject.ParseJSONValue(TFile.ReadAllText(TB1008Items.DataPath('shops-v1.json'),TEncoding.UTF8)) as TJSONObject;
  if Root=nil then raise Exception.Create('Invalid b1008 shop catalog');
  try
    if Root.GetValue<string>('build')<>'b1008' then raise Exception.Create('Wrong shop catalog build');
    Rows:=Root.GetValue<TJSONArray>('merchants');SetLength(FMerchants,Rows.Count);I:=0;
    for V in Rows do begin
      M:=Default(TB1008Merchant);M.Handle:=V.GetValue<Cardinal>('handle');
      M.NpcID:=V.GetValue<Cardinal>('npcId');M.MapID:=V.GetValue<Cardinal>('mapId');
      M.ShopID:=V.GetValue<Cardinal>('shopId');M.Name:=V.GetValue<string>('name');
      M.X:=V.GetValue<Double>('x');M.Z:=V.GetValue<Double>('z');M.Y:=V.GetValue<Double>('y');
      // Original Store services use unmodified itemBase prices. Fail closed
      // rather than silently ignoring a future catalog's different factors.
      if (M.Handle=0) or (M.Handle>=1000) or (M.NpcID=0) or (M.MapID<>19003) or
        (M.Name='') or IsNan(M.X) or IsNan(M.Z) or IsNan(M.Y) or
        IsInfinite(M.X) or IsInfinite(M.Z) or IsInfinite(M.Y) or
        (V.GetValue<Integer>('buyPercent')<>100) or (V.GetValue<Integer>('sellPercent')<>100) then
        raise Exception.Create('Unsupported merchant definition');
      for J:=0 to I-1 do if FMerchants[J].Handle=M.Handle then raise Exception.Create('Duplicate merchant handle');
      Items:=V.GetValue<TJSONArray>('items');SetLength(M.Items,Items.Count);
      // An empty native Store (Jason, Holio, etc.) still accepts sales.
      if (M.ShopID=0)<>(Items.Count=0) then raise Exception.Create('Invalid sell-only Store');
      for J:=0 to Items.Count-1 do begin
        ItemID:=StrToInt(Items.Items[J].Value);
        if (ItemID<=0) or not TB1008Items.Find(ItemID,D) then
          raise Exception.Create('Unsupported merchant item');
        for K:=0 to J-1 do if M.Items[K]=Cardinal(ItemID) then raise Exception.Create('Duplicate merchant item');
        M.Items[J]:=ItemID;
      end;
      FMerchants[I]:=M;Inc(I);
    end;
  finally Root.Free;end;
end;

class function TB1008Shop.All:TArray<TB1008Merchant>;
begin Result:=Copy(FMerchants);end;

class function TB1008Shop.Find(Handle:Cardinal;out Merchant:TB1008Merchant):Boolean;
var M:TB1008Merchant;
begin
  for M in FMerchants do if M.Handle=Handle then begin Merchant:=M;Exit(True);end;
  Merchant:=Default(TB1008Merchant);Result:=False;
end;

class function TB1008Shop.IsMerchant(Handle:Cardinal):Boolean;
var M:TB1008Merchant;
begin Result:=Find(Handle,M);end;

class function TB1008Shop.BuildAppear(Timestamp,Handle:Cardinal):TBytes;
var M:TB1008Merchant;
begin
  if not Find(Handle,M) then raise EArgumentException.Create('Unknown merchant handle');
  // Same verified neutral NPC packet and original placement/template identity.
  Result:=TB1008World.BuildDomingoAppearProbe(Timestamp);
  Move(M.Handle,Result[8],4);Move(M.Handle,Result[$46],4);
  Move(M.X,Result[12],4);Move(M.Z,Result[16],4);Move(M.Y,Result[20],4);
end;

procedure BE(var P:TBytes;O:Integer;V:Cardinal);
begin
  P[O]:=Byte(V shr 24);P[O+1]:=Byte((V shr 16) and $FF);
  P[O+2]:=Byte((V shr 8) and $FF);P[O+3]:=Byte(V and $FF);
end;

class function TB1008ShopBuy.Parse(const P:TBytes):TB1008ShopBuy;
var N:UInt64;
begin
  // Original serializer 0x47C322; 27-byte request observed live.
  if (Length(P)<>27) then raise EKarosProtocol.Create('Invalid shop buy size');
  if (P[0]<>6) or (P[1]<>$0D) then raise EKarosProtocol.Create('Not shop buy');
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2);
  Result.CharacterID:=TB1008Wire.ReadBE32(P,6);
  Result.NpcHandle:=TB1008Wire.ReadBE32(P,10);
  Result.ItemID:=TB1008Wire.ReadBE32(P,14);Result.Code:=P[18];
  N:=(UInt64(TB1008Wire.ReadBE32(P,19)) shl 32) or TB1008Wire.ReadBE32(P,23);
  Move(N,Result.Amount,8);
end;

function TB1008ShopBuy.Quantity:Cardinal;
begin
  Result:=0;
  // Direct purchase 0x50DF27 uses 09/-1; quantity dialog 0x47CA64
  // sends 20/positive amount. The success handler also normalizes -1 to 1.
  if (Code=9) and (Amount=-1) then Result:=1
  else if (Code=$20) and (Amount>0) and (Amount<=100) then Result:=Amount;
end;

function TB1008ShopBuy.Supported:Boolean;
begin Result:=(CharacterID=1) and TB1008Shop.Sells(NpcHandle,ItemID) and (Quantity>0);end;

function TB1008ShopBuy.Ack:TBytes;
begin
  if not Supported then raise EKarosProtocol.Create('Unsupported purchase acknowledgement');
  // 0x526E39: 20 is success; inventory remains authoritative via 06/06/07.
  SetLength(Result,27);Result[0]:=6;Result[1]:=$0D;
  BE(Result,2,Timestamp);BE(Result,6,CharacterID);BE(Result,10,NpcHandle);
  BE(Result,14,ItemID);Result[18]:=$20;BE(Result,19,0);BE(Result,23,Quantity);
end;

class function TB1008Shop.Sells(NpcHandle,ItemID:Cardinal):Boolean;
var M:TB1008Merchant;ID:Cardinal;
begin
  Result:=False;if not Find(NpcHandle,M) then Exit;
  for ID in M.Items do if ID=ItemID then Exit(True);
end;

class function TB1008ShopSell.Parse(const P:TBytes):TB1008ShopSell;
var N:UInt64;
begin
  // 0x47C38B: five BE32 fields, byte code, signed BE64 quantity.
  // Live 20260921-032410: 1/1/3/80008/121/0x21/2 for both RMB and drag.
  if (Length(P)<>35) then raise EKarosProtocol.Create('Invalid shop sell size');
  if (P[0]<>6) or (P[1]<>$0E) then raise EKarosProtocol.Create('Not shop sell');
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2);
  Result.CharacterID:=TB1008Wire.ReadBE32(P,6);
  Result.Page:=TB1008Wire.ReadBE32(P,10);Result.Slot:=TB1008Wire.ReadBE32(P,14);
  Result.ItemID:=TB1008Wire.ReadBE32(P,18);Result.NpcHandle:=TB1008Wire.ReadBE32(P,22);
  Result.Code:=P[26];N:=(UInt64(TB1008Wire.ReadBE32(P,27)) shl 32) or TB1008Wire.ReadBE32(P,31);
  Move(N,Result.Amount,8);
end;

function TB1008ShopSell.Supported:Boolean;
begin
  Result:=(CharacterID=1) and (Page=1) and (Slot<B1008BagSlots) and
    (ItemID<>0) and (ItemID<>B1008CaratID) and (Code=$21) and
    (Amount>0) and (Amount<=B1008CaratLimit);
end;

function TB1008ShopSell.Ack:TBytes;
begin
  if not Supported then raise EKarosProtocol.Create('Unsupported sale acknowledgement');
  // 0x526F5D only displays a message using local price*quantity. Inventory
  // and physical Carat/HUD are updated separately, via authoritative 06/06/07.
  Result:=nil;SetLength(Result,35);Result[0]:=6;Result[1]:=$0E;
  BE(Result,2,Timestamp);BE(Result,6,CharacterID);BE(Result,10,Page);
  BE(Result,14,Slot);BE(Result,18,ItemID);BE(Result,22,NpcHandle);
  Result[26]:=$21;BE(Result,27,Cardinal(UInt64(Amount) shr 32));
  BE(Result,31,Cardinal(UInt64(Amount) and $FFFFFFFF));
end;

class function TB1008Shop.CanSellAt(MapID,NpcHandle:Cardinal;X,Z,Y:Single):Boolean;
var M:TB1008Merchant;
begin
  Result:=False;
  if not Find(NpcHandle,M) or (MapID<>M.MapID) or
    IsNan(X) or IsNan(Z) or IsNan(Y) or IsInfinite(X) or IsInfinite(Z) or IsInfinite(Y) then Exit;
  // NPC interaction range from 0x4FD1CB / 0x66C494 (10000 square units).
  Result:=(Sqr(Double(X)-M.X)+Sqr(Double(Z)-M.Z)+Sqr(Double(Y)-M.Y)<=10000);
end;

end.
