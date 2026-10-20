unit Emulator.Character.B1008;

interface

uses System.SysUtils, System.SyncObjs, Winapi.Windows;

type
  TB1008Character = record
    Name: string;
    Appearance: array[0..9] of Byte;
    function ClassID: Word;
  end;

  TB1008CharacterWire = class
  public
    class function ParseCreate(const Payload: TBytes): TB1008Character; static;
    class function BuildPreview(const Character: TB1008Character;
      Timestamp: Cardinal): TBytes; static;
  end;

  // One local dummy account, one preview character. The server owns this store;
  // sessions borrow it. Empty path means memory-only (tests/diagnostic tools).
  TB1008CharacterStore = class
  private
    FLock: TCriticalSection;
    FFileLock: THandle;
    FPath: string;
    FRequest: TBytes;
    procedure SaveNew(const Request: TBytes);
  public
    constructor Create(const FilePath: string = '');
    destructor Destroy; override;
    function Preview(Timestamp: Cardinal): TBytes;
    function CreateCharacter(const Request: TBytes; out Reply: TBytes): string;
    class function DefaultPath(const StartDirectory: string): string; static;
  end;

implementation

uses System.Classes, System.IOUtils, System.Hash, Emulator.Protocol.B1008;

const StoreMagic: array[0..7] of Byte = ($4B,$31,$30,$30,$38,$43,$30,$31);

function DigestOf(const Data: TBytes): TBytes;
var Hash: THashSHA2;
begin
  Hash := THashSHA2.Create;
  Hash.Update(Data);
  Result := Hash.HashAsBytes;
end;

function TB1008Character.ClassID: Word;
begin
  Result := Word(Appearance[0]) or (Word(Appearance[1]) shl 8);
end;

class function TB1008CharacterWire.ParseCreate(const Payload: TBytes): TB1008Character;
var Count, I, Offset, Ch: Integer;
begin
  Result := Default(TB1008Character);
  if Length(Payload) < 22 then
    raise EKarosProtocol.Create('Truncated CreateChar');
  if (Payload[0] <> 2) or (Payload[1] <> 2) then
    raise EKarosProtocol.Create('Not a CreateChar request');
  Count := TB1008Wire.ReadBE16(Payload, 16);
  // 0x4C9AE4 / 0x4265ED: UTF-16 units zero-extended to LE DWORDs,
  // INCLUDING a DWORD NUL after count non-NUL units. Never trust the client's
  // weaker 0x5208B7 length check (it does not multiply the count by four).
  if (Count < 1) or (Count > 20) or (Length(Payload) <> 18 + 4*(Count+1)) then
    raise EKarosProtocol.Create('Invalid CreateChar name length');
  SetLength(Result.Name, Count);
  for I := 0 to Count do
  begin
    Offset := 18 + 4*I;
    Ch := Payload[Offset] or (Integer(Payload[Offset+1]) shl 8);
    if (Payload[Offset+2] <> 0) or (Payload[Offset+3] <> 0) then
      raise EKarosProtocol.Create('Invalid CreateChar DWORD character');
    if I = Count then
    begin
      if Ch <> 0 then raise EKarosProtocol.Create('Missing CreateChar terminator');
    end
    else
    begin
      if (Ch = 0) or ((Ch >= $D800) and (Ch <= $DFFF)) then
        raise EKarosProtocol.Create('Invalid CreateChar name character');
      Result.Name[I+1] := Char(Ch);
    end;
  end;
  Move(Payload[6], Result.Appearance[0], 10);
end;

procedure PutBE32(var Data: TBytes; Offset: Integer; Value: Cardinal);
begin
  Data[Offset] := Byte(Value shr 24);
  Data[Offset+1] := Byte((Value shr 16) and $FF);
  Data[Offset+2] := Byte((Value shr 8) and $FF);
  Data[Offset+3] := Byte(Value and $FF);
end;

function Supported(const Character: TB1008Character): Boolean;
var C: Char;
begin
  // Deliberately limited local preview policy, NOT historical server rules.
  // ASCII avoids the native parser's 20-byte ACP conversion buffer ambiguity.
  Result := (Length(Character.Name) >= 4) and (Length(Character.Name) <= 14) and
    ((Character.ClassID = 100) or (Character.ClassID = 300) or (Character.ClassID = 500)) and
    (Character.Appearance[2] = 0) and (Character.Appearance[9] = 0) and
    (Character.Appearance[3] <= 15) and (Character.Appearance[8] <= 15);
  for C in Character.Name do
    Result := Result and (((C >= 'A') and (C <= 'Z')) or
      ((C >= 'a') and (C <= 'z')) or ((C >= '0') and (C <= '9')));
end;

class function TB1008CharacterWire.BuildPreview(const Character: TB1008Character;
  Timestamp: Cardinal): TBytes;
var I, Offset, Ch: Integer;
begin
  if not Supported(Character) then
    raise EKarosProtocol.Create('Unsupported local character preview');
  Result := nil;
  SetLength(Result, $152 + 4*(Length(Character.Name)+1));
  Result[0] := 2;
  Result[1] := 1;
  PutBE32(Result, 2, Timestamp);
  Result[6] := 1; // Last NONEMPTY record -> 0x52534E GUI state 4.
  PutBE32(Result, 7, 1); // Stable ID for the only local preview character.
  // +11..14 unknown: zero. +15..335 is the 321-byte character record.
  // 0x4266F2 and 0x4CA6A0 establish its first ten bytes; appearance consumers
  // 0x4EFF72 / 0x4EFB29 use +3, +4 and +8 without endian conversion.
  Move(Character.Appearance[0], Result[15], 10);
  Result[15+$26] := 1; // LE level word: 0x4CB757 -> level label 0x520D.
  // Remaining stats/equipment are neutral PREVIEW placeholders, not a world
  // spawn or a reconstruction of the original server's starting attributes.
  Result[$151] := Byte(Length(Character.Name)); // BE16 at +0x150.
  for I := 1 to Length(Character.Name) do
  begin
    Offset := $152 + 4*(I-1);
    Ch := Ord(Character.Name[I]);
    Result[Offset] := Byte(Ch and $FF);
    Result[Offset+1] := Byte(Ch shr 8);
  end;
end;

class function TB1008CharacterStore.DefaultPath(const StartDirectory: string): string;
var Dir, Parent: string; I: Integer;
begin
  Dir := ExcludeTrailingPathDelimiter(ExpandFileName(StartDirectory));
  for I := 0 to 5 do
  begin
    if FileExists(TPath.Combine(Dir, 'KarosOldEmulator.dpr')) then
      Exit(TPath.Combine(Dir, 'data\b1008\test-character.b1008'));
    Parent := ExtractFileDir(Dir);
    if SameText(Parent, Dir) then Break;
    Dir := Parent;
  end;
  raise Exception.Create('Character store project directory not found');
end;

constructor TB1008CharacterStore.Create(const FilePath: string);
var Stream: TFileStream; Data, Digest, Request: TBytes;
begin
  inherited Create;
  FFileLock := INVALID_HANDLE_VALUE;
  FLock := TCriticalSection.Create;
  if FilePath = '' then Exit;
  FPath := ExpandFileName(FilePath);
  if not ForceDirectories(ExtractFileDir(FPath)) then
    raise Exception.Create('Cannot create character storage directory');
  // Share mode zero prevents two emulator processes from owning this store.
  FFileLock := CreateFile(PChar(FPath+'.lock'), GENERIC_READ or GENERIC_WRITE,
    0, nil, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  Win32Check(FFileLock <> INVALID_HANDLE_VALUE);
  if not FileExists(FPath) then Exit;
  Stream := TFileStream.Create(FPath, fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size < 66) or (Stream.Size > 142) then
      raise Exception.Create('Invalid character store size; file left unchanged');
    SetLength(Data, Integer(Stream.Size));
    Stream.ReadBuffer(Data[0], Length(Data));
  finally Stream.Free; end;
  if not CompareMem(@Data[0], @StoreMagic[0], 8) then
    raise Exception.Create('Unknown character store format; file left unchanged');
  Request := Copy(Data, 40, Length(Data)-40);
  Digest := DigestOf(Request);
  if not CompareMem(@Data[8], @Digest[0], 32) then
    raise Exception.Create('Character store checksum mismatch; file left unchanged');
  if not Supported(TB1008CharacterWire.ParseCreate(Request)) then
    raise Exception.Create('Unsupported saved character; file left unchanged');
  FRequest := Request;
end;

destructor TB1008CharacterStore.Destroy;
begin
  if (FFileLock <> 0) and (FFileLock <> INVALID_HANDLE_VALUE) then CloseHandle(FFileLock);
  FLock.Free;
  inherited;
end;

procedure TB1008CharacterStore.SaveNew(const Request: TBytes);
var TempPath: string; GUID: TGUID; Handle: THandle; Stream: THandleStream;
  Digest: TBytes;
begin
  if FPath = '' then Exit;
  CreateGUID(GUID);
  TempPath := FPath+'.'+GUIDToString(GUID)+'.tmp';
  Handle := CreateFile(PChar(TempPath), GENERIC_WRITE, 0, nil, CREATE_NEW,
    FILE_ATTRIBUTE_NORMAL, 0);
  Win32Check(Handle <> INVALID_HANDLE_VALUE);
  try
    try
      Stream := THandleStream.Create(Handle);
      try
        Digest := DigestOf(Request);
        Stream.WriteBuffer(StoreMagic[0], 8);
        Stream.WriteBuffer(Digest[0], 32);
        Stream.WriteBuffer(Request[0], Length(Request));
        Win32Check(FlushFileBuffers(Handle));
      finally Stream.Free; end;
    finally CloseHandle(Handle); end;
    // No REPLACE_EXISTING: never overwrite a character, even after an external
    // file appeared while the emulator was running. Publish only complete data.
    Win32Check(MoveFileEx(PChar(TempPath), PChar(FPath), MOVEFILE_WRITE_THROUGH));
  finally
    if FileExists(TempPath) then Winapi.Windows.DeleteFile(PChar(TempPath));
  end;
end;

function TB1008CharacterStore.Preview(Timestamp: Cardinal): TBytes;
begin
  FLock.Acquire;
  try
    Result := nil;
    if Length(FRequest) > 0 then
      Result := TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(FRequest), Timestamp);
  finally FLock.Release; end;
end;

function TB1008CharacterStore.CreateCharacter(const Request: TBytes; out Reply: TBytes): string;
var Character: TB1008Character; Normalized: TBytes; IsDuplicate: Boolean;
begin
  Reply := nil;
  Character := TB1008CharacterWire.ParseCreate(Request);
  if not Supported(Character) then
    Exit('CREATE SKIPPED | preview supports classes 100/300/500, ASCII letters/digits 4..14, bounded appearance; no reply');
  Normalized := Copy(Request);
  FillChar(Normalized[2], 4, 0); // A client tick is not persistent character data.
  FLock.Acquire;
  try
    if Length(FRequest) = 0 then
    begin
      // Persist BEFORE reporting success; failed writes cannot create ghosts.
      SaveNew(Normalized);
      FRequest := Normalized;
      Result := Format('CREATE SAVED | id=1 class=%d name-length=%d | single-character preview; world entry not implemented',
        [Character.ClassID, Length(Character.Name)]);
    end
    else
    begin
      IsDuplicate := (Length(FRequest) = Length(Normalized));
      if IsDuplicate then IsDuplicate := CompareMem(@FRequest[0], @Normalized[0], Length(FRequest));
      if IsDuplicate then
        Result := 'CREATE REPLAY | returning existing id=1; no duplicate character'
      else
        Result := 'CREATE LIMIT | one preview character already exists; unchanged; returning existing id=1';
    end;
    Reply := TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(FRequest),
      TB1008Wire.ReadBE32(Request, 2));
  finally FLock.Release; end;
end;

end.
