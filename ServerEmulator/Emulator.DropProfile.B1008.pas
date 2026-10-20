unit Emulator.DropProfile.B1008;

interface

uses System.SysUtils,Emulator.Rates.B1008;

type
  TB1008RolledDrop = record
    ItemID,Amount:Cardinal;
    Category:string;
  end;
  TB1008DropProfile = class
  private
    class var FCategoryWeights:array[0..2] of Integer;
    class var FGearChance:Integer;
    class var FArmor,FWeapon,FOwn,FOther,FLevel,FMinMoney,FMaxMoney,FQuantity:Integer;
    class var FIDs,FWeights:array[0..2] of TArray<Integer>;
    class var FEnabled:array[0..2] of Boolean;
    class var FTiers:array[1..20,0..2] of Integer;
  public
    class constructor Create;
    class procedure EnsureReady;static;
    class function Tier(Level,Roll100:Integer):Integer;static;
    class function ClassForRoll(PlayerClass:Word;Roll:Integer):Word;static;
    class function GearForRoll(Armor:Boolean;Level:Integer;ClassID:Word;
      GroupRoll,ItemRoll:Integer):Cardinal;static;
    class function RollSpider(var State:Cardinal;PlayerClass:Word):TArray<TB1008RolledDrop>;static;
    class function RollMob(var State:Cardinal;PlayerClass:Word;MobID:Cardinal):TArray<TB1008RolledDrop>;overload;static;
    class function RollMob(var State:Cardinal;PlayerClass:Word;MobID:Cardinal;
      const Rates:TB1008Rates):TArray<TB1008RolledDrop>;overload;static;
  end;

implementation

uses System.IniFiles,Emulator.Items.B1008,Emulator.Berneo.B1008;

function Integers(const S:string):TArray<Integer>;
var Parts:TArray<string>;I:Integer;
begin
  if Trim(S)='' then Exit(nil);
  Parts:=S.Split([',']);SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=StrToInt(Trim(Parts[I]));
end;

class constructor TB1008DropProfile.Create;
const Names:array[0..2] of string=('ordinary','craft','potion');
  Classes:array[0..2] of Word=(100,300,500);
var Ini:TMemIniFile;I,J,K,C,T,N:Integer;A:TArray<Integer>;D:TB1008ItemDefinition;
  Counts:array[0..7] of Integer;M:TB1008BerneoMob;
begin
  Ini:=TMemIniFile.Create(TB1008Items.DataPath('drop-v1.ini'),TEncoding.UTF8);
  try
    if Ini.ReadString('drop','profile','')<>'karos-istoki-drop-v1' then raise Exception.Create('Missing/invalid drop profile');
    for I:=0 to 2 do begin
      FCategoryWeights[I]:=Ini.ReadInteger('drop',Names[I]+'_weight',-1);
      if (FCategoryWeights[I]<0) or (FCategoryWeights[I]>10000) then raise Exception.Create('Invalid drop category weight');
    end;
    FGearChance:=Ini.ReadInteger('drop','equipment_bp',-1);
    if (FGearChance<0) or (FGearChance>10000) then raise Exception.Create('Invalid equipment chance');
    FArmor:=Ini.ReadInteger('drop','armor_weight',0);FWeapon:=Ini.ReadInteger('drop','weapon_weight',0);
    FOwn:=Ini.ReadInteger('drop','own_class_weight',0);FOther:=Ini.ReadInteger('drop','other_class_weight',0);
    for N in TArray<Integer>.Create(FArmor,FWeapon,FOwn,FOther) do
      if (N<1) or (N>10000) then raise Exception.Create('Invalid drop weight');
    FLevel:=Ini.ReadInteger('spider','monster_level',0);
    FMinMoney:=Ini.ReadInteger('spider','carat_min',0);FMaxMoney:=Ini.ReadInteger('spider','carat_max',0);
    FQuantity:=Ini.ReadInteger('spider','item_quantity',0);
    if (FLevel<1) or (FLevel>15) or (FMinMoney<1) or (FMaxMoney<FMinMoney) or
      (FMaxMoney>100000000) or (FQuantity<1) then raise Exception.Create('Invalid spider drop settings');
    for I:=0 to 2 do begin
      FEnabled[I]:=Ini.ReadBool('spider',Names[I]+'_enabled',True);
      FIDs[I]:=Integers(Ini.ReadString('spider',Names[I]+'_ids',''));
      FWeights[I]:=Integers(Ini.ReadString('spider',Names[I]+'_weights',''));
      // Species with no canon-backed pool do not inherit later-build items.
      // Guaranteed bags select only among the species' available categories.
      if not FEnabled[I] then begin
        if (Length(FIDs[I])<>0) or (Length(FWeights[I])<>0) then
          raise Exception.Create('Disabled category must have an empty species pool');
        Continue;
      end;
      if (Length(FIDs[I])=0) or (Length(FIDs[I])<>Length(FWeights[I])) then raise Exception.Create('Empty/mismatched drop pool');
      for J:=0 to High(FIDs[I]) do begin
        D:=TB1008Items.Get(FIDs[I][J]);
        if (D.Slot<>0) or (D.ID=999999) or (Cardinal(FQuantity)>D.StackLimit) or
          (FWeights[I][J]<1) or (FWeights[I][J]>10000) or
          ((I=2)<>TB1008Items.IsPotion(D.ID)) then raise Exception.Create('Invalid category item');
        for K:=0 to J-1 do if FIDs[I][K]=FIDs[I][J] then raise Exception.Create('Duplicate pool item');
      end;
    end;
    for I:=1 to 20 do begin
      A:=Integers(Ini.ReadString('tiers',IntToStr(I),''));
      if (Length(A)<>3) or (A[0]<5) or (A[1]<A[0]) or (A[2]<1) or (A[2]>100) then
        raise Exception.Create('Invalid gear level row');
      for J:=0 to 2 do FTiers[I,J]:=A[J];
      // Reject incomplete catalogs before admitting a kill: every class and
      // every armor slot must exist at every configured tier. No fallback roll.
      for K:=0 to 1 do begin
        T:=A[K];
        for C in Classes do begin
          FillChar(Counts,SizeOf(Counts),0);
          for D in TB1008Items.All do if not D.InventoryOnly and (D.RequiredLevel=T) and (D.ClassID=C) then Inc(Counts[D.Slot]);
          for J:=1 to 4 do if Counts[J]<>1 then raise Exception.Create('Expected one armor template per class/tier/slot');
          if ((C=500) and (Counts[7]<>1)) or ((C<>500) and (Counts[7]<>2)) then
            raise Exception.Create('Incomplete weapon subtype pool');
          // This catalog deliberately has exactly one unenchanted template per
          // subtype. Reject duplicates instead of silently biasing selection.
          for D in TB1008Items.All do if not D.InventoryOnly and (D.RequiredLevel=T) and (D.ClassID=C) and (D.Slot=7) then begin
            N:=0;
            for var Other in TB1008Items.All do if not Other.InventoryOnly and (Other.RequiredLevel=T) and
              (Other.ClassID=C) and (Other.Slot=7) and (Other.Subtype=D.Subtype) then Inc(N);
            if N<>1 then raise Exception.Create('Duplicate weapon subtype');
          end;
        end;
      end;
    end;
  finally Ini.Free;end;
  // A guaranteed regular bag must always have an eligible pool. Reject bad
  // configuration before starting the server, never during a lethal hit.
  for M in TB1008Berneo.Mobs do begin
    N:=0;
    for I:=0 to 2 do
      if M.Definition.MobID=120 then begin
        if Length(FIDs[I])>0 then Inc(N,FCategoryWeights[I]);
      end else if Length(M.IDs[I])>0 then Inc(N,FCategoryWeights[I]);
    if N=0 then raise Exception.Create('Monster has no weighted regular drop pool');
  end;
end;

class procedure TB1008DropProfile.EnsureReady;
begin
  TB1008Berneo.Mobs;
  // Calling this before the server opens its listener forces class-constructor
  // validation. Bad files must never fail for the first time on a lethal hit.
end;

class function TB1008DropProfile.Tier(Level,Roll100:Integer):Integer;
begin
  if (Level<1) or (Level>20) or (Roll100<0) or (Roll100>=100) then raise EArgumentException.Create('Unconfigured monster level or tier roll');
  if Roll100<FTiers[Level,2] then Result:=FTiers[Level,0] else Result:=FTiers[Level,1];
end;

class function TB1008DropProfile.ClassForRoll(PlayerClass:Word;Roll:Integer):Word;
const Classes:array[0..2] of Word=(100,300,500);
var C:Word;W:Integer;
begin
  if not ((PlayerClass=100) or (PlayerClass=300) or (PlayerClass=500)) or
    (Roll<0) or (Roll>=FOwn+2*FOther) then raise EArgumentException.Create('Invalid drop class/roll');
  for C in Classes do begin
    if C=PlayerClass then W:=FOwn else W:=FOther;
    if Roll<W then Exit(C);Dec(Roll,W);
  end;
  raise Exception.Create('Class weight error');
end;

class function TB1008DropProfile.GearForRoll(Armor:Boolean;Level:Integer;ClassID:Word;
  GroupRoll,ItemRoll:Integer):Cardinal;
var D:TB1008ItemDefinition;Groups,IDs:TArray<Integer>;G,I,N,Group:Integer;Found:Boolean;
begin
  Groups:=nil;IDs:=nil;
  for D in TB1008Items.All do if not D.InventoryOnly and (D.RequiredLevel=Level) and (D.ClassID=ClassID) and
    (((D.Slot=7) and not Armor) or ((D.Slot in [1,2,3,4]) and Armor)) then begin
    if Armor then G:=D.Slot else G:=D.Subtype;
    Found:=False;for I in Groups do if I=G then Found:=True;
    if not Found then begin N:=Length(Groups);SetLength(Groups,N+1);Groups[N]:=G;end;
  end;
  if (Length(Groups)=0) or (GroupRoll<0) or (ItemRoll<0) then raise Exception.Create('Empty gear pool or invalid roll');
  Group:=Groups[GroupRoll mod Length(Groups)];
  for D in TB1008Items.All do if not D.InventoryOnly and (D.RequiredLevel=Level) and (D.ClassID=ClassID) and
    ((Armor and (D.Slot=Group) and (D.Slot in [1,2,3,4])) or
    (not Armor and (D.Slot=7) and (D.Subtype=Group))) then begin
    N:=Length(IDs);SetLength(IDs,N+1);IDs[N]:=D.ID;
  end;
  Result:=IDs[ItemRoll mod Length(IDs)];
end;

class function TB1008DropProfile.RollSpider(var State:Cardinal;PlayerClass:Word):TArray<TB1008RolledDrop>;
begin Result:=RollMob(State,PlayerClass,120);end;

class function TB1008DropProfile.RollMob(var State:Cardinal;PlayerClass:Word;MobID:Cardinal):TArray<TB1008RolledDrop>;
begin Result:=RollMob(State,PlayerClass,MobID,TB1008Rates.Default);end;

class function TB1008DropProfile.RollMob(var State:Cardinal;PlayerClass:Word;MobID:Cardinal;
  const Rates:TB1008Rates):TArray<TB1008RolledDrop>;
const Names:array[0..2] of string=('ordinary','craft','potion');
var I,J,W,R,L,Quantity:Integer;C:Word;Armor:Boolean;M:TB1008BerneoMob;
  K,N,Cash,Total:Integer;
  function Draw(MaxExclusive:Integer):Integer;
  var Limit,Sample:Cardinal;
  begin
    if State=0 then State:=$9E3779B9;
    Limit:=High(Cardinal)-(High(Cardinal) mod Cardinal(MaxExclusive));
    repeat
      State:=State xor (State shl 13);State:=State xor (State shr 17);
      State:=State xor (State shl 5);Sample:=State-1;
    until Sample<Limit;
    Result:=Sample mod Cardinal(MaxExclusive);
  end;
  procedure Add(ID,Amount:Cardinal;const Category:string);
  var N:Integer;
  begin
    N:=Length(Result);SetLength(Result,N+1);Result[N].ItemID:=ID;
    Result[N].Amount:=Amount;Result[N].Category:=Category;
  end;
begin
  Result:=nil;Rates.Validate;ClassForRoll(PlayerClass,0); // Fail before any RNG draws.
  M:=TB1008Berneo.Mob(MobID);Quantity:=1;
  if MobID=120 then begin // Retain the already-tested configurable spider profile.
    M.Level:=FLevel;M.CaratMin:=FMinMoney;M.CaratMax:=FMaxMoney;Quantity:=FQuantity;
    for I:=0 to 2 do begin M.IDs[I]:=FIDs[I];M.Weights[I]:=FWeights[I];end;
  end;
  Cash:=TB1008Rates.Scale(M.CaratMin+Draw(M.CaratMax-M.CaratMin+1),Rates.Carat,100000000);
  if Cash>0 then Add(999999,Cash,'currency');
  // One shared budget for ordinary items, materials and potions. Integer
  // rates give an exact bag count; only the fractional remainder is rolled.
  Total:=0;for I:=0 to 2 do if Length(M.IDs[I])>0 then Inc(Total,FCategoryWeights[I]);
  N:=Rates.Drop div B1008RateOne;
  if (Rates.Drop mod B1008RateOne<>0) and
    (Draw(B1008RateOne)<Rates.Drop mod B1008RateOne) then Inc(N);
  for K:=1 to N do begin
    R:=Draw(Total);
    for I:=0 to 2 do if Length(M.IDs[I])>0 then begin
      if R>=FCategoryWeights[I] then begin Dec(R,FCategoryWeights[I]);Continue;end;
      W:=0;for J in M.Weights[I] do Inc(W,J);R:=Draw(W);
      for J:=0 to High(M.IDs[I]) do begin
        if R<M.Weights[I][J] then begin Add(M.IDs[I][J],Quantity,Names[I]);Break;end;
        Dec(R,M.Weights[I][J]);
      end;
      Break;
    end;
  end;
  // Exactly one equipment roll, independent of regular bags. Never emit
  // multiple equipment pieces, even when the scaled chance reaches 100%.
  if Draw(10000)<TB1008Rates.Scale(FGearChance,Rates.Drop,10000) then begin
    Armor:=Draw(FArmor+FWeapon)<FArmor;L:=Tier(M.Level,Draw(100));
    C:=ClassForRoll(PlayerClass,Draw(FOwn+2*FOther));
    // All bound pools have 1 template per group; group count divides 4
    // (four armor slots; two melee subtypes; one bow). No template-count bias.
    if Armor then W:=4 else if C=500 then W:=1 else W:=2;
    if Armor then Add(GearForRoll(True,L,C,Draw(W),0),1,'armor')
    else Add(GearForRoll(False,L,C,Draw(W),0),1,'weapon');
  end;
end;

end.
