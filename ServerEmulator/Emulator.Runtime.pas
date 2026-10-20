unit Emulator.Runtime;

interface

uses
  System.SysUtils, System.SyncObjs, Emulator.Content, Emulator.Repository;

type
  IEmulatorContentValidator = interface
    ['{A8DFF855-D282-41F2-93D7-46D70DB78F7D}']
    procedure Validate(const ASnapshot: IEmulatorContentSnapshot);
  end;

  TEmulatorRuntimeManager = class
  private
    FRepository: IEmulatorContentRepository;
    FBuildID: string;
    FLock: TCriticalSection;
    FSnapshot: IEmulatorContentSnapshot;
    FValidator: IEmulatorContentValidator;
  public
    constructor Create(const ARepository: IEmulatorContentRepository;
      const ABuildID: string;
      const AValidator: IEmulatorContentValidator = nil);
    destructor Destroy; override;
    function Reload(out AStatus: string): Boolean;
    function AcquireSnapshot: IEmulatorContentSnapshot;
    function Revision: Int64;
    function Loaded: Boolean;
    function DatabasePath: string;
  end;

implementation

constructor TEmulatorRuntimeManager.Create(
  const ARepository: IEmulatorContentRepository; const ABuildID: string;
  const AValidator: IEmulatorContentValidator);
begin
  inherited Create;
  if not Assigned(ARepository) then
    raise EArgumentNilException.Create('Content repository is required');
  if Trim(ABuildID) = '' then
    raise EArgumentException.Create('Build ID is required');
  FRepository := ARepository;
  FBuildID := ABuildID;
  FValidator := AValidator;
  FLock := TCriticalSection.Create;
end;

destructor TEmulatorRuntimeManager.Destroy;
begin
  FLock.Acquire;
  try
    FSnapshot := nil;
  finally
    FLock.Release;
  end;
  FLock.Free;
  FRepository := nil;
  FValidator := nil;
  inherited Destroy;
end;

function TEmulatorRuntimeManager.Reload(out AStatus: string): Boolean;
var
  Candidate: IEmulatorContentSnapshot;
begin
  Result := False;
  try
    Candidate := FRepository.LoadSnapshot(FBuildID);
    if not Assigned(Candidate) then
      raise EEmulatorContent.Create('Repository returned an empty snapshot');
    if Assigned(FValidator) then
      FValidator.Validate(Candidate);
    FLock.Acquire;
    try
      FSnapshot := Candidate;
    finally
      FLock.Release;
    end;
    AStatus := Format('revision %d, mobs %d, spawns %d',
      [Candidate.Revision, Candidate.MobCount, Candidate.SpawnCount]);
    Result := True;
  except
    on E: Exception do
      AStatus := E.Message;
  end;
end;

function TEmulatorRuntimeManager.AcquireSnapshot: IEmulatorContentSnapshot;
begin
  FLock.Acquire;
  try
    Result := FSnapshot;
  finally
    FLock.Release;
  end;
end;

function TEmulatorRuntimeManager.Revision: Int64;
var
  Snapshot: IEmulatorContentSnapshot;
begin
  Snapshot := AcquireSnapshot;
  if Assigned(Snapshot) then
    Result := Snapshot.Revision
  else
    Result := 0;
end;

function TEmulatorRuntimeManager.Loaded: Boolean;
var
  Snapshot: IEmulatorContentSnapshot;
begin
  Snapshot := AcquireSnapshot;
  Result := Assigned(Snapshot);
end;

function TEmulatorRuntimeManager.DatabasePath: string;
begin
  Result := FRepository.DatabasePath;
end;

end.
