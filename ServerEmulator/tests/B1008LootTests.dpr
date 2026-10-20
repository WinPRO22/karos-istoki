program B1008LootTests;
{$APPTYPE CONSOLE}
uses Emulator.Rates.B1008,System.SysUtils, System.IOUtils, System.Math, Winapi.Windows, FireDAC.Comp.Client,
  Emulator.Loot.B1008, Emulator.LootStore.B1008, Emulator.Inventory.B1008,
  Emulator.Protocol.B1008, Emulator.Character.B1008, Emulator.Session,
  Emulator.Login.B1008, Emulator.World.B1008, Emulator.Progression.B1008,
  Emulator.Combat.B1008, Emulator.Balance.B1008, Emulator.DropProfile.B1008,
  Emulator.Items.B1008, Emulator.Equipment.B1008;

{$I B1008UnitRates.inc}

procedure Check(B: Boolean; const Msg: string);
begin if not B then raise Exception.Create(Msg); end;
{$I B1008MigrationFixture.inc}
procedure BE(var P: TBytes; O: Integer; V: Cardinal);
begin P[O]:=Byte(V shr 24); P[O+1]:=Byte(V shr 16); P[O+2]:=Byte(V shr 8); P[O+3]:=Byte(V); end;
procedure Float(var P: TBytes; O: Integer; V: Single);
begin Move(V,P[O],4); end;
function Hero: TBytes;
begin Result:=TBytes.Create(2,2,0,0,0,1,100,0,0,0,0,0,0,0,0,0,0,4,
  72,0,0,0,101,0,0,0,114,0,0,0,111,0,0,0,0,0,0,0); end;
function Preview: TBytes;
begin Result:=TB1008CharacterWire.BuildPreview(TB1008CharacterWire.ParseCreate(Hero),1); end;
function MoveTo(X: Single): TBytes;
begin
  Result:=TB1008World.BuildActorMovement(1,0,2,1,X,6668.010254,604.350342,
    X,6668.010254,604.350342,0);
end;
procedure Enter(S: TEmulatorSession; out Replies: TB1008Replies);
var P: TBytes;
begin
  S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),Replies);
  S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),Replies);
  P:=TBytes.Create(4,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
  Float(P,11,8669.776367); Float(P,15,6668.010254); Float(P,19,604.350342);
  S.HandlePacket(P,Replies);
end;
procedure Kill(S: TEmulatorSession; out Replies: TB1008Replies);
var A,D,P: TBytes; I,HP: Integer; Desc: string;
begin
  A:=nil; SetLength(A,53); A[0]:=5; BE(A,7,1); A[32]:=1; BE(A,33,120);
  Float(A,16,8669.776367); Float(A,20,6668.010254); Float(A,24,604.350342);
  Move(A[16],A[37],12);
  I:=0;HP:=B1008SpiderProbeHP;
  while HP>0 do
  begin
    Inc(I);Check(I<=(B1008SpiderProbeHP+15) div 16,'Variable attack never killed spider');
    BE(A,2,I*2); BE(A,12,I);
    Desc:=S.HandlePacket(A,Replies);
    Check(Pos('ATTACK START ACCEPTED',Desc)>0,Desc);
    D:=nil; SetLength(D,38); D[0]:=5; D[1]:=1; BE(D,2,I*2+1);
    Move(A[6],D[6],27); D[33]:=1; BE(D,34,120);
    Desc:=S.HandlePacket(D,Replies);
    Check(Pos('SPIDER HIT ACCEPTED',Desc)>0,Desc);
    Move(Replies[1][11],HP,4);
    if HP>0 then for P in Replies do
      Check(not ((P[0]=6) and (P[1]=4)),'Loot emitted before death');
  end;
end;
procedure WireTests;
var D: TB1008GroundDrop; R,Q: TB1008Pickup; P,B: TBytes; I: Integer; Failed: Boolean;
begin
  D:=Default(TB1008GroundDrop); D.ID:=$12345678; D.OwnerID:=1;
  D.ItemID:=B1008BoneFragmentID; D.Amount:=1; D.X:=1; D.Z:=2; D.Y:=3;
  P:=TB1008LootWire.BuildDrop(7,D);
  Check((Length(P)=74) and (P[0]=6) and (P[1]=4) and
    (TB1008Wire.ReadBE32(P,10)=D.ID) and (P[28]=$94) and (P[29]=$5F) and
    (P[30]=1) and (P[42]=1) and (P[65]=$3F) and (P[69]=$40) and (P[73]=$40),'Drop layout');
  R:=Default(TB1008Pickup); R.Timestamp:=7; R.CharacterID:=1;
  R.DropID:=D.ID; R.ItemID:=D.ItemID; R.Code:=$33;
  P:=TB1008LootWire.BuildPickup(R); Q:=TB1008LootWire.ParsePickup(P);
  Check((Q.DropID=R.DropID) and (Q.ItemID=D.ItemID) and (Q.Code=$33),'Pickup roundtrip');
  for I:=0 to 21 do
  begin
    B:=Copy(P);
    if I<19 then SetLength(B,I);
    if I=19 then SetLength(B,20);
    if I=20 then B[0]:=7;
    if I=21 then B[1]:=4;
    Failed:=False; try TB1008LootWire.ParsePickup(B); except on E:EKarosProtocol do Failed:=True; end;
    Check(Failed,'Malformed pickup admitted');
  end;
  P:=TB1008InventoryWire.BuildList(1,1,3,2);
  B:=TB1008InventoryWire.AppendLoot(P,1);
  Check((Length(B)=Length(P)+36) and (B[11]=3) and
    CompareMem(@B[12],@P[12],Length(P)-12) and (B[Length(P)+1]=2),'Reward slots changed');
  P:=TB1008InventoryWire.AppendCarat(B,20);
  Check((P[11]=4) and (P[Length(B)+1]=3) and (P[Length(B)+16]=20) and
    CompareMem(@B[12],@P[12],Length(B)-12),'Wallet overwrote an item');
  D.ItemID:=B1008CaratID; D.Amount:=10; P:=TB1008LootWire.BuildDrop(7,D);
  Check((P[28]=$3F) and (P[29]=$42) and (P[30]=$0F) and (P[42]=10),'Carat drop layout');
  Writeln('PASS: loot wire layout, strict pickup parser, additive inventory slot');
end;
procedure StoreTests;
var Dir,Path: string; G: TGUID; L: TB1008LootStore; O,Other: TObject;
  P: TBytes; N: Cardinal; I: Integer; Failed: Boolean; DB: TFDConnection;
begin
  CreateGUID(G); Dir:=TPath.Combine(TPath.GetTempPath,'KarosLoot-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir); Path:=TPath.Combine(Dir,'loot.sqlite3');
  L:=nil; O:=TObject.Create; Other:=TObject.Create; DB:=nil;
  try
    L:=TB1008LootStore.Create(Path,FixtureRates); P:=Preview;
    Check(L.Acquire(O,P),'Acquire'); Check(not L.Acquire(Other,P),'Concurrent owner');
    Check(L.Collect(O,'one',N) and (N=1),'First durable pickup');
    Check(L.Collect(O,'one',N) and (N=1),'Duplicate receipt');
    Check(L.CollectItem(O,'money1',B1008CaratID,10,N) and (N=10),'First Carat pickup');
    Check(L.CollectItem(O,'money1',B1008CaratID,10,N) and (N=10),'Duplicate Carat');
    Failed:=False;
    try L.CollectItem(O,'money1',B1008CaratID,20,N); except on E:Exception do Failed:=True; end;
    Check(Failed and (L.Balance(O)=10),'Receipt amount changed');
    Failed:=False; try L.Collect(Other,'intruder',N); except on E:Exception do Failed:=True; end;
    Check(Failed,'Foreign owner granted loot');
    FreeAndNil(L); L:=TB1008LootStore.Create(Path,FixtureRates);
    P[2]:=25; Check(L.Acquire(O,P) and (L.Count(O)=1),'Restart/timestamp identity');
    Check(L.Collect(O,'one',N) and (N=1),'Duplicate across restart');
    Check(L.Balance(O)=10,'Wallet missing after restart');
    Check(L.CollectItem(O,'money2',B1008CaratID,10,N) and (N=20),'Second Carat total');
    DB:=TFDConnection.Create(nil); DB.LoginPrompt:=False;
    DB.Params.Values['DriverID']:='SQLite'; DB.Params.Values['Database']:=Path; DB.Connected:=True;
    DB.ExecSQL('CREATE TRIGGER fail_pickup BEFORE INSERT ON pickups BEGIN SELECT RAISE(ABORT,''test write failure''); END');
    Failed:=False; try L.Collect(O,'two',N); except on E:Exception do Failed:=True; end;
    Check(Failed and (L.Count(O)=1),'Failed receipt write did not roll back inventory');
    Failed:=False;
    try L.CollectItem(O,'money3',B1008CaratID,10,N); except on E:Exception do Failed:=True; end;
    Check(Failed and (L.Balance(O)=20),'Failed receipt did not roll back wallet');
    DB.ExecSQL('DROP TRIGGER fail_pickup'); FreeAndNil(DB);
    Check(L.Collect(O,'two',N) and (N=2),'Retry after rollback');
    for I:=3 to B1008LootStackLimit do Check(L.Collect(O,IntToStr(I),N),'Fill stack');
    Check(L.Collect(O,'next-stack',N) and (L.Count(O)=B1008LootStackLimit+1),'Second stack missing');
    Check(L.CollectItem(O,'rich',B1008CaratID,B1008CaratLimit-20,N) and
      (N=B1008CaratLimit),'Wallet limit');
    Check(not L.CollectItem(O,'overflow',B1008CaratID,1,N) and
      (L.Balance(O)=B1008CaratLimit),'Wallet overflow');
    L.Release(O); P[15]:=P[15] xor 1;
    Failed:=False; try L.Acquire(O,P); except on E:Exception do Failed:=True; end;
    Check(Failed,'Different hero accepted old loot');
  finally
    DB.Free; L.Free; O.Free; Other.Free;
    if FileExists(Path) then TFile.Delete(Path);
    if FileExists(Path+'-wal') then TFile.Delete(Path+'-wal');
    if FileExists(Path+'-shm') then TFile.Delete(Path+'-shm');
    TDirectory.Delete(Dir,False);
  end;
  Writeln('PASS: loot SQLite restart, owner/identity, duplicate receipts, atomic rollback and full stack');
end;
procedure MigrationTests;
var Dir,Path: string; G: TGUID; DB: TFDConnection; L: TB1008LootStore;
  O: TObject; N: Cardinal; D: TB1008GroundDrop; Ground: TArray<TB1008GroundDrop>;
begin
  CreateGUID(G); Dir:=TPath.Combine(TPath.GetTempPath,'KarosLootMigration-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir); Path:=TPath.Combine(Dir,'loot.sqlite3');
  DB:=nil; L:=nil; O:=TObject.Create;
  try
    // Establish a real version-1 store with the current character identity.
    L:=TB1008LootStore.Create(Path,FixtureRates); Check(L.Acquire(O,Preview),'Migration owner');
    L.Collect(O,'old1',N); L.Collect(O,'old2',N); FreeAndNil(L);
    DB:=TFDConnection.Create(nil); DB.LoginPrompt:=False;
    DB.Params.Values['DriverID']:='SQLite'; DB.Params.Values['Database']:=Path; DB.Connected:=True;
    DB.ExecSQL('ALTER TABLE pickups RENAME TO pickups_v2');
    DB.ExecSQL('CREATE TABLE pickups (receipt TEXT PRIMARY KEY NOT NULL)');
    DB.ExecSQL('INSERT INTO pickups SELECT receipt FROM pickups_v2');
    DB.ExecSQL('DROP TABLE pickups_v2');
    RestorePreDropSchema(DB);DB.ExecSQL('DROP VIEW wallet');
    DB.ExecSQL('DROP TABLE inventory_v2_backup'); DB.ExecSQL('DROP TABLE wallet_v2_backup');
    DB.ExecSQL('DROP TABLE inventory_v9_backup');
    DB.ExecSQL('DELETE FROM inventory_v10_backup');
    DB.ExecSQL('INSERT INTO inventory_v10_backup SELECT * FROM inventory');
    DB.ExecSQL('DROP TABLE inventory');
    DB.ExecSQL('ALTER TABLE inventory_v10_backup RENAME TO inventory');
    DB.ExecSQL('DROP TABLE ground');
    DB.ExecSQL('DROP TABLE progression'); DB.ExecSQL('DROP TABLE exp_receipts');
    DB.ExecSQL('DROP TABLE progression_v5_backup'); DB.ExecSQL('DROP TABLE exp_receipts_v5_backup');
    DB.ExecSQL('DROP TABLE fletta_attributes_v12_backup');DB.ExecSQL('DROP TABLE fletta_investments_v12_backup');
    DB.ExecSQL('PRAGMA user_version=1'); FreeAndNil(DB);
    L:=TB1008LootStore.Create(Path,FixtureRates);
    Check(L.Acquire(O,Preview) and (L.Count(O)=2) and (L.Balance(O)=0),'Migration lost old loot');
    Check(L.Collect(O,'old1',N) and (N=2),'Migration lost old receipt');
    Check(L.CollectItem(O,'newmoney',B1008CaratID,10,N) and (N=10),'Migrated wallet unusable');
    FreeAndNil(L); L:=TB1008LootStore.Create(Path,FixtureRates);
    Check(L.Acquire(O,Preview) and (L.Count(O)=2) and (L.Balance(O)=10),'Second migration changed data');
    Check(L.Swap(O,3,17,999999,0),'Move money before restart');
    D:=Default(TB1008GroundDrop); D.ID:=1; D.OwnerID:=1; D.Receipt:='restart-ground';
    D.X:=8669; D.Z:=6668; D.Y:=604;
    DB:=TFDConnection.Create(nil); DB.LoginPrompt:=False;
    DB.Params.Values['DriverID']:='SQLite'; DB.Params.Values['Database']:=Path; DB.Connected:=True;
    DB.ExecSQL('CREATE TRIGGER fail_ground BEFORE INSERT ON ground BEGIN SELECT RAISE(ABORT,''test ground failure''); END');
    try L.ThrowItem(O,'failed-throw',17,999999,4,D,N); except on E:Exception do begin end; end;
    Check((L.Balance(O)=10) and (Length(L.GroundItems(O))=0),'Failed ground write lost money');
    DB.ExecSQL('DROP TRIGGER fail_ground'); FreeAndNil(DB);
    Check(L.ThrowItem(O,'failed-throw',17,999999,4,D,N) and (N=6),'Retry after ground rollback');
    FreeAndNil(L); L:=TB1008LootStore.Create(Path,FixtureRates); L.Acquire(O,Preview);
    Ground:=L.GroundItems(O);
    Check((L.Item(O,999999).Slot=17) and (L.Balance(O)=6) and
      (Length(Ground)=1) and (Ground[0].Amount=4),'Moved slot/ground lost on restart');
    Check(L.CollectItem(O,Ground[0].Receipt,999999,4,N) and (N=10),'Pickup after process-store restart');
  finally
    DB.Free; L.Free; O.Free;
    if FileExists(Path) then TFile.Delete(Path);
    if FileExists(Path+'-wal') then TFile.Delete(Path+'-wal');
    if FileExists(Path+'-shm') then TFile.Delete(Path+'-shm');
    TDirectory.Delete(Dir,False);
  end;
  Writeln('PASS: loot v1 migration preserves items, identity and receipts; wallet survives reopen');
end;
procedure BagTests;
var L: TB1008LootStore; O: TObject; N: Cardinal; D: TB1008GroundDrop;
  A: TB1008BagItem; Ground: TArray<TB1008GroundDrop>; P: TBytes;
  Swap: TB1008ItemSwap; Throw: TB1008ItemThrow;
begin
  L:=TB1008LootStore.Create('',FixtureRates); O:=TObject.Create;
  try
    L.Acquire(O,Preview); L.CollectItem(O,'bones',90004,8,N); L.CollectItem(O,'cash',999999,40,N);
    L.ImportRewards(O,3,2); L.ImportRewards(O,3,2);
    Check(L.Item(O,54006).Amount=3,'Duplicate legacy import');
    Check(L.Swap(O,2,7,90004,0),'Move to empty slot');
    Check(not L.Swap(O,2,7,90004,0),'Duplicate move accepted');
    Check(L.Swap(O,7,3,90004,999999),'Swap occupied slots');
    Check((L.Item(O,90004).Slot=3) and (L.Item(O,999999).Slot=7) and (L.Balance(O)=40),'Swap altered balance');
    Check(not L.Swap(O,7,20,999999,0),'Invalid slot accepted');
    Check(not L.Swap(O,3,4,54006,0),'Forged source accepted');
    Check(L.Swap(O,0,6,54006,0),'Move potion');
    Check(L.Consume(O,6,54006,N) and (N=2),'Use moved potion');
    Check(not L.Consume(O,0,54006,N),'Use stale potion slot');
    L.ImportRewards(O,3,2); Check(L.Item(O,54006).Amount=2,'Import restored consumed potion');
    D:=Default(TB1008GroundDrop); D.ID:=1; D.OwnerID:=1; D.X:=1; D.Z:=2; D.Y:=3; D.Receipt:='groundcash';
    Check(not L.ThrowItem(O,'badcount',7,999999,41,D,N),'Excessive throw');
    Check(L.ThrowItem(O,'throwcash',7,999999,10,D,N) and (N=30) and (D.Amount=10),'Partial money throw');
    Check(not L.ThrowItem(O,'throwcash',7,999999,10,D,N) and (L.Balance(O)=30),'Repeated throw duplicated ground');
    Ground:=L.GroundItems(O); Check((Length(Ground)=1) and (Ground[0].Amount=10),'Durable ground missing');
    Check(L.CollectItem(O,D.Receipt,D.ItemID,D.Amount,N) and (N=40),'Recollect thrown money');
    Check(Length(L.GroundItems(O))=0,'Picked-up ground not removed');
    Check(L.CollectItem(O,D.Receipt,D.ItemID,D.Amount,N) and (N=40),'Ground receipt duplicated');
    D.Receipt:='groundbone'; D.ID:=2;
    Check(L.ThrowItem(O,'throwbone',3,90004,-1,D,N) and (N=0) and (D.Amount=8),'Throw entire stack');
    Check(L.Swap(O,7,3,999999,0),'Freed throw slot unusable');
    Check(L.CollectItem(O,D.Receipt,D.ItemID,D.Amount,N) and (N=8),'Recollect entire stack');
    A:=L.Item(O,90004); Check(A.Slot<>3,'Pickup overwrote occupied slot');
    P:=TB1008InventoryWire.BuildBagList(1,1,L.Items(O)); Check(P[11]=3,'Bag list must omit money but include potions');
    P:=nil; SetLength(P,22); P[0]:=6; P[1]:=8; BE(P,6,1); P[10]:=1; P[11]:=2;
    BE(P,12,90004); P[16]:=1; P[17]:=7; BE(P,18,0);
    Swap:=TB1008InventoryWire.ParseSwap(P);
    Check((Swap.SourceID=90004) and (Swap.TargetID=0) and (Swap.TargetSlot=7),'Swap layout');
    P:=TB1008InventoryWire.BuildPutOut(1,1,90004,2); BE(P,16,$FFFFFFFF); BE(P,20,$FFFFFFFF);
    Throw:=TB1008InventoryWire.ParseThrow(P); Check(Throw.Amount=-1,'Signed throw-all count');
    BE(P,16,0); BE(P,20,10); Throw:=TB1008InventoryWire.ParseThrow(P); Check(Throw.Amount=10,'Throw BE64 count');
  finally O.Free; L.Free; end;
  Writeln('PASS: bag moves/swaps, moved potions, import-once, partial/all throw and re-pickup; no duplicates');
end;
procedure EquipmentThrowTests;
var Dir,Path,Desc:string; G:TGUID; L:TB1008LootStore; C:TB1008CharacterStore;
  S:TEmulatorSession; DB:TFDConnection; P,Request:TBytes; Replies:TB1008Replies;
  Items:TArray<TB1008EquipmentItem>; Ground:TArray<TB1008GroundDrop>;
  Pickup:TB1008Pickup; N,ItemID,RestoredID:Cardinal; I,J,Slot:Integer; Expires:Int64;
  Failed:Boolean;
  procedure CheckEquipment;
  var Current:TArray<TB1008EquipmentItem>; K:Integer;
  begin
    Current:=L.Equipment(S); Check(Length(Current)=Length(Items),'Throw changed equipped count');
    for K:=0 to High(Items) do Check((Current[K].Slot=Items[K].Slot) and
      (Current[K].ItemID=Items[K].ItemID),'Throw changed equipped item');
  end;
  procedure Reopen;
  var Reply:TBytes;
  begin
    FreeAndNil(S);FreeAndNil(L);L:=TB1008LootStore.Create(Path,FixtureRates);
    S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);Enter(S,Replies);
    S.HandlePacket(MoveTo(8669.776367),Replies);S.PollWorld(GetTickCount64,Replies);
    RestoredID:=0;
    for Reply in Replies do if (Reply[0]=6) and (Reply[1]=4) then
      RestoredID:=TB1008Wire.ReadBE32(Reply,10);
  end;
begin
  CreateGUID(G);Dir:=TPath.Combine(TPath.GetTempPath,'KarosGearThrow-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir);Path:=TPath.Combine(Dir,'loot.sqlite3');
  L:=nil;S:=nil;DB:=nil;C:=TB1008CharacterStore.Create;
  try
    C.CreateCharacter(Hero,P);Reopen;Items:=L.Equipment(S);
    // Every starter equipment slot, including a backpack copy of the equipped sword.
    for I:=0 to High(Items) do begin
      ItemID:=Items[I].ItemID;
      Check(L.CollectItem(S,'gear'+IntToStr(I),ItemID,1,N) and (N=1),'Seed backpack gear');
      Slot:=L.Item(S,ItemID).Slot;
      Request:=TB1008InventoryWire.BuildPutOut(100+Cardinal(I),1,ItemID,Slot);
      BE(Request,16,$FFFFFFFF);BE(Request,20,$FFFFFFFF);
      for J:=0 to 3 do begin
        P:=Copy(Request);
        case J of
          0:P[10]:=0; // Equipped page must never consume a backpack copy.
          1:BE(P,12,999999);
          2:P[11]:=19;
          3:begin BE(P,16,0);BE(P,20,2);end;
        end;
        Desc:=S.HandlePacket(P,Replies);
        Check((Pos('THROW SKIPPED',Desc)>0) and (Length(Replies)=0) and
          (L.Item(S,ItemID).Amount=1) and (Length(L.GroundItems(S))=0),
          'Invalid gear throw mutated state: '+Desc);
      end;
      if I=0 then begin
        DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;
        DB.Params.Values['DriverID']:='SQLite';DB.Params.Values['Database']:=Path;DB.Connected:=True;
        DB.ExecSQL('CREATE TRIGGER fail_gear_ground BEFORE INSERT ON ground BEGIN SELECT RAISE(ABORT,''gear write failure''); END');
        Failed:=False;
        try S.HandlePacket(Request,Replies);except on E:Exception do Failed:=True;end;
        Check(Failed and (L.Item(S,ItemID).Amount=1) and
          (Length(L.GroundItems(S))=0),'Failed gear ground write lost item');
        DB.ExecSQL('DROP TRIGGER fail_gear_ground');FreeAndNil(DB);
      end;
      Desc:=S.HandlePacket(Request,Replies);
      Check((Pos('ITEM THROWN',Desc)>0) and (Length(Replies)=2),Desc);
      Check((Replies[0][0]=6) and (Replies[0][1]=7) and
        (Replies[1][0]=6) and (Replies[1][1]=4),'Gear throw reply order');
      Ground:=L.GroundItems(S);Check((Length(Ground)=1) and (Ground[0].ItemID=ItemID) and
        (Ground[0].Amount=1) and (L.Item(S,ItemID).Amount=0),'Gear ground ownership');
      Expires:=Ground[0].ExpiresUTC;CheckEquipment;
      S.HandlePacket(Request,Replies);
      Check((Length(Replies)=0) and (Length(L.GroundItems(S))=1),'Gear throw replay duplicated ground');
      Reopen;Ground:=L.GroundItems(S);
      Check((Length(Ground)=1) and (Ground[0].ExpiresUTC=Expires) and
        (L.Item(S,ItemID).Amount=0),'Gear throw persistence/expiry');CheckEquipment;
      Pickup:=Default(TB1008Pickup);Pickup.Timestamp:=300+Cardinal(I);Pickup.CharacterID:=1;
      Check(RestoredID<>0,'Restored gear was not published');
      Pickup.DropID:=RestoredID;Pickup.ItemID:=ItemID;Pickup.Code:=$33;
      P:=TB1008LootWire.BuildPickup(Pickup);Desc:=S.HandlePacket(P,Replies);
      Check((Pos('LOOT PICKED UP',Desc)>0) and (Length(Replies)=2) and
        (L.Item(S,ItemID).Amount=1) and (Length(L.GroundItems(S))=0),Desc);
      S.HandlePacket(P,Replies);
      Check((Length(Replies)=0) and (L.Item(S,ItemID).Amount=1),'Gear pickup replay duplicated item');
      Reopen;Check((L.Item(S,ItemID).Amount=1) and
        (Length(L.GroundItems(S))=0),'Gear pickup persistence');CheckEquipment;
    end;
  finally
    DB.Free;S.Free;L.Free;C.Free;
    if FileExists(Path) then TFile.Delete(Path);
    if FileExists(Path+'-wal') then TFile.Delete(Path+'-wal');
    if FileExists(Path+'-shm') then TFile.Delete(Path+'-shm');
    TDirectory.Delete(Dir,False);
  end;
  Writeln('PASS: all five gear slots throw/reopen/pickup, equipped copies retained, replay and atomic rollback');
end;
procedure CleanerTests;
var L: TB1008LootStore; C: TB1008CharacterStore; S: TEmulatorSession;
  P,B: TBytes; Replies: TB1008Replies; T: UInt64; N: Cardinal; Removed,Created: Integer;
  ExpiresBefore:Int64;
begin
  L:=TB1008LootStore.Create('',FixtureRates); C:=TB1008CharacterStore.Create; S:=nil;
  try
    C.CreateCharacter(Hero,P); S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);
    Enter(S,Replies); T:=GetTickCount64;
    S.PollWorld(T+100,Replies);
    Check(Length(Replies)=0,'Patrol began before client scene readiness');
    Kill(S,Replies);
    Created:=0;for P in Replies do if (P[0]=6) and (P[1]=4) then Inc(Created);
    Check(Created>0,'Cleaner test needs guaranteed currency drop');
    Check((B1008MobLootLifetimeMS=60000) and (B1008ThrownLootLifetimeMS=60000),'Expected one-minute ground lifetimes');
    S.PollWorld(T+59000,Replies);
    for P in Replies do Check(not ((P[0]=6) and (P[1]=3)),'Mob loot expired early');
    S.PollWorld(T+61000,Replies); Removed:=0;
    for P in Replies do if (P[0]=6) and (P[1]=3) then begin
      Inc(Removed); Check(TB1008Wire.ReadBE32(P,6)=$FFFFFFFF,'Cleaner must not credit a pickup');
    end;
    Check((Removed=Created) and (L.Count(S)=0) and (L.Balance(S)=0),'Mob cleaner did not remove all rolled drops without a grant');
    L.CollectItem(S,'cleaner-money',999999,10,N);
    P:=TB1008InventoryWire.BuildPutOut(1,1,999999,3); BE(P,16,$FFFFFFFF); BE(P,20,$FFFFFFFF);
    S.HandlePacket(P,Replies); Check((Length(Replies)=2) and (Length(L.GroundItems(S))=1),'Thrown test ground missing');
    ExpiresBefore:=L.GroundItems(S)[0].ExpiresUTC;
    FreeAndNil(S); S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);
    Enter(S,Replies);
    for B in Replies do Check(not ((B[0]=6) and (B[1]=4)),'Ground drop emitted during scene loading');
    Check(L.GroundItems(S)[0].ExpiresUTC>B1008UtcNowMS,'Persisted expiry truncated to 32 bits');
    Check(L.GroundItems(S)[0].ExpiresUTC=ExpiresBefore,'Reentry extended thrown loot expiry');
    S.HandlePacket(MoveTo(8669.776367),Replies); S.PollWorld(GetTickCount64,Replies); Removed:=0;
    for B in Replies do if (B[0]=6) and (B[1]=4) then Inc(Removed);
    Check(Removed=1,'Unexpired ground not restored after movement readiness');
    S.PollWorld(GetTickCount64+59000,Replies);
    for B in Replies do Check(not ((B[0]=6) and (B[1]=3)),'Thrown loot expired before one minute');
    S.PollWorld(GetTickCount64+61000,Replies); Removed:=0;
    for B in Replies do if (B[0]=6) and (B[1]=3) then Inc(Removed);
    Check((Removed=1) and (Length(L.GroundItems(S))=0) and (L.Balance(S)=0),'Thrown cleaner failed');
  finally S.Free; C.Free; L.Free; end;
  Writeln('PASS: cleaner60 seconds for mob/thrown loot, no phantom pickup, reentry retains original expiry');
end;
procedure MultiStackTests;
var G:TGUID;Dir,Path:string;L:TB1008LootStore;O:TObject;DB:TFDConnection;
  N,Take:Cardinal;I:Integer;Failed:Boolean;U,All:TArray<TB1008BagItem>;D:TB1008GroundDrop;
begin
  CreateGUID(G);Dir:=TPath.Combine(TPath.GetTempPath,'KarosStacks-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir);Path:=TPath.Combine(Dir,'hero.sqlite3');
  O:=TObject.Create;L:=nil;DB:=nil;
  try
    L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Preview);
    L.CollectItem(O,'old-bones',90004,98,N);L.Swap(O,2,0,90004,0);
    L.CollectItem(O,'old-money',999999,345,N);L.Swap(O,3,1,999999,0);
    L.RecordQuestEXP(O,19003003);FreeAndNil(L);
    // Restore the real v10 table (including its single-item UNIQUE constraint).
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;DB.Params.Values['DriverID']:='SQLite';
    DB.Params.Values['Database']:=Path;DB.Connected:=True;
    RestorePreDropSchema(DB);
    DB.ExecSQL('DROP VIEW wallet');DB.ExecSQL('DELETE FROM inventory_v10_backup');
    DB.ExecSQL('INSERT INTO inventory_v10_backup SELECT * FROM inventory');DB.ExecSQL('DROP TABLE inventory');
    DB.ExecSQL('ALTER TABLE inventory_v10_backup RENAME TO inventory');
    DB.ExecSQL('CREATE VIEW wallet AS SELECT 1 AS id,amount FROM inventory WHERE item_id=999999');
    DB.ExecSQL('PRAGMA user_version=10');
    DB.ExecSQL('DROP TABLE fletta_attributes_v12_backup');DB.ExecSQL('DROP TABLE fletta_investments_v12_backup');
    L:=TB1008LootStore.Create(Path,FixtureRates);Check(L.Acquire(O,Preview),'Migrated owner');
    Check((Integer(DB.ExecSQLScalar('PRAGMA user_version'))=39) and
      (Integer(DB.ExecSQLScalar('SELECT amount FROM inventory_v10_backup WHERE item_id=90004'))=98),'v10 backup/version');
    Check((L.Item(O,90004).Slot=0) and (L.Item(O,999999).Slot=1) and
      (L.Progress(O).TotalEXP=24) and (Length(L.Equipment(O))=5),'Migration changed hero/gear/cells');
    DB.ExecSQL('INSERT INTO ground(receipt,item_id,amount,x,z,y,expires_ms) VALUES(''overflow'',90004,3,8669,6668,604,:t)',[B1008UtcNowMS+30000]);
    DB.ExecSQL('CREATE TRIGGER fail_stack_receipt BEFORE INSERT ON pickups BEGIN SELECT RAISE(ABORT,''test'');END');
    Failed:=False;try L.CollectItem(O,'overflow',90004,3,N,U);except on E:Exception do Failed:=True;end;
    Check(Failed and (L.Count(O)=98) and (Length(L.Items(O))=2) and (Length(U)=0) and
      (Length(L.GroundItems(O))=1),'Two-cell pickup did not roll back');
    DB.ExecSQL('DROP TRIGGER fail_stack_receipt');
    Check(L.CollectItem(O,'overflow',90004,3,N,U) and (N=101) and (Length(U)=2),'98+3 split');
    Check((U[0].Slot=0) and (U[0].Amount=100) and (U[1].Slot=2) and (U[1].Amount=1),'Wrong split/cells');
    Check(L.CollectItem(O,'overflow',90004,3,N,U) and (N=101) and (Length(U)=0),'Duplicate split pickup');
    Check((L.Balance(O)=345) and (Length(L.GroundItems(O))=0),'Money/ground changed incorrectly');
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Preview);
    All:=L.Items(O);Check((Length(All)=3) and (All[0].Amount=100) and
      (All[2].Amount=1) and (L.Count(O)=101),'Second stack lost after reopen');
    Check(L.Swap(O,2,8,90004,0),'Move second stack');
    D:=Default(TB1008GroundDrop);D.OwnerID:=1;D.ID:=7;D.Receipt:='throw-second';D.X:=8669;D.Z:=6668;D.Y:=604;
    Check(L.ThrowItem(O,'throw-second',8,90004,-1,D,N) and (D.Amount=1) and
      (N=0) and (L.Count(O)=100),'Throw addressed wrong stack');
    Check(L.CollectItem(O,D.Receipt,90004,1,N,U) and (N=101),'Re-pick second stack');
    I:=0;
    while L.Count(O)<1899 do begin
      Inc(I);Take:=1899-L.Count(O);if Take>100 then Take:=100;
      Check(L.CollectItem(O,'fill-'+IntToStr(I),90004,Take,N,U),'Fill available cells');
    end;
    Check(Length(L.Items(O))=20,'Expected 19 bone cells and one currency cell');
    Check(not L.CollectItem(O,'full',90004,3,N,U) and (L.Count(O)=1899) and
      (N=1899) and (Length(U)=0),'Full bag lost partial pickup');
    Check(L.CollectItem(O,'last-space',90004,1,N,U) and (N=1900) and (Length(U)=1),'Fill partial stack with no free cells');
    Check(not L.CollectItem(O,'over-capacity',90004,1,N,U) and (N=1900),'Bag exceeded capacity');
    Check(L.Balance(O)=345,'Full bone bag changed currency');
    Writeln('PASS: v10->11 retains cells/gear/EXP; 98+3=100+1, replay/rollback, move/throw/re-pick/reopen, full bag atomicity');
  finally L.Free;DB.Free;O.Free;TDirectory.Delete(Dir,True);end;
end;

function SplitRequest(Timestamp:Cardinal;Slot:Byte;ItemID,Count:Cardinal;Amount:Int64):TBytes;
var V:UInt64;
begin
  Result:=TB1008InventoryWire.BuildPutIn(Timestamp,1,ItemID,Count,Slot);
  SetLength(Result,55);Result[1]:=$0A;Move(Amount,V,8);
  BE(Result,46,Cardinal(V shr 32));BE(Result,50,Cardinal(V and $FFFFFFFF));Result[54]:=$38;
end;

procedure SplitTests;
var G:TGUID;Dir,Path:string;L:TB1008LootStore;O,Other:TObject;DB:TFDConnection;
  A,B:TB1008BagItem;N:Cardinal;P,Q:TBytes;R:TB1008ItemSplit;I:Integer;Failed:Boolean;
begin
  P:=SplitRequest($12345678,7,90004,100,5);R:=TB1008InventoryWire.ParseSplit(P);
  Check((R.Timestamp=$12345678) and (R.CharacterID=1) and (R.Page=1) and
    (R.Slot=7) and (R.ItemID=90004) and (R.SourceCount=100) and (R.Amount=5) and (R.Code=$38),'Shift wire fields');
  Q:=SplitRequest(1,7,90004,100,-1);R:=TB1008InventoryWire.ParseSplit(Q);Check(R.Amount=-1,'Signed split amount');
  Q:=SplitRequest(1,7,90004,100,Int64(1) shl 40);R:=TB1008InventoryWire.ParseSplit(Q);Check(R.Amount=Int64(1) shl 40,'Full BE64 quantity');
  Q:=Copy(P);Q[33]:=$80;R:=TB1008InventoryWire.ParseSplit(Q);Check(R.SourceCount>UInt64(High(Int64)),'Full packed LE64 source count');
  for I:=0 to 57 do begin
    Q:=Copy(P);if I<55 then SetLength(Q,I);
    if I=55 then SetLength(Q,56);if I=56 then Q[0]:=7;if I=57 then Q[1]:=9;
    Failed:=False;try TB1008InventoryWire.ParseSplit(Q);except on E:EKarosProtocol do Failed:=True;end;
    Check(Failed,'Malformed split admitted');
  end;
  Q:=TB1008InventoryWire.BuildSplitAck(1,1,True);Check((Length(Q)=55) and (Q[54]=$38),'Split success code');
  Q:=TB1008InventoryWire.BuildSplitAck(1,1,False);Check(Q[54]=9,'Split failure code');
  for I:=10 to 53 do Check(Q[I]=0,'Ack reflected untrusted item data');
  CreateGUID(G);Dir:=TPath.Combine(TPath.GetTempPath,'KarosSplit-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir);Path:=TPath.Combine(Dir,'hero.sqlite3');
  O:=TObject.Create;Other:=TObject.Create;L:=nil;DB:=nil;
  try
    L:=TB1008LootStore.Create(Path,FixtureRates);Check(L.Acquire(O,Preview),'Split owner');
    L.CollectItem(O,'bones',90004,100,N);L.CollectItem(O,'more-bones',90004,4,N);
    L.CollectItem(O,'money',999999,365,N);
    Check(not L.SplitItem(O,'zero',2,90004,100,0,A,B),'Zero split');
    Check(not L.SplitItem(O,'negative',2,90004,100,-1,A,B),'Negative split');
    Check(not L.SplitItem(O,'all',2,90004,100,100,A,B),'Whole stack is not a split');
    Check(not L.SplitItem(O,'overflow',2,90004,100,High(Int64),A,B),'Huge split');
    Check(not L.SplitItem(O,'stale',2,90004,99,5,A,B),'Stale source amount');
    Check(not L.SplitItem(O,'huge-source',2,90004,High(UInt64),5,A,B),'Huge packed source amount');
    Check(not L.SplitItem(O,'wrong-id',2,54006,100,5,A,B),'Forged item ID');
    Check(not L.SplitItem(O,'empty',19,90004,100,5,A,B),'Empty source');
    Check(not L.SplitItem(O,'bad-slot',255,90004,100,5,A,B),'Invalid source slot');
    Check(not L.SplitItem(O,'',2,90004,100,5,A,B),'Empty receipt');
    Check(not L.SplitItem(O,'carat',3,999999,365,5,A,B),'Unsupported wallet split changed money');
    Failed:=False;try L.SplitItem(Other,'foreign',2,90004,100,5,A,B);except on E:Exception do Failed:=True;end;
    Check(Failed,'Foreign split owner');
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;DB.Params.Values['DriverID']:='SQLite';
    DB.Params.Values['Database']:=Path;DB.Connected:=True;
    DB.ExecSQL('CREATE TRIGGER fail_split BEFORE INSERT ON operations BEGIN SELECT RAISE(ABORT,''test'');END');
    Failed:=False;try L.SplitItem(O,'split-five',2,90004,100,5,A,B);except on E:Exception do Failed:=True;end;
    Check(Failed and (A.Amount=0) and (B.Amount=0) and (L.Count(O)=104) and
      (Length(L.Items(O))=3),'Split receipt failure lost items or exposed uncommitted rows');
    DB.ExecSQL('DROP TRIGGER fail_split');
    Check(L.SplitItem(O,'split-five',2,90004,100,5,A,B),'Split retry');
    Check((A.Slot=2) and (A.Amount=95) and (B.Slot=1) and (B.Amount=5) and
      (L.Count(O)=104) and (L.Item(O,90004).Amount=4),'Split merged into existing partial stack');
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Preview);
    Check((Length(L.Items(O))=4) and (L.Count(O)=104) and (L.Balance(O)=365) and
      (Length(L.Equipment(O))=5),'Split reopen affected inventory/wallet/gear');
    Check(not L.SplitItem(O,'split-five',2,90004,95,5,A,B),'Receipt replay after restart');
    // Restore the original source count via ordinary pickup; replay must still fail.
    L.CollectItem(O,'fill-small',90004,96,N);L.CollectItem(O,'fill-other',90004,95,N);
    L.CollectItem(O,'restore-source',90004,5,N);
    Check(not L.SplitItem(O,'split-five',2,90004,100,5,A,B),'Replay after source amount restored');
    L.CollectItem(O,'potions',54006,3,N);I:=L.Item(O,54006).Slot;
    Check(L.SplitItem(O,'split-potion',I,54006,3,1,A,B) and (A.Amount=2) and (B.Amount=1),'Potion split');
    I:=0;
    while Length(L.Items(O))<20 do begin
      Inc(I);Check(L.CollectItem(O,'fill-'+IntToStr(I),90004,100,N),'Fill bag for split');
    end;
    N:=L.Count(O);
    Check(not L.SplitItem(O,'full',2,90004,100,5,A,B) and (L.Count(O)=N) and
      (Length(L.Items(O))=20) and (L.Balance(O)=365),'Full bag split lost/duplicated items');
  finally L.Free;DB.Free;O.Free;Other.Free;TDirectory.Delete(Dir,True);end;
  Writeln('PASS: Shift wire, 100->95+5, no merge, owner/count guards, atomic rollback, receipts/reopen/full bag');
end;

procedure SplitSessionTests;
var L:TB1008LootStore;C:TB1008CharacterStore;S:TEmulatorSession;P,Q,Expected:TBytes;
  Replies:TB1008Replies;N:Cardinal;Desc:string;
begin
  L:=TB1008LootStore.Create('',FixtureRates);C:=TB1008CharacterStore.Create;S:=nil;
  try
    C.CreateCharacter(Hero,P);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);
    P:=SplitRequest(100,2,90004,100,5);
    S.HandlePacket(P,Replies);Check(Length(Replies)=0,'Unadmitted split');
    Enter(S,Replies);L.CollectItem(S,'seed',90004,100,N);L.CollectItem(S,'money',999999,365,N);
    Q:=Copy(P);BE(Q,6,2);S.HandlePacket(Q,Replies);Check(Length(Replies)=0,'Wrong split character');
    Q:=Copy(P);Q[10]:=0;S.HandlePacket(Q,Replies);Check(Length(Replies)=0,'Equipment-page split');
    Q:=Copy(P);Q[54]:=9;S.HandlePacket(Q,Replies);Check(Length(Replies)=0,'Unknown split request code');
    Desc:=S.HandlePacket(P,Replies);
    Check((Pos('INVENTORY SPLIT',Desc)>0) and (Length(Replies)=3),Desc);
    Check((Replies[0][1]=6) and (Replies[0][11]=2) and (Replies[0][26]=95) and
      (Replies[1][1]=6) and (Replies[1][11]=0) and (Replies[1][26]=5) and
      (Replies[2][1]=$0A) and (Replies[2][54]=$38),'Split cell updates/ack order');
    Desc:=S.HandlePacket(P,Replies);
    Check((Pos('REJECTED',Desc)>0) and (Length(Replies)=1) and (Replies[0][54]=9) and
      (L.Count(S)=100) and (L.Balance(S)=365),'Duplicate split grants items');
    Q:=SplitRequest(101,2,90004,95,1);S.HandlePacket(Q,Replies);
    Check((Length(Replies)=3) and (Replies[0][26]=94) and (Replies[1][26]=1),'Repeated distinct split');
    FreeAndNil(S);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);Enter(S,Replies);
    Expected:=TB1008InventoryWire.BuildBagList(1,1,L.Items(S));Q:=Replies[3];
    Check((Q[11]=Expected[11]+5) and CompareMem(@Q[12],@Expected[12],Length(Expected)-12) and
      (L.Count(S)=100) and (L.Balance(S)=365),'Split cell restore on reconnect');
  finally S.Free;C.Free;L.Free;end;
  Writeln('PASS: Shift session admission, per-cell updates, success/failure notifications, replay and reconnect');
end;

procedure MergeTests;
var G:TGUID;Dir,Path:string;L:TB1008LootStore;O,Other:TObject;DB:TFDConnection;
  A,B:TB1008BagItem;N:Cardinal;I,SmallSlot:Integer;Failed:Boolean;
begin
  CreateGUID(G);Dir:=TPath.Combine(TPath.GetTempPath,'KarosMerge-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir);Path:=TPath.Combine(Dir,'hero.sqlite3');
  O:=TObject.Create;Other:=TObject.Create;L:=nil;DB:=nil;
  try
    L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Preview);
    L.CollectItem(O,'seed',90004,100,N);L.SplitItem(O,'split',2,90004,100,40,A,B);
    L.CollectItem(O,'money',999999,365,N);
    Check(not L.MergeItems(O,'same-cell',0,0,90004,A,B),'Same-cell merge');
    Check(not L.MergeItems(O,'bad-cell',255,2,90004,A,B),'Invalid merge cell');
    Check(not L.MergeItems(O,'empty',19,2,90004,A,B),'Empty merge source');
    Check(not L.MergeItems(O,'empty-target',0,19,90004,A,B),'Empty merge target');
    Check(not L.MergeItems(O,'mixed',0,3,90004,A,B),'Merge different item IDs');
    Check(not L.MergeItems(O,'forged',0,2,54006,A,B),'Forged merge type');
    Check(not L.MergeItems(O,'gear',0,2,1001,A,B),'Gear merge');
    Check(not L.MergeItems(O,'',0,2,90004,A,B),'Missing merge receipt');
    Failed:=False;try L.MergeItems(Other,'foreign',0,2,90004,A,B);except on E:Exception do Failed:=True;end;
    Check(Failed,'Foreign merge owner');
    DB:=TFDConnection.Create(nil);DB.LoginPrompt:=False;DB.Params.Values['DriverID']:='SQLite';
    DB.Params.Values['Database']:=Path;DB.Connected:=True;
    DB.ExecSQL('CREATE TRIGGER fail_merge BEFORE INSERT ON operations BEGIN SELECT RAISE(ABORT,''test'');END');
    Failed:=False;try L.MergeItems(O,'merge',0,2,90004,A,B);except on E:Exception do Failed:=True;end;
    Check(Failed and (A.Amount=0) and (B.Amount=0) and (L.Count(O)=100) and
      (Length(L.Items(O))=3) and (L.Item(O,90004).Amount=40),'Merge delete/update did not roll back');
    DB.ExecSQL('DROP TRIGGER fail_merge');
    Check(L.MergeItems(O,'merge',0,2,90004,A,B) and (A.Amount=0) and
      (B.Slot=2) and (B.Amount=100) and (Length(L.Items(O))=2),'Complete merge did not free source');
    FreeAndNil(L);L:=TB1008LootStore.Create(Path,FixtureRates);L.Acquire(O,Preview);
    L.SplitItem(O,'split-again',2,90004,100,40,A,B);
    Check(not L.MergeItems(O,'merge',0,2,90004,A,B),'Merge receipt replay after reopen/restored arrangement');
    Check(L.MergeItems(O,'reverse',2,0,90004,A,B) and (A.Amount=0) and
      (B.Slot=0) and (B.Amount=100),'Merge direction follows target');
    L.CollectItem(O,'extra',90004,50,N);
    Check(L.MergeItems(O,'partial',0,2,90004,A,B) and (A.Amount=50) and
      (B.Amount=100) and (L.Count(O)=150),'Partial merge lost overflow');
    Check(not L.MergeItems(O,'full-target',0,2,90004,A,B) and (L.Count(O)=150),'Full target changed source');
    L.CollectItem(O,'potions',54006,99,N);I:=L.Item(O,54006).Slot;
    L.SplitItem(O,'split-potion',I,54006,99,1,A,B);SmallSlot:=B.Slot;
    Check(L.MergeItems(O,'merge-potion',SmallSlot,I,54006,A,B) and (B.Amount=99),'Potion stack limit/merge');
    I:=0;
    while Length(L.Items(O))<19 do begin
      Inc(I);Check(L.CollectItem(O,'fill-'+IntToStr(I),90004,100,N),'Fill merge bag');
    end;
    Check(L.SplitItem(O,'full-bag-split',0,90004,100,5,A,B),'Prepare full bag');SmallSlot:=B.Slot;
    Check(Length(L.Items(O))=20,'Full bag merge fixture');N:=L.Count(O);
    Check(L.MergeItems(O,'full-bag-partial',2,0,90004,A,B) and (A.Amount=95) and
      (B.Amount=100) and (Length(L.Items(O))=20),'Partial merge must work in full bag');
    Check(L.MergeItems(O,'full-bag-complete',SmallSlot,2,90004,A,B) and (A.Amount=0) and
      (B.Amount=100) and (Length(L.Items(O))=19) and (L.Count(O)=N),'Full bag merge did not release cell');
    Check((L.Balance(O)=365) and (Length(L.Equipment(O))=5),'Merge changed money or gear');
  finally L.Free;DB.Free;O.Free;Other.Free;TDirectory.Delete(Dir,True);end;
  Writeln('PASS: complete/partial merge, original target, full backpack, stack caps, rollback/replay/reopen/guards');
end;

procedure MergeSessionTests;
var L:TB1008LootStore;C:TB1008CharacterStore;S:TEmulatorSession;P,Q:TBytes;
  Replies:TB1008Replies;N:Cardinal;Desc:string;A,B:TB1008BagItem;
begin
  L:=TB1008LootStore.Create('',FixtureRates);C:=TB1008CharacterStore.Create;S:=nil;
  try
    C.CreateCharacter(Hero,P);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);Enter(S,Replies);
    L.CollectItem(S,'seed',90004,100,N);L.SplitItem(S,'split',2,90004,100,5,A,B);
    L.CollectItem(S,'money',999999,365,N);
    P:=nil;SetLength(P,22);P[0]:=6;P[1]:=8;BE(P,2,1000);BE(P,6,1);
    P[10]:=1;P[11]:=0;BE(P,12,90004);P[16]:=1;P[17]:=2;BE(P,18,90004);
    Desc:=S.HandlePacket(P,Replies);
    Check((Pos('INVENTORY MERGED',Desc)>0) and (Length(Replies)=2),Desc);
    Check((Replies[0][1]=7) and (Replies[0][11]=0) and (Replies[1][1]=6) and
      (Replies[1][11]=2) and (Replies[1][26]=100),'Complete merge must remove source, update target, NOT echo swap');
    L.SplitItem(S,'split-again',2,90004,100,5,A,B);
    S.HandlePacket(P,Replies);Check((Length(Replies)=0) and (L.Item(S,90004).Amount=5),'Duplicate merge after cells restored');
    L.CollectItem(S,'more',90004,10,N); // source 15, target 95
    BE(P,2,1001);S.HandlePacket(P,Replies);
    Check((Length(Replies)=2) and (Replies[0][1]=6) and (Replies[0][11]=0) and
      (Replies[0][26]=10) and (Replies[1][26]=100),'Partial merge per-cell values');
    BE(P,2,1002);S.HandlePacket(P,Replies);Check((Length(Replies)=0) and (L.Count(S)=110),'Full target duplicated items');
    // Different items continue to swap with an exact 06/08 acknowledgement.
    Q:=Copy(P);BE(Q,2,1003);Q[17]:=3;BE(Q,18,999999);S.HandlePacket(Q,Replies);
    Check((Length(Replies)=1) and (Length(Replies[0])=22) and CompareMem(@Q[0],@Replies[0][0],22) and
      (L.Item(S,999999).Slot=0) and (L.Count(S)=110),'Different-item swap regressed');
    FreeAndNil(S);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);Enter(S,Replies);
    Check((L.Count(S)=110) and (L.Balance(S)=365) and (L.Item(S,90004).Amount=100),'Merge reconnect persistence');
  finally S.Free;C.Free;L.Free;end;
  Writeln('PASS: ordinary drag merges identical IDs without swap echo; overflow, receipts, other-item swap, reconnect');
end;

procedure SessionTests(PreFill:Boolean = False);
var L: TB1008LootStore; C: TB1008CharacterStore; S: TEmulatorSession;
  P,B: TBytes; Replies,DeathReplies: TB1008Replies; R,Bad: TB1008Pickup; I,Drops,J: Integer;
  Desc: string;Initial,N,Seed:Cardinal;ExpectedList:TBytes;
  Awards:TArray<TB1008RolledDrop>;Award:TB1008RolledDrop;
  DropX,DropZ,OtherX,OtherZ:Single;
begin
  L:=TB1008LootStore.Create('',FixtureRates); C:=TB1008CharacterStore.Create; S:=nil;
  try
    C.CreateCharacter(Hero,P);
    Seed:=12345;Awards:=TB1008DropProfile.RollMob(Seed,100,120,FixtureRates);
    S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L,12345);
    R:=Default(TB1008Pickup); R.CharacterID:=1; R.DropID:=1; R.ItemID:=90004; R.Code:=$33;
    Desc:=S.HandlePacket(TB1008LootWire.BuildPickup(R),Replies);
    Check((Length(Replies)=0) and (Pos('SKIPPED',Desc)>0),'Early pickup');
    Enter(S,Replies);
    if PreFill then for Award in Awards do if Award.Category='ordinary' then
      L.CollectItem(S,'full-stack',Award.ItemID,100,N);
    Kill(S,Replies);
    DeathReplies:=Copy(Replies);
    Check(L.Progress(S).TotalEXP=TB1008Balance.SpiderEXP,'One lethal hit must award configured EXP');
    Drops:=0;
    for P in Replies do if (P[0]=8) and (P[1]=1) then begin
      Inc(Drops); Check((Length(P)=101) and (P[$3D]=TB1008Balance.SpiderEXP),'Kill EXP wire');
    end;
    Check(Drops=1,'One EXP update per kill');
    Drops:=0;
    for I:=0 to High(Replies) do
      if (Replies[I][0]=6) and (Replies[I][1]=4) then
      begin
        Move(Replies[I][28],N,4);Check(N=Awards[Drops].ItemID,'Rolled template changed');
        Move(Replies[I][42],N,4);Check(N=Awards[Drops].Amount,'Rolled quantity changed');Inc(Drops);
        Move(Replies[I][62],DropX,4);Move(Replies[I][66],DropZ,4);
        if Length(Awards)>1 then Check(Abs(Sqrt(Sqr(DropX-8669.776367)+
          Sqr(DropZ-6668.010254))-B1008MobLootScatterRadius)<0.01,'Wrong scatter radius');
        for J:=0 to I-1 do if (Replies[J][0]=6) and (Replies[J][1]=4) then begin
          Move(Replies[J][62],OtherX,4);Move(Replies[J][66],OtherZ,4);
          Check(Sqr(DropX-OtherX)+Sqr(DropZ-OtherZ)>Sqr(9),'Simultaneous boxes overlap');
        end;
      end;
    Check(Drops=Length(Awards),'Lethal hit must immediately emit every rolled category');
    S.PollWorld(GetTickCount64+2601,Replies);
    Check(L.Progress(S).TotalEXP=TB1008Balance.SpiderEXP,'Corpse despawn awarded EXP twice');
    for P in Replies do Check(not ((P[0]=6) and (P[1]=4)),'Repeated despawn created duplicate loot');
    J:=0;
    for P in DeathReplies do if (P[0]=6) and (P[1]=4) then begin
      Award:=Awards[J];Inc(J);R.DropID:=TB1008Wire.ReadBE32(P,10);R.ItemID:=Award.ItemID;
      Bad:=R;Bad.CharacterID:=2;
      S.HandlePacket(TB1008LootWire.BuildPickup(Bad),Replies);Check(Length(Replies)=0,'Foreign pickup');
      Bad:=R;Bad.ItemID:=12345678;
      S.HandlePacket(TB1008LootWire.BuildPickup(Bad),Replies);Check(Length(Replies)=0,'Forged item');
      Bad:=R;Bad.DropID:=999;
      S.HandlePacket(TB1008LootWire.BuildPickup(Bad),Replies);Check(Length(Replies)=0,'Unknown drop');
      Initial:=0;for var Item in L.Items(S) do if Item.ItemID=R.ItemID then Inc(Initial,Item.Amount);
      S.HandlePacket(MoveTo(8769.776367),Replies);
      S.HandlePacket(TB1008LootWire.BuildPickup(R),Replies);
      Check((Length(Replies)=2) and (Replies[0][1]=3) and
        (TB1008Wire.ReadBE32(Replies[0],6)=$FFFFFFFF) and
        (Replies[1][1]=4) and (TB1008Wire.ReadBE32(Replies[1],10)=R.DropID),
        'Distant pickup must reset the same ground object without granting it');
      N:=0;for var Item in L.Items(S) do if Item.ItemID=R.ItemID then Inc(N,Item.Amount);
      Check(N=Initial,'Range rejection granted inventory');
      if PreFill then S.HandlePacket(MoveTo(8669.776367),Replies)
      else begin
        Move(P[62],DropX,4);Move(P[66],DropZ,4);
        S.HandlePacket(TB1008World.BuildActorMovement(1,0,1,1,
          DropX-34,DropZ,604.350342,DropX,DropZ,604.350342,0),Replies);
      end;
      Desc:=S.HandlePacket(TB1008LootWire.BuildPickup(R),Replies);
      Check((Length(Replies)>=2) and (Pos('LOOT PICKED UP',Desc)>0),Desc);
      Check((Replies[0][1]=6) and (Replies[High(Replies)][1]=3),'Grant before removal');
      N:=0;for var Item in L.Items(S) do if Item.ItemID=R.ItemID then Inc(N,Item.Amount);
      Check(N=Initial+Award.Amount,'Rolled reward not collected exactly once');
      S.HandlePacket(TB1008LootWire.BuildPickup(R),Replies);Check(Length(Replies)=0,'Duplicate pickup');
    end;
    Check(L.Balance(S)=Awards[0].Amount,'Guaranteed currency not collected');
    FreeAndNil(S); S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);
    Enter(S,Replies); B:=Replies[3];
    Check(L.Progress(S).TotalEXP=TB1008Balance.SpiderEXP,'EXP missing after reconnect');
    ExpectedList:=TB1008InventoryWire.BuildBagList(1,1,L.Items(S));
    Check((B[0]=6) and (B[1]=5) and (B[11]=ExpectedList[11]+5) and
      CompareMem(@B[12],@ExpectedList[12],Length(ExpectedList)-12),'Bag stacks and five starters missing after reconnect');
    B:=Replies[4];
    Check((Length(B)=46) and (B[0]=6) and (B[1]=6) and (B[11]=3) and
      (B[12]=$3F) and (B[26]=Awards[0].Amount),'Wallet update missing after inventory initialization');
    S.HandlePacket(TBytes.Create(4,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),Replies);
    Check(Length(Replies)=0,'Repeated Regen duplicated restored currency');
  finally S.Free; C.Free; L.Free; end;
  Writeln('PASS: death/drop/pickup session, distance/identity guards, no duplicate grant, reconnect inventory');
end;

procedure RapidPickupTests;
var L:TB1008LootStore;C:TB1008CharacterStore;S:TEmulatorSession;
  P:TBytes;Replies:TB1008Replies;D:TB1008GroundDrop;Ground:TArray<TB1008GroundDrop>;
  R:TB1008Pickup;N,Count:Cardinal;I,J,Slot:Integer;Desc:string;Found:Boolean;
begin
  L:=TB1008LootStore.Create('',FixtureRates);C:=TB1008CharacterStore.Create;S:=nil;
  try
    C.CreateCharacter(Hero,P);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);Enter(S,Replies);
    Check(L.CollectItem(S,'burst-seed',54004,100,N),'Burst seed');
    Check(L.CollectItem(S,'burst-extra',54004,23,N),'Burst overflow seed');
    Check(L.CollectItem(S,'similar-potion',54005,17,N),'Similar potion seed');
    for I:=1 to 25 do begin
      Slot:=-1;
      for var Item in L.Items(S) do if (Item.ItemID=54004) and (Item.Amount<100) then Slot:=Item.Slot;
      if Slot<0 then Slot:=L.Item(S,54004).Slot;
      D:=Default(TB1008GroundDrop);D.ID:=I;D.OwnerID:=1;D.Receipt:='burst-ground-'+IntToStr(I);
      D.X:=8669.776367;D.Z:=6668.010254;D.Y:=604.350342;
      Check(L.ThrowItem(S,'burst-throw-'+IntToStr(I),Slot,54004,1,D,N),'Burst ground seed');
    end;
    Check(L.Item(S,54004).Amount=98,'Burst starts at98');
    FreeAndNil(S);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);Enter(S,Replies);
    Ground:=L.GroundItems(S);Check(Length(Ground)=25,'Burst restored drops');
    S.HandlePacket(MoveTo(8669.776367),Replies);S.PollWorld(GetTickCount64,Replies);J:=0;
    for P in Replies do if (P[0]=6) and (P[1]=4) then begin
      Ground[J].ID:=TB1008Wire.ReadBE32(P,10);Inc(J);
    end;
    Check(J=25,'Burst ground publication');
    R:=Default(TB1008Pickup);R.CharacterID:=1;R.Timestamp:=777;R.ItemID:=54004;R.Code:=$33;
    // Same timestamp, no delays: each distinct ground receipt must update its cell.
    for I:=0 to High(Ground) do begin
      R.DropID:=Ground[I].ID;Desc:=S.HandlePacket(TB1008LootWire.BuildPickup(R),Replies);
      Check((Pos('LOOT PICKED UP',Desc)>0) and (Pos('slot=',Desc)>0),Desc);
      Check((Replies[High(Replies)][1]=3) and (Length(Replies)>=2),'Burst ACK order');
      for J:=0 to High(Replies)-1 do begin
        Check((Replies[J][1]=6) and (Replies[J][10]=1),'Burst cell update');
        Move(Replies[J][26],Count,4);Found:=False;
        for var Item in L.Items(S) do if Item.Slot=Replies[J][11] then begin
          Found:=True;Check((Item.ItemID=54004) and (Item.Amount=Count),'Burst absolute quantity differs from durable cell');
        end;
        Check(Found,'Burst updated missing cell');
      end;
      S.HandlePacket(TB1008LootWire.BuildPickup(R),Replies);Check(Length(Replies)=0,'Burst duplicate granted');
    end;
    N:=0;for var Item in L.Items(S) do if Item.ItemID=54004 then Inc(N,Item.Amount);
    Check((N=123) and (L.Item(S,54005).Amount=17),'Burst total or similar potion changed');
    FreeAndNil(S);S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);Enter(S,Replies);
    N:=0;for var Item in L.Items(S) do if Item.ItemID=54004 then Inc(N,Item.Amount);
    Check((N=123) and (Length(L.GroundItems(S))=0),'Burst reopen lost quantity or ground cleanup');
  finally S.Free;C.Free;L.Free;end;
  Writeln('PASS:25 immediate pickups,98->100->new stack, absolute per-cell updates, similar potion unchanged, replay/reentry');
end;

procedure AutomaticPatrolTests;
var C: TB1008CharacterStore; S: TEmulatorSession; P: TBytes;
  Replies: TB1008Replies; T: UInt64; Found: Boolean;
begin
  C:=TB1008CharacterStore.Create; S:=nil;
  try
    C.CreateCharacter(Hero,P); S:=TEmulatorSession.Create(blMapLoadingProbe,C);
    Enter(S,Replies); T:=GetTickCount64;
    S.PollWorld(T+100,Replies); Check(Length(Replies)=0,'Patrol during loading grace');
    S.PollWorld(T+300,Replies); S.PollWorld(T+700,Replies);
    Found:=False;
    for P in Replies do if (P[0]=4) and (P[1]=1) then Found:=True;
    Check(Found,'Patrol still requires player input');
  finally S.Free; C.Free; end;
  Writeln('PASS: automatic patrol after loading grace, no mandatory player movement');
end;

procedure ProgressTests;
var Dir,Path: string; G: TGUID; L: TB1008LootStore; O,Other: TObject;
  DB: TFDConnection; XP: TB1008Progress; P,B: TBytes; I: Integer; Failed: Boolean;
  C: TB1008CharacterStore; S: TEmulatorSession; Replies: TB1008Replies;
begin
  CreateGUID(G); Dir:=TPath.Combine(TPath.GetTempPath,'KarosEXP-'+GUIDToString(G));
  TDirectory.CreateDirectory(Dir); Path:=TPath.Combine(Dir,'player.sqlite3');
  L:=nil; DB:=nil; C:=nil; S:=nil; O:=TObject.Create; Other:=TObject.Create;
  try
    L:=TB1008LootStore.Create(Path,FixtureRates); L.Acquire(O,Preview);
    XP:=L.Progress(O); Check((XP.Level=1) and (XP.CurrentEXP=0),'Initial EXP');
    // Pin boundary/replay fixtures independently of live monster rewards.
    XP:=L.RecordMobEXP(O,'kill1',10,1); Check(XP.TotalEXP=10,'First kill EXP');
    XP:=L.RecordMobEXP(O,'kill1',10,1); Check(XP.TotalEXP=10,'Duplicate kill EXP');
    Failed:=False; try L.RecordMobEXP(Other,'foreign',10,1); except on E:Exception do Failed:=True; end;
    Check(Failed and (L.Progress(O).TotalEXP=10),'EXP ownership');
    DB:=TFDConnection.Create(nil); DB.LoginPrompt:=False;
    DB.Params.Values['DriverID']:='SQLite'; DB.Params.Values['Database']:=Path; DB.Connected:=True;
    DB.ExecSQL('CREATE TRIGGER fail_exp BEFORE INSERT ON exp_receipts BEGIN SELECT RAISE(ABORT,''test EXP failure''); END');
    Failed:=False; try L.RecordMobEXP(O,'kill2',10,1); except on E:Exception do Failed:=True; end;
    Check(Failed and (L.Progress(O).TotalEXP=10),'EXP write not atomic');
    DB.ExecSQL('DROP TRIGGER fail_exp'); FreeAndNil(DB);
    FreeAndNil(L); L:=TB1008LootStore.Create(Path,FixtureRates); L.Acquire(O,Preview);
    XP:=L.RecordMobEXP(O,'kill1',10,1); Check(XP.TotalEXP=10,'EXP/replay lost across reopen');
    for I:=2 to 4 do XP:=L.RecordMobEXP(O,'kill'+IntToStr(I),10,1);
    Check((XP.Level=1) and (XP.CurrentEXP=40),'Early level-up');
    P:=TB1008ProgressWire.BuildHeroGage(1,4321,123,XP);
    B:=TB1008CombatWire.BuildPlayerGageProbe(1,4321,123,1);
    Check((Length(P)=101) and CompareMem(@P[11],@B[11],38) and
      (P[$3D]=40) and (P[$45]=48),'EXP overwrote combat fields or wrong LE offsets');
    XP:=L.RecordMobEXP(O,'kill5',10,1); Check((XP.Level=2) and (XP.CurrentEXP=2),'Fifth kill level-up');
    XP:=L.RecordMobEXP(O,'kill6',10,1); Check(XP.TotalEXP=60,'EXP continues after level 2');
    P:=TB1008ProgressWire.BuildHeroGage(9,4000,99,XP);
    Check((P[39]=2) and (P[$3D]=12) and (P[$45]=216),'Level-up gage');
    B:=TB1008CombatWire.BuildPlayerGageProbe(10,3990,99,XP.Level);
    Check(B[39]=2,'Damage resets level');
    P:=Preview; B:=Copy(P); TB1008ProgressWire.ApplyPreview(P,XP);
    Check((P[$35]=2) and (B[$35]=1),'Preview level or immutable identity');
    // A real new session must show level 2 in all three entry records.
    L.Release(O); C:=TB1008CharacterStore.Create; C.CreateCharacter(Hero,P);
    S:=TEmulatorSession.Create(blMapLoadingProbe,C,nil,nil,nil,L);
    S.HandlePacket(TBytes.Create(2,0,1,2,3,4,0,14,0,0,116,101,115,116,0,116,101,115,116,0,0),Replies);
    Check(Replies[1][$35]=2,'Selection preview not restored');
    S.HandlePacket(TBytes.Create(2,4,0,0,0,1,0,0,0,1,0,0,0,0),Replies);
    Check((Replies[0][$30]=2) and (Replies[0][$46]=12) and (Replies[0][$4E]=216),'Initial CharInfo not restored');
    Enter(S,Replies); Check(Replies[0][56]=2,'Appearance resets saved level');
  finally
    S.Free; C.Free; DB.Free; L.Free; O.Free; Other.Free;
    if FileExists(Path) then TFile.Delete(Path);
    if FileExists(Path+'-wal') then TFile.Delete(Path+'-wal');
    if FileExists(Path+'-shm') then TFile.Delete(Path+'-shm');
    TDirectory.Delete(Dir,False);
  end;
  Writeln('PASS: EXP 10/48, atomic receipts/replay/reopen, level-up, restored preview/world, damage preserves level');
end;
begin
  try WireTests; StoreTests; MigrationTests; BagTests; EquipmentThrowTests; CleanerTests; MultiStackTests;
    SplitTests;SplitSessionTests;MergeTests;MergeSessionTests;
    SessionTests;SessionTests(True);RapidPickupTests;ProgressTests;AutomaticPatrolTests;
  except on E:Exception do begin Writeln('FAIL: ',E.ClassName,': ',E.Message); ExitCode:=1; end; end;
end.
