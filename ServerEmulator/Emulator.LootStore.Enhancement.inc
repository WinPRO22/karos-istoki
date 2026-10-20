function TB1008LootStore.EnhanceItem(Owner:TObject;const Receipt:string;const Request:TB1008EnhancementRequest;
  out Updated:TArray<TB1008BagItem>;out Gear:TB1008EquipmentItem):Byte;
var A,B:TB1008BagItem;E:TB1008EquipmentItem;Found:Boolean;
  Minimum,Maximum,Defense:Integer;
begin
  Updated:=nil;Gear:=Default(TB1008EquipmentItem);
  if Request.Kind=$19 then Result:=$57 else Result:=$51;
  if (Receipt='') or (Request.CharacterID<>1) or (Request.PageA<>1) or
    (Request.SlotA>=B1008BagSlots) or (Request.PageB>1) or (Request.SlotB>255) or
    ((Request.Kind=$17) and (Request.Code<>$4D)) or
    ((Request.Kind=$19) and ((Request.Code<>$56) or (Request.Index>1))) or
    not (Request.Kind in [$17,$19]) then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM operations WHERE receipt=:r',['enhance:'+Receipt]))<>0 then Exit;
      A:=FindSlot(Request.SlotA);if (A.Amount=0) or (A.ItemID<>Request.ItemA) then Exit;
      if Request.PageB=1 then begin
        if (Request.SlotB>=B1008BagSlots) or (Request.SlotB=Request.SlotA) then Exit;
        B:=FindSlot(Request.SlotB);
      end else begin
        B:=Default(TB1008BagItem);Found:=False;
        for E in ReadEquipment do if E.Slot=Request.SlotB then begin
          B.ItemID:=E.ItemID;B.Amount:=1;B.Slot:=E.Slot;B.Properties:=E.Properties;Found:=True;Break;
        end;
        if not Found then Exit;
      end;
      if (B.Amount<>1) or (B.ItemID<>Request.ItemB) then Exit;
      if Request.Kind=$17 then begin
        if not TB1008ItemEnhancement.ScrollMatches(A.ItemID,B.ItemID) then begin Result:=$50;Exit;end;
        if (B.Properties.NativeGrade<0) or (B.Properties.NativeGrade>=3) then begin Result:=$4E;Exit;end;
        if not TB1008ItemEnhancement.FindStats(B.ItemID,B.Properties.NativeGrade+1,Minimum,Maximum,Defense) then Exit;
        Inc(B.Properties.NativeGrade);Result:=$4D;
      end else begin
        // First supported accessory chain: b1008 Minor Diamond gives STR+1.
        // Other primary-stat gems await their derived-stat balance contract.
        if not (((A.ItemID=55001) and (B.ItemID=51001)) or
          ((A.ItemID=55200) and (B.ItemID=2999) and (Request.PageB=1))) then begin Result:=$50;Exit;end;
        B.Properties.GemIDs[Request.Index]:=A.ItemID;Result:=$56;
      end;
      SaveProperties(B.ItemID,B.Properties);
      Dec(A.Amount);SaveItem(A);SetLength(Updated,1);Updated[0]:=A;
      if Request.PageB=1 then begin
        SaveItem(B);SetLength(Updated,2);Updated[1]:=B;
      end else begin
        FDB.ExecSQL('UPDATE equipment SET instance_id=:i WHERE slot=:s',[B.Properties.InstanceID,Integer(B.Slot)]);
        Gear.ItemID:=B.ItemID;Gear.Slot:=B.Slot;Gear.Properties:=B.Properties;
      end;
      FDB.ExecSQL('INSERT INTO operations VALUES(:r)',['enhance:'+Receipt]);FDB.Commit;
    finally
      if FDB.InTransaction then begin
        FDB.Rollback;Updated:=nil;Gear:=Default(TB1008EquipmentItem);
      end;
    end;
  finally FLock.Release;end;
end;
