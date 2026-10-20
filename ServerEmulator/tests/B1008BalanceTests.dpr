program B1008BalanceTests;
{$APPTYPE CONSOLE}
uses Emulator.Rates.B1008,System.SysUtils, System.IOUtils, Winapi.Windows, FireDAC.Comp.Client,
  Emulator.Balance.B1008, Emulator.Progression.B1008, Emulator.LootStore.B1008,
  Emulator.Character.B1008, Emulator.Session, Emulator.Login.B1008,
  Emulator.Protocol.B1008, Emulator.QuestState.B1008, Emulator.Combat.B1008,
  Emulator.Inventory.B1008, Emulator.Regen.B1008, Emulator.Fletta.B1008,
  Emulator.World.B1008, Emulator.Equipment.B1008;

{$I B1008UnitRates.inc}

procedure Check(B: Boolean; const S: string);
begin if not B then raise Exception.Create(S); end;
{$I B1008MigrationFixture.inc}
function Preview: TBytes;
var H: TBytes;
begin
  H:=TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
    72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);
  Result:=TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(H),1);
end;

procedure RespawnSessionTests(WithLevelLoss:Boolean);
var C:TB1008CharacterStore;S:TEmulatorSession;P,A,H:TBytes;R:TB1008Replies;
  X:Single;I,J,V:Integer;T:UInt64;Dead:Boolean;Description:string;
  L:TB1008LootStore;Progress:TB1008Progress;
begin
  C:=TB1008CharacterStore.Create;S:=nil;L:=nil;
  try
    H:=TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
      72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);
    C.CreateCharacter(H,P);
    if WithLevelLoss then begin
      L:=TB1008LootStore.Create('',FixtureRates);
      L.Acquire(C,Preview);
      // Pin death-boundary fixtures independently of the live reward profile.
      for I:=1 to 6 do Progress:=L.RecordMobEXP(C,'seed/'+IntToStr(I),8,1);
      Check(Progress.TotalEXP=48,'Level loss seed');L.Release(C);
    end;
    S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);
    S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),R);
    S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),R);
    P:=TBytes.Create(4,0,0,0,0,2,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
    X:=8669.776367;Move(X,P[11],4);X:=6668.010254;Move(X,P[15],4);X:=604.350342;Move(X,P[19],4);
    S.HandlePacket(P,R);
    SetLength(A,53);A[0]:=5;A[5]:=3;A[10]:=1;A[15]:=1;A[32]:=1;A[36]:=120;
    Move(P[11],A[16],12);Move(P[11],A[37],12);
    Description:=S.HandlePacket(A,R);Check(Pos('ATTACK START ACCEPTED',Description)>0,'Death test attack admission');
    T:=GetTickCount64;Dead:=False;
    for I:=1 to 160 do begin
      S.PollWorld(T+UInt64(I)*250,R);
      for J:=0 to High(R) do
        if (R[J][0]=8) and (R[J][6]=0) then begin
          Move(R[J][11],V,4);if V=0 then begin
            Dead:=True;
            if WithLevelLoss then Check(R[J][1]=0,'Level-down sent false level-up packet');
          end;
        end;
      if Dead then Break;
    end;
    Check(Dead,'Player never reached death');
    if WithLevelLoss then begin
      Progress:=L.Progress(S);
      Check((Progress.Level=1) and (Progress.TotalEXP=39) and L.PendingDeath(S),'Death level decrease');
      // A reconnect must remain dead without repeating the penalty.
      FreeAndNil(S);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);
      S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),R);
      S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),R);
      Move(R[0][$14],V,4);Check(V=0,'Reconnect bypassed pending death');
      Move(R[0][$3C3],X,4);Check(X=16,'Delevel retained physical growth');
      Move(R[0][$3DF],X,4);Check(X=8,'Delevel retained magical growth');
      Move(R[0][$413],X,4);Check(Abs(X-5.2)<0.001,'Delevel retained critical growth');
      P[5]:=54;S.HandlePacket(P,R);
      Check(L.Progress(S).TotalEXP=39,'Reconnect repeated death penalty');
    end;
    P[5]:=55;S.HandlePacket(P,R);
    Check((Length(R)=2) and (R[0][0]=2) and (R[1][1]=4),'Respawn loading reply');
    Move(R[0][$14],V,4);Check(V=5,'Respawn 3 percent HP');
    Move(R[0][$1C],V,4);Check(V=0,'Respawn mana not empty');
    if WithLevelLoss then Check(not L.PendingDeath(S),'Respawn left death pending');
    S.HandlePacket(P,R);Check(Length(R)=0,'Duplicate respawn request admitted as scene-ready');
    P[5]:=56;S.HandlePacket(P,R);
    Check((Length(R)>4) and (R[0][0]=4) and (R[0][1]=2) and
      (R[0][6]=1) and (R[0][7]=0),'Respawn scene/idle initialization missing');
    Move(R[0][28],V,4);Check(V=5,'Respawn appearance healed to full');
    Move(R[0][36],V,4);Check(V=0,'Respawn mana not empty');
    Check(Abs(S.WorldState.Position.X-7470.669922)<0.01,'Respawn ignored stone checkpoint');
    S.HandlePacket(P,R);Check(Length(R)=0,'Alive duplicate respawn');
    T:=GetTickCount64+1000;S.PollWorld(T,R);S.PollWorld(T+TB1008Balance.RegenIntervalMS,R);
    Dead:=True;
    for J:=0 to High(R) do
      if (R[J][0]=8) and (R[J][6]=0) then begin
        Move(R[J][11],V,4);Check(V=18,'Automatic respawn regeneration HP');
        Move(R[J][19],V,4);Check(V=1,'Automatic respawn regeneration MP');Dead:=False;
      end;
    Check(not Dead,'Respawn regeneration requires movement or stance input');
  finally S.Free;L.Free;C.Free;end;
end;

procedure DeathStoreTests;
var L:TB1008LootStore;O:TObject;P:TB1008Progress;I:Integer;
  FileName:string;G:TGUID;DB:TFDConnection;Failed:Boolean;
begin
  Check((TB1008Balance.DeathEXPLoss(1)=2) and (TB1008Balance.DeathEXPLoss(2)=9),'Death loss rounding');
  CreateGUID(G);FileName:=TPath.Combine(TPath.GetTempPath,'KarosDeath-'+GUIDToString(G)+'.sqlite3');
  O:=TObject.Create;L:=nil;DB:=nil;
  try
    L:=TB1008LootStore.Create(FileName,FixtureRates);L.Acquire(O,Preview);
    P:=L.RecordDeath(O,'zero');Check((P.TotalEXP=0) and L.PendingDeath(O),'Zero EXP death floor');
    L.CompleteRespawn(O);
    for I:=1 to 7 do P:=L.RecordMobEXP(O,'seed/'+IntToStr(I),8,1);
    P:=L.RecordDeath(O,'one');Check((P.TotalEXP=47) and (P.Level=1),'Level-down subtraction');
    P:=L.RecordDeath(O,'one');Check(P.TotalEXP=47,'Duplicate receipt charged');
    P:=L.RecordDeath(O,'other');Check(P.TotalEXP=47,'Pending death charged twice');
    FreeAndNil(L);L:=TB1008LootStore.Create(FileName,FixtureRates);L.Acquire(O,Preview);
    Check(L.PendingDeath(O) and (L.Progress(O).TotalEXP=47),'Death persistence');
    L.CompleteRespawn(O);L.CompleteRespawn(O);
    P:=L.RecordDeath(O,'one');Check((P.TotalEXP=47) and not L.PendingDeath(O),'Old receipt reopened death');
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;
    DB.Params.Values['DriverID']:='SQLite';DB.Params.Values['Database']:=FileName;DB.Connected:=True;
    DB.ExecSQL('CREATE TRIGGER fail_death BEFORE INSERT ON death_state BEGIN SELECT RAISE(ABORT,''test''); END');
    Failed:=False;try L.RecordDeath(O,'two');except on E:Exception do Failed:=True;end;
    Check(Failed and (L.Progress(O).TotalEXP=47) and not L.PendingDeath(O),'Death transaction did not roll back');
    DB.ExecSQL('DROP TRIGGER fail_death');
    P:=L.RecordDeath(O,'two');Check(P.TotalEXP=45,'Death retry after rollback');
    L.CompleteRespawn(O);FreeAndNil(L);L:=TB1008LootStore.Create(FileName,FixtureRates);L.Acquire(O,Preview);
    Check(not L.PendingDeath(O) and (L.Progress(O).TotalEXP=45),'Respawn completion persistence');
  finally
    DB.Free;L.Free;O.Free;
    if FileExists(FileName) then TFile.Delete(FileName);
    if FileExists(FileName+'-wal') then TFile.Delete(FileName+'-wal');
    if FileExists(FileName+'-shm') then TFile.Delete(FileName+'-shm');
  end;
end;

procedure FlettaTests;
var F:TB1008Fletta;P,Before:TBytes;XP:TB1008Progress;I,J,V:Integer;
  L:TB1008LootStore;O:TObject;FileName:string;G:TGUID;DB:TFDConnection;Failed:Boolean;
begin
  Check(TB1008Fletta.KillGain(1,1)=1150,'Equal level Fletta');
  Check(TB1008Fletta.KillGain(2,1)=1050,'Near level interpolation');
  Check(TB1008Fletta.KillGain(3,1)=950,'Two-level Fletta anchor');
  Check(TB1008Fletta.KillGain(6,1)=650,'Five-level Fletta anchor');
  Check(TB1008Fletta.KillGain(9,1)=350,'Eight-level Fletta anchor');
  Check((TB1008Fletta.KillGain(11,1)=150) and (TB1008Fletta.KillGain(20,1)=150),'Low mob clamp');
  Check(TB1008Fletta.KillGain(1,20)=1150,'Invented stronger-mob bonus');
  F.Total:=0;for I:=1 to 10 do F.Add(1050);
  Check((F.Points=1) and (F.Progress=500),'FP conversion lost remainder');
  XP.TotalEXP:=119;
  for I:=0 to 1 do begin
    if I=0 then P:=TB1008ProgressWire.BuildHeroGage(5,100,50,XP)
    else begin
      P:=TB1008World.BuildCharacterInfoProbe(Preview,5);
      TB1008ProgressWire.ApplyCharacterInfo(P,XP);
    end;
    Before:=Copy(P);F.Apply(P,XP.Level);
    if I=0 then V:=$31 else V:=$3A;
    for J:=0 to High(P) do
      if (J<V) or (J>=V+12) then Check(P[J]=Before[J],'Fletta overwrote other gage fields');
    Move(P[V],J,4);Check(J=500,'Fletta progress offset');
    Move(P[V+4],J,4);Check(J=10000,'Fletta zero denominator');
    Move(P[V+8],J,4);Check(J=1,'Fletta FP offset');
    F.Total:=TB1008Fletta.LevelCapacity(XP.Level);F.Apply(P,XP.Level);
    Move(P[V],J,4);Check(J=10000,'Full Fletta capacity must display 100 percent');
    Move(P[V+8],J,4);Check(J=XP.Level,'Full bar added a spendable FP');
    Check(F.Progress=0,'Display mutated fractional Fletta balance');
    F.Total:=F.Total-10000;F.Apply(P,XP.Level);
    Move(P[V],J,4);Check(J=0,'Spending did not clear full Fletta bar');
    F.Total:=TB1008Fletta.LevelCapacity(XP.Level);F.Apply(P,XP.Level+1);
    Move(P[V],J,4);Check(J=0,'Level increase kept the lower-level cap display');
    F.Total:=10500;
  end;
  F.Total:=B1008FlettaMaxTotal-1;F.Add(1150);Check(F.Total=B1008FlettaMaxTotal,'Fletta counter overflow');
  CreateGUID(G);FileName:=TPath.Combine(TPath.GetTempPath,'KarosFletta-'+GUIDToString(G)+'.sqlite3');
  O:=TObject.Create;L:=nil;DB:=nil;
  try
    L:=TB1008LootStore.Create(FileName,FixtureRates);L.Acquire(O,Preview);
    // Fixed EXP isolates Fletta boundaries from the live species reward table.
    for I:=1 to 6 do XP:=L.RecordMobEXP(O,'seed/'+IntToStr(I),10,1);
    Check(L.Fletta(O).Total=6800,'Level-up kill used new level');
    XP:=L.RecordMobEXP(O,'seed/6',10,1);Check(L.Fletta(O).Total=6800,'Replay awarded Fletta');
    XP:=L.RecordQuestEXP(O,19003003);Check(L.Fletta(O).Total=6800,'Quest awarded unconfirmed Fletta');
    for I:=7 to 10 do XP:=L.RecordMobEXP(O,'seed/'+IntToStr(I),10,1);
    F:=L.Fletta(O);Check((F.Points=1) and (F.Progress=1000),'Persistent FP conversion');
    XP:=L.RecordDeath(O,'death');Check(L.Fletta(O).Total=11000,'Death introduced Fletta penalty');L.CompleteRespawn(O);
    FreeAndNil(L);L:=TB1008LootStore.Create(FileName,FixtureRates);L.Acquire(O,Preview);
    Check(L.Fletta(O).Total=11000,'Fletta persistence');
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;
    DB.Params.Values['DriverID']:='SQLite';DB.Params.Values['Database']:=FileName;DB.Connected:=True;
    DB.ExecSQL('CREATE TRIGGER fail_fletta BEFORE INSERT ON exp_receipts BEGIN SELECT RAISE(ABORT,''test''); END');
    XP:=L.Progress(O);Failed:=False;
    try L.RecordMobEXP(O,'rollback',10,1);except on E:Exception do Failed:=True;end;
    Check(Failed and (L.Progress(O).TotalEXP=XP.TotalEXP) and (L.Fletta(O).Total=11000),'Fletta/EXP transaction split');
    DB.ExecSQL('DROP TRIGGER fail_fletta');XP:=L.RecordMobEXP(O,'rollback',10,1);
    Check(L.Fletta(O).Total=12050,'Retry lost Fletta');
  finally
    DB.Free;L.Free;O.Free;
    if FileExists(FileName) then TFile.Delete(FileName);
    if FileExists(FileName+'-wal') then TFile.Delete(FileName+'-wal');
    if FileExists(FileName+'-shm') then TFile.Delete(FileName+'-shm');
  end;
end;

procedure RegenerationTests;
var R:TB1008Regeneration;HP,MP:Integer;
  function Tick(T:UInt64;Blocked:Boolean=False):Boolean;
  begin Result:=R.Poll(T,Blocked,4000,13,1,210,63,HP,MP);end;
begin
  R:=Default(TB1008Regeneration);HP:=100;MP:=50;
  Check(not Tick(0) and not Tick(5000),'Unknown stance healed');
  Check(R.ObserveState($FFFFFFFE,0),'Initial peaceful state');
  Check(not Tick(6000) and not Tick(9999),'Regen fired early');
  Check(Tick(10000) and (HP=113) and (MP=51),'Regen quantum');
  Check(Tick(30000) and (HP=126),'Delayed poll caused catch-up healing');
  Check(not R.ObserveState($FFFFFFFE,1),'Duplicate state accepted');
  Check(R.ObserveState($FFFFFFFF,1),'Combat stance update');
  Check(not Tick(40000),'Combat stance healed');
  Check(R.ObserveState(0,0),'Timestamp wrap rejected');
  Check(not R.ObserveState($FFFFFFFF,1),'Stale state accepted');
  Check(not Tick(41000,True) and not Tick(45000,True),'Engaged monster allowed healing');
  Check(not Tick(46000) and Tick(50000),'Combat exit grace');
  R.EnterCombat;Check(not Tick(55000),'Attack failed to block regeneration');
  R.ObserveState(1,0);HP:=205;MP:=63;
  Check(not Tick(56000) and Tick(60000) and (HP=210) and (MP=63),'Regen clamp');
  Check(not Tick(64000),'Full bars sent redundant update');
  HP:=0;Check(not Tick(70000) and not Tick(74000) and (HP=0),'Regen revived dead player');
  HP:=100;R.ObserveState(2,2);Check(not Tick(80000),'Unconfirmed state 2 healed');
  R.ObserveState(3,0);Check(not Tick(81000) and not Tick(10) and not Tick(4009) and Tick(4010),'Clock rollback');
end;

procedure VitalsTests;
var P,Original:TBytes;Progress:TB1008Progress;I,V:Integer;
begin
  Check((TB1008Balance.BladerMaxHP(1)=185) and (TB1008Balance.BladerMaxMP(1)=119),'Blader backward extrapolation');
  Check((TB1008Balance.BladerMaxHP(2)=236) and (TB1008Balance.BladerMaxMP(2)=127),'Blader anchor');
  Check((TB1008Balance.BladerMaxHP(20)=1162) and (TB1008Balance.BladerMaxMP(20)=271),'Blader phase cap');
  Check((TB1008Balance.BladerMaxHP(30)=1676) and (TB1008Balance.BladerMaxMP(30)=351),'Blader level 30');
  Check((TB1008Balance.ClassMaxHP(300,1)=105) and (TB1008Balance.ClassMaxMP(300,1)=83),'Rogue backward extrapolation');
  Check((TB1008Balance.ClassMaxHP(300,4)=259) and (TB1008Balance.ClassMaxMP(300,4)=107),'Rogue anchor');
  Check((TB1008Balance.ClassMaxHP(500,1)=102) and (TB1008Balance.ClassMaxMP(500,1)=121),'Archer stock percentages');
  for I:=1 to TB1008Balance.LevelCap do begin
    Check(TB1008Balance.ClassMaxHP(500,I)=(TB1008Balance.ClassMaxHP(300,I)*97+50) div 100,'Archer HP reference level');
    Check(TB1008Balance.ClassMaxMP(500,I)=(TB1008Balance.ClassMaxMP(100,I)*102+50) div 100,'Archer MP reference level');
    Progress.TotalEXP:=0;
    P:=TB1008ProgressWire.BuildHeroGage(1,TB1008Balance.ClassMaxHP(500,I),
      TB1008Balance.ClassMaxMP(500,I),Progress,TB1008Balance.ClassMaxHP(500,I),TB1008Balance.ClassMaxMP(500,I));
    Move(P[19],V,4);Check(V=TB1008Balance.ClassMaxMP(500,I),'Gage rejected MP above diagnostic maximum');
  end;
  Progress.TotalEXP:=48;
  for I:=0 to 1 do begin
    if I=0 then P:=TB1008CombatWire.BuildPlayerGageProbe(123,180,50,2)
    else P:=TB1008ProgressWire.BuildHeroGage(123,180,50,Progress);
    Original:=Copy(P);
    TB1008ProgressWire.ApplyVitals(P,180,50,210,63);
    Move(P[11],V,4);Check(V=180,'HP changed during vitals patch');
    Move(P[15],V,4);Check(V=210,'Wrong max HP');
    Move(P[23],V,4);Check(V=63,'Wrong max MP');
    Check(CompareMem(@P[27],@Original[27],Length(P)-27),'Vitals altered speed, level or EXP');
  end;
end;

procedure LevelCombatGrowthTests;
const Levels:array[0..4] of Word=(1,5,10,20,30);
  Attacks:array[0..4] of Integer=(16,28,43,73,103);
  Magics:array[0..4] of Integer=(8,12,17,27,37);
  Crits:array[0..4] of Integer=(520,600,700,900,1100);
var I,LowDamage,HighDamage:Integer;A:TB1008BaseAttributes;P:TBytes;X:Single;
  F:TB1008FlettaAttributes;Bad:Boolean;
begin
  for I:=0 to High(Levels) do begin
    A:=TB1008Balance.BaseAttributes(100,Levels[I]);
    Check((A.PhysicalAttack=Attacks[I]) and (A.MagicalAttack=Magics[I]) and
      (A.CriticalBasisPoints=Crits[I]),'Level growth anchor');
    Check((A.AttackRatingBonus=2*(Levels[I]-1)) and
      (A.DefenseRatingBonus=Levels[I]-1),'Level rating anchor');
    Check((A.Strength=10) and (A.PhysicalDefense=21),'Growth changed unrelated base stats');
    P:=TB1008ProgressWire.BuildParameters(1,100,Levels[I]);
    Move(P[$5A],X,4);Check(X=Attacks[I],'Physical attack wire growth');
    Move(P[$76],X,4);Check(X=Magics[I],'Magical attack wire growth');
    Move(P[$AA],X,4);Check(Abs(X-Crits[I]/100)<0.001,'Critical wire growth');
    TB1008Equipment.PhysicalAttack(100,TB1008Equipment.Starter(100),LowDamage,HighDamage,Levels[I]);
    Check((LowDamage=Attacks[I]+2) and (HighDamage=Attacks[I]+8),'Weapon must add to current level base once');
    F:=Default(TB1008FlettaAttributes);F.FireInvested:=1600;
    F.PhysicalAttack(LowDamage,HighDamage,A.PhysicalAttack);
    Check((LowDamage=Attacks[I]+2+(Attacks[I]*30+50) div 100) and
      (HighDamage=Attacks[I]+8+(Attacks[I]*30+50) div 100),'Fire must use current level base');
  end;
  A:=TB1008Balance.BaseAttributes(100,1);
  Check((A.PhysicalAttack=16) and (A.CriticalBasisPoints=520) and
    (A.DefenseRatingBonus=0),'Derived growth accumulated across calls');
  Bad:=False;try TB1008Balance.BaseAttributes(100,0);except on E:Exception do Bad:=True;end;
  Check(Bad,'Zero growth level accepted');
  Bad:=False;try TB1008Balance.BaseAttributes(100,TB1008Balance.LevelCap+1);except on E:Exception do Bad:=True;end;
  Check(Bad,'Growth beyond phase cap accepted');
end;

procedure BaseAttributesWireTests;
var P,Before:TBytes;I:Integer;Failed,ChangedField:Boolean;
begin
  SetLength(P,$4B3);FillChar(P[0],Length(P),$55);P[0]:=2;P[1]:=5;
  Before:=Copy(P);TB1008ProgressWire.ApplyBaseAttributes(P,500);
  for I:=0 to High(P) do begin
    ChangedField:=((I>=$375) and (I<$37F)) or ((I>=$413) and (I<$417));
    if not ChangedField then Check(P[I]=Before[I],'Attributes changed unrelated wire field');
  end;
  Before:=Copy(P);Failed:=False;
  try TB1008ProgressWire.ApplyBaseAttributes(P,999);except on E:Exception do Failed:=True;end;
  Check(Failed and CompareMem(@P[0],@Before[0],Length(P)),'Unsupported class mutated packet');
  SetLength(P,4);P[0]:=2;P[1]:=5;Failed:=False;
  try TB1008ProgressWire.ApplyBaseAttributes(P,100);except on E:Exception do Failed:=True;end;
  Check(Failed,'Truncated attributes packet accepted');
end;

procedure ClassVitalsSessionTests;
const Classes:array[0..2] of Word=(100,300,500);
  Expected:array[0..2,0..4] of Word=((10,7,10,7,6),(7,11,6,8,8),(6,12,6,8,8));
  Critical:array[0..2] of Single=(5.2,7.1,8.0);
var C:TB1008CharacterStore;S:TEmulatorSession;H,P:TBytes;R:TB1008Replies;
  I,J,V:Integer;ClassID,W:Word;X:Single;
begin
  LevelCombatGrowthTests;BaseAttributesWireTests;
  for I:=0 to High(Classes) do begin
    ClassID:=Classes[I];C:=TB1008CharacterStore.Create;S:=nil;
    try
      H:=TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
        72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);
      Move(ClassID,H[6],2);C.CreateCharacter(H,P);
      S:=TEmulatorSession.Create(blMapLoadingProbe,C);
      S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),R);
      S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),R);
      Move(R[0][$14],V,4);Check(V=TB1008Balance.ClassMaxHP(ClassID,1),'Class login HP used diagnostic fallback');
      Move(R[0][$1C],V,4);Check(V=TB1008Balance.ClassMaxMP(ClassID,1),'Class login MP used diagnostic fallback');
      for J:=0 to 4 do begin
        Move(R[0][$375+2*J],W,2);Check(W=Expected[I,J],'Class base attribute field/order');
      end;
      Move(R[0][$413],X,4);Check(Abs(X-Critical[I])<0.001,'Class critical percentage');
      Move(R[0][$423],X,4);Check(X=TB1008Balance.ClassMaxHP(ClassID,1),'Character window HP');
      Move(R[0][$39B],X,4);Check(X=TB1008Balance.ClassMaxMP(ClassID,1),'Character window MP');
      Move(R[0][$393],X,4);Check(X=TB1008Balance.BaseAttributes(ClassID).RegenHP,'Character window regen HP');
      Move(R[0][$39F],X,4);Check(X=TB1008Balance.BaseAttributes(ClassID).RegenMP,'Character window regen MP');
      Move(R[0][$3A7],X,4);Check(X=B1008PlayerMeleeReach,'Login omitted client ordinary melee reach');
      Move(R[0][$3C3],X,4);Check(X=TB1008Balance.BaseAttributes(ClassID).PhysicalAttack,'Character window attack');
      Move(R[0][$3CF],X,4);Check(X=TB1008Balance.BaseAttributes(ClassID).PhysicalDefense,'Character window defense');
      Move(R[0][$3DF],X,4);Check(X=TB1008Balance.BaseAttributes(ClassID).MagicalAttack,'Character window magic attack');
      Move(R[0][$3E7],X,4);Check(X=TB1008Balance.BaseAttributes(ClassID).MagicalDefense,'Character window magic defense');
      P:=TB1008ProgressWire.BuildParameters($12345678,ClassID,1);
      Check((Length(P)=$14A) and (P[0]=8) and (P[1]=2) and
        (TB1008Wire.ReadBE32(P,2)=$12345678) and (TB1008Wire.ReadBE32(P,6)=1),'Parameter packet header');
      Check(CompareMem(@P[10],@R[0][$373],$140),'Initial/update parameter blocks differ');
      Move(P[$3E],X,4);Check(X=B1008PlayerMeleeReach,'Parameters erased client ordinary melee reach');
      P:=TB1008ProgressWire.BuildParameters(1,ClassID,TB1008Balance.LevelCap);
      Move(P[$3E],X,4);Check(X=B1008PlayerMeleeReach,'Level update erased melee reach');
      Move(P[$BA],X,4);Check(X=TB1008Balance.ClassMaxHP(ClassID,TB1008Balance.LevelCap),'Max level parameter HP');
      Move(P[$32],X,4);Check(X=TB1008Balance.ClassMaxMP(ClassID,TB1008Balance.LevelCap),'Max level parameter MP');
      P:=TBytes.Create(4,0,0,0,0,2,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
      X:=8669.776367;Move(X,P[11],4);X:=6668.010254;Move(X,P[15],4);X:=604.350342;Move(X,P[19],4);
      S.HandlePacket(P,R);
      Move(R[0][28],V,4);Check(V=TB1008Balance.ClassMaxHP(ClassID,1),'Class appearance HP mismatch');
      Move(R[0][36],V,4);Check(V=TB1008Balance.ClassMaxMP(ClassID,1),'Class appearance MP mismatch');
    finally S.Free;C.Free;end;
  end;
end;

procedure PotionEffectTests;
var HP,MP:Integer;Failed:Boolean;
begin
  HP:=100;MP:=5;TB1008PotionEffect.Apply(54006,HP,MP,190,60);
  Check((HP=120) and (MP=5),'Healing potion amount or MP mutation');
  TB1008PotionEffect.Apply(54206,HP,MP,190,60);Check((HP=120) and (MP=15),'Mana potion amount');
  HP:=185;MP:=55;TB1008PotionEffect.Apply(54006,HP,MP,190,60);TB1008PotionEffect.Apply(54206,HP,MP,190,60);
  Check((HP=190) and (MP=60),'Potion overfill');
  TB1008PotionEffect.Apply(54006,HP,MP,190,60);Check(HP=190,'Full HP overflow');
  HP:=0;Failed:=False;try TB1008PotionEffect.Apply(54006,HP,MP,190,60);except on E:Exception do Failed:=True;end;
  Check(Failed and (HP=0),'Potion revived dead player');
end;

procedure ShortCombatTests;
var E:TB1008SpiderEncounter; R:TB1008AttackStart; Reason:string; I,Damage:Integer; P:TBytes;
begin
  Check(TB1008Balance.PlayerDamage=22,'Normal hit profile');
  Check(TB1008Balance.CriticalDamagePercent=120,'Working critical multiplier from user screenshots');
  E:=TB1008SpiderEncounter.Create(54,TB1008Balance.PlayerDamage);
  try
    R:=Default(TB1008AttackStart);R.ActorID:=1;R.TargetKind:=1;R.TargetID:=120;
    R.X:=8669.776367;R.Z:=6668.010254;R.Y:=604.350342;
    R.TargetX:=R.X;R.TargetZ:=R.Z;R.TargetY:=R.Y;
    for I:=1 to 3 do begin
      R.Timestamp:=I;
      Check(E.TryHit(R,R.X,R.Z,R.Y,UInt64(I)*1000,Reason),'Balanced hit rejected');
      if I<3 then Check(E.HP=54-I*22,'Balanced HP subtraction') else Check(E.HP=0,'Third hit must kill');
      P:=TB1008CombatWire.BuildSpiderDamageProbe(R,R.X,R.Z,R.Y,TB1008Balance.PlayerDamage);
      Move(P[23],Damage,4);Check(Damage=22,'Wire damage differs from server damage');
      Check(not E.TryHit(R,R.X,R.Z,R.Y,UInt64(I)*1000,Reason),'Duplicate hit accepted');
    end;
    Check(E.TryDespawn(5500),'Balanced corpse cleanup');
    Check(E.TryRespawn(20500,15000) and (E.HP=54),'Balanced respawn HP');
    R.Timestamp:=4;Check(E.TryHit(R,R.X,R.Z,R.Y,21000,Reason) and (E.HP=32),'Damage lost after respawn');
  finally E.Free;end;
end;

procedure ProgressTests;
var L: TB1008LootStore; O: TObject; P: TB1008Progress; I: Integer; Bad: Boolean; Sum: Int64;
begin
  Check((TB1008Balance.SpiderEXP=16) and (TB1008Balance.Threshold(1)=48),'Profile anchors');
  O:=TObject.Create; L:=TB1008LootStore.Create('',FixtureRates);
  try
    L.Acquire(O,Preview);
    for I:=1 to 4 do P:=L.RecordMobEXP(O,'k'+IntToStr(I),10,1);
    Check((P.Level=1) and (P.CurrentEXP=40),'Four spiders');
    P:=L.RecordQuestEXP(O,19003003);
    Check((P.Level=2) and (P.CurrentEXP=16) and (P.NextEXP=216),'First quest overflow');
    P:=L.RecordQuestEXP(O,19003003); Check(P.TotalEXP=64,'Duplicate quest EXP');
    P:=L.RecordMobEXP(O,'k1',10,1); Check(P.TotalEXP=64,'Duplicate kill after quest');
    Bad:=False;try L.RecordQuestEXP(O,999);except on E:Exception do Bad:=True;end;
    Check(Bad and (L.Progress(O).TotalEXP=64),'Unknown quest');
    Sum:=0;
    for I:=1 to TB1008Balance.LevelCap-1 do begin
      P.TotalEXP:=Sum; Check(P.Level=I,'Level lower boundary');
      P.TotalEXP:=Sum+TB1008Balance.Threshold(I)-1;
      Check((P.Level=I) and (P.CurrentEXP=P.NextEXP-1),'Level upper boundary');
      Inc(Sum,TB1008Balance.Threshold(I)); P.TotalEXP:=Sum;
      Check((P.Level=I+1) and (P.CurrentEXP=0),'Multi-level cumulative boundary');
    end;
    Check((P.Level=TB1008Balance.LevelCap) and (P.NextEXP>0),'Cap HUD denominator');
    P.TotalEXP:=-1; Bad:=False;try P.Validate;except on E:Exception do Bad:=True;end;Check(Bad,'Negative EXP');
    P.TotalEXP:=TB1008Balance.MaxEXP+1;Bad:=False;try P.Validate;except on E:Exception do Bad:=True;end;Check(Bad,'Cap overflow');
  finally L.Free; O.Free; end;
end;

procedure QuestSessionTests;
var L:TB1008LootStore;Q:TB1008QuestStore;C:TB1008CharacterStore;S:TEmulatorSession;
  H,P,Reward:TBytes;Replies:TB1008Replies;I,Mode,V:Integer;X:Single;Tick:UInt64;Found:Boolean;
begin
  // Mode 0: normal completion. Mode 1: marker committed but EXP write interrupted.
  for Mode:=0 to 1 do begin
    L:=TB1008LootStore.Create('',FixtureRates);Q:=TB1008QuestStore.Create;C:=TB1008CharacterStore.Create;S:=nil;
    try
      H:=TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
        72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0);
      C.CreateCharacter(H,P);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,Q,nil,L);
      S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),Replies);
      S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),Replies);
      Move(Replies[0][$14],V,4);Check(V=185,'Session CharInfo HP anchor');
      Move(Replies[0][$20],V,4);Check(V=119,'Session CharInfo max MP anchor');
      P:=TBytes.Create(4,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
      X:=8669.776367;Move(X,P[11],4);X:=6668.010254;Move(X,P[15],4);X:=604.350342;Move(X,P[19],4);
      S.HandlePacket(P,Replies);
      Move(Replies[0][28],V,4);Check(V=185,'Self appearance HP mismatch');
      Q.Accept(S);for I:=1 to 5 do begin Q.RecordSpiderKill(S);L.RecordMobEXP(S,'kill'+IntToStr(I),8,1);end;
      if Mode=1 then Q.Complete(S);
      Reward:=TBytes.Create(9,1,1,2,3,4,0,0,0,1,1,$21,$F6,$7B,$FF,$FF,$FF,$FF,0,0,0,$2B);
      S.HandlePacket(Reward,Replies);
      Check(Q.Rewarded(S) and (L.Progress(S).TotalEXP=64),'Quest session completion/recovery');
      Check((Replies[High(Replies)][0]=8) and (Replies[High(Replies)][1]=1),'Quest EXP packet missing');
      Move(Replies[High(Replies)][11],V,4);Check(V=236,'Quest level-up did not refill HP immediately');
      Move(Replies[High(Replies)][19],V,4);Check(V=127,'Quest level-up did not refill MP immediately');
      S.HandlePacket(Reward,Replies);Check(L.Progress(S).TotalEXP=64,'Duplicate Done credited EXP');
      if Mode=0 then begin
        S.HandlePacket(TBytes.Create(3,2,0,0,0,10,0,0,0,1,0,0),Replies);
        Tick:=GetTickCount64+10000;S.PollWorld(Tick,Replies);
        Found:=False;
        for I:=0 to High(Replies) do if (Replies[I][0]=8) and (Replies[I][1]=2) then begin
          Move(Replies[I][$BA],X,4);Check(X=236,'Level-up parameter HP');
          Move(Replies[I][$32],X,4);Check(X=127,'Level-up parameter MP');Found:=True;
          Move(Replies[I][$5A],X,4);Check(X=19,'Level-up physical attack refresh');
          Move(Replies[I][$76],X,4);Check(X=9,'Level-up magical attack refresh');
          Move(Replies[I][$AA],X,4);Check(Abs(X-5.4)<0.001,'Level-up critical refresh');
        end;
        Check(Found,'Level-up must refresh character window');
        S.PollWorld(Tick+TB1008Balance.RegenIntervalMS,Replies);
        for I:=0 to High(Replies) do Check(not ((Replies[I][0]=8) and (Replies[I][1]=2)),'Repeated unchanged parameters');
        Found:=False;
        for I:=0 to High(Replies) do
          if (Replies[I][0]=8) and (Replies[I][1]=0) and (Replies[I][6]=0) then begin
            Move(Replies[I][11],V,4);Check(V=236,'Full HP changed after level-up');
            Move(Replies[I][15],V,4);Check(V=236,'Session regen max HP');Found:=True;
          end;
        Check(not Found and (L.Progress(S).TotalEXP=64),'Full vitals emitted unnecessary regen');
        P:=TBytes.Create(6,2,0,0,0,1,0,0,0,1,1,0,0,0,$D2,$F6,0,0,0,0,1);
        S.HandlePacket(P,Replies);
        Check((Length(Replies)=3) and (Replies[2][0]=8) and (Replies[2][1]=1),'Potion vitals reply missing');
        Check((L.Item(S,54006).Amount=2) and (L.Progress(S).TotalEXP=64),'Potion count or EXP changed incorrectly');
        Move(Replies[2][11],V,4);Check(V=236,'Full-HP potion overflowed');
        S.HandlePacket(P,Replies);Check((Length(Replies)=0) and (L.Item(S,54006).Amount=2),'Duplicate use consumed twice');
      end;
      FreeAndNil(S);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,Q,nil,L);
      S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),Replies);
      S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),Replies);
      Check((Replies[0][$30]=2) and (Replies[0][$46]=16),'Quest reconnect changed EXP');
      Move(Replies[0][$18],V,4);Check(V=236,'Reconnect max HP mismatch');
      Move(Replies[0][$20],V,4);Check(V=127,'Reconnect max MP mismatch');
      Move(Replies[0][$3C3],X,4);Check(X=19,'Reconnect repeated/lost attack growth');
      Move(Replies[0][$413],X,4);Check(Abs(X-5.4)<0.001,'Reconnect repeated/lost critical growth');
    finally S.Free;C.Free;Q.Free;L.Free;end;
  end;
end;

procedure ProfessionGrowthTests;
var A,B:TB1008BaseAttributes;C:Word;
begin
  for C in [110,120] do begin
    A:=TB1008Balance.BaseAttributes(100,45);
    B:=TB1008Balance.ProfessionAttributes(100,C,0,45);
    Check((B.PhysicalAttack=A.PhysicalAttack+12) and (B.MagicalAttack=A.MagicalAttack+4) and
      (B.CriticalBasisPoints=A.CriticalBasisPoints+80),'First profession attack/critical growth');
    B:=TB1008Balance.ProfessionAttributes(100,C,1,45);
    Check((B.PhysicalAttack=A.PhysicalAttack+27) and (B.MagicalAttack=A.MagicalAttack+9) and
      (B.CriticalBasisPoints=A.CriticalBasisPoints+180),'Rank growth');
    Check(TB1008Balance.ProfessionMaxHP(100,C,11)=TB1008Balance.ClassMaxHP(100,11)+456,'HP delta at anchor');
    Check(TB1008Balance.ProfessionMaxMP(100,C,11)=TB1008Balance.ClassMaxMP(100,11)+104,'MP delta at anchor');
    Check((TB1008Balance.ProfessionMaxHP(100,C,45)=3144) and
      (TB1008Balance.ProfessionMaxMP(100,C,45)=643),'Profession45 vitals');
    Check(TB1008Balance.ProfessionMaxHP(100,C,10)=1096,'Negative anchor rounding');
  end;
  Check(TB1008Balance.ProfessionMaxHP(100,100,45)=TB1008Balance.ClassMaxHP(100,45),'Base class received profession bonus');
end;

procedure MigrationTests;
var Dir,FileName: string; G:TGUID; DB:TFDConnection; L:TB1008LootStore; O:TObject;
  P:TB1008Progress; N:Cardinal; Failed:Boolean;
begin
  CreateGUID(G);Dir:=TPath.Combine(TPath.GetTempPath,'KarosBalance-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir);FileName:=TPath.Combine(Dir,'hero.sqlite3');
  DB:=nil;L:=nil;O:=TObject.Create;
  try
    L:=TB1008LootStore.Create(FileName,FixtureRates);L.Acquire(O,Preview);L.CollectItem(O,'carat',999999,135,N);FreeAndNil(L);
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;
    DB.Params.Values['DriverID']:='SQLite';DB.Params.Values['Database']:=FileName;DB.Connected:=True;
    RestorePreDropSchema(DB);
    // Recreate the real legacy constraints, not a version-number-only downgrade.
    DB.ExecSQL('DROP TABLE progression');DB.ExecSQL('DROP TABLE exp_receipts');
    DB.ExecSQL('ALTER TABLE progression_v5_backup RENAME TO progression');
    DB.ExecSQL('ALTER TABLE exp_receipts_v5_backup RENAME TO exp_receipts');
    DB.ExecSQL('INSERT INTO progression VALUES(1,100)');
    DB.ExecSQL('INSERT INTO exp_receipts VALUES(''legacykill'',10)');
    DB.ExecSQL('DROP VIEW wallet');DB.ExecSQL('DELETE FROM inventory_v9_backup');
    DB.ExecSQL('DROP TABLE inventory_v10_backup');
    DB.ExecSQL('INSERT INTO inventory_v9_backup SELECT * FROM inventory');DB.ExecSQL('DROP TABLE inventory');
    DB.ExecSQL('ALTER TABLE inventory_v9_backup RENAME TO inventory');
    DB.ExecSQL('CREATE VIEW wallet AS SELECT 1 AS id,amount FROM inventory WHERE item_id=999999');
    DB.ExecSQL('DROP TABLE fletta_attributes_v12_backup');DB.ExecSQL('DROP TABLE fletta_investments_v12_backup');
    DB.ExecSQL('PRAGMA user_version=5');FreeAndNil(DB);
    L:=TB1008LootStore.Create(FileName,FixtureRates);L.Acquire(O,Preview);P:=L.Progress(O);
    Check((P.TotalEXP=48) and (P.Level=2) and (P.CurrentEXP=0),'Migration must preserve level 2');
    Check(L.Balance(O)=135,'Migration changed inventory');
    P:=L.RecordMobEXP(O,'legacykill',10,1);Check(P.TotalEXP=48,'Legacy receipt replay');
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;
    DB.Params.Values['DriverID']:='SQLite';DB.Params.Values['Database']:=FileName;DB.Connected:=True;
    Check(Int64(DB.ExecSQLScalar('SELECT total_exp FROM progression_v5_backup'))=100,'Legacy backup missing');
    DB.ExecSQL('CREATE TRIGGER fail_exp BEFORE INSERT ON exp_receipts BEGIN SELECT RAISE(ABORT,''test''); END');
    Failed:=False;try L.RecordQuestEXP(O,19003003);except on E:Exception do Failed:=True;end;
    Check(Failed and (L.Progress(O).TotalEXP=48),'Quest reward must roll back atomically');
    DB.ExecSQL('DROP TRIGGER fail_exp');P:=L.RecordQuestEXP(O,19003003);Check(P.TotalEXP=72,'Retry quest reward');
    FreeAndNil(L);L:=TB1008LootStore.Create(FileName,FixtureRates);L.Acquire(O,Preview);
    P:=L.RecordQuestEXP(O,19003003);Check(P.TotalEXP=72,'Reopen repeated migration or reward');
    DB.ExecSQL('UPDATE progression SET total_exp=:n',[TB1008Balance.MaxEXP-3]);
    P:=L.RecordMobEXP(O,'capkill',10,1);Check(P.TotalEXP=TB1008Balance.MaxEXP,'Final reward clamp');
    P:=L.RecordMobEXP(O,'capped',10,1);Check((P.Level=TB1008Balance.LevelCap) and (P.CurrentEXP=0),'EXP beyond cap');
  finally
    DB.Free;L.Free;O.Free;
    if FileExists(FileName) then TFile.Delete(FileName);
    if FileExists(FileName+'-wal') then TFile.Delete(FileName+'-wal');
    if FileExists(FileName+'-shm') then TFile.Delete(FileName+'-shm');
    TDirectory.Delete(Dir,False);
  end;
end;
procedure ProfessionBalanceTests;
begin
  Check(Abs(TB1008Balance.WeaponAutoAttackSpeed(1)-1.1)<0.0001,'Sword weapon speed');
  Check(Abs(TB1008Balance.WeaponAutoAttackSpeed(2)-0.9)<0.0001,'Polearm weapon speed');
  Check(TB1008Balance.WeaponAutoAttackSpeed(0)=1,'Unarmed speed');
  Check(TB1008Balance.WeaponAutoAttackSpeed(7)=1,'Other subtype speed');
  Check(TB1008Balance.ProfessionPhysicalAttack(110,85)=85,'Sword attack');
  Check(TB1008Balance.ProfessionPhysicalAttack(100,85)=85,'Unpromoted attack');
  Check(TB1008Balance.ProfessionPhysicalAttack(120,85)=102,'Polearm base attack');
  Check((TB1008Balance.ProfessionPhysicalAttack(120,14)=17) and
    (TB1008Balance.ProfessionPhysicalAttack(120,52)=62),'Polearm endpoint rounding');
  Check(TB1008Balance.ProfessionPhysicalDefense(120,199)=215,'Polearm total defense');
  Check(TB1008Balance.ProfessionPhysicalDefense(110,199)=199,'Sword defense');
end;

begin
  try ProfessionBalanceTests;ProfessionGrowthTests;ClassVitalsSessionTests;FlettaTests;DeathStoreTests;RespawnSessionTests(False);RespawnSessionTests(True);RegenerationTests;VitalsTests;PotionEffectTests;ShortCombatTests;ProgressTests;MigrationTests;QuestSessionTests;Writeln('PASS: three-class stock vitals and shared growth; Fletta anchors, carry, wire isolation, atomic EXP, persistence and replay; death penalty and level decrease; town reload; regeneration; potions; combat; progression');
  except on E:Exception do begin Writeln('FAIL: '+E.ClassName+': '+E.Message);ExitCode:=1;end;end;
end.
