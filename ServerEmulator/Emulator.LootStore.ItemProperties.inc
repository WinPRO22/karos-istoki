function TB1008LootStore.InstanceColumn:string;
begin
  if FPropertiesReady then Result:='COALESCE(instance_id,0)' else Result:='0';
end;

function TB1008LootStore.ReadProperties(InstanceID:Int64):TB1008ItemProperties;
var Q:TFDQuery;
begin
  Result:=Default(TB1008ItemProperties);if InstanceID=0 then Exit;
  Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FDB;Q.Open('SELECT grade,data8,data12,gem0,gem1,gem2 FROM item_instances WHERE instance_id=:i',[InstanceID]);
    if Q.Eof then raise Exception.Create('Missing item instance');
    Result.InstanceID:=InstanceID;Result.NativeGrade:=Q.Fields[0].AsInteger;
    Result.NativeData8:=Q.Fields[1].AsLargeInt;Result.NativeData12:=Q.Fields[2].AsLargeInt;
    Result.GemIDs[0]:=Q.Fields[3].AsLargeInt;Result.GemIDs[1]:=Q.Fields[4].AsLargeInt;
    Result.GemIDs[2]:=Q.Fields[5].AsLargeInt;
  finally Q.Free;end;
end;

procedure TB1008LootStore.EnsureProperties(ItemID:Cardinal;var Properties:TB1008ItemProperties);
begin
  if TB1008Items.StackLimit(ItemID)<>1 then begin
    if Properties.InstanceID<>0 then raise Exception.Create('Stackable item has instance');
    Properties:=Default(TB1008ItemProperties);Exit;
  end;
  if Properties.InstanceID=0 then begin
    FDB.ExecSQL('INSERT INTO item_instances(item_id,grade,data8,data12,gem0,gem1,gem2) VALUES(:i,:g,:a,:b,:x,:y,:z)',
      [Int64(ItemID),Integer(Properties.NativeGrade),Int64(Properties.NativeData8),Int64(Properties.NativeData12),
       Int64(Properties.GemIDs[0]),Int64(Properties.GemIDs[1]),Int64(Properties.GemIDs[2])]);
    Properties.InstanceID:=Int64(FDB.ExecSQLScalar('SELECT last_insert_rowid()'));
  end else if Int64(FDB.ExecSQLScalar('SELECT COALESCE((SELECT item_id FROM item_instances WHERE instance_id=:i),0)',
    [Properties.InstanceID]))<>ItemID then raise Exception.Create('Item instance template mismatch');
end;

procedure TB1008LootStore.SaveProperties(ItemID:Cardinal;var Properties:TB1008ItemProperties);
begin
  EnsureProperties(ItemID,Properties);
  if Properties.InstanceID=0 then raise Exception.Create('No modifiable item instance');
  FDB.ExecSQL('UPDATE item_instances SET grade=:g,data8=:a,data12=:b,gem0=:x,gem1=:y,gem2=:z WHERE instance_id=:p',
    [Integer(Properties.NativeGrade),Int64(Properties.NativeData8),Int64(Properties.NativeData12),
     Int64(Properties.GemIDs[0]),Int64(Properties.GemIDs[1]),Int64(Properties.GemIDs[2]),Properties.InstanceID]);
end;

procedure TB1008LootStore.MigrateItemInstances;
var TableName,KeyName:string;Q:TFDQuery;P:TB1008ItemProperties;ID:Cardinal;Key:Variant;
begin
  for TableName in ['inventory','equipment','personal_stash','ground'] do begin
    if TableName='ground' then KeyName:='receipt' else KeyName:='slot';
    Q:=TFDQuery.Create(nil);
    try
      Q.Connection:=FDB;Q.Open('SELECT '+KeyName+',item_id FROM '+TableName+' WHERE instance_id IS NULL');
      while not Q.Eof do begin
        ID:=Q.Fields[1].AsLargeInt;Key:=Q.Fields[0].Value;
        if TB1008Items.StackLimit(ID)=1 then begin
          P:=Default(TB1008ItemProperties);EnsureProperties(ID,P);
          FDB.ExecSQL('UPDATE '+TableName+' SET instance_id=:i WHERE '+KeyName+'=:k',[P.InstanceID,Key]);
        end;
        Q.Next;
      end;
    finally Q.Free;end;
  end;
end;
