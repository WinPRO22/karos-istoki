unit Emulator.Content;

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  EEmulatorContent = class(Exception);

  TEmulatorMobDefinition = record
    BuildID: string;
    MobID: Cardinal;
    Name: string;
    MaxHP: Integer;
    AttackDamage: Integer;
    // >0: raw attack range; zero preserves legacy nominal-damage overrides.
    AttackMin: Integer;
    PhysicalDefense: Integer;
    AttackSpeed: Single;
    MovementSpeed: Single;
    ChaseSpeed: Single;
    PatrolRadius: Single;
    AggroRadius: Single;
    AttackRange: Single;
    LeashRadius: Single;
    RespawnMS: Integer;
    Aggressive: Boolean;
    Enabled: Boolean;
    Revision: Int64;
  end;

  TEmulatorSpawnDefinition = record
    BuildID: string;
    SpawnID: Cardinal;
    MapID: Cardinal;
    MobID: Cardinal;
    EntityHandle: Cardinal;
    X: Single;
    Z: Single;
    Y: Single;
    Heading: Single;
    Population: Integer;
    SpawnRadius: Single;
    Enabled: Boolean;
    Revision: Int64;
  end;

  IEmulatorContentSnapshot = interface
    ['{089EA47F-C5EC-4869-85C6-2140CB3EA279}']
    function GetRevision: Int64;
    function GetBuildID: string;
    function GetMobCount: Integer;
    function GetSpawnCount: Integer;
    function TryGetMob(AMobID: Cardinal;
      out ADefinition: TEmulatorMobDefinition): Boolean;
    function TryGetSpawn(ASpawnID: Cardinal;
      out ADefinition: TEmulatorSpawnDefinition): Boolean;
    function GetSpawns: TArray<TEmulatorSpawnDefinition>;
    property Revision: Int64 read GetRevision;
    property BuildID: string read GetBuildID;
    property MobCount: Integer read GetMobCount;
    property SpawnCount: Integer read GetSpawnCount;
  end;

  TEmulatorContentSnapshot = class(TInterfacedObject, IEmulatorContentSnapshot)
  private
    FRevision: Int64;
    FBuildID: string;
    FMobs: TDictionary<Cardinal,TEmulatorMobDefinition>;
    FSpawns: TDictionary<Cardinal,TEmulatorSpawnDefinition>;
    function GetRevision: Int64;
    function GetBuildID: string;
    function GetMobCount: Integer;
    function GetSpawnCount: Integer;
  public
    constructor Create(ARevision: Int64; const ABuildID: string;
      const AMobs: TArray<TEmulatorMobDefinition>;
      const ASpawns: TArray<TEmulatorSpawnDefinition>);
    destructor Destroy; override;
    function TryGetMob(AMobID: Cardinal;
      out ADefinition: TEmulatorMobDefinition): Boolean;
    function TryGetSpawn(ASpawnID: Cardinal;
      out ADefinition: TEmulatorSpawnDefinition): Boolean;
    function GetSpawns: TArray<TEmulatorSpawnDefinition>;
  end;

procedure ValidateMobDefinition(const ADefinition: TEmulatorMobDefinition);
procedure ValidateSpawnDefinition(const ADefinition: TEmulatorSpawnDefinition);

implementation

uses
  System.Math;

procedure RequireFinite(const AName: string; AValue: Single);
begin
  if IsNan(AValue) or IsInfinite(AValue) then
    raise EEmulatorContent.Create(AName + ' must be finite');
end;

procedure ValidateMobDefinition(const ADefinition: TEmulatorMobDefinition);
begin
  if Trim(ADefinition.BuildID) = '' then
    raise EEmulatorContent.Create('Mob build ID is empty');
  if ADefinition.MobID = 0 then
    raise EEmulatorContent.Create('Mob ID must be nonzero');
  if Trim(ADefinition.Name) = '' then
    raise EEmulatorContent.Create('Mob name is empty');
  if ADefinition.MaxHP <= 0 then
    raise EEmulatorContent.Create('Mob maximum HP must be positive');
  if ADefinition.AttackDamage < 0 then
    raise EEmulatorContent.Create('Mob attack damage cannot be negative');
  if (ADefinition.AttackMin<0) or (ADefinition.AttackMin>ADefinition.AttackDamage) or
    (ADefinition.AttackMin>1000000) or
    ((ADefinition.AttackMin>0) and (ADefinition.AttackDamage>1000000)) then
    raise EEmulatorContent.Create('Invalid mob raw attack range');
  if (ADefinition.PhysicalDefense<0) or (ADefinition.PhysicalDefense>1000000) then
    raise EEmulatorContent.Create('Invalid mob physical defense');
  RequireFinite('Mob attack speed', ADefinition.AttackSpeed);
  RequireFinite('Mob movement speed', ADefinition.MovementSpeed);
  RequireFinite('Mob chase speed', ADefinition.ChaseSpeed);
  RequireFinite('Mob patrol radius', ADefinition.PatrolRadius);
  RequireFinite('Mob aggro radius', ADefinition.AggroRadius);
  RequireFinite('Mob attack range', ADefinition.AttackRange);
  RequireFinite('Mob leash radius', ADefinition.LeashRadius);
  if ADefinition.AttackSpeed <= 0 then
    raise EEmulatorContent.Create('Mob attack speed must be positive');
  if ADefinition.MovementSpeed < 0 then
    raise EEmulatorContent.Create('Mob movement speed cannot be negative');
  if ADefinition.ChaseSpeed <= 0 then
    raise EEmulatorContent.Create('Mob chase speed must be positive');
  if (ADefinition.PatrolRadius < 0) or (ADefinition.AggroRadius < 0) or
    (ADefinition.AttackRange < 0) or (ADefinition.LeashRadius < 0) then
    raise EEmulatorContent.Create('Mob radii cannot be negative');
  if ADefinition.AttackRange > ADefinition.LeashRadius then
    raise EEmulatorContent.Create('Mob attack range exceeds leash radius');
  if ADefinition.PatrolRadius > ADefinition.LeashRadius then
    raise EEmulatorContent.Create('Mob patrol radius exceeds leash radius');
  if ADefinition.RespawnMS < 0 then
    raise EEmulatorContent.Create('Mob respawn delay cannot be negative');
  if ADefinition.Revision <= 0 then
    raise EEmulatorContent.Create('Mob revision must be positive');
end;

procedure ValidateSpawnDefinition(const ADefinition: TEmulatorSpawnDefinition);
begin
  if Trim(ADefinition.BuildID) = '' then
    raise EEmulatorContent.Create('Spawn build ID is empty');
  if (ADefinition.SpawnID = 0) or (ADefinition.MapID = 0) or
    (ADefinition.MobID = 0) or (ADefinition.EntityHandle = 0) then
    raise EEmulatorContent.Create('Spawn identifiers must be nonzero');
  RequireFinite('Spawn X', ADefinition.X);
  RequireFinite('Spawn Z', ADefinition.Z);
  RequireFinite('Spawn Y', ADefinition.Y);
  RequireFinite('Spawn heading', ADefinition.Heading);
  RequireFinite('Spawn radius', ADefinition.SpawnRadius);
  if ADefinition.Population <= 0 then
    raise EEmulatorContent.Create('Spawn population must be positive');
  if ADefinition.SpawnRadius < 0 then
    raise EEmulatorContent.Create('Spawn radius cannot be negative');
  if ADefinition.Revision <= 0 then
    raise EEmulatorContent.Create('Spawn revision must be positive');
end;

constructor TEmulatorContentSnapshot.Create(ARevision: Int64;
  const ABuildID: string; const AMobs: TArray<TEmulatorMobDefinition>;
  const ASpawns: TArray<TEmulatorSpawnDefinition>);
var
  Mob: TEmulatorMobDefinition;
  Spawn: TEmulatorSpawnDefinition;
begin
  inherited Create;
  if ARevision <= 0 then
    raise EEmulatorContent.Create('Content revision must be positive');
  if Trim(ABuildID) = '' then
    raise EEmulatorContent.Create('Snapshot build ID is empty');
  FRevision := ARevision;
  FBuildID := ABuildID;
  FMobs := TDictionary<Cardinal,TEmulatorMobDefinition>.Create;
  FSpawns := TDictionary<Cardinal,TEmulatorSpawnDefinition>.Create;
  try
    for Mob in AMobs do
    begin
      ValidateMobDefinition(Mob);
      if not SameText(Mob.BuildID, FBuildID) then
        raise EEmulatorContent.Create('Mob belongs to another build');
      if Mob.Revision > FRevision then
        raise EEmulatorContent.Create('Mob revision exceeds snapshot revision');
      if FMobs.ContainsKey(Mob.MobID) then
        raise EEmulatorContent.CreateFmt('Duplicate mob ID %d', [Mob.MobID]);
      FMobs.Add(Mob.MobID, Mob);
    end;
    for Spawn in ASpawns do
    begin
      ValidateSpawnDefinition(Spawn);
      if not SameText(Spawn.BuildID, FBuildID) then
        raise EEmulatorContent.Create('Spawn belongs to another build');
      if Spawn.Revision > FRevision then
        raise EEmulatorContent.Create('Spawn revision exceeds snapshot revision');
      if not FMobs.ContainsKey(Spawn.MobID) then
        raise EEmulatorContent.CreateFmt('Spawn %d references missing mob %d',
          [Spawn.SpawnID, Spawn.MobID]);
      if FSpawns.ContainsKey(Spawn.SpawnID) then
        raise EEmulatorContent.CreateFmt('Duplicate spawn ID %d', [Spawn.SpawnID]);
      FSpawns.Add(Spawn.SpawnID, Spawn);
    end;
  except
    FSpawns.Free;
    FMobs.Free;
    raise;
  end;
end;

destructor TEmulatorContentSnapshot.Destroy;
begin
  FSpawns.Free;
  FMobs.Free;
  inherited Destroy;
end;

function TEmulatorContentSnapshot.GetRevision: Int64;
begin
  Result := FRevision;
end;

function TEmulatorContentSnapshot.GetBuildID: string;
begin
  Result := FBuildID;
end;

function TEmulatorContentSnapshot.GetMobCount: Integer;
begin
  Result := FMobs.Count;
end;

function TEmulatorContentSnapshot.GetSpawnCount: Integer;
begin
  Result := FSpawns.Count;
end;

function TEmulatorContentSnapshot.TryGetMob(AMobID: Cardinal;
  out ADefinition: TEmulatorMobDefinition): Boolean;
begin
  Result := FMobs.TryGetValue(AMobID, ADefinition);
end;

function TEmulatorContentSnapshot.TryGetSpawn(ASpawnID: Cardinal;
  out ADefinition: TEmulatorSpawnDefinition): Boolean;
begin
  Result := FSpawns.TryGetValue(ASpawnID, ADefinition);
end;

function TEmulatorContentSnapshot.GetSpawns: TArray<TEmulatorSpawnDefinition>;
var
  Spawn: TEmulatorSpawnDefinition;
  Index: Integer;
begin
  SetLength(Result,FSpawns.Count);
  Index:=0;
  for Spawn in FSpawns.Values do
  begin
    Result[Index]:=Spawn;
    Inc(Index);
  end;
end;

end.
