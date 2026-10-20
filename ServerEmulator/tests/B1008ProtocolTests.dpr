program B1008ProtocolTests;

{$APPTYPE CONSOLE}
{$R+}
{$Q+}
{$B-}

uses
  System.SysUtils, System.Classes, Winapi.Windows, IdTCPClient, IdGlobal,
  Emulator.Protocol.B1008 in '..\Emulator.Protocol.B1008.pas',
  Emulator.Session in '..\Emulator.Session.pas',
  Emulator.Server in '..\Emulator.Server.pas',
  Emulator.Login.B1008 in '..\Emulator.Login.B1008.pas';

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

function Hex(const AText: string): TBytes;
var I: Integer;
begin
  Check(Length(AText) mod 2 = 0, 'Bad hex fixture');
  SetLength(Result, Length(AText) div 2);
  for I := 0 to High(Result) do
    Result[I] := StrToInt('$' + Copy(AText, I * 2 + 1, 2));
end;

procedure Equal(const A, B: TBytes; const AMessage: string);
begin
  Check(Length(A) = Length(B), AMessage + ': size');
  if Length(A) > 0 then
    Check(CompareMem(@A[0], @B[0], Length(A)), AMessage + ': content');
end;

function Join(const A, B: TBytes): TBytes;
begin
  SetLength(Result, Length(A) + Length(B));
  if Length(A) > 0 then Move(A[0], Result[0], Length(A));
  if Length(B) > 0 then Move(B[0], Result[Length(A)], Length(B));
end;

procedure ExpectBadFrame(const AData: TBytes);
var D: TB1008FrameDecoder; P: TBytes; Failed: Boolean;
begin
  D := TB1008FrameDecoder.Create;
  try
    Failed := False;
    try
      D.Append(AData);
      D.TryPop(P);
    except
      on E: EKarosProtocol do Failed := True;
    end;
    Check(Failed and D.Faulted and (D.PendingBytes = 0), 'Bad frame not rejected');
    Failed := False;
    try
      D.Append(nil);
    except
      on E: EKarosProtocol do Failed := True;
    end;
    Check(Failed, 'Faulted decoder was reused');
  finally D.Free; end;
end;

procedure CodecTests;
var D: TB1008FrameDecoder; P, W, OutP, One: TBytes; I, Split, Offset, Count: Integer;
  Failed: Boolean;
begin
  // Hand-computed from the native ROR8(plain XOR key,1) primitive, not roundtrip.
  Equal(TB1008Wire.Encode(Hex('02')), Hex('000000030622AF'), 'Known-answer encode');
  Equal(TB1008Wire.Decode(Hex('0622AF')), Hex('02'), 'Known-answer decode');
  P := Hex('0B0001020304FFFFFFFF00000000');
  W := TB1008Wire.Encode(P);
  Equal(W, Hex('00000010828786878487FB7BFC7C02820181A529'), 'Ping known answer');
  for Split := 0 to Length(W) do
  begin
    D := TB1008FrameDecoder.Create;
    try
      D.Append(Copy(W, 0, Split));
      if Split < Length(W) then
        Check(not D.TryPop(OutP), 'Partial frame emitted');
      D.Append(Copy(W, Split, Length(W) - Split));
      Check(D.TryPop(OutP), 'Split frame missing');
      Equal(P, OutP, 'Split frame content');
      Check(not D.TryPop(OutP), 'Duplicate frame');
      Check(D.PendingBytes = 0, 'Remainder after frame');
    finally D.Free; end;
  end;
  D := TB1008FrameDecoder.Create;
  try
    for I := 0 to High(W) do
    begin
      One := Copy(W, I, 1);
      D.Append(One);
      Check(D.TryPop(OutP) = (I = High(W)), 'Bytewise framing');
    end;
    Equal(P, OutP, 'Bytewise payload');
    D.Append(Join(Join(W, W), Copy(W, 0, 7)));
    for I := 1 to 2 do
    begin
      Check(D.TryPop(OutP), 'Coalesced packet missing');
      Equal(P, OutP, 'Coalesced packet');
    end;
    Check(not D.TryPop(OutP), 'Partial tail emitted');
    Check(D.PendingBytes = 7, 'Partial tail lost');
    D.Append(Copy(W, 7, Length(W) - 7));
    Check(D.TryPop(OutP), 'Tail did not complete');
  finally D.Free; end;
  SetLength(P, B1008MaxPayload);
  for I := 0 to High(P) do P[I] := Byte(I and $FF);
  W := TB1008Wire.Encode(P);
  D := TB1008FrameDecoder.Create;
  try
    Offset := 0;
    while Offset < Length(W) do
    begin
      Count := Length(W) - Offset;
      if Count > B1008ReadChunk then Count := B1008ReadChunk;
      D.Append(Copy(W, Offset, Count));
      Inc(Offset, Count);
      Check(D.TryPop(OutP) = (Offset = Length(W)), 'Max frame timing');
    end;
    Equal(P, OutP, 'Max frame content/key wrap');
  finally D.Free; end;
  ExpectBadFrame(Hex('00000000'));
  ExpectBadFrame(Hex('00000002'));
  ExpectBadFrame(Hex('00002001'));
  ExpectBadFrame(Hex('FFFFFFFF'));
  ExpectBadFrame(Hex('03000000'));
  ExpectBadFrame(Hex('000000030622AE'));
  SetLength(P, B1008ReadChunk + 1);
  ExpectBadFrame(P);
  Failed := False;
  try TB1008Wire.Encode(nil);
  except on E: EKarosProtocol do Failed := True; end;
  Check(Failed, 'Empty payload encoded');
  SetLength(P, B1008MaxPayload + 1);
  Failed := False;
  try TB1008Wire.Encode(P);
  except on E: EKarosProtocol do Failed := True; end;
  Check(Failed, 'Oversized payload encoded');
  Writeln('PASS: known vectors, every split, bytewise/coalesced frames, max length, corrupt input');
end;

function HandleSingle(S: TEmulatorSession; const P: TBytes; out Reply: TBytes): string;
var Replies: TB1008Replies;
begin
  Reply := nil;
  Result := S.HandlePacket(P, Replies);
  Check(Length(Replies) <= 1, 'Observe-only test unexpectedly emitted multiple replies');
  if Length(Replies) = 1 then Reply := Replies[0];
end;

procedure SessionTests;
var S, Other: TEmulatorSession; P, Reply: TBytes; Description: string; Failed: Boolean;
begin
  S := TEmulatorSession.Create;
  Other := TEmulatorSession.Create;
  try
    P := Hex('02000102030400010002616263006465660067686900');
    Description := HandleSingle(S, P, Reply);
    Check((S.Stage = ssLoginObserved) and (Other.Stage = ssConnected), 'Session isolation');
    Check((Length(Reply) = 0) and (Pos('authentication not implemented', Description) > 0), 'Fake login success');
    Check((Pos('abc', Description) = 0) and (Pos('def', Description) = 0), 'Credentials leaked');
    Failed := False;
    try HandleSingle(S, Copy(P, 0, Length(P)-1), Reply);
    except on E: EKarosProtocol do Failed := True; end;
    Check(Failed, 'Unterminated field accepted');
    Failed := False;
    try HandleSingle(S, Join(P, Hex('00')), Reply);
    except on E: EKarosProtocol do Failed := True; end;
    Check(Failed, 'Trailing login data accepted');
    P := Hex('0B0001020304FFFFFFFF00000000');
    HandleSingle(S, P, Reply);
    Equal(P, Reply, 'Sentinel ping reply');
    P[6] := 0;
    HandleSingle(S, P, Reply);
    Check(Length(Reply) = 0, 'Ping echo loop');
    Description := HandleSingle(S, Hex('0204010203040000000100000000'), Reply);
    Check((Length(Reply) = 0) and (Pos('START SKIPPED', Description) > 0), 'Unexpected world entry');
    S.Close;
    Failed := False;
    try HandleSingle(S, P, Reply);
    except on E: EKarosProtocol do Failed := True; end;
    Check(Failed, 'Closed session accepted packet');
  finally Other.Free; S.Free; end;
  Writeln('PASS: login bounds/redaction, isolated states, ping anti-loop, no fabricated login/world reply');
end;

procedure WaitPackets(S: TEmulatorServer; RX, TX, Errors: Int64);
var A, B, C: Int64; Started: UInt64;
begin
  Started := GetTickCount64;
  repeat
    S.GetProtocolStatistics(A, B, C);
    if (A = RX) and (B = TX) and (C = Errors) then Exit;
    Sleep(10);
  until GetTickCount64 - Started > 5000;
  raise Exception.CreateFmt('Packet counters: %d/%d/%d expected %d/%d/%d', [A,B,C,RX,TX,Errors]);
end;

procedure LoginUtf8Tests;
var S: TEmulatorSession; P, Reply: TBytes; Text, Invalid: string;
  Failed: Boolean;
begin
  S := TEmulatorSession.Create;
  try
    // Empty fields, Cyrillic, CJK and a supplementary-plane character.
    HandleSingle(S, Hex('020000000000000E0000000000'), Reply);
    P := Hex('020000000000000E0000D09100E6BCA200F09F988000');
    Text := HandleSingle(S, P, Reply);
    Check((S.Stage = ssLoginObserved) and (Length(Reply) = 0), 'UTF-8 login stage/reply');
    Check(Pos('UTF-8 byte lengths=2/3/4', Text) > 0, 'UTF-8 lengths must count bytes');
    Check(Pos(#$0411, Text) = 0, 'Decoded text leaked');
  finally S.Free; end;
  for Invalid in ['80', 'C080', 'C2', 'E08080', 'EDA080', 'F4908080', 'FF', 'E228A1'] do
  begin
    S := TEmulatorSession.Create;
    try
      Failed := False;
      P := Join(Hex('020000000000000E0000'), Join(Hex(Invalid), Hex('000000')));
      try HandleSingle(S, P, Reply);
      except on E: EKarosProtocol do Failed := True; end;
      Check(Failed and (S.Stage = ssConnected) and (Length(Reply) = 0),
        'Malformed UTF-8 accepted or advanced login state');
    finally S.Free; end;
  end;
  Writeln('PASS: UTF-8 login strings, empty fields, byte counts, invalid sequences, redaction');
end;

procedure NetworkTests;
var S: TEmulatorServer; C, Other: TIdTCPClient; Ping, Wire, Login: TBytes;
  Received: TIdBytes; I: Integer; Line, Logs: string;
begin
  S := TEmulatorServer.Create;
  C := TIdTCPClient.Create(nil);
  Other := TIdTCPClient.Create(nil);
  try
    S.Start(0);
    C.Host := EmulatorHost; C.Port := S.Port;
    C.ConnectTimeout := 1000; C.ReadTimeout := 1500; C.Connect;
    Other.Host := EmulatorHost; Other.Port := S.Port;
    Other.ConnectTimeout := 1000; Other.ReadTimeout := 1500; Other.Connect;
    Ping := Hex('0B0001020304FFFFFFFF00000000');
    Wire := TB1008Wire.Encode(Ping);
    C.IOHandler.Write(TIdBytes(Copy(Wire, 0, 2)));
    Other.IOHandler.Write(TIdBytes(Wire));
    Other.IOHandler.ReadBytes(Received, Length(Wire), False);
    Equal(TBytes(Received), Wire, 'Other session reply while first partial');
    WaitPackets(S, 1, 1, 0);
    C.IOHandler.Write(TIdBytes(Copy(Wire, 2, Length(Wire)-2)));
    C.IOHandler.ReadBytes(Received, Length(Wire), False);
    Equal(TBytes(Received), Wire, 'Network ping');
    WaitPackets(S, 2, 2, 0);
    Login := TB1008Wire.Encode(Hex('02000102030400010002616263006465660067686900'));
    C.IOHandler.Write(TIdBytes(Join(Login, Login)));
    WaitPackets(S, 4, 2, 0);
    Check(not C.IOHandler.CheckForDataOnSource(100), 'Fabricated login response');
    Logs := '';
    for Line in S.DrainLogs do Logs := Logs + Line + sLineBreak;
    Check((Pos('abc', Logs) = 0) and (Pos('61 62 63', Logs) = 0), 'Network credential leak');
    Check(Pos('LOGIN OBSERVED', Logs) > 0, 'Login log missing');
    C.IOHandler.Write(TIdBytes(Hex('FFFFFFFF')));
    WaitPackets(S, 4, 2, 1);
    // A malformed connection does not prevent healthy clients from continuing.
    Other.IOHandler.Write(TIdBytes(Wire));
    Other.IOHandler.ReadBytes(Received, Length(Wire), False);
    Equal(TBytes(Received), Wire, 'Healthy connection after peer protocol error');
    WaitPackets(S, 5, 3, 1);
    Other.Disconnect;
    C.Disconnect;
    S.Stop;
    for I := 1 to 3 do
    begin
      S.Start(0);
      WaitPackets(S, 0, 0, 0);
      S.Stop;
    end;
  finally Other.Free; C.Free; S.Free; end;
  Writeln('PASS: real loopback framing, encrypted replies, per-client buffers, invalid peer isolation, restart');
end;

procedure EmptyAccountTests;
var S: TEmulatorSession; P, Bad: TBytes; Replies: TB1008Replies; Text: string;
  I: Integer; Failed: Boolean;
begin
  P := Hex('020001020304000E00007465737400746573740000');
  S := TEmulatorSession.Create(blEmptyAccountProbe);
  try
    // Well-formed but not admitted: wrong request fields, credentials or third field.
    for I := 0 to 3 do
    begin
      Bad := Copy(P);
      case I of
        0: Bad[7] := 15;
        1: Bad[9] := 1;
        2: Bad[10] := Ord('X');
        3: begin Bad[High(Bad)] := Ord('X'); Bad := Join(Bad, Hex('00')); end;
      end;
      Text := S.HandlePacket(Bad, Replies);
      Check((Length(Replies) = 0) and (S.Stage = ssLoginObserved), 'Invalid probe admitted');
      Check(Pos('SKIPPED', Text) > 0, 'Skipped probe not logged');
    end;
    Failed := False;
    try S.HandlePacket(Copy(P, 0, Length(P)-1), Replies);
    except on E: EKarosProtocol do Failed := True; end;
    Check(Failed and (Length(Replies) = 0), 'Truncated probe emitted replies');
    Text := S.HandlePacket(P, Replies);
    Check((Length(Replies) = 2) and (S.Stage = ssEmptyAccountProbe), 'Missing probe replies');
    Equal(Replies[0], Hex('020001020304000E0000000000'), 'Acknowledgement known answer');
    Equal(Replies[1], Hex('0201010203040100000000'), 'Empty list known answer');
    Check(Pos('test', Text) = 0, 'Dummy credential contents leaked');
    for I := 0 to High(Replies) do
      Check(Pos('test', TEncoding.ASCII.GetString(Replies[I])) = 0, 'Credential echoed');
    S.HandlePacket(P, Replies);
    Check((Length(Replies) = 0) and (S.Stage = ssEmptyAccountProbe), 'Duplicate probe replayed');
    S.HandlePacket(Hex('0B0001020304FFFFFFFF00000000'), Replies);
    Check(Length(Replies) = 1, 'Ping stopped working after probe');
    Text := S.HandlePacket(Hex('020201020304'), Replies);
    Check((Length(Replies) = 0) and (Pos('CREATE OBSERVED', Text) > 0), 'Unexpected creation reply');
    S.Close;
    Failed := False;
    try S.HandlePacket(P, Replies);
    except on E: EKarosProtocol do Failed := True; end;
    Check(Failed and (Length(Replies) = 0), 'Closed probe session replied');
  finally S.Free; end;
  Writeln('PASS: empty-account admission, exact replies, ordering, duplicates, no stored account or character');
end;

procedure EmptyAccountNetworkTests;
var S: TEmulatorServer; C, Other: TIdTCPClient; Login, Expected, Ping: TBytes;
  Received: TIdBytes; Text, Line: string;
begin
  S := TEmulatorServer.Create(emB1008, blEmptyAccountProbe);
  C := TIdTCPClient.Create(nil);
  Other := TIdTCPClient.Create(nil);
  try
    S.Start(0);
    C.Host := EmulatorHost; C.Port := S.Port;
    C.ConnectTimeout := 1000; C.ReadTimeout := 1500; C.Connect;
    Login := TB1008Wire.Encode(Hex('020001020304000E00007465737400746573740000'));
    // Fragmented login produces two complete, separately encoded frames in order.
    C.IOHandler.Write(TIdBytes(Copy(Login, 0, 7)));
    Check(not C.IOHandler.CheckForDataOnSource(100), 'Reply before full login');
    C.IOHandler.Write(TIdBytes(Copy(Login, 7, Length(Login)-7)));
    Expected := Join(TB1008Wire.Encode(Hex('020001020304000E0000000000')),
      TB1008Wire.Encode(Hex('0201010203040100000000')));
    C.IOHandler.ReadBytes(Received, Length(Expected), False);
    Equal(TBytes(Received), Expected, 'Network login response order and bytes');
    WaitPackets(S, 1, 2, 0);
    // Coalesced duplicate+ping: no second list, just one ping reply.
    Ping := TB1008Wire.Encode(Hex('0B0001020304FFFFFFFF00000000'));
    C.IOHandler.Write(TIdBytes(Join(Login, Ping)));
    Received := nil; // Indy may retain the previous buffer length on shorter reads.
    C.IOHandler.ReadBytes(Received, Length(Ping), False);
    Equal(TBytes(Received), Ping, 'Duplicate login replayed before ping');
    WaitPackets(S, 3, 3, 0);
    Check(not C.IOHandler.CheckForDataOnSource(100), 'Extra response after duplicate');
    Other.Host := EmulatorHost; Other.Port := S.Port;
    Other.ConnectTimeout := 1000; Other.ReadTimeout := 1500; Other.Connect;
    Other.IOHandler.Write(TIdBytes(Login));
    Received := nil;
    Other.IOHandler.ReadBytes(Received, Length(Expected), False);
    Equal(TBytes(Received), Expected, 'Probe state shared between sessions');
    WaitPackets(S, 4, 5, 0);
    Text := '';
    for Line in S.DrainLogs do Text := Text + Line + sLineBreak;
    Check((Pos('02/00 LoginAckProbe', Text) > 0) and
      (Pos('02/01 EmptyCharacterListEnd', Text) > 0), 'Reply names missing');
    Check(Pos('test', Text) = 0, 'Credential leaked into network log');
    Other.Disconnect;
    C.Disconnect;
    S.Stop;
  finally Other.Free; C.Free; S.Free; end;
  Writeln('PASS: probe TCP fragmentation, two ordered frames, duplicate suppression, ping, session isolation');
end;

procedure ServeProbe;
var S: TEmulatorServer; A, B, C: Int64; Started: UInt64;
begin
  // Optional short-lived loopback host for testing the separate PowerShell probe.
  S := TEmulatorServer.Create;
  try
    S.Start(0);
    Writeln('PROBE_PORT=', S.Port);
    Flush(Output);
    Started := GetTickCount64;
    repeat
      S.GetProtocolStatistics(A, B, C);
      if B > 0 then Break;
      Sleep(10);
    until GetTickCount64 - Started > 30000;
    Check((A = 1) and (B = 1) and (C = 0), 'Probe host timed out or wrong counters');
    Writeln('PASS: external probe exchanged one b1008 ping');
  finally S.Free; end;
end;

begin
  try
    if (ParamCount = 1) and (ParamStr(1) = '--serve-probe') then
      ServeProbe
    else
    begin
      CodecTests;
      SessionTests;
      LoginUtf8Tests;
      NetworkTests;
      EmptyAccountTests;
      EmptyAccountNetworkTests;
      Writeln('ALL B1008 TESTS PASSED');
    end;
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
