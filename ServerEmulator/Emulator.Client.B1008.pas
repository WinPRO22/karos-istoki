unit Emulator.Client.B1008;

interface

uses System.SysUtils, Winapi.Windows;

const
  B1008ExeSHA256 = '9d0a4ff1cf224e1637be3c0c99ab60eea962928747e0f1f1baad3fca0e082966';
  // Exact reversible local UI/range/tooltip/stash/potion/hotbar/appearance v16 from the pinned original.
  B1008TradeUIExeSHA256 = '312d1e3465e4a0e4b42fdebd30d000998bd3647307da90d1dd1164b6f29ab927';

type
  TB1008LocalClient = class
  private
    FProcess: THandle;
    FProcessID: Cardinal;
  public
    destructor Destroy; override;
    class function FindClientDirectory(const AStartDirectory: string): string; static;
    class function IsLocalServerList(const AData: TBytes): Boolean; static;
    class procedure ValidateDirectory(const ADirectory: string); static;
    function Launch(const ADirectory: string = ''): Cardinal;
    function PollExit(out AExitCode: Cardinal): Boolean;
    function Running: Boolean;
    property ProcessID: Cardinal read FProcessID;
  end;

implementation

uses System.Classes, System.IOUtils, System.Hash, Winapi.TlHelp32;

function B1008QueryProcessName(AProcess: THandle; AFlags: DWORD;
  AName: PWideChar; var ASize: DWORD): BOOL; stdcall;
  external 'kernel32.dll' name 'QueryFullProcessImageNameW';

procedure CheckNoReparse(const APath: string);
var Path, Parent: string; Attributes: Cardinal;
begin
  Path := ExpandFileName(APath);
  repeat
    Attributes := GetFileAttributes(PChar(Path));
    if (Attributes <> INVALID_FILE_ATTRIBUTES) and
      ((Attributes and FILE_ATTRIBUTE_REPARSE_POINT) <> 0) then
      raise Exception.Create('Client path contains a reparse point: ' + Path);
    Parent := ExtractFileDir(ExcludeTrailingPathDelimiter(Path));
    if SameText(Path, Parent) or (Parent = '') then Break;
    Path := Parent;
  until False;
end;

class function TB1008LocalClient.FindClientDirectory(const AStartDirectory: string): string;
var Dir, Parent: string; I: Integer;
begin
  Dir := ExcludeTrailingPathDelimiter(ExpandFileName(AStartDirectory));
  for I := 0 to 5 do
  begin
    if FileExists(TPath.Combine(Dir, 'KarosOldEmulator.dpr')) then
    begin
      Result := TPath.Combine(Dir, 'runtime\b1008');
      if DirectoryExists(Result) then Exit;
      Result := TPath.Combine(ExtractFileDir(Dir), 'client');
      if DirectoryExists(Result) then Exit;
      raise Exception.Create('Client directory is missing; use Start-Berneo.ps1 -ClientDirectory <path>');
    end;
    Parent := ExtractFileDir(Dir);
    if SameText(Parent, Dir) then Break;
    Dir := Parent;
  end;
  raise Exception.Create('ServerEmulator project folder not found near executable');
end;

class function TB1008LocalClient.IsLocalServerList(const AData: TBytes): Boolean;
const Expected: array[0..17] of Byte =
  ($73,$A5,$DC,$0A,$3A,$68,$98,$C6,$F7,$04,$0E,$3F,$6F,$9F,$CF,$00,$0D,$17);
begin
  Result := Length(AData) = Length(Expected);
  if Result then Result := CompareMem(@AData[0], @Expected[0], Length(Expected));
end;

function ReadExactFile(const APath: string; ASize: Integer;
  AOtherSize1:Integer=0; AOtherSize2:Integer=0): TBytes;
var Stream: TFileStream;
begin
  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size <> ASize) and
      ((AOtherSize1=0) or (Stream.Size<>AOtherSize1)) and
      ((AOtherSize2=0) or (Stream.Size<>AOtherSize2)) then
      raise Exception.Create('Unexpected file size: ' + ExtractFileName(APath));
    SetLength(Result, Integer(Stream.Size));
    Stream.ReadBuffer(Result[0], Length(Result));
  finally Stream.Free; end;
end;

class procedure TB1008LocalClient.ValidateDirectory(const ADirectory: string);
var Path, Name: string; Bytes: TBytes; Hash: THashSHA2;
begin
  CheckNoReparse(ADirectory);
  for Name in ['AMo.exe', 'ServerList.ten', 'LOCAL-CLIENT-MANIFEST.json',
    'BERNEO-CLIENT-MANIFEST.json'] do
  begin
    Path := TPath.Combine(ADirectory, Name);
    CheckNoReparse(Path);
    if not FileExists(Path) then raise Exception.Create('Missing local client file: ' + Name);
  end;
  for Name in ['LaunchKaros.exe', 'LaunchKarosNew.exe', 'KarosOnline_CBT_Setup.exe'] do
    if FileExists(TPath.Combine(ADirectory, Name)) then
      raise Exception.Create('Unexpected launcher/installer in local client folder: ' + Name);
  Bytes := ReadExactFile(TPath.Combine(ADirectory, 'AMo.exe'), 3170304);
  Hash := THashSHA2.Create;
  Hash.Update(Bytes);
  if not SameText(Hash.HashAsString, B1008TradeUIExeSHA256) then
    raise Exception.Create('AMo.exe does not match the pinned b1008 executable');
  Bytes := ReadExactFile(TPath.Combine(ADirectory, 'ServerList.ten'), 18);
  if not IsLocalServerList(Bytes) then
    raise Exception.Create('ServerList.ten must contain the prepared 127.0.0.1:10001 endpoint');
end;

function FindExistingClient(const AExecutable: string): Cardinal;
var Snapshot, Process: THandle; Entry: TProcessEntry32;
  Buffer: array[0..32767] of Char; Size: Cardinal;
begin
  Result := 0;
  Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if Snapshot = INVALID_HANDLE_VALUE then RaiseLastOSError;
  try
    Entry.dwSize := SizeOf(Entry);
    if Process32First(Snapshot, Entry) then
      repeat
        if not SameText(Entry.szExeFile, 'AMo.exe') then Continue;
        Process := OpenProcess($1000 {PROCESS_QUERY_LIMITED_INFORMATION}, False, Entry.th32ProcessID);
        if Process = 0 then Continue;
        try
          Size := Length(Buffer);
          if B1008QueryProcessName(Process, 0, @Buffer[0], Size) and
            SameText(string(PChar(@Buffer[0])), AExecutable) then
            Exit(Entry.th32ProcessID);
        finally CloseHandle(Process); end;
      until not Process32Next(Snapshot, Entry);
  finally CloseHandle(Snapshot); end;
end;

function TB1008LocalClient.Running: Boolean;
begin
  Result := FProcess <> 0;
  if Result then Result := WaitForSingleObject(FProcess, 0) = WAIT_TIMEOUT;
end;

function TB1008LocalClient.PollExit(out AExitCode: Cardinal): Boolean;
begin
  AExitCode := 0;
  Result := FProcess <> 0;
  if Result then Result := WaitForSingleObject(FProcess, 0) = WAIT_OBJECT_0;
  if Result then
  begin
    GetExitCodeProcess(FProcess, AExitCode);
    CloseHandle(FProcess);
    FProcess := 0;
    FProcessID := 0;
  end;
end;

function TB1008LocalClient.Launch(const ADirectory: string): Cardinal;
var Dir, Exe, Command: string; Existing, ExitCode: Cardinal;
  Startup: TStartupInfo; Info: TProcessInformation;
begin
  if Running then raise Exception.Create('Local client is already running');
  PollExit(ExitCode);
  if ADirectory = '' then
    Dir := FindClientDirectory(ExtractFilePath(ParamStr(0)))
  else
    Dir := ExpandFileName(ADirectory);
  ValidateDirectory(Dir);
  Exe := TPath.Combine(Dir, 'AMo.exe');
  Existing := FindExistingClient(Exe);
  if Existing <> 0 then
    raise Exception.CreateFmt('Local client is already running (PID %d)', [Existing]);
  Command := '"' + Exe + '"';
  UniqueString(Command);
  ZeroMemory(@Startup, SizeOf(Startup));
  Startup.cb := SizeOf(Startup);
  Startup.dwFlags := STARTF_USESHOWWINDOW;
  Startup.wShowWindow := SW_SHOWNORMAL;
  ZeroMemory(@Info, SizeOf(Info));
  // Explicit EXE + working directory. No shell, updater or guessed arguments.
  if not CreateProcess(PChar(Exe), PChar(Command), nil, nil, False, 0, nil,
    PChar(Dir), Startup, Info) then RaiseLastOSError;
  CloseHandle(Info.hThread);
  FProcess := Info.hProcess;
  FProcessID := Info.dwProcessId;
  Result := FProcessID;
end;

destructor TB1008LocalClient.Destroy;
begin
  // Closing the emulator does not forcibly terminate the user's game window.
  if FProcess <> 0 then CloseHandle(FProcess);
  inherited;
end;

end.
