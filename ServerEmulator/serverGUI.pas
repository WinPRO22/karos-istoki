unit serverGUI;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.UITypes, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Emulator.Server, Emulator.Client.B1008, Emulator.Login.B1008,
  Emulator.Character.B1008, Emulator.Repository.SQLite, FireDAC.VCLUI.Wait;

type
  TForm23 = class(TForm)
    btn1: TButton;
    btn2: TButton;
    lbl1: TLabel;
    mmo1: TMemo;
    btn3: TButton;
    btn4: TButton;
    lbl2: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btn1Click(Sender: TObject);
    procedure btn2Click(Sender: TObject);
    procedure btn3Click(Sender: TObject);
    procedure btn4Click(Sender: TObject);
  private
    FServer: TEmulatorServer;
    FClient: TB1008LocalClient;
    FLogTimer: TTimer;
    procedure RefreshServer(Sender: TObject);
    procedure AppendLog(const AText: string);
  public
    { Public declarations }
  end;

var
  Form23: TForm23;

implementation

{$R *.dfm}

procedure TForm23.FormCreate(Sender: TObject);
begin
  FServer := TEmulatorServer.Create(emB1008, blMapLoadingProbe,
    TB1008CharacterStore.DefaultPath(ExtractFilePath(ParamStr(0))),
    TSQLiteContentRepository.DefaultDatabasePath(ExtractFilePath(ParamStr(0))));
  FClient := TB1008LocalClient.Create;
  FLogTimer := TTimer.Create(Self);
  FLogTimer.Enabled := False;
  FLogTimer.Interval := 100;
  FLogTimer.OnTimer := RefreshServer;
  btn1.Caption := 'Старт';
  btn2.Caption := 'Стоп';
  btn3.Caption := 'Запуск клиента';
  btn4.Caption := 'Перезагрузить данные';
  btn4.ShowHint := True;
  btn4.Hint := 'Проверить БД и атомарно применить новую ревизию без пересборки';
  btn3.ShowHint := True;
  btn3.Hint := 'Прямой запуск runtime\b1008\AMo.exe; проверка EXE и локального адреса';
  mmo1.ReadOnly := True;
  mmo1.ScrollBars := ssBoth;
  mmo1.WordWrap := False;
  lbl1.ShowHint := True;
  Caption := 'Karos — Истоки / Berneo b1008';
  AppendLog('Готово. Эмулятор Бернео: 127.0.0.1:10001. Один локальный персонаж с сохранением.');
  AppendLog('Лимит уровня 45. Баланс и рейты читаются из data\b1008 при запуске.');
  AppendLog('ID test, пароль test. Имя: 4–14 латинских букв/цифр, например Arden; KarosTest запрещено клиентом.');
  AppendLog('Мир: только Бернео, 955 существ, 29 NPC, 16 магазинов, 41 активное задание.');
  AppendLog('Состояние персонажа, инвентаря, заданий и позиции сохраняется локально.');
  AppendLog('Используй только вымышленные учётные данные. Содержимое строк в логах скрывается.');
  AppendLog('Запуск клиента разрешён без изменения брандмауэра. Прочие сетевые обращения клиента не блокируются.');
  AppendLog('Live Runtime: SQLite + снимок в памяти. Изменения применяются кнопкой «Перезагрузить данные» без пересборки.');
  RefreshServer(nil);
  FLogTimer.Enabled := True;
end;

procedure TForm23.FormDestroy(Sender: TObject);
begin
  if Assigned(FLogTimer) then
    FLogTimer.Enabled := False;
  FreeAndNil(FServer);
  FreeAndNil(FClient);
end;

procedure TForm23.AppendLog(const AText: string);
begin
  mmo1.Lines.Add(AText);
  while mmo1.Lines.Count > 2000 do
    mmo1.Lines.Delete(0);
end;

procedure TForm23.RefreshServer(Sender: TObject);
var
  Line: string;
  Clients: Integer;
  Received, Packets, Sent, Errors: Int64;
  ClientExitCode: Cardinal;
begin
  if not Assigned(FServer) then
    Exit;
  mmo1.Lines.BeginUpdate;
  try
    for Line in FServer.DrainLogs do
      AppendLog(Line);
  finally
    mmo1.Lines.EndUpdate;
  end;
  FServer.GetStatistics(Clients, Received);
  FServer.GetProtocolStatistics(Packets, Sent, Errors);
  btn1.Enabled := not FServer.Running;
  btn2.Enabled := FServer.Running;
  if Assigned(FClient) then
  begin
    if FClient.PollExit(ClientExitCode) then
      AppendLog(Format('Клиент завершён; код %d ($%s).', [ClientExitCode, IntToHex(ClientExitCode, 8)]));
    btn3.Enabled := FServer.Running and not FClient.Running;
  end;
  if FServer.Running then
    lbl1.Caption := Format('Работает (%d)', [Clients])
  else
    lbl1.Caption := 'Остановлен';
  if FServer.ContentRevision > 0 then
    lbl2.Caption := Format('Данные: rev.%d', [FServer.ContentRevision])
  else
    lbl2.Caption := 'Данные: не загружены';
  lbl2.Hint := FServer.ContentDatabasePath;
  lbl1.Hint := Format('Клиентов: %d; байт: %d; пакетов RX/TX: %d/%d; ошибок: %d',
    [Clients, Received, Packets, Sent, Errors]);
end;

procedure TForm23.btn4Click(Sender: TObject);
var
  Status: string;
begin
  btn4.Enabled := False;
  try
    if FServer.ReloadContent(Status) then
      AppendLog('Данные применены: '+Status)
    else
      AppendLog('Данные не применены: '+Status);
  finally
    btn4.Enabled := True;
  end;
  RefreshServer(nil);
end;

procedure TForm23.btn1Click(Sender: TObject);
begin
  btn1.Enabled := False;
  try
    FServer.Start;
  except
    on E: Exception do
      AppendLog('Не удалось запустить сервер: ' + E.Message);
  end;
  RefreshServer(nil);
end;

procedure TForm23.btn2Click(Sender: TObject);
begin
  btn2.Enabled := False;
  try
    FServer.Stop;
  except
    on E: Exception do
      AppendLog('Ошибка остановки: ' + E.Message);
  end;
  RefreshServer(nil);
end;

procedure TForm23.btn3Click(Sender: TObject);
var ClientID: Cardinal;
begin
  try
    if not FServer.Running or (FServer.Port <> 10001) then
      raise Exception.Create('Сначала запусти сервер на 127.0.0.1:10001.');
    ClientID := FClient.Launch;
    AppendLog(Format('AMo.exe b1008 запущен напрямую, PID %d; ожидается запрос входа.', [ClientID]));
  except
    on E: Exception do AppendLog('Клиент не запущен: ' + E.Message);
  end;
  RefreshServer(nil);
end;

end.
