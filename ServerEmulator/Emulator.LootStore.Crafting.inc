function TB1008LootStore.CraftItem(Owner:TObject;const Receipt:string;const Request:TB1008CraftRequest;
  out Updated:TArray<TB1008BagItem>):Byte;
var Recipe:TB1008CraftRecipe;Ingredient:TB1008CraftIngredient;Npc:TB1008Npc;
  Allowed:Boolean;Count:Int64;
begin
  Result:=$4C;Updated:=nil;
  if (Receipt='') or (Request.CharacterID<>1) or (Request.Code<>$48) or
    not TB1008Crafting.Find(Request.RecipeID,Recipe) then Exit;
  Allowed:=False;
  for Npc in TB1008Npcs.All do if Npc.Handle=Request.NpcHandle then begin
    Allowed:=TB1008Crafting.Allows(Recipe,Npc.ID);Break;
  end;
  if not Allowed then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM operations WHERE receipt=:r',['craft:'+Receipt]))<>0 then Exit;
      Count:=Int64(FDB.ExecSQLScalar('SELECT COALESCE(SUM(amount),0) FROM inventory WHERE item_id=999999'));
      if Count<Recipe.Cost then begin Result:=$49;Exit;end;
      for Ingredient in Recipe.Ingredients do begin
        if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM inventory b JOIN item_instances p ON p.instance_id=b.instance_id '+
          'WHERE b.item_id=:i AND (p.grade<>0 OR p.data8<>0 OR p.data12<>0 OR p.gem0<>0 OR p.gem1<>0 OR p.gem2<>0)',
          [Int64(Ingredient.ID)]))<>0 then Exit;
        Count:=Int64(FDB.ExecSQLScalar('SELECT COALESCE(SUM(amount),0) FROM inventory WHERE item_id=:i',[Int64(Ingredient.ID)]));
        if Count<Ingredient.Amount then begin Result:=$4B;Exit;end;
      end;
      for Ingredient in Recipe.Ingredients do
        if not TakeQuestItem(Ingredient.ID,Ingredient.Amount,Updated) then raise Exception.Create('Craft ingredient changed inside transaction');
      if (Recipe.Cost>0) and not TakeQuestItem(B1008CaratID,Recipe.Cost,Updated) then
        raise Exception.Create('Craft wallet changed inside transaction');
      // Released component cells are usable by the result. Failure restores
      // every consumed component, currency cell and operation receipt.
      if not AddQuestItem(Recipe.ResultItemID,1,Updated) then begin Result:=$4A;Exit;end;
      FDB.ExecSQL('INSERT INTO operations VALUES(:r)',['craft:'+Receipt]);
      FDB.Commit;Result:=$48;
    finally
      if FDB.InTransaction then FDB.Rollback;
      if Result<>$48 then Updated:=nil;
    end;
  finally FLock.Release;end;
end;
