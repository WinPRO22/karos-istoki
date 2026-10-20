unit Emulator.Repository.SQLite;

interface

uses
  System.SysUtils, FireDAC.Comp.Client, FireDAC.Phys.SQLite,
  Emulator.Content, Emulator.Repository;

type
  TSQLiteContentRepository = class(TInterfacedObject,
    IEmulatorContentRepository)
  private
    FDatabasePath: string;
    FConnection: TFDConnection;
    FDriverLink: TFDPhysSQLiteDriverLink;
    procedure Open;
    procedure EnsureSchema;
    procedure SeedBerneo;
    procedure Execute(const ASQL: string);
    function SchemaVersion: Integer;
    function ActiveRevision: Int64;
    function GetDatabasePath: string;
  public
    constructor Create(const ADatabasePath: string; AFullBerneo:Boolean=False);
    destructor Destroy; override;
    class function DefaultDatabasePath(const AStartDirectory: string): string; static;
    function LoadSnapshot(const ABuildID: string): IEmulatorContentSnapshot;
    function PublishMob(const ADefinition: TEmulatorMobDefinition): Int64;
    function PublishSpawn(const ADefinition: TEmulatorSpawnDefinition): Int64;
  end;

implementation

uses
  System.IOUtils, System.Math, System.Generics.Collections, Data.DB,
  FireDAC.Stan.Def, FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.DApt,
  FireDAC.Phys.SQLiteDef, Emulator.Berneo.B1008;

const
  CurrentSchemaVersion = 8;
  SeedBuildID = 'b1008';

constructor TSQLiteContentRepository.Create(const ADatabasePath: string; AFullBerneo:Boolean);
begin
  inherited Create;
  if Trim(ADatabasePath) = '' then
    raise EArgumentException.Create('SQLite database path is required');
  FDatabasePath := ExpandFileName(ADatabasePath);
  FDriverLink := TFDPhysSQLiteDriverLink.Create(nil);
  FConnection := TFDConnection.Create(nil);
  try
    Open;
    EnsureSchema;
    if AFullBerneo then SeedBerneo;
  except
    FConnection.Free;
    FConnection := nil;
    FDriverLink.Free;
    FDriverLink := nil;
    raise;
  end;
end;

destructor TSQLiteContentRepository.Destroy;
begin
  FConnection.Free;
  FDriverLink.Free;
  inherited Destroy;
end;

class function TSQLiteContentRepository.DefaultDatabasePath(
  const AStartDirectory: string): string;
var
  Dir, Parent: string;
  I: Integer;
begin
  Dir := ExcludeTrailingPathDelimiter(ExpandFileName(AStartDirectory));
  for I := 0 to 5 do
  begin
    if FileExists(TPath.Combine(Dir, 'KarosOldEmulator.dpr')) then
      Exit(TPath.Combine(Dir, 'data\karos-emulator.sqlite3'));
    Parent := ExtractFileDir(Dir);
    if SameText(Parent, Dir) then
      Break;
    Dir := Parent;
  end;
  raise Exception.Create('Emulator project directory not found for database');
end;

procedure TSQLiteContentRepository.Open;
var
  VendorLibrary: string;
begin
  ForceDirectories(ExtractFileDir(FDatabasePath));
  VendorLibrary := TPath.Combine(ExtractFilePath(ParamStr(0)), 'sqlite3.dll');
  if FileExists(VendorLibrary) then
    FDriverLink.VendorLib := VendorLibrary;
  FConnection.LoginPrompt := False;
  FConnection.Params.Clear;
  FConnection.Params.Values['DriverID'] := 'SQLite';
  FConnection.Params.Values['Database'] := FDatabasePath;
  FConnection.Params.Values['OpenMode'] := 'CreateUTF8';
  FConnection.Params.Values['LockingMode'] := 'Normal';
  FConnection.Params.Values['Synchronous'] := 'Normal';
  FConnection.Params.Values['JournalMode'] := 'WAL';
  FConnection.Params.Values['BusyTimeout'] := '5000';
  FConnection.Connected := True;
  Execute('PRAGMA foreign_keys = ON');
  Execute('PRAGMA busy_timeout = 5000');
end;

procedure TSQLiteContentRepository.Execute(const ASQL: string);
begin
  FConnection.ExecSQL(ASQL);
end;

function TSQLiteContentRepository.SchemaVersion: Integer;
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'SELECT COALESCE(MAX(version), 0) AS version FROM schema_migrations';
    Query.Open;
    Result := Query.FieldByName('version').AsInteger;
  finally
    Query.Free;
  end;
end;

procedure TSQLiteContentRepository.EnsureSchema;
var
  Version: Integer;
  WasNew: Boolean;
begin
  Execute('CREATE TABLE IF NOT EXISTS schema_migrations ('+
    'version INTEGER PRIMARY KEY, applied_utc TEXT NOT NULL)');
  Version := SchemaVersion;
  WasNew := Version=0;
  if Version > CurrentSchemaVersion then
    raise EEmulatorContent.CreateFmt('Database schema %d is newer than supported %d',
      [Version, CurrentSchemaVersion]);
  if Version = CurrentSchemaVersion then
    Exit;

  if Version < 1 then
  begin
    FConnection.StartTransaction;
    try
    Execute('CREATE TABLE content_meta ('+
      'id INTEGER PRIMARY KEY CHECK (id = 1), '+
      'active_revision INTEGER NOT NULL CHECK (active_revision > 0))');
    Execute('INSERT INTO content_meta(id, active_revision) VALUES (1, 1)');
    Execute('CREATE TABLE build_profiles ('+
      'build_id TEXT PRIMARY KEY, protocol_profile TEXT NOT NULL, '+
      'enabled INTEGER NOT NULL CHECK (enabled IN (0,1)), '+
      'revision INTEGER NOT NULL CHECK (revision > 0))');
    Execute('CREATE TABLE mob_definitions ('+
      'build_id TEXT NOT NULL, mob_id INTEGER NOT NULL, name TEXT NOT NULL, '+
      'max_hp INTEGER NOT NULL CHECK (max_hp > 0), '+
      'attack_damage INTEGER NOT NULL CHECK (attack_damage >= 0), '+
      'attack_speed REAL NOT NULL CHECK (attack_speed > 0), '+
      'movement_speed REAL NOT NULL CHECK (movement_speed >= 0), '+
      'patrol_radius REAL NOT NULL CHECK (patrol_radius >= 0), '+
      'aggro_radius REAL NOT NULL CHECK (aggro_radius >= 0), '+
      'attack_range REAL NOT NULL CHECK (attack_range >= 0), '+
      'leash_radius REAL NOT NULL CHECK (leash_radius >= attack_range), '+
      'respawn_ms INTEGER NOT NULL CHECK (respawn_ms >= 0), '+
      'aggressive INTEGER NOT NULL CHECK (aggressive IN (0,1)), '+
      'enabled INTEGER NOT NULL CHECK (enabled IN (0,1)), '+
      'revision INTEGER NOT NULL CHECK (revision > 0), '+
      'PRIMARY KEY(build_id, mob_id), '+
      'FOREIGN KEY(build_id) REFERENCES build_profiles(build_id))');
    Execute('CREATE TABLE spawn_definitions ('+
      'build_id TEXT NOT NULL, spawn_id INTEGER NOT NULL, map_id INTEGER NOT NULL, '+
      'mob_id INTEGER NOT NULL, entity_handle INTEGER NOT NULL, '+
      'x REAL NOT NULL, z REAL NOT NULL, y REAL NOT NULL, heading REAL NOT NULL, '+
      'enabled INTEGER NOT NULL CHECK (enabled IN (0,1)), '+
      'revision INTEGER NOT NULL CHECK (revision > 0), '+
      'PRIMARY KEY(build_id, spawn_id), '+
      'UNIQUE(build_id, entity_handle), '+
      'FOREIGN KEY(build_id, mob_id) REFERENCES mob_definitions(build_id, mob_id))');

    Execute('INSERT INTO build_profiles(build_id, protocol_profile, enabled, revision) '+
      'VALUES (''b1008'', ''NHN-EN CBT1 b1008'', 1, 1)');
    Execute('INSERT INTO mob_definitions(build_id, mob_id, name, max_hp, '+
      'attack_damage, attack_speed, movement_speed, patrol_radius, aggro_radius, '+
      'attack_range, leash_radius, respawn_ms, aggressive, enabled, revision) '+
      'VALUES (''b1008'', 120, ''Little Spider'', 500, 10, 1.0, 8.0, '+
      '8.0, 0.0, 13.0, 60.0, 5000, 0, 1, 1)');
    Execute('INSERT INTO spawn_definitions(build_id, spawn_id, map_id, mob_id, '+
      'entity_handle, x, z, y, heading, enabled, revision) VALUES '+
      '(''b1008'', 107, 19003, 120, 107, 8011.3486328125, '+
      '6333.36328125, 668.4842529296875, 0.0, 1, 1)');
    Execute('INSERT INTO spawn_definitions(build_id, spawn_id, map_id, mob_id, '+
      'entity_handle, x, z, y, heading, enabled, revision) VALUES '+
      '(''b1008'', 108, 19003, 120, 108, 7820.375, '+
      '5866.0869140625, 628.9754638671875, 0.0, 1, 1)');
    Execute('INSERT INTO spawn_definitions(build_id, spawn_id, map_id, mob_id, '+
      'entity_handle, x, z, y, heading, enabled, revision) VALUES '+
      '(''b1008'', 109, 19003, 120, 109, 8594.7197265625, '+
      '5896.509765625, 631.677978515625, 0.0, 1, 1)');
    Execute('INSERT INTO spawn_definitions(build_id, spawn_id, map_id, mob_id, '+
      'entity_handle, x, z, y, heading, enabled, revision) VALUES '+
      '(''b1008'', 118, 19003, 120, 118, 7796.43798828125, '+
      '6788.62841796875, 601.01904296875, 0.0, 1, 1)');
    Execute('INSERT INTO spawn_definitions(build_id, spawn_id, map_id, mob_id, '+
      'entity_handle, x, z, y, heading, enabled, revision) VALUES '+
      '(''b1008'', 119, 19003, 120, 119, 8246.01171875, '+
      '6681.85888671875, 609.94384765625, 0.0, 1, 1)');
    Execute('INSERT INTO spawn_definitions(build_id, spawn_id, map_id, mob_id, '+
      'entity_handle, x, z, y, heading, enabled, revision) VALUES '+
      '(''b1008'', 120, 19003, 120, 120, 8669.7763671875, '+
      '6668.01025390625, 604.350341796875, 0.0, 1, 1)');
    Execute('INSERT INTO spawn_definitions(build_id, spawn_id, map_id, mob_id, '+
      'entity_handle, x, z, y, heading, enabled, revision) VALUES '+
      '(''b1008'', 132, 19003, 120, 132, 7617.93994140625, '+
      '7342.89990234375, 609.7030029296875, 0.0, 1, 1)');
    Execute('INSERT INTO spawn_definitions(build_id, spawn_id, map_id, mob_id, '+
      'entity_handle, x, z, y, heading, enabled, revision) VALUES '+
      '(''b1008'', 133, 19003, 120, 133, 8134.47998046875, '+
      '7266.41015625, 596.64501953125, 0.0, 1, 1)');
    Execute('INSERT INTO spawn_definitions(build_id, spawn_id, map_id, mob_id, '+
      'entity_handle, x, z, y, heading, enabled, revision) VALUES '+
      '(''b1008'', 134, 19003, 120, 134, 7799.26708984375, '+
      '7169.55908203125, 600.18115234375, 0.0, 1, 1)');
    Execute('INSERT INTO spawn_definitions(build_id, spawn_id, map_id, mob_id, '+
      'entity_handle, x, z, y, heading, enabled, revision) VALUES '+
      '(''b1008'', 135, 19003, 120, 135, 8072.2001953125, '+
      '7384.4501953125, 597.4719848632812, 0.0, 1, 1)');

    Execute('CREATE TRIGGER build_profiles_revision_update AFTER UPDATE ON build_profiles '+
      'BEGIN UPDATE content_meta SET active_revision=active_revision+1 WHERE id=1; END');
    Execute('CREATE TRIGGER mob_definitions_revision_insert AFTER INSERT ON mob_definitions '+
      'BEGIN UPDATE content_meta SET active_revision=active_revision+1 WHERE id=1; END');
    Execute('CREATE TRIGGER mob_definitions_revision_update AFTER UPDATE ON mob_definitions '+
      'BEGIN UPDATE content_meta SET active_revision=active_revision+1 WHERE id=1; END');
    Execute('CREATE TRIGGER mob_definitions_revision_delete AFTER DELETE ON mob_definitions '+
      'BEGIN UPDATE content_meta SET active_revision=active_revision+1 WHERE id=1; END');
    Execute('CREATE TRIGGER spawn_definitions_revision_insert AFTER INSERT ON spawn_definitions '+
      'BEGIN UPDATE content_meta SET active_revision=active_revision+1 WHERE id=1; END');
    Execute('CREATE TRIGGER spawn_definitions_revision_update AFTER UPDATE ON spawn_definitions '+
      'BEGIN UPDATE content_meta SET active_revision=active_revision+1 WHERE id=1; END');
    Execute('CREATE TRIGGER spawn_definitions_revision_delete AFTER DELETE ON spawn_definitions '+
      'BEGIN UPDATE content_meta SET active_revision=active_revision+1 WHERE id=1; END');
    Execute('INSERT INTO schema_migrations(version, applied_utc) '+
      'VALUES (1, strftime(''%Y-%m-%dT%H:%M:%fZ'', ''now''))');
      FConnection.Commit;
    except
      if FConnection.InTransaction then
        FConnection.Rollback;
      raise;
    end;
    Version := 1;
  end;

  if Version < 2 then
  begin
    FConnection.StartTransaction;
    try
      // Handle 122 is Chonchon in BERNEO65.NPC. Handle 119 is an original
      // Little Spider placement and can safely carry the nearby test spawn.
      Execute('UPDATE spawn_definitions SET spawn_id=119, entity_handle=119 '+
        'WHERE build_id=''b1008'' AND spawn_id=122 AND entity_handle=122');
      Execute('INSERT INTO schema_migrations(version, applied_utc) '+
        'VALUES (2, strftime(''%Y-%m-%dT%H:%M:%fZ'', ''now''))');
      FConnection.Commit;
    except
      if FConnection.InTransaction then
        FConnection.Rollback;
      raise;
    end;
  end;

  if Version < 3 then
  begin
    FConnection.StartTransaction;
    try
      Execute('UPDATE spawn_definitions SET x=8246.01171875, '+
        'z=6681.85888671875, y=609.94384765625 '+
        'WHERE build_id=''b1008'' AND spawn_id=119 AND '+
        '(x<>8246.01171875 OR z<>6681.85888671875 OR y<>609.94384765625)');
      Execute('INSERT OR IGNORE INTO spawn_definitions(build_id, spawn_id, '+
        'map_id, mob_id, entity_handle, x, z, y, heading, enabled, revision) '+
        'VALUES (''b1008'',107,19003,120,107,8011.3486328125,6333.36328125,'+
        '668.4842529296875,0.0,1,1)');
      Execute('INSERT OR IGNORE INTO spawn_definitions(build_id, spawn_id, '+
        'map_id, mob_id, entity_handle, x, z, y, heading, enabled, revision) '+
        'VALUES (''b1008'',108,19003,120,108,7820.375,5866.0869140625,'+
        '628.9754638671875,0.0,1,1)');
      Execute('INSERT OR IGNORE INTO spawn_definitions(build_id, spawn_id, '+
        'map_id, mob_id, entity_handle, x, z, y, heading, enabled, revision) '+
        'VALUES (''b1008'',109,19003,120,109,8594.7197265625,5896.509765625,'+
        '631.677978515625,0.0,1,1)');
      Execute('INSERT OR IGNORE INTO spawn_definitions(build_id, spawn_id, '+
        'map_id, mob_id, entity_handle, x, z, y, heading, enabled, revision) '+
        'VALUES (''b1008'',118,19003,120,118,7796.43798828125,6788.62841796875,'+
        '601.01904296875,0.0,1,1)');
      Execute('INSERT OR IGNORE INTO spawn_definitions(build_id, spawn_id, '+
        'map_id, mob_id, entity_handle, x, z, y, heading, enabled, revision) '+
        'VALUES (''b1008'',132,19003,120,132,7617.93994140625,7342.89990234375,'+
        '609.7030029296875,0.0,1,1)');
      Execute('INSERT OR IGNORE INTO spawn_definitions(build_id, spawn_id, '+
        'map_id, mob_id, entity_handle, x, z, y, heading, enabled, revision) '+
        'VALUES (''b1008'',133,19003,120,133,8134.47998046875,7266.41015625,'+
        '596.64501953125,0.0,1,1)');
      Execute('INSERT OR IGNORE INTO spawn_definitions(build_id, spawn_id, '+
        'map_id, mob_id, entity_handle, x, z, y, heading, enabled, revision) '+
        'VALUES (''b1008'',134,19003,120,134,7799.26708984375,7169.55908203125,'+
        '600.18115234375,0.0,1,1)');
      Execute('INSERT OR IGNORE INTO spawn_definitions(build_id, spawn_id, '+
        'map_id, mob_id, entity_handle, x, z, y, heading, enabled, revision) '+
        'VALUES (''b1008'',135,19003,120,135,8072.2001953125,7384.4501953125,'+
        '597.4719848632812,0.0,1,1)');
      Execute('INSERT INTO schema_migrations(version, applied_utc) '+
        'VALUES (3, strftime(''%Y-%m-%dT%H:%M:%fZ'', ''now''))');
      FConnection.Commit;
    except
      if FConnection.InTransaction then
        FConnection.Rollback;
      raise;
    end;
  end;

  if Version < 4 then
  begin
    FConnection.StartTransaction;
    try
      Execute('ALTER TABLE spawn_definitions ADD COLUMN population INTEGER '+
        'NOT NULL DEFAULT 1 CHECK(population > 0)');
      Execute('ALTER TABLE spawn_definitions ADD COLUMN spawn_radius REAL '+
        'NOT NULL DEFAULT 0 CHECK(spawn_radius >= 0)');
      // BERNEO65.NPC v5 stores these two values after every Little Spider
      // group anchor. They are retained as editable live-content data.
      Execute('UPDATE spawn_definitions SET population=CASE spawn_id '+
        'WHEN 107 THEN 10 WHEN 108 THEN 10 WHEN 109 THEN 10 '+
        'WHEN 118 THEN 10 WHEN 119 THEN 10 WHEN 120 THEN 5 '+
        'WHEN 132 THEN 12 WHEN 133 THEN 12 WHEN 134 THEN 10 '+
        'WHEN 135 THEN 12 ELSE population END, spawn_radius=CASE spawn_id '+
        'WHEN 107 THEN 300 WHEN 108 THEN 300 WHEN 109 THEN 300 '+
        'WHEN 118 THEN 300 WHEN 119 THEN 300 WHEN 120 THEN 150 '+
        'WHEN 132 THEN 300 WHEN 133 THEN 300 WHEN 134 THEN 500 '+
        'WHEN 135 THEN 500 ELSE spawn_radius END '+
        'WHERE build_id=''b1008'' AND spawn_id IN '+
        '(107,108,109,118,119,120,132,133,134,135)');
      if WasNew then
      begin
        Execute('UPDATE mob_definitions SET revision=1 '+
          'WHERE build_id=''b1008'' AND mob_id=120');
        Execute('UPDATE content_meta SET active_revision=1 WHERE id=1');
      end;
      Execute('INSERT INTO schema_migrations(version, applied_utc) '+
        'VALUES (4, strftime(''%Y-%m-%dT%H:%M:%fZ'', ''now''))');
      FConnection.Commit;
    except
      if FConnection.InTransaction then
        FConnection.Rollback;
      raise;
    end;
  end;

  if Version < 5 then
  begin
    FConnection.StartTransaction;
    try
      Execute('ALTER TABLE mob_definitions ADD COLUMN chase_speed REAL '+
        'NOT NULL DEFAULT 8 CHECK(chase_speed > 0)');
      Execute('UPDATE mob_definitions SET chase_speed=24, patrol_radius=18, '+
        'respawn_ms=15000, '+
        'revision=(SELECT active_revision+1 FROM content_meta WHERE id=1) '+
        'WHERE build_id=''b1008'' AND mob_id=120');
      if WasNew then
      begin
        Execute('UPDATE mob_definitions SET revision=1 '+
          'WHERE build_id=''b1008'' AND mob_id=120');
        Execute('UPDATE content_meta SET active_revision=1 WHERE id=1');
      end;
      Execute('INSERT INTO schema_migrations(version, applied_utc) '+
        'VALUES (5, strftime(''%Y-%m-%dT%H:%M:%fZ'', ''now''))');
      FConnection.Commit;
    except
      if FConnection.InTransaction then
        FConnection.Rollback;
      raise;
    end;
  end;

  if Version < 6 then
  begin
    FConnection.StartTransaction;
    try
      Execute('UPDATE mob_definitions SET movement_speed=12, chase_speed=32, '+
        'patrol_radius=22, '+
        'revision=(SELECT active_revision+1 FROM content_meta WHERE id=1) '+
        'WHERE build_id=''b1008'' AND mob_id=120');
      if WasNew then
      begin
        Execute('UPDATE mob_definitions SET revision=1 '+
          'WHERE build_id=''b1008'' AND mob_id=120');
        Execute('UPDATE content_meta SET active_revision=1 WHERE id=1');
      end;
      Execute('INSERT INTO schema_migrations(version, applied_utc) '+
        'VALUES (6, strftime(''%Y-%m-%dT%H:%M:%fZ'', ''now''))');
      FConnection.Commit;
    except
      if FConnection.InTransaction then
        FConnection.Rollback;
      raise;
    end;
  end;
  if Version < 7 then
  begin
    FConnection.StartTransaction;
    try
      Execute('CREATE TABLE content_packs (name TEXT PRIMARY KEY)');
      Execute('INSERT INTO schema_migrations(version,applied_utc) VALUES (7,strftime(''%Y-%m-%dT%H:%M:%fZ'',''now''))');
      FConnection.Commit;
    except FConnection.Rollback;raise;end;
  end;
  if Version < 8 then
  begin
    FConnection.StartTransaction;
    try
      Execute('ALTER TABLE mob_definitions ADD COLUMN attack_min INTEGER NOT NULL DEFAULT 0 CHECK(attack_min>=0)');
      Execute('ALTER TABLE mob_definitions ADD COLUMN physical_defense INTEGER NOT NULL DEFAULT 0 CHECK(physical_defense>=0)');
      Execute('INSERT INTO schema_migrations(version,applied_utc) VALUES (8,strftime(''%Y-%m-%dT%H:%M:%fZ'',''now''))');
      FConnection.Commit;
    except FConnection.Rollback;raise;end;
  end;
end;

procedure TSQLiteContentRepository.SeedBerneo;
var M:TB1008BerneoMob;D:TEmulatorMobDefinition;S:TEmulatorSpawnDefinition;
  I:Integer;OldFactor:Double;
begin
  FConnection.StartTransaction;
  try
    if Integer(FConnection.ExecSQLScalar('SELECT COUNT(*) FROM content_packs WHERE name=''berneo-overworld-v1'''))=0 then begin
      for M in TB1008Berneo.Mobs do begin
        D:=M.Definition;
        // Additive seed: preserve the user's tested spider and all live overrides.
        FConnection.ExecSQL('INSERT OR IGNORE INTO mob_definitions '+
          '(build_id,mob_id,name,max_hp,attack_damage,attack_min,physical_defense,attack_speed,movement_speed,chase_speed,'+
          'patrol_radius,aggro_radius,attack_range,leash_radius,respawn_ms,aggressive,enabled,revision) '+
          'VALUES (''b1008'',:id,:n,:hp,:d,:min,:def,:a,:m,:c,:p,0,:r,:l,:s,0,1,1)',
          [D.MobID,D.Name,D.MaxHP,D.AttackDamage,D.AttackMin,D.PhysicalDefense,D.AttackSpeed,D.MovementSpeed,D.ChaseSpeed,
           D.PatrolRadius,D.AttackRange,D.LeashRadius,D.RespawnMS]);
      end;
      for S in TB1008Berneo.Groups do
        FConnection.ExecSQL('INSERT OR IGNORE INTO spawn_definitions '+
          '(build_id,spawn_id,map_id,mob_id,entity_handle,x,z,y,heading,population,spawn_radius,enabled,revision) '+
          'VALUES (''b1008'',:id,19003,:m,:e,:x,:z,:y,:h,:p,:r,1,1)',
          [S.SpawnID,S.MobID,S.EntityHandle,S.X,S.Z,S.Y,S.Heading,S.Population,S.SpawnRadius]);
      Execute('INSERT INTO content_packs VALUES (''berneo-overworld-v1'')');
    end;
    if Integer(FConnection.ExecSQLScalar('SELECT COUNT(*) FROM content_packs WHERE name=''berneo-melee-spacing-v2'''))=0 then begin
      for M in TB1008Berneo.Mobs do if M.Definition.MobID<>120 then
        // Only replace the old shared placeholder; retain any edited reach.
        FConnection.ExecSQL('UPDATE mob_definitions SET attack_range=:r,revision=revision+1 '+
          'WHERE build_id=''b1008'' AND mob_id=:id AND attack_range=14',
          [M.Definition.AttackRange,M.Definition.MobID]);
      Execute('INSERT INTO content_packs VALUES (''berneo-melee-spacing-v2'')');
    end;
    if Integer(FConnection.ExecSQLScalar('SELECT COUNT(*) FROM content_packs WHERE name=''berneo-combat-growth-v3'''))=0 then begin
      for M in TB1008Berneo.Mobs do begin
        D:=M.Definition;
        // Upgrade known v1 combat defaults once. Retain custom HP/damage and
        // all movement, reach, spawn, reward and drop edits.
        FConnection.ExecSQL('UPDATE mob_definitions SET max_hp=:hp,attack_damage=:d,'+
          'attack_min=:min,physical_defense=:def,revision=revision+1 '+
          'WHERE build_id=''b1008'' AND mob_id=:id AND max_hp=:oldhp AND attack_damage=:oldd '+
          'AND attack_min=0 AND physical_defense=0',
          [D.MaxHP,D.AttackDamage,D.AttackMin,D.PhysicalDefense,D.MobID,M.LegacyHP,M.LegacyDamage]);
      end;
      Execute('INSERT INTO content_packs VALUES (''berneo-combat-growth-v3'')');
    end;
    if Integer(FConnection.ExecSQLScalar('SELECT COUNT(*) FROM content_packs WHERE name=''berneo-combat-growth-v4'''))=0 then begin
      // Preserve the installed definitions before replacing only the exact
      // previous 20% profile. Custom tuning and all non-combat data survive.
      Execute('CREATE TABLE IF NOT EXISTS mob_definitions_growth_v3_backup AS SELECT * FROM mob_definitions');
      for M in TB1008Berneo.Mobs do begin
        D:=M.Definition;OldFactor:=1;
        for I:=2 to M.Level do OldFactor:=OldFactor*120/100;
        FConnection.ExecSQL('UPDATE mob_definitions SET max_hp=:hp,attack_damage=:d,'+
          'attack_min=:min,physical_defense=:def,revision=revision+1 '+
          'WHERE build_id=''b1008'' AND mob_id=:id AND max_hp=:oldhp AND attack_damage=:oldd '+
          'AND attack_min=:oldmin AND physical_defense=:olddef',
          [D.MaxHP,D.AttackDamage,D.AttackMin,D.PhysicalDefense,D.MobID,
           Floor(50*OldFactor+0.5),Floor(17*OldFactor+0.5),Floor(13*OldFactor+0.5),Floor(15*OldFactor+0.5)]);
      end;
      Execute('INSERT INTO content_packs VALUES (''berneo-combat-growth-v4'')');
    end;
    if Integer(FConnection.ExecSQLScalar('SELECT COUNT(*) FROM content_packs WHERE name=''berneo-miniboss-v5'''))=0 then begin
      Execute('CREATE TABLE IF NOT EXISTS miniboss_mobs_v4_backup AS SELECT * FROM mob_definitions WHERE mob_id=1005717');
      Execute('CREATE TABLE IF NOT EXISTS miniboss_spawns_v4_backup AS SELECT * FROM spawn_definitions WHERE mob_id=1005717');
      D:=TB1008Berneo.Mob(1005717).Definition;
      FConnection.ExecSQL('UPDATE mob_definitions SET max_hp=:hp,revision=revision+1 '+
        'WHERE build_id=''b1008'' AND mob_id=1005717 AND max_hp=:oldhp',[D.MaxHP,D.MaxHP div 7]);
      Execute('UPDATE spawn_definitions SET population=10,revision=revision+1 '+
        'WHERE build_id=''b1008'' AND spawn_id=23 AND mob_id=1005717 AND population=1');
      Execute('INSERT INTO content_packs VALUES (''berneo-miniboss-v5'')');
    end;
    FConnection.Commit;
  except FConnection.Rollback;raise;end;
end;

function TSQLiteContentRepository.ActiveRevision: Int64;
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'SELECT active_revision FROM content_meta WHERE id=1';
    Query.Open;
    if Query.Eof then
      raise EEmulatorContent.Create('Content revision row is missing');
    Result := Query.Fields[0].AsLargeInt;
  finally
    Query.Free;
  end;
end;

function TSQLiteContentRepository.GetDatabasePath: string;
begin
  Result := FDatabasePath;
end;

function TSQLiteContentRepository.LoadSnapshot(
  const ABuildID: string): IEmulatorContentSnapshot;
var
  Query: TFDQuery;
  Mobs: TList<TEmulatorMobDefinition>;
  Spawns: TList<TEmulatorSpawnDefinition>;
  Mob: TEmulatorMobDefinition;
  Spawn: TEmulatorSpawnDefinition;
  Revision: Int64;
begin
  if Trim(ABuildID) = '' then
    raise EArgumentException.Create('Build ID is required');
  EnsureSchema;
  Revision := ActiveRevision;
  Query := TFDQuery.Create(nil);
  Mobs := TList<TEmulatorMobDefinition>.Create;
  Spawns := TList<TEmulatorSpawnDefinition>.Create;
  try
    Query.Connection := FConnection;
    Query.SQL.Text := 'SELECT enabled FROM build_profiles '+
      'WHERE build_id=:build_id';
    Query.ParamByName('build_id').AsString := ABuildID;
    Query.Open;
    if Query.Eof or (Query.Fields[0].AsInteger = 0) then
      raise EEmulatorContent.Create('Build profile is missing or disabled: '+ABuildID);
    Query.Close;

    Query.SQL.Text := 'SELECT * FROM mob_definitions '+
      'WHERE build_id=:build_id AND enabled=1 ORDER BY mob_id';
    Query.ParamByName('build_id').AsString := ABuildID;
    Query.Open;
    while not Query.Eof do
    begin
      Mob.BuildID := Query.FieldByName('build_id').AsString;
      Mob.MobID := Query.FieldByName('mob_id').AsLargeInt;
      Mob.Name := Query.FieldByName('name').AsString;
      Mob.MaxHP := Query.FieldByName('max_hp').AsInteger;
      Mob.AttackDamage := Query.FieldByName('attack_damage').AsInteger;
      Mob.AttackMin := Query.FieldByName('attack_min').AsInteger;
      Mob.PhysicalDefense := Query.FieldByName('physical_defense').AsInteger;
      Mob.AttackSpeed := Query.FieldByName('attack_speed').AsFloat;
      Mob.MovementSpeed := Query.FieldByName('movement_speed').AsFloat;
      Mob.ChaseSpeed := Query.FieldByName('chase_speed').AsFloat;
      Mob.PatrolRadius := Query.FieldByName('patrol_radius').AsFloat;
      Mob.AggroRadius := Query.FieldByName('aggro_radius').AsFloat;
      Mob.AttackRange := Query.FieldByName('attack_range').AsFloat;
      Mob.LeashRadius := Query.FieldByName('leash_radius').AsFloat;
      Mob.RespawnMS := Query.FieldByName('respawn_ms').AsInteger;
      Mob.Aggressive := Query.FieldByName('aggressive').AsInteger <> 0;
      Mob.Enabled := Query.FieldByName('enabled').AsInteger <> 0;
      Mob.Revision := Query.FieldByName('revision').AsLargeInt;
      ValidateMobDefinition(Mob);
      Mobs.Add(Mob);
      Query.Next;
    end;
    Query.Close;

    Query.SQL.Text := 'SELECT * FROM spawn_definitions '+
      'WHERE build_id=:build_id AND enabled=1 ORDER BY spawn_id';
    Query.ParamByName('build_id').AsString := ABuildID;
    Query.Open;
    while not Query.Eof do
    begin
      Spawn.BuildID := Query.FieldByName('build_id').AsString;
      Spawn.SpawnID := Query.FieldByName('spawn_id').AsLargeInt;
      Spawn.MapID := Query.FieldByName('map_id').AsLargeInt;
      Spawn.MobID := Query.FieldByName('mob_id').AsLargeInt;
      Spawn.EntityHandle := Query.FieldByName('entity_handle').AsLargeInt;
      Spawn.X := Query.FieldByName('x').AsFloat;
      Spawn.Z := Query.FieldByName('z').AsFloat;
      Spawn.Y := Query.FieldByName('y').AsFloat;
      Spawn.Heading := Query.FieldByName('heading').AsFloat;
      Spawn.Population := Query.FieldByName('population').AsInteger;
      Spawn.SpawnRadius := Query.FieldByName('spawn_radius').AsFloat;
      Spawn.Enabled := Query.FieldByName('enabled').AsInteger <> 0;
      Spawn.Revision := Query.FieldByName('revision').AsLargeInt;
      ValidateSpawnDefinition(Spawn);
      Spawns.Add(Spawn);
      Query.Next;
    end;
    Result := TEmulatorContentSnapshot.Create(Revision, ABuildID,
      Mobs.ToArray, Spawns.ToArray);
  finally
    Spawns.Free;
    Mobs.Free;
    Query.Free;
  end;
end;

function TSQLiteContentRepository.PublishMob(
  const ADefinition: TEmulatorMobDefinition): Int64;
var
  Query: TFDQuery;
begin
  ValidateMobDefinition(ADefinition);
  Query := TFDQuery.Create(nil);
  try
    FConnection.StartTransaction;
    try
      Query.Connection := FConnection;
      Query.SQL.Text :=
        'UPDATE mob_definitions SET name=:name, max_hp=:max_hp, '+
        'attack_damage=:attack_damage, attack_speed=:attack_speed, '+
        'attack_min=:attack_min, physical_defense=:physical_defense, '+
        'movement_speed=:movement_speed, chase_speed=:chase_speed, '+
        'patrol_radius=:patrol_radius, '+
        'aggro_radius=:aggro_radius, attack_range=:attack_range, '+
        'leash_radius=:leash_radius, respawn_ms=:respawn_ms, '+
        'aggressive=:aggressive, enabled=:enabled, '+
        'revision=(SELECT active_revision+1 FROM content_meta WHERE id=1) '+
        'WHERE build_id=:build_id AND mob_id=:mob_id';
      Query.ParamByName('name').AsString := ADefinition.Name;
      Query.ParamByName('max_hp').AsInteger := ADefinition.MaxHP;
      Query.ParamByName('attack_damage').AsInteger := ADefinition.AttackDamage;
      Query.ParamByName('attack_min').AsInteger := ADefinition.AttackMin;
      Query.ParamByName('physical_defense').AsInteger := ADefinition.PhysicalDefense;
      Query.ParamByName('attack_speed').AsFloat := ADefinition.AttackSpeed;
      Query.ParamByName('movement_speed').AsFloat := ADefinition.MovementSpeed;
      Query.ParamByName('chase_speed').AsFloat := ADefinition.ChaseSpeed;
      Query.ParamByName('patrol_radius').AsFloat := ADefinition.PatrolRadius;
      Query.ParamByName('aggro_radius').AsFloat := ADefinition.AggroRadius;
      Query.ParamByName('attack_range').AsFloat := ADefinition.AttackRange;
      Query.ParamByName('leash_radius').AsFloat := ADefinition.LeashRadius;
      Query.ParamByName('respawn_ms').AsInteger := ADefinition.RespawnMS;
      Query.ParamByName('aggressive').AsInteger := Ord(ADefinition.Aggressive);
      Query.ParamByName('enabled').AsInteger := Ord(ADefinition.Enabled);
      Query.ParamByName('build_id').AsString := ADefinition.BuildID;
      Query.ParamByName('mob_id').AsLargeInt := ADefinition.MobID;
      Query.ExecSQL;
      if Query.RowsAffected <> 1 then
        raise EEmulatorContent.CreateFmt('Mob %s/%d was not found',
          [ADefinition.BuildID, ADefinition.MobID]);
      FConnection.Commit;
      Result := ActiveRevision;
    except
      if FConnection.InTransaction then
        FConnection.Rollback;
      raise;
    end;
  finally
    Query.Free;
  end;
end;

function TSQLiteContentRepository.PublishSpawn(
  const ADefinition: TEmulatorSpawnDefinition): Int64;
var
  Query: TFDQuery;
begin
  ValidateSpawnDefinition(ADefinition);
  Query := TFDQuery.Create(nil);
  try
    FConnection.StartTransaction;
    try
      Query.Connection := FConnection;
      Query.SQL.Text :=
        'UPDATE spawn_definitions SET map_id=:map_id, mob_id=:mob_id, '+
        'entity_handle=:entity_handle, x=:x, z=:z, y=:y, heading=:heading, '+
        'population=:population, spawn_radius=:spawn_radius, '+
        'enabled=:enabled, '+
        'revision=(SELECT active_revision+1 FROM content_meta WHERE id=1) '+
        'WHERE build_id=:build_id AND spawn_id=:spawn_id';
      Query.ParamByName('map_id').AsLargeInt := ADefinition.MapID;
      Query.ParamByName('mob_id').AsLargeInt := ADefinition.MobID;
      Query.ParamByName('entity_handle').AsLargeInt := ADefinition.EntityHandle;
      Query.ParamByName('x').AsFloat := ADefinition.X;
      Query.ParamByName('z').AsFloat := ADefinition.Z;
      Query.ParamByName('y').AsFloat := ADefinition.Y;
      Query.ParamByName('heading').AsFloat := ADefinition.Heading;
      Query.ParamByName('population').AsInteger := ADefinition.Population;
      Query.ParamByName('spawn_radius').AsFloat := ADefinition.SpawnRadius;
      Query.ParamByName('enabled').AsInteger := Ord(ADefinition.Enabled);
      Query.ParamByName('build_id').AsString := ADefinition.BuildID;
      Query.ParamByName('spawn_id').AsLargeInt := ADefinition.SpawnID;
      Query.ExecSQL;
      if Query.RowsAffected <> 1 then
        raise EEmulatorContent.CreateFmt('Spawn %s/%d was not found',
          [ADefinition.BuildID, ADefinition.SpawnID]);
      FConnection.Commit;
      Result := ActiveRevision;
    except
      if FConnection.InTransaction then
        FConnection.Rollback;
      raise;
    end;
  finally
    Query.Free;
  end;
end;

end.
