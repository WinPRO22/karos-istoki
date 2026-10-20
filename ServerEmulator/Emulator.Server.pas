unit Emulator.Server;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  IdTCPServer, IdContext, IdGlobal, Emulator.Protocol.B1008, Emulator.Session, Emulator.Login.B1008,
  Emulator.Character.B1008, Emulator.WorldState.B1008, Emulator.QuestState.B1008,
  Emulator.Runtime, Emulator.LootStore.B1008;

const
  EmulatorHost = '127.0.0.1';
  EmulatorDefaultPort = 10001;
  EmulatorMaxClients = 8;
  EmulatorLogCapacity = 1000;
  EmulatorHexPreviewBytes = 256;

type
  TEmulatorMode = (emB1008, emRawDiagnostic);

  TB1008ScheduledReply = record
    DueTick: UInt64;
    Payload: TBytes;
  end;

  // Owned by one Indy connection worker. The queue therefore needs no lock.
  TB1008ConnectionState = class
  private
    FSession: TEmulatorSession;
    FReplies: TQueue<TB1008ScheduledReply>;
    FNextCombatStartTick: UInt64;
  public
    constructor Create(ALoginMode: TB1008LoginMode; ACharacters: TB1008CharacterStore;
      AWorld: TB1008WorldStore; AQuests: TB1008QuestStore;
      ARuntime: TEmulatorRuntimeManager = nil; ALoot: TB1008LootStore = nil);
    destructor Destroy; override;
    procedure Enqueue(const APayload: TBytes; ADueTick: UInt64);
    function TryPopDue(ANowTick: UInt64; out APayload: TBytes): Boolean;
    procedure ReserveCombatCycle(ANowTick: UInt64; out AStartTick, ADamageTick: UInt64);
    property Session: TEmulatorSession read FSession;
  end;

  // Start, Stop, Running and Port belong to the controlling (GUI) thread.
  // DrainLogs and GetStatistics may be called while Indy workers are running.
  TEmulatorServer = class
  private
    FServer: TIdTCPServer;
    FLock: TCriticalSection;
    FLogs: TQueue<string>;
    FDroppedLogs: Integer;
    FClientCount: Integer;
    FReceivedBytes: Int64;
    FPort: Word;
    FMode: TEmulatorMode;
    FLoginMode: TB1008LoginMode;
    FCharacters: TB1008CharacterStore;
    FWorld: TB1008WorldStore;
    FQuests: TB1008QuestStore;
    FLoot: TB1008LootStore;
    FCharacterPath: string;
    FReceivedPackets: Int64;
    FSentPackets: Int64;
    FProtocolErrors: Int64;
    FRuntime: TEmulatorRuntimeManager;
    FDatabasePath: string;
    FFullBerneo:Boolean;
    procedure EnsureRuntime;
    procedure Log(const AText: string);
    procedure ClientConnect(AContext: TIdContext);
    procedure ClientDisconnect(AContext: TIdContext);
    procedure ClientExecute(AContext: TIdContext);
    procedure ClientException(AContext: TIdContext; AException: Exception);
    procedure SendReply(AContext: TIdContext; const AReply: TBytes);
    procedure FlushScheduledReplies(AContext: TIdContext);
    procedure FlushWorldEvents(AContext: TIdContext);
    function GetRunning: Boolean;
    class function Peer(AContext: TIdContext): string; static;
    class function HexPreview(const ABytes: TIdBytes): string; static;
  public
    constructor Create(AMode: TEmulatorMode = emB1008; ALoginMode: TB1008LoginMode = blObserveOnly;
      const ACharacterPath: string = ''; const ADatabasePath: string = ''; AFullBerneo:Boolean=True);
    destructor Destroy; override;
    // Port 0 requests an available loopback port (useful for automated tests).
    procedure Start(APort: Word = EmulatorDefaultPort);
    procedure Stop;
    function DrainLogs(AMaxLines: Integer = 200): TArray<string>;
    procedure GetStatistics(out AClientCount: Integer; out AReceivedBytes: Int64);
    procedure GetProtocolStatistics(out AReceived, ASent, AErrors: Int64);
    function ReloadContent(out AStatus: string): Boolean;
    function ReloadRates(out AStatus:string;const APath:string=''):Boolean;
    function ContentRevision: Int64;
    function ContentDatabasePath: string;
    property Running: Boolean read GetRunning;
    property Port: Word read FPort;
  end;

implementation

uses
  Winapi.Windows, IdSocketHandle, IdException, IdStackConsts, Emulator.Combat.B1008,
  Emulator.Repository.SQLite, Emulator.Profile.B1008, Emulator.DropProfile.B1008,
  Emulator.Rates.B1008,Emulator.Items.B1008;

constructor TB1008ConnectionState.Create(ALoginMode: TB1008LoginMode;
  ACharacters: TB1008CharacterStore; AWorld: TB1008WorldStore;
  AQuests: TB1008QuestStore; ARuntime: TEmulatorRuntimeManager;
  ALoot: TB1008LootStore);
begin
  inherited Create;
  FSession := TEmulatorSession.Create(ALoginMode, ACharacters, AWorld, AQuests,
    ARuntime,ALoot);
  FReplies := TQueue<TB1008ScheduledReply>.Create;
end;

destructor TB1008ConnectionState.Destroy;
begin
  FReplies.Free;
  FSession.Free;
  inherited Destroy;
end;

procedure TB1008ConnectionState.Enqueue(const APayload: TBytes; ADueTick: UInt64);
var
  Item: TB1008ScheduledReply;
begin
  Item.DueTick := ADueTick;
  Item.Payload := Copy(APayload);
  FReplies.Enqueue(Item);
end;

function TB1008ConnectionState.TryPopDue(ANowTick: UInt64;
  out APayload: TBytes): Boolean;
var
  Item: TB1008ScheduledReply;
begin
  Result := (FReplies.Count > 0) and (FReplies.Peek.DueTick <= ANowTick);
  if not Result then
  begin
    APayload := nil;
    Exit;
  end;
  Item := FReplies.Dequeue;
  APayload := Item.Payload;
end;

procedure TB1008ConnectionState.ReserveCombatCycle(ANowTick: UInt64;
  out AStartTick, ADamageTick: UInt64);
begin
  AStartTick := FNextCombatStartTick;
  if AStartTick < ANowTick then
    AStartTick := ANowTick;
  ADamageTick := AStartTick + B1008DiagnosticHitDelayMS;
  FNextCombatStartTick := ADamageTick;
end;

constructor TEmulatorServer.Create(AMode: TEmulatorMode; ALoginMode: TB1008LoginMode;
  const ACharacterPath, ADatabasePath: string; AFullBerneo:Boolean);
begin
  inherited Create;
  FMode := AMode;
  FLoginMode := ALoginMode;
  FCharacterPath := ACharacterPath;
  FDatabasePath := ADatabasePath;
  FFullBerneo:=AFullBerneo;
  FLock := TCriticalSection.Create;
  FLogs := TQueue<string>.Create;
  FServer := TIdTCPServer.Create(nil);
  FServer.MaxConnections := EmulatorMaxClients;
  FServer.OnConnect := ClientConnect;
  FServer.OnDisconnect := ClientDisconnect;
  FServer.OnExecute := ClientExecute;
  FServer.OnException := ClientException;
end;

destructor TEmulatorServer.Destroy;
begin
  // Indy closes sockets and joins its workers before their logging queue dies.
  FServer.Free;
  FRuntime.Free;
  FWorld.Free;
  FQuests.Free;
  FLoot.Free;
  FCharacters.Free;
  FLogs.Free;
  FLock.Free;
  inherited Destroy;
end;

function TEmulatorServer.GetRunning: Boolean;
begin
  Result := Assigned(FServer) and FServer.Active;
end;

procedure TEmulatorServer.EnsureRuntime;
begin
  if not Assigned(FRuntime) and (FDatabasePath <> '') then
    FRuntime := TEmulatorRuntimeManager.Create(
      TSQLiteContentRepository.Create(FDatabasePath,FFullBerneo), 'b1008',
      TB1008ContentValidator.Create);
end;

procedure TEmulatorServer.Start(APort: Word);
var
  Binding: TIdSocketHandle;
  WorldPath, RuntimeStatus: string;
begin
  if Running then
    Exit;
  if FLoginMode=blMapLoadingProbe then TB1008DropProfile.EnsureReady;
  EnsureRuntime;
  if Assigned(FRuntime) and not FRuntime.Loaded then
    if not FRuntime.Reload(RuntimeStatus) then
      raise Exception.Create('Content database: '+RuntimeStatus);
  FServer.Bindings.Clear;
  Binding := FServer.Bindings.Add;
  Binding.IPVersion := Id_IPv4;
  Binding.IP := EmulatorHost;
  Binding.Port := APort;
  FPort := 0;
  FLock.Acquire;
  try
    FClientCount := 0;
    FReceivedBytes := 0;
    FReceivedPackets := 0;
    FSentPackets := 0;
    FProtocolErrors := 0;
  finally
    FLock.Release;
  end;
  try
    if (FLoginMode in [blCharacterPreview,blMapLoadingProbe]) and not Assigned(FCharacters) then
      FCharacters := TB1008CharacterStore.Create(FCharacterPath);
    if (FLoginMode=blMapLoadingProbe) and not Assigned(FWorld) then
    begin
      WorldPath := '';
      if FCharacterPath<>'' then WorldPath := FCharacterPath+'.world';
      FWorld := TB1008WorldStore.Create(WorldPath);
    end;
    if (FLoginMode=blMapLoadingProbe) and not Assigned(FQuests) then
    begin
      WorldPath := '';
      if FCharacterPath<>'' then WorldPath := FCharacterPath+'.quests';
      FQuests := TB1008QuestStore.Create(WorldPath);
    end;
    if (FLoginMode=blMapLoadingProbe) and not Assigned(FLoot) then
    begin
      WorldPath:='';
      if FCharacterPath<>'' then WorldPath:=FCharacterPath+'.loot.sqlite3';
      FLoot:=TB1008LootStore.Create(WorldPath);
    end;
    FServer.Active := True;
    if FLoginMode=blMapLoadingProbe then begin
      Log('DROP PROFILE karos-istoki-drop-v1 | currency separate; regular bags by rate; ordinary:craft:potion weights 80:50:40; equipment 5% per x1, max one; armor:weapon 13:10; own:other class 11:10');
      Log(Format('RATES LIVE | drop=%.2f experience=%.2f fletta=%.2f carat=%.2f',
        [FLoot.Rates.Drop/100,FLoot.Rates.Experience/100,FLoot.Rates.Fletta/100,FLoot.Rates.Carat/100],TFormatSettings.Invariant));
    end;
    FPort := Binding.Port;
    if FMode = emB1008 then
    begin
      Log(Format('START %s:%d | %s | initial mode-2 codec', [EmulatorHost, FPort, B1008ProfileName]));
      if FLoginMode in [blCharacterPreview,blMapLoadingProbe] then
      begin
        if FCharacterPath = '' then
          Log('LOGIN MODE character-preview | one dummy character; memory-only')
        else
          Log('LOGIN MODE character-preview | one dummy character; persistent store: '+FCharacterPath);
      end
      else if FLoginMode = blEmptyAccountProbe then
        Log('LOGIN MODE empty-account probe | dummy credentials only; no account storage or world entry')
      else
        Log('LOGIN MODE observe-only | no login replies');
      if FLoginMode = blMapLoadingProbe then
        Log('WORLD MODE checkpoint probe | one world owner; stop position saved/restored separately; client reports, no movement simulation');
      if Assigned(FRuntime) then
        Log(Format('CONTENT LIVE | revision %d | %s',
          [FRuntime.Revision, FRuntime.DatabasePath]));
    end
    else
      Log(Format('START %s:%d | RAW DIAGNOSTIC; no replies; data may contain secrets',
        [EmulatorHost, FPort]));
  except
    on E: Exception do
    begin
      Log('START ERROR: ' + E.Message);
      FServer.Active := False;
      raise;
    end;
  end;
end;

function TEmulatorServer.ReloadRates(out AStatus:string;const APath:string):Boolean;
var Path:string;Value:TB1008Rates;
begin
  try
    if not Running or not Assigned(FLoot) then raise Exception.Create('World server is not running');
    Path:=APath;if Path='' then Path:=TB1008Items.DataPath('rates-v1.ini');
    Value:=TB1008Rates.Load(Path); // Validate everything before publication.
    FLoot.UpdateRates(Value);
    AStatus:=Format('drop=%.2f experience=%.2f fletta=%.2f carat=%.2f; active connections preserved',
      [Value.Drop/100,Value.Experience/100,Value.Fletta/100,Value.Carat/100],TFormatSettings.Invariant);
    Log('RATES RELOAD OK | '+AStatus);Result:=True;
  except on E:Exception do begin
    AStatus:=E.Message;Log('RATES RELOAD REJECTED | '+AStatus);Result:=False;
  end;end;
end;

function TEmulatorServer.ReloadContent(out AStatus: string): Boolean;
begin
  try
    EnsureRuntime;
  except
    on E: Exception do
    begin
      AStatus := E.Message;
      Log('CONTENT RELOAD REJECTED | '+AStatus);
      Exit(False);
    end;
  end;
  if not Assigned(FRuntime) then
  begin
    AStatus := 'Live Runtime is not configured for this server';
    Exit(False);
  end;
  Result := FRuntime.Reload(AStatus);
  if Result then
    Log('CONTENT RELOAD OK | '+AStatus)
  else
    Log('CONTENT RELOAD REJECTED | '+AStatus);
end;

function TEmulatorServer.ContentRevision: Int64;
begin
  if Assigned(FRuntime) then
    Result := FRuntime.Revision
  else
    Result := 0;
end;

function TEmulatorServer.ContentDatabasePath: string;
begin
  if Assigned(FRuntime) then
    Result := FRuntime.DatabasePath
  else
    Result := FDatabasePath;
end;

procedure TEmulatorServer.Stop;
begin
  if not Running then
    Exit;
  FServer.Active := False;
  Log('STOP | listener and client connections closed');
end;

procedure TEmulatorServer.Log(const AText: string);
var
  Line: string;
begin
  Line := FormatDateTime('hh:nn:ss.zzz', Now) + ' ' + AText;
  FLock.Acquire;
  try
    if FLogs.Count >= EmulatorLogCapacity then
    begin
      FLogs.Dequeue;
      if FDroppedLogs < MaxInt then
        Inc(FDroppedLogs);
    end;
    FLogs.Enqueue(Line);
  finally
    FLock.Release;
  end;
end;

function TEmulatorServer.DrainLogs(AMaxLines: Integer): TArray<string>;
var
  Count, I: Integer;
begin
  Result := nil;
  if AMaxLines <= 0 then
    Exit;
  FLock.Acquire;
  try
    Count := FLogs.Count;
    if FDroppedLogs > 0 then
      Inc(Count);
    if Count > AMaxLines then
      Count := AMaxLines;
    SetLength(Result, Count);
    I := 0;
    if (FDroppedLogs > 0) and (Count > 0) then
    begin
      Result[0] := Format('LOG OVERFLOW: %d oldest entries dropped', [FDroppedLogs]);
      FDroppedLogs := 0;
      Inc(I);
    end;
    while I < Count do
    begin
      Result[I] := FLogs.Dequeue;
      Inc(I);
    end;
  finally
    FLock.Release;
  end;
end;

procedure TEmulatorServer.GetStatistics(out AClientCount: Integer;
  out AReceivedBytes: Int64);
begin
  FLock.Acquire;
  try
    AClientCount := FClientCount;
    AReceivedBytes := FReceivedBytes;
  finally
    FLock.Release;
  end;
end;

class function TEmulatorServer.Peer(AContext: TIdContext): string;
begin
  if Assigned(AContext.Binding) then
    Result := AContext.Binding.PeerIP + ':' + IntToStr(AContext.Binding.PeerPort)
  else
    Result := '(closed socket)';
end;

procedure TEmulatorServer.ClientConnect(AContext: TIdContext);
begin
  AContext.Connection.IOHandler.ReadTimeout := 100;
  // Do not coalesce a short NPC movement/speed update with its later stop
  // while waiting for a TCP acknowledgement.
  AContext.Binding.UseNagle := False;
  AContext.Binding.SetSockOpt(Id_SOL_SOCKET, Id_SO_SNDTIMEO, 1000);
  if FMode = emB1008 then
    AContext.Data := TB1008ConnectionState.Create(FLoginMode, FCharacters,
      FWorld, FQuests, FRuntime, FLoot); // Indy owns Data.
  FLock.Acquire;
  try
    Inc(FClientCount);
  finally
    FLock.Release;
  end;
  Log('CONNECT ' + Peer(AContext));
end;

procedure TEmulatorServer.ClientDisconnect(AContext: TIdContext);
var
  State: TB1008ConnectionState;
begin
  if AContext.Data is TB1008ConnectionState then
  begin
    State := TB1008ConnectionState(AContext.Data);
    if State.Session.Decoder.PendingBytes > 0 then
      Log(Format('INCOMPLETE FRAME %s | %d pending bytes discarded',
        [Peer(AContext), State.Session.Decoder.PendingBytes]));
    State.Session.Close;
  end;
  FLock.Acquire;
  try
    if FClientCount > 0 then
      Dec(FClientCount);
  finally
    FLock.Release;
  end;
  Log('DISCONNECT ' + Peer(AContext));
end;

procedure TEmulatorServer.SendReply(AContext: TIdContext; const AReply: TBytes);
var
  WireReply: TBytes;
begin
  WireReply := TB1008Wire.Encode(AReply);
  AContext.Connection.IOHandler.Write(TIdBytes(WireReply));
  FLock.Acquire;
  try
    Inc(FSentPackets);
  finally
    FLock.Release;
  end;
  // 101 independently moving spiders produce hundreds of 04/01 packets per
  // minute. Statistics still count every packet; omit only their repetitive
  // per-packet text so the VCL memo is not the dominant server workload.
  if not ((Length(AReply)>=2) and (AReply[0]=4) and (AReply[1]=1)) then
    Log(Format('TX %s | %s/%s %s | %d decoded / %d wire bytes',
      [Peer(AContext), IntToHex(AReply[0], 2), IntToHex(AReply[1], 2),
       TB1008Login.ReplyName(AReply), Length(AReply), Length(WireReply)]));
end;

procedure TEmulatorServer.FlushScheduledReplies(AContext: TIdContext);
var
  State: TB1008ConnectionState;
  Reply: TBytes;
begin
  if not (AContext.Data is TB1008ConnectionState) then
    Exit;
  State := TB1008ConnectionState(AContext.Data);
  while State.TryPopDue(GetTickCount64, Reply) do
    SendReply(AContext, Reply);
end;

procedure TEmulatorServer.FlushWorldEvents(AContext: TIdContext);
var
  State: TB1008ConnectionState;
  Replies: TB1008Replies;
  Reply: TBytes;
  Description: string;
begin
  if not (AContext.Data is TB1008ConnectionState) then Exit;
  State:=TB1008ConnectionState(AContext.Data);
  Description:=State.Session.PollWorld(GetTickCount64,Replies);
  if Description='' then Exit;
  if Pos('SPIDER PATROL',Description)<>1 then
    Log(Format('WORLD EVENT %s | %s',[Peer(AContext),Description]));
  for Reply in Replies do
    SendReply(AContext,Reply);
end;

class function TEmulatorServer.HexPreview(const ABytes: TIdBytes): string;
var
  I, Count: Integer;
begin
  Count := Length(ABytes);
  if Count > EmulatorHexPreviewBytes then
    Count := EmulatorHexPreviewBytes;
  Result := '';
  for I := 0 to Count - 1 do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + IntToHex(ABytes[I], 2);
  end;
  if Length(ABytes) > Count then
    Result := Result + Format(' ... [preview %d/%d bytes]', [Count, Length(ABytes)]);
end;

procedure TEmulatorServer.ClientExecute(AContext: TIdContext);
var
  Bytes: TIdBytes;
  Payload, Reply: TBytes;
  Replies: TB1008Replies;
  Session: TEmulatorSession;
  State: TB1008ConnectionState;
  Description: string;
  Count, ReplyIndex: Integer;
begin
  // The client emits 05/01 at the animation impact point. Combat results are
  // therefore sent immediately after that decision instead of accumulating in
  // the old one-second transport queue.
  FlushScheduledReplies(AContext);
  FlushWorldEvents(AContext);
  // TCP fragments are assembled by the connection's decoder, never by Indy reads.
  if AContext.Connection.IOHandler.InputBufferIsEmpty then
    // NPCs do not clamp at their destination client-side. A 100 ms idle read
    // delays the stop and can overshoot by 15 units at chase speed 150.
    if not AContext.Connection.IOHandler.CheckForDataOnSource(10) then
    begin
      AContext.Connection.IOHandler.CheckForDisconnect;
      Exit;
    end;
  Count := AContext.Connection.IOHandler.InputBuffer.Size;
  if Count > B1008ReadChunk then
    Count := B1008ReadChunk;
  if Count = 0 then
    Exit;
  AContext.Connection.IOHandler.ReadBytes(Bytes, Count, False);
  FLock.Acquire;
  try
    Inc(FReceivedBytes, Count);
  finally
    FLock.Release;
  end;
  if FMode = emRawDiagnostic then
  begin
    Log(Format('RX %s | %d bytes | %s', [Peer(AContext), Count, HexPreview(Bytes)]));
    Exit;
  end;
  State := TB1008ConnectionState(AContext.Data);
  Session := State.Session;
  try
    Session.Decoder.Append(TBytes(Bytes));
    while Session.Decoder.TryPop(Payload) do
    begin
      Description := Session.HandlePacket(Payload, Replies);
      FLock.Acquire;
      try
        Inc(FReceivedPackets);
      finally
        FLock.Release;
      end;
      Log(Format('PACKET %s | %s', [Peer(AContext), Description]));
      for ReplyIndex := 0 to High(Replies) do
      begin
        Reply := Replies[ReplyIndex];
        SendReply(AContext, Reply);
      end;
    end;
  except
    on E: EKarosProtocol do
    begin
      FLock.Acquire;
      try
        Inc(FProtocolErrors);
      finally
        FLock.Release;
      end;
      Session.Close;
      Log('PROTOCOL ERROR ' + Peer(AContext) + ' | ' + E.Message);
      AContext.Connection.Disconnect;
    end;
  end;
end;

procedure TEmulatorServer.GetProtocolStatistics(out AReceived, ASent, AErrors: Int64);
begin
  FLock.Acquire;
  try
    AReceived := FReceivedPackets;
    ASent := FSentPackets;
    AErrors := FProtocolErrors;
  finally
    FLock.Release;
  end;
end;

procedure TEmulatorServer.ClientException(AContext: TIdContext; AException: Exception);
begin
  if not (AException is EIdConnClosedGracefully) then
    Log('CONNECTION ERROR ' + Peer(AContext) + ' | ' + AException.Message);
end;

end.
