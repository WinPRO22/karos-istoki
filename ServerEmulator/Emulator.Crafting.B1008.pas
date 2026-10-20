unit Emulator.Crafting.B1008;

interface

uses System.SysUtils;

const
  B1008CraftSuccess=$48;
  B1008CraftInsufficientCarat=$49;
  B1008CraftInventoryFull=$4A;
  B1008CraftInsufficientMaterials=$4B;
  B1008CraftRejected=$4C;

type
  TB1008CraftRequest=record
    Timestamp,CharacterID,NpcHandle,RecipeID:Cardinal;
    Code:Byte;
    class function Parse(const P:TBytes):TB1008CraftRequest;static;
    function Reply(ACode:Byte):TBytes;
  end;
  TB1008CraftIngredient=record
    ID,Amount:Cardinal;
  end;
  TB1008CraftRecipe=record
    ID,ResultItemID,Cost:Cardinal;
    Ingredients:TArray<TB1008CraftIngredient>;
    NpcIDs:TArray<Cardinal>;
  end;
  TB1008Crafting=class
  private
    class var FRecipes:TArray<TB1008CraftRecipe>;
  public
    class constructor Create;
    class function Find(ID:Cardinal;out Recipe:TB1008CraftRecipe):Boolean;static;
    class function Allows(const Recipe:TB1008CraftRecipe;NpcID:Cardinal):Boolean;static;
  end;

implementation

uses System.IOUtils,System.JSON,Emulator.Protocol.B1008,Emulator.Items.B1008;

procedure CraftBE(var P:TBytes;Offset:Integer;Value:Cardinal);
begin
  P[Offset]:=Byte(Value shr 24);P[Offset+1]:=Byte((Value shr 16) and 255);
  P[Offset+2]:=Byte((Value shr 8) and 255);P[Offset+3]:=Byte(Value and 255);
end;

class function TB1008CraftRequest.Parse(const P:TBytes):TB1008CraftRequest;
begin
  // Native serializer 49ABDD, parser 525AB3. Each packet is one attempt;
  // 49BE24 sends repeated packets for the quantity selected in the UI.
  if Length(P)<>19 then raise EKarosProtocol.Create('Invalid crafting size');
  if (P[0]<>6) or (P[1]<>$16) then raise EKarosProtocol.Create('Not crafting');
  Result.Timestamp:=TB1008Wire.ReadBE32(P,2);
  Result.CharacterID:=TB1008Wire.ReadBE32(P,6);
  Result.NpcHandle:=TB1008Wire.ReadBE32(P,10);
  Result.RecipeID:=TB1008Wire.ReadBE32(P,14);Result.Code:=P[18];
end;

function TB1008CraftRequest.Reply(ACode:Byte):TBytes;
begin
  if (ACode<B1008CraftSuccess) or (ACode>B1008CraftRejected) then
    raise EKarosProtocol.Create('Invalid crafting result');
  Result:=nil;SetLength(Result,19);Result[0]:=6;Result[1]:=$16;
  CraftBE(Result,2,Timestamp);CraftBE(Result,6,CharacterID);
  CraftBE(Result,10,NpcHandle);CraftBE(Result,14,RecipeID);Result[18]:=ACode;
end;

function CraftNumber(Value:TJSONValue;const Field:string):Cardinal;
var N:Int64;
begin
  if not (Value is TJSONNumber) then raise Exception.Create('Invalid crafting number: '+Field);
  if not TryStrToInt64(Value.Value,N) then raise Exception.Create('Invalid crafting integer: '+Field);
  if (N<0) or ((N=0) and (Field<>'cost')) or (N>High(Cardinal)) then raise Exception.Create('Invalid crafting range: '+Field);
  Result:=Cardinal(N);
end;

function CraftField(Row:TJSONValue;const Field:string):Cardinal;
begin
  if not (Row is TJSONObject) then raise Exception.Create('Invalid crafting record');
  Result:=CraftNumber(TJSONObject(Row).GetValue(Field),Field);
end;

class constructor TB1008Crafting.Create;
var Root:TJSONObject;Parsed,V:TJSONValue;Rows,Ingredients,Npcs:TJSONArray;
  R:TB1008CraftRecipe;D:TB1008ItemDefinition;I,J,K:Integer;
begin
  Parsed:=TJSONObject.ParseJSONValue(TFile.ReadAllText(TB1008Items.DataPath('crafting-v1.json'),TEncoding.UTF8));
  if not (Parsed is TJSONObject) then begin Parsed.Free;raise Exception.Create('Invalid crafting catalog');end;
  Root:=TJSONObject(Parsed);
  try
    if Root.GetValue<string>('build')<>'b1008' then raise Exception.Create('Wrong crafting catalog build');
    Rows:=Root.GetValue<TJSONArray>('recipes');
    if (Rows.Count=0) or (Rows.Count>119) then raise Exception.Create('Invalid crafting recipe count');
    SetLength(FRecipes,Rows.Count);I:=0;
    for V in Rows do begin
      R:=Default(TB1008CraftRecipe);R.ID:=CraftField(V,'id');
      R.ResultItemID:=CraftField(V,'resultItemId');R.Cost:=CraftField(V,'cost');
      // The archived b1008 rows guarantee success. One output per request
      // is the explicit local policy, not an extracted result-count field.
      if (CraftField(V,'chance')<>10000) or (CraftField(V,'resultCount')<>1) or
        (R.Cost>High(Integer)) then raise Exception.Create('Unsupported crafting policy');
      if not TB1008Items.Find(R.ResultItemID,D) then raise Exception.Create('Unsupported crafting result');
      for J:=0 to I-1 do if FRecipes[J].ID=R.ID then raise Exception.Create('Duplicate crafting recipe');
      Ingredients:=V.GetValue<TJSONArray>('ingredients');
      if (Ingredients.Count=0) or (Ingredients.Count>20) then raise Exception.Create('Invalid crafting ingredient count');
      SetLength(R.Ingredients,Ingredients.Count);
      for J:=0 to Ingredients.Count-1 do begin
        R.Ingredients[J].ID:=CraftField(Ingredients.Items[J],'id');
        R.Ingredients[J].Amount:=CraftField(Ingredients.Items[J],'amount');
        if (R.Ingredients[J].Amount>High(Integer)) or
          not TB1008Items.Find(R.Ingredients[J].ID,D) then raise Exception.Create('Unsupported crafting ingredient');
        for K:=0 to J-1 do if R.Ingredients[K].ID=R.Ingredients[J].ID then
          raise Exception.Create('Duplicate crafting ingredient');
      end;
      Npcs:=V.GetValue<TJSONArray>('npcIds');
      if (Npcs.Count=0) or (Npcs.Count>771) then raise Exception.Create('Invalid crafting NPC count');
      SetLength(R.NpcIDs,Npcs.Count);
      for J:=0 to Npcs.Count-1 do begin
        R.NpcIDs[J]:=CraftNumber(Npcs.Items[J],'npcIds');
        for K:=0 to J-1 do if R.NpcIDs[K]=R.NpcIDs[J] then raise Exception.Create('Duplicate crafting NPC');
      end;
      FRecipes[I]:=R;Inc(I);
    end;
  finally Root.Free;end;
end;

class function TB1008Crafting.Find(ID:Cardinal;out Recipe:TB1008CraftRecipe):Boolean;
var R:TB1008CraftRecipe;
begin
  for R in FRecipes do if R.ID=ID then begin
    Recipe:=R;Recipe.Ingredients:=Copy(R.Ingredients);Recipe.NpcIDs:=Copy(R.NpcIDs);Exit(True);
  end;
  Recipe:=Default(TB1008CraftRecipe);Result:=False;
end;

class function TB1008Crafting.Allows(const Recipe:TB1008CraftRecipe;NpcID:Cardinal):Boolean;
var ID:Cardinal;
begin
  for ID in Recipe.NpcIDs do if ID=NpcID then Exit(True);
  Result:=False;
end;

end.
