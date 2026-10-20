// Isolated migration fixtures only: remove v39 additions before rewinding.
// Keep the item rows, so older migrations still exercise data preservation.
procedure RestorePreInstanceSchema(DB:TFDConnection);
const
  Tables:array[0..3] of string=('inventory','equipment','personal_stash','ground');
var
  TableName:string;
  Q:TFDQuery;
  HasInstanceID:Boolean;
begin
  Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=DB;
    for TableName in Tables do begin
      HasInstanceID:=False;
      Q.Open('PRAGMA table_info('+TableName+')');
      while not Q.Eof do begin
        if Q.FieldByName('name').AsString='instance_id' then HasInstanceID:=True;
        Q.Next;
      end;
      Q.Close;
      if HasInstanceID then DB.ExecSQL('ALTER TABLE '+TableName+' DROP COLUMN instance_id');
    end;
    DB.ExecSQL('DROP TABLE IF EXISTS item_instances');
  finally
    Q.Free;
  end;
end;
