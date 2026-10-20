program B1008TestHost;
{$APPTYPE CONSOLE}

uses System.SysUtils, System.Classes, System.IOUtils, System.JSON, Winapi.Windows,
  FireDAC.ConsoleUI.Wait, Emulator.Server, Emulator.Login.B1008,
  Emulator.Character.B1008, Emulator.Repository.SQLite, Emulator.Client.B1008,
  Emulator.World.B1008;

var Server:TEmulatorServer; Client:TB1008LocalClient; Log:TStreamWriter;
  RunDir,CharacterPath,ContentPath,Status,ClientDirectory:string;
  NoClient,Smoke:Boolean; ClientID,ClientExit:Cardinal;
  PlayerSpeedMultiplier:Integer;
  Info:TJSONObject; Lock:TFileStream;

procedure Drain;
var Lines:TArray<string>;Line:string;
begin
  Lines:=Server.DrainLogs(1000);
  for Line in Lines do Log.WriteLine(Line);
  if Length(Lines)>0 then Log.Flush;
end;

begin
  Server:=nil;Client:=nil;Log:=nil;Lock:=nil;
  try
    // Offline release preflight: exercise the same directory/EXE/TEN guard
    // used by Launch, without opening a server socket or game process.
    if (ParamCount=1) and ParamStr(1).StartsWith('--verify-client=') then
    begin
      TB1008LocalClient.ValidateDirectory(Copy(ParamStr(1),17,MaxInt));
      Writeln('PASS: Berneo client directory, exact executable and local endpoint');
      Exit;
    end;
    if (ParamCount<1) or (ParamCount>5) then
      raise Exception.Create('Usage: B1008TestHost <new run directory> [--no-client] [--smoke] [--player-speed=1..20] [--client-dir=<path>]');
    NoClient:=False;Smoke:=False;PlayerSpeedMultiplier:=1;ClientDirectory:='';
    for var I:=2 to ParamCount do
      if ParamStr(I)='--no-client' then NoClient:=True
      else if ParamStr(I)='--smoke' then begin Smoke:=True;NoClient:=True;end
      else if ParamStr(I).StartsWith('--player-speed=') then
        PlayerSpeedMultiplier:=StrToInt(Copy(ParamStr(I),16,MaxInt))
      else if ParamStr(I).StartsWith('--client-dir=') then
        ClientDirectory:=Copy(ParamStr(I),14,MaxInt)
      else raise Exception.Create('Unknown test host option');
    ConfigureB1008TestPlayerSpeed(PlayerSpeedMultiplier);
    RunDir:=ExpandFileName(ParamStr(1));
    if not DirectoryExists(RunDir) or FileExists(TPath.Combine(RunDir,'server.log')) then
      raise Exception.Create('Run directory must exist and have no previous log');
    Lock:=TFileStream.Create(TPath.Combine(RunDir,'host.lock'),fmCreate or fmShareExclusive);
    Log:=TStreamWriter.Create(TFileStream.Create(TPath.Combine(RunDir,'server.log'),
      fmCreate or fmShareDenyWrite),TEncoding.UTF8);Log.OwnStream;
    Log.WriteLine(Format('TEST PLAYER SPEED | multiplier=%d walk=%.0f run=%.0f | process only',
      [PlayerSpeedMultiplier,B1008PlayerSpeedA,B1008PlayerSpeedB]));Log.Flush;
    if Smoke then begin
      CharacterPath:='';ContentPath:=TPath.Combine(RunDir,'smoke-content.sqlite3');
    end else begin
      // Exactly the production GUI's paths/mode; no second combat implementation.
      CharacterPath:=TB1008CharacterStore.DefaultPath(ExtractFilePath(ParamStr(0)));
      ContentPath:=TSQLiteContentRepository.DefaultDatabasePath(ExtractFilePath(ParamStr(0)));
    end;
    Server:=TEmulatorServer.Create(emB1008,blMapLoadingProbe,CharacterPath,ContentPath);
    Client:=TB1008LocalClient.Create;
    if Smoke then Server.Start(0) else Server.Start(10001);
    Drain;
    ClientID:=0;
    if not NoClient then ClientID:=Client.Launch(ClientDirectory);
    Info:=TJSONObject.Create;
    try
      Info.AddPair('hostPid',TJSONNumber.Create(GetCurrentProcessId));
      Info.AddPair('clientPid',TJSONNumber.Create(ClientID));
      Info.AddPair('port',TJSONNumber.Create(Server.Port));
      Info.AddPair('characterPath',CharacterPath);Info.AddPair('contentPath',ContentPath);
      Info.AddPair('smoke',TJSONBool.Create(Smoke));
      Info.AddPair('playerSpeedMultiplier',TJSONNumber.Create(PlayerSpeedMultiplier));
      TFile.WriteAllText(TPath.Combine(RunDir,'ready.tmp'),Info.ToJSON,TEncoding.UTF8);
      TFile.Move(TPath.Combine(RunDir,'ready.tmp'),TPath.Combine(RunDir,'ready.json'));
    finally Info.Free;end;
    Log.WriteLine(Format('HOST READY | port=%d clientPid=%d smoke=%s',
      [Server.Port,ClientID,BoolToStr(Smoke,True)]));Log.Flush;
    while not FileExists(TPath.Combine(RunDir,'stop.request')) do begin
      Drain;
      if Client.PollExit(ClientExit) then begin
        Log.WriteLine(Format('CLIENT EXIT | code=%d',[ClientExit]));Log.Flush;
      end;
      if FileExists(TPath.Combine(RunDir,'reload.request')) then begin
        TFile.Delete(TPath.Combine(RunDir,'reload.request'));
        if Server.ReloadContent(Status) then Log.WriteLine('CONTENT RELOADED | '+Status)
        else Log.WriteLine('CONTENT REJECTED | '+Status);
        Log.Flush;
      end;
      if FileExists(TPath.Combine(RunDir,'reload-rates.request')) then begin
        TFile.Delete(TPath.Combine(RunDir,'reload-rates.request'));
        if Server.ReloadRates(Status) then Log.WriteLine('RATES RELOADED | '+Status)
        else Log.WriteLine('RATES REJECTED | '+Status);
        Log.Flush;
      end;
      Sleep(100);
    end;
    Server.Stop;Drain;Log.WriteLine('HOST STOPPED | graceful');Log.Flush;
  except on E:Exception do begin
    if Assigned(Log) then begin Log.WriteLine('HOST ERROR | '+E.ClassName+': '+E.Message);Log.Flush;end;
    Writeln('HOST ERROR: ',E.ClassName,': ',E.Message);ExitCode:=1;
  end;end;
  Client.Free;Server.Free;Log.Free;Lock.Free;
end.
