unit Emulator.WorldState.B1008;

{$B-}

interface

uses System.SysUtils, System.SyncObjs, Winapi.Windows, Emulator.World.B1008;

type
  TB1008Position = record
    X, Z, Y, Heading: Single;
  end;
  TB1008WorldSnapshot = record
    Active, Moving, Restored, HasCheckpoint: Boolean;
    CharacterID, MapID: Cardinal;
    Position: TB1008Position; // Last client report, NOT a simulated position.
  end;

  // A short-lived announced movement segment, not a saved/simulated position.
  // An attack can arrive before the stop report; admit its current point only
  // if reachable along this segment. Server time is used, never client ticks.
  TB1008MovementAdmission = record
  private
    FActive: Boolean;
    FTick: UInt64;
    FFrom, FTo: TB1008Position;
  public
    procedure Reset;
    procedure Observe(const Movement: TB1008Movement; NowTick: UInt64);
    function Allows(X,Z,Y: Single; NowTick: UInt64;MovementMultiplier:Single=1): Boolean;
    function AllowsPickup(X,Z,Range,Speed: Single; NowTick: UInt64): Boolean;
  end;

  // One world owner at a time. Sessions borrow this server-owned store.
  // Empty path: memory only. Disk sidecar never modifies the character file.
  TB1008WorldStore = class
  private
    FLock: TCriticalSection;
    FFileLock: THandle;
    FPath: string;
    FOwner: TObject;
    FIdentity, FDisk: TBytes;
    FHasCheckpoint: Boolean;
    FCheckpoint: TB1008Position;
    procedure RequireOwner(Owner: TObject);
    procedure Publish(const Data: TBytes);
  public
    constructor Create(const Path: string = '');
    destructor Destroy; override;
    function Acquire(Owner: TObject; const Preview: TBytes): Boolean;
    procedure Release(Owner: TObject);
    function Restore(Owner: TObject; out Position: TB1008Position): Boolean;
    procedure Checkpoint(Owner: TObject; const Position: TB1008Position);
    class procedure Validate(const Position: TB1008Position); static;
  end;

implementation

uses System.Classes, System.Hash, System.Math, Emulator.Protocol.B1008;

const Magic: array[0..7] of Byte = ($4B,$31,$30,$30,$38,$57,$30,$31); // K1008W01

procedure TB1008MovementAdmission.Reset;
begin FActive:=False; end;

procedure TB1008MovementAdmission.Observe(const Movement: TB1008Movement; NowTick: UInt64);
begin
  Reset;
  if (Movement.Kind<>0) or (Movement.CharacterID<>1) or (Movement.Mode<>1) then Exit;
  FFrom.X:=Movement.FromX; FFrom.Z:=Movement.FromZ; FFrom.Y:=Movement.FromY;
  FTo.X:=Movement.ToX; FTo.Z:=Movement.ToZ; FTo.Y:=Movement.ToY;
  FTick:=NowTick; FActive:=True;
end;

function TB1008MovementAdmission.Allows(X,Z,Y: Single; NowTick: UInt64;MovementMultiplier:Single): Boolean;
var DX,DZ,DY,PX,PZ,PY,LengthSquared,T,Travel,Speed:Double;
begin
  Result:=False;
  if not FActive or (NowTick<FTick) then Exit;
  if NowTick-FTick>2000 then Exit;
  if IsNan(X) or IsNan(Z) or IsNan(Y) or IsInfinite(X) or
    IsInfinite(Z) or IsInfinite(Y) then Exit;
  DX:=FTo.X-FFrom.X; DZ:=FTo.Z-FFrom.Z; DY:=FTo.Y-FFrom.Y;
  LengthSquared:=Sqr(DX)+Sqr(DZ)+Sqr(DY);
  if IsNan(LengthSquared) or IsInfinite(LengthSquared) or (LengthSquared<0.01) then Exit;
  PX:=X-FFrom.X; PZ:=Z-FFrom.Z; PY:=Y-FFrom.Y;
  T:=EnsureRange((PX*DX+PZ*DZ+PY*DY)/LengthSquared,0.0,1.0);
  // Preserve the existing 10-unit position tolerance around the segment,
  // including its endpoints. No attacks far away/off the reported path.
  if Sqr(PX-T*DX)+Sqr(PZ-T*DZ)+Sqr(PY-T*DY)>100 then Exit;
  Travel:=Sqrt(Sqr(PX)+Sqr(PZ)+Sqr(PY));
  if IsNan(MovementMultiplier) or IsInfinite(MovementMultiplier) or
    (MovementMultiplier<1) or (MovementMultiplier>2) then Exit;
  Speed:=Max(B1008PlayerSpeedA,B1008PlayerSpeedB)*MovementMultiplier;
  // Technical jitter allowance: 100 ms, in addition to the old 10 units.
  Result:=Travel<=Speed*((NowTick-FTick)/1000.0+0.1)+10;
end;

function TB1008MovementAdmission.AllowsPickup(X,Z,Range,Speed: Single;
  NowTick: UInt64): Boolean;
var DX,DZ,PX,PZ,LengthSquared,Reach,T: Double;
begin
  Result:=False;
  if not FActive or (NowTick<FTick) then Exit;
  if NowTick-FTick>2000 then Exit;
  if IsNan(X) or IsNan(Z) or IsNan(Range) or IsNan(Speed) or
    IsInfinite(X) or IsInfinite(Z) or IsInfinite(Range) or IsInfinite(Speed) or
    (Range<0) or (Speed<=0) then Exit;
  DX:=FTo.X-FFrom.X;DZ:=FTo.Z-FFrom.Z;
  LengthSquared:=Sqr(DX)+Sqr(DZ);
  if IsNan(LengthSquared) or IsInfinite(LengthSquared) or (LengthSquared<0.01) then Exit;
  // Pickup can precede the next position report. Only the reachable prefix
  // of the announced path counts, with the existing 100 ms transport margin.
  Reach:=Min(1.0,Speed*((NowTick-FTick)/1000.0+0.1)/Sqrt(LengthSquared));
  PX:=X-FFrom.X;PZ:=Z-FFrom.Z;
  T:=EnsureRange((PX*DX+PZ*DZ)/LengthSquared,0.0,Reach);
  Result:=Sqr(PX-T*DX)+Sqr(PZ-T*DZ)<=Sqr(Range);
end;

function Digest(const B: TBytes): TBytes;
var H: THashSHA2;
begin H := THashSHA2.Create; H.Update(B); Result := H.HashAsBytes; end;

function Equal(const A,B: TBytes): Boolean;
begin
  Result := Length(A)=Length(B);
  if Result and (Length(A)>0) then Result := CompareMem(@A[0],@B[0],Length(A));
end;

function ReadDisk(const Path: string): TBytes;
var S: TFileStream;
begin
  Result := nil;
  S := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if S.Size<>96 then raise Exception.Create('Invalid world checkpoint size; file preserved');
    SetLength(Result,96); S.ReadBuffer(Result[0],96);
  finally S.Free; end;
end;

class procedure TB1008WorldStore.Validate(const Position: TB1008Position);
  procedure Finite(V: Single);
  begin
    if IsNan(V) or IsInfinite(V) then raise EKarosProtocol.Create('Non-finite checkpoint');
    if Abs(V)>1000000 then raise EKarosProtocol.Create('Checkpoint outside diagnostic bounds');
  end;
begin
  Finite(Position.X); Finite(Position.Z); Finite(Position.Y); Finite(Position.Heading);
end;

constructor TB1008WorldStore.Create(const Path: string);
var H: TBytes; ID,Map: Cardinal;
begin
  inherited Create;
  FFileLock := INVALID_HANDLE_VALUE; FLock := TCriticalSection.Create;
  if Path='' then Exit;
  FPath := ExpandFileName(Path);
  if not ForceDirectories(ExtractFileDir(FPath)) then raise Exception.Create('Cannot create world storage directory');
  FFileLock := CreateFile(PChar(FPath+'.lock'),GENERIC_READ or GENERIC_WRITE,
    0,nil,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,0);
  Win32Check(FFileLock<>INVALID_HANDLE_VALUE);
  if not FileExists(FPath) then Exit;
  FDisk := ReadDisk(FPath);
  if not CompareMem(@FDisk[0],@Magic[0],8) then raise Exception.Create('Unknown world checkpoint format; file preserved');
  H := Digest(Copy(FDisk,40,56));
  if not CompareMem(@FDisk[8],@H[0],32) then raise Exception.Create('World checkpoint checksum mismatch; file preserved');
  Move(FDisk[72],ID,4); Move(FDisk[76],Map,4);
  if (ID<>1) or (Map<>B1008BerneoMapID) then raise Exception.Create('Unsupported checkpoint character/map; file preserved');
  Move(FDisk[80],FCheckpoint.X,4); Move(FDisk[84],FCheckpoint.Z,4);
  Move(FDisk[88],FCheckpoint.Y,4); Move(FDisk[92],FCheckpoint.Heading,4);
  Validate(FCheckpoint);
  FIdentity := Copy(FDisk,40,32); FHasCheckpoint := True;
end;

destructor TB1008WorldStore.Destroy;
begin
  if (FFileLock<>0) and (FFileLock<>INVALID_HANDLE_VALUE) then CloseHandle(FFileLock);
  FLock.Free;
  inherited;
end;

function TB1008WorldStore.Acquire(Owner: TObject; const Preview: TBytes): Boolean;
var Normalized,Identity: TBytes;
begin
  if Owner=nil then raise Exception.Create('Missing world owner');
  if (Length(Preview)<$152) or (Preview[0]<>2) or (Preview[1]<>1) or
    (TB1008Wire.ReadBE32(Preview,7)<>1) then raise EKarosProtocol.Create('Invalid checkpoint identity');
  Normalized := Copy(Preview); FillChar(Normalized[2],4,0);
  Identity := Digest(Normalized);
  FLock.Acquire;
  try
    Result := (FOwner=nil) or (FOwner=Owner);
    if not Result then Exit;
    if FHasCheckpoint and not Equal(Identity,FIdentity) then
      raise Exception.Create('World checkpoint belongs to a different character; file preserved');
    FIdentity := Identity; FOwner := Owner;
  finally FLock.Release; end;
end;

procedure TB1008WorldStore.RequireOwner(Owner: TObject);
begin
  if (Owner=nil) or (FOwner<>Owner) then raise Exception.Create('Session does not own world character');
end;

procedure TB1008WorldStore.Release(Owner: TObject);
begin
  FLock.Acquire;
  try if FOwner=Owner then FOwner := nil; finally FLock.Release; end;
end;

function TB1008WorldStore.Restore(Owner: TObject; out Position: TB1008Position): Boolean;
begin
  FLock.Acquire;
  try
    RequireOwner(Owner); Result := FHasCheckpoint;
    Position := Default(TB1008Position);
    if Result then Position := FCheckpoint;
  finally FLock.Release; end;
end;

procedure TB1008WorldStore.Publish(const Data: TBytes);
var Temp: string; G: TGUID; Handle: THandle; S: THandleStream; Flags: DWORD;
begin
  if FPath='' then Exit;
  // Refuse a file created/changed externally since load or the last commit.
  if Length(FDisk)=0 then
  begin
    if FileExists(FPath) then raise Exception.Create('External world checkpoint appeared; file preserved');
  end
  else if not FileExists(FPath) or not Equal(ReadDisk(FPath),FDisk) then
    raise Exception.Create('World checkpoint changed externally; file preserved');
  CreateGUID(G); Temp := FPath+'.'+GUIDToString(G)+'.tmp';
  Handle := CreateFile(PChar(Temp),GENERIC_WRITE,0,nil,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);
  Win32Check(Handle<>INVALID_HANDLE_VALUE);
  try
    try
      S := THandleStream.Create(Handle);
      try S.WriteBuffer(Data[0],Length(Data)); Win32Check(FlushFileBuffers(Handle));
      finally S.Free; end;
    finally CloseHandle(Handle); end;
    Flags := MOVEFILE_WRITE_THROUGH;
    if Length(FDisk)>0 then Flags := Flags or MOVEFILE_REPLACE_EXISTING;
    Win32Check(MoveFileEx(PChar(Temp),PChar(FPath),Flags));
  finally
    if FileExists(Temp) then Winapi.Windows.DeleteFile(PChar(Temp));
  end;
end;

procedure TB1008WorldStore.Checkpoint(Owner: TObject; const Position: TB1008Position);
var Data,H: TBytes; ID,Map: Cardinal;
begin
  Validate(Position);
  FLock.Acquire;
  try
    RequireOwner(Owner);
    Data := nil; SetLength(Data,96); Move(Magic[0],Data[0],8);
    Move(FIdentity[0],Data[40],32); ID := 1; Map := B1008BerneoMapID;
    Move(ID,Data[72],4); Move(Map,Data[76],4);
    Move(Position.X,Data[80],4); Move(Position.Z,Data[84],4);
    Move(Position.Y,Data[88],4); Move(Position.Heading,Data[92],4);
    H := Digest(Copy(Data,40,56)); Move(H[0],Data[8],32);
    if Equal(Data,FDisk) then Exit; // Repeated stationary report: no extra write.
    Publish(Data); // Commit first: failed IO must not produce a phantom checkpoint.
    FDisk := Data; FCheckpoint := Position; FHasCheckpoint := True;
  finally FLock.Release; end;
end;

end.
