program B1008RatesTests;
{$APPTYPE CONSOLE}
uses System.SysUtils,System.IOUtils,FireDAC.Comp.Client,
  IdTCPClient,IdGlobal,Emulator.Server,Emulator.Login.B1008,
  Emulator.Rates.B1008,Emulator.DropProfile.B1008,Emulator.Items.B1008,
  Emulator.Character.B1008,Emulator.LootStore.B1008,Emulator.Balance.B1008,
  Emulator.Fletta.B1008;

procedure Check(B:Boolean;const Msg:string);
begin if not B then raise Exception.Create(Msg);end;

function UnitRates:TB1008Rates;
begin
  Result.Drop:=100;Result.Experience:=100;Result.Fletta:=100;Result.Carat:=100;
end;

function Hero:TBytes;
begin Result:=TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(
  TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
    72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0)),1);end;

procedure FormulaTests;
var R:TB1008Rates;I,Count,Valuable,All,Base:Integer;Failed:Boolean;
begin
  R:=UnitRates;
  Check(TB1008Rates.Scale(9,150,100000000)=14,'Half-up money');
  Check(TB1008Rates.Scale(8,125,1000)=10,'Fractional EXP');
  Check(TB1008Rates.Scale(High(Int64),2000,100000000)=100000000,'Overflow/cap');
  Check(TB1008Rates.Scale(8,0,1000)=0,'Disabled rate');
  Check(TB1008Rates.Scale(8,2000,0)=0,'Full progression cap');
  Failed:=False;try TB1008Rates.Scale(8,-1,1000);except on E:Exception do Failed:=True;end;Check(Failed,'Negative rate');
  R.Drop:=2001;Failed:=False;try R.Validate;except on E:Exception do Failed:=True;end;Check(Failed,'Unbounded drop rate');
  Count:=0;Valuable:=0;Base:=0;All:=0;
  for I:=0 to 999999 do begin
    Inc(Count,TB1008Rates.DropIntervalCount(0,1,1,1000,200,I));
    // The interval helper remains available to quest drops. Hypothetical
    // item weight 1/8 in an 80% pool: 10% -> exactly 20%,
    // including when the entire pool's expected count is already 1.6 bags.
    Inc(Valuable,TB1008Rates.DropIntervalCount(7,8,8,8000,200,I));
    Inc(Base,TB1008Rates.DropIntervalCount(7,8,8,8000,100,I));
    Inc(All,TB1008Rates.DropIntervalCount(0,8,8,8000,200,I));
  end;
  Check((Count=200000) and (Valuable=200000) and (Base=100000) and (All=1600000),'Exact scaled chances/bags');
  Check(TB1008Rates.DropIntervalCount(0,1,1,1000,2000,0)=2,'Quest interval lost copies above 100%');
end;

procedure DropTests;
var R:TB1008Rates;State,Before:Cardinal;I,Rate,Ordinary,Potion,Gear,Cash,RegularCount,GearCount:Integer;
  Drops:TArray<TB1008RolledDrop>;D:TB1008RolledDrop;
begin
  R:=UnitRates;R.Carat:=400;State:=12345;
  // Integer rates require an exact count on EVERY kill, not just an average.
  // Fractional rates add at most one bag; currency uses its independent rate.
  for Rate in TArray<Integer>.Create(50,100,150,200,300,400,500,2000) do begin
    R.Drop:=Rate;Ordinary:=0;Potion:=0;Gear:=0;Cash:=0;
    for I:=1 to 20000 do begin
      Drops:=TB1008DropProfile.RollMob(State,100,120,R);
      Check((Length(Drops)>0) and (Drops[0].ItemID=999999),'Guaranteed separate currency');
      RegularCount:=0;GearCount:=0;
      for D in Drops do begin
        if D.Category='currency' then begin
          Inc(Cash);Check((D.Amount>=36) and (D.Amount<=48) and (D.Amount mod 4=0),'Carat multiplier');
        end else begin
          Check(D.Amount=1,'Drop rate stacked quantity instead of separate bags');
          if D.Category='ordinary' then begin Inc(Ordinary);Inc(RegularCount);end
          else if D.Category='potion' then begin Inc(Potion);Inc(RegularCount);end
          else if (D.Category='armor') or (D.Category='weapon') then begin
            Inc(Gear);Inc(GearCount);
            Check(TB1008Items.Get(D.ItemID).RequiredLevel=5,'Rate bypassed gear tier');
          end else Check(False,'Foreign spider category');
        end;
      end;
      Check((RegularCount>=Rate div 100) and (RegularCount<=(Rate+99) div 100),'Fixed regular bag budget');
      Check(GearCount<=1,'More than one equipment item');
      if Rate=2000 then Check(GearCount=1,'Guaranteed equipment at x20');
    end;
    Check((Abs(Ordinary+Potion-Rate*200)<350) and (Abs(Gear-Rate*10)<250) and (Cash=20000),'Rate distribution');
    Check((Abs(Ordinary-Rate*200*2/3)<1500) and (Abs(Potion-Rate*200/3)<1500),'Species category proportions');
    Writeln(Format('PASS: rate=%d/100; 20000 kills: regular=%d equipment=%d; max one equipment; independent x4 carat',
      [Rate,Ordinary+Potion,Gear]));
  end;
  R.Drop:=0;R.Carat:=100;Drops:=TB1008DropProfile.RollMob(State,100,120,R);
  Check((Length(Drops)=1) and (Drops[0].ItemID=999999),'Drop zero disabled independent currency');
  R.Drop:=0;R.Carat:=0;Check(Length(TB1008DropProfile.RollMob(State,100,120,R))=0,'Disabled rewards');
  R.Drop:=100;Drops:=TB1008DropProfile.RollMob(State,500,120,R);
  Check((Length(Drops)>=1) and (Length(Drops)<=2),'Carat zero disabled regular drops');
  for D in Drops do Check(D.ItemID<>999999,'Disabled currency dropped');
  R.Drop:=-1;Before:=State;
  try TB1008DropProfile.RollMob(State,100,120,R);except on E:EArgumentException do ;end;
  Check(State=Before,'Invalid rate advanced RNG');
end;

procedure PersistenceTests;
var R:TB1008Rates;L:TB1008LootStore;O:TObject;DB:TFDConnection;G:TGUID;Dir,Path:string;
  N:Cardinal;Failed:Boolean;BeforeEXP,BeforeFletta:Int64;
begin
  CreateGUID(G);Dir:=TPath.Combine(TPath.GetTempPath,'KarosRates-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir);Path:=TPath.Combine(Dir,'hero.sqlite3');L:=nil;DB:=nil;O:=TObject.Create;
  try
    R:=UnitRates;R.Experience:=300;R.Fletta:=400;R.Drop:=200;R.Carat:=400;
    L:=TB1008LootStore.Create(Path,R);L.Acquire(O,Hero);
    // Explicit base EXP tests multipliers without depending on live species rewards.
    L.RecordMobEXP(O,'kill1',10,1);Check((L.Progress(O).TotalEXP=30) and (L.Fletta(O).Total=1150),'Independent EXP/Fletta charging');
    L.RecordMobEXP(O,'kill1',10,1);Check((L.Progress(O).TotalEXP=30) and (L.Fletta(O).Total=1150),'Reward replay');
    L.RecordQuestEXP(O,19003003);
    Check((L.Progress(O).TotalEXP=102) and (L.Fletta(O).Total=1150),'Quest rates/accidental Fletta');
    L.CollectItem(O,'money',999999,11,N);Check(L.Balance(O)=11,'Pickup double multiplied money');
    FreeAndNil(L);R.Experience:=2000;R.Fletta:=2000;L:=TB1008LootStore.Create(Path,R);L.Acquire(O,Hero);
    L.RecordMobEXP(O,'kill1',10,1);L.RecordQuestEXP(O,19003003);
    Check((L.Progress(O).TotalEXP=102) and (L.Fletta(O).Total=1150),'Rate change revalued receipts');
    L.RecordMobEXP(O,'kill2',8,20);
    Check((L.Progress(O).TotalEXP=262) and (L.Fletta(O).Total=2300),'Rate change accelerated charging');
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;DB.Params.Values['DriverID']:='SQLite';DB.Params.Values['Database']:=Path;DB.Connected:=True;
    BeforeEXP:=L.Progress(O).TotalEXP;BeforeFletta:=L.Fletta(O).Total;
    DB.ExecSQL('CREATE TRIGGER fail_rate BEFORE INSERT ON exp_receipts BEGIN SELECT RAISE(ABORT,''test'');END');
    Failed:=False;try L.RecordMobEXP(O,'failure',8,20);except on E:Exception do Failed:=True;end;
    Check(Failed and (L.Progress(O).TotalEXP=BeforeEXP) and (L.Fletta(O).Total=BeforeFletta),'Partial scaled reward commit');
    DB.ExecSQL('DROP TRIGGER fail_rate');
    DB.ExecSQL('UPDATE progression SET total_exp=:n',[TB1008Balance.MaxEXP-1]);
    DB.ExecSQL('UPDATE fletta SET total=:n',[TB1008Fletta.LevelCapacity(TB1008Balance.LevelCap)-7]);
    L.RecordMobEXP(O,'cap',High(Integer),20);
    Check((L.Progress(O).TotalEXP=TB1008Balance.MaxEXP) and
      (L.Fletta(O).Total=TB1008Fletta.LevelCapacity(TB1008Balance.LevelCap)),'Progression/Fletta cap');
    Check(Int64(DB.ExecSQLScalar('SELECT amount FROM fletta_receipts WHERE receipt=''cap'''))=7,'Receipt exceeds credited Fletta');
    FreeAndNil(L);R.Experience:=0;R.Fletta:=0;L:=TB1008LootStore.Create('',R);L.Acquire(O,Hero);
    L.RecordMobEXP(O,'zero',10,1);Check((L.Progress(O).TotalEXP=0) and (L.Fletta(O).Total=0),'Disabled progression');
  finally L.Free;DB.Free;O.Free;TDirectory.Delete(Dir,True);end;
end;

procedure LiveReloadTests;
var R:TB1008Rates;L:TB1008LootStore;O:TObject;N,State:Cardinal;
  Drops:TArray<TB1008RolledDrop>;D:TB1008RolledDrop;Regular:Integer;Failed:Boolean;
  Server:TEmulatorServer;Client:TIdTCPClient;Packet,Reply:TIdBytes;
  G:TGUID;Path,Status:string;
  procedure Ping;
  begin
    Client.IOHandler.Write(Packet);Reply:=nil;Client.IOHandler.ReadBytes(Reply,Length(Packet),False);
    Check((Length(Reply)=Length(Packet)) and CompareMem(@Reply[0],@Packet[0],Length(Packet)),
      'Live rate reload interrupted the existing connection');
  end;
begin
  R:=UnitRates;L:=TB1008LootStore.Create('',R);O:=TObject.Create;
  try
    L.Acquire(O,Hero);L.CollectItem(O,'before-rates',999999,777,N);L.RecordMobEXP(O,'before-kill',10,1);
    State:=12345;Drops:=TB1008DropProfile.RollMob(State,100,120,L.Rates);
    Check((Length(Drops)>=2) and (Length(Drops)<=3),'Initial x1');
    R.Drop:=500;L.UpdateRates(R);
    Check((L.Rates.Drop=500) and (L.Rates.Carat=100) and
      (L.Balance(O)=777) and (L.Progress(O).TotalEXP=10),'Reload changed independent rates or saved rewards');
    Check((Length(Drops)>=2) and (Length(Drops)<=3),'Old rolled drops changed');
    Drops:=TB1008DropProfile.RollMob(State,100,120,L.Rates);Regular:=0;
    for D in Drops do if (D.Category='ordinary') or (D.Category='potion') then Inc(Regular);
    Check(Regular=5,'Existing world owner did not receive new drop rate');
    R.Drop:=-1;Failed:=False;
    try L.UpdateRates(R);except on E:EArgumentException do Failed:=True;end;
    Check(Failed and (L.Rates.Drop=500),'Invalid reload replaced valid rates');
    L.RecordMobEXP(O,'before-kill',10,1);Check(L.Progress(O).TotalEXP=10,'Reload reset kill receipts');
  finally L.Free;O.Free;end;
  CreateGUID(G);Path:=TPath.Combine(TPath.GetTempPath,'karos-live-rates-'+GUIDToString(G)+'.ini');
  Server:=TEmulatorServer.Create(emB1008,blMapLoadingProbe);Client:=TIdTCPClient.Create(nil);
  try
    Server.Start(0);Client.Host:='127.0.0.1';Client.Port:=Server.Port;
    Client.ConnectTimeout:=2000;Client.ReadTimeout:=2000;Client.Connect;
    Packet:=TIdBytes.Create(0,0,0,16,$82,$87,$86,$87,$84,$87,$FB,$7B,$FC,$7C,$02,$82,$01,$81,$A5,$29);
    Ping;
    TFile.WriteAllText(Path,'[rates]'+sLineBreak+'drop=5'+sLineBreak+'experience=1'+sLineBreak+
      'fletta=1'+sLineBreak+'carat=1'+sLineBreak);
    Check(Server.ReloadRates(Status,Path) and (Pos('drop=5.00',Status)>0),Status);Ping;
    TFile.WriteAllText(Path,'[rates]'+sLineBreak+'drop=invalid');
    Check(not Server.ReloadRates(Status,Path),'Malformed live config accepted');Ping;
  finally Client.Free;Server.Free;if FileExists(Path) then TFile.Delete(Path);end;
  Writeln('PASS: live x1->x5 on existing owner, unchanged rewards/receipts, invalid rollback, same TCP connection before/after reload');
end;

procedure LevelCapTests;
var R:TB1008Rates;L:TB1008LootStore;O:TObject;DB:TFDConnection;G:TGUID;Dir,Path:string;
  Q:TB1008FlettaInvestment;F:TB1008Fletta;A:TB1008FlettaAttributes;Failed:Boolean;
  I,Carry,Value:Integer;P:TBytes;
begin
  CreateGUID(G);Dir:=TPath.Combine(TPath.GetTempPath,'KarosFlettaCap-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir);Path:=TPath.Combine(Dir,'hero.sqlite3');L:=nil;DB:=nil;O:=TObject.Create;
  try
    R:=UnitRates;R.Experience:=0;R.Fletta:=500;
    L:=TB1008LootStore.Create(Path,R);L.Acquire(O,Hero);
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;
    DB.Params.Values['DriverID']:='SQLite';DB.Params.Values['Database']:=Path;DB.Connected:=True;
    for I:=1 to 8 do L.RecordMobEXP(O,'charge/'+IntToStr(I),0,20);
    Check((L.Fletta(O).Points=0) and (L.Fletta(O).Progress=9200),'x5 accelerated charging instead of completed bars');
    L.RecordMobEXP(O,'complete',0,20);
    Check((L.Progress(O).Level=1) and (L.Fletta(O).Total=50000),'First complete bar must award 5 FP at level1');
    F:=L.Fletta(O);SetLength(P,$4B3);P[0]:=2;P[1]:=5;F.Apply(P,1,500);
    Move(P[$3A],Value,4);Check(Value=10000,'Full x5 low-level bar not 100 percent');
    Move(P[$42],Value,4);Check(Value=5,'Low-level FP display lost bundle');
    L.RecordMobEXP(O,'full',0,20);
    Check((L.Fletta(O).Total=50000) and
      (Int64(DB.ExecSQLScalar('SELECT amount FROM fletta_receipts WHERE receipt=''full'''))=0),'Full wallet credited extra energy');
    Q:=Default(TB1008FlettaInvestment);Q.CharacterID:=1;Q.Category:=1;Q.Attribute:=1;Q.Amount:=5;Q.Code:=$87;
    Check(L.InvestFletta(O,'spend',Q,F,A)=firApplied,'Spend five capped FP');
    L.RecordMobEXP(O,'complete',0,20);Check(L.Fletta(O).Total=0,'Replay paid bundle again after spending');
    L.GrantTestProgress(O,'level6',6,5);
    DB.ExecSQL('UPDATE fletta SET total=49000');
    DB.ExecSQL('CREATE TRIGGER fail_bundle BEFORE INSERT ON exp_receipts BEGIN SELECT RAISE(ABORT,''test'');END');
    Failed:=False;try L.RecordMobEXP(O,'six',0,20);except on E:Exception do Failed:=True;end;
    Check(Failed and (L.Fletta(O).Total=49000),'Bundle transaction split');
    DB.ExecSQL('DROP TRIGGER fail_bundle');L.RecordMobEXP(O,'six',0,20);
    Check(L.Fletta(O).Total=60000,'Level6 exceeded/lost six FP cap');
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,R);L.Acquire(O,Hero);
    Check((L.Fletta(O).Total=60000) and (L.FlettaAttributes(O).YangInvested=5),'Bundle/cap persistence lost investment');
    // Fractional supported rates carry between completed bars, not the HUD bar.
    R.Fletta:=150;L.UpdateRates(R);DB.ExecSQL('UPDATE fletta SET total=9000');
    L.RecordMobEXP(O,'fraction1',0,20);
    Check((L.Fletta(O).Points=1) and (L.Fletta(O).Progress=150),'x1.5 first bundle / leftover charge');
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,R);L.Acquire(O,Hero);
    Check(Integer(DB.ExecSQLScalar('SELECT remainder FROM fletta_rate_carry WHERE id=1'))=50,'Fraction carry lost on reconnect');
    DB.ExecSQL('UPDATE fletta SET total=19000');L.RecordMobEXP(O,'fraction2',0,20);
    Check((L.Fletta(O).Points=3) and (L.Fletta(O).Progress=150),'x1.5 second bundle must award 2');
    R.Fletta:=50;L.UpdateRates(R);DB.ExecSQL('UPDATE fletta SET total=9000');
    L.RecordMobEXP(O,'half',0,20);Check(L.Fletta(O).Total=150,'Half rate should retain charge and bank half a point');
    Check(Integer(DB.ExecSQLScalar('SELECT amount FROM fletta_receipts WHERE receipt=''half'''))=-8850,'Fractional bar reset delta not recorded');
    // Delevel clamps only above max(level, bundle); migration/reopen preserve old receipts.
    R.Fletta:=500;L.UpdateRates(R);DB.ExecSQL('UPDATE fletta SET total=60000');
    DB.ExecSQL('UPDATE progression SET total_exp=:n',[TB1008Balance.Threshold(1)]);
    DB.ExecSQL('CREATE TRIGGER fail_cap BEFORE INSERT ON fletta BEGIN SELECT RAISE(ABORT,''test'');END');
    Failed:=False;try L.RecordDeath(O,'death');except on E:Exception do Failed:=True;end;
    Check(Failed and (L.Progress(O).Level=2) and (L.Fletta(O).Total=60000) and not L.PendingDeath(O),'Death/cap transaction split');
    DB.ExecSQL('DROP TRIGGER fail_cap');L.RecordDeath(O,'death');
    Check((L.Progress(O).Level=1) and (L.Fletta(O).Total=50000),'Delevel erased low-level bundle allowance');
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,R);L.Acquire(O,Hero);
    L.RecordMobEXP(O,'half',0,20);Check(L.Fletta(O).Total=50000,'Reopen replayed fractional receipt');
    F:=Default(TB1008Fletta);Carry:=0;F.CreditKill(10000,500,10,Carry);
    Check(F.Total=50000,'Exact full bar bundle');
    F.CreditKill(10000,500,10,Carry);Check(F.Total=100000,'Second full bar bundle');
  finally L.Free;DB.Free;O.Free;TDirectory.Delete(Dir,True);end;
  Writeln('PASS: x5 awards five FP per full bar; low-level floor, level6 cap, charge carry, x1.5/x0.5 persistence, rollback/delevel/replay');
end;

procedure ConfigTests;
var R:TB1008Rates;G:TGUID;Path:string;Failed:Boolean;
begin
  CreateGUID(G);Path:=TPath.Combine(TPath.GetTempPath,'KarosRateConfig-'+GUIDToString(G)+'.ini');
  try
    TFile.WriteAllText(Path,'[rates]'+sLineBreak+'drop=1'+sLineBreak+'experience=1'+sLineBreak+
      'fletta=1'+sLineBreak+'carat=1'+sLineBreak,TEncoding.UTF8);
    R:=TB1008Rates.Load(Path);
    Check((R.Drop=100) and (R.Experience=100) and (R.Fletta=100) and (R.Carat=100),'Unit rate INI');
    TFile.WriteAllText(Path,'[rates]'+sLineBreak+'drop=2'+sLineBreak+'experience=1.25'+sLineBreak+
      'fletta=0'+sLineBreak+'carat=20'+sLineBreak,TEncoding.UTF8);
    R:=TB1008Rates.Load(Path);
    Check((R.Drop=200) and (R.Experience=125) and (R.Fletta=0) and (R.Carat=2000),'Rate INI/locale');
    TFile.WriteAllText(Path,'[rates]'+sLineBreak+'drop=2.001'+sLineBreak,TEncoding.UTF8);
    Failed:=False;try TB1008Rates.Load(Path);except on E:Exception do Failed:=True;end;
    Check(Failed,'Silent precision loss or missing setting');
  finally TFile.Delete(Path);end;
end;

begin
  try FormulaTests;DropTests;PersistenceTests;LiveReloadTests;LevelCapTests;ConfigTests;
    Writeln('PASS: rate bounds/rounding; fixed regular bags; equipment 5% per x1, at most one; quest interval unchanged; independent rewards; durable replay/rollback/caps');
  except on E:Exception do begin Writeln('FAIL: ',E.ClassName,': ',E.Message);ExitCode:=1;end;end;
end.
