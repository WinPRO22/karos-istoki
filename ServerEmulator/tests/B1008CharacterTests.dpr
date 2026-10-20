program B1008CharacterTests;

{$APPTYPE CONSOLE}
{$R+}
{$Q+}

uses System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows,
  IdTCPClient, IdGlobal, Emulator.Character.B1008, Emulator.Session,
  Emulator.Login.B1008, Emulator.Protocol.B1008, Emulator.Server;

procedure Check(Value: Boolean; const Text: string);
begin
  if not Value then raise Exception.Create(Text);
end;

procedure Equal(const A, B: TBytes; const Text: string);
begin
  Check(Length(A) = Length(B), Text+' size');
  if Length(A) > 0 then Check(CompareMem(@A[0], @B[0], Length(A)), Text+' bytes');
end;

function Login: TBytes;
begin
  Result := TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0);
end;

function Request(const Name: string = 'Hero'; ClassID: Word = 100): TBytes;
var I: Integer;
begin
  Result := nil;
  SetLength(Result, 18+4*(Length(Name)+1));
  Result[0] := 2; Result[1] := 2; Result[5] := 42;
  Result[6] := Byte(ClassID and $FF); Result[7] := Byte(ClassID shr 8);
  Result[9] := 2; Result[10] := $CC; Result[11] := $DD;
  Result[12] := $EE; Result[13] := $FF; Result[14] := 3;
  Result[17] := Byte(Length(Name));
  for I := 1 to Length(Name) do
  begin
    Result[18+4*(I-1)] := Byte(Ord(Name[I]) and $FF);
    Result[19+4*(I-1)] := Byte(Ord(Name[I]) shr 8);
  end;
end;

procedure ParserTests;
var P, Bad, Reply: TBytes; C: TB1008Character; I, K: Integer; Failed: Boolean;
begin
  P := Request;
  C := TB1008CharacterWire.ParseCreate(P);
  Check((C.ClassID = 100) and (C.Name = 'Hero'), 'Create parser');
  Reply := TB1008CharacterWire.BuildPreview(C, $01020304);
  Check((Length(Reply) = 358) and (Reply[0] = 2) and (Reply[1] = 1) and
    (Reply[6] = 1) and (TB1008Wire.ReadBE32(Reply, 7) = 1), 'Preview header');
  Check(TB1008Wire.ReadBE32(Reply, 2) = $01020304, 'Preview timestamp');
  Equal(Copy(Reply,15,10), Copy(P,6,10), 'Appearance preserved');
  Check((Reply[15+$26] = 1) and (Reply[15+$27] = 0), 'Level 1 LE');
  Check(TB1008Wire.ReadBE16(Reply,$150) = 4, 'Name count BE');
  Equal(Copy(Reply,$152,20), Copy(P,18,20), 'Name DWORDs and terminator');
  for K in [100,300,500] do
  begin
    C := TB1008CharacterWire.ParseCreate(Request('Hero', K));
    Reply := TB1008CharacterWire.BuildPreview(C,0);
    Check(Reply[15] or (Integer(Reply[16]) shl 8) = K, 'Class mapping');
  end;
  // Every truncation must fail, including inside the DWORD NUL.
  for I := 0 to Length(P)-1 do
  begin
    Failed := False;
    try TB1008CharacterWire.ParseCreate(Copy(P,0,I));
    except on E: EKarosProtocol do Failed := True; end;
    Check(Failed,'Accepted truncated create');
  end;
  for I := 0 to 7 do
  begin
    Bad := Copy(P);
    case I of
      0: Bad[0] := 3;
      1: Bad[1] := 3;
      2: Bad[17] := 21;
      3: Bad[20] := 1;
      4: Bad[18] := 0;
      5: Bad[19] := $D8;
      6: Bad[Length(Bad)-4] := 1;
      7: SetLength(Bad, Length(Bad)+1);
    end;
    Failed := False;
    try TB1008CharacterWire.ParseCreate(Bad);
    except on E: EKarosProtocol do Failed := True; end;
    Check(Failed,'Accepted malformed create');
  end;
  Writeln('PASS: create layout, all truncations, malformed names, three classes, preview fields');
end;

procedure StoreAndSessionTests;
var Store, Other: TB1008CharacterStore; Session: TEmulatorSession;
  Dir, Path, Text: string; GUID: TGUID; Replies: TB1008Replies;
  P, Saved, Reply, Bad, Snapshot: TBytes; Failed: Boolean;
begin
  CreateGUID(GUID);
  Dir := TPath.Combine(TPath.GetTempPath, 'karos-character-'+GUIDToString(GUID));
  TDirectory.CreateDirectory(Dir);
  Path := TPath.Combine(Dir, 'test-character.b1008');
  Store := nil; Session := nil; Other := nil;
  try
    Store := TB1008CharacterStore.Create(Path);
    Failed := False;
    try Other := TB1008CharacterStore.Create(Path);
    except on E: EOSError do Failed := True; end;
    Check(Failed,'Concurrent store owner admitted');
    Session := TEmulatorSession.Create(blCharacterPreview, Store);
    P := Request;
    Session.HandlePacket(P, Replies);
    Check((Length(Replies)=0) and not FileExists(Path),'Create before login persisted');
    Session.HandlePacket(Login, Replies);
    Check((Length(Replies)=2) and (Length(Replies[1])=11),'Empty account reply');
    Session.HandlePacket(Request('abc'), Replies);
    Check((Length(Replies)=0) and not FileExists(Path),'Unsupported preview admitted');
    Session.HandlePacket(Request('Hero',200), Replies);
    Check((Length(Replies)=0) and not FileExists(Path),'Unsupported class admitted');
    Text := Session.HandlePacket(P, Replies);
    Check((Length(Replies)=1) and (Pos('CREATE SAVED',Text)>0) and
      (Pos('Hero',Text)=0) and (Session.Stage=ssCharacterPreview),'Create not committed/redacted');
    Saved := Replies[0]; Snapshot := TFile.ReadAllBytes(Path);
    Text := Session.HandlePacket(P, Replies);
    Check(Pos('REPLAY',Text)>0,'Duplicate not recognized');
    Equal(Saved, Replies[0], 'Duplicate response');
    Equal(Snapshot, TFile.ReadAllBytes(Path), 'Duplicate modified store');
    Text := Session.HandlePacket(Request('Other'), Replies);
    Check(Pos('LIMIT',Text)>0,'One-character limit');
    Equal(Saved, Replies[0], 'Limit returns existing character');
    Session.HandlePacket(Login, Replies);
    Check(Length(Replies)=0,'Login duplicate replayed');
    FreeAndNil(Session); FreeAndNil(Store);
    Store := TB1008CharacterStore.Create(Path);
    Session := TEmulatorSession.Create(blCharacterPreview, Store);
    Session.HandlePacket(Login, Replies);
    Check((Length(Replies)=2) and (Length(Replies[1])=Length(Saved)) and
      (Session.Stage=ssCharacterPreview),'Restart lost character');
    Reply := TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(P),$01020304);
    Equal(Reply, Replies[1], 'Restart preview');
    FreeAndNil(Session); FreeAndNil(Store);
    // Corruption fails closed and preserves the exact file for recovery.
    Bad := Copy(Snapshot); Bad[High(Bad)] := Bad[High(Bad)] xor 1;
    TFile.WriteAllBytes(Path,Bad);
    Failed := False;
    try Store := TB1008CharacterStore.Create(Path);
    except on E: Exception do Failed := True; end;
    Check(Failed,'Corrupt store loaded');
    Equal(Bad,TFile.ReadAllBytes(Path),'Corrupt store overwritten');
    TFile.Delete(Path);
    Store := TB1008CharacterStore.Create(Path);
    // External destination appearing after load must never be overwritten.
    TFile.WriteAllBytes(Path,Snapshot);
    Failed := False;
    try Store.CreateCharacter(P,Reply);
    except on E: EOSError do Failed := True; end;
    Check(Failed and (Length(Reply)=0) and (Length(Store.Preview(0))=0), 'Failed write created ghost');
    Equal(Snapshot,TFile.ReadAllBytes(Path),'External file overwritten');
    Writeln('PASS: admission, redaction, persistence, restart, duplicate/limit, exclusive ownership, corruption, failed commit');
  finally
    Other.Free; Session.Free; Store.Free;
    // Only exact fixtures inside the uniquely created directory are removed.
    if FileExists(Path) then TFile.Delete(Path);
    if FileExists(Path+'.lock') then TFile.Delete(Path+'.lock');
    TDirectory.Delete(Dir,False);
  end;
end;

procedure NetworkTests;
var Server: TEmulatorServer; Client: TIdTCPClient; Wire, P, Reply: TBytes;
  Incoming: TIdBytes; Decoder: TB1008FrameDecoder; I: Integer;
begin
  Server := TEmulatorServer.Create(emB1008,blCharacterPreview);
  Client := TIdTCPClient.Create(nil); Decoder := TB1008FrameDecoder.Create;
  try
    Server.Start(0); Client.Host := '127.0.0.1'; Client.Port := Server.Port;
    Client.ReadTimeout := 3000; Client.Connect;
    Client.IOHandler.Write(TIdBytes(TB1008Wire.Encode(Login)));
    Client.IOHandler.ReadBytes(Incoming,36,False);
    Decoder.Append(TBytes(Incoming));
    Check(Decoder.TryPop(P) and Decoder.TryPop(P),'Login batch');
    Wire := TB1008Wire.Encode(Request);
    // Byte-by-byte transport fragmentation; store must commit only a full frame.
    for I := 0 to High(Wire) do Client.IOHandler.Write(TIdBytes(Copy(Wire,I,1)));
    Incoming := nil; Client.IOHandler.ReadBytes(Incoming,364,False);
    Decoder.Append(TBytes(Incoming)); Check(Decoder.TryPop(P),'Create response missing');
    Reply := TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(Request),42);
    Equal(Reply,P,'TCP create response');
    Client.Disconnect; Client.Connect;
    Client.IOHandler.Write(TIdBytes(TB1008Wire.Encode(Login)));
    Incoming := nil; Client.IOHandler.ReadBytes(Incoming,19+364,False);
    Decoder.Append(TBytes(Incoming));
    Check(Decoder.TryPop(P) and Decoder.TryPop(P),'Reconnect list missing');
    Reply := TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(Request),$01020304);
    Equal(Reply,P,'TCP reconnect saved character');
    Writeln('PASS: loopback login/create/reconnect with fragmented encrypted create frame');
  finally
    Client.Free; Server.Free; Decoder.Free;
  end;
end;

begin
  try ParserTests; StoreAndSessionTests; NetworkTests;
  except on E: Exception do begin Writeln('FAIL: ',E.ClassName,': ',E.Message); ExitCode := 1; end; end;
end.
