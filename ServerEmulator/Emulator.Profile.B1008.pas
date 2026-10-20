unit Emulator.Profile.B1008;

interface

uses
  Emulator.Content, Emulator.Runtime;

type
  TB1008ContentValidator = class(TInterfacedObject, IEmulatorContentValidator)
  public
    procedure Validate(const ASnapshot: IEmulatorContentSnapshot);
  end;

implementation

uses
  System.SysUtils, Emulator.World.B1008, Emulator.Berneo.B1008;

procedure TB1008ContentValidator.Validate(
  const ASnapshot: IEmulatorContentSnapshot);
var
  Mob: TEmulatorMobDefinition;
  Spawn: TEmulatorSpawnDefinition;
  Handle: Cardinal;
  Source:TEmulatorSpawnDefinition;Found:Boolean;
begin
  if not Assigned(ASnapshot) then
    raise EEmulatorContent.Create('b1008 content snapshot is empty');
  if not SameText(ASnapshot.BuildID,'b1008') then
    raise EEmulatorContent.Create('Unexpected content profile: '+ASnapshot.BuildID);
  if not ASnapshot.TryGetMob(B1008SpiderHandle,Mob) then
    raise EEmulatorContent.Create('b1008 requires Little Spider mob 120');
  for Handle in B1008SpiderHandles do
  begin
    if not ASnapshot.TryGetSpawn(Handle,Spawn) then
      raise EEmulatorContent.CreateFmt(
        'b1008 requires Little Spider spawn %d',[Handle]);
    if (Spawn.MapID<>B1008BerneoMapID) or
      (Spawn.MobID<>Mob.MobID) or (Spawn.EntityHandle<>Handle) or
      (Spawn.Population<>B1008SpiderGroupPopulation(Handle)) or
      (Abs(Spawn.SpawnRadius-B1008SpiderGroupRadius(Handle))>0.001) then
      raise EEmulatorContent.CreateFmt(
        'Little Spider spawn %d is incompatible with the b1008 wire profile',
        [Handle]);
  end;
  for Spawn in ASnapshot.GetSpawns do begin
    Found:=False;
    for Source in TB1008Berneo.Groups do if Source.EntityHandle=Spawn.EntityHandle then begin
      Found:=(Source.MobID=Spawn.MobID) and (Spawn.MapID=Source.MapID) and
        (Spawn.SpawnID=Spawn.EntityHandle) and (Spawn.Population<=Source.Population);
      Break;
    end;
    if not Found then raise EEmulatorContent.Create('Berneo spawn/template/level mismatch');
    TB1008Berneo.Mob(Spawn.MobID);
  end;
end;

end.
