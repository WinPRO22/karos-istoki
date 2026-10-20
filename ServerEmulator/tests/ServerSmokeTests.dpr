program ServerSmokeTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.IOUtils, Winapi.Windows, Vcl.Forms,
  IdTCPClient, IdGlobal,
  Emulator.Server in '..\Emulator.Server.pas',
  Emulator.Login.B1008 in '..\Emulator.Login.B1008.pas',
  serverGUI in '..\serverGUI.pas' {Form23};

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure WaitForStats(AServer: TEmulatorServer; AClients: Integer; ABytes: Int64);
var
  Started: UInt64;
  Clients: Integer;
  Bytes: Int64;
begin
  Started := GetTickCount64;
  repeat
    AServer.GetStatistics(Clients, Bytes);
    if (Clients = AClients) and (Bytes = ABytes) then
      Exit;
    Sleep(10);
  until GetTickCount64 - Started > 5000;
  raise Exception.CreateFmt('Statistics timeout: clients=%d/%d bytes=%d/%d',
    [Clients, AClients, Bytes, ABytes]);
end;

function TakeLogs(AServer: TEmulatorServer): string;
var
  Lines: TArray<string>;
  Line: string;
begin
  Result := '';
  repeat
    Lines := AServer.DrainLogs(10);
    Check(Length(Lines) <= 10, 'Drain limit exceeded');
    for Line in Lines do
      Result := Result + Line + sLineBreak;
  until Length(Lines) = 0;
end;

procedure NetworkTests;
var
  Server, Competitor: TEmulatorServer;
  Clients: array[0..EmulatorMaxClients - 1] of TIdTCPClient;
  Data: TIdBytes;
  I, N: Integer;
  Expected: Int64;
  Logs: string;
  LogBatch: TArray<string>;
  Started: UInt64;
  BindFailed: Boolean;
begin
  Server := TEmulatorServer.Create(emRawDiagnostic);
  Competitor := nil;
  for I := Low(Clients) to High(Clients) do
    Clients[I] := nil;
  try
    Check(not Server.Running, 'Unexpected initial state');
    Server.Stop;
    Server.Start(0);
    Check(Server.Running and (Server.Port <> 0), 'Listener failed to bind');
    Server.Start; // Idempotent: does not replace the existing listener.
    Writeln('PASS: loopback bind and idempotent start/stop');

    Competitor := TEmulatorServer.Create;
    BindFailed := False;
    try
      Competitor.Start(Server.Port);
    except
      on E: Exception do
        BindFailed := True;
    end;
    Check(BindFailed and not Competitor.Running, 'Occupied port was not rejected');
    Competitor.Start(0);
    Competitor.Stop;
    FreeAndNil(Competitor);
    Writeln('PASS: occupied port and recovery after failed start');

    Clients[0] := TIdTCPClient.Create(nil);
    Clients[0].Host := EmulatorHost;
    Clients[0].Port := Server.Port;
    Clients[0].ConnectTimeout := 1000;
    Clients[0].Connect;
    SetLength(Data, 3);
    Data[0] := $00;
    Data[1] := $7F;
    Data[2] := $FF;
    Clients[0].IOHandler.Write(Data);
    WaitForStats(Server, 1, 3);
    Sleep(30); // Statistics are updated immediately before the log is queued.
    Logs := TakeLogs(Server);
    Check(Pos('00 7F FF', Logs) > 0, 'Binary log missing');
    Check(not Clients[0].IOHandler.CheckForDataOnSource(100), 'Unexpected reply');
    Writeln('PASS: binary input, hex log, no fabricated game reply');

    SetLength(Data, 8192);
    for I := 0 to High(Data) do
      Data[I] := Byte(I and $FF);
    Clients[0].IOHandler.Write(Data);
    WaitForStats(Server, 1, 8195);
    Sleep(30);
    Logs := TakeLogs(Server);
    Check(Pos('[preview 256/', Logs) > 0, 'Large log was not bounded');
    Expected := 8195;
    for I := 1 to High(Clients) do
    begin
      Clients[I] := TIdTCPClient.Create(nil);
      Clients[I].Host := EmulatorHost;
      Clients[I].Port := Server.Port;
      Clients[I].ConnectTimeout := 1000;
      Clients[I].Connect;
      Clients[I].IOHandler.Write(Data);
      Inc(Expected, Length(Data));
    end;
    WaitForStats(Server, EmulatorMaxClients, Expected);
    Writeln('PASS: large reads, bounded previews and eight clients');

    // More than 1000 reads with no GUI draining: bounded queue must shed logs.
    SetLength(Data, 1100 * 4096);
    Clients[0].IOHandler.Write(Data);
    Inc(Expected, Length(Data));
    WaitForStats(Server, EmulatorMaxClients, Expected);
    Sleep(30);
    LogBatch := Server.DrainLogs(EmulatorLogCapacity + 20);
    Check(Length(LogBatch) = EmulatorLogCapacity + 1, 'Queue capacity mismatch');
    Check(Pos('LOG OVERFLOW:', LogBatch[0]) = 1, 'Overflow was not reported');
    Writeln('PASS: log queue bounded under receive flood, dropped logs reported');

    Clients[0].Disconnect;
    WaitForStats(Server, EmulatorMaxClients - 1, Expected);
    Started := GetTickCount64;
    Server.Stop;
    Check(GetTickCount64 - Started < 5000, 'Shutdown took too long');
    WaitForStats(Server, 0, Expected);
    Check(not Server.Running, 'Listener still active after stop');
    for I := Low(Clients) to High(Clients) do
      FreeAndNil(Clients[I]);
    Writeln('PASS: disconnect and stop with idle connected clients');

    for N := 1 to 3 do
    begin
      Server.Start(0);
      WaitForStats(Server, 0, 0);
      Server.Stop;
    end;
    Server.Start(0);
    Clients[0] := TIdTCPClient.Create(nil);
    Clients[0].Host := EmulatorHost;
    Clients[0].Port := Server.Port;
    Clients[0].Connect;
    WaitForStats(Server, 1, 0);
    FreeAndNil(Server); // Form destruction uses this same path.
    Writeln('PASS: restart and destruction with a live connection');
  finally
    for I := Low(Clients) to High(Clients) do
      Clients[I].Free;
    Competitor.Free;
    Server.Free;
  end;
end;

procedure FormTests;
var
  Form: TForm23;
begin
  Application.Initialize;
  Form := TForm23.Create(nil); // Never shown; no original client is launched.
  try
    Check(Assigned(Form.btn1.OnClick), 'Start event missing');
    Check(Assigned(Form.btn2.OnClick), 'Stop event missing');
    Check(Assigned(Form.btn3.OnClick), 'Client event missing');
    Check(Form.btn1.Enabled and not Form.btn2.Enabled, 'Wrong initial buttons');
    Check(Form.mmo1.ReadOnly and (Form.mmo1.Lines.Count >= 2), 'Log not initialized');
    Check(Form.btn1.Caption = #$0421#$0442#$0430#$0440#$0442, 'UTF-8 caption corrupted');
  finally
    Form.Free;
  end;
  Writeln('PASS: hidden VCL form, events, initial state and Russian captions');
end;

procedure GuiSQLiteStartTest;
var
  ID: TGUID;
  DatabasePath: string;
  Server: TEmulatorServer;
begin
  CreateGUID(ID);
  DatabasePath:=TPath.Combine(TPath.GetTempPath,
    'karos-gui-'+Copy(GUIDToString(ID),2,36)+'.sqlite3');
  Server:=TEmulatorServer.Create(emB1008,blObserveOnly,'',DatabasePath);
  try
    Server.Start(0);
    Check(Server.Running and (Server.ContentRevision>0),
      'GUI process could not initialize SQLite Live Runtime');
    Server.Stop;
  finally
    Server.Free;
    if FileExists(DatabasePath) then TFile.Delete(DatabasePath);
    if FileExists(DatabasePath+'-wal') then TFile.Delete(DatabasePath+'-wal');
    if FileExists(DatabasePath+'-shm') then TFile.Delete(DatabasePath+'-shm');
  end;
  Writeln('PASS: GUI process initializes SQLite Live Runtime');
end;

begin
  try
    NetworkTests;
    FormTests;
    GuiSQLiteStartTest;
    Writeln('ALL TESTS PASSED');
  except
    on E: Exception do
    begin
      Writeln('FAIL: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
