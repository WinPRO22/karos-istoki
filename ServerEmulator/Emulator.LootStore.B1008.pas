unit Emulator.LootStore.B1008;

interface

uses System.SysUtils, System.SyncObjs, FireDAC.Comp.Client, FireDAC.Phys.SQLite,
  Emulator.Loot.B1008, Emulator.Progression.B1008, Emulator.Fletta.B1008,
  Emulator.Equipment.B1008, Emulator.Shop.B1008, Emulator.Skills.B1008, Emulator.QuickSlots.B1008,
  Emulator.Rates.B1008,Emulator.QuestCatalog.B1008,Emulator.Stash.B1008,Emulator.Return.B1008,
  Emulator.Profession.B1008,Emulator.ProfessionSkills.B1008,Emulator.ItemProperties.B1008,Emulator.Crafting.B1008,
  Emulator.ItemEnhancement.B1008;

type
  // A separate additive player store. Existing character/quest files are untouched.
  // Each receipt and inventory increment commit together before any client reply.
  TB1008LootStore = class
  private
    FLock: TCriticalSection;
    FDB: TFDConnection;
    FDriver: TFDPhysSQLiteDriverLink;
    FOwner: TObject;
    FPropertiesReady:Boolean;
    FRates:TB1008Rates;
    function InstanceColumn:string;
    function GetRates:TB1008Rates;
    procedure RequireOwner(Owner: TObject);
    function FindItem(ItemID: Cardinal): TB1008BagItem;
    function FindSlot(Slot: Byte): TB1008BagItem;
    function FreeSlot(Preferred: Byte): Byte;
    procedure SaveItem(var Item: TB1008BagItem);
    function ReadProperties(InstanceID:Int64):TB1008ItemProperties;
    procedure EnsureProperties(ItemID:Cardinal;var Properties:TB1008ItemProperties);
    procedure SaveProperties(ItemID:Cardinal;var Properties:TB1008ItemProperties);
    procedure MigrateItemInstances;
    function ReadStashSlot(Slot:Byte):TB1008BagItem;
    procedure SaveStashItem(var Item:TB1008BagItem);
    function ReadProgress: TB1008Progress;
    procedure AwardSkillLevels(Level:Word);
    function ReadLearnedSkills:TArray<TB1008LearnedSkill>;
    function TrainingPrerequisitesMet(const Training:TB1008SkillTraining):Boolean;
    function ReadEquipment: TArray<TB1008EquipmentItem>;
    function ReadClassState:TB1008ClassState;
    function ReadFlettaAttributes:TB1008FlettaAttributes;
    function LimitFletta(Level:Word):TB1008Fletta;
    function RecordEXP(Owner: TObject; const Receipt: string; Amount: Integer;
      MonsterLevel: Integer = 0): TB1008Progress;
    function ReadQuest(ID:Cardinal):TB1008QuestEntry;
    function AddQuestItem(ID,Amount:Cardinal;var Updated:TArray<TB1008BagItem>):Boolean;
    function QuestItemAmount(ID,RequiredGemID:Cardinal):Int64;
    function TakeQuestItem(ID,Amount:Cardinal;var Updated:TArray<TB1008BagItem>;RequiredGemID:Cardinal=0):Boolean;
  public
    function MineQuestItem(Owner:TObject;const Receipt:string;
      out Updated:TArray<TB1008BagItem>):Byte;
    function EnhanceItem(Owner:TObject;const Receipt:string;const Request:TB1008EnhancementRequest;
      out Updated:TArray<TB1008BagItem>;out Gear:TB1008EquipmentItem):Byte;
    function CraftItem(Owner:TObject;const Receipt:string;const Request:TB1008CraftRequest;
      out Updated:TArray<TB1008BagItem>):Byte;
    constructor Create(const Path: string = '');overload;
    constructor Create(const Path:string;const Rates:TB1008Rates);overload;
    property Rates:TB1008Rates read GetRates;
    procedure UpdateRates(const Value:TB1008Rates);
    destructor Destroy; override;
    function Acquire(Owner: TObject; const Preview: TBytes): Boolean;
    procedure Release(Owner: TObject);
    function Progress(Owner: TObject): TB1008Progress;
    function ClassState(Owner:TObject):TB1008ClassState;
    function PreviewClass(const Preview:TBytes):TB1008ClassState;
    function ChangeClass(Owner:TObject;const Receipt:string;const Request:TB1008ClassChange;
      out State:TB1008ClassState;out Updated:TArray<TB1008BagItem>):Word;
    function SkillPoints(Owner:TObject):Cardinal;
    procedure GrantTestProgress(Owner:TObject;const Receipt:string;Level:Word;FreeSP:Cardinal);
    function LearnedSkills(Owner:TObject):TArray<TB1008LearnedSkill>;
    function LearnSkill(Owner:TObject;const Receipt:string;
      const Request:TB1008SkillLearn):TB1008SkillLearnResult;
    function UpgradeSkill(Owner:TObject;const Receipt:string;
      const Request:TB1008SkillUpgrade;out Rank:Cardinal):TB1008SkillUpgradeResult;
    function QuickSlots(Owner:TObject):TArray<TB1008QuickSlot>;
    function SetQuickSlot(Owner:TObject;const Request:TB1008QuickSlotRequest):Boolean;
    function Fletta(Owner: TObject): TB1008Fletta;
    function FlettaAttributes(Owner:TObject):TB1008FlettaAttributes;
    function InvestFletta(Owner:TObject;const Receipt:string;
      const Request:TB1008FlettaInvestment;out Free:TB1008Fletta;
      out Attributes:TB1008FlettaAttributes):TB1008FlettaInvestmentResult;
    function PreviewProgress(const Preview: TBytes): TB1008Progress;
    function Equipment(Owner: TObject): TArray<TB1008EquipmentItem>;
    function PreviewEquipment(const Preview: TBytes): TArray<TB1008EquipmentItem>;
    function TransferEquipment(Owner:TObject;const Receipt:string;ClassID:Word;
      const Request:TB1008EquipmentRequest;out Bag:TB1008BagItem):Boolean;
    function RecordSpiderEXP(Owner: TObject; const Receipt: string): TB1008Progress;
    function RecordMobEXP(Owner:TObject;const Receipt:string;Amount,MonsterLevel:Integer):TB1008Progress;
    function RecordQuestEXP(Owner: TObject; QuestID: Cardinal): TB1008Progress;
    function QuestEntries(Owner:TObject):TArray<TB1008QuestEntry>;
    function QuestDropNeeds(Owner:TObject;ModelID:Cardinal):TArray<TB1008QuestDropNeed>;
    function AcceptQuest(Owner:TObject;ID:Cardinal;LegacyActive:Boolean;
      out Updated:TArray<TB1008BagItem>):Boolean;
    function PerformQuest(Owner:TObject;ID,Kind,Target,Count:Cardinal;
      out Update:TB1008QuestUpdate):Boolean;
    function RecordQuestKill(Owner:TObject;const Receipt:string;ModelID:Cardinal):TArray<TB1008QuestUpdate>;
    function RewardQuest(Owner:TObject;ID,Choice:Cardinal;
      out Updated:TArray<TB1008BagItem>;out Progress:TB1008Progress):Boolean;
    function RecordDeath(Owner: TObject; const Receipt: string): TB1008Progress;
    function PendingDeath(Owner: TObject): Boolean;
    procedure CompleteRespawn(Owner: TObject);
    function Count(Owner: TObject): Cardinal;
    function Balance(Owner: TObject): Cardinal;
    function Items(Owner: TObject): TArray<TB1008BagItem>;
    function StashItems(Owner:TObject):TArray<TB1008BagItem>;
    function ReturnState(Owner:TObject):TB1008ReturnState;
    procedure BindReturn(Owner:TObject);
    function UseReturn(Owner:TObject;const Receipt:string;Slot:Byte;NowMS:Int64=-1):Boolean;
    procedure CompleteReturn(Owner:TObject);
    function TransferStash(Owner:TObject;const Receipt:string;const Request:TB1008StashRequest;
      out NewAmount:Cardinal;out Updated:TArray<TB1008BagItem>):Boolean;overload;
    function TransferStash(Owner:TObject;const Receipt:string;const Request:TB1008StashRequest;
      out NewAmount:Cardinal;out Updated,StashUpdated:TArray<TB1008BagItem>):Boolean;overload;
    function Item(Owner: TObject; ItemID: Cardinal): TB1008BagItem;
    procedure ImportRewards(Owner: TObject; Healing,Mana: Cardinal);
    function RewardFarm(Owner:TObject;Healing,Mana:Cardinal;
      out Updated:TArray<TB1008BagItem>;out Progress:TB1008Progress):Boolean;
    function Swap(Owner: TObject; Source,Target: Byte; SourceID,TargetID: Cardinal): Boolean;
    function SplitItem(Owner: TObject; const Receipt: string; Slot: Byte;
      ItemID: Cardinal; ExpectedCount: UInt64; Amount: Int64;
      out Source, Created: TB1008BagItem): Boolean;
    function MergeItems(Owner: TObject; const Receipt: string; SourceSlot,TargetSlot: Byte;
      ItemID: Cardinal; out Source,Target: TB1008BagItem): Boolean;
    function ThrowItem(Owner: TObject; const Operation: string; Slot: Byte;
      ItemID: Cardinal; Amount: Int64; var Drop: TB1008GroundDrop;
      out Remaining: Cardinal): Boolean;
    function GroundItems(Owner: TObject): TArray<TB1008GroundDrop>;
    procedure RemoveGround(Owner: TObject; const Receipt: string);
    function Consume(Owner: TObject; Slot: Byte; ItemID: Cardinal; out Remaining: Cardinal;
      NowMS:Int64=-1): Boolean;
    function SellItem(Owner:TObject;const Receipt:string;const Request:TB1008ShopSell;
      out Source,Wallet:TB1008BagItem;out Paid:Cardinal):Boolean;
    function BuyItem(Owner:TObject;const Receipt:string;const Request:TB1008ShopBuy;
      out Updated:TArray<TB1008BagItem>;out Wallet:TB1008BagItem;out Paid:Cardinal):Boolean;
    function Collect(Owner: TObject; const Receipt: string; out NewCount: Cardinal): Boolean;
    function CollectItem(Owner: TObject; const Receipt: string; ItemID,Amount: Cardinal;
      out NewCount: Cardinal): Boolean; overload;
    function CollectItem(Owner: TObject; const Receipt: string; ItemID,Amount: Cardinal;
      out NewCount: Cardinal;out Updated:TArray<TB1008BagItem>): Boolean; overload;
  end;

implementation

uses System.IOUtils, System.Hash, System.Variants, FireDAC.Stan.Def,
  FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.DApt, FireDAC.Phys.SQLiteDef,
  Emulator.Protocol.B1008, Emulator.Balance.B1008, Emulator.Items.B1008,Emulator.Inventory.B1008,Emulator.Npcs.B1008;

constructor TB1008LootStore.Create(const Path: string);
begin Create(Path,TB1008Rates.Default);end;

function TB1008LootStore.GetRates:TB1008Rates;
begin
  FLock.Acquire;
  try Result:=FRates;finally FLock.Release;end;
end;

procedure TB1008LootStore.UpdateRates(const Value:TB1008Rates);
begin
  Value.Validate;
  // Publish the complete profile between store operations. Existing grants,
  // receipts, inventory and already-created ground items are not recalculated.
  FLock.Acquire;
  try FRates:=Value;finally FLock.Release;end;
end;

constructor TB1008LootStore.Create(const Path:string;const Rates:TB1008Rates);
var Vendor, SavedSignature: string; Version: Integer;D:TB1008ItemDefinition;Q:TFDQuery;
  SeedProgress:TB1008Progress;HighestEXP:Int64;
begin
  inherited Create;
  Rates.Validate;FRates:=Rates;
  FLock:=TCriticalSection.Create;
  FDriver:=TFDPhysSQLiteDriverLink.Create(nil);
  FDB:=TFDConnection.Create(nil);
  Vendor:=TPath.Combine(ExtractFilePath(ParamStr(0)),'sqlite3.dll');
  if FileExists(Vendor) then FDriver.VendorLib:=Vendor;
  FDB.LoginPrompt:=False;
  FDB.Params.Values['DriverID']:='SQLite';
  if Path='' then FDB.Params.Values['Database']:=':memory:'
  else begin
    ForceDirectories(ExtractFileDir(ExpandFileName(Path)));
    FDB.Params.Values['Database']:=ExpandFileName(Path);
  end;
  FDB.Params.Values['LockingMode']:='Normal';
  FDB.Params.Values['JournalMode']:='WAL';
  FDB.Params.Values['Synchronous']:='Full';
  FDB.Params.Values['BusyTimeout']:='5000';
  FDB.Connected:=True;
  Version:=Integer(FDB.ExecSQLScalar('PRAGMA user_version'));
  if Version>39 then
    raise Exception.Create('Unsupported loot database version; preserved');
  FDB.StartTransaction;
  try
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS hero (id INTEGER PRIMARY KEY CHECK(id=1), identity TEXT NOT NULL)');
    if Version<3 then FDB.ExecSQL('CREATE TABLE IF NOT EXISTS inventory (slot INTEGER PRIMARY KEY CHECK(slot=2), '+
      'item_id INTEGER NOT NULL CHECK(item_id=90004), amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 99))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS pickups (receipt TEXT PRIMARY KEY NOT NULL)');
    if Version<2 then begin
      FDB.ExecSQL('ALTER TABLE pickups ADD COLUMN item_id INTEGER NOT NULL DEFAULT 90004');
      FDB.ExecSQL('ALTER TABLE pickups ADD COLUMN amount INTEGER NOT NULL DEFAULT 1');
    end;
    if Version<3 then FDB.ExecSQL('CREATE TABLE IF NOT EXISTS wallet (id INTEGER PRIMARY KEY CHECK(id=1), '+
      'amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 100000000))');
    if Version<3 then begin
      // Retain the old physical tables as migration backups; no hero data is deleted.
      FDB.ExecSQL('ALTER TABLE inventory RENAME TO inventory_v2_backup');
      FDB.ExecSQL('ALTER TABLE wallet RENAME TO wallet_v2_backup');
      FDB.ExecSQL('CREATE TABLE inventory (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 19), '+
        'item_id INTEGER NOT NULL UNIQUE CHECK(item_id IN (90004,999999,54006,54206)), '+
        'amount INTEGER NOT NULL CHECK(amount>0 AND amount<=CASE item_id WHEN 999999 THEN 100000000 ELSE 99 END))');
      FDB.ExecSQL('INSERT INTO inventory SELECT slot,item_id,amount FROM inventory_v2_backup');
      FDB.ExecSQL('INSERT INTO inventory SELECT 3,999999,amount FROM wallet_v2_backup');
      FDB.ExecSQL('CREATE VIEW wallet AS SELECT 1 AS id,amount FROM inventory WHERE item_id=999999');
    end;
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS operations (receipt TEXT PRIMARY KEY NOT NULL)');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS ground (receipt TEXT PRIMARY KEY NOT NULL, '+
      'item_id INTEGER NOT NULL, amount INTEGER NOT NULL CHECK(amount>0), x REAL NOT NULL,z REAL NOT NULL,y REAL NOT NULL)');
    if Version<4 then begin
      FDB.ExecSQL('ALTER TABLE ground ADD COLUMN expires_ms BIGINT NOT NULL DEFAULT 0');
      // Existing pre-cleaner drops get one 30-second grace period on migration.
      FDB.ExecSQL('UPDATE ground SET expires_ms=:t',[B1008UtcNowMS+B1008ThrownLootLifetimeMS]);
    end;
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS progression (id INTEGER PRIMARY KEY CHECK(id=1), '+
      'total_exp INTEGER NOT NULL CHECK(total_exp BETWEEN 0 AND 100))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS exp_receipts (receipt TEXT PRIMARY KEY NOT NULL, '+
      'amount INTEGER NOT NULL CHECK(amount BETWEEN 0 AND 10))');
    if Version<6 then begin
      // Preserve old tables, inventory and receipt identities. Preserve level
      // and fractional progress, not the old diagnostic 10/100 exchange rate.
      FDB.ExecSQL('ALTER TABLE progression RENAME TO progression_v5_backup');
      FDB.ExecSQL('ALTER TABLE exp_receipts RENAME TO exp_receipts_v5_backup');
      FDB.ExecSQL('CREATE TABLE progression (id INTEGER PRIMARY KEY CHECK(id=1), total_exp INTEGER NOT NULL CHECK(total_exp>=0))');
      FDB.ExecSQL('INSERT INTO progression SELECT id, CASE WHEN total_exp=100 THEN :threshold ELSE total_exp*:threshold/100 END FROM progression_v5_backup',
        [TB1008Balance.Threshold(1)]);
      FDB.ExecSQL('CREATE TABLE exp_receipts (receipt TEXT PRIMARY KEY NOT NULL, amount INTEGER NOT NULL CHECK(amount>=0))');
      FDB.ExecSQL('INSERT INTO exp_receipts SELECT receipt,amount FROM exp_receipts_v5_backup');
    end;
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS balance_meta (id INTEGER PRIMARY KEY CHECK(id=1), progression_signature TEXT NOT NULL)');
    SavedSignature:=VarToStr(FDB.ExecSQLScalar('SELECT progression_signature FROM balance_meta WHERE id=1'));
    if SavedSignature='' then
      FDB.ExecSQL('INSERT INTO balance_meta VALUES(1,:s)',[TB1008Balance.ProgressionSignature])
    else if (Version<22) and (TB1008Balance.LevelCap in [30,45]) and
      (SavedSignature=TB1008Balance.ProgressionSignature(20)) then
      // Explicit append-only 20 -> current cap: old thresholds/EXP stay exact.
      FDB.ExecSQL('UPDATE balance_meta SET progression_signature=:s WHERE id=1',[TB1008Balance.ProgressionSignature])
    else if (Version<38) and (TB1008Balance.LevelCap=45) and
      (SavedSignature=TB1008Balance.ProgressionSignature(30)) then
      // Append-only continuation: all existing thresholds and total EXP retained.
      FDB.ExecSQL('UPDATE balance_meta SET progression_signature=:s WHERE id=1',[TB1008Balance.ProgressionSignature])
    else if SavedSignature<>TB1008Balance.ProgressionSignature then
      raise Exception.Create('Progression curve changed: explicit player migration required; database preserved');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS death_receipts (receipt TEXT PRIMARY KEY NOT NULL, '+
      'loss INTEGER NOT NULL CHECK(loss>=0), before_exp INTEGER NOT NULL CHECK(before_exp>=0), '+
      'after_exp INTEGER NOT NULL CHECK(after_exp>=0 AND after_exp<=before_exp))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS death_state (id INTEGER PRIMARY KEY CHECK(id=1), '+
      'receipt TEXT NOT NULL REFERENCES death_receipts(receipt), pending INTEGER NOT NULL CHECK(pending IN (0,1)))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS fletta (id INTEGER PRIMARY KEY CHECK(id=1), '+
      'total INTEGER NOT NULL CHECK(total BETWEEN 0 AND 21474836479999))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS fletta_receipts (receipt TEXT PRIMARY KEY NOT NULL, '+
      'amount INTEGER NOT NULL CHECK(amount BETWEEN 0 AND 10000))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS fletta_attributes (category INTEGER PRIMARY KEY CHECK(category=1), '+
      'attribute INTEGER NOT NULL CHECK(attribute=1), invested INTEGER NOT NULL CHECK(invested BETWEEN 1 AND 10))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS fletta_investments (receipt TEXT PRIMARY KEY NOT NULL, '+
      'category INTEGER NOT NULL CHECK(category=1), attribute INTEGER NOT NULL CHECK(attribute=1), '+
      'amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 10))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS equipment (slot INTEGER PRIMARY KEY CHECK(slot IN (1,2,3,4,7)), '+
      'item_id INTEGER NOT NULL UNIQUE CHECK(item_id IN (1001,9001,13001,32001,32401,32801,33201,36001,36401,36801,37201,40001,40401,40801,41201)))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS starter_equipment (id INTEGER PRIMARY KEY CHECK(id=1), '+
      'class_id INTEGER NOT NULL CHECK(class_id IN (100,300,500)), revision INTEGER NOT NULL CHECK(revision=1))');
    if Version<10 then begin
      FDB.ExecSQL('DROP VIEW wallet');
      FDB.ExecSQL('ALTER TABLE inventory RENAME TO inventory_v9_backup');
      FDB.ExecSQL('CREATE TABLE inventory (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 19), '+
        'item_id INTEGER NOT NULL UNIQUE CHECK(item_id IN (90004,999999,54006,54206,1001,9001,13001,32001,32401,32801,33201,36001,36401,36801,37201,40001,40401,40801,41201)), '+
        'amount INTEGER NOT NULL CHECK(amount>0 AND amount<=CASE WHEN item_id=999999 THEN 100000000 '+
        'WHEN item_id IN (90004,54006,54206) THEN 99 ELSE 1 END))');
      FDB.ExecSQL('INSERT INTO inventory SELECT slot,item_id,amount FROM inventory_v9_backup');
      FDB.ExecSQL('CREATE VIEW wallet AS SELECT 1 AS id,amount FROM inventory WHERE item_id=999999');
    end;
    if Version<11 then begin
      FDB.ExecSQL('DROP VIEW wallet');
      FDB.ExecSQL('ALTER TABLE inventory RENAME TO inventory_v10_backup');
      FDB.ExecSQL('CREATE TABLE inventory (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 19), '+
        'item_id INTEGER NOT NULL CHECK(item_id IN (90004,999999,54006,54206,1001,9001,13001,32001,32401,32801,33201,36001,36401,36801,37201,40001,40401,40801,41201)), '+
        'amount INTEGER NOT NULL CHECK(amount>0 AND amount<=CASE WHEN item_id=999999 THEN 100000000 '+
        'WHEN item_id=90004 THEN 100 WHEN item_id IN (54006,54206) THEN 99 ELSE 1 END))');
      // Stackable items may occupy multiple cells. Currency and our unique
      // starter gear retain their previous one-instance invariant.
      FDB.ExecSQL('CREATE UNIQUE INDEX inventory_unique_items ON inventory(item_id) WHERE item_id NOT IN (90004,54006,54206)');
      FDB.ExecSQL('INSERT INTO inventory SELECT slot,item_id,amount FROM inventory_v10_backup');
      FDB.ExecSQL('CREATE VIEW wallet AS SELECT 1 AS id,amount FROM inventory WHERE item_id=999999');
    end;
    if Version<13 then begin
      // Widen the supported independent axes; keep the previous Yang data
      // and receipt tables as migration backups, never reset invested FP.
      FDB.ExecSQL('ALTER TABLE fletta_attributes RENAME TO fletta_attributes_v12_backup');
      FDB.ExecSQL('CREATE TABLE fletta_attributes (category INTEGER PRIMARY KEY, '+
        'attribute INTEGER NOT NULL, invested INTEGER NOT NULL CHECK(invested BETWEEN 1 AND 10), '+
        'CHECK((category=1 AND attribute=1) OR (category=2 AND attribute=2)))');
      FDB.ExecSQL('INSERT INTO fletta_attributes SELECT * FROM fletta_attributes_v12_backup');
      FDB.ExecSQL('ALTER TABLE fletta_investments RENAME TO fletta_investments_v12_backup');
      FDB.ExecSQL('CREATE TABLE fletta_investments (receipt TEXT PRIMARY KEY NOT NULL, '+
        'category INTEGER NOT NULL, attribute INTEGER NOT NULL, amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 10), '+
        'CHECK((category=1 AND attribute=1) OR (category=2 AND attribute=2)))');
      FDB.ExecSQL('INSERT INTO fletta_investments SELECT * FROM fletta_investments_v12_backup');
    end;
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS item_catalog (item_id INTEGER PRIMARY KEY, stack_limit INTEGER NOT NULL)');
    for D in TB1008Items.All do FDB.ExecSQL('INSERT INTO item_catalog VALUES(:i,:n) '+
      'ON CONFLICT(item_id) DO UPDATE SET stack_limit=excluded.stack_limit',[Int64(D.ID),Int64(D.StackLimit)]);
    if Version<14 then begin
      // Preserve v13 tables as backups; new gear can have multiple copies in
      // distinct bag cells. Currency alone retains the unique-stack invariant.
      FDB.ExecSQL('DROP VIEW wallet');
      FDB.ExecSQL('ALTER TABLE inventory RENAME TO inventory_v13_backup');
      FDB.ExecSQL('CREATE TABLE inventory (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 19), '+
        'item_id INTEGER NOT NULL, amount INTEGER NOT NULL CHECK(amount>0))');
      FDB.ExecSQL('CREATE UNIQUE INDEX inventory_currency_unique ON inventory(item_id) WHERE item_id=999999');
      FDB.ExecSQL('CREATE TRIGGER inventory_catalog_insert BEFORE INSERT ON inventory BEGIN '+
        'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM item_catalog WHERE item_id=NEW.item_id AND NEW.amount<=stack_limit) '+
        'THEN RAISE(ABORT,''Invalid catalog item or amount'') END; END');
      FDB.ExecSQL('CREATE TRIGGER inventory_catalog_update BEFORE UPDATE ON inventory BEGIN '+
        'SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM item_catalog WHERE item_id=NEW.item_id AND NEW.amount<=stack_limit) '+
        'THEN RAISE(ABORT,''Invalid catalog item or amount'') END; END');
      FDB.ExecSQL('INSERT INTO inventory SELECT * FROM inventory_v13_backup');
      FDB.ExecSQL('CREATE VIEW wallet AS SELECT 1 AS id,amount FROM inventory WHERE item_id=999999');
      FDB.ExecSQL('ALTER TABLE equipment RENAME TO equipment_v13_backup');
      FDB.ExecSQL('CREATE TABLE equipment (slot INTEGER PRIMARY KEY CHECK(slot IN (1,2,3,4,7)), item_id INTEGER NOT NULL UNIQUE)');
      FDB.ExecSQL('INSERT INTO equipment SELECT * FROM equipment_v13_backup');
    end;
    // Reject a changed/incomplete catalog rather than loading saved unknown
    // items into the client. A failed migration remains fully transactional.
    Q:=TFDQuery.Create(nil);
    try
      Q.Connection:=FDB;Q.Open('SELECT item_id,amount FROM inventory');
      while not Q.Eof do begin
        D:=TB1008Items.Get(Q.Fields[0].AsLargeInt);
        if (Q.Fields[1].AsLargeInt<1) or (Q.Fields[1].AsLargeInt>D.StackLimit) then
          raise Exception.Create('Saved inventory exceeds item stack limit');
        Q.Next;
      end;
    finally Q.Free;end;
    ReadEquipment;
    // Additive v15 migration: no inventory rewrite. Keep exact sale facts for
    // auditing; request receipt and both inventory changes commit atomically.
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS npc_sales (receipt TEXT PRIMARY KEY NOT NULL, '+
      'npc_handle INTEGER NOT NULL, slot INTEGER NOT NULL CHECK(slot BETWEEN 0 AND 19), '+
      'item_id INTEGER NOT NULL, amount INTEGER NOT NULL CHECK(amount>0), '+
      'unit_price INTEGER NOT NULL CHECK(unit_price>0), '+
      'paid INTEGER NOT NULL CHECK(paid=amount*unit_price AND paid<=100000000))');
    if Version<16 then begin
      // Preserve the complete paid-sale history while admitting zero-price
      // disposal. No repricing, inventory rewrite or automatic item removal.
      FDB.ExecSQL('ALTER TABLE npc_sales RENAME TO npc_sales_v15_backup');
      FDB.ExecSQL('CREATE TABLE npc_sales (receipt TEXT PRIMARY KEY NOT NULL, '+
        'npc_handle INTEGER NOT NULL, slot INTEGER NOT NULL CHECK(slot BETWEEN 0 AND 19), '+
        'item_id INTEGER NOT NULL, amount INTEGER NOT NULL CHECK(amount>0), '+
        'unit_price INTEGER NOT NULL CHECK(unit_price>=0), '+
        'paid INTEGER NOT NULL CHECK(paid=amount*unit_price AND paid<=100000000))');
      FDB.ExecSQL('INSERT INTO npc_sales SELECT * FROM npc_sales_v15_backup');
    end;
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS npc_purchases (receipt TEXT PRIMARY KEY NOT NULL, '+
      'npc_handle INTEGER NOT NULL,item_id INTEGER NOT NULL,amount INTEGER NOT NULL CHECK(amount>0), '+
      'unit_price INTEGER NOT NULL CHECK(unit_price>0),paid INTEGER NOT NULL CHECK(paid=amount*unit_price))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS skill_points (id INTEGER PRIMARY KEY CHECK(id=1), '+
      'highest_level INTEGER NOT NULL CHECK(highest_level BETWEEN 1 AND 20), '+
      'earned INTEGER NOT NULL CHECK(earned=highest_level-1), '+
      'spent INTEGER NOT NULL CHECK(spent BETWEEN 0 AND earned))');
    // Bootstrap only once. Death history can prove a previously reached
    // level above the current one; never grant a level twice after delevel.
    SeedProgress:=ReadProgress;
    HighestEXP:=Int64(FDB.ExecSQLScalar('SELECT COALESCE(MAX(before_exp),0) FROM death_receipts'));
    if HighestEXP>SeedProgress.TotalEXP then SeedProgress.TotalEXP:=HighestEXP;
    FDB.ExecSQL('INSERT OR IGNORE INTO skill_points(id,highest_level,earned,spent) VALUES(1,:l,:e,0)',
      [Integer(SeedProgress.Level),Integer(SeedProgress.Level)-1]);
    // v17 adds learned skills without changing EXP, earned SP or inventory.
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS learned_skills (skill_id INTEGER PRIMARY KEY CHECK(skill_id IN (1001,5001,9001)), '+
      'rank INTEGER NOT NULL CHECK(rank=1))');
    if Version<19 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS learned_skills_v18_backup AS SELECT * FROM learned_skills');
      FDB.ExecSQL('CREATE TABLE learned_skills_v19 (skill_id INTEGER PRIMARY KEY CHECK(skill_id IN (1001,5001,9001)), '+
        'rank INTEGER NOT NULL CHECK((skill_id=1001 AND rank BETWEEN 1 AND 5) OR (skill_id IN (5001,9001) AND rank=1)))');
      FDB.ExecSQL('INSERT INTO learned_skills_v19 SELECT * FROM learned_skills');
      FDB.ExecSQL('DROP TABLE learned_skills');
      FDB.ExecSQL('ALTER TABLE learned_skills_v19 RENAME TO learned_skills');
    end;
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS skill_upgrades (receipt TEXT PRIMARY KEY NOT NULL, '+
      'skill_id INTEGER NOT NULL CHECK(skill_id=1001), rank INTEGER NOT NULL CHECK(rank BETWEEN 2 AND 5), '+
      'spent INTEGER NOT NULL CHECK(spent=1))');
    if Version<20 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS learned_skills_v19_backup AS SELECT * FROM learned_skills');
      FDB.ExecSQL('CREATE TABLE learned_skills_v20 (skill_id INTEGER PRIMARY KEY CHECK(skill_id IN (1001,1003,5001,9001)), '+
        'rank INTEGER NOT NULL CHECK((skill_id=1001 AND rank BETWEEN 1 AND 5) OR (skill_id IN (1003,5001,9001) AND rank=1)))');
      FDB.ExecSQL('INSERT INTO learned_skills_v20 SELECT * FROM learned_skills');
      FDB.ExecSQL('DROP TABLE learned_skills');
      FDB.ExecSQL('ALTER TABLE learned_skills_v20 RENAME TO learned_skills');
    end;
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS skill_acquisitions (receipt TEXT PRIMARY KEY NOT NULL, '+
      'skill_id INTEGER NOT NULL UNIQUE CHECK(skill_id=1003), spent INTEGER NOT NULL CHECK(spent=1))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS starter_skills (id INTEGER PRIMARY KEY CHECK(id=1), '+
      'class_id INTEGER NOT NULL, skill_id INTEGER NOT NULL, revision INTEGER NOT NULL CHECK(revision=1), '+
      'CHECK((class_id=100 AND skill_id=1001) OR (class_id=300 AND skill_id=5001) OR (class_id=500 AND skill_id=9001)))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS quickslots (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 35), '+
      'reference_id INTEGER NOT NULL CHECK(reference_id IN (1001,5001,9001)), '+
      'source_page INTEGER NOT NULL CHECK(source_page=9), source_slot INTEGER NOT NULL CHECK(source_slot=0))');
    if Version<21 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS quickslots_v20_backup AS SELECT * FROM quickslots');
      FDB.ExecSQL('CREATE TABLE quickslots_v21 (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 35), '+
        'reference_id INTEGER NOT NULL CHECK(reference_id IN (1001,1003,5001,9001)), '+
        'source_page INTEGER NOT NULL CHECK(source_page=9), source_slot INTEGER NOT NULL, '+
        'CHECK((reference_id=1003 AND source_slot=5) OR (reference_id IN (1001,5001,9001) AND source_slot=0)))');
      FDB.ExecSQL('INSERT INTO quickslots_v21 SELECT * FROM quickslots');
      FDB.ExecSQL('DROP TABLE quickslots');
      FDB.ExecSQL('ALTER TABLE quickslots_v21 RENAME TO quickslots');
    end;
    if (Version<22) and (Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM pragma_table_info(''skill_points'') WHERE name=''bonus'''))=0) then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS skill_points_v21_backup AS SELECT * FROM skill_points');
      FDB.ExecSQL('CREATE TABLE skill_points_v22 (id INTEGER PRIMARY KEY CHECK(id=1), '+
        'highest_level INTEGER NOT NULL CHECK(highest_level BETWEEN 1 AND 30), '+
        'earned INTEGER NOT NULL CHECK(earned=highest_level-1), '+
        'spent INTEGER NOT NULL CHECK(spent BETWEEN 0 AND earned+bonus), '+
        'bonus INTEGER NOT NULL DEFAULT 0 CHECK(bonus BETWEEN 0 AND 1000))');
      FDB.ExecSQL('INSERT INTO skill_points_v22(id,highest_level,earned,spent) SELECT id,highest_level,earned,spent FROM skill_points');
      FDB.ExecSQL('DROP TABLE skill_points');
      FDB.ExecSQL('ALTER TABLE skill_points_v22 RENAME TO skill_points');
    end;
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS test_progress_grants (receipt TEXT PRIMARY KEY NOT NULL, '+
      'level INTEGER NOT NULL,free_sp INTEGER NOT NULL,before_exp INTEGER NOT NULL,after_exp INTEGER NOT NULL)');
    if Version<23 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS learned_skills_v22_backup AS SELECT * FROM learned_skills');
      FDB.ExecSQL('CREATE TABLE learned_skills_v23 (skill_id INTEGER PRIMARY KEY, rank INTEGER NOT NULL, '+
        'CHECK((skill_id IN (1001,1004,1006) AND rank BETWEEN 1 AND 5) OR (skill_id IN (1003,5001,9001) AND rank=1)))');
      FDB.ExecSQL('INSERT INTO learned_skills_v23 SELECT * FROM learned_skills');
      FDB.ExecSQL('DROP TABLE learned_skills');
      FDB.ExecSQL('ALTER TABLE learned_skills_v23 RENAME TO learned_skills');
      FDB.ExecSQL('CREATE TABLE skill_acquisitions_v23 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'skill_id INTEGER NOT NULL UNIQUE CHECK(skill_id IN (1003,1004,1006)), spent INTEGER NOT NULL CHECK(spent=1))');
      FDB.ExecSQL('INSERT INTO skill_acquisitions_v23 SELECT * FROM skill_acquisitions');
      FDB.ExecSQL('DROP TABLE skill_acquisitions');
      FDB.ExecSQL('ALTER TABLE skill_acquisitions_v23 RENAME TO skill_acquisitions');
      FDB.ExecSQL('CREATE TABLE skill_upgrades_v23 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'skill_id INTEGER NOT NULL CHECK(skill_id IN (1001,1004,1006)), '+
        'rank INTEGER NOT NULL CHECK(rank BETWEEN 2 AND 5), spent INTEGER NOT NULL CHECK(spent=1))');
      FDB.ExecSQL('INSERT INTO skill_upgrades_v23 SELECT * FROM skill_upgrades');
      FDB.ExecSQL('DROP TABLE skill_upgrades');
      FDB.ExecSQL('ALTER TABLE skill_upgrades_v23 RENAME TO skill_upgrades');
      FDB.ExecSQL('CREATE TABLE quickslots_v23 (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 35), '+
        'reference_id INTEGER NOT NULL, source_page INTEGER NOT NULL CHECK(source_page=9), source_slot INTEGER NOT NULL, '+
        'CHECK((reference_id=1003 AND source_slot=5) OR (reference_id=1004 AND source_slot=2) OR '+
        '(reference_id IN (1001,5001,9001) AND source_slot=0)))');
      FDB.ExecSQL('INSERT INTO quickslots_v23 SELECT * FROM quickslots');
      FDB.ExecSQL('DROP TABLE quickslots');
      FDB.ExecSQL('ALTER TABLE quickslots_v23 RENAME TO quickslots');
    end;
    if Version<24 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS learned_skills_v23_backup AS SELECT * FROM learned_skills');
      FDB.ExecSQL('CREATE TABLE learned_skills_v24 (skill_id INTEGER PRIMARY KEY, rank INTEGER NOT NULL, '+
        'CHECK((skill_id IN (1001,1003,1004,1006) AND rank BETWEEN 1 AND 5) OR (skill_id IN (5001,9001) AND rank=1)))');
      FDB.ExecSQL('INSERT INTO learned_skills_v24 SELECT * FROM learned_skills');
      FDB.ExecSQL('DROP TABLE learned_skills');
      FDB.ExecSQL('ALTER TABLE learned_skills_v24 RENAME TO learned_skills');
      FDB.ExecSQL('CREATE TABLE skill_upgrades_v24 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'skill_id INTEGER NOT NULL CHECK(skill_id IN (1001,1003,1004,1006)), '+
        'rank INTEGER NOT NULL CHECK(rank BETWEEN 2 AND 5), spent INTEGER NOT NULL CHECK(spent=1))');
      FDB.ExecSQL('INSERT INTO skill_upgrades_v24 SELECT * FROM skill_upgrades');
      FDB.ExecSQL('DROP TABLE skill_upgrades');
      FDB.ExecSQL('ALTER TABLE skill_upgrades_v24 RENAME TO skill_upgrades');
    end;
    if Version<25 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS learned_skills_v24_backup AS SELECT * FROM learned_skills');
      FDB.ExecSQL('CREATE TABLE learned_skills_v25 (skill_id INTEGER PRIMARY KEY, rank INTEGER NOT NULL, '+
        'CHECK((skill_id IN (1001,1003,1004,1005,1006) AND rank BETWEEN 1 AND 5) OR (skill_id IN (5001,9001) AND rank=1)))');
      FDB.ExecSQL('INSERT INTO learned_skills_v25 SELECT * FROM learned_skills');
      FDB.ExecSQL('DROP TABLE learned_skills');
      FDB.ExecSQL('ALTER TABLE learned_skills_v25 RENAME TO learned_skills');
      FDB.ExecSQL('CREATE TABLE skill_acquisitions_v25 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'skill_id INTEGER NOT NULL UNIQUE CHECK(skill_id IN (1003,1004,1005,1006)), spent INTEGER NOT NULL CHECK(spent=1))');
      FDB.ExecSQL('INSERT INTO skill_acquisitions_v25 SELECT * FROM skill_acquisitions');
      FDB.ExecSQL('DROP TABLE skill_acquisitions');
      FDB.ExecSQL('ALTER TABLE skill_acquisitions_v25 RENAME TO skill_acquisitions');
      FDB.ExecSQL('CREATE TABLE skill_upgrades_v25 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'skill_id INTEGER NOT NULL CHECK(skill_id IN (1001,1003,1004,1005,1006)), '+
        'rank INTEGER NOT NULL CHECK(rank BETWEEN 2 AND 5), spent INTEGER NOT NULL CHECK(spent=1))');
      FDB.ExecSQL('INSERT INTO skill_upgrades_v25 SELECT * FROM skill_upgrades');
      FDB.ExecSQL('DROP TABLE skill_upgrades');
      FDB.ExecSQL('ALTER TABLE skill_upgrades_v25 RENAME TO skill_upgrades');
      FDB.ExecSQL('CREATE TABLE quickslots_v25 (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 35), '+
        'reference_id INTEGER NOT NULL, source_page INTEGER NOT NULL CHECK(source_page=9), source_slot INTEGER NOT NULL, '+
        'CHECK((reference_id=1003 AND source_slot=5) OR (reference_id=1004 AND source_slot=2) OR '+
        '(reference_id=1005 AND source_slot=4) OR (reference_id IN (1001,5001,9001) AND source_slot=0)))');
      FDB.ExecSQL('INSERT INTO quickslots_v25 SELECT * FROM quickslots');
      FDB.ExecSQL('DROP TABLE quickslots');
      FDB.ExecSQL('ALTER TABLE quickslots_v25 RENAME TO quickslots');
    end;
    if Version<26 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS learned_skills_v25_backup AS SELECT * FROM learned_skills');
      FDB.ExecSQL('CREATE TABLE learned_skills_v26 (skill_id INTEGER PRIMARY KEY, rank INTEGER NOT NULL, '+
        'CHECK((skill_id IN (1001,1002,1003,1004,1005,1006) AND rank BETWEEN 1 AND 5) OR (skill_id IN (5001,9001) AND rank=1)))');
      FDB.ExecSQL('INSERT INTO learned_skills_v26 SELECT * FROM learned_skills');
      FDB.ExecSQL('DROP TABLE learned_skills');
      FDB.ExecSQL('ALTER TABLE learned_skills_v26 RENAME TO learned_skills');
      FDB.ExecSQL('CREATE TABLE skill_acquisitions_v26 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'skill_id INTEGER NOT NULL UNIQUE CHECK(skill_id IN (1002,1003,1004,1005,1006)), spent INTEGER NOT NULL CHECK(spent=1))');
      FDB.ExecSQL('INSERT INTO skill_acquisitions_v26 SELECT * FROM skill_acquisitions');
      FDB.ExecSQL('DROP TABLE skill_acquisitions');
      FDB.ExecSQL('ALTER TABLE skill_acquisitions_v26 RENAME TO skill_acquisitions');
      FDB.ExecSQL('CREATE TABLE skill_upgrades_v26 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'skill_id INTEGER NOT NULL CHECK(skill_id IN (1001,1002,1003,1004,1005,1006)), '+
        'rank INTEGER NOT NULL CHECK(rank BETWEEN 2 AND 5), spent INTEGER NOT NULL CHECK(spent=1))');
      FDB.ExecSQL('INSERT INTO skill_upgrades_v26 SELECT * FROM skill_upgrades');
      FDB.ExecSQL('DROP TABLE skill_upgrades');
      FDB.ExecSQL('ALTER TABLE skill_upgrades_v26 RENAME TO skill_upgrades');
      FDB.ExecSQL('CREATE TABLE quickslots_v26 (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 35), '+
        'reference_id INTEGER NOT NULL, source_page INTEGER NOT NULL CHECK(source_page=9), source_slot INTEGER NOT NULL, '+
        'CHECK((reference_id=1003 AND source_slot=5) OR (reference_id=1004 AND source_slot=2) OR '+
        '(reference_id=1005 AND source_slot=4) OR (reference_id=1002 AND source_slot=1) OR (reference_id IN (1001,5001,9001) AND source_slot=0)))');
      FDB.ExecSQL('INSERT INTO quickslots_v26 SELECT * FROM quickslots');
      FDB.ExecSQL('DROP TABLE quickslots');
      FDB.ExecSQL('ALTER TABLE quickslots_v26 RENAME TO quickslots');
    end;
    if Version<27 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS fletta_attributes_v26_backup AS SELECT * FROM fletta_attributes');
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS fletta_investments_v26_backup AS SELECT * FROM fletta_investments');
      FDB.ExecSQL('CREATE TABLE fletta_attributes_v27 (category INTEGER PRIMARY KEY, '+
        'attribute INTEGER NOT NULL, invested INTEGER NOT NULL CHECK(invested BETWEEN 1 AND 1600), '+
        'CHECK((category=1 AND attribute=1) OR (category=2 AND attribute=2)))');
      FDB.ExecSQL('INSERT INTO fletta_attributes_v27 SELECT * FROM fletta_attributes');
      FDB.ExecSQL('DROP TABLE fletta_attributes');
      FDB.ExecSQL('ALTER TABLE fletta_attributes_v27 RENAME TO fletta_attributes');
      FDB.ExecSQL('CREATE TABLE fletta_investments_v27 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'category INTEGER NOT NULL, attribute INTEGER NOT NULL, amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 1600), '+
        'CHECK((category=1 AND attribute=1) OR (category=2 AND attribute=2)))');
      FDB.ExecSQL('INSERT INTO fletta_investments_v27 SELECT * FROM fletta_investments');
      FDB.ExecSQL('DROP TABLE fletta_investments');
      FDB.ExecSQL('ALTER TABLE fletta_investments_v27 RENAME TO fletta_investments');
    end;
    if Version<28 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS quickslots_v27_backup AS SELECT * FROM quickslots');
      FDB.ExecSQL('CREATE TABLE quickslots_v28 (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 35), '+
        'reference_id INTEGER NOT NULL, source_page INTEGER NOT NULL, source_slot INTEGER NOT NULL, '+
        'CHECK((source_page=9 AND ((reference_id=1003 AND source_slot=5) OR '+
        '(reference_id=1004 AND source_slot=2) OR (reference_id=1005 AND source_slot=4) OR '+
        '(reference_id=1002 AND source_slot=1) OR (reference_id IN (1001,5001,9001) AND source_slot=0))) OR '+
        '(source_page=1 AND reference_id IN (54004,54005,54006,54203,54205,54206) AND source_slot BETWEEN 0 AND 19)))');
      FDB.ExecSQL('INSERT INTO quickslots_v28 SELECT * FROM quickslots');
      FDB.ExecSQL('DROP TABLE quickslots');
      FDB.ExecSQL('ALTER TABLE quickslots_v28 RENAME TO quickslots');
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS fletta_receipts_v27_backup AS SELECT * FROM fletta_receipts');
      FDB.ExecSQL('CREATE TABLE fletta_receipts_v28 (receipt TEXT PRIMARY KEY NOT NULL, amount INTEGER NOT NULL CHECK(amount>=0))');
      FDB.ExecSQL('INSERT INTO fletta_receipts_v28 SELECT * FROM fletta_receipts');
      FDB.ExecSQL('DROP TABLE fletta_receipts');
      FDB.ExecSQL('ALTER TABLE fletta_receipts_v28 RENAME TO fletta_receipts');
    end;
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS potion_cooldowns (kind INTEGER PRIMARY KEY CHECK(kind IN (0,1)), '+
      'until_ms BIGINT NOT NULL CHECK(until_ms>=0))');
    if Version<29 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS fletta_attributes_v28_backup AS SELECT * FROM fletta_attributes');
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS fletta_investments_v28_backup AS SELECT * FROM fletta_investments');
      FDB.ExecSQL('CREATE TABLE fletta_attributes_v29 (category INTEGER PRIMARY KEY, '+
        'attribute INTEGER NOT NULL, invested INTEGER NOT NULL CHECK(invested BETWEEN 1 AND 1600), '+
        'CHECK((category=1 AND attribute BETWEEN 1 AND 2) OR (category=2 AND attribute BETWEEN 1 AND 5)))');
      FDB.ExecSQL('INSERT INTO fletta_attributes_v29 SELECT * FROM fletta_attributes');
      FDB.ExecSQL('DROP TABLE fletta_attributes');
      FDB.ExecSQL('ALTER TABLE fletta_attributes_v29 RENAME TO fletta_attributes');
      FDB.ExecSQL('CREATE TABLE fletta_investments_v29 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'category INTEGER NOT NULL, attribute INTEGER NOT NULL, amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 1600), '+
        'CHECK((category=1 AND attribute BETWEEN 1 AND 2) OR (category=2 AND attribute BETWEEN 1 AND 5)))');
      FDB.ExecSQL('INSERT INTO fletta_investments_v29 SELECT * FROM fletta_investments');
      FDB.ExecSQL('DROP TABLE fletta_investments');
      FDB.ExecSQL('ALTER TABLE fletta_investments_v29 RENAME TO fletta_investments');
    end;
    // New quests share inventory/EXP transactions. The original Farm journal
    // remains the compatibility adapter; its existing files are not migrated.
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS quests (quest_id INTEGER PRIMARY KEY, '+
      'status INTEGER NOT NULL CHECK(status IN (1,2)), choice INTEGER NOT NULL DEFAULT -1)');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS quest_objectives (quest_id INTEGER NOT NULL REFERENCES quests(quest_id), '+
      'objective INTEGER NOT NULL CHECK(objective BETWEEN 0 AND 6), count INTEGER NOT NULL CHECK(count BETWEEN 0 AND 10000), '+
      'PRIMARY KEY(quest_id,objective))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS quest_kills (receipt TEXT PRIMARY KEY NOT NULL, model_id INTEGER NOT NULL)');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS personal_stash (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 31), '+
      'item_id INTEGER NOT NULL REFERENCES item_catalog(item_id), amount INTEGER NOT NULL CHECK(amount>0))');
    FDB.ExecSQL('CREATE TRIGGER IF NOT EXISTS stash_limit_insert BEFORE INSERT ON personal_stash WHEN '+
      'NEW.amount>COALESCE((SELECT stack_limit FROM item_catalog WHERE item_id=NEW.item_id),0) '+
      'BEGIN SELECT RAISE(ABORT,''Invalid stash stack''); END');
    FDB.ExecSQL('CREATE TRIGGER IF NOT EXISTS stash_limit_update BEFORE UPDATE ON personal_stash WHEN '+
      'NEW.amount>COALESCE((SELECT stack_limit FROM item_catalog WHERE item_id=NEW.item_id),0) '+
      'BEGIN SELECT RAISE(ABORT,''Invalid stash stack''); END');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS return_stone (id INTEGER PRIMARY KEY CHECK(id=1), '+
      'point INTEGER NOT NULL CHECK(point IN (0,190033)), until_ms BIGINT NOT NULL CHECK(until_ms>=0), '+
      'pending INTEGER NOT NULL CHECK(pending IN (0,1)))');
    FDB.ExecSQL('INSERT OR IGNORE INTO return_stone VALUES(1,0,0,0)');
    // Preserve the original use time when shortening old one-hour cooldowns.
    // Version gating prevents subtracting again on reconnect/restart.
    if Version<32 then
      FDB.ExecSQL('UPDATE return_stone SET until_ms=MAX(0,until_ms-3000000) WHERE until_ms>0');
    if Version<33 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS fletta_receipts_v32_backup AS SELECT * FROM fletta_receipts');
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS fletta_v32_backup AS SELECT * FROM fletta');
      // The delta includes the charging bar: rates below x1 can complete a
      // bar without awarding a whole FP yet, producing a negative bar delta.
      FDB.ExecSQL('CREATE TABLE fletta_receipts_v33 (receipt TEXT PRIMARY KEY NOT NULL, amount INTEGER NOT NULL CHECK(amount>=-9999))');
      FDB.ExecSQL('INSERT INTO fletta_receipts_v33 SELECT * FROM fletta_receipts');
      FDB.ExecSQL('DROP TABLE fletta_receipts');
      FDB.ExecSQL('ALTER TABLE fletta_receipts_v33 RENAME TO fletta_receipts');
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS npc_purchases_v32_backup AS SELECT * FROM npc_purchases');
      FDB.ExecSQL('CREATE TABLE npc_purchases_v33 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'npc_handle INTEGER NOT NULL,item_id INTEGER NOT NULL,amount INTEGER NOT NULL CHECK(amount>0), '+
        'unit_price INTEGER NOT NULL CHECK(unit_price>=0),paid INTEGER NOT NULL CHECK(paid=amount*unit_price))');
      FDB.ExecSQL('INSERT INTO npc_purchases_v33 SELECT * FROM npc_purchases');
      FDB.ExecSQL('DROP TABLE npc_purchases');
      FDB.ExecSQL('ALTER TABLE npc_purchases_v33 RENAME TO npc_purchases');
    end;
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS fletta_rate_carry (id INTEGER PRIMARY KEY CHECK(id=1), '+
      'remainder INTEGER NOT NULL CHECK(remainder BETWEEN 0 AND 99))');
    FDB.ExecSQL('INSERT OR IGNORE INTO fletta_rate_carry VALUES(1,0)');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS quest_cycles (quest_id INTEGER PRIMARY KEY REFERENCES quests(quest_id), '+
      'cycle INTEGER NOT NULL CHECK(cycle>=0))');
    FDB.ExecSQL('INSERT OR IGNORE INTO quest_cycles SELECT quest_id,0 FROM quests');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS hero_class (id INTEGER PRIMARY KEY CHECK(id=1), '+
      'base_class INTEGER NOT NULL CHECK(base_class IN(100,300,500)), '+
      'class_id INTEGER NOT NULL, rank INTEGER NOT NULL CHECK(rank IN(0,1)))');
    FDB.ExecSQL('CREATE TABLE IF NOT EXISTS class_receipts (receipt TEXT PRIMARY KEY NOT NULL, '+
      'target INTEGER NOT NULL, rank INTEGER NOT NULL)');
    FDB.ExecSQL('INSERT OR IGNORE INTO hero_class SELECT 1,class_id,class_id,0 FROM starter_equipment WHERE id=1');
    if Version<36 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS learned_skills_v35_backup AS SELECT * FROM learned_skills');
      FDB.ExecSQL('CREATE TABLE learned_skills_v36 (skill_id INTEGER PRIMARY KEY, rank INTEGER NOT NULL, '+
        'CHECK((skill_id IN(1001,1002,1003,1004,1005,1006,1101,1102,1901,1902) AND rank BETWEEN 1 AND 5) OR '+
        '(skill_id IN(5001,9001) AND rank=1)))');
      FDB.ExecSQL('INSERT INTO learned_skills_v36 SELECT * FROM learned_skills');
      FDB.ExecSQL('DROP TABLE learned_skills');FDB.ExecSQL('ALTER TABLE learned_skills_v36 RENAME TO learned_skills');
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS skill_acquisitions_v35_backup AS SELECT * FROM skill_acquisitions');
      FDB.ExecSQL('CREATE TABLE skill_acquisitions_v36 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'skill_id INTEGER NOT NULL UNIQUE CHECK(skill_id IN(1002,1003,1004,1005,1006,1101,1102,1901,1902)), '+
        'spent INTEGER NOT NULL CHECK(spent=1))');
      FDB.ExecSQL('INSERT INTO skill_acquisitions_v36 SELECT * FROM skill_acquisitions');
      FDB.ExecSQL('DROP TABLE skill_acquisitions');FDB.ExecSQL('ALTER TABLE skill_acquisitions_v36 RENAME TO skill_acquisitions');
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS skill_upgrades_v35_backup AS SELECT * FROM skill_upgrades');
      FDB.ExecSQL('CREATE TABLE skill_upgrades_v36 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'skill_id INTEGER NOT NULL CHECK(skill_id IN(1001,1002,1003,1004,1005,1006,1101,1102,1901,1902)), '+
        'rank INTEGER NOT NULL CHECK(rank BETWEEN 2 AND 5),spent INTEGER NOT NULL CHECK(spent=1))');
      FDB.ExecSQL('INSERT INTO skill_upgrades_v36 SELECT * FROM skill_upgrades');
      FDB.ExecSQL('DROP TABLE skill_upgrades');FDB.ExecSQL('ALTER TABLE skill_upgrades_v36 RENAME TO skill_upgrades');
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS quickslots_v35_backup AS SELECT * FROM quickslots');
      FDB.ExecSQL('CREATE TABLE quickslots_v36 (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 35), '+
        'reference_id INTEGER NOT NULL, source_page INTEGER NOT NULL, source_slot INTEGER NOT NULL, '+
        'CHECK((source_page=9 AND ((reference_id=1003 AND source_slot IN(5,6)) OR '+
        '(reference_id=1101 AND source_slot=5) OR (reference_id=1901 AND source_slot=6) OR '+
        '(reference_id=1004 AND source_slot=2) OR (reference_id=1005 AND source_slot=4) OR '+
        '(reference_id=1002 AND source_slot=1) OR (reference_id IN(1001,5001,9001) AND source_slot=0))) OR '+
        '(source_page=1 AND reference_id IN(54004,54005,54006,54203,54205,54206) AND source_slot BETWEEN 0 AND 19)))');
      FDB.ExecSQL('INSERT INTO quickslots_v36 SELECT * FROM quickslots');
      FDB.ExecSQL('DROP TABLE quickslots');FDB.ExecSQL('ALTER TABLE quickslots_v36 RENAME TO quickslots');
    end;
    if Version<37 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS learned_skills_v36_backup AS SELECT * FROM learned_skills');
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS skill_acquisitions_v36_backup AS SELECT * FROM skill_acquisitions');
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS skill_upgrades_v36_backup AS SELECT * FROM skill_upgrades');
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS quickslots_v36_backup AS SELECT * FROM quickslots');
      FDB.ExecSQL('CREATE TABLE learned_skills_v37 (skill_id INTEGER PRIMARY KEY, rank INTEGER NOT NULL, '+
        'CHECK((skill_id IN(1001,1002,1003,1004,1005,1006,1101,1102,1103,1104,1105,1106,1107,1901,1902,1903,1904,1905,1906,1907) AND rank BETWEEN 1 AND 5) OR '+
        '(skill_id IN(5001,9001) AND rank=1)))');
      FDB.ExecSQL('INSERT INTO learned_skills_v37 SELECT * FROM learned_skills');
      FDB.ExecSQL('DROP TABLE learned_skills');FDB.ExecSQL('ALTER TABLE learned_skills_v37 RENAME TO learned_skills');
      FDB.ExecSQL('CREATE TABLE skill_acquisitions_v37 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'skill_id INTEGER NOT NULL UNIQUE CHECK(skill_id IN(1002,1003,1004,1005,1006,1101,1102,1103,1104,1105,1106,1107,1901,1902,1903,1904,1905,1906,1907)), '+
        'spent INTEGER NOT NULL CHECK(spent=1))');
      FDB.ExecSQL('INSERT INTO skill_acquisitions_v37 SELECT * FROM skill_acquisitions');
      FDB.ExecSQL('DROP TABLE skill_acquisitions');FDB.ExecSQL('ALTER TABLE skill_acquisitions_v37 RENAME TO skill_acquisitions');
      FDB.ExecSQL('CREATE TABLE skill_upgrades_v37 (receipt TEXT PRIMARY KEY NOT NULL, '+
        'skill_id INTEGER NOT NULL CHECK(skill_id IN(1001,1002,1003,1004,1005,1006,1101,1102,1103,1104,1105,1106,1107,1901,1902,1903,1904,1905,1906,1907)), '+
        'rank INTEGER NOT NULL CHECK(rank BETWEEN 2 AND 5),spent INTEGER NOT NULL CHECK(spent=1))');
      FDB.ExecSQL('INSERT INTO skill_upgrades_v37 SELECT * FROM skill_upgrades');
      FDB.ExecSQL('DROP TABLE skill_upgrades');FDB.ExecSQL('ALTER TABLE skill_upgrades_v37 RENAME TO skill_upgrades');
      FDB.ExecSQL('CREATE TABLE quickslots_v37 (slot INTEGER PRIMARY KEY CHECK(slot BETWEEN 0 AND 35), '+
        'reference_id INTEGER NOT NULL,source_page INTEGER NOT NULL,source_slot INTEGER NOT NULL, '+
        'CHECK((source_page=9 AND ((reference_id IN(1001,5001,9001) AND source_slot=0) OR '+
        '(reference_id=1002 AND source_slot=1) OR (reference_id=1004 AND source_slot=2) OR '+
        '(reference_id=1005 AND source_slot=4) OR (reference_id=1003 AND source_slot IN(5,6)) OR '+
        '(reference_id=1101 AND source_slot=5) OR (reference_id=1901 AND source_slot=6) OR '+
        '(reference_id IN(1103,1903) AND source_slot=8) OR (reference_id IN(1104,1904) AND source_slot=9) OR '+
        '(reference_id IN(1105,1905) AND source_slot=10) OR (reference_id IN(1106,1906) AND source_slot=11) OR '+
        '(reference_id IN(1107,1907) AND source_slot=12))) OR '+
        '(source_page=1 AND reference_id IN(54004,54005,54006,54203,54205,54206) AND source_slot BETWEEN 0 AND 19)))');
      FDB.ExecSQL('INSERT INTO quickslots_v37 SELECT * FROM quickslots');
      FDB.ExecSQL('DROP TABLE quickslots');FDB.ExecSQL('ALTER TABLE quickslots_v37 RENAME TO quickslots');
    end;
    if Version<38 then begin
      FDB.ExecSQL('CREATE TABLE IF NOT EXISTS skill_points_v37_backup AS SELECT * FROM skill_points');
      FDB.ExecSQL('CREATE TABLE skill_points_v38 (id INTEGER PRIMARY KEY CHECK(id=1), '+
        'highest_level INTEGER NOT NULL CHECK(highest_level BETWEEN 1 AND 45), '+
        'earned INTEGER NOT NULL CHECK(earned=highest_level-1), '+
        'spent INTEGER NOT NULL CHECK(spent BETWEEN 0 AND earned+bonus), '+
        'bonus INTEGER NOT NULL DEFAULT 0 CHECK(bonus BETWEEN 0 AND 1000))');
      FDB.ExecSQL('INSERT INTO skill_points_v38 SELECT * FROM skill_points');
      FDB.ExecSQL('DROP TABLE skill_points');FDB.ExecSQL('ALTER TABLE skill_points_v38 RENAME TO skill_points');
    end;
    if Version<39 then begin
      FDB.ExecSQL('CREATE TABLE item_instances (instance_id INTEGER PRIMARY KEY AUTOINCREMENT, '+
        'item_id INTEGER NOT NULL,grade INTEGER NOT NULL DEFAULT 0 CHECK(grade BETWEEN -128 AND 127), '+
        'data8 BIGINT NOT NULL DEFAULT 0 CHECK(data8 BETWEEN 0 AND 4294967295),'+
        'data12 BIGINT NOT NULL DEFAULT 0 CHECK(data12 BETWEEN 0 AND 4294967295), '+
        'gem0 INTEGER NOT NULL DEFAULT 0,gem1 INTEGER NOT NULL DEFAULT 0,gem2 INTEGER NOT NULL DEFAULT 0)');
      FDB.ExecSQL('ALTER TABLE inventory ADD COLUMN instance_id INTEGER');
      FDB.ExecSQL('CREATE TABLE equipment_v39 (slot INTEGER PRIMARY KEY CHECK(slot IN (1,2,3,4,7,22,24)), '+
        'item_id INTEGER NOT NULL,instance_id INTEGER)');
      FDB.ExecSQL('INSERT INTO equipment_v39(slot,item_id) SELECT slot,item_id FROM equipment');
      FDB.ExecSQL('DROP TABLE equipment');FDB.ExecSQL('ALTER TABLE equipment_v39 RENAME TO equipment');
      FDB.ExecSQL('ALTER TABLE personal_stash ADD COLUMN instance_id INTEGER');
      FDB.ExecSQL('ALTER TABLE ground ADD COLUMN instance_id INTEGER');
      MigrateItemInstances;
    end;
    FPropertiesReady:=True;
    FDB.ExecSQL('PRAGMA user_version=39');
    FDB.Commit;
  except
    FDB.Rollback; raise;
  end;
end;

destructor TB1008LootStore.Destroy;
begin
  FDB.Free; FDriver.Free; FLock.Free;
  inherited;
end;

procedure TB1008LootStore.RequireOwner(Owner: TObject);
begin
  if (Owner=nil) or (Owner<>FOwner) then raise Exception.Create('Loot store ownership required');
end;

function PreviewIdentity(const Preview: TBytes): string;
var Normalized: TBytes; Hash: THashSHA2;
begin
  if (Length(Preview)<$152) or (Preview[0]<>2) or
    (Preview[1]<>1) or (TB1008Wire.ReadBE32(Preview,7)<>1) then
    raise EKarosProtocol.Create('Invalid loot character identity');
  Normalized:=Copy(Preview); FillChar(Normalized[2],4,0);
  Hash:=THashSHA2.Create; Hash.Update(Normalized); Result:=Hash.HashAsString;
end;

{$I Emulator.LootStore.ItemProperties.inc}
{$I Emulator.LootStore.Crafting.inc}
{$I Emulator.LootStore.Enhancement.inc}
{$I Emulator.LootStore.Mining.inc}
{$I Emulator.LootStore.Class.inc}

function TB1008LootStore.Acquire(Owner: TObject; const Preview: TBytes): Boolean;
var Identity,Saved: string;ClassID:Word;Item:TB1008EquipmentItem;SavedClass:Integer;
  StarterID:Cardinal;Skills:TArray<TB1008LearnedSkill>;Skill:TB1008LearnedSkill;
begin
  if Owner=nil then raise EArgumentException.Create('Missing loot owner');
  Identity:=PreviewIdentity(Preview);
  Move(Preview[15],ClassID,2);
  FLock.Acquire;
  try
    Result:=(FOwner=nil) or (FOwner=Owner);
    if not Result then Exit;
    FDB.StartTransaction;
    try
      Saved:=VarToStr(FDB.ExecSQLScalar('SELECT identity FROM hero WHERE id=1'));
      if (Saved<>'') and (Saved<>Identity) then
        raise Exception.Create('Loot belongs to another character; database preserved');
      if Saved='' then FDB.ExecSQL('INSERT INTO hero(id,identity) VALUES(1,:identity)',[Identity]);
      SavedClass:=Integer(FDB.ExecSQLScalar('SELECT COALESCE((SELECT class_id FROM starter_equipment WHERE id=1),0)'));
      if SavedClass=0 then begin
        // One transaction/receipt: never replace existing inventory or regrant
        // a removed starter item on reconnect. Identity remains the old preview.
        for Item in TB1008Equipment.Starter(ClassID) do
          FDB.ExecSQL('INSERT INTO equipment(slot,item_id) VALUES(:s,:i)',[Item.Slot,Item.ItemID]);
        MigrateItemInstances;
        FDB.ExecSQL('INSERT INTO starter_equipment VALUES(1,:c,1)',[ClassID]);
      end else if SavedClass<>ClassID then raise Exception.Create('Starter equipment belongs to another class');
      FDB.ExecSQL('INSERT OR IGNORE INTO hero_class VALUES(1,:c,:c,0)',[ClassID]);
      if ReadClassState.BaseClass<>ClassID then raise Exception.Create('Profession belongs to another class');
      TB1008Equipment.Validate(ReadEquipment,ClassID);
      StarterID:=TB1008SkillWire.StarterID(ClassID);
      SavedClass:=Integer(FDB.ExecSQLScalar('SELECT COALESCE((SELECT class_id FROM starter_skills WHERE id=1),0)'));
      if SavedClass=0 then begin
        // New and existing characters: seed once in the same identity-bound
        // transaction as starter equipment, without touching earned SP.
        FDB.ExecSQL('INSERT OR IGNORE INTO learned_skills VALUES(:i,1)',[Int64(StarterID)]);
        FDB.ExecSQL('INSERT INTO starter_skills VALUES(1,:c,:i,1)',[ClassID,Int64(StarterID)]);
      end else if SavedClass<>ClassID then raise Exception.Create('Starter skill belongs to another class');
      Skills:=ReadLearnedSkills;
      if (Length(Skills)<1) or (Length(Skills)>13) or (Skills[0].ID<>StarterID) or
        not TB1008SkillWire.SupportedRank(Skills[0].ID,Skills[0].Rank) then
        raise Exception.Create('Invalid starter skill save; preserved');
      for Skill in Skills do
        if not TB1008SkillWire.SupportedRank(Skill.ID,Skill.Rank) or
          ((Skill.ID<>StarterID) and ((ClassID<>100) or
            ((Skill.ID<>B1008BodyBlowID) and (Skill.ID<>B1008FrenzyID) and
             (Skill.ID<>B1008ProvocationID) and (Skill.ID<>B1008CoerciveID) and (Skill.ID<>B1008StrengthMasteryID) and
             not TB1008ProfessionSkill.Allowed(Skill.ID,ReadClassState.ClassID)))) then
          raise Exception.Create('Invalid class skill save; preserved');
      LimitFletta(ReadProgress.Level);
      FDB.Commit;
    except FDB.Rollback; raise; end;
    FOwner:=Owner;
  finally FLock.Release; end;
end;

function TB1008LootStore.ReadEquipment:TArray<TB1008EquipmentItem>;
var Q:TFDQuery;N:Integer;
begin
  Result:=nil;Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FDB;Q.Open('SELECT slot,item_id,'+InstanceColumn+' FROM equipment ORDER BY slot');
    while not Q.Eof do begin
      N:=Length(Result);SetLength(Result,N+1);
      Result[N].Slot:=Q.Fields[0].AsInteger;Result[N].ItemID:=Q.Fields[1].AsLargeInt;
      Result[N].Properties:=ReadProperties(Q.Fields[2].AsLargeInt);Q.Next;
    end;
    TB1008Equipment.Validate(Result);
  finally Q.Free;end;
end;

function TB1008LootStore.Equipment(Owner:TObject):TArray<TB1008EquipmentItem>;
begin
  FLock.Acquire;
  try RequireOwner(Owner);Result:=ReadEquipment;finally FLock.Release;end;
end;

function TB1008LootStore.TransferEquipment(Owner:TObject;const Receipt:string;ClassID:Word;
  const Request:TB1008EquipmentRequest;out Bag:TB1008BagItem):Boolean;
var Slot:Byte;CurrentID:Cardinal;NewProperties,OldProperties:TB1008ItemProperties;
begin
  Result:=False;Bag:=Default(TB1008BagItem);Slot:=TB1008Equipment.ItemSlot(Request.ItemID,ClassID);
  if (Receipt='') or (Slot=0) or (Request.CharacterID<>1) or (Request.Code<>0) or
    not (Request.EquipSlot in [Slot,255]) then Exit;
  if Request.Wear then begin
    if (Request.Page<>1) or (Request.Slot>=B1008BagSlots) then Exit;
  end else if (Request.Page<>0) or (Request.Slot<>Slot) or (Request.EquipSlot<>Slot) then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM operations WHERE receipt=:r',[Receipt]))<>0 then begin
        FDB.Rollback;Exit;
      end;
      CurrentID:=Int64(FDB.ExecSQLScalar('SELECT COALESCE((SELECT item_id FROM equipment WHERE slot=:s),0)',[Slot]));
      OldProperties:=ReadProperties(Int64(FDB.ExecSQLScalar('SELECT COALESCE((SELECT instance_id FROM equipment WHERE slot=:s),0)',[Slot])));
      if Request.Wear then begin
        if ReadProgress.Level<TB1008Items.Get(Request.ItemID).RequiredLevel then begin FDB.Rollback;Exit;end;
        Bag:=FindSlot(Request.Slot);
        if (Bag.ItemID<>Request.ItemID) or (Bag.Amount<>1) then begin FDB.Rollback;Exit;end;
        NewProperties:=Bag.Properties;EnsureProperties(Request.ItemID,NewProperties);
        // Return the displaced item to the source cell, even with a full bag.
        // Bag describes that cell AFTER the transaction; an empty slot has amount 0.
        Bag.ItemID:=CurrentID;Bag.Amount:=Ord(CurrentID<>0);Bag.Properties:=OldProperties;
        if CurrentID=0 then FDB.ExecSQL('DELETE FROM inventory WHERE slot=:s',[Bag.Slot])
        else SaveItem(Bag);
        FDB.ExecSQL('INSERT OR REPLACE INTO equipment(slot,item_id,instance_id) VALUES(:s,:i,:p)',[Slot,Request.ItemID,NewProperties.InstanceID]);
      end else begin
        if CurrentID<>Request.ItemID then begin FDB.Rollback;Exit;end;
        Bag.Slot:=FreeSlot(0);
        if Bag.Slot=255 then begin FDB.Rollback;Exit;end;
        Bag.ItemID:=Request.ItemID;Bag.Amount:=1;Bag.Properties:=OldProperties;
        FDB.ExecSQL('DELETE FROM equipment WHERE slot=:s',[Slot]);SaveItem(Bag);
      end;
      FDB.ExecSQL('INSERT INTO operations VALUES(:r)',[Receipt]);FDB.Commit;Result:=True;
    except FDB.Rollback;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.PreviewEquipment(const Preview:TBytes):TArray<TB1008EquipmentItem>;
var Identity,Saved:string;ClassID:Word;
begin
  Identity:=PreviewIdentity(Preview);Move(Preview[15],ClassID,2);
  FLock.Acquire;
  try
    Saved:=VarToStr(FDB.ExecSQLScalar('SELECT identity FROM hero WHERE id=1'));
    if (Saved<>'') and (Saved<>Identity) then raise Exception.Create('Equipment preview identity mismatch');
    if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM starter_equipment'))=0 then
      Result:=TB1008Equipment.Starter(ClassID) else Result:=ReadEquipment;
    TB1008Equipment.Validate(Result,ClassID);
  finally FLock.Release;end;
end;

procedure TB1008LootStore.Release(Owner: TObject);
begin
  FLock.Acquire;
  try if FOwner=Owner then FOwner:=nil; finally FLock.Release; end;
end;

function TB1008LootStore.ReadProgress: TB1008Progress;
begin
  Result.TotalEXP:=Int64(FDB.ExecSQLScalar('SELECT COALESCE((SELECT total_exp FROM progression WHERE id=1),0)'));
  Result.Validate;
end;

function TB1008LootStore.Progress(Owner: TObject): TB1008Progress;
begin
  FLock.Acquire;
  try RequireOwner(Owner); Result:=ReadProgress; finally FLock.Release; end;
end;

procedure TB1008LootStore.AwardSkillLevels(Level:Word);
begin
  // Called within the same transaction as the EXP receipt.
  FDB.ExecSQL('UPDATE skill_points SET highest_level=:l,earned=:e WHERE id=1 AND highest_level<:bound',
    [Integer(Level),Integer(Level)-1,Integer(Level)]);
end;

function TB1008LootStore.SkillPoints(Owner:TObject):Cardinal;
begin
  FLock.Acquire;
  try RequireOwner(Owner);
    Result:=Integer(FDB.ExecSQLScalar('SELECT earned+bonus-spent FROM skill_points WHERE id=1'));
  finally FLock.Release;end;
end;

procedure TB1008LootStore.GrantTestProgress(Owner:TObject;const Receipt:string;Level:Word;FreeSP:Cardinal);
var TargetEXP: Int64;Before:TB1008Progress;I,Bonus:Integer;
begin
  // Offline tool only. No network command exposes administrative grants.
  if (Receipt='') or (Length(Receipt)>512) or (Level<1) or
    (Level>TB1008Balance.LevelCap) or (FreeSP>1000) then
    raise EArgumentException.Create('Invalid test progression grant');
  TargetEXP:=0;for I:=1 to Level-1 do Inc(TargetEXP,TB1008Balance.Threshold(I));
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM test_progress_grants WHERE receipt=:r',[Receipt]))=0 then begin
        Before:=ReadProgress;
        if Before.TotalEXP>TargetEXP then raise EArgumentException.Create('Test grant cannot lower EXP');
        AwardSkillLevels(Level);
        Bonus:=Integer(FreeSP)+Integer(FDB.ExecSQLScalar('SELECT spent-earned FROM skill_points WHERE id=1'));
        if (Bonus<0) or (Bonus>1000) then raise EArgumentException.Create('Test grant cannot remove earned SP');
        FDB.ExecSQL('UPDATE skill_points SET bonus=:n WHERE id=1',[Bonus]);
        FDB.ExecSQL('INSERT INTO progression(id,total_exp) VALUES(1,:n) '+
          'ON CONFLICT(id) DO UPDATE SET total_exp=excluded.total_exp',[TargetEXP]);
        LimitFletta(Level);
        FDB.ExecSQL('INSERT INTO test_progress_grants VALUES(:r,:l,:s,:b,:a)',
          [Receipt,Integer(Level),Int64(FreeSP),Before.TotalEXP,TargetEXP]);
      end;
      FDB.Commit;
    except FDB.Rollback;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.ReadLearnedSkills:TArray<TB1008LearnedSkill>;
var Q:TFDQuery;N:Integer;
begin
  Result:=nil;Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FDB;Q.Open('SELECT skill_id,rank FROM learned_skills ORDER BY skill_id');
    while not Q.Eof do begin
      N:=Length(Result);SetLength(Result,N+1);
      Result[N].ID:=Q.Fields[0].AsLargeInt;Result[N].Rank:=Q.Fields[1].AsLargeInt;Q.Next;
    end;
  finally Q.Free;end;
end;

function TB1008LootStore.LearnedSkills(Owner:TObject):TArray<TB1008LearnedSkill>;
begin
  FLock.Acquire;
  try RequireOwner(Owner);Result:=ReadLearnedSkills;finally FLock.Release;end;
end;

function TB1008LootStore.TrainingPrerequisitesMet(const Training:TB1008SkillTraining):Boolean;
var I:Integer;
begin
  Result:=False;
  if Training.PrerequisiteCount>0 then begin
    for I:=0 to Training.PrerequisiteCount-1 do
      if (Training.PrerequisiteRanks[I]>0) and (Integer(FDB.ExecSQLScalar(
        'SELECT COUNT(*) FROM learned_skills WHERE skill_id=:i AND rank>=:r',
        [Int64(Training.PrerequisiteIDs[I]),Int64(Training.PrerequisiteRanks[I])]))<>1) then Exit;
  end else if (Training.PrerequisiteID<>0) and (Training.PrerequisiteRank>0) and
    (Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM learned_skills WHERE skill_id=:i AND rank>=:r',
      [Int64(Training.PrerequisiteID),Int64(Training.PrerequisiteRank)]))<>1) then Exit;
  Result:=True;
end;

function TB1008LootStore.LearnSkill(Owner:TObject;const Receipt:string;
  const Request:TB1008SkillLearn):TB1008SkillLearnResult;
var FreeSP:Integer;Training:TB1008SkillTraining;
begin
  Result:=slrRejected;FLock.Acquire;
  try
    RequireOwner(Owner);
    if (Receipt='') or (Length(Receipt)>512) or not Request.Supported then Exit;
    Training:=TB1008SkillTraining.Get(Request.SkillID,1);
    FDB.StartTransaction;
    try
      // Class and prerequisites come from the owned save, never the request.
      if (Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM starter_skills WHERE class_id=100'))=1) and
        (not TB1008ProfessionSkill.Supported(Request.SkillID) or
          TB1008ProfessionSkill.Allowed(Request.SkillID,ReadClassState.ClassID)) then begin
        if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM learned_skills WHERE skill_id=:i',[Int64(Request.SkillID)]))=1 then
          Result:=slrAlreadyKnown
        else if (ReadProgress.Level>=Training.RequiredLevel) and
          TrainingPrerequisitesMet(Training) and
          (Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM skill_acquisitions WHERE receipt=:r',[Receipt]))=0) then begin
          FreeSP:=Integer(FDB.ExecSQLScalar('SELECT earned+bonus-spent FROM skill_points WHERE id=1'));
          if FreeSP>=Training.SPCost then begin
            FDB.ExecSQL('UPDATE skill_points SET spent=spent+:n WHERE id=1',[Training.SPCost]);
            FDB.ExecSQL('INSERT INTO learned_skills VALUES(:i,1)',[Int64(Request.SkillID)]);
            FDB.ExecSQL('INSERT INTO skill_acquisitions VALUES(:r,:i,:s)',[Receipt,Int64(Request.SkillID),Training.SPCost]);
            Result:=slrApplied;
          end;
        end;
      end;
      FDB.Commit;
    except FDB.Rollback;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.UpgradeSkill(Owner:TObject;const Receipt:string;
  const Request:TB1008SkillUpgrade;out Rank:Cardinal):TB1008SkillUpgradeResult;
var Next:TB1008SkillTraining;FreeSP:Integer;
begin
  Result:=surRejected;Rank:=0;FLock.Acquire;
  try
    RequireOwner(Owner);
    if (Receipt='') or (Length(Receipt)>512) or not Request.Supported then Exit;
    FDB.StartTransaction;
    try
      Rank:=Integer(FDB.ExecSQLScalar('SELECT COALESCE((SELECT rank FROM learned_skills WHERE skill_id=:i),0)',[Int64(Request.SkillID)]));
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM skill_upgrades WHERE receipt=:r',[Receipt]))>0 then
        Result:=surDuplicate
      else if (Rank>=1) and (Rank<5) and (Request.CurrentRank=Rank) then begin
        Next:=TB1008SkillTraining.Get(Request.SkillID,Rank+1);
        FreeSP:=Integer(FDB.ExecSQLScalar('SELECT earned+bonus-spent FROM skill_points WHERE id=1'));
        if (Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM starter_skills WHERE class_id=100'))=1) and
          (not TB1008ProfessionSkill.Supported(Request.SkillID) or
            TB1008ProfessionSkill.Allowed(Request.SkillID,ReadClassState.ClassID)) and
          (ReadProgress.Level>=Next.RequiredLevel) and (FreeSP>=Next.SPCost) and
          TrainingPrerequisitesMet(Next) then begin
          Inc(Rank);
          FDB.ExecSQL('UPDATE skill_points SET spent=spent+:n WHERE id=1',[Next.SPCost]);
          FDB.ExecSQL('UPDATE learned_skills SET rank=:n WHERE skill_id=:i',[Int64(Rank),Int64(Request.SkillID)]);
          FDB.ExecSQL('INSERT INTO skill_upgrades VALUES(:r,:i,:n,:s)',[Receipt,Int64(Request.SkillID),Int64(Rank),Next.SPCost]);
          Result:=surApplied;
        end;
      end;
      FDB.Commit;
    except FDB.Rollback;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.QuickSlots(Owner:TObject):TArray<TB1008QuickSlot>;
var Q:TFDQuery;N:Integer;Entry:TB1008QuickSlot;Bag:TB1008BagItem;
begin
  Result:=nil;FLock.Acquire;
  try
    RequireOwner(Owner);Q:=TFDQuery.Create(nil);
    try
      Q.Connection:=FDB;Q.Open('SELECT q.slot,q.reference_id,q.source_page,q.source_slot '+
        'FROM quickslots q WHERE q.source_page=1 OR EXISTS '+
        '(SELECT 1 FROM learned_skills s WHERE s.skill_id=q.reference_id) ORDER BY q.slot');
      while not Q.Eof do begin
        Entry.Slot:=Q.Fields[0].AsLargeInt;Entry.ReferenceID:=Q.Fields[1].AsLargeInt;
        Entry.SourcePage:=Q.Fields[2].AsInteger;Entry.SourceSlot:=Q.Fields[3].AsInteger;
        if Entry.SourcePage=1 then begin
          Bag:=FindSlot(Entry.SourceSlot);
          if (Bag.Amount=0) or (Bag.ItemID<>Entry.ReferenceID) then Bag:=FindItem(Entry.ReferenceID);
          // Keep the preference when exhausted, but never restore a link to a
          // different item which subsequently occupies the old bag cell.
          if Bag.Amount=0 then begin Q.Next;Continue;end;
          Entry.ReferenceID:=High(Cardinal);Entry.SourceSlot:=Bag.Slot;
        end else if Entry.SourcePage=9 then
          Entry.SourceSlot:=TB1008QuickSlotWire.SkillSourceSlot(Entry.ReferenceID,ReadClassState.ClassID);
        if not Entry.Supported then raise Exception.Create('Unsupported saved quickslot; database preserved');
        N:=Length(Result);SetLength(Result,N+1);Result[N]:=Entry;
        Q.Next;
      end;
    finally Q.Free;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.SetQuickSlot(Owner:TObject;const Request:TB1008QuickSlotRequest):Boolean;
var Entry:TB1008QuickSlot;Bag:TB1008BagItem;SavedID:Cardinal;
begin
  Result:=False;FLock.Acquire;
  try
    RequireOwner(Owner);
    if (Request.CharacterID<>1) or (Request.Entry.Slot>=B1008QuickSlotCount) then Exit;
    if Request.Remove then begin
      FDB.ExecSQL('DELETE FROM quickslots WHERE slot=:s',[Int64(Request.Entry.Slot)]);Exit(True);
    end;
    Entry:=Request.Entry;
    if Entry.ReferenceID=High(Cardinal) then begin
      if (Entry.SourcePage=0) and (Entry.SourceSlot>=0) and (Entry.SourceSlot<B1008QuickSlotCount) then begin
        SavedID:=Int64(FDB.ExecSQLScalar('SELECT COALESCE((SELECT reference_id FROM quickslots '+
          'WHERE slot=:s AND source_page=1),0)',[Entry.SourceSlot]));
        if not TB1008Items.IsPotion(SavedID) then Exit;
        Bag:=FindItem(SavedID);if Bag.Amount=0 then Exit;
        Entry.SourcePage:=1;Entry.SourceSlot:=Bag.Slot;
      end else begin
        if not Entry.Supported then Exit;
        Bag:=FindSlot(Entry.SourceSlot);
      end;
      if (Bag.Amount=0) or not TB1008Items.IsPotion(Bag.ItemID) then Exit;
      // The DB retains the item identity; only the wire uses the -1 sentinel.
      Entry.ReferenceID:=Bag.ItemID;
    end else begin
    // 0x512BDD/0x512C03: these two words identify the drag-source UI
    // control/cell, not a skill rank. K sends 9/0 for a starter; moving
    // a hotbar icon sends 0/source-cell (live slot 0 -> 3: 1001/0/0).
    // Persist the canonical learned-skill reference, not a transient link
    // to the old hotbar cell which the following 06/0C removes.
    if (Entry.SourcePage=0) and (Entry.SourceSlot>=0) and
      (Entry.SourceSlot<B1008QuickSlotCount) then begin
      Entry.SourcePage:=9;
      Entry.SourceSlot:=TB1008QuickSlotWire.SkillSourceSlot(Entry.ReferenceID,ReadClassState.ClassID);
    end;
    if not Entry.Supported then Exit;
    if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM learned_skills WHERE skill_id=:i AND rank BETWEEN 1 AND 5',
      [Int64(Request.Entry.ReferenceID)]))<>1 then Exit;
    end;
    // One atomic upsert; duplicates have no resource side effects. A moved
    // shortcut is a separate add/delete pair in this ordered TCP session.
    FDB.ExecSQL('INSERT OR REPLACE INTO quickslots VALUES(:s,:i,:p,:c)',
      [Int64(Entry.Slot),Int64(Entry.ReferenceID),Entry.SourcePage,Entry.SourceSlot]);
    Result:=True;
  finally FLock.Release;end;
end;

function TB1008LootStore.PreviewProgress(const Preview: TBytes): TB1008Progress;
var Identity,Saved: string;
begin
  Identity:=PreviewIdentity(Preview);
  FLock.Acquire;
  try
    Saved:=VarToStr(FDB.ExecSQLScalar('SELECT identity FROM hero WHERE id=1'));
    if (Saved<>'') and (Saved<>Identity) then
      raise Exception.Create('Progress belongs to another character; database preserved');
    Result:=ReadProgress;
  finally FLock.Release; end;
end;

function TB1008LootStore.RecordSpiderEXP(Owner: TObject;
  const Receipt: string): TB1008Progress;
begin Result:=RecordEXP(Owner,Receipt,TB1008Balance.SpiderEXP,1); end;

function TB1008LootStore.RecordMobEXP(Owner:TObject;const Receipt:string;
  Amount,MonsterLevel:Integer):TB1008Progress;
begin
  if (MonsterLevel<1) or (MonsterLevel>20) then raise EArgumentException.Create('Invalid monster level');
  Result:=RecordEXP(Owner,Receipt,Amount,MonsterLevel);
end;

function TB1008LootStore.RecordQuestEXP(Owner: TObject; QuestID: Cardinal): TB1008Progress;
begin Result:=RecordEXP(Owner,'quest/'+UIntToStr(QuestID),TB1008Balance.QuestEXP(QuestID)); end;

{$I Emulator.LootStore.Quests.inc}
{$I Emulator.LootStore.Stash.inc}
{$I Emulator.LootStore.Return.inc}

function TB1008LootStore.PendingDeath(Owner:TObject):Boolean;
begin
  FLock.Acquire;
  try RequireOwner(Owner);Result:=Integer(FDB.ExecSQLScalar('SELECT COALESCE((SELECT pending FROM death_state WHERE id=1),0)'))=1;
  finally FLock.Release;end;
end;

function TB1008LootStore.RecordDeath(Owner:TObject;const Receipt:string):TB1008Progress;
var Loss,BeforeEXP:Int64;
begin
  if Receipt='' then raise EArgumentException.Create('Missing death receipt');
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      Result:=ReadProgress;
      if (Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM death_receipts WHERE receipt=:r',[Receipt]))=0) and
        (Integer(FDB.ExecSQLScalar('SELECT COALESCE((SELECT pending FROM death_state WHERE id=1),0)'))=0) then begin
        BeforeEXP:=Result.TotalEXP;Loss:=TB1008Balance.DeathEXPLoss(Result.Level);
        if Loss>BeforeEXP then Loss:=BeforeEXP;
        Dec(Result.TotalEXP,Loss);Result.Validate;
        FDB.ExecSQL('INSERT INTO death_receipts(receipt,loss,before_exp,after_exp) VALUES(:r,:l,:b,:a)',
          [Receipt,Loss,BeforeEXP,Result.TotalEXP]);
        FDB.ExecSQL('INSERT OR REPLACE INTO progression(id,total_exp) VALUES(1,:n)',[Result.TotalEXP]);
        FDB.ExecSQL('INSERT OR REPLACE INTO death_state(id,receipt,pending) VALUES(1,:r,1)',[Receipt]);
        LimitFletta(Result.Level);
      end;
      FDB.Commit;
    except FDB.Rollback;raise;end;
  finally FLock.Release;end;
end;

procedure TB1008LootStore.CompleteRespawn(Owner:TObject);
begin
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.ExecSQL('UPDATE death_state SET pending=0 WHERE id=1 AND pending=1');
  finally FLock.Release;end;
end;

function TB1008LootStore.RecordEXP(Owner: TObject;
  const Receipt: string; Amount: Integer; MonsterLevel:Integer): TB1008Progress;
var Gain,ScaledEXP,BeforeFletta: Int64; F:TB1008Fletta; FlettaGain,BeforeLevel,RateRemainder:Integer;
begin
  if Receipt='' then raise EArgumentException.Create('Missing kill receipt');
  if Amount<0 then raise EArgumentException.Create('Negative EXP reward');
  FLock.Acquire;
  try
    RequireOwner(Owner); FDB.StartTransaction;
    try
      Result:=ReadProgress;
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM exp_receipts WHERE receipt=:r',[Receipt]))=0 then begin
        BeforeLevel:=Result.Level;
        Gain:=TB1008Balance.MaxEXP-Result.TotalEXP;
        ScaledEXP:=TB1008Rates.Scale(Amount,FRates.Experience,Gain);
        if Gain>ScaledEXP then Gain:=ScaledEXP;
        Inc(Result.TotalEXP,Gain);
        if MonsterLevel>0 then begin
          // The reward uses the pre-kill level; capacity follows the resulting
          // level so a level-up kill can fill the newly opened space immediately.
          F:=LimitFletta(Result.Level);BeforeFletta:=F.Total;
          RateRemainder:=Integer(FDB.ExecSQLScalar('SELECT remainder FROM fletta_rate_carry WHERE id=1'));
          F.CreditKill(TB1008Fletta.KillGain(BeforeLevel,MonsterLevel),FRates.Fletta,Result.Level,RateRemainder);
          FlettaGain:=F.Total-BeforeFletta;
          FDB.ExecSQL('UPDATE fletta_rate_carry SET remainder=:n WHERE id=1',[RateRemainder]);
          FDB.ExecSQL('INSERT OR REPLACE INTO fletta VALUES(1,:n)',[F.Total]);
          FDB.ExecSQL('INSERT INTO fletta_receipts VALUES(:r,:n)',[Receipt,FlettaGain]);
        end;
        FDB.ExecSQL('INSERT OR REPLACE INTO progression(id,total_exp) VALUES(1,:n)',[Result.TotalEXP]);
        FDB.ExecSQL('INSERT INTO exp_receipts(receipt,amount) VALUES(:r,:n)',[Receipt,Gain]);
        AwardSkillLevels(Result.Level);
      end;
      FDB.Commit;
    except FDB.Rollback; raise; end;
  finally FLock.Release; end;
end;

function TB1008LootStore.LimitFletta(Level:Word):TB1008Fletta;
var Capacity:Int64;
begin
  // Caller holds the store lock and an identity-checked transaction. Only free
  // energy is capped: invested attributes and historical receipts stay intact.
  Result.Total:=Int64(FDB.ExecSQLScalar('SELECT COALESCE((SELECT total FROM fletta WHERE id=1),0)'));
  Result.Validate;Capacity:=TB1008Fletta.LevelCapacity(Level,FRates.Fletta);
  if Result.Total>Capacity then begin
    Result.Total:=Capacity;
    FDB.ExecSQL('INSERT OR REPLACE INTO fletta VALUES(1,:n)',[Result.Total]);
  end;
end;

function TB1008LootStore.Fletta(Owner:TObject):TB1008Fletta;
begin
  FLock.Acquire;
  try
    RequireOwner(Owner);
    Result.Total:=Int64(FDB.ExecSQLScalar('SELECT COALESCE((SELECT total FROM fletta WHERE id=1),0)'));
    Result.Validate;
  finally FLock.Release;end;
end;

function TB1008LootStore.ReadFlettaAttributes:TB1008FlettaAttributes;
var Q:TFDQuery;R:TB1008FlettaInvestment;
begin
  Result:=Default(TB1008FlettaAttributes);
  Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FDB;Q.Open('SELECT category,attribute,invested FROM fletta_attributes');
    R:=Default(TB1008FlettaInvestment);R.CharacterID:=1;R.Code:=$87;
    while not Q.Eof do begin
      R.Category:=Q.Fields[0].AsInteger;R.Attribute:=Q.Fields[1].AsInteger;
      R.Amount:=Q.Fields[2].AsInteger;Result.AddInvestment(R);Q.Next;
    end;
  finally Q.Free;end;
  Result.Validate;
end;

function TB1008LootStore.FlettaAttributes(Owner:TObject):TB1008FlettaAttributes;
begin
  FLock.Acquire;
  try RequireOwner(Owner);Result:=ReadFlettaAttributes;
  finally FLock.Release;end;
end;

function TB1008LootStore.InvestFletta(Owner:TObject;const Receipt:string;
  const Request:TB1008FlettaInvestment;out Free:TB1008Fletta;
  out Attributes:TB1008FlettaAttributes):TB1008FlettaInvestmentResult;
begin
  if Receipt='' then raise EArgumentException.Create('Missing Fletta investment receipt');
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      Free.Total:=Int64(FDB.ExecSQLScalar('SELECT COALESCE((SELECT total FROM fletta WHERE id=1),0)'));
      Free.Validate;Attributes:=ReadFlettaAttributes;
      Result:=firRejected;
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM fletta_investments WHERE receipt=:r',[Receipt]))<>0 then
        Result:=firDuplicate
      else if Attributes.CanInvest(Request) then begin
        if Request.Amount>Cardinal(Free.Points) then Result:=firInsufficient
        else begin
          Dec(Free.Total,Int64(Request.Amount)*B1008FlettaThreshold);
          Attributes.AddInvestment(Request);
          FDB.ExecSQL('INSERT OR REPLACE INTO fletta VALUES(1,:n)',[Free.Total]);
          FDB.ExecSQL('INSERT OR REPLACE INTO fletta_attributes VALUES(:c,:a,:n)',
            [Int64(Request.Category),Int64(Request.Attribute),Attributes.Invested(Request.Category)]);
          FDB.ExecSQL('INSERT INTO fletta_investments VALUES(:r,:c,:a,:n)',
            [Receipt,Int64(Request.Category),Int64(Request.Attribute),Int64(Request.Amount)]);
          Result:=firApplied;
        end;
      end;
      FDB.Commit;
    except FDB.Rollback;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.Count(Owner: TObject): Cardinal;
begin
  FLock.Acquire;
  try
    RequireOwner(Owner);
    Result:=Integer(FDB.ExecSQLScalar('SELECT COALESCE(SUM(amount),0) FROM inventory WHERE item_id=90004'));
  finally FLock.Release; end;
end;

function TB1008LootStore.Collect(Owner: TObject; const Receipt: string;
  out NewCount: Cardinal): Boolean;
begin
  Result:=CollectItem(Owner,Receipt,B1008BoneFragmentID,1,NewCount);
end;

function TB1008LootStore.Balance(Owner: TObject): Cardinal;
begin
  FLock.Acquire;
  try
    RequireOwner(Owner);
    Result:=Integer(FDB.ExecSQLScalar('SELECT COALESCE(SUM(amount),0) FROM wallet'));
  finally FLock.Release; end;
end;

function TB1008LootStore.CollectItem(Owner: TObject; const Receipt: string;
  ItemID,Amount: Cardinal; out NewCount: Cardinal): Boolean;
var Updated:TArray<TB1008BagItem>;
begin Result:=CollectItem(Owner,Receipt,ItemID,Amount,NewCount,Updated);end;

function TB1008LootStore.CollectItem(Owner: TObject; const Receipt: string;
  ItemID,Amount: Cardinal; out NewCount: Cardinal;out Updated:TArray<TB1008BagItem>): Boolean;
var Limit,Remaining,Take,OldCount: Cardinal; A: TB1008BagItem;S,N:Integer;GroundInstance:Int64;
  procedure SaveUpdated;
  begin
    SaveItem(A);N:=Length(Updated);SetLength(Updated,N+1);Updated[N]:=A;
  end;
begin
  Updated:=nil;NewCount:=0;
  if Receipt='' then raise EArgumentException.Create('Missing pickup receipt');
  Limit:=TB1008Items.StackLimit(ItemID);
  if Limit=0 then raise EArgumentException.Create('Unsupported loot item');
  if (Amount=0) or (Amount>Limit) then raise EArgumentException.Create('Invalid loot amount');
  FLock.Acquire;
  try
    RequireOwner(Owner);
    FDB.StartTransaction;
    try
      OldCount:=Integer(FDB.ExecSQLScalar('SELECT COALESCE(SUM(amount),0) FROM inventory WHERE item_id=:i',[Int64(ItemID)]));
      NewCount:=OldCount;
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM pickups WHERE receipt=:r',[Receipt]))>0 then
      begin
        if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM pickups WHERE receipt=:r AND item_id=:i AND amount=:n',
          [Receipt,Int64(ItemID),Int64(Amount)]))<>1 then raise Exception.Create('Pickup receipt contents mismatch');
        FDB.Commit; Exit(True);
      end;
      if (ItemID=B1008CaratID) and (OldCount>Limit-Amount) then begin FDB.Rollback;Exit(False);end;
      Remaining:=Amount;
      GroundInstance:=Int64(FDB.ExecSQLScalar('SELECT COALESCE((SELECT instance_id FROM ground WHERE receipt=:r),0)',[Receipt]));
      if (GroundInstance<>0) and (Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM ground WHERE receipt=:r AND item_id=:i AND amount=:a',
        [Receipt,Int64(ItemID),Int64(Amount)]))<>1) then raise Exception.Create('Ground instance pickup mismatch');
      // Fill existing partial stacks in cell order before allocating any cell.
      for S:=0 to B1008BagSlots-1 do begin
        A:=FindSlot(S);
        if (A.ItemID<>ItemID) or (A.Amount>=Limit) then Continue;
        Take:=Limit-A.Amount;if Take>Remaining then Take:=Remaining;
        Inc(A.Amount,Take);Dec(Remaining,Take);SaveUpdated;
        if Remaining=0 then Break;
      end;
      if Remaining>0 then begin
        A:=Default(TB1008BagItem);
        if ItemID=B1008CaratID then A.Slot:=FreeSlot(3) else A.Slot:=FreeSlot(2);
        if A.Slot=255 then begin
          // No partial pickup: keep the original ground item and every cell.
          FDB.Rollback;Updated:=nil;Exit(False);
        end;
        A.ItemID:=ItemID;A.Amount:=Remaining;A.Properties:=ReadProperties(GroundInstance);SaveUpdated;
      end;
      FDB.ExecSQL('INSERT INTO pickups(receipt,item_id,amount) VALUES(:r,:i,:n)',
        [Receipt,Int64(ItemID),Int64(Amount)]);
      FDB.ExecSQL('DELETE FROM ground WHERE receipt=:r',[Receipt]);
      FDB.Commit;
      NewCount:=OldCount+Amount;
      Result:=True;
    except FDB.Rollback;Updated:=nil;raise;end;
  finally FLock.Release; end;
end;

function TB1008LootStore.FindItem(ItemID: Cardinal): TB1008BagItem;
var Q: TFDQuery;
begin
  Result:=Default(TB1008BagItem); Result.ItemID:=ItemID; Result.Slot:=255;
  Q:=TFDQuery.Create(nil);
  try
    // Compatibility lookup: one physical stack, never a total placed in a cell.
    Q.Connection:=FDB; Q.Open('SELECT slot,amount,'+InstanceColumn+' FROM inventory WHERE item_id=:i ORDER BY slot LIMIT 1',[Int64(ItemID)]);
    if not Q.Eof then begin Result.Slot:=Q.Fields[0].AsInteger; Result.Amount:=Q.Fields[1].AsLargeInt;
      Result.Properties:=ReadProperties(Q.Fields[2].AsLargeInt);end;
  finally Q.Free; end;
end;

function TB1008LootStore.FindSlot(Slot: Byte): TB1008BagItem;
var Q: TFDQuery;
begin
  Result:=Default(TB1008BagItem); Result.Slot:=Slot; // Live 06/08 uses item ID 0 for an empty cell.
  Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=FDB; Q.Open('SELECT item_id,amount,'+InstanceColumn+' FROM inventory WHERE slot=:s',[Integer(Slot)]);
    if not Q.Eof then begin Result.ItemID:=Q.Fields[0].AsLargeInt; Result.Amount:=Q.Fields[1].AsLargeInt;
      Result.Properties:=ReadProperties(Q.Fields[2].AsLargeInt);end;
  finally Q.Free; end;
end;

function TB1008LootStore.FreeSlot(Preferred: Byte): Byte;
var S: Integer;
begin
  if (Preferred<B1008BagSlots) and (FindSlot(Preferred).Amount=0) then Exit(Preferred);
  for S:=0 to B1008BagSlots-1 do if FindSlot(S).Amount=0 then Exit(S);
  Result:=255;
end;

procedure TB1008LootStore.SaveItem(var Item: TB1008BagItem);
begin
  if (Item.Slot>=B1008BagSlots) or (TB1008Items.StackLimit(Item.ItemID)=0) or
    (Item.Amount>TB1008Items.StackLimit(Item.ItemID)) then raise EArgumentException.Create('Invalid inventory item');
  if Item.Amount=0 then FDB.ExecSQL('DELETE FROM inventory WHERE slot=:s',[Integer(Item.Slot)])
  else begin
    EnsureProperties(Item.ItemID,Item.Properties);
    FDB.ExecSQL('INSERT OR REPLACE INTO inventory(slot,item_id,amount,instance_id) VALUES(:s,:i,:n,NULLIF(:p,0))',
      [Integer(Item.Slot),Int64(Item.ItemID),Int64(Item.Amount),Item.Properties.InstanceID]);
  end;
end;

function TB1008LootStore.Item(Owner: TObject; ItemID: Cardinal): TB1008BagItem;
begin
  FLock.Acquire;
  try RequireOwner(Owner); Result:=FindItem(ItemID); finally FLock.Release; end;
end;

function TB1008LootStore.Items(Owner: TObject): TArray<TB1008BagItem>;
var Q: TFDQuery; N: Integer;
begin
  Result:=nil; FLock.Acquire;
  try
    RequireOwner(Owner); Q:=TFDQuery.Create(nil);
    try
      Q.Connection:=FDB; Q.Open('SELECT slot,item_id,amount,COALESCE(instance_id,0) FROM inventory ORDER BY slot');
      while not Q.Eof do begin
        N:=Length(Result); SetLength(Result,N+1);
        Result[N].Slot:=Q.Fields[0].AsInteger; Result[N].ItemID:=Q.Fields[1].AsLargeInt;
        Result[N].Amount:=Q.Fields[2].AsLargeInt;Result[N].Properties:=ReadProperties(Q.Fields[3].AsLargeInt); Q.Next;
      end;
    finally Q.Free; end;
  finally FLock.Release; end;
end;

procedure TB1008LootStore.ImportRewards(Owner: TObject; Healing,Mana: Cardinal);
var A: TB1008BagItem; K: Integer;
begin
  if (Healing>3) or (Mana>3) then raise EArgumentException.Create('Invalid legacy rewards');
  FLock.Acquire;
  try
    RequireOwner(Owner); FDB.StartTransaction;
    try
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM operations WHERE receipt=''quest-rewards-imported'''))=0 then begin
        for K:=0 to 1 do begin
          A:=Default(TB1008BagItem);
          if K=0 then begin A.ItemID:=54006; A.Amount:=Healing; end
          else begin A.ItemID:=54206; A.Amount:=Mana; end;
          if A.Amount=0 then Continue;
          if FindItem(A.ItemID).Amount<>0 then raise Exception.Create('Reward import conflict');
          A.Slot:=FreeSlot(K);
          if A.Slot=255 then raise Exception.Create('No room for quest reward');
          SaveItem(A);
        end;
        FDB.ExecSQL('INSERT INTO operations VALUES(''quest-rewards-imported'')');
      end;
      FDB.Commit;
    except FDB.Rollback; raise; end;
  finally FLock.Release; end;
end;

function TB1008LootStore.Swap(Owner: TObject; Source,Target: Byte;
  SourceID,TargetID: Cardinal): Boolean;
var A,B: TB1008BagItem;
begin
  Result:=False;
  if (Source>=B1008BagSlots) or (Target>=B1008BagSlots) or (Source=Target) then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner); FDB.StartTransaction;
    try
      A:=FindSlot(Source); B:=FindSlot(Target);
      if (A.Amount=0) or (A.ItemID<>SourceID) or (B.ItemID<>TargetID) then begin FDB.Rollback; Exit; end;
      FDB.ExecSQL('DELETE FROM inventory WHERE slot IN (:a,:b)',[Integer(Source),Integer(Target)]);
      A.Slot:=Target; SaveItem(A);
      if B.Amount>0 then begin B.Slot:=Source; SaveItem(B); end;
      FDB.Commit; Result:=True;
    except FDB.Rollback; raise; end;
  finally FLock.Release; end;
end;

function TB1008LootStore.SplitItem(Owner: TObject; const Receipt: string;
  Slot: Byte; ItemID: Cardinal; ExpectedCount: UInt64; Amount: Int64;
  out Source, Created: TB1008BagItem): Boolean;
var A,B: TB1008BagItem;
begin
  Result:=False;Source:=Default(TB1008BagItem);Created:=Default(TB1008BagItem);
  // Only catalog items already supporting multiple ordinary stacks. Carat
  // remains a single wallet stack; equipment cannot be divided.
  if (Slot>=B1008BagSlots) or (Receipt='') or (Amount<=0) or
    (ItemID=B1008CaratID) or (TB1008Items.StackLimit(ItemID)<=1) then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      A:=FindSlot(Slot);
      if (A.ItemID<>ItemID) or (A.Amount<>ExpectedCount) or (Amount>=A.Amount) or
        (Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM operations WHERE receipt=:r',[Receipt]))>0) then
      begin FDB.Rollback;Exit;end;
      B:=Default(TB1008BagItem);B.Slot:=FreeSlot(255);
      if B.Slot=255 then begin FDB.Rollback;Exit;end;
      B.ItemID:=A.ItemID;B.Amount:=Cardinal(Amount);
      A.Amount:=A.Amount-B.Amount;
      SaveItem(A);SaveItem(B);
      FDB.ExecSQL('INSERT INTO operations VALUES(:r)',[Receipt]);
      FDB.Commit;Source:=A;Created:=B;Result:=True;
    except FDB.Rollback;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.MergeItems(Owner: TObject; const Receipt: string;
  SourceSlot,TargetSlot: Byte; ItemID: Cardinal; out Source,Target: TB1008BagItem): Boolean;
var A,B:TB1008BagItem;Limit,Take:Cardinal;
begin
  Result:=False;Source:=Default(TB1008BagItem);Target:=Default(TB1008BagItem);
  if (Receipt='') or (SourceSlot>=B1008BagSlots) or (TargetSlot>=B1008BagSlots) or
    (SourceSlot=TargetSlot) then Exit;
  Limit:=TB1008Items.StackLimit(ItemID);
  if (ItemID=B1008CaratID) or (Limit<=1) then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      A:=FindSlot(SourceSlot);B:=FindSlot(TargetSlot);
      if (A.ItemID<>ItemID) or (B.ItemID<>ItemID) or (A.Amount=0) or
        (B.Amount=0) or (B.Amount>=Limit) or
        (Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM operations WHERE receipt=:r',[Receipt]))>0) then
      begin FDB.Rollback;Exit;end;
      Take:=Limit-B.Amount;if Take>A.Amount then Take:=A.Amount;
      A.Amount:=A.Amount-Take;B.Amount:=B.Amount+Take;
      // Uses only two existing cells, so a full backpack can still merge.
      SaveItem(A);SaveItem(B);
      FDB.ExecSQL('INSERT INTO operations VALUES(:r)',[Receipt]);
      FDB.Commit;Source:=A;Target:=B;Result:=True;
    except FDB.Rollback;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.SellItem(Owner:TObject;const Receipt:string;
  const Request:TB1008ShopSell;out Source,Wallet:TB1008BagItem;out Paid:Cardinal):Boolean;
var A,B:TB1008BagItem;D:TB1008ItemDefinition;Value:Int64;
begin
  Result:=False;Source:=Default(TB1008BagItem);Wallet:=Default(TB1008BagItem);Paid:=0;
  if (Receipt='') or not Request.Supported or not TB1008Shop.IsMerchant(Request.NpcHandle) then Exit;
  if not TB1008Items.Find(Request.ItemID,D) or D.QuestItem then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM npc_sales WHERE receipt=:r',[Receipt]))<>0 then
      begin FDB.Rollback;Exit;end;
      A:=FindSlot(Byte(Request.Slot));
      if (A.ItemID<>Request.ItemID) or (Request.Amount>A.Amount) then
      begin FDB.Rollback;Exit;end;
      Value:=Request.Amount*Int64(D.SellPrice);B:=FindItem(B1008CaratID);
      if Value>Int64(B1008CaratLimit)-B.Amount then begin FDB.Rollback;Exit;end;
      // Deleting a whole stack frees its own cell for a previously absent
      // wallet, even in a full bag. Partial sale with no free cell rolls back.
      Dec(A.Amount,Cardinal(Request.Amount));SaveItem(A);
      if Value>0 then begin
        if B.Amount=0 then begin
          B.Slot:=FreeSlot(B1008CaratSlot);
          if B.Slot=255 then begin FDB.Rollback;Exit;end;
        end;
        Inc(B.Amount,Cardinal(Value));SaveItem(B);
      end;
      FDB.ExecSQL('INSERT INTO npc_sales VALUES(:r,:n,:s,:i,:a,:p,:v)',
        [Receipt,Int64(Request.NpcHandle),Integer(Request.Slot),Int64(Request.ItemID),
         Request.Amount,Int64(D.SellPrice),Value]);
      FDB.Commit;Source:=A;Wallet:=B;Paid:=Value;Result:=True;
    except FDB.Rollback;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.BuyItem(Owner:TObject;const Receipt:string;
  const Request:TB1008ShopBuy;out Updated:TArray<TB1008BagItem>;
  out Wallet:TB1008BagItem;out Paid:Cardinal):Boolean;
var D:TB1008ItemDefinition;A,B:TB1008BagItem;Cost:Int64;
  Remaining,Take:Cardinal;S:Integer;
  procedure SaveUpdated;
  begin SaveItem(A);SetLength(Updated,Length(Updated)+1);Updated[High(Updated)]:=A;end;
begin
  Result:=False;Updated:=nil;Wallet:=Default(TB1008BagItem);Paid:=0;
  if (Receipt='') or not Request.Supported then Exit;
  D:=TB1008Items.Get(Request.ItemID);
  if Request.Quantity>D.StackLimit then Exit;
  Cost:=Int64(Request.Quantity)*D.BuyPrice;
  FLock.Acquire;
  try
    RequireOwner(Owner);FDB.StartTransaction;
    try
      if Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM npc_purchases WHERE receipt=:r',[Receipt]))<>0 then
      begin FDB.Rollback;Exit;end;
      B:=FindItem(B1008CaratID);
      if Cost>B.Amount then begin FDB.Rollback;Exit;end;
      if Cost>0 then begin Dec(B.Amount,Cardinal(Cost));SaveItem(B);end;
      Remaining:=Request.Quantity;
      for S:=0 to B1008BagSlots-1 do begin
        A:=FindSlot(S);
        if (A.ItemID<>D.ID) or (A.Amount>=D.StackLimit) then Continue;
        Take:=D.StackLimit-A.Amount;if Take>Remaining then Take:=Remaining;
        Inc(A.Amount,Take);Dec(Remaining,Take);SaveUpdated;
        if Remaining=0 then Break;
      end;
      if Remaining>0 then begin
        A:=Default(TB1008BagItem);A.Slot:=FreeSlot(2);
        if A.Slot=255 then begin FDB.Rollback;Updated:=nil;Exit;end;
        A.ItemID:=D.ID;A.Amount:=Remaining;SaveUpdated;
      end;
      FDB.ExecSQL('INSERT INTO npc_purchases VALUES(:r,:n,:i,:a,:p,:v)',
        [Receipt,Int64(Request.NpcHandle),Int64(D.ID),Int64(Request.Quantity),Int64(D.BuyPrice),Cost]);
      FDB.Commit;Wallet:=B;Paid:=Cost;Result:=True;
    except FDB.Rollback;Updated:=nil;raise;end;
  finally FLock.Release;end;
end;

function TB1008LootStore.ThrowItem(Owner: TObject; const Operation: string;
  Slot: Byte; ItemID: Cardinal; Amount: Int64; var Drop: TB1008GroundDrop;
  out Remaining: Cardinal): Boolean;
var A: TB1008BagItem;
begin
  Result:=False; Remaining:=0;
  if (Slot>=B1008BagSlots) or (Operation='') or
    ((Drop.Receipt='') and not TB1008Items.IsQuestItem(ItemID)) then Exit;
  FLock.Acquire;
  try
    RequireOwner(Owner); FDB.StartTransaction;
    try
      A:=FindSlot(Slot);
      if (A.Amount=0) or (A.ItemID<>ItemID) or
        (Integer(FDB.ExecSQLScalar('SELECT COUNT(*) FROM operations WHERE receipt=:r',[Operation]))>0) then
      begin FDB.Rollback; Exit; end;
      if Amount=-1 then Amount:=A.Amount;
      if (Amount<=0) or (Amount>A.Amount) then begin FDB.Rollback; Exit; end;
      Drop.ItemID:=ItemID; Drop.Amount:=Amount;Drop.Properties:=A.Properties;
      if TB1008Items.IsQuestItem(ItemID) then begin
        Drop.ID:=0;Drop.Collected:=True;Drop.ExpiresUTC:=0;
      end else begin
        Drop.ExpiresUTC:=B1008UtcNowMS+B1008ThrownLootLifetimeMS;
        TB1008LootWire.BuildDrop(0,Drop); // Validate before changing any durable state.
      end;
      A.Amount:=A.Amount-Cardinal(Amount); SaveItem(A); Remaining:=A.Amount;
      if not TB1008Items.IsQuestItem(ItemID) then
        FDB.ExecSQL('INSERT INTO ground(receipt,item_id,amount,x,z,y,expires_ms,instance_id) VALUES(:r,:i,:n,:x,:z,:y,:t,NULLIF(:p,0))',
          [Drop.Receipt,Int64(ItemID),Amount,Double(Drop.X),Double(Drop.Z),Double(Drop.Y),Drop.ExpiresUTC,Drop.Properties.InstanceID]);
      FDB.ExecSQL('INSERT INTO operations VALUES(:r)',[Operation]);
      FDB.Commit; Result:=True;
    except FDB.Rollback; raise; end;
  finally FLock.Release; end;
end;

function TB1008LootStore.GroundItems(Owner: TObject): TArray<TB1008GroundDrop>;
var Q: TFDQuery; N: Integer;
begin
  Result:=nil; FLock.Acquire;
  try
    RequireOwner(Owner); Q:=TFDQuery.Create(nil);
    try
      FDB.ExecSQL('DELETE FROM ground WHERE expires_ms<=:t',[B1008UtcNowMS]);
      Q.Connection:=FDB; Q.Open('SELECT receipt,item_id,amount,x,z,y,expires_ms,COALESCE(instance_id,0) FROM ground ORDER BY receipt');
      while not Q.Eof do begin
        N:=Length(Result); SetLength(Result,N+1); Result[N].OwnerID:=1;
        Result[N].Receipt:=Q.Fields[0].AsString; Result[N].ItemID:=Q.Fields[1].AsLargeInt;
        Result[N].Amount:=Q.Fields[2].AsLargeInt; Result[N].X:=Q.Fields[3].AsFloat;
        Result[N].Z:=Q.Fields[4].AsFloat; Result[N].Y:=Q.Fields[5].AsFloat;
        Result[N].ExpiresUTC:=Q.Fields[6].AsLargeInt;Result[N].Properties:=ReadProperties(Q.Fields[7].AsLargeInt); Q.Next;
      end;
    finally Q.Free; end;
  finally FLock.Release; end;
end;

procedure TB1008LootStore.RemoveGround(Owner: TObject; const Receipt: string);
begin
  FLock.Acquire;
  try RequireOwner(Owner); FDB.ExecSQL('DELETE FROM ground WHERE receipt=:r',[Receipt]);
  finally FLock.Release; end;
end;

function TB1008LootStore.Consume(Owner: TObject; Slot: Byte; ItemID: Cardinal;
  out Remaining: Cardinal;NowMS:Int64): Boolean;
var A: TB1008BagItem;Kind:Integer;UntilMS:Int64;
begin
  Result:=False; Remaining:=0;
  if (Slot>=B1008BagSlots) or not TB1008Items.IsPotion(ItemID) then Exit;
  if NowMS=-1 then NowMS:=B1008UtcNowMS;
  if (NowMS<0) or (NowMS>High(Int64)-60000) then raise EArgumentException.Create('Invalid potion clock');
  Kind:=TB1008PotionEffect.Kind(ItemID);
  FLock.Acquire;
  try
    RequireOwner(Owner); FDB.StartTransaction;
    try
      A:=FindSlot(Slot);
      if (A.Amount=0) or (A.ItemID<>ItemID) then begin FDB.Rollback; Exit; end;
      UntilMS:=Int64(FDB.ExecSQLScalar('SELECT COALESCE((SELECT until_ms FROM potion_cooldowns WHERE kind=:k),0)',[Kind]));
      if NowMS<UntilMS then begin FDB.Rollback;Exit;end;
      Dec(A.Amount); SaveItem(A);
      FDB.ExecSQL('INSERT OR REPLACE INTO potion_cooldowns VALUES(:k,:t)',[Kind,NowMS+TB1008PotionEffect.CooldownMS(ItemID)]);
      FDB.Commit;Remaining:=A.Amount;Result:=True;
    except FDB.Rollback; raise; end;
  finally FLock.Release; end;
end;

end.
