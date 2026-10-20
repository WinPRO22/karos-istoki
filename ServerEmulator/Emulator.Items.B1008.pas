unit Emulator.Items.B1008;

interface

uses System.SysUtils;

type
  TB1008ItemDefinition = record
    ID,StackLimit,OriginalSellPrice,SellPrice,BuyPrice:Cardinal;
    Name:string;
    ClassID,RequiredLevel:Word;
    Slot,Subtype:Byte;
    InventoryOnly,QuestItem:Boolean;
    AttackMin100,AttackMax100,Defense,HealHP,HealMP:Integer;
  end;
  TB1008Items = class
  private
    class var FItems:TArray<TB1008ItemDefinition>;
  public
    class constructor Create;
    class function All:TArray<TB1008ItemDefinition>;static;
    class function Find(ID:Cardinal;out Item:TB1008ItemDefinition):Boolean;static;
    class function Get(ID:Cardinal):TB1008ItemDefinition;static;
    class function StackLimit(ID:Cardinal):Cardinal;static;
    class function IsPotion(ID:Cardinal):Boolean;static;
    class function IsQuestItem(ID:Cardinal):Boolean;static;
    class function DataPath(const Name:string):string;static;
  end;

implementation

uses System.IOUtils,System.JSON;

class function TB1008Items.DataPath(const Name:string):string;
var Dir,Parent:string;I:Integer;
begin
  Dir:=ExtractFileDir(ExpandFileName(ParamStr(0)));
  for I:=0 to 6 do begin
    if FileExists(TPath.Combine(Dir,'KarosOldEmulator.dpr')) then
      Exit(TPath.Combine(Dir,'data\b1008\'+Name));
    Parent:=ExtractFileDir(Dir);if SameText(Dir,Parent) then Break;Dir:=Parent;
  end;
  raise Exception.Create('Cannot locate b1008 data directory');
end;

class constructor TB1008Items.Create;
var Root:TJSONObject;Rows:TJSONArray;V:TJSONValue;D:TB1008ItemDefinition;I,J,FileIndex:Integer;
const CatalogFiles:array[0..3] of string=('drop-catalog.json','quest-items-v1.json','shop-items-v1.json','crafting-items-v1.json');
begin
  I:=0;
  for FileIndex:=0 to High(CatalogFiles) do begin
  Root:=TJSONObject.ParseJSONValue(TFile.ReadAllText(DataPath(CatalogFiles[FileIndex]),TEncoding.UTF8)) as TJSONObject;
  if Root=nil then raise Exception.Create('Invalid b1008 item catalog');
  try
    if Root.GetValue<string>('build')<>'b1008' then raise Exception.Create('Wrong item catalog build');
    Rows:=Root.GetValue<TJSONArray>('items');SetLength(FItems,Length(FItems)+Rows.Count);
    for V in Rows do begin
      D:=Default(TB1008ItemDefinition);
      D.ID:=V.GetValue<Cardinal>('id');D.Name:=V.GetValue<string>('name');
      D.StackLimit:=V.GetValue<Cardinal>('stackLimit');
      D.ClassID:=V.GetValue<Word>('classId');D.Slot:=V.GetValue<Byte>('slot');
      D.RequiredLevel:=V.GetValue<Word>('requiredLevel');D.Subtype:=V.GetValue<Byte>('subtype');
      D.InventoryOnly:=V.GetValue<Boolean>('inventoryOnly',False);
      D.QuestItem:=V.GetValue<Boolean>('questItem',False);
      D.AttackMin100:=V.GetValue<Integer>('attackMin100');D.AttackMax100:=V.GetValue<Integer>('attackMax100');
      D.Defense:=V.GetValue<Integer>('defense');D.HealHP:=V.GetValue<Integer>('healHP');D.HealMP:=V.GetValue<Integer>('healMP');
      D.OriginalSellPrice:=V.GetValue<Cardinal>('originalSellPrice');
      D.SellPrice:=V.GetValue<Cardinal>('sellPrice');
      D.BuyPrice:=V.GetValue<Cardinal>('buyPrice');
      if (D.ID=0) or (D.Name='') or (D.StackLimit=0) or (D.StackLimit>100000000) or
        (D.AttackMin100<0) or (D.AttackMax100<D.AttackMin100) or (D.Defense<0) or
        (D.HealHP<0) or (D.HealMP<0) or (D.SellPrice>100000000) or
        (D.OriginalSellPrice>100000000) or (D.BuyPrice>100000000) then raise Exception.Create('Invalid item definition');
      if D.SellPrice<>D.OriginalSellPrice then
        raise Exception.Create('All sale prices must remain original b1008');
      if (D.Slot<>0) and not D.InventoryOnly and (not
        (((D.Slot in [1,2,3,4,7]) and ((D.ClassID=100) or (D.ClassID=300) or (D.ClassID=500))) or
         ((D.Slot in [22,24]) and (D.ClassID=0)) or
         ((D.Slot=7) and (D.ClassID=0) and (D.Subtype=17) and
          ((D.ID=30001) or (D.ID=30002)))) or
        (D.RequiredLevel=0) or (D.StackLimit<>1)) then raise Exception.Create('Invalid equipment definition');
      // Local inventory policy; source catalog retains original reference values.
      if D.ID=999999 then D.StackLimit:=High(Integer)
      else if D.Slot<>0 then D.StackLimit:=1
      else D.StackLimit:=100;
      for J:=0 to I-1 do if FItems[J].ID=D.ID then raise Exception.Create('Duplicate item ID');
      FItems[I]:=D;Inc(I);
    end;
  finally Root.Free;end;
  end;
end;

class function TB1008Items.All:TArray<TB1008ItemDefinition>;
begin Result:=Copy(FItems);end;
class function TB1008Items.Find(ID:Cardinal;out Item:TB1008ItemDefinition):Boolean;
var D:TB1008ItemDefinition;
begin
  for D in FItems do if D.ID=ID then begin Item:=D;Exit(True);end;
  Item:=Default(TB1008ItemDefinition);Result:=False;
end;
class function TB1008Items.Get(ID:Cardinal):TB1008ItemDefinition;
begin if not Find(ID,Result) then raise EArgumentException.CreateFmt('Unsupported b1008 item %d',[ID]);end;
class function TB1008Items.StackLimit(ID:Cardinal):Cardinal;
var D:TB1008ItemDefinition;
begin if Find(ID,D) then Result:=D.StackLimit else Result:=0;end;
class function TB1008Items.IsPotion(ID:Cardinal):Boolean;
var D:TB1008ItemDefinition;
begin Result:=Find(ID,D) and ((D.HealHP>0) or (D.HealMP>0));end;

class function TB1008Items.IsQuestItem(ID:Cardinal):Boolean;
var D:TB1008ItemDefinition;
begin Result:=Find(ID,D) and D.QuestItem;end;

end.
