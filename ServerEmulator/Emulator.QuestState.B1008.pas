unit Emulator.QuestState.B1008;

{$B-}

interface

uses System.SysUtils, System.SyncObjs, Winapi.Windows;

type
  // One quest and five kills. Immutable acceptance, append-only progress.1..5,
  // then one immutable rewarded marker: never overwrite an existing user's file.
  TB1008QuestStore = class
  private
    FLock: TCriticalSection;
    FFileLock: THandle;
    FPath: string;
    FOwner: TObject;
    FIdentity, FDisk: TBytes;
    FAccepted: Boolean;
    FRewarded: Boolean;
    FProgress: Cardinal;
    FProgressDisk: array[1..5] of TBytes;
    FRewardDisk: TBytes;
    FConsumed: array[0..1] of Cardinal;
    FConsumeDisk: array[0..1,1..3] of TBytes;
    procedure RequireOwner(Owner: TObject);
    procedure CheckDisk;
    procedure Publish(const Data: TBytes; const Destination: string);
    function ProgressPath(Index: Integer): string;
    function RewardPath: string;
    function ConsumePath(ItemIndex, UseIndex: Integer): string;
  public
    constructor Create(const Path: string = '');
    destructor Destroy; override;
    function Acquire(Owner: TObject; const Preview: TBytes): Boolean;
    procedure Release(Owner: TObject);
    function Active(Owner: TObject): Boolean;
    function Accept(Owner: TObject): Boolean; // True=first commit, False=already active.
    function Progress(Owner: TObject): Cardinal;
    function RecordSpiderKill(Owner: TObject): Cardinal;
    function Rewarded(Owner: TObject): Boolean;
    function Complete(Owner: TObject): Boolean; // True=first durable reward grant.
    function RewardItemCount(Owner: TObject; ItemID: Cardinal): Cardinal;
    function ConsumeRewardItem(Owner: TObject; ItemID: Cardinal): Cardinal;
  end;

implementation

uses System.Classes, System.Hash, Emulator.Protocol.B1008, Emulator.Quest.B1008,
  Emulator.Inventory.B1008;

const Magic: array[0..7] of Byte = ($4B,$31,$30,$30,$38,$51,$30,$31); // K1008Q01

function Digest(const Data: TBytes): TBytes;
var H: THashSHA2;
begin H:=THashSHA2.Create; H.Update(Data); Result:=H.HashAsBytes; end;

function Equal(const A,B: TBytes): Boolean;
begin
  Result:=Length(A)=Length(B);
  if Result and (Length(A)>0) then Result:=CompareMem(@A[0],@B[0],Length(A));
end;

function ReadDisk(const Path: string): TBytes;
var S: TFileStream;
begin
  Result:=nil; S:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if S.Size<>84 then raise Exception.Create('Invalid quest state size; file preserved');
    SetLength(Result,84); S.ReadBuffer(Result[0],84);
  finally S.Free; end;
end;

constructor TB1008QuestStore.Create(const Path: string);
var H,Data: TBytes; ID,Quest,Count,ItemID: Cardinal; I,J: Integer;
begin
  inherited Create; FFileLock:=INVALID_HANDLE_VALUE; FLock:=TCriticalSection.Create;
  if Path='' then Exit;
  FPath:=ExpandFileName(Path);
  if not ForceDirectories(ExtractFileDir(FPath)) then raise Exception.Create('Cannot create quest directory');
  FFileLock:=CreateFile(PChar(FPath+'.lock'),GENERIC_READ or GENERIC_WRITE,
    0,nil,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,0);
  Win32Check(FFileLock<>INVALID_HANDLE_VALUE);
  if not FileExists(FPath) then begin
    for I:=1 to 5 do
      if FileExists(ProgressPath(I)) then raise Exception.Create('Orphan quest progress; files preserved');
    if FileExists(RewardPath) then raise Exception.Create('Orphan quest reward; file preserved');
    for I:=0 to 1 do for J:=1 to 3 do
      if FileExists(ConsumePath(I,J)) then
        raise Exception.Create('Orphan reward-item use; file preserved');
    Exit;
  end;
  FDisk:=ReadDisk(FPath);
  if not CompareMem(@FDisk[0],@Magic[0],8) then raise Exception.Create('Unknown quest state format; file preserved');
  H:=Digest(Copy(FDisk,40,44));
  if not CompareMem(@FDisk[8],@H[0],32) then raise Exception.Create('Quest checksum mismatch; file preserved');
  Move(FDisk[72],ID,4); Move(FDisk[76],Quest,4); Move(FDisk[80],Count,4);
  if (ID<>1) or (Quest<>B1008ProtectingTheFarmID) or (Count<>0) then
    raise Exception.Create('Unsupported quest state; file preserved');
  FIdentity:=Copy(FDisk,40,32); FAccepted:=True;
  for I:=1 to 5 do if FileExists(ProgressPath(I)) then begin
    Data:=ReadDisk(ProgressPath(I)); H:=Digest(Copy(Data,40,44));
    Move(Data[72],ID,4); Move(Data[76],Quest,4); Move(Data[80],Count,4);
    if not CompareMem(@Data[0],@Magic[0],7) or (Data[7]<>Ord('2')) or
      not CompareMem(@Data[8],@H[0],32) or
      not CompareMem(@Data[40],@FIdentity[0],32) or (ID<>1) or
      (Quest<>B1008ProtectingTheFarmID) or (Count<>Cardinal(I)) or
      (FProgress<>Cardinal(I-1)) then
      raise Exception.Create('Invalid quest progress chain; files preserved');
    FProgressDisk[I]:=Data; FProgress:=I;
  end;
  if FileExists(RewardPath) then begin
    if FProgress<>5 then raise Exception.Create('Reward without complete progress; file preserved');
    Data:=ReadDisk(RewardPath); H:=Digest(Copy(Data,40,44));
    Move(Data[72],ID,4); Move(Data[76],Quest,4); Move(Data[80],Count,4);
    if not CompareMem(@Data[0],@Magic[0],7) or (Data[7]<>Ord('3')) or
      not CompareMem(@Data[8],@H[0],32) or
      not CompareMem(@Data[40],@FIdentity[0],32) or (ID<>1) or
      (Quest<>B1008ProtectingTheFarmID) or (Count<>5) then
      raise Exception.Create('Invalid quest reward marker; file preserved');
    FRewardDisk:=Data; FRewarded:=True;
  end;
  for I:=0 to 1 do for J:=1 to 3 do
    if FileExists(ConsumePath(I,J)) then begin
      if not FRewarded then
        raise Exception.Create('Reward-item use without reward; files preserved');
      Data:=ReadDisk(ConsumePath(I,J)); H:=Digest(Copy(Data,40,44));
      Move(Data[72],ID,4); Move(Data[76],ItemID,4); Move(Data[80],Count,4);
      if I=0 then Quest:=B1008BeginnerHealingPotionID
      else Quest:=B1008BeginnerManaPotionID;
      if not CompareMem(@Data[0],@Magic[0],7) or (Data[7]<>Ord('4')) or
        not CompareMem(@Data[8],@H[0],32) or
        not CompareMem(@Data[40],@FIdentity[0],32) or (ID<>1) or
        (ItemID<>Quest) or (Count<>Cardinal(J)) or
        (FConsumed[I]<>Cardinal(J-1)) then
        raise Exception.Create('Invalid reward-item use chain; files preserved');
      FConsumeDisk[I,J]:=Data; FConsumed[I]:=J;
    end;
end;

destructor TB1008QuestStore.Destroy;
begin
  if (FFileLock<>0) and (FFileLock<>INVALID_HANDLE_VALUE) then CloseHandle(FFileLock);
  FLock.Free; inherited;
end;

procedure TB1008QuestStore.CheckDisk;
var I,J: Integer;
begin
  if FPath='' then Exit;
  if Length(FDisk)=0 then begin
    if FileExists(FPath) then raise Exception.Create('External quest state appeared; file preserved');
  end else if not FileExists(FPath) or not Equal(ReadDisk(FPath),FDisk) then
    raise Exception.Create('Quest state changed externally; file preserved');
  for I:=1 to 5 do
    if Length(FProgressDisk[I])=0 then begin
      if FileExists(ProgressPath(I)) then raise Exception.Create('External quest progress appeared; file preserved');
    end else if not FileExists(ProgressPath(I)) or
      not Equal(ReadDisk(ProgressPath(I)),FProgressDisk[I]) then
      raise Exception.Create('Quest progress changed externally; file preserved');
  if Length(FRewardDisk)=0 then begin
    if FileExists(RewardPath) then raise Exception.Create('External quest reward appeared; file preserved');
  end else if not FileExists(RewardPath) or
    not Equal(ReadDisk(RewardPath),FRewardDisk) then
    raise Exception.Create('Quest reward changed externally; file preserved');
  for I:=0 to 1 do for J:=1 to 3 do
    if Length(FConsumeDisk[I,J])=0 then begin
      if FileExists(ConsumePath(I,J)) then
        raise Exception.Create('External reward-item use appeared; file preserved');
    end else if not FileExists(ConsumePath(I,J)) or
      not Equal(ReadDisk(ConsumePath(I,J)),FConsumeDisk[I,J]) then
      raise Exception.Create('Reward-item use changed externally; file preserved');
end;

function TB1008QuestStore.ProgressPath(Index: Integer): string;
begin Result:=FPath+'.progress.'+IntToStr(Index); end;

function TB1008QuestStore.RewardPath: string;
begin Result:=FPath+'.rewarded'; end;

function TB1008QuestStore.ConsumePath(ItemIndex, UseIndex: Integer): string;
const Names: array[0..1] of string = ('healing','mana');
begin Result:=FPath+'.used.'+Names[ItemIndex]+'.'+IntToStr(UseIndex); end;

function TB1008QuestStore.Acquire(Owner: TObject; const Preview: TBytes): Boolean;
var Normalized,Identity: TBytes;
begin
  if Owner=nil then raise Exception.Create('Missing quest owner');
  if (Length(Preview)<$152) or (Preview[0]<>2) or (Preview[1]<>1) or
    (TB1008Wire.ReadBE32(Preview,7)<>1) then raise EKarosProtocol.Create('Invalid quest identity');
  Normalized:=Copy(Preview); FillChar(Normalized[2],4,0); Identity:=Digest(Normalized);
  FLock.Acquire;
  try
    Result:=(FOwner=nil) or (FOwner=Owner); if not Result then Exit;
    CheckDisk;
    if FAccepted and not Equal(Identity,FIdentity) then
      raise Exception.Create('Quest belongs to a different character; file preserved');
    FIdentity:=Identity; FOwner:=Owner;
  finally FLock.Release; end;
end;

procedure TB1008QuestStore.RequireOwner(Owner: TObject);
begin
  if (Owner=nil) or (FOwner<>Owner) then raise Exception.Create('Session does not own quest state');
end;

procedure TB1008QuestStore.Release(Owner: TObject);
begin FLock.Acquire; try if FOwner=Owner then FOwner:=nil; finally FLock.Release; end; end;

function TB1008QuestStore.Active(Owner: TObject): Boolean;
begin
  FLock.Acquire;
  try RequireOwner(Owner); CheckDisk; Result:=FAccepted and not FRewarded;
  finally FLock.Release; end;
end;

procedure TB1008QuestStore.Publish(const Data: TBytes; const Destination: string);
var Temp: string; G: TGUID; H: THandle; S: THandleStream;
begin
  if FPath='' then Exit;
  CreateGUID(G); Temp:=Destination+'.'+GUIDToString(G)+'.tmp';
  H:=CreateFile(PChar(Temp),GENERIC_WRITE,0,nil,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,0);
  Win32Check(H<>INVALID_HANDLE_VALUE);
  try
    try
      S:=THandleStream.Create(H);
      try S.WriteBuffer(Data[0],Length(Data)); Win32Check(FlushFileBuffers(H)); finally S.Free; end;
    finally CloseHandle(H); end;
    // No REPLACE_EXISTING: even a file that appeared during commit is preserved.
    CheckDisk;
    Win32Check(MoveFileEx(PChar(Temp),PChar(Destination),MOVEFILE_WRITE_THROUGH));
  finally if FileExists(Temp) then Winapi.Windows.DeleteFile(PChar(Temp)); end;
end;

function TB1008QuestStore.Accept(Owner: TObject): Boolean;
var Data,H: TBytes; V: Cardinal;
begin
  FLock.Acquire;
  try
    RequireOwner(Owner); CheckDisk; Result:=not FAccepted; if not Result then Exit;
    Data:=nil; SetLength(Data,84); Move(Magic[0],Data[0],8);
    Move(FIdentity[0],Data[40],32); V:=1; Move(V,Data[72],4);
    V:=B1008ProtectingTheFarmID; Move(V,Data[76],4);
    H:=Digest(Copy(Data,40,44)); Move(H[0],Data[8],32);
    Publish(Data,FPath); // No phantom success on failed IO.
    FDisk:=Data; FAccepted:=True;
  finally FLock.Release; end;
end;

function TB1008QuestStore.Progress(Owner: TObject): Cardinal;
begin
  FLock.Acquire;
  try RequireOwner(Owner); CheckDisk; Result:=FProgress; finally FLock.Release; end;
end;

function TB1008QuestStore.RecordSpiderKill(Owner: TObject): Cardinal;
var Data,H: TBytes; V: Cardinal;
begin
  FLock.Acquire;
  try
    RequireOwner(Owner); CheckDisk; Result:=FProgress;
    if not FAccepted or (FProgress=5) then Exit;
    V:=FProgress+1; Data:=Copy(FDisk); Data[7]:=Ord('2'); Move(V,Data[80],4);
    H:=Digest(Copy(Data,40,44)); Move(H[0],Data[8],32);
    Publish(Data,ProgressPath(V)); // Durable before HP=0 or outgoing acknowledgement.
    FProgressDisk[V]:=Data; FProgress:=V; Result:=V;
  finally FLock.Release; end;
end;

function TB1008QuestStore.Rewarded(Owner: TObject): Boolean;
begin
  FLock.Acquire;
  try RequireOwner(Owner); CheckDisk; Result:=FRewarded; finally FLock.Release; end;
end;

function TB1008QuestStore.Complete(Owner: TObject): Boolean;
var Data,H: TBytes; V: Cardinal;
begin
  FLock.Acquire;
  try
    RequireOwner(Owner); CheckDisk; Result:=not FRewarded;
    if not Result then Exit;
    if not FAccepted or (FProgress<>5) then
      raise Exception.Create('Quest objectives are not complete');
    Data:=Copy(FDisk); Data[7]:=Ord('3'); V:=5; Move(V,Data[80],4);
    H:=Digest(Copy(Data,40,44)); Move(H[0],Data[8],32);
    Publish(Data,RewardPath); // Inventory grant is now durable before wire replies.
    FRewardDisk:=Data; FRewarded:=True;
  finally FLock.Release; end;
end;

function TB1008QuestStore.RewardItemCount(Owner: TObject;
  ItemID: Cardinal): Cardinal;
var ItemIndex: Integer;
begin
  if ItemID=B1008BeginnerHealingPotionID then ItemIndex:=0
  else if ItemID=B1008BeginnerManaPotionID then ItemIndex:=1
  else raise EArgumentOutOfRangeException.Create('Unsupported reward item');
  FLock.Acquire;
  try
    RequireOwner(Owner); CheckDisk;
    if not FRewarded then Result:=0
    else Result:=B1008FirstRewardCount-FConsumed[ItemIndex];
  finally FLock.Release; end;
end;

function TB1008QuestStore.ConsumeRewardItem(Owner: TObject;
  ItemID: Cardinal): Cardinal;
var ItemIndex: Integer; Data,H: TBytes; V,UseIndex: Cardinal;
begin
  if ItemID=B1008BeginnerHealingPotionID then ItemIndex:=0
  else if ItemID=B1008BeginnerManaPotionID then ItemIndex:=1
  else raise EArgumentOutOfRangeException.Create('Unsupported reward item');
  FLock.Acquire;
  try
    RequireOwner(Owner); CheckDisk;
    if not FRewarded then raise Exception.Create('Reward items were not granted');
    if FConsumed[ItemIndex]>=B1008FirstRewardCount then Exit(0);
    UseIndex:=FConsumed[ItemIndex]+1;
    Data:=Copy(FDisk); Data[7]:=Ord('4'); V:=1; Move(V,Data[72],4);
    V:=ItemID; Move(V,Data[76],4); V:=UseIndex; Move(V,Data[80],4);
    H:=Digest(Copy(Data,40,44)); Move(H[0],Data[8],32);
    Publish(Data,ConsumePath(ItemIndex,UseIndex));
    FConsumeDisk[ItemIndex,UseIndex]:=Data; FConsumed[ItemIndex]:=UseIndex;
    Result:=B1008FirstRewardCount-UseIndex;
  finally FLock.Release; end;
end;

end.
