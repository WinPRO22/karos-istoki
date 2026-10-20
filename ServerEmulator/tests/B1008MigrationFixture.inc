{$I B1008PreInstances.inc}

// Reconstruct a real v13 schema before older migration fixtures rewind it.
// Test databases only; copy current fixture rows rather than stale backup rows.
procedure RestorePreDropSchema(DB:TFDConnection);
begin
  RestorePreInstanceSchema(DB);
  DB.ExecSQL('DROP TABLE npc_sales');
  DB.ExecSQL('DROP TABLE npc_sales_v15_backup');
  DB.ExecSQL('DROP TABLE npc_purchases');
  DB.ExecSQL('DROP TABLE skill_points');
  DB.ExecSQL('DROP TABLE learned_skills');
  DB.ExecSQL('DROP TABLE starter_skills');
  DB.ExecSQL('DROP VIEW wallet');
  DB.ExecSQL('DELETE FROM inventory_v13_backup');
  DB.ExecSQL('INSERT INTO inventory_v13_backup SELECT * FROM inventory');
  DB.ExecSQL('DROP TABLE inventory');
  DB.ExecSQL('ALTER TABLE inventory_v13_backup RENAME TO inventory');
  DB.ExecSQL('DELETE FROM equipment_v13_backup');
  DB.ExecSQL('INSERT INTO equipment_v13_backup SELECT * FROM equipment');
  DB.ExecSQL('DROP TABLE equipment');
  DB.ExecSQL('ALTER TABLE equipment_v13_backup RENAME TO equipment');
  DB.ExecSQL('CREATE VIEW wallet AS SELECT 1 AS id,amount FROM inventory WHERE item_id=999999');
  DB.ExecSQL('PRAGMA user_version=13');
end;
