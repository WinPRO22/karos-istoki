unit Emulator.Session;

{$B-}

interface

uses System.SysUtils, Emulator.Protocol.B1008, Emulator.Login.B1008, Emulator.Character.B1008,
  Emulator.WorldState.B1008, Emulator.QuestState.B1008, Emulator.Combat.B1008,
  Emulator.MonsterBalance.B1008,
  Emulator.Content, Emulator.Runtime, Emulator.AI.B1008,
  Emulator.Loot.B1008, Emulator.LootStore.B1008, Emulator.Progression.B1008,
  Emulator.Regen.B1008, Emulator.Fletta.B1008, Emulator.Equipment.B1008, Emulator.Shop.B1008,
  Emulator.Skills.B1008, Emulator.QuickSlots.B1008, Emulator.FlettaProc.B1008,Emulator.Profession.B1008,
  Emulator.ProfessionSkills.B1008,Emulator.ProfessionEffects.B1008,Emulator.Balance.B1008,Emulator.Crafting.B1008,
  Emulator.ItemEnhancement.B1008,Emulator.Mining.B1008;

type
  TSessionStage = (ssConnected, ssLoginObserved, ssEmptyAccountProbe, ssCharacterPreview,
    ssMapLoadingProbe, ssAppearanceProbe, ssClosed);

  TB1008SpiderSlot = record
    Handle: Cardinal;
    Spawn: TEmulatorSpawnDefinition;
    Definition:TEmulatorMobDefinition;
    PlayerMeleeRange:Single;
    Visible:Boolean;
    StunEffectActive:Boolean;
    StunEffectSkillID:Cardinal;
    Coercive:TB1008CoerciveEffect;
    WindBleed:TB1008WindBleed;
    ProfessionEffects:array[0..2] of TB1008ProfessionEffect;
    Encounter: TB1008SpiderEncounter;
    AI: TB1008SpiderAI;
    AttackTimestamp: Cardinal;
    SentChaseSpeed: Single;
  end;

  TEmulatorSession = class
  private
    FDecoder: TB1008FrameDecoder;
    FStage: TSessionStage;
    FLoginMode: TB1008LoginMode;
    FCharacters: TB1008CharacterStore; // Borrowed from server; never freed here.
    FWorld: TB1008WorldStore;
    FQuests: TB1008QuestStore; // Borrowed; nil keeps observe-only quest behavior.
    FOwnWorld: Boolean;
    FWorldState: TB1008WorldSnapshot;
    FMovementAdmission: TB1008MovementAdmission;
    FRuntime: TEmulatorRuntimeManager; // Borrowed from server; survives this session.
    FSpiderContentRevision: Int64;
    FSpiders: TArray<TB1008SpiderSlot>;
    FPlayerHP, FPlayerMP: Integer;
    FPlayerClassID: Word;
    FClassState:TB1008ClassState; // Actual wire profession; combat retains the immutable base family.
    FRegeneration: TB1008Regeneration;
    FRespawnLoading: Boolean;
    FRespawnRequestTimestamp: Cardinal;
    FHasPendingAttack: Boolean;
    FPlayerAutoAttacking: Boolean; // Persists between impacts until cancellation/target death.
    FPendingAttack: TB1008AttackStart;
    FPendingSpiderHandle: Cardinal;
    FSkillCast:TB1008AttackSkillCast;
    FFlettaProc:TB1008FlettaProc;
    FFlettaProcRandomState:Cardinal;
    FTornadoVisualUntilTick:UInt64;
    FTornadoVisualSkillID:Cardinal;
    FFlettaBarrier:TB1008FlettaBarrier;
    FFrenzy:TB1008FrenzyEffect;
    FRevenge,FDeathLeap:TB1008ProfessionEffect;
    FStrengthBonus:Integer;
    FBodyBlowCharge:TB1008ChargeAdmission;
    FSkillImpactUntilTick:UInt64;
    FSkillEndTarget:Cardinal;
    FSkillEndSkillID:Cardinal;
    FSkillEndUntilTick:UInt64;
    FLoot: TB1008LootStore; // Borrowed. Nil disables the diagnostic drop path.
    FDrops: TArray<TB1008GroundDrop>;
    FNextDropID: Cardinal;
    FInventorySessionID: string;
    FNextCraftOperation:UInt64;
    FMinePending:Boolean;
    FMineStartedTick,FMineNextTick:UInt64;
    FMineStartTimestamp:Cardinal;
    FStashNpcHandle:Cardinal;
    FClientInWorld: Boolean;
    FParameterLevel: Word;
    FAutoWorldStartTick: UInt64;
    FWorldPatrolStarted: Boolean;
    FCombatFormationHeading: Single;
    FProgress: TB1008Progress;
    FFletta: TB1008Fletta;
    FFlettaAttributes: TB1008FlettaAttributes;
    FEquipment: TArray<TB1008EquipmentItem>;
    FCombatRandomState:Cardinal;
    FDropRandomState:Cardinal; // Independent stream: drop rolls cannot change combat rolls.
    FQuestDropRandomState:Cardinal;
    FNextKillID: UInt64;
    FNextDeathID: UInt64;
    FHasPotionUse: array[0..1] of Boolean;
    FLastPotionTimestamp: array[0..1] of Cardinal;
    FPotionUntil:array[0..1] of UInt64;
    function PlayerMaxHP: Integer;
    function PlayerAttributes:TB1008BaseAttributes;
    procedure PermanentAttackRange(out Minimum,Maximum:Integer);
    function PermanentPhysicalDefense:Integer;
    function FlettaRate:Integer;
    function PlayerSkillList(Timestamp:Cardinal):TBytes;
    function ResolveTargetImpact(const AttackDecide:TB1008AttackDecide;
      out AReplies:TB1008Replies;AreaAdmission:Boolean=False):string;
    function HandleProfessionImpact(const Packet:TBytes;out Replies:TB1008Replies):string;
    procedure ApplyProfessionHit(AIndex:Integer;Timestamp:Cardinal;NowTick:UInt64;var Replies:TB1008Replies);
    procedure PollProfessionEffects(AIndex:Integer;NowTick:UInt64;var Replies:TB1008Replies);
    procedure RemoveProfessionEffects(AIndex:Integer;Timestamp:Cardinal;var Replies:TB1008Replies);
    procedure RefreshProfessionSpeed(AIndex:Integer;Timestamp:Cardinal;NowTick:UInt64;var Replies:TB1008Replies);
    function MobProfessionSpeed(AIndex:Integer;NowTick:UInt64;ModifierType:Cardinal=27):Single;
    procedure PollProfessionBuffs(NowTick:UInt64;var Replies:TB1008Replies);
    procedure ApplyProfessionSpeeds(var Packet:TBytes);
    function CommitMobKill(AIndex:Integer;Timestamp:Cardinal;var Replies:TB1008Replies):string;
    procedure PollWindBleed(AIndex:Integer;NowTick:UInt64;var Replies:TB1008Replies);
    procedure RemoveWindBleed(AIndex:Integer;Timestamp:Cardinal;var Replies:TB1008Replies);
    function PlayerHitRange(AIndex:Integer;ActionKind:Byte;ActionID:Cardinal=1004):Single;
    function PlayerMaxMP: Integer;
    function PlayerGage(Timestamp: Cardinal; IncludeEXP: Boolean): TBytes;
    procedure AcceptProgress(const Progress:TB1008Progress);
    procedure ApplyPlayerParameters(var Packet:TBytes);
    function SkillAttackBonus(NowTick:UInt64):Integer;
    function ProfessionAttackBonus:Integer;
    function SkillWeaponAllowed(SkillID:Cardinal):Boolean;
    function SkillDefensePenalty(NowTick:UInt64):Integer;
    procedure RemoveFrenzy(Timestamp:Cardinal;var Replies:TB1008Replies);
    procedure RemoveFlettaBarrier(Timestamp:Cardinal;var Replies:TB1008Replies);
    function HandleCatalogQuest(const Packet:TBytes;out Replies:TB1008Replies):string;
    function HandleStash(const Packet:TBytes;out Replies:TB1008Replies):string;
    function HandleReturn(const Packet:TBytes;out Replies:TB1008Replies):string;
    function HandleClassChange(const Packet:TBytes;out Replies:TB1008Replies):string;
    procedure ApplyReturnInfo(var Packet:TBytes);
    procedure RecoverReturn;
    procedure AppendReturnCooldown(Timestamp:Cardinal;var Replies:TB1008Replies);
    function HandlePacketCore(const APayload:TBytes;out AReplies:TB1008Replies):string;
    procedure AppendCatalogQuests(Timestamp:Cardinal;var Replies:TB1008Replies);
    procedure AppendQuestItems(Timestamp:Cardinal;const Items:TArray<TB1008BagItem>;var Replies:TB1008Replies);
    procedure StartWorldPatrol(ANowTick: UInt64);
    procedure AppendSpiderMotionReset(AIndex: Integer; Timestamp: Cardinal;
      var AReplies: TB1008Replies);
    procedure UpdateMobVisibility(ANowTick:UInt64;var Replies:TB1008Replies);
    procedure RemoveSpiderStunEffect(AIndex:Integer;Timestamp:Cardinal;var Replies:TB1008Replies);
    procedure RemoveSpiderCoercive(AIndex:Integer;Timestamp:Cardinal;var Replies:TB1008Replies);
    function CreateSpiderDrop(Timestamp,ItemID,Amount: Cardinal; X,Z,Y: Single): TBytes;
    procedure SyncSpiderContent;
    function FindSpiderIndex(AHandle: Cardinal): Integer;
    function PollSpider(AIndex: Integer; ANowTick: UInt64;
      out AReplies: TB1008Replies): string;
  public
    constructor Create(ALoginMode: TB1008LoginMode = blObserveOnly;
      ACharacters: TB1008CharacterStore = nil; AWorld: TB1008WorldStore = nil;
      AQuests: TB1008QuestStore = nil; ARuntime: TEmulatorRuntimeManager = nil;
      ALoot: TB1008LootStore = nil; ADropSeed:Cardinal = 0; ACombatSeed:Cardinal = 0;
      AProcSeed:Cardinal = 0);
    destructor Destroy; override;
    // Returns a description with no string/credential contents.
    function HandlePacket(const APayload: TBytes; out AReplies: TB1008Replies): string;
    function PollWorld(ANowTick: UInt64; out AReplies: TB1008Replies): string;
    procedure Close;
    property Decoder: TB1008FrameDecoder read FDecoder;
    property Stage: TSessionStage read FStage;
    // Value snapshot; only access on this session's worker (not directly from VCL).
    property WorldState: TB1008WorldSnapshot read FWorldState;
  end;

implementation

uses Winapi.Windows, System.Math, System.Generics.Collections,
  Emulator.World.B1008, Emulator.Quest.B1008, Emulator.Inventory.B1008,
  Emulator.Items.B1008, Emulator.DropProfile.B1008, Emulator.Berneo.B1008,
  Emulator.Npcs.B1008,Emulator.QuestCatalog.B1008,Emulator.Rates.B1008,Emulator.Stash.B1008,
  Emulator.Return.B1008;

{$I Emulator.Session.Quests.inc}
{$I Emulator.Session.Stash.inc}
{$I Emulator.Session.Return.inc}
{$I Emulator.Session.Class.inc}

function TEmulatorSession.PlayerSkillList(Timestamp:Cardinal):TBytes;
var Skills:TArray<TB1008LearnedSkill>;N:Integer;DerivedID:Cardinal;
begin
  Skills:=FLoot.LearnedSkills(Self);
  DerivedID:=TB1008FlettaProc.CombinedSkill(FFlettaAttributes);
  if TB1008FlettaProc.Enabled(DerivedID) then begin
    N:=Length(Skills);SetLength(Skills,N+1);Skills[N].ID:=DerivedID;Skills[N].Rank:=1;
  end;
  // Derived grant: no SP receipt, no new persistent skill, removed if pair changes.
  Result:=TB1008SkillWire.BuildList(Timestamp,Skills);
end;

function TEmulatorSession.PlayerHitRange(AIndex:Integer;ActionKind:Byte;ActionID:Cardinal):Single;
var SkillID,Rank:Cardinal;Skill:TB1008LearnedSkill;
begin
  Result:=FSpiders[AIndex].PlayerMeleeRange;
  SkillID:=TB1008AttackSkillStats.FromAction(ActionID);
  if (ActionKind=1) and TB1008FlettaProc.YinSupported(SkillID) and
    (FFlettaProc.Target=FSpiders[AIndex].Handle) and FFlettaProc.Active(GetTickCount64) then
    Exit(FFlettaProc.GrantedRange); // Bound to the admitted source hit and its original target.
  if (ActionKind=1) and (SkillID<>0) then begin
    Rank:=1;
    if Assigned(FLoot) then for Skill in FLoot.LearnedSkills(Self) do
      if Skill.ID=SkillID then Rank:=Skill.Rank;
    Result:=Max(Result,(TB1008Berneo.Mob(FSpiders[AIndex].Spawn.MobID).ClientRadius+
      TB1008AttackSkillStats.Get(SkillID,Rank).Range)*B1008PlayerMeleeRangeScale);
  end;
end;

function TEmulatorSession.FlettaRate:Integer;
begin
  if Assigned(FLoot) then Result:=FLoot.Rates.Fletta else Result:=100;
end;

function TEmulatorSession.PlayerAttributes:TB1008BaseAttributes;
begin
  Result:=TB1008Balance.ProfessionAttributes(FPlayerClassID,FClassState.ClassID,FClassState.Rank,FProgress.Level);
end;

function TEmulatorSession.PlayerMaxHP: Integer;
begin
  if (FPlayerClassID=100) or (FPlayerClassID=300) or (FPlayerClassID=500) then
    Result:=TB1008Balance.ProfessionMaxHP(FPlayerClassID,FClassState.ClassID,FProgress.Level)
  else Result:=B1008ProbeHP;
end;
function TEmulatorSession.PlayerMaxMP: Integer;
begin
  if (FPlayerClassID=100) or (FPlayerClassID=300) or (FPlayerClassID=500) then
    Result:=TB1008Balance.ProfessionMaxMP(FPlayerClassID,FClassState.ClassID,FProgress.Level)
  else Result:=B1008ProbeMP;
end;
function TEmulatorSession.PlayerGage(Timestamp: Cardinal; IncludeEXP: Boolean): TBytes;
begin
  if IncludeEXP then Result:=TB1008ProgressWire.BuildHeroGage(Timestamp,FPlayerHP,FPlayerMP,FProgress,PlayerMaxHP,PlayerMaxMP)
  else Result:=TB1008CombatWire.BuildPlayerGageProbe(Timestamp,FPlayerHP,FPlayerMP,FProgress.Level,PlayerMaxHP,PlayerMaxMP);
  TB1008ProgressWire.ApplyVitals(Result,FPlayerHP,FPlayerMP,PlayerMaxHP,PlayerMaxMP);
  FFlettaAttributes.ApplySpeeds(Result);
  ApplyProfessionSpeeds(Result);
  if IncludeEXP then FFletta.Apply(Result,FProgress.Level,FlettaRate);
  if IncludeEXP and Assigned(FLoot) then
    TB1008ProgressWire.ApplySkillPoints(Result,FLoot.SkillPoints(Self));
end;

procedure TEmulatorSession.AcceptProgress(const Progress:TB1008Progress);
var PreviousLevel:Word;
begin
  PreviousLevel:=FProgress.Level;
  FProgress:=Progress;
  // Refill once, at the committed level increase, before its HP/EXP packet.
  // Replayed rewards, ordinary EXP gains and level loss do not heal.
  if (FProgress.Level>PreviousLevel) and (FPlayerHP>0) then begin
    FPlayerHP:=PlayerMaxHP;FPlayerMP:=PlayerMaxMP;
  end;
end;

function TEmulatorSession.SkillWeaponAllowed(SkillID:Cardinal):Boolean;
var Gear:TB1008EquipmentItem;
begin
  Result:=TB1008ProfessionSkill.Supported(SkillID) and
    not TB1008ProfessionSkill.Get(SkillID,1).WeaponRequired and
    (TB1008ProfessionSkill.Get(SkillID,1).WeaponMask=0);
  for Gear in FEquipment do if Gear.Slot=7 then
    Exit(TB1008ProfessionSkill.WeaponAllowed(SkillID,TB1008Items.Get(Gear.ItemID).Subtype));
end;

procedure TEmulatorSession.PermanentAttackRange(out Minimum,Maximum:Integer);
var OriginalBase,Base:Integer;
begin
  TB1008Equipment.PhysicalAttack(FPlayerClassID,FEquipment,Minimum,Maximum,FProgress.Level);
  OriginalBase:=TB1008Balance.BaseAttributes(FPlayerClassID,FProgress.Level).PhysicalAttack;
  Base:=TB1008Balance.ProfessionPhysicalAttack(FClassState.ClassID,PlayerAttributes.PhysicalAttack);
  // Round the permanent base and each truncated weapon endpoint separately.
  // Native character UI uses the same components; temporary additions follow.
  Minimum:=Base+TB1008Balance.ProfessionPhysicalAttack(FClassState.ClassID,Minimum-OriginalBase);
  Maximum:=Base+TB1008Balance.ProfessionPhysicalAttack(FClassState.ClassID,Maximum-OriginalBase);
end;

function TEmulatorSession.PermanentPhysicalDefense:Integer;
begin
  Result:=TB1008Balance.ProfessionPhysicalDefense(FClassState.ClassID,
    PlayerAttributes.PhysicalDefense+TB1008Equipment.Defense(FEquipment));
end;

function TEmulatorSession.ProfessionAttackBonus:Integer;
var Skill:TB1008LearnedSkill;P:TB1008ProfessionSkill;
begin
  Result:=0;
  if not Assigned(FLoot) then Exit;
  for Skill in FLoot.LearnedSkills(Self) do
    if ((Skill.ID=B1008SwordMasteryID) or (Skill.ID=B1008PolearmMasteryID)) and
      TB1008ProfessionSkill.Allowed(Skill.ID,FClassState.ClassID) and SkillWeaponAllowed(Skill.ID) then
    begin
      P:=TB1008ProfessionSkill.Get(Skill.ID,Skill.Rank);
      Inc(Result,P.AttackBonus+Integer((Int64(PlayerAttributes.PhysicalAttack)*P.AttackPercent+50) div 100));
    end;
end;

function TEmulatorSession.SkillAttackBonus(NowTick:UInt64):Integer;
begin
  // Authored balance: one additional STR gives one attack, additive after
  // the existing Fletta multiplier. Base class STR is already in base attack.
  Result:=FStrengthBonus+ProfessionAttackBonus;
  if FFrenzy.Active(NowTick) then Inc(Result,TB1008FrenzyRank.Get(FFrenzy.Rank).AttackBonus);
  if FDeathLeap.Active(NowTick) then Inc(Result,Integer((Int64(
    PlayerAttributes.PhysicalAttack)*
    TB1008ProfessionSkill.Get(FDeathLeap.SkillID,FDeathLeap.Rank).AttackPercent+50) div 100));
end;

function TEmulatorSession.SkillDefensePenalty(NowTick:UInt64):Integer;
begin
  Result:=0;
  if FFrenzy.Active(NowTick) then Result:=TB1008FrenzyRank.Get(FFrenzy.Rank).DefensePenalty;
  if FDeathLeap.Active(NowTick) then Inc(Result,Integer((Int64(Max(0,
    FFlettaAttributes.Defense(PermanentPhysicalDefense)-Result))*
    TB1008ProfessionSkill.Get(FDeathLeap.SkillID,FDeathLeap.Rank).DefensePenaltyPercent+50) div 100));
end;

procedure TEmulatorSession.RemoveFrenzy(Timestamp:Cardinal;var Replies:TB1008Replies);
var Rank:Cardinal;
begin
  Rank:=FFrenzy.Rank;
  if not FFrenzy.Remove then Exit;
  SetLength(Replies,Length(Replies)+2);
  Replies[High(Replies)-1]:=TB1008SkillWire.BuildFrenzy(Timestamp,Rank,False);
  Replies[High(Replies)]:=TB1008ProgressWire.BuildParameters(Timestamp,FPlayerClassID,FProgress.Level);
  ApplyPlayerParameters(Replies[High(Replies)]);
end;

procedure TEmulatorSession.RemoveFlettaBarrier(Timestamp:Cardinal;var Replies:TB1008Replies);
var ID:Cardinal;
begin
  ID:=FFlettaBarrier.SkillID;if ID=0 then Exit;
  FFlettaBarrier.Clear;
  SetLength(Replies,Length(Replies)+1);
  Replies[High(Replies)]:=TB1008FlettaProc.BuildBuff(Timestamp,ID,0,False);
end;

procedure TEmulatorSession.ApplyPlayerParameters(var Packet:TBytes);
var Minimum,Maximum,Offset,Penalty:Integer;Skill:TB1008LearnedSkill;Strength:Word;Value:Single;
  Base:TB1008BaseAttributes;
begin
  FStrengthBonus:=TB1008Equipment.GemStrength(FEquipment);
  if Assigned(FLoot) and (FPlayerClassID=100) then
    for Skill in FLoot.LearnedSkills(Self) do if Skill.ID=B1008StrengthMasteryID then Inc(FStrengthBonus,Skill.Rank);
  if (Packet[0]=2) and (Packet[1]=5) and Assigned(FLoot) then begin
    TB1008ProgressWire.ApplySkillPoints(Packet,FLoot.SkillPoints(Self));
    TB1008QuickSlotWire.ApplyCharacterInfo(Packet,FLoot.QuickSlots(Self));
  end;
  TB1008Equipment.ApplyParameters(Packet,FPlayerClassID,FEquipment);
  Base:=PlayerAttributes;
  FFlettaAttributes.ApplyRegeneration(Packet,Base.RegenHP,Base.RegenMP);
  FFlettaAttributes.ApplySecondaryParameters(Packet,Base.MagicalAttack,Base.PhysicalDefense,
    PermanentPhysicalDefense-Base.PhysicalDefense);
  PermanentAttackRange(Minimum,Maximum);
  FFlettaAttributes.ApplyAttackParameters(Packet,PlayerAttributes.PhysicalAttack,Minimum,Maximum);
  if Packet[0]=2 then Offset:=$373 else Offset:=10;
  // Keep Fletta/passive/buff additions unscaled; only the permanent base changes.
  Move(Packet[Offset+$50],Value,4);
  Value:=Value+TB1008Balance.ProfessionPhysicalAttack(FClassState.ClassID,Base.PhysicalAttack)-Base.PhysicalAttack;
  Move(Value,Packet[Offset+$50],4);
  Value:=PlayerMaxHP;Move(Value,Packet[Offset+$B0],4);
  Value:=PlayerMaxMP;Move(Value,Packet[Offset+$28],4);
  Value:=Base.CriticalBasisPoints/100;Move(Value,Packet[Offset+$A0],4);
  // Native 46B45F/46B521 adds equipped primary-stat gems to +02/+0E.
  // Send only non-gem STR here; diamond attack still belongs in +50 and
  // authoritative damage because the weapon renderer only adds gem types6/7.
  Move(Packet[Offset+2],Strength,2);
  Inc(Strength,FStrengthBonus-TB1008Equipment.GemStrength(FEquipment));Move(Strength,Packet[Offset+2],2);
  Move(Packet[Offset+$50],Value,4);Value:=Value+SkillAttackBonus(GetTickCount64);Move(Value,Packet[Offset+$50],4);
  Penalty:=SkillDefensePenalty(GetTickCount64);
  Move(Packet[Offset+$5C],Value,4);Value:=Max(0,Value-Penalty);Move(Value,Packet[Offset+$5C],4);
  Move(Packet[Offset+$94],Value,4);Value:=Value-Penalty;Move(Value,Packet[Offset+$94],4);
  if FDeathLeap.Active(GetTickCount64) then begin
    Move(Packet[Offset+$74],Value,4);Value:=Value*(1-
      TB1008ProfessionSkill.Get(FDeathLeap.SkillID,FDeathLeap.Rank).DefensePenaltyPercent/100);
    Move(Value,Packet[Offset+$74],4);
  end;
  if Packet[0]=2 then ApplyProfessionSpeeds(Packet);
end;

constructor TEmulatorSession.Create(ALoginMode: TB1008LoginMode;
  ACharacters: TB1008CharacterStore; AWorld: TB1008WorldStore;
  AQuests: TB1008QuestStore; ARuntime: TEmulatorRuntimeManager;
  ALoot: TB1008LootStore; ADropSeed,ACombatSeed,AProcSeed:Cardinal);
var G: TGUID;
begin
  inherited Create;
  CreateGUID(G); FInventorySessionID:=GUIDToString(G);
  FCombatRandomState:=G.D1;
  if ACombatSeed<>0 then FCombatRandomState:=ACombatSeed; // Offline deterministic tests only.
  CreateGUID(G);FFlettaProcRandomState:=G.D1;
  if AProcSeed<>0 then FFlettaProcRandomState:=AProcSeed;
  CreateGUID(G);FDropRandomState:=G.D1;
  if ADropSeed<>0 then FDropRandomState:=ADropSeed; // Offline deterministic tests only.
  FQuestDropRandomState:=FDropRandomState xor $A341316C;
  FDecoder := TB1008FrameDecoder.Create;
  FRuntime := ARuntime;
  FLoot:=ALoot;
  SetLength(FSpiders,2);
  FSpiders[0].Handle:=B1008SpiderHandle;
  FSpiders[1].Handle:=B1008SecondSpiderHandle;
  SyncSpiderContent;
  FPlayerHP:=B1008ProbeHP; FPlayerMP:=B1008ProbeMP;
  FStage := ssConnected;
  FLoginMode := ALoginMode;
  FCharacters := ACharacters;
  FWorld := AWorld;
  FQuests := AQuests;
  FOwnWorld := AWorld=nil;
  if FOwnWorld then FWorld := TB1008WorldStore.Create;
end;

procedure TEmulatorSession.AppendSpiderMotionReset(AIndex: Integer;
  Timestamp: Cardinal; var AReplies: TB1008Replies);
var N: Integer; Spawn: TEmulatorSpawnDefinition; Heading: Single;
begin
  Spawn:=FSpiders[AIndex].Spawn; N:=Length(AReplies);
  Spawn.X:=FSpiders[AIndex].AI.X;Spawn.Z:=FSpiders[AIndex].AI.Z;
  Spawn.Y:=FSpiders[AIndex].AI.Y;Spawn.Heading:=FSpiders[AIndex].AI.Heading;
  SetLength(AReplies,N+2);
  // 04/02 sets NPC position but not active movement speed (+$1B8).
  // 04/01 mode 0 with equal endpoints initializes that scalar from the
  // positive run speed (4E11F1..4E120B), with zero direction. Immediately
  // stop at the same point, so admission never implies a patrol step.
  AReplies[N]:=TB1008World.BuildActorMovement(Timestamp,1,0,
    FSpiders[AIndex].Handle,Spawn.X,Spawn.Z,Spawn.Y,
    Spawn.X,Spawn.Z,Spawn.Y,Spawn.Heading);
  Heading:=Spawn.Heading+Pi;
  while Heading>=2*Pi do Heading:=Heading-2*Pi;
  AReplies[N+1]:=TB1008World.BuildActorMovement(Timestamp,1,2,
    FSpiders[AIndex].Handle,Spawn.X,Spawn.Z,Spawn.Y,
    Spawn.X,Spawn.Z,Spawn.Y,Heading);
end;

procedure TEmulatorSession.StartWorldPatrol(ANowTick: UInt64);
var I: Integer;
begin
  if FWorldPatrolStarted then Exit;
  for I:=0 to High(FSpiders) do FSpiders[I].AI.Reset(ANowTick,I);
  FWorldPatrolStarted:=True;
end;

procedure TEmulatorSession.UpdateMobVisibility(ANowTick:UInt64;var Replies:TB1008Replies);
var I,N,Admissions,HP:Integer;S:^TB1008SpiderSlot;D2:Double;
begin
  Admissions:=0;
  for I:=0 to High(FSpiders) do begin
    S:=@FSpiders[I];S^.AI.UpdatePosition(ANowTick);
    D2:=Sqr(S^.AI.X-FWorldState.Position.X)+Sqr(S^.AI.Z-FWorldState.Position.Z);
    if S^.Visible and (S^.Spawn.MobID<>120) and (D2>Sqr(1100.0)) and not S^.AI.Engaged then begin
      RemoveSpiderStunEffect(I,ANowTick and $FFFFFFFF,Replies);
      RemoveSpiderCoercive(I,ANowTick and $FFFFFFFF,Replies);
      RemoveWindBleed(I,ANowTick and $FFFFFFFF,Replies);
      RemoveProfessionEffects(I,ANowTick and $FFFFFFFF,Replies);
      N:=Length(Replies);SetLength(Replies,N+1);
      Replies[N]:=TB1008World.BuildActorDisappear(ANowTick and $FFFFFFFF,1,S^.Handle);
      S^.Visible:=False;
    end;
    if not S^.Visible and (S^.Encounter.HP>0) and
      ((S^.Spawn.MobID=120) or (D2<=Sqr(900.0))) and (Admissions<8) then begin
      S^.AI.PauseForAdmission(ANowTick);
      N:=Length(Replies);SetLength(Replies,N+1);
      Replies[N]:=TB1008World.BuildSpiderAppearProbe(ANowTick and $FFFFFFFF,S^.Handle,
        S^.Definition.MaxHP,S^.Definition.MovementSpeed,S^.Definition.ChaseSpeed,S^.Definition.AttackSpeed,
        S^.AI.X,S^.AI.Z,S^.AI.Y,S^.AI.Heading);
      HP:=S^.Encounter.HP;Move(HP,Replies[N][28],4);
      AppendSpiderMotionReset(I,ANowTick and $FFFFFFFF,Replies);
      S^.SentChaseSpeed:=S^.Definition.ChaseSpeed;S^.Visible:=True;Inc(Admissions);
    end;
  end;
end;

procedure TEmulatorSession.RemoveSpiderStunEffect(AIndex:Integer;Timestamp:Cardinal;var Replies:TB1008Replies);
begin
  if not FSpiders[AIndex].StunEffectActive then Exit;
  if FSpiders[AIndex].Visible then begin
    SetLength(Replies,Length(Replies)+1);
    if TB1008ProfessionSkill.Supported(FSpiders[AIndex].StunEffectSkillID) then
      Replies[High(Replies)]:=TB1008SkillWire.BuildProfessionEffect(Timestamp,1,FSpiders[AIndex].Handle,
        FSpiders[AIndex].StunEffectSkillID,1,0,False)
    else Replies[High(Replies)]:=TB1008SkillWire.BuildMobStun(Timestamp,FSpiders[AIndex].Handle,False,
      FSpiders[AIndex].StunEffectSkillID);
  end;
  FSpiders[AIndex].StunEffectActive:=False;
  FSpiders[AIndex].StunEffectSkillID:=0;
end;

procedure TEmulatorSession.RemoveSpiderCoercive(AIndex:Integer;Timestamp:Cardinal;var Replies:TB1008Replies);
begin
  if FSpiders[AIndex].Coercive.Rank=0 then Exit;
  if FSpiders[AIndex].Visible then begin
    SetLength(Replies,Length(Replies)+1);
    Replies[High(Replies)]:=TB1008SkillWire.BuildMobCoercive(Timestamp,FSpiders[AIndex].Handle,
      FSpiders[AIndex].Coercive.Rank,False);
  end;
  FSpiders[AIndex].Coercive.Clear;
end;

procedure TEmulatorSession.RemoveWindBleed(AIndex:Integer;Timestamp:Cardinal;var Replies:TB1008Replies);
begin
  if FSpiders[AIndex].WindBleed.Rank=0 then Exit;
  if FSpiders[AIndex].Visible then begin
    SetLength(Replies,Length(Replies)+1);
    Replies[High(Replies)]:=TB1008SkillWire.BuildMobWindBlade(Timestamp,FSpiders[AIndex].Handle,
      FSpiders[AIndex].WindBleed.Rank,False);
  end;
  FSpiders[AIndex].WindBleed.Clear;
end;

procedure TEmulatorSession.PollWindBleed(AIndex:Integer;NowTick:UInt64;var Replies:TB1008Replies);
var Spider:^TB1008SpiderSlot;Damage:Integer;R:TB1008AttackStart;Due:TB1008WindBleed;
  QuestProgress:Cardinal;LegacyQuest:Boolean;
begin
  Spider:=@FSpiders[AIndex];
  if Spider^.WindBleed.Rank=0 then Exit;
  if (FPlayerHP<=0) or (Spider^.Encounter.HP=0) or not Spider^.Visible then begin
    RemoveWindBleed(AIndex,NowTick and $FFFFFFFF,Replies);Exit;
  end;
  Due:=Spider^.WindBleed;
  while Due.TakeDue(NowTick,Damage) do begin
    QuestProgress:=0;
    LegacyQuest:=(Spider^.Encounter.HP<=Damage) and (Spider^.Spawn.MobID=120) and
      Assigned(FQuests) and FQuests.Active(Self) and (FQuests.Progress(Self)<5);
    if LegacyQuest then QuestProgress:=FQuests.RecordSpiderKill(Self);
    Spider^.WindBleed:=Due;
    if not Spider^.Encounter.ApplyPeriodicDamage(Damage,NowTick) then Break;
    R:=Default(TB1008AttackStart);R.Timestamp:=NowTick and $FFFFFFFF;
    R.ActorID:=1;R.ActionKind:=1;R.ActionID:=1008;R.TargetKind:=1;R.TargetID:=Spider^.Handle;
    SetLength(Replies,Length(Replies)+2);
    Replies[High(Replies)-1]:=TB1008CombatWire.BuildSpiderDamageProbe(R,
      Spider^.AI.X,Spider^.AI.Z,Spider^.AI.Y,Damage);
    Replies[High(Replies)]:=TB1008CombatWire.BuildSpiderGageProbe(R.Timestamp,Spider^.Handle,
      Spider^.Encounter.HP,Spider^.Definition.MaxHP,Spider^.Definition.MovementSpeed*MobProfessionSpeed(AIndex,NowTick),
      Spider^.AI.ActiveChaseSpeed,Spider^.Definition.AttackSpeed*MobProfessionSpeed(AIndex,NowTick,13));
    if LegacyQuest then begin
      SetLength(Replies,Length(Replies)+1);
      Replies[High(Replies)]:=TB1008QuestWire.BuildProgress(R.Timestamp,QuestProgress);
    end;
    if Spider^.Encounter.HP=0 then begin
      RemoveSpiderStunEffect(AIndex,R.Timestamp,Replies);
      RemoveSpiderCoercive(AIndex,R.Timestamp,Replies);
      RemoveWindBleed(AIndex,R.Timestamp,Replies);
      RemoveProfessionEffects(AIndex,R.Timestamp,Replies);
      if FPendingAttack.TargetID=Spider^.Handle then begin
        FPlayerAutoAttacking:=False;
        FHasPendingAttack:=False;FPendingSpiderHandle:=0;
        // Retain the admitted skill-finish context: native selection can
        // already be zero when another cast loses its target to this tick.
      end;
      if (FFlettaProc.Phase<>fppIdle) and (FFlettaProc.Target=Spider^.Handle) then begin
        FFlettaProc.Clear;SetLength(Replies,Length(Replies)+1);
        Replies[High(Replies)]:=TB1008FlettaProc.BuildTrigger(R.Timestamp,High(Cardinal));
      end;
      CommitMobKill(AIndex,R.Timestamp,Replies);Break;
    end;
  end;
  if Spider^.WindBleed.RemainingTicks=0 then RemoveWindBleed(AIndex,NowTick and $FFFFFFFF,Replies);
end;

procedure TEmulatorSession.SyncSpiderContent;
var Snapshot:IEmulatorContentSnapshot;Definition:TEmulatorMobDefinition;
  Spawn,Temp:TEmulatorSpawnDefinition;Groups,Selected:TArray<TEmulatorSpawnDefinition>;
  Candidates,Expanded:TList<TEmulatorSpawnDefinition>;I,J,K,Variant:Integer;
  Angle,Distance,DX,DZ,W,Sum,YSum:Double;Rebuild:Boolean;
begin
  if Assigned(FRuntime) then begin
    Snapshot:=FRuntime.AcquireSnapshot;
    if not Assigned(Snapshot) then raise EEmulatorContent.Create('Live content not loaded');
    if Snapshot.Revision=FSpiderContentRevision then Exit;
    Candidates:=TList<TEmulatorSpawnDefinition>.Create;
    Expanded:=TList<TEmulatorSpawnDefinition>.Create;
    try
      for Spawn in Snapshot.GetSpawns do
        if Spawn.Enabled and (Spawn.MapID=B1008BerneoMapID) then begin
          if (TB1008Berneo.TemplateForHandle(Spawn.EntityHandle)<>Spawn.EntityHandle) or
            (Spawn.SpawnID<>Spawn.EntityHandle) then raise EEmulatorContent.Create('Unknown Berneo source handle');
          Candidates.Add(Spawn);
        end;
      Groups:=Candidates.ToArray;
      for I:=0 to High(Groups)-1 do for J:=I+1 to High(Groups) do
        if Groups[J].EntityHandle<Groups[I].EntityHandle then begin
          Temp:=Groups[I];Groups[I]:=Groups[J];Groups[J]:=Temp;
        end;
      for I:=0 to High(Groups) do begin
        if not Snapshot.TryGetMob(Groups[I].MobID,Definition) then
          raise EEmulatorContent.Create('Spawn has no enabled definition');
        Variant:=0;
        for K:=0 to I-1 do if Groups[K].MobID=Groups[I].MobID then Inc(Variant);
        for J:=0 to Groups[I].Population-1 do begin
          Temp:=Groups[I];
          Temp.EntityHandle:=TB1008Berneo.MemberHandle(Groups[I].EntityHandle,J);
          Temp.SpawnID:=Temp.EntityHandle;Temp.Population:=1;Temp.SpawnRadius:=0;
          if J>0 then begin
            if J=Groups[I].Population-1 then Distance:=Groups[I].SpawnRadius
            else Distance:=Min(Groups[I].SpawnRadius*Sqrt(J/(Groups[I].Population-1)),37.0*J);
            Angle:=J*2.399963229728653+Variant*0.731;
            Temp.X:=Groups[I].X+Distance*Cos(Angle);
            Temp.Z:=Groups[I].Z+Distance*Sin(Angle);
            Sum:=0;YSum:=0;
            // Approximate height between same-species source anchors. Exact
            // individual positions/navmesh heights are not stored in NPC groups.
            for K:=0 to High(Groups) do if Groups[K].MobID=Groups[I].MobID then begin
              DX:=Temp.X-Groups[K].X;DZ:=Temp.Z-Groups[K].Z;
              W:=1/(DX*DX+DZ*DZ+400);Sum:=Sum+W;YSum:=YSum+Groups[K].Y*W;
            end;
            Temp.Y:=YSum/Sum;Temp.Heading:=Angle-2*Pi*Floor(Angle/(2*Pi));
          end;
          Expanded.Add(Temp);
        end;
      end;
      Selected:=Expanded.ToArray;
    finally Expanded.Free;Candidates.Free;end;
    if Length(Selected)=0 then raise EEmulatorContent.Create('No enabled Berneo population');
    for I:=0 to High(Selected)-1 do for J:=I+1 to High(Selected) do
      if Selected[J].EntityHandle<Selected[I].EntityHandle then begin
        Temp:=Selected[I];Selected[I]:=Selected[J];Selected[J]:=Temp;
      end;
    Rebuild:=Length(FSpiders)<>Length(Selected);
    if not Rebuild then for I:=0 to High(FSpiders) do
      if (FSpiders[I].Handle<>Selected[I].EntityHandle) or
        (FSpiders[I].Spawn.MobID<>Selected[I].MobID) then Rebuild:=True;
    // A membership change requires a new scene: never leave orphaned client
    // actors behind or silently swap species under an existing live handle.
    if Rebuild and (FStage=ssAppearanceProbe) then
      raise EEmulatorContent.Create('Population membership changed: reconnect required');
    if Rebuild then begin
      FHasPendingAttack:=False;FPlayerAutoAttacking:=False;FPendingSpiderHandle:=0;
      FSkillCast.Cancel;
      for I:=0 to High(FSpiders) do begin FSpiders[I].Encounter.Free;FSpiders[I].AI.Free;end;
      FSpiders:=nil;SetLength(FSpiders,Length(Selected));
    end;
    for I:=0 to High(FSpiders) do begin
      FSpiders[I].Handle:=Selected[I].EntityHandle;FSpiders[I].Spawn:=Selected[I];
      Snapshot.TryGetMob(Selected[I].MobID,FSpiders[I].Definition);
      // Start from immutable content on every reload: never compound the
      // global rate. The same effective speed drives AI and all client gages.
      FSpiders[I].Definition.AttackSpeed:=TB1008MonsterBalance.AttackSpeed(
        FSpiders[I].Definition.AttackSpeed);
    end;
    FSpiderContentRevision:=Snapshot.Revision;
  end else begin
    if FSpiderContentRevision<>0 then Exit;
    Definition:=Default(TEmulatorMobDefinition);Definition.BuildID:='b1008';
    Definition.MobID:=120;Definition.Name:='Little Spider';Definition.MaxHP:=B1008SpiderProbeHP;
    Definition.AttackDamage:=B1008DiagnosticSpiderDamage;Definition.AttackSpeed:=B1008ProbeAttackSpeed;
    Definition.MovementSpeed:=12;Definition.ChaseSpeed:=32;Definition.PatrolRadius:=22;
    Definition.AttackRange:=13;Definition.LeashRadius:=60;Definition.RespawnMS:=15000;
    Definition.Enabled:=True;Definition.Revision:=1;
    for I:=0 to High(FSpiders) do begin
      Spawn:=Default(TEmulatorSpawnDefinition);Spawn.BuildID:='b1008';
      Spawn.SpawnID:=FSpiders[I].Handle;Spawn.EntityHandle:=Spawn.SpawnID;
      Spawn.MapID:=19003;Spawn.MobID:=120;Spawn.X:=8669.7763671875+I*24;
      Spawn.Z:=6668.01025390625;Spawn.Y:=604.350341796875;
      Spawn.Population:=1;Spawn.Enabled:=True;Spawn.Revision:=1;
      FSpiders[I].Spawn:=Spawn;FSpiders[I].Definition:=Definition;
    end;
    FSpiderContentRevision:=-1;
  end;
  for I:=0 to High(FSpiders) do begin
    Definition:=FSpiders[I].Definition;
    if Definition.MobID=120 then FSpiders[I].PlayerMeleeRange:=Definition.AttackRange+2
    else FSpiders[I].PlayerMeleeRange:=TB1008Berneo.Mob(Definition.MobID).PlayerMeleeRange;
    // The original client starts at body radius + weapon reach. Retain
    // existing admission allowances, but never reject a larger model's
    // legitimate start just because it has the same old fixed bound.
    FSpiders[I].PlayerMeleeRange:=Max(FSpiders[I].PlayerMeleeRange,
      TB1008Berneo.Mob(Definition.MobID).ClientRadius+B1008PlayerMeleeReach);
    FSpiders[I].PlayerMeleeRange:=FSpiders[I].PlayerMeleeRange*B1008PlayerMeleeRangeScale;
    if not Assigned(FSpiders[I].AI) then FSpiders[I].AI:=TB1008SpiderAI.Create;
    FSpiders[I].AI.Configure(Definition,FSpiders[I].Spawn);
    if Assigned(FSpiders[I].Encounter) then FSpiders[I].Encounter.ReconfigureMaxHP(Definition.MaxHP)
    else FSpiders[I].Encounter:=TB1008SpiderEncounter.Create(Definition.MaxHP,TB1008Balance.PlayerDamage);
  end;
end;

destructor TEmulatorSession.Destroy;
var I: Integer;
begin
  Close;
  if FOwnWorld then FWorld.Free;
  FDecoder.Free;
  for I:=0 to High(FSpiders) do
  begin
    FSpiders[I].Encounter.Free;
    FSpiders[I].AI.Free;
  end;
  inherited;
end;

function TEmulatorSession.CreateSpiderDrop(Timestamp,ItemID,Amount: Cardinal; X,Z,Y: Single): TBytes;
var I: Integer; D: TB1008GroundDrop; G: TGUID;
begin
  Result:=nil;
  if not Assigned(FLoot) then Exit;
  I:=0;
  while (I<Length(FDrops)) and not FDrops[I].Collected do Inc(I);
  if (I=B1008LootGroundLimit) or (FNextDropID=High(Cardinal)) then Exit;
  D:=Default(TB1008GroundDrop);
  Inc(FNextDropID); D.ID:=FNextDropID;
  D.OwnerID:=1; D.ItemID:=ItemID; D.Amount:=Amount;
  D.X:=X; D.Z:=Z; D.Y:=Y;
  D.Sent:=True; D.ExpiresTick:=GetTickCount64+B1008MobLootLifetimeMS;
  CreateGUID(G); D.Receipt:=GUIDToString(G);
  Result:=TB1008LootWire.BuildDrop(Timestamp,D);
  if I=Length(FDrops) then SetLength(FDrops,I+1);
  FDrops[I]:=D;
end;

procedure TEmulatorSession.Close;
begin
  FStashNpcHandle:=0;
  if Assigned(FWorld) then FWorld.Release(Self);
  if Assigned(FQuests) then FQuests.Release(Self);
  if Assigned(FLoot) then FLoot.Release(Self);
  FDrops:=nil;
  FWorldState.Active := False;
  FSkillCast.Cancel;
  FHasPendingAttack:=False;
  FPlayerAutoAttacking:=False;
  FPendingSpiderHandle:=0;
  FStage := ssClosed;
end;

function TEmulatorSession.FindSpiderIndex(AHandle: Cardinal): Integer;
begin
  for Result:=0 to High(FSpiders) do
    if (FSpiders[Result].Handle=AHandle) and FSpiders[Result].Visible then Exit;
  Result:=-1;
end;

function TEmulatorSession.PollSpider(AIndex: Integer; ANowTick: UInt64;
  out AReplies: TB1008Replies): string;
var
  Spider: ^TB1008SpiderSlot;
  Movement: TB1008MobMovement;
  AttackPhase: TB1008MobAttackPhase;
  MovementIndex,GroupCount,GroupIndex,K,IncomingDamage,RawIncomingDamage,PlayerDefense: Integer;
  FormationRadius,FormationAngle: Single;
  DeathProgress: TB1008Progress;
  OldTotalEXP: Int64;
  IncomingFailed:Boolean;
begin
  AReplies:=nil;
  Result:='';
  Spider:=@FSpiders[AIndex];
  if Spider^.Encounter.TryDespawn(ANowTick) then
  begin
    SetLength(AReplies,1);
    AReplies[0]:=TB1008World.BuildActorDisappear(ANowTick and $FFFFFFFF,1,
      Spider^.Handle);
    Exit(Format('SPIDER DESPAWN | handle=%d after death animation',
      [Spider^.Handle]));
  end;
  if Spider^.Encounter.TryRespawn(ANowTick,Spider^.Definition.RespawnMS) then
  begin
    Spider^.Coercive.Clear;
    Spider^.WindBleed.Clear;
    FillChar(Spider^.ProfessionEffects,SizeOf(Spider^.ProfessionEffects),0);
    Spider^.AI.Reset(ANowTick,AIndex);
    Spider^.SentChaseSpeed:=Spider^.Definition.ChaseSpeed;
    SetLength(AReplies,1);
    AReplies[0]:=TB1008World.BuildSpiderAppearProbe(ANowTick and $FFFFFFFF,
      Spider^.Handle,Spider^.Definition.MaxHP,Spider^.Definition.MovementSpeed,
      Spider^.Definition.ChaseSpeed,Spider^.Definition.AttackSpeed,
      Spider^.Spawn.X,Spider^.Spawn.Z,
      Spider^.Spawn.Y,Spider^.Spawn.Heading);
    AppendSpiderMotionReset(AIndex,ANowTick and $FFFFFFFF,AReplies);
    Exit(Format('SPIDER RESPAWN | handle=%d HP=%d/%d spawn=%d map=%d '+
      'position=(%.3f,%.3f,%.3f) content rev=%d',
      [Spider^.Handle,Spider^.Encounter.HP,Spider^.Encounter.MaxHP,
       Spider^.Spawn.SpawnID,Spider^.Spawn.MapID,Spider^.Spawn.X,
       Spider^.Spawn.Z,Spider^.Spawn.Y,FSpiderContentRevision],
      TFormatSettings.Invariant));
  end;
  if (Spider^.Encounter.HP<>0) and Spider^.AI.Engaged then
  begin
    GroupCount:=0; GroupIndex:=0;
    for K:=0 to High(FSpiders) do
      if (FSpiders[K].Encounter.HP>0) and FSpiders[K].AI.Engaged and
        not FSpiders[K].AI.ReturningHome then begin
        if K=AIndex then GroupIndex:=GroupCount;
        Inc(GroupCount);
      end;
    if GroupCount>1 then begin
      // Distinct approach positions for a group, not one common endpoint.
      // Four inner places; extra mobs wait outside real attack range rather
      // than stacking or receiving an artificially extended melee radius.
      FormationRadius:=Spider^.Definition.AttackRange*0.8+
        (GroupIndex div 4)*Max(Spider^.Definition.AttackRange*1.6,20.0);
      FormationAngle:=FCombatFormationHeading+
        (GroupIndex mod 4)*2*Pi/Min(GroupCount,4);
      Spider^.AI.SetApproachOffset(FormationRadius*Cos(FormationAngle),
        FormationRadius*Sin(FormationAngle));
    end else Spider^.AI.SetApproachOffset(0,0);
    if Spider^.AI.PollChase(ANowTick,FWorldState.Position.X,
      FWorldState.Position.Z,FWorldState.Position.Y,
      Spider^.Definition.AttackRange,Spider^.Definition.LeashRadius,
      Movement) then
    begin
      MovementIndex:=0;
      if Abs(Spider^.SentChaseSpeed-Spider^.AI.ActiveChaseSpeed)>0.001 then
        MovementIndex:=1;
      SetLength(AReplies,MovementIndex+1);
      if MovementIndex=1 then
      begin
        // 08/00 updates NPC+$392 before 04/01 selects mode-0 run speed.
        // Changing only the AI duration would recreate client/server snaps.
        AReplies[0]:=TB1008CombatWire.BuildSpiderGageProbe(
          ANowTick and $FFFFFFFF,Spider^.Handle,Spider^.Encounter.HP,
          Spider^.Definition.MaxHP,Spider^.Definition.MovementSpeed*MobProfessionSpeed(AIndex,ANowTick),
          Spider^.AI.ActiveChaseSpeed,Spider^.Definition.AttackSpeed*MobProfessionSpeed(AIndex,ANowTick,13));
        Spider^.SentChaseSpeed:=Spider^.AI.ActiveChaseSpeed;
      end;
      AReplies[MovementIndex]:=TB1008World.BuildActorMovement(ANowTick and $FFFFFFFF,
        1,Movement.Mode,Spider^.Handle,Movement.FromX,Movement.FromZ,
        Movement.FromY,Movement.ToX,Movement.ToZ,Movement.ToY,
        Movement.Heading);
      if Movement.ReturningHome then
        Result:=Format('SPIDER RETURN | handle=%d mode=%d from=(%.3f,%.3f,%.3f) '+
          'to=(%.3f,%.3f,%.3f)',
          [Spider^.Handle,Movement.Mode,Movement.FromX,Movement.FromZ,
           Movement.FromY,Movement.ToX,Movement.ToZ,Movement.ToY],
          TFormatSettings.Invariant)
      else
        Result:=Format('SPIDER CHASE | handle=%d mode=%d speed=%.1f from=(%.3f,%.3f,%.3f) '+
          'to=(%.3f,%.3f,%.3f)',
          [Spider^.Handle,Movement.Mode,Spider^.AI.ActiveChaseSpeed,Movement.FromX,Movement.FromZ,
           Movement.FromY,Movement.ToX,Movement.ToZ,Movement.ToY],
          TFormatSettings.Invariant);
      Exit;
    end;
    if (FPlayerHP>0) and Spider^.AI.PollAttack(ANowTick,
      FWorldState.Position.X,FWorldState.Position.Z,
      Spider^.Definition.AttackRange,Spider^.Definition.AttackSpeed*MobProfessionSpeed(AIndex,ANowTick,13),
      AttackPhase) then
    begin
      if AttackPhase=mapStart then
      begin
        Spider^.AttackTimestamp:=ANowTick and $FFFFFFFF;
        SetLength(AReplies,1);
        AReplies[0]:=TB1008CombatWire.BuildSpiderCounterStart(
          Spider^.AttackTimestamp,Spider^.Handle,FWorldState.Position.X,
          FWorldState.Position.Z,FWorldState.Position.Y,Spider^.AI.X,
          Spider^.AI.Z,Spider^.AI.Y);
        Result:=Format('SPIDER ATTACK | start timestamp=%u handle=%d playerHP=%d/%d',
          [Spider^.AttackTimestamp,Spider^.Handle,FPlayerHP,PlayerMaxHP]);
      end
      else
      begin
        RawIncomingDamage:=Spider^.Definition.AttackDamage;PlayerDefense:=0;
        if Spider^.Definition.AttackMin>0 then
          RawIncomingDamage:=TB1008CombatDamage.Roll(FCombatRandomState,
            Spider^.Definition.AttackMin,Spider^.Definition.AttackDamage);
        IncomingDamage:=RawIncomingDamage;
        if Assigned(FLoot) then begin
          PlayerDefense:=FFlettaAttributes.Defense(PermanentPhysicalDefense)-SkillDefensePenalty(ANowTick);
          PlayerDefense:=Max(0,PlayerDefense);
          if Spider^.Definition.AttackMin>0 then
            IncomingDamage:=TB1008MonsterBalance.PhysicalDamage(RawIncomingDamage,PlayerDefense)
          else IncomingDamage:=TB1008CombatDamage.AgainstDefense(IncomingDamage,PlayerDefense,
            TB1008Balance.PhysicalDefenseCurve,TB1008Balance.MobDamageReferenceDefense);
        end; // Equipment-less probes retain their diagnostic damage.
        IncomingFailed:=FFlettaBarrier.CausesFailure(ANowTick,FCombatRandomState,
          PlayerAttributes.DefenseRatingBonus);
        if IncomingFailed then IncomingDamage:=0
        else IncomingDamage:=FFlettaBarrier.Mitigate(IncomingDamage,ANowTick);
        if (IncomingDamage>0) and FRevenge.Active(ANowTick) then
          IncomingDamage:=Max(1,(IncomingDamage*(100-
            TB1008ProfessionSkill.Get(FRevenge.SkillID,FRevenge.Rank).AbsorbPercent)+50) div 100);
        // One impact-time result drives death, HP, floating numbers and log.
        DeathProgress:=FProgress;OldTotalEXP:=FProgress.TotalEXP;
        if FPlayerHP<=IncomingDamage then begin
          if Assigned(FLoot) then begin
            Inc(FNextDeathID);
            DeathProgress:=FLoot.RecordDeath(Self,FInventorySessionID+'/death/'+UIntToStr(FNextDeathID));
            FFletta:=FLoot.Fletta(Self);
          end;
          FHasPendingAttack:=False;FPendingSpiderHandle:=0;FSkillCast.Cancel;
          FPlayerAutoAttacking:=False;
          FRegeneration.EnterCombat;
        end;
        FPlayerHP:=Max(0,FPlayerHP-IncomingDamage);
        SetLength(AReplies,2);
        AReplies[0]:=TB1008CombatWire.BuildPlayerDamageProbe(
          Spider^.AttackTimestamp,Spider^.Handle,FWorldState.Position.X,
          FWorldState.Position.Z,FWorldState.Position.Y,
          IncomingDamage,IncomingFailed);
        if (FPlayerHP=0) and (DeathProgress.Level=FProgress.Level) then begin
          FProgress:=DeathProgress;
          AReplies[1]:=PlayerGage(Spider^.AttackTimestamp,True);
        end else begin
          // 08/01 treats ANY level change as level-up (client 0x52B800).
          // Publish death with the old level, then sync a decreased level
          // through the verified 02/05 town reload, without a false effect.
          AReplies[1]:=PlayerGage(Spider^.AttackTimestamp,False);
          FProgress:=DeathProgress;
          FPlayerMP:=Min(FPlayerMP,PlayerMaxMP);
        end;
        Result:=Format('SPIDER ATTACK | damage=%d handle=%d playerHP=%d/%d nominal=%d defense=%d fail=%d',
          [IncomingDamage,Spider^.Handle,FPlayerHP,PlayerMaxHP,RawIncomingDamage,PlayerDefense,Ord(IncomingFailed)]);
        if FFlettaBarrier.SkillID<>0 then begin
          Result:=Result+Format(' barrier=%u remainingHits=%d',[FFlettaBarrier.SkillID,FFlettaBarrier.RemainingHits]);
          if (FPlayerHP=0) or not FFlettaBarrier.Active(ANowTick) then
            RemoveFlettaBarrier(Spider^.AttackTimestamp,AReplies);
        end;
        if FPlayerHP=0 then Result:=Result+Format(' | DEATH loss=%d totalEXP=%d level=%d',
          [OldTotalEXP-FProgress.TotalEXP,FProgress.TotalEXP,FProgress.Level]);
        if FPlayerHP=0 then begin
          FSkillEndTarget:=0;
          FFlettaProc.Clear;
          if FTornadoVisualUntilTick<>0 then begin
            SetLength(AReplies,Length(AReplies)+1);
            AReplies[High(AReplies)]:=TB1008FlettaProc.BuildVisual(Spider^.AttackTimestamp,False,FTornadoVisualSkillID);
            FTornadoVisualUntilTick:=0;
          end;
          RemoveFrenzy(Spider^.AttackTimestamp,AReplies);
        end;
      end;
      Exit;
    end;
  end
  // Technical clearance for passive patrols only, not historical aggro or
  // melee range. Neighboring spiders must not walk through the combatant.
  else if (Spider^.Encounter.HP<>0) and Spider^.AI.Poll(ANowTick,
    FWorldState.Position.X,FWorldState.Position.Z,
    Max(20.0,Spider^.Definition.AttackRange+2),Movement,
    FWorldState.Moving and not FRegeneration.Peaceful) then
  begin
    SetLength(AReplies,1);
    AReplies[0]:=TB1008World.BuildActorMovement(ANowTick and $FFFFFFFF,
      1,Movement.Mode,Spider^.Handle,Movement.FromX,Movement.FromZ,
      Movement.FromY,Movement.ToX,Movement.ToZ,Movement.ToY,
      Movement.Heading);
    Result:=Format('SPIDER PATROL | handle=%d mode=%d from=(%.3f,%.3f,%.3f) '+
      'to=(%.3f,%.3f,%.3f)',
      [Spider^.Handle,Movement.Mode,Movement.FromX,Movement.FromZ,
       Movement.FromY,Movement.ToX,Movement.ToZ,Movement.ToY],
      TFormatSettings.Invariant);
  end;
end;

function TEmulatorSession.PollWorld(ANowTick: UInt64;
  out AReplies: TB1008Replies): string;
var
  I, EventCount: Integer;
  One: TB1008Replies;
  Description: string;
  RegenBlocked: Boolean;
  procedure Collect(AIndex: Integer);
  var
    OldLength, K, BeforeBleed: Integer;
    WasVisible:Boolean;
  begin
    WasVisible:=FSpiders[AIndex].Visible;
    BeforeBleed:=Length(AReplies);
    PollWindBleed(AIndex,ANowTick,AReplies);
    PollProfessionEffects(AIndex,ANowTick,AReplies);
    if Length(AReplies)>BeforeBleed then begin
      if Result<>'' then Result:=Result+' | ';
      Result:=Result+Format('WIND BLADE TICK/REMOVE | handle=%d HP=%d',
        [FSpiders[AIndex].Handle,FSpiders[AIndex].Encounter.HP]);Inc(EventCount);
    end;
    // Use the AI's authoritative deadline, before any resumed movement/attack.
    // Stop/reset clears that deadline too; no independent visual timer can drift.
    if FSpiders[AIndex].StunEffectActive and
      ((ANowTick>=FSpiders[AIndex].AI.StunUntilTick) or (FSpiders[AIndex].Encounter.HP=0)) then begin
      RemoveSpiderStunEffect(AIndex,ANowTick and $FFFFFFFF,AReplies);
      if WasVisible then begin
        if Result<>'' then Result:=Result+' | ';
        Result:=Result+Format('STUN VISUAL REMOVE | handle=%d',[FSpiders[AIndex].Handle]);
        Inc(EventCount);
      end;
    end;
    if (FSpiders[AIndex].Coercive.Rank<>0) and
      (not FSpiders[AIndex].Coercive.Active(ANowTick) or (FSpiders[AIndex].Encounter.HP=0)) then begin
      RemoveSpiderCoercive(AIndex,ANowTick and $FFFFFFFF,AReplies);
      if WasVisible then begin
        if Result<>'' then Result:=Result+' | ';
        Result:=Result+Format('COERCIVE REMOVE | handle=%d',[FSpiders[AIndex].Handle]);Inc(EventCount);
      end;
    end;
    Description:=PollSpider(AIndex,ANowTick,One);
    if not WasVisible then Exit; // No packets for unknown distant client handles.
    if Description='' then Exit;
    if Result='' then Result:=Description;
    OldLength:=Length(AReplies);
    SetLength(AReplies,OldLength+Length(One));
    for K:=0 to High(One) do
      AReplies[OldLength+K]:=One[K];
    Inc(EventCount);
  end;
begin
  AReplies:=nil;
  Result:='';
  EventCount:=0;
  if (FStage<>ssAppearanceProbe) or not FWorldState.Active then Exit;
  if (FFlettaProc.Phase<>fppIdle) and not FFlettaProc.Active(ANowTick) then begin
    SetLength(AReplies,1);
    if FFlettaProc.Phase=fppQueued then
      AReplies[0]:=TB1008FlettaProc.BuildTrigger(ANowTick and $FFFFFFFF,High(Cardinal))
    else begin
      FSkillCast.Cancel;FSkillEndTarget:=0;
      FHasPendingAttack:=False;FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;
      AReplies[0]:=TB1008SkillWire.BuildCancel(ANowTick and $FFFFFFFF,
        FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y,FWorldState.Position.Heading,FFlettaProc.SkillID);
    end;
    FFlettaProc.Clear;Result:='FLETTA PROC TIMEOUT | pending cast released';
  end;
  // b1008 sends no separate scene-ready acknowledgement here. Allow a
  // bounded loading grace period, then start automatically even if idle.
  // This is a compatibility fallback, not a claimed protocol readiness signal.
  if (FFrenzy.Rank<>0) and ((FPlayerHP<=0) or not FFrenzy.Active(ANowTick)) then begin
    RemoveFrenzy(ANowTick and $FFFFFFFF,AReplies);
    Result:=Result+' | FRENZY REMOVE | expired/dead; parameters restored';
  end;
  I:=Length(AReplies);PollProfessionBuffs(ANowTick,AReplies);
  if Length(AReplies)>I then Result:=Result+' | PROFESSION BUFF REMOVE | expired/dead';
  if (FTornadoVisualUntilTick<>0) and ((FPlayerHP<=0) or (ANowTick>=FTornadoVisualUntilTick)) then begin
    SetLength(AReplies,Length(AReplies)+1);
    AReplies[High(AReplies)]:=TB1008FlettaProc.BuildVisual(ANowTick and $FFFFFFFF,False,FTornadoVisualSkillID);
    FTornadoVisualUntilTick:=0;
    Result:=Result+' | FLETTA VISUAL REMOVE | expired/dead';
  end;
  if (FFlettaBarrier.SkillID<>0) and ((FPlayerHP<=0) or not FFlettaBarrier.Active(ANowTick)) then begin
    RemoveFlettaBarrier(ANowTick and $FFFFFFFF,AReplies);
    Result:=Result+' | FLETTA BARRIER REMOVE | expired/dead/exhausted';
  end;
  if not FWorldPatrolStarted and (ANowTick>=FAutoWorldStartTick) then
    StartWorldPatrol(ANowTick);
  for I:=0 to High(FDrops) do begin
    if FDrops[I].Collected then Continue;
    if ANowTick>=FDrops[I].ExpiresTick then begin
      FLoot.RemoveGround(Self,FDrops[I].Receipt);
      FDrops[I].Collected:=True;
      if FDrops[I].Sent then begin
        SetLength(AReplies,Length(AReplies)+1);
        AReplies[High(AReplies)]:=TB1008LootWire.BuildRemove(ANowTick and $FFFFFFFF,FDrops[I]);
      end;
      Result:='LOOT CLEANER | expired items removed';
    end else if FClientInWorld and not FDrops[I].Sent then begin
      SetLength(AReplies,Length(AReplies)+1);
      AReplies[High(AReplies)]:=TB1008LootWire.BuildDrop(ANowTick and $FFFFFFFF,FDrops[I]);
      FDrops[I].Sent:=True; Result:='GROUND RESTORED | after client movement readiness';
    end;
  end;
  SyncSpiderContent;
  // Regen admits the scene but can precede the end of client loading.
  // Do not send movement into an initializing terrain/collision system.
  if not FWorldPatrolStarted then Exit;
  UpdateMobVisibility(ANowTick,AReplies);
  if (Length(AReplies)>0) and (Result='') then Result:='MOB VISIBILITY | nearby actors synchronized';
  // Combat/death lifecycle must not be delayed behind unrelated patrol events
  // when the map contains many independently scheduled creatures.
  for I:=0 to High(FSpiders) do
    if (FSpiders[I].Encounter.HP=0) or FSpiders[I].AI.Engaged then
      Collect(I);
  for I:=0 to High(FSpiders) do
  begin
    if (FSpiders[I].Encounter.HP=0) or FSpiders[I].AI.Engaged then Continue;
    Collect(I);
  end;
  if EventCount>1 then
    Result:=Result+Format(' | batched world events=%d',[EventCount]);
  if (FPlayerHP>0) and (FParameterLevel<>FProgress.Level) then begin
    SetLength(AReplies,Length(AReplies)+1);
    AReplies[High(AReplies)]:=TB1008ProgressWire.BuildParameters(ANowTick and $FFFFFFFF,FPlayerClassID,FProgress.Level);
    ApplyPlayerParameters(AReplies[High(AReplies)]);
    FParameterLevel:=FProgress.Level;Result:=Result+' | PLAYER PARAMETERS updated after level change';
  end;
  RegenBlocked:=FHasPendingAttack;
  for I:=0 to High(FSpiders) do
    if (FSpiders[I].Encounter.HP>0) and FSpiders[I].AI.Engaged and
      not FSpiders[I].AI.ReturningHome then RegenBlocked:=True;
  if FRegeneration.Poll(ANowTick,RegenBlocked,TB1008Balance.RegenIntervalMS,
    FFlettaAttributes.RegenHP(PlayerAttributes.RegenHP),
    FFlettaAttributes.RegenMP(PlayerAttributes.RegenMP),
    PlayerMaxHP,PlayerMaxMP,FPlayerHP,FPlayerMP) then begin
    SetLength(AReplies,Length(AReplies)+1);
    AReplies[High(AReplies)]:=PlayerGage(ANowTick and $FFFFFFFF,False);
    if Result<>'' then Result:=Result+' | ';
    Result:=Result+Format('PLAYER REGEN | HP=%d/%d MP=%d/%d',[FPlayerHP,PlayerMaxHP,FPlayerMP,PlayerMaxMP]);
  end;
end;

function TEmulatorSession.CommitMobKill(AIndex:Integer;Timestamp:Cardinal;var Replies:TB1008Replies):string;
var Spider:^TB1008SpiderSlot;QuestUpdate:TB1008QuestUpdate;DropRates:TB1008Rates;
  Awards:TArray<TB1008RolledDrop>;Award:TB1008RolledDrop;Need:TB1008QuestDropNeed;
  Ground:TB1008GroundDrop;GroundAmount,QuestDropCount,QuestDropIndex:Cardinal;
  AwardIndex:Integer;Position:TB1008Position;DropAngle:Double;Reply:TBytes;
begin
  Result:='';Spider:=@FSpiders[AIndex];
  if not Assigned(FLoot) or (Spider^.Encounter.HP<>0) then Exit;
  begin
    Inc(FNextKillID);
    if Spider^.Spawn.MobID=120 then
      AcceptProgress(FLoot.RecordSpiderEXP(Self,FInventorySessionID+'/kill/'+UIntToStr(FNextKillID)))
    else AcceptProgress(FLoot.RecordMobEXP(Self,FInventorySessionID+'/kill/'+UIntToStr(FNextKillID),
      TB1008Berneo.Mob(Spider^.Spawn.MobID).BaseEXP,TB1008Berneo.Mob(Spider^.Spawn.MobID).Level));
    FFletta:=FLoot.Fletta(Self);
    SetLength(Replies,Length(Replies)+1);
    Replies[High(Replies)]:=PlayerGage(Timestamp,True);
    // Objective targets are model IDs, not spawn handles or npcInfo variants.
    for QuestUpdate in FLoot.RecordQuestKill(Self,FInventorySessionID+'/kill/'+UIntToStr(FNextKillID),
      TB1008Npcs.MobModel(TB1008Berneo.Mob(Spider^.Spawn.MobID).ClientID)) do begin
      SetLength(Replies,Length(Replies)+1);
      Replies[High(Replies)]:=TB1008QuestWire.BuildUpdate(Timestamp,1,QuestUpdate);
    end;
    DropRates:=FLoot.Rates;
    Awards:=TB1008DropProfile.RollMob(FDropRandomState,FPlayerClassID,Spider^.Spawn.MobID,DropRates);
    for Need in FLoot.QuestDropNeeds(Self,TB1008Npcs.MobModel(TB1008Berneo.Mob(Spider^.Spawn.MobID).ClientID)) do begin
      GroundAmount:=0;
      for Ground in FDrops do if not Ground.Collected and (Ground.ExpiresTick>GetTickCount64) and
        (Ground.ItemID=Need.ItemID) then Inc(GroundAmount,Ground.Amount);
      QuestDropCount:=TB1008QuestCatalog.RollDrop(FQuestDropRandomState,Need,GroundAmount,DropRates.Drop);
      for QuestDropIndex:=1 to QuestDropCount do begin
        Award.ItemID:=Need.ItemID;Award.Amount:=1;Award.Category:='quest';
        SetLength(Awards,Length(Awards)+1);Awards[High(Awards)]:=Award;
      end;
    end;
    for AwardIndex:=0 to High(Awards) do begin
      Award:=Awards[AwardIndex];
      Position.X:=Spider^.AI.X; Position.Z:=Spider^.AI.Z; Position.Y:=Spider^.AI.Y;
      if Length(Awards)>1 then begin
        // One roll, stable layout, no extra random draws or loot changes.
        DropAngle:=2*Pi*AwardIndex/Length(Awards);
        Position.X:=Position.X+Cos(DropAngle)*B1008MobLootScatterRadius;
        Position.Z:=Position.Z+Sin(DropAngle)*B1008MobLootScatterRadius;
      end;
      Reply:=CreateSpiderDrop(Timestamp,Award.ItemID,Award.Amount,
        Position.X,Position.Z,Position.Y);
      if Length(Reply)>0 then begin
        SetLength(Replies,Length(Replies)+1); Replies[High(Replies)]:=Reply;
        Result:=Result+Format(' %s:%u x%u',[Award.Category,Award.ItemID,Award.Amount]);
      end else Result:=Result+' GROUND_CAPACITY_REACHED';
    end;
  end;
end;

{$I Emulator.Session.Profession.inc}

function TEmulatorSession.ResolveTargetImpact(const AttackDecide:TB1008AttackDecide;
  out AReplies:TB1008Replies;AreaAdmission:Boolean):string;
var
  IsAttackSkill,AddQuestProgress:Boolean;
  ImpactAttack:TB1008AttackStart;
  SpiderIndex,MinDamage,MaxDamage,TargetDefense,HitDamage,MissFailChance,
    AttackRating,MobLevel,HitIndex,HitCount:Integer;
  AdmissionRange:Single;
  Profession:TB1008ProfessionSkill;
  Spider:^TB1008SpiderSlot;
  HitTick:UInt64;
  StateNote,LootNote:string;
  QuestProgress:Cardinal;
  Hit:TB1008ResolvedHit;
  SkillParameters:TB1008AttackSkillStats;
  SpiderStop:TB1008MobMovement;
begin
  AReplies:=nil;
  if (AttackDecide.ActorKind<>0) or
    (AttackDecide.ActorID<>FWorldState.CharacterID) or
    not ((AttackDecide.ActionKind=0) or ((AttackDecide.ActionKind=1) and
      ((AttackDecide.ActionID=B1008PowerStrikeID) or (AttackDecide.ActionID=B1008BodyBlowID) or
       TB1008ProfessionSkill.IsAttack(AttackDecide.ActionID) or (AttackDecide.ActionID=B1008ThunderHowlID) or
       (TB1008FlettaProc.YinSupported(AttackDecide.ActionID))))) or (AttackDecide.TargetKind<>1) or
    (AttackDecide.TargetCount<>1) then
    Exit(Format('ATTACK DECIDE SKIPPED | actor=%d/%u action=%d/%u target=%d/%u count=%d; unsupported',
      [AttackDecide.ActorKind,AttackDecide.ActorID,AttackDecide.ActionKind,AttackDecide.ActionID,
       AttackDecide.TargetKind,AttackDecide.TargetID,AttackDecide.TargetCount]));
  if not FHasPendingAttack then
    Exit('ATTACK DECIDE SKIPPED | no pending attack start');
  // 0x502046 calls 0x4EDBF6: impact carries skillBase.ID (1001),
  // unlike 0x50143A which starts skillBase.animation (1004).
  IsAttackSkill:=FPendingAttack.ActionKind=1;
  if (AttackDecide.ActionKind<>FPendingAttack.ActionKind) or
    (not IsAttackSkill and (AttackDecide.ActionID<>FPendingAttack.ActionID)) or
    (IsAttackSkill and (AttackDecide.ActionID<>FSkillCast.ActiveSkillID)) or
    (AttackDecide.TargetID<>FPendingSpiderHandle) then
    Exit(Format('ATTACK DECIDE SKIPPED | stale action=%u target=%d; pending action=%u target=%d',
      [AttackDecide.ActionID,AttackDecide.TargetID,
       FPendingAttack.ActionID,FPendingSpiderHandle]));
  if IsAttackSkill and ((GetTickCount64>FSkillImpactUntilTick) or
    (((Int64(AttackDecide.Timestamp)-Int64(FPendingAttack.Timestamp)+$100000000) mod $100000000)>=$80000000)) then begin
    FHasPendingAttack:=False;FPlayerAutoAttacking:=False;FPendingSpiderHandle:=0;
    Exit('SKILL IMPACT REJECTED | expired/stale impact');
  end;
  ImpactAttack:=FPendingAttack;
  ImpactAttack.Timestamp:=AttackDecide.Timestamp;
  ImpactAttack.X:=AttackDecide.X; ImpactAttack.Z:=AttackDecide.Z;
  ImpactAttack.Y:=AttackDecide.Y; ImpactAttack.Heading:=AttackDecide.Heading;
  FHasPendingAttack:=False;
  FPendingSpiderHandle:=0;
  SpiderIndex:=FindSpiderIndex(AttackDecide.TargetID);
  if SpiderIndex<0 then begin
    FPlayerAutoAttacking:=False;Exit('ATTACK DECIDE SKIPPED | target disappeared');
  end;
  Spider:=@FSpiders[SpiderIndex];
  HitTick:=GetTickCount64;
  Spider^.AI.UpdatePosition(HitTick);
  AdmissionRange:=PlayerHitRange(SpiderIndex,ImpactAttack.ActionKind,ImpactAttack.ActionID);
  if AreaAdmission then begin
    // Only HandleProfessionImpact can grant this after validating the whole
    // target list against authoritative native circle/rectangle geometry.
    ImpactAttack.X:=FWorldState.Position.X;ImpactAttack.Z:=FWorldState.Position.Z;ImpactAttack.Y:=FWorldState.Position.Y;
    ImpactAttack.TargetX:=Spider^.AI.X;ImpactAttack.TargetZ:=Spider^.AI.Z;ImpactAttack.TargetY:=Spider^.AI.Y;
    AdmissionRange:=Sqrt(Sqr(ImpactAttack.X-Spider^.AI.X)+Sqr(ImpactAttack.Z-Spider^.AI.Z))+1;
  end;
  if not Spider^.Encounter.TryHit(ImpactAttack,Spider^.Handle,
    FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y,
    Spider^.AI.X,Spider^.AI.Z,Spider^.AI.Y,
    AdmissionRange,HitTick,StateNote,False) then begin
    FPlayerAutoAttacking:=False;
    Exit(Format('ATTACK IMPACT CANCELLED | timestamp=%u action=%u | %s',
      [AttackDecide.Timestamp,AttackDecide.ActionID,StateNote]));
  end;
  AddQuestProgress:=False; QuestProgress:=0;
  if IsAttackSkill and (TB1008FlettaProc.YinSupported(FSkillCast.ActiveSkillID)) and
    not FFlettaProc.Impact(AttackDecide.TargetID,AttackDecide.Timestamp,HitTick) then
    Exit('FLETTA IMPACT REJECTED | no matching server proc');
  Hit:=Default(TB1008ResolvedHit);
  MissFailChance:=0;AttackRating:=0;MobLevel:=0;
  if Assigned(FLoot) then begin
    PermanentAttackRange(MinDamage,MaxDamage);
    FFlettaAttributes.PhysicalAttack(MinDamage,MaxDamage,PlayerAttributes.PhysicalAttack);
    Inc(MinDamage,SkillAttackBonus(HitTick));Inc(MaxDamage,SkillAttackBonus(HitTick));
    if IsAttackSkill then begin
      // Authored approximation: effective attack + rounded client rank bonus.
      // Skill criticals are deliberately separate from the confirmed ordinary rule.
      SkillParameters:=TB1008AttackSkillStats.Get(FSkillCast.ActiveSkillID,FSkillCast.ActiveRank);
      // Original Tornado skillLevel +B0/+B8: standalone 200..230 damage.
      if TB1008FlettaProc.YinSupported(FSkillCast.ActiveSkillID) then
        Hit.NormalDamage:=TB1008CombatDamage.Roll(FCombatRandomState,
          TB1008FlettaProc.DirectMinimum(FSkillCast.ActiveSkillID),TB1008FlettaProc.DirectMaximum(FSkillCast.ActiveSkillID))
      else Hit.NormalDamage:=TB1008CombatDamage.Roll(FCombatRandomState,
        MinDamage+SkillParameters.BonusMin,MaxDamage+SkillParameters.BonusMax);
      Hit.Damage:=Hit.NormalDamage;
    end else begin
      // Only live PvE content has authoritative mob levels. Standalone
      // equipment/protocol probes retain their deterministic hit rules.
      if Assigned(FRuntime) then begin
        MobLevel:=TB1008Berneo.Mob(Spider^.Spawn.MobID).Level;
        AttackRating:=PlayerAttributes.AttackRatingBonus;
        MissFailChance:=TB1008Balance.MissFailBasisPoints(FProgress.Level,MobLevel,AttackRating);
      end;
      Hit:=TB1008CombatDamage.ResolveOrdinary(FCombatRandomState,MinDamage,MaxDamage,
        PlayerAttributes.CriticalBasisPoints,
        TB1008Balance.CriticalDamagePercent,MissFailChance);
    end;
  end else begin // Equipment-less diagnostic sessions retain fixed noncritical hits.
    Hit.NormalDamage:=TB1008Balance.PlayerDamage;Hit.Damage:=Hit.NormalDamage;
  end;
  TargetDefense:=Max(0,Spider^.Definition.PhysicalDefense-Spider^.Coercive.ActiveDefensePenalty(HitTick));
  HitDamage:=TB1008MonsterBalance.PhysicalDamage(Hit.Damage,TargetDefense);
  if IsAttackSkill and TB1008ProfessionSkill.Supported(FSkillCast.ActiveSkillID) then begin
    Profession:=TB1008ProfessionSkill.Get(FSkillCast.ActiveSkillID,FSkillCast.ActiveRank);
    HitCount:=Max(1,Integer(Profession.HitCount));
    if FSkillCast.ActiveSkillID=B1008ThunderHowlID then HitDamage:=0
    else for HitIndex:=2 to HitCount do begin
      if Assigned(FLoot) then Hit.Damage:=TB1008CombatDamage.Roll(FCombatRandomState,
        MinDamage+Profession.BonusMin,MaxDamage+Profession.BonusMax);
      Inc(HitDamage,TB1008MonsterBalance.PhysicalDamage(Hit.Damage,TargetDefense));
    end;
  end;
  // Roll once AFTER impact admission. Use the same value for lethal checks,
  // committed HP, the floating damage packet and log; never reroll in TryHit.
  if (Spider^.Encounter.HP<=HitDamage) and
    (Spider^.Spawn.MobID=120) and
    Assigned(FQuests) and
    FQuests.Active(Self) then
  begin
    QuestProgress:=FQuests.Progress(Self);
    AddQuestProgress:=QuestProgress<5;
  end;
  if AddQuestProgress then
    try
      QuestProgress:=FQuests.RecordSpiderKill(Self);
    except
      on E: Exception do Exit('SPIDER KILL NOT COMMITTED | HP unchanged; '+E.Message);
    end;
  Spider^.Encounter.TryHit(ImpactAttack,Spider^.Handle,
    FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y,
    Spider^.AI.X,Spider^.AI.Z,Spider^.AI.Y,
    AdmissionRange,HitTick,StateNote,True,HitDamage);
  if (Spider^.Encounter.HP=0) or IsAttackSkill then FPlayerAutoAttacking:=False;
  SetLength(AReplies,2+Ord(AddQuestProgress));
  if AttackDecide.ActionID=B1008ThunderHowlID then SetLength(AReplies,1)
  else AReplies[0]:=TB1008CombatWire.BuildSpiderDamageProbe(ImpactAttack,
    Spider^.AI.X,Spider^.AI.Z,Spider^.AI.Y,HitDamage,Hit.Outcome);
  if IsAttackSkill and TB1008FlettaProc.YinSupported(FSkillCast.ActiveSkillID) then begin
    // Action zero is shared by Yin skills; the damage packet carries the actual ID.
    AReplies[0][12]:=Byte(FSkillCast.ActiveSkillID shr 24);
    AReplies[0][13]:=Byte(FSkillCast.ActiveSkillID shr 16);
    AReplies[0][14]:=Byte(FSkillCast.ActiveSkillID shr 8);
    AReplies[0][15]:=Byte(FSkillCast.ActiveSkillID);
  end;
  AReplies[Ord(AttackDecide.ActionID<>B1008ThunderHowlID)]:=TB1008CombatWire.BuildSpiderGageProbe(
    ImpactAttack.Timestamp,Spider^.Handle,Spider^.Encounter.HP,
    Spider^.Definition.MaxHP,Spider^.Definition.MovementSpeed*MobProfessionSpeed(SpiderIndex,HitTick),
    Spider^.AI.ActiveChaseSpeed,Spider^.Definition.AttackSpeed*MobProfessionSpeed(SpiderIndex,HitTick,13));
  Spider^.SentChaseSpeed:=Spider^.AI.ActiveChaseSpeed;
  if AddQuestProgress then
    AReplies[2]:=TB1008QuestWire.BuildProgress(
      ImpactAttack.Timestamp,QuestProgress);
  // Emit loot on the committed lethal hit, after damage/HP, independently
  // of corpse despawn. TryHit rejects an already dead target and duplicates.
  LootNote:='';
  if AreaAdmission and (Spider^.Encounter.HP>0) and Spider^.AI.Engage(HitTick,SpiderStop) then begin
    SetLength(AReplies,Length(AReplies)+1);
    AReplies[High(AReplies)]:=TB1008World.BuildActorMovement(ImpactAttack.Timestamp,1,2,Spider^.Handle,
      SpiderStop.FromX,SpiderStop.FromZ,SpiderStop.FromY,SpiderStop.ToX,SpiderStop.ToZ,SpiderStop.ToY,SpiderStop.Heading);
  end;
  if IsAttackSkill and (FSkillCast.ActiveSkillID=B1008WindBladeID) and (Spider^.Encounter.HP>0) then begin
    Spider^.WindBleed.Start(FSkillCast.ActiveRank,HitTick);
    SetLength(AReplies,Length(AReplies)+1);
    AReplies[High(AReplies)]:=TB1008SkillWire.BuildMobWindBlade(ImpactAttack.Timestamp,
      Spider^.Handle,FSkillCast.ActiveRank,True);
  end;
  if IsAttackSkill and TB1008ProfessionSkill.Supported(FSkillCast.ActiveSkillID) then
    ApplyProfessionHit(SpiderIndex,ImpactAttack.Timestamp,HitTick,AReplies);
  if IsAttackSkill and ((FSkillCast.ActiveSkillID=B1008BodyBlowID) or
    (FSkillCast.ActiveSkillID=B1008RockStraightID)) and (Spider^.Encounter.HP>0) and
    Spider^.AI.Stun(HitTick,TB1008AttackSkillStats.Get(FSkillCast.ActiveSkillID,FSkillCast.ActiveRank).StunMS,SpiderStop) then begin
    SetLength(AReplies,Length(AReplies)+1);
    AReplies[High(AReplies)]:=TB1008World.BuildActorMovement(ImpactAttack.Timestamp,1,2,Spider^.Handle,
      SpiderStop.FromX,SpiderStop.FromZ,SpiderStop.FromY,SpiderStop.ToX,SpiderStop.ToZ,SpiderStop.ToY,SpiderStop.Heading);
    if Spider^.StunEffectActive and (Spider^.StunEffectSkillID<>FSkillCast.ActiveSkillID) then
      RemoveSpiderStunEffect(SpiderIndex,ImpactAttack.Timestamp,AReplies);
    if not Spider^.StunEffectActive then begin
      SetLength(AReplies,Length(AReplies)+1);
      AReplies[High(AReplies)]:=TB1008SkillWire.BuildMobStun(ImpactAttack.Timestamp,Spider^.Handle,True,FSkillCast.ActiveSkillID);
      Spider^.StunEffectActive:=True;
      Spider^.StunEffectSkillID:=FSkillCast.ActiveSkillID;
    end;
    LootNote:=Format(' stun=%ums visual=05/09',
      [TB1008AttackSkillStats.Get(FSkillCast.ActiveSkillID,FSkillCast.ActiveRank).StunMS]);
  end;
  if Spider^.Encounter.HP=0 then begin
    RemoveSpiderStunEffect(SpiderIndex,ImpactAttack.Timestamp,AReplies);
    RemoveSpiderCoercive(SpiderIndex,ImpactAttack.Timestamp,AReplies);
    RemoveWindBleed(SpiderIndex,ImpactAttack.Timestamp,AReplies);
    RemoveProfessionEffects(SpiderIndex,ImpactAttack.Timestamp,AReplies);
    if (not TB1008FlettaProc.YinSupported(AttackDecide.ActionID)) and (FFlettaProc.Phase<>fppIdle) and (FFlettaProc.Target=Spider^.Handle) then begin
      FFlettaProc.Clear;
      SetLength(AReplies,Length(AReplies)+1);
      AReplies[High(AReplies)]:=TB1008FlettaProc.BuildTrigger(ImpactAttack.Timestamp,High(Cardinal));
    end;
  end;
  if Spider^.Encounter.HP=0 then LootNote:=LootNote+CommitMobKill(SpiderIndex,ImpactAttack.Timestamp,AReplies);
  FWorldState.Position.X:=AttackDecide.X;
  FWorldState.Position.Z:=AttackDecide.Z;
  FWorldState.Position.Y:=AttackDecide.Y;
  if TB1008FlettaProc.EligibleImpact(AttackDecide.ActionKind,AttackDecide.ActionID,HitDamage,Spider^.Encounter.HP) and
    FFlettaProc.TryQueue(FFlettaAttributes,Spider^.Handle,AttackDecide.Timestamp,
      HitTick,FFlettaProcRandomState,(HitTick<FTornadoVisualUntilTick) or FFlettaBarrier.Active(HitTick),TB1008Balance.FlettaProcBasisPoints,
      PlayerHitRange(SpiderIndex,ImpactAttack.ActionKind,ImpactAttack.ActionID)) then begin
    SetLength(AReplies,Length(AReplies)+1);
    AReplies[High(AReplies)]:=TB1008FlettaProc.BuildTrigger(AttackDecide.Timestamp,FFlettaProc.SkillID);
    LootNote:=LootNote+Format(' FLETTA PROC QUEUED skill=%u chanceBP=%d sourceKind=%d sourceID=%u range=%.2f',
      [FFlettaProc.SkillID,TB1008Balance.FlettaProcBasisPoints,AttackDecide.ActionKind,AttackDecide.ActionID,
       FFlettaProc.GrantedRange],TFormatSettings.Invariant);
  end;
  if AddQuestProgress then StateNote:=Format('quest %d/5 committed',[QuestProgress])
  else StateNote:='no quest progress';
  Exit(Format('SPIDER HIT ACCEPTED | timestamp=%u action=%u target=%d damage=%d HP=%d/%d | normal=%d critical=%d defense=%d outcome=%d missFailBP=%d ratingBonus=%d mobLevel=%d; impact-time commit; %s',
    [ImpactAttack.Timestamp,ImpactAttack.ActionID,Spider^.Handle,
     HitDamage,Spider^.Encounter.HP,
     Spider^.Definition.MaxHP,Hit.NormalDamage,Ord(Hit.Critical),TargetDefense,
     Ord(Hit.Outcome),MissFailChance,AttackRating,MobLevel,StateNote])+LootNote);
end;

function TEmulatorSession.HandlePacketCore(const APayload: TBytes;
  out AReplies: TB1008Replies): string;
var
  Offset, I, Start: Integer;
  Sizes, Starts: array[0..2] of Integer;
  Token, Timestamp: Cardinal;
  IsTest: Boolean;
  Reply: TBytes;
  ProcReplies:TB1008Replies;
  StartRequest: TB1008StartCharacter;
  Regen: TB1008Regen;
  Movement: TB1008Movement;
  QuestStart: TB1008QuestStart;
  QuestReward: TB1008QuestReward;
  ItemUse: TB1008ItemUse;
  ItemSwap: TB1008ItemSwap;
  Sale:TB1008ShopSell;
  Purchase:TB1008ShopBuy;
  EnhancementRequest:TB1008EnhancementRequest;
  EnhancementCode:Byte;
  EnhancementGear:TB1008EquipmentItem;
  EnhancementUpdates:TArray<TB1008BagItem>;
  MiningRequest:TB1008MiningRequest;
  MiningCode:Byte;
  MiningUpdates:TArray<TB1008BagItem>;
  MiningIDs:TArray<Cardinal>;
  MiningItem:TB1008BagItem;
  MiningPick:Boolean;
  CraftRequest:TB1008CraftRequest;
  CraftCode:Byte;
  CraftAllowed:Boolean;
  CraftBefore,CraftUpdates:TArray<TB1008BagItem>;
  CraftOld,CraftNew:TB1008BagItem;
  SalePaid:Cardinal;
  ItemSplit: TB1008ItemSplit;
  SplitSource,SplitCreated: TB1008BagItem;
  GearRequest: TB1008EquipmentRequest;
  GearItem,ReplacedGearItem: TB1008EquipmentItem;
  FlettaRequest:TB1008FlettaInvestment;
  FlettaResult:TB1008FlettaInvestmentResult;
  NewFletta:TB1008Fletta;
  NewFlettaAttributes:TB1008FlettaAttributes;
  SkillLearn:TB1008SkillLearn;
  SkillLearnResult:TB1008SkillLearnResult;
  SkillUpgrade:TB1008SkillUpgrade;
  SkillReady:TB1008SkillReady;
  SkillCancel:TB1008SkillCancel;
  LearnedSkill:TB1008LearnedSkill;
  SkillUpgradeResult:TB1008SkillUpgradeResult;
  SkillRank:Cardinal;
  SkillParameters:TB1008AttackSkillStats;
  AttackSkillID,SelfSkillID:Cardinal;
  SelfSkillName:string;
  AreaTargets:TArray<TB1008AttackDecide>;
  AreaTarget:TB1008AttackDecide;
  AreaCount:Integer;
  AreaRadius:Double;
  HasSkill,HasWeapon,IsAttackSkill:Boolean;
  QuickRequest:TB1008QuickSlotRequest;
  ItemThrow: TB1008ItemThrow;
  BagItem: TB1008BagItem;
  PickupUpdates:TArray<TB1008BagItem>;
  FarmProgress:TB1008Progress;
  DestroyThrownItem:Boolean;
  GroundDrop: TB1008GroundDrop;
  G: TGUID;
  Pickup: TB1008Pickup;
  LootCount: Cardinal;
  DropIndex: Integer;
  PickupDX,PickupDZ: Double;
  AttackStart: TB1008AttackStart;
  AttackDecide: TB1008AttackDecide;
  ImpactAttack: TB1008AttackStart;
  ActionFlags: TB1008ActionFlags;
  Position: TB1008Position;
  StateNote,ChargeNote: string;
  QuestProgress, HealingCount, ManaCount: Cardinal;
  Npc:TB1008Npc;
  HitTick: UInt64;
  FirstEngagement: Boolean;
  SpiderStop: TB1008MobMovement;
  SpiderIndex: Integer;
  Spider: ^TB1008SpiderSlot;
  function RejectPreparedSelf(const Reason:string):string;
  begin
    Result:=Reason;
    if FSkillCast.RejectStart(AttackStart.Timestamp,1,SelfSkillID) then begin
      SetLength(AReplies,1);
      AReplies[0]:=TB1008SkillWire.BuildCancel(AttackStart.Timestamp,
        FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y,
        FWorldState.Position.Heading,SelfSkillID);
      FSkillEndTarget:=0;FHasPendingAttack:=False;FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;
      Result:=Result+'; prepared self cast cancelled; no cost or cooldown';
    end;
  end;
  function RejectPreparedAttack(const Reason:string):string;
  begin
    Result:=Reason;
    if IsAttackSkill and (AttackStart.TargetKind=1) and
      FSkillCast.RejectStart(AttackStart.Timestamp,AttackStart.TargetID,AttackSkillID) then begin
      SetLength(AReplies,1);
      AReplies[0]:=TB1008SkillWire.BuildCancel(AttackStart.Timestamp,
        FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y,
        FWorldState.Position.Heading,AttackSkillID);
      FBodyBlowCharge:=Default(TB1008ChargeAdmission);
      if TB1008FlettaProc.YinSupported(AttackSkillID) then FFlettaProc.Clear;
      FSkillEndTarget:=0;FHasPendingAttack:=False;FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;
      Result:=Result+'; prepared cast cancelled; no cost or cooldown';
    end;
  end;
begin
  AReplies := nil;
  if FStage = ssClosed then
    raise EKarosProtocol.Create('Packet after session close');
  if Length(APayload) < 2 then
    raise EKarosProtocol.Create('Missing command group/subcommand');
  if (APayload[0]=2) and (APayload[1]=1) then
  begin
    // 426995 -> 4268CE: return-to-selection uses the view packet with
    // final=1, both IDs=0, an unused 321-byte body and an empty wide name.
    // Never adopt any character data from that client-owned body.
    if (Length(APayload)<>342) then
      raise EKarosProtocol.Create('Invalid character-selection request size');
    if (APayload[6]<>1) or (TB1008Wire.ReadBE32(APayload,7)<>0) or
      (TB1008Wire.ReadBE32(APayload,11)<>0) or
      (TB1008Wire.ReadBE16(APayload,336)<>0) or
      (TB1008Wire.ReadBE32(APayload,338)<>0) then
      Exit('CHARACTER SELECT REJECTED | unsupported request fields');
    if (FLoginMode<>blMapLoadingProbe) or not Assigned(FCharacters) or
      not (FStage in [ssMapLoadingProbe,ssAppearanceProbe]) then
      Exit('CHARACTER SELECT ignored | no admitted world session');
    Timestamp:=TB1008Wire.ReadBE32(APayload,2);
    Reply:=FCharacters.Preview(Timestamp);
    if Length(Reply)=0 then Exit('CHARACTER SELECT REJECTED | no saved character');
    if Assigned(FLoot) then begin
      TB1008ProgressWire.ApplyPreview(Reply,FLoot.Progress(Self));
      TB1008Equipment.ApplyPreview(Reply,FLoot.Equipment(Self));
      TB1008ClassWire.ApplyPreview(Reply,FLoot.ClassState(Self));
    end;
    Close; // Release world/quest/inventory ownership, without closing the socket.
    FWorldState:=Default(TB1008WorldSnapshot);FMovementAdmission.Reset;
    FClientInWorld:=False;FWorldPatrolStarted:=False;FRespawnLoading:=False;
    FFrenzy.Remove;FRevenge.Clear;FDeathLeap.Clear;FFlettaBarrier.Clear;FFlettaProc.Clear;
    FBodyBlowCharge:=Default(TB1008ChargeAdmission);
    FTornadoVisualUntilTick:=0;FSkillEndTarget:=0;FSkillImpactUntilTick:=0;
    FRegeneration:=Default(TB1008Regeneration);
    for I:=0 to High(FSpiders) do begin
      FSpiders[I].AI.Stop;FSpiders[I].Visible:=False;
      FSpiders[I].StunEffectActive:=False;FSpiders[I].Coercive.Clear;
      FSpiders[I].WindBleed.Clear;
      FillChar(FSpiders[I].ProfessionEffects,SizeOf(FSpiders[I].ProfessionEffects),0);
      FSpiders[I].Encounter.Free;
      FSpiders[I].Encounter:=TB1008SpiderEncounter.Create(FSpiders[I].Definition.MaxHP,TB1008Balance.PlayerDamage);
    end;
    SetLength(AReplies,1);AReplies[0]:=Reply;FStage:=ssCharacterPreview;
    Exit('CHARACTER SELECT | saved preview restored; world ownership released');
  end;
  if (APayload[0] = $02) and (APayload[1] = $00) then
  begin
    // Serializer 0x4CF278: group, command, tick32, field16, field16,
    // then three UTF-8 NUL-terminated strings (0x43327C -> CP_UTF8).
    // Validate without materializing/logging credentials. Roles remain opaque.
    if Length(APayload) < 13 then
      raise EKarosProtocol.Create('Truncated LoginReq');
    Offset := 10;
    for I := 0 to 2 do
    begin
      Start := Offset;
      while (Offset < Length(APayload)) and (APayload[Offset] <> 0) do
        Inc(Offset);
      if Offset = Length(APayload) then
        raise EKarosProtocol.Create('Unterminated LoginReq field');
      Sizes[I] := Offset - Start;
      Starts[I] := Start;
      if (Sizes[I] > 0) and (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
        PAnsiChar(@APayload[Start]), Sizes[I], nil, 0) = 0) then
        raise EKarosProtocol.Create('Invalid LoginReq UTF-8');
      Inc(Offset);
    end;
    if Offset <> Length(APayload) then
      raise EKarosProtocol.Create('Unexpected LoginReq trailing data');
    if FStage in [ssEmptyAccountProbe, ssCharacterPreview, ssMapLoadingProbe, ssAppearanceProbe] then
      Exit('LOGIN duplicate ignored | empty-account probe already prepared; reconnect for another attempt');
    FStage := ssLoginObserved;
    Result := Format('LOGIN OBSERVED | fields=%d/%d | UTF-8 byte lengths=%d/%d/%d | contents redacted; authentication not implemented',
      [TB1008Wire.ReadBE16(APayload, 6), TB1008Wire.ReadBE16(APayload, 8),
       Sizes[0], Sizes[1], Sizes[2]]);
    if FLoginMode in [blEmptyAccountProbe, blCharacterPreview, blMapLoadingProbe] then
    begin
      if (TB1008Wire.ReadBE16(APayload, 6) <> 14) or
        (TB1008Wire.ReadBE16(APayload, 8) <> 0) then
        Exit('LOGIN PROBE SKIPPED | unsupported request fields (expected 14/0); no reply');
      IsTest := (Sizes[0] = 4) and (Sizes[1] = 4) and (Sizes[2] = 0);
      if IsTest then
        for I := 0 to 1 do
          IsTest := IsTest and (APayload[Starts[I]] = $74) and
            (APayload[Starts[I]+1] = $65) and (APayload[Starts[I]+2] = $73) and
            (APayload[Starts[I]+3] = $74);
      if not IsTest then
        Exit('LOGIN PROBE SKIPPED | use the documented dummy credentials; no reply; contents redacted');
      Timestamp := TB1008Wire.ReadBE32(APayload, 2);
      SetLength(AReplies, 2);
      AReplies[0] := TB1008Login.BuildAcknowledgement(Timestamp);
      AReplies[1] := TB1008Login.BuildEmptyListEnd(Timestamp);
      FStage := ssEmptyAccountProbe;
      Result := 'LOGIN PROBE | empty-account replies prepared (02/00 then 02/01); editor transition confirmed manually';
      if (FLoginMode in [blCharacterPreview, blMapLoadingProbe]) and Assigned(FCharacters) then
      begin
        Reply := FCharacters.Preview(Timestamp);
        if Length(Reply) > 0 then
        begin
          // Apply only to the outgoing copy. Store ownership hashes continue
          // to use the immutable original character preview.
          if Assigned(FLoot) then begin
            FClassState:=FLoot.PreviewClass(Reply);
            FEquipment:=FLoot.PreviewEquipment(Reply);
            TB1008ProgressWire.ApplyPreview(Reply,FLoot.PreviewProgress(Reply));
            TB1008Equipment.ApplyPreview(Reply,FEquipment);
            TB1008ClassWire.ApplyPreview(Reply,FClassState);
          end;
          AReplies[1] := Reply;
          FStage := ssCharacterPreview;
          Result := 'LOGIN PREVIEW | saved character id=1 prepared';
        end;
      end;
    end;
    Exit;
  end;
  if (APayload[0] = $0B) and (APayload[1] = $00) then
  begin
    if Length(APayload) <> 14 then
      raise EKarosProtocol.Create('Invalid SystemPing size (expected 14)');
    Token := TB1008Wire.ReadBE32(APayload, 6);
    if Token = $FFFFFFFF then
    begin
      // Client handler 0x5211AD consumes this sentinel WITHOUT replying.
      // Do not echo other tokens: the client echoes those and would loop.
      SetLength(AReplies, 1);
      AReplies[0] := Copy(APayload, 0, Length(APayload));
      Result := 'PING sentinel acknowledged';
    end
    else
      Result := 'PING response observed; no echo';
    Exit;
  end;
  if (APayload[0] = $02) and (APayload[1] = $02) then
  begin
    if (FLoginMode in [blCharacterPreview, blMapLoadingProbe]) and Assigned(FCharacters) and
      (FStage in [ssEmptyAccountProbe, ssCharacterPreview]) then
    begin
      Result := FCharacters.CreateCharacter(APayload, Reply);
      if Length(Reply) > 0 then
      begin
        SetLength(AReplies, 1);
        AReplies[0] := Reply;
        FStage := ssCharacterPreview;
      end;
      Exit;
    end;
    Exit(Format('CREATE OBSERVED | %d decoded bytes | contents redacted; no admitted character-preview session; no reply',
      [Length(APayload)]));
  end;
  if (APayload[0] = $02) and (APayload[1] = $04) then
  begin
    StartRequest := TB1008World.ParseStart(APayload);
    if (FLoginMode <> blMapLoadingProbe) or not Assigned(FCharacters) or
      not (FStage in [ssCharacterPreview,ssMapLoadingProbe]) then
      Exit('START SKIPPED | no admitted map-loading probe session; no reply');
    if (StartRequest.CharacterID <> 1) or (StartRequest.Option <> 0) then
      Exit('START SKIPPED | unsupported character ID or option; no reply');
    if FStage = ssMapLoadingProbe then
      Exit('START duplicate ignored | map-loading probe already sent; reconnect to retry');
    Reply := FCharacters.Preview(StartRequest.Timestamp);
    if Length(Reply) = 0 then
      Exit('START SKIPPED | no saved character; no reply');
    if not FWorld.Acquire(Self,Reply) then
      Exit('START SKIPPED | character already owned by another world session; no reply');
    try
      if Assigned(FQuests) and not FQuests.Acquire(Self,Reply) then
      begin
        FWorld.Release(Self);
        Exit('START SKIPPED | quest state already owned; no reply');
      end;
      if Assigned(FLoot) and not FLoot.Acquire(Self,Reply) then
      begin
        FWorld.Release(Self);
        if Assigned(FQuests) then FQuests.Release(Self);
        Exit('START SKIPPED | loot state already owned; no reply');
      end;
      SetLength(AReplies,2);
      if Assigned(FLoot) then begin
        // Completion marker is durable. Recover missing EXP after a crash
        // between the quest file commit and the SQLite reward transaction.
        if Assigned(FQuests) and FQuests.Rewarded(Self) then
          FProgress:=FLoot.RecordQuestEXP(Self,B1008ProtectingTheFarmID)
        else FProgress:=FLoot.Progress(Self);
        FFletta:=FLoot.Fletta(Self);
        FFlettaAttributes:=FLoot.FlettaAttributes(Self);
        FEquipment:=FLoot.Equipment(Self);
      end;
      FFrenzy.Remove;FRevenge.Clear;FDeathLeap.Clear;FTornadoVisualUntilTick:=0;FFlettaBarrier.Clear;
      AReplies[0] := TB1008World.BuildCharacterInfoProbe(Reply,StartRequest.Timestamp);
      RecoverReturn;ApplyReturnInfo(AReplies[0]);
      TB1008ProgressWire.ApplyCharacterInfo(AReplies[0],FProgress);
      FFletta.Apply(AReplies[0],FProgress.Level,FlettaRate);
      Move(Reply[15],FPlayerClassID,2);
      FClassState:=Default(TB1008ClassState);FClassState.BaseClass:=FPlayerClassID;
      FClassState.ClassID:=FPlayerClassID;
      if Assigned(FLoot) then FClassState:=FLoot.ClassState(Self);
      TB1008ClassWire.ApplyCharacterInfo(AReplies[0],FClassState);
      TB1008ProgressWire.ApplyBaseAttributes(AReplies[0],FPlayerClassID,FProgress.Level);
      TB1008ProgressWire.ApplyCombatParameters(AReplies[0],FPlayerClassID,FProgress.Level);
      TB1008Equipment.ApplyCharacterInfo(AReplies[0],FEquipment);
      FFlettaAttributes.ApplyCharacterInfo(AReplies[0]);
      ApplyPlayerParameters(AReplies[0]);
      FParameterLevel:=FProgress.Level;
      FPlayerHP:=PlayerMaxHP;FPlayerMP:=PlayerMaxMP;
      if Assigned(FLoot) and FLoot.PendingDeath(Self) then begin
        FPlayerHP:=0;FPlayerMP:=0;
      end;
      FRegeneration:=Default(TB1008Regeneration);
      TB1008ProgressWire.ApplyVitals(AReplies[0],FPlayerHP,FPlayerMP,PlayerMaxHP,PlayerMaxMP);
      AReplies[1] := TB1008World.BuildZoneProbe(StartRequest.Timestamp);
    except
      FWorld.Release(Self);
      if Assigned(FQuests) then FQuests.Release(Self);
      if Assigned(FLoot) then FLoot.Release(Self);
      AReplies := nil; raise;
    end;
    FStage := ssMapLoadingProbe;
    Exit('START PROBE | id=1 option=0 | 02/05 then 04/04 map=19003; loading experiment, NOT world-ready');
  end;
  if (APayload[0]=4) and (APayload[1]=0) then
  begin
    SyncSpiderContent;
    Regen := TB1008World.ParseRegen(APayload);
    if (FLoginMode<>blMapLoadingProbe) or not Assigned(FCharacters) or
      not (FStage in [ssMapLoadingProbe,ssAppearanceProbe]) then
      Exit('REGEN SKIPPED | no admitted map-loading session');
    if (Regen.CharacterID<>1) or (Regen.Kind<>0) or (Regen.Option<>0) then
      Exit('REGEN SKIPPED | unsupported ID/kind/option');
    if FRespawnLoading and (Regen.Timestamp=FRespawnRequestTimestamp) then
      Exit('REGEN duplicate respawn request ignored');
    if FStage=ssAppearanceProbe then begin
      if FPlayerHP<>0 then Exit('REGEN duplicate ignored');
      // The original death dialog (0x43374A -> 0x4FE32B) sends 04/00
      // and clears local actors. Use the verified map reload so the client
      // also reinitializes peaceful stance, as requested by the user.
      // Town stone: BERNEO65.NPC record 51, Remember Stone 99001.
      // A 60-unit south offset is a test clearance, NOT an original spawn.
      Position.X:=7470.669922;Position.Z:=9023.019531;
      Position.Y:=692.872986;Position.Heading:=0;
      FWorld.Checkpoint(Self,Position);
      FPlayerHP:=Max(1,(PlayerMaxHP*3) div 100);FPlayerMP:=0;
      FRegeneration.ResetPeaceful;
      FFrenzy.Remove;FRevenge.Clear;FDeathLeap.Clear;FTornadoVisualUntilTick:=0;FFlettaBarrier.Clear;FSkillEndTarget:=0;
      FHasPendingAttack:=False;FPendingSpiderHandle:=0;FSkillCast.Cancel;
      FPlayerAutoAttacking:=False;
      FClientInWorld:=False;FWorldPatrolStarted:=False;
      FWorldState.Active:=False;
      FRespawnLoading:=True;FRespawnRequestTimestamp:=Regen.Timestamp;
      for I:=0 to High(FSpiders) do begin
        FSpiders[I].AI.Stop;
        FSpiders[I].StunEffectActive:=False; // Client cleared actors before town reload.
        FSpiders[I].Coercive.Clear;
        FSpiders[I].WindBleed.Clear;
        FillChar(FSpiders[I].ProfessionEffects,SizeOf(FSpiders[I].ProfessionEffects),0);
        FSpiders[I].Encounter.Free;
        FSpiders[I].Encounter:=TB1008SpiderEncounter.Create(FSpiders[I].Definition.MaxHP,TB1008Balance.PlayerDamage);
      end;
      Reply:=FCharacters.Preview(Regen.Timestamp);
      SetLength(AReplies,2);
      AReplies[0]:=TB1008World.BuildCharacterInfoProbe(Reply,Regen.Timestamp);
      TB1008ClassWire.ApplyCharacterInfo(AReplies[0],FClassState);
      ApplyReturnInfo(AReplies[0]);
      TB1008ProgressWire.ApplyBaseAttributes(AReplies[0],FPlayerClassID,FProgress.Level);
      TB1008ProgressWire.ApplyCombatParameters(AReplies[0],FPlayerClassID,FProgress.Level);
      TB1008Equipment.ApplyCharacterInfo(AReplies[0],FEquipment);
      FFlettaAttributes.ApplyCharacterInfo(AReplies[0]);
      ApplyPlayerParameters(AReplies[0]);
      FParameterLevel:=FProgress.Level;
      TB1008ProgressWire.ApplyCharacterInfo(AReplies[0],FProgress);
      FFletta.Apply(AReplies[0],FProgress.Level,FlettaRate);
      TB1008ProgressWire.ApplyVitals(AReplies[0],FPlayerHP,FPlayerMP,PlayerMaxHP,PlayerMaxMP);
      AReplies[1]:=TB1008World.BuildZoneProbe(Regen.Timestamp);
      if Assigned(FLoot) then FLoot.CompleteRespawn(Self);
      FStage:=ssMapLoadingProbe;
      Exit('PLAYER RESPAWN | town loading, 3% HP, MP=0; death receipt completed');
    end;
    FHasPendingAttack:=False;FSkillCast.Cancel;FMinePending:=False;
    FPendingSpiderHandle:=0;
    FRespawnLoading:=False;
    FStashNpcHandle:=0;
    FPlayerAutoAttacking:=False;
    FWorldState.Restored := FWorld.Restore(Self,Position);
    FWorldState.HasCheckpoint := FWorldState.Restored;
    if FWorldState.Restored then
    begin
      Regen.X := Position.X; Regen.Z := Position.Z;
      Regen.Y := Position.Y; Regen.Heading := Position.Heading;
      StateNote := 'restored checkpoint';
    end
    else StateNote := 'client initial position';
    Reply := FCharacters.Preview(Regen.Timestamp);
    SetLength(AReplies,4);
    AReplies[0] := TB1008World.BuildAppearProbe(Reply,Regen);
    TB1008ClassWire.ApplyAppearance(AReplies[0],FClassState);
    TB1008ProgressWire.ApplyVitals(AReplies[0],FPlayerHP,FPlayerMP,PlayerMaxHP,PlayerMaxMP);
    TB1008ProgressWire.ApplyAppearance(AReplies[0],FProgress);
    FFlettaAttributes.ApplySpeeds(AReplies[0]);
    ApplyProfessionSpeeds(AReplies[0]);
    AReplies[1] := TB1008World.BuildDomingoAppearProbe(Regen.Timestamp);
    AReplies[2] := TB1008World.BuildSullibentAppearProbe(Regen.Timestamp);
    HealingCount:=0; ManaCount:=0;
    if Assigned(FQuests) and FQuests.Rewarded(Self) then
    begin
      HealingCount:=FQuests.RewardItemCount(Self,B1008BeginnerHealingPotionID);
      ManaCount:=FQuests.RewardItemCount(Self,B1008BeginnerManaPotionID);
    end;
    AReplies[3] := TB1008InventoryWire.BuildList(Regen.Timestamp,1,
      HealingCount,ManaCount);
    if Assigned(FLoot) then begin
      if Assigned(FQuests) and FQuests.Rewarded(Self) then
        FLoot.RewardFarm(Self,HealingCount,ManaCount,PickupUpdates,FarmProgress);
      AReplies[3]:=TB1008InventoryWire.BuildBagList(Regen.Timestamp,1,FLoot.Items(Self));
      AReplies[3]:=TB1008Equipment.AppendList(AReplies[3],FEquipment);
      // Restore currency through the already verified 06/06 update path.
      // 06/05's currency callback (0x50EE7C) additionally refreshes shop UI
      // during world initialization. Keep money out of that list so it is
      // counted exactly once; 06/06 updates both the stack and the balance.
      BagItem:=FLoot.Item(Self,B1008CaratID); LootCount:=BagItem.Amount;
      if LootCount>0 then begin
        SetLength(AReplies,Length(AReplies)+1);
        AReplies[High(AReplies)]:=TB1008InventoryWire.BuildPutIn(Regen.Timestamp,1,
          B1008CaratID,LootCount,BagItem.Slot);
      end;
      FDrops:=FLoot.GroundItems(Self);
      if Length(FDrops)>B1008LootGroundLimit then raise EKarosProtocol.Create('Too many persisted drops');
      for I:=0 to High(FDrops) do begin
        Inc(FNextDropID); FDrops[I].ID:=FNextDropID;
        FDrops[I].ExpiresTick:=GetTickCount64+UInt64(Max(Int64(0),FDrops[I].ExpiresUTC-B1008UtcNowMS));
        // Do not create world drop objects during loading. A movement report
        // confirms the scene can accept them; the original expiry is retained.
      end;
      SetLength(AReplies,Length(AReplies)+1);
      AReplies[High(AReplies)]:=PlayerSkillList(Regen.Timestamp);
      AppendReturnCooldown(Regen.Timestamp,AReplies);
    end;
    if Assigned(FQuests) and FQuests.Active(Self) then
    begin
      SetLength(AReplies,Length(AReplies)+1);
      QuestProgress:=FQuests.Progress(Self);
      AReplies[High(AReplies)] := TB1008QuestWire.BuildActiveList(Regen.Timestamp,QuestProgress);
      // 0x4F6D46 loads every restored quest in state 1. Only the 09/03 path
      // (0x4FF6C7) promotes it to state 2 when the last objective is complete.
      if QuestProgress=5 then begin
        SetLength(AReplies,Length(AReplies)+1);
        AReplies[High(AReplies)] := TB1008QuestWire.BuildProgress(Regen.Timestamp,QuestProgress);
      end;
      StateNote := StateNote+Format('; quest 19003003 restored (%d/5)',[QuestProgress]);
    end;
    if Assigned(FQuests) and FQuests.Rewarded(Self) then
    begin
      SetLength(AReplies,Length(AReplies)+1);
      AReplies[High(AReplies)] := TB1008QuestWire.BuildCompleteList(Regen.Timestamp,1);
      StateNote := StateNote+'; completed quest and first reward inventory restored';
    end;
    AppendCatalogQuests(Regen.Timestamp,AReplies);
    for I:=0 to High(FSpiders) do
    begin
      FSpiders[I].AI.Reset(GetTickCount64,I);
      FSpiders[I].StunEffectActive:=False; // Fresh client scene has no attached buffs.
      FSpiders[I].Coercive.Clear;
      FSpiders[I].WindBleed.Clear;
      FillChar(FSpiders[I].ProfessionEffects,SizeOf(FSpiders[I].ProfessionEffects),0);
      FSpiders[I].Visible:=FSpiders[I].Spawn.MobID=120;
      if not FSpiders[I].Visible then Continue; // New species stream in after scene initialization.
      SetLength(AReplies,Length(AReplies)+1);
      AReplies[High(AReplies)] := TB1008World.BuildSpiderAppearProbe(
        Regen.Timestamp,FSpiders[I].Handle,FSpiders[I].Definition.MaxHP,
        FSpiders[I].Definition.MovementSpeed,FSpiders[I].Definition.ChaseSpeed,
        FSpiders[I].Definition.AttackSpeed,
        FSpiders[I].Spawn.X,FSpiders[I].Spawn.Z,FSpiders[I].Spawn.Y,
        FSpiders[I].Spawn.Heading);
      FSpiders[I].SentChaseSpeed:=FSpiders[I].Definition.ChaseSpeed;
    end;
    for I:=0 to High(FSpiders) do
      if FSpiders[I].Visible then AppendSpiderMotionReset(I,Regen.Timestamp,AReplies);
    StateNote:=StateNote+'; native idle initialized by appearance';
    StateNote := StateNote+Format('; Berneo population=%d, independent combat; nearby species streamed',
      [Length(FSpiders)]);
    if Assigned(FRuntime) then
      for Npc in TB1008Npcs.All do
        if (Npc.Handle<>121) and (Npc.Handle<>136) then begin
          SetLength(AReplies,Length(AReplies)+1);
          AReplies[High(AReplies)]:=TB1008Npcs.BuildAppear(Regen.Timestamp,Npc);
        end;
    FWorldState.Active := True; FWorldState.Moving := False;
    FMovementAdmission.Reset;
    FWorldState.CharacterID := 1; FWorldState.MapID := B1008BerneoMapID;
    FWorldState.Position.X := Regen.X; FWorldState.Position.Z := Regen.Z;
    FWorldState.Position.Y := Regen.Y; FWorldState.Position.Heading := Regen.Heading;
    FStage := ssAppearanceProbe;
    FAutoWorldStartTick:=GetTickCount64;
    Inc(FAutoWorldStartTick,250);
    Exit(Format('APPEAR PROBE | id=1 X=%.3f Z=%.3f Y=%.3f heading=%.3f | %s; HP=%d/%d MP=%d/%d; Domingo=121 and Sullibent=136 activated',
      [Regen.X,Regen.Z,Regen.Y,Regen.Heading,StateNote,FPlayerHP,PlayerMaxHP,
       FPlayerMP,PlayerMaxMP],TFormatSettings.Invariant));
  end;
  if (APayload[0]=4) and (APayload[1]=1) then
  begin
    Movement := TB1008World.ParseMovement(APayload);
    if (FLoginMode<>blMapLoadingProbe) or (FStage<>ssAppearanceProbe) then
      Exit('MOVE SKIPPED | no admitted appearance session');
    if (Movement.CharacterID<>1) or (Movement.Kind<>0) then
      Exit('MOVE SKIPPED | unsupported character ID/kind');
    FMovementAdmission.Observe(Movement,GetTickCount64);
    FClientInWorld:=True;
    StartWorldPatrol(GetTickCount64);
    // Any explicit movement/stop report after an attack start invalidates its
    // pending impact. This includes the stationary report emitted by Esc.
    FHasPendingAttack:=False;FSkillCast.Cancel;FMinePending:=False;
    FSkillEndTarget:=0;
    FPlayerAutoAttacking:=False;
    FPendingSpiderHandle:=0;
    // Observe, not authoritative movement. The self receive handler 0x4FDAFB
    // can change local movement state, so do not blindly echo these reports.
    StateNote := 'unmapped mode; no checkpoint';
    if (Movement.Mode=1) or ((Movement.Mode=2) and
      (Abs(Movement.FromX-Movement.ToX)<=0.01) and
      (Abs(Movement.FromZ-Movement.ToZ)<=0.01) and
      (Abs(Movement.FromY-Movement.ToY)<=0.01)) then
    begin
      // From is the reported current point; To may be an unreached destination.
      FWorldState.Position.X := Movement.FromX;
      FWorldState.Position.Z := Movement.FromZ;
      FWorldState.Position.Y := Movement.FromY;
      FWorldState.Moving := Movement.Mode=1;
      // Parameter is not yet proven to be heading: retain the Regen heading.
      StateNote := 'moving report; no checkpoint';
      if not FWorldState.Moving then
      begin
        try
          FWorld.Checkpoint(Self,FWorldState.Position);
          FWorldState.HasCheckpoint := True;
          StateNote := 'stop checkpoint committed';
        except
          on E: Exception do StateNote := 'CHECKPOINT FAILED: '+E.Message;
        end;
      end;
    end
    else if Movement.Mode=2 then StateNote := 'inconsistent stop vectors; no checkpoint';
    Exit(Format('MOVE OBSERVED | id=1 mode=%d from=(%.3f,%.3f,%.3f) to=(%.3f,%.3f,%.3f) parameter=%.3f flags=%d/%d | client report only; no echo; %s',
      [Movement.Mode,Movement.FromX,Movement.FromZ,Movement.FromY,
       Movement.ToX,Movement.ToZ,Movement.ToY,Movement.Parameter,Movement.FlagA,Movement.FlagB,StateNote],TFormatSettings.Invariant));
  end;
  if (APayload[0]=9) and Assigned(FLoot) and (APayload[1] in [0,1,3]) then begin
    if (Length(APayload)<14) then raise EKarosProtocol.Create('Truncated quest request');
    if (APayload[1]=3) or (TB1008Wire.ReadBE32(APayload,10)<>B1008ProtectingTheFarmID) then
      Exit(HandleCatalogQuest(APayload,AReplies));
  end;
  if (APayload[0]=9) and (APayload[1]=0) then
  begin
    QuestStart := TB1008QuestWire.ParseStart(APayload);
    if (FLoginMode<>blMapLoadingProbe) or (FStage<>ssAppearanceProbe) or
      not FWorldState.Active then Exit('QUEST START SKIPPED | no admitted world session');
    if QuestStart.CharacterID<>FWorldState.CharacterID then
      Exit('QUEST START SKIPPED | unsupported character ID');
    if (QuestStart.QuestID<>B1008ProtectingTheFarmID) or
      (QuestStart.Code<>B1008QuestStartCode) then
      Exit('QUEST START SKIPPED | unsupported quest/code');
    if Assigned(FQuests) then
    begin
      Reply := TB1008QuestWire.BuildStartAck(QuestStart.Timestamp);
      if FQuests.Accept(Self) then StateNote := 'committed before acknowledgement'
      else StateNote := 'already active; no duplicate state or reward';
      SetLength(AReplies,1); AReplies[0] := Reply;
      Exit(Format('QUEST ACCEPTED | character=1 quest=19003003 code=2B progress=%d/5 | %s',[FQuests.Progress(Self),StateNote]));
    end;
    Exit(Format('QUEST START OBSERVED | character=%d quest=%d code=%s | NOT accepted; persistence and acknowledgement pending; no reply',
      [QuestStart.CharacterID,QuestStart.QuestID,IntToHex(QuestStart.Code,2)]));
  end;
  if (APayload[0]=9) and (APayload[1]=1) then
  begin
    QuestReward := TB1008QuestWire.ParseReward(APayload);
    if FPlayerHP=0 then Exit('QUEST REWARD SKIPPED | player is dead');
    if (FLoginMode<>blMapLoadingProbe) or (FStage<>ssAppearanceProbe) or
      not FWorldState.Active then Exit('QUEST REWARD SKIPPED | no admitted world session');
    if QuestReward.CharacterID<>FWorldState.CharacterID then
      Exit('QUEST REWARD SKIPPED | unsupported character ID');
    if QuestReward.QuestID<>B1008ProtectingTheFarmID then
      Exit('QUEST REWARD SKIPPED | unsupported quest');
    if (QuestReward.Choice<>$FFFFFFFF) or (QuestReward.Code<>B1008QuestStartCode) then
      Exit('QUEST REWARD SKIPPED | unsupported choice/code');
    if Assigned(FLoot) and Assigned(FQuests) and
      (FQuests.Rewarded(Self) or (FQuests.Active(Self) and (FQuests.Progress(Self)=5))) then begin
      if FQuests.Rewarded(Self) then begin
        HealingCount:=FQuests.RewardItemCount(Self,B1008BeginnerHealingPotionID);
        ManaCount:=FQuests.RewardItemCount(Self,B1008BeginnerManaPotionID);
      end else begin HealingCount:=B1008FirstRewardCount;ManaCount:=B1008FirstRewardCount;end;
      // Inventory, money and EXP commit together before the legacy completion
      // marker. A failed marker write can be retried without a second grant.
      try
        if not FLoot.RewardFarm(Self,HealingCount,ManaCount,PickupUpdates,FarmProgress) then begin
          SetLength(AReplies,1);
          AReplies[0]:=TB1008QuestWire.BuildRewardAck(QuestReward.Timestamp,1,
            QuestReward.QuestID,QuestReward.Choice,$A3);
          Exit('QUEST REWARD REJECTED | insufficient bag capacity; quest remains ready');
        end;
        if not FQuests.Rewarded(Self) then FQuests.Complete(Self);
      except on E:Exception do Exit('QUEST REWARD RETRYABLE | '+E.Message);end;
      AcceptProgress(FarmProgress);
      // Absolute quantities also repair a retry after the sidecar write failed.
      AppendQuestItems(QuestReward.Timestamp,FLoot.Items(Self),AReplies);
      SetLength(AReplies,Length(AReplies)+2);
      AReplies[High(AReplies)-1]:=TB1008QuestWire.BuildRewardAck(QuestReward.Timestamp,1,
        QuestReward.QuestID,QuestReward.Choice,B1008QuestStartCode);
      AReplies[High(AReplies)]:=PlayerGage(QuestReward.Timestamp,True);
      Exit('QUEST REWARDED | Farm potions, 100 Carat and EXP committed; replay safe');
    end;
    if not Assigned(FQuests) or not FQuests.Active(Self) or
      (FQuests.Progress(Self)<>5) then
    begin
      if Assigned(FQuests) and FQuests.Rewarded(Self) then begin
        SetLength(AReplies,1);
        AReplies[0]:=TB1008QuestWire.BuildRewardAck(QuestReward.Timestamp,
          QuestReward.CharacterID,QuestReward.QuestID,QuestReward.Choice,
          B1008QuestStartCode);
        Exit('QUEST REWARD duplicate acknowledged | no duplicate items');
      end;
      Exit('QUEST REWARD SKIPPED | objectives are not complete');
    end;
    try
      if not FQuests.Complete(Self) then
        Exit('QUEST REWARD SKIPPED | completion race');
    except
      on E:Exception do Exit('QUEST REWARD NOT COMMITTED | no reply or items; '+E.Message);
    end;
    SetLength(AReplies,3);
    AReplies[0]:=TB1008InventoryWire.BuildPutIn(QuestReward.Timestamp,
      QuestReward.CharacterID,B1008BeginnerHealingPotionID,B1008FirstRewardCount,0);
    AReplies[1]:=TB1008InventoryWire.BuildPutIn(QuestReward.Timestamp,
      QuestReward.CharacterID,B1008BeginnerManaPotionID,B1008FirstRewardCount,1);
    AReplies[2]:=TB1008QuestWire.BuildRewardAck(QuestReward.Timestamp,
      QuestReward.CharacterID,QuestReward.QuestID,QuestReward.Choice,
      B1008QuestStartCode);
    Exit(Format('QUEST REWARDED | size=%d character=%d quest=%d choice=%d code=%s | HP potion x3 slot=0, MP potion x3 slot=1; committed before replies',
      [QuestReward.WireSize,
       QuestReward.CharacterID,QuestReward.QuestID,QuestReward.Choice,
       IntToHex(QuestReward.Code,8)]));
  end;
  if (APayload[0]=5) and (APayload[1]=4) then begin
    SkillCancel:=TB1008SkillCancel.Parse(APayload);
    if (FStage<>ssAppearanceProbe) or not FWorldState.Active or
      (SkillCancel.ActorKind<>0) or (SkillCancel.ActorID<>1) or
      ((SkillCancel.SkillID<>B1008PowerStrikeID) and (SkillCancel.SkillID<>B1008BodyBlowID) and
       (SkillCancel.SkillID<>B1008FrenzyID) and (SkillCancel.SkillID<>B1008ProvocationID) and
       (SkillCancel.SkillID<>B1008CoerciveID) and not (TB1008ProfessionSkill.Supported(SkillCancel.SkillID) and
         not TB1008ProfessionSkill.IsPassive(SkillCancel.SkillID)) and
       not TB1008FlettaProc.Enabled(SkillCancel.SkillID)) then
      Exit('SKILL CANCEL SKIPPED | unsupported actor/skill/session');
    FSkillCast.Cancel;
    if TB1008FlettaProc.Enabled(SkillCancel.SkillID) then FFlettaProc.Clear;
    FSkillEndTarget:=0;
    if FHasPendingAttack and (FPendingAttack.ActionKind=1) then begin
      FHasPendingAttack:=False;FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;
    end;
    Exit('SKILL CANCELLED | pending cast cleared; cooldown retained');
  end;
  if (APayload[0]=5) and (APayload[1]=3) then begin
    SkillReady:=TB1008SkillReady.Parse(APayload);
    if not Assigned(FLoot) or (FLoginMode<>blMapLoadingProbe) or
      (FStage<>ssAppearanceProbe) or not FWorldState.Active or (FPlayerHP<=0) then
      Exit('SKILL READY SKIPPED | no living admitted character');
    if not SkillReady.Supported or ((FPlayerClassID<>100) and not TB1008FlettaProc.Enabled(SkillReady.SkillID)) then
      Exit(Format('SKILL READY OBSERVED | actor=%d/%u skill=%u rank=%u target=%d/%u code=%d; unsupported',
        [SkillReady.ActorKind,SkillReady.ActorID,SkillReady.SkillID,SkillReady.Rank,
         SkillReady.TargetKind,SkillReady.TargetID,SkillReady.Code]));
    // On a valid local request that cannot start, release the client skill state.
    SetLength(AReplies,1);AReplies[0]:=TB1008SkillWire.BuildCancel(SkillReady.Timestamp,
      FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y,FWorldState.Position.Heading,SkillReady.SkillID);
    if TB1008ProfessionSkill.Supported(SkillReady.SkillID) and
      not TB1008ProfessionSkill.Allowed(SkillReady.SkillID,FClassState.ClassID) then
      Exit('SKILL READY REJECTED | wrong profession');
    HasSkill:=False;
    for LearnedSkill in FLoot.LearnedSkills(Self) do
      if (LearnedSkill.ID=SkillReady.SkillID) and (LearnedSkill.Rank=SkillReady.Rank) then HasSkill:=True;
    if TB1008FlettaProc.Enabled(SkillReady.SkillID) and (SkillReady.Rank=1) then
      HasSkill:=TB1008FlettaProc.CombinedSkill(FFlettaAttributes)=SkillReady.SkillID;
    HasWeapon:=SkillWeaponAllowed(SkillReady.SkillID);
    if not HasSkill or ((SkillReady.SkillID<>B1008FrenzyID) and
      (SkillReady.SkillID<>B1008CoerciveID) and not HasWeapon) then
      Exit('SKILL READY REJECTED | requires learned skill rank and equipped weapon');
    if FHasPendingAttack and (FPendingAttack.ActionKind=1) and
      (GetTickCount64<=FSkillImpactUntilTick) then begin
      AReplies:=nil;Exit('SKILL READY REJECTED | skill impact pending');
    end;
    if TB1008FlettaBarrier.Supported(SkillReady.SkillID) then begin
      HitTick:=GetTickCount64;
      if (FFlettaProc.SkillID<>SkillReady.SkillID) or FFlettaBarrier.Active(HitTick) or
        not FFlettaProc.Prepare(1,SkillReady.Timestamp,HitTick) then
        Exit('FLETTA READY REJECTED | no matching self proc');
      if not FSkillCast.Prepare(SkillReady.Timestamp,1,HitTick,FPlayerMP,1,SkillReady.SkillID) then begin
        FFlettaProc.Clear;Exit('FLETTA READY REJECTED | self preparation');
      end;
      FHasPendingAttack:=False;FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;FSkillEndTarget:=0;
      SkillReady.X:=FWorldState.Position.X;SkillReady.Z:=FWorldState.Position.Z;
      SkillReady.Y:=FWorldState.Position.Y;SkillReady.Heading:=FWorldState.Position.Heading;
      AReplies[0]:=SkillReady.Ack;
      Exit(Format('FLETTA READY ACCEPTED | skill=%u self; waiting action=0',[SkillReady.SkillID]));
    end;
    if (SkillReady.SkillID=B1008FrenzyID) or (SkillReady.SkillID=B1008ProvocationID) or
      (SkillReady.SkillID=B1008CoerciveID) or TB1008ProfessionSkill.IsSelf(SkillReady.SkillID) then begin
      HitTick:=GetTickCount64;
      if not FSkillCast.Prepare(SkillReady.Timestamp,1,HitTick,FPlayerMP,SkillReady.Rank,SkillReady.SkillID) then
        Exit('SKILL READY REJECTED | self skill mana/cooldown/replay');
      // A queued Fletta proc can run after this self cast's native finish.
      // Applying Frenzy must not discard a barrier already earned by a hit.
      FHasPendingAttack:=False;FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;FSkillEndTarget:=0;
      // Self skill does not authorize movement. 501362 selects actor 0/1.
      SkillReady.X:=FWorldState.Position.X;SkillReady.Z:=FWorldState.Position.Z;
      SkillReady.Y:=FWorldState.Position.Y;SkillReady.Heading:=FWorldState.Position.Heading;
      AReplies[0]:=SkillReady.Ack;
      Exit(Format('SKILL READY ACCEPTED | skill=%u rank=%u self; waiting action=%u',
        [SkillReady.SkillID,SkillReady.Rank,TB1008AttackSkillStats.Get(SkillReady.SkillID,SkillReady.Rank).ActionID]));
    end;
    SyncSpiderContent;SpiderIndex:=FindSpiderIndex(SkillReady.TargetID);
    if SpiderIndex<0 then Exit('SKILL READY REJECTED | target not visible');
    Spider:=@FSpiders[SpiderIndex];HitTick:=GetTickCount64;Spider^.AI.UpdatePosition(HitTick);
    Position:=FWorldState.Position;
    if FMovementAdmission.Allows(SkillReady.X,SkillReady.Z,SkillReady.Y,HitTick,
      FFlettaAttributes.MovementMultiplier) then begin
      Position.X:=SkillReady.X;Position.Z:=SkillReady.Z;Position.Y:=SkillReady.Y;
    end;
    AttackStart:=Default(TB1008AttackStart);AttackStart.Timestamp:=SkillReady.Timestamp;
    SkillParameters:=TB1008AttackSkillStats.Get(SkillReady.SkillID,SkillReady.Rank);
    AttackStart.ActorID:=1;AttackStart.ActionKind:=1;AttackStart.ActionID:=SkillParameters.ActionID;
    AttackStart.TargetKind:=1;AttackStart.TargetID:=SkillReady.TargetID;
    AttackStart.X:=SkillReady.X;AttackStart.Z:=SkillReady.Z;AttackStart.Y:=SkillReady.Y;
    AttackStart.Heading:=SkillReady.Heading;
    AttackStart.TargetX:=Spider^.AI.X;AttackStart.TargetZ:=Spider^.AI.Z;AttackStart.TargetY:=Spider^.AI.Y;
    if not Spider^.Encounter.TryHit(AttackStart,Spider^.Handle,Position.X,Position.Z,Position.Y,
      Spider^.AI.X,Spider^.AI.Z,Spider^.AI.Y,PlayerHitRange(SpiderIndex,1,AttackStart.ActionID),HitTick,StateNote,False) then
      Exit('SKILL READY REJECTED | '+StateNote);
    if (TB1008FlettaProc.YinSupported(SkillReady.SkillID)) and
      not FFlettaProc.Prepare(SkillReady.TargetID,SkillReady.Timestamp,HitTick) then
      Exit('FLETTA READY REJECTED | no matching server proc');
    if not FSkillCast.Prepare(SkillReady.Timestamp,SkillReady.TargetID,HitTick,FPlayerMP,SkillReady.Rank,SkillReady.SkillID) then begin
      if TB1008FlettaProc.YinSupported(SkillReady.SkillID) then FFlettaProc.Clear;
      Exit('SKILL READY REJECTED | mana/cooldown/duplicate request');
    end;
    FBodyBlowCharge.Arm(SkillReady,Spider^.AI.X,Spider^.AI.Z,Spider^.AI.Y,HitTick);
    if not TB1008FlettaProc.YinSupported(SkillReady.SkillID) then FFlettaProc.Clear;
    FHasPendingAttack:=False;FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;
    FWorldState.Position.X:=SkillReady.X;FWorldState.Position.Z:=SkillReady.Z;
    FWorldState.Position.Y:=SkillReady.Y;FWorldState.Moving:=False;FMovementAdmission.Reset;
    FClientInWorld:=True;
    AReplies[0]:=SkillReady.Ack;
    Exit(Format('SKILL READY ACCEPTED | skill=%u rank=%u target=%u MP=%d; cost waits for 05/00 action 1/%u',
      [SkillReady.SkillID,SkillReady.Rank,SkillReady.TargetID,FPlayerMP,SkillParameters.ActionID]));
  end;
  if (APayload[0]=5) and (APayload[1]=0) then
  begin
    SyncSpiderContent;
    AttackStart:=TB1008CombatWire.ParseStart(APayload);
    AttackSkillID:=TB1008AttackSkillStats.FromAction(AttackStart.ActionID);
    if (AttackStart.ActionID=0) and TB1008FlettaProc.YinSupported(FFlettaProc.SkillID) then
      AttackSkillID:=FFlettaProc.SkillID;
    IsAttackSkill:=(AttackStart.ActionKind=1) and (AttackSkillID<>0);
    if FPlayerHP<=0 then Exit('ATTACK SKIPPED | player dead');
    if (FLoginMode<>blMapLoadingProbe) or (FStage<>ssAppearanceProbe) or
      not FWorldState.Active then Exit('ATTACK SKIPPED | no admitted world session');
    if (AttackStart.ActorKind<>0) or (AttackStart.ActorID<>FWorldState.CharacterID) then
      Exit('ATTACK SKIPPED | unsupported actor ID/kind');
    FMinePending:=False;
    if (AttackStart.ActionKind=0) and (AttackStart.ActionID=900) and
      (AttackStart.TargetKind=2) and (AttackStart.TargetID=1) then begin
      MiningPick:=False;
      for GearItem in FEquipment do if (GearItem.Slot=7) and
        TB1008Mining.IsPick(GearItem.ItemID) then MiningPick:=True;
      HitTick:=GetTickCount64;
      if MiningPick and not FHasPendingAttack and not FPlayerAutoAttacking and
        TB1008Mining.Near(FWorldState.MapID,FWorldState.Position.X,
          FWorldState.Position.Z,FWorldState.Position.Y) and
        TB1008Mining.Near(FWorldState.MapID,AttackStart.TargetX,AttackStart.TargetZ,
          AttackStart.TargetY) then begin
        FMinePending:=True;FMineStartedTick:=HitTick;FMineStartTimestamp:=AttackStart.Timestamp;
        // b1008 performs this animation locally and sends a separate 0A/02
        // after completion. Do not arm mob damage or invent a finish reply.
        Exit('MINING START ACCEPTED | quest vein; local animation900');
      end;
      if MiningPick then MiningCode:=$60 else MiningCode:=$61;
      SetLength(AReplies,1);AReplies[0]:=TB1008Mining.BuildResult(AttackStart.Timestamp,1,MiningCode,[]);
      Exit('MINING START REJECTED | tool, position, combat or cycle guard');
    end;
    if (AttackStart.ActionKind=1) and (AttackStart.ActionID=0) and
      TB1008FlettaBarrier.Supported(FFlettaProc.SkillID) then begin
      HitTick:=GetTickCount64;SelfSkillID:=FFlettaProc.SkillID;
      if (AttackStart.TargetKind>1) or (AttackStart.TargetID<>1) then
        Exit('FLETTA START REJECTED | invalid self target');
      if not FFlettaProc.Start(1,AttackStart.Timestamp,HitTick) or
        not FSkillCast.Start(AttackStart.Timestamp,1,HitTick,FPlayerMP,SelfSkillID) then begin
        SetLength(AReplies,1);AReplies[0]:=TB1008SkillWire.BuildCancel(AttackStart.Timestamp,
          FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y,FWorldState.Position.Heading,SelfSkillID);
        FFlettaProc.Clear;FSkillCast.Cancel;
        Exit('FLETTA START REJECTED | self proc handshake; cancelled');
      end;
      FFlettaBarrier.Start(SelfSkillID,HitTick,TB1008Balance.WindBarrierDefenseRating);
      FPlayerHP:=Min(PlayerMaxHP,FPlayerHP+TB1008FlettaBarrier.Healing(SelfSkillID));
      SetLength(AReplies,4);
      AReplies[0]:=TB1008CombatWire.BuildSelfSkillAction(AttackStart,
        FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y,FWorldState.Position.Heading);
      AReplies[1]:=TB1008FlettaProc.BuildBuff(AttackStart.Timestamp,SelfSkillID,
        TB1008FlettaBarrier.DurationMS(SelfSkillID),True);
      AReplies[2]:=PlayerGage(AttackStart.Timestamp,False);
      ImpactAttack:=AttackStart;ImpactAttack.ActionKind:=5;
      AReplies[3]:=TB1008CombatWire.BuildSelfSkillAction(ImpactAttack,
        FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y,FWorldState.Position.Heading);
      FFlettaProc.Clear;FSkillCast.Cancel;FSkillEndTarget:=0;FHasPendingAttack:=False;
      FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;
      Exit(Format('FLETTA BARRIER APPLIED | skill=%u duration=%ums heal=%d HP=%d ratingBonus=%d; native finish sent',
        [SelfSkillID,TB1008FlettaBarrier.DurationMS(SelfSkillID),TB1008FlettaBarrier.Healing(SelfSkillID),FPlayerHP,
         FFlettaBarrier.DefenseRatingBonus(HitTick)]));
    end;
    SelfSkillID:=TB1008AttackSkillStats.SelfFromAction(AttackStart.ActionID);
    // 1019 names both sword Death Leap and polearm Revenge. Authenticate
    // with the actual prepared cast (or admitted finish), never the alias.
    if AttackStart.ActionID=1019 then begin
      if AttackStart.ActionKind=5 then SelfSkillID:=FSkillEndSkillID
      else SelfSkillID:=FSkillCast.PreparedSkillID;
      if not ((SelfSkillID=B1008SwordDeathLeapID) or (SelfSkillID=B1008PolearmRevengeID)) then
        Exit('PROFESSION START REJECTED | ambiguous action without matching skill');
    end;
    if SelfSkillID<>0 then begin
      case SelfSkillID of
        B1008FrenzyID:SelfSkillName:='FRENZY';B1008ProvocationID:SelfSkillName:='PROVOCATION';
        B1008CoerciveID:SelfSkillName:='COERCIVE';
      else SelfSkillName:=Format('PROFESSION %u',[SelfSkillID]);
      end;
      HitTick:=GetTickCount64;
      if AttackStart.ActionKind=5 then begin
        if (FSkillEndSkillID<>SelfSkillID) or (FSkillEndTarget<>1) or
          (HitTick>FSkillEndUntilTick) or
          (((Int64(AttackStart.Timestamp)-Int64(FPendingAttack.Timestamp)+$100000000) mod $100000000)>=$80000000) then
          Exit('SKILL END SKIPPED | no matching self cast');
        SetLength(AReplies,1);AReplies[0]:=TB1008CombatWire.BuildSelfSkillAction(AttackStart,
          FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y,FWorldState.Position.Heading);
        FSkillEndTarget:=0;FHasPendingAttack:=False;FPendingSpiderHandle:=0;
        Exit('SKILL END ACCEPTED | '+SelfSkillName+' animation completed');
      end;
      // 501504 copies current selection kind, including selected loot/NPCs,
      // even though the authenticated self target ID is always1.
      // Canonicalize the start reply to actor 0/1 for self-centered skills.
      if (AttackStart.ActionKind<>1) or (AttackStart.TargetID<>1) then
        Exit(RejectPreparedSelf(Format('%s START REJECTED | action=%u target=%u/%u; invalid self target/action',
          [SelfSkillName,AttackStart.ActionKind,AttackStart.TargetKind,AttackStart.TargetID])));
      if FHasPendingAttack and (FPendingAttack.ActionKind=1) and (HitTick<=FSkillImpactUntilTick) then
        Exit(RejectPreparedSelf(SelfSkillName+' START REJECTED | skill impact pending'));
      HasWeapon:=False;for GearItem in FEquipment do if GearItem.Slot=7 then HasWeapon:=True;
      if (SelfSkillID=B1008ProvocationID) and not HasWeapon then
        Exit(RejectPreparedSelf(SelfSkillName+' START REJECTED | weapon required'));
      if TB1008ProfessionSkill.Supported(SelfSkillID) and not SkillWeaponAllowed(SelfSkillID) then
        Exit(RejectPreparedSelf(SelfSkillName+' START REJECTED | weapon requirement changed'));
      if not FSkillCast.Start(AttackStart.Timestamp,1,HitTick,FPlayerMP,SelfSkillID) then
        Exit(RejectPreparedSelf(SelfSkillName+' START REJECTED | missing preparation/mana/cooldown'));
      FPendingAttack:=AttackStart;FPendingAttack.TargetKind:=0;FPendingAttack.TargetID:=1;
      FHasPendingAttack:=True;FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;
      FSkillImpactUntilTick:=HitTick+B1008SkillHandshakeMS;
      FSkillEndUntilTick:=HitTick+5000;FSkillEndTarget:=1;FSkillEndSkillID:=SelfSkillID;
      SetLength(AReplies,2);AReplies[0]:=TB1008CombatWire.BuildSelfSkillAction(AttackStart,
        FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y,FWorldState.Position.Heading);
      AReplies[1]:=PlayerGage(AttackStart.Timestamp,False);
      Exit(Format('%s START ACCEPTED | rank=%u MP=%d; cooldown=%ums; waiting impact',
        [SelfSkillName,FSkillCast.ActiveRank,FPlayerMP,TB1008AttackSkillStats.Get(SelfSkillID,FSkillCast.ActiveRank).CooldownMS]));
    end;
    if (AttackStart.ActionKind=5) and (AttackSkillID<>0) then begin
      // 0x501564 serializes the CURRENT selection, which can disappear after
      // a lethal hit. 0x52AD58 calls the owner's finish vtable+$74 without
      // consuming target/pose arguments. Authenticate the actual cast, not a
      // still-living selection. Never echo callback coordinates as movement.
      if (FSkillEndTarget=0) or (AttackSkillID<>FSkillEndSkillID) or
        (GetTickCount64>FSkillEndUntilTick) or
        (((Int64(AttackStart.Timestamp)-Int64(FPendingAttack.Timestamp)+$100000000) mod $100000000)>=$80000000) then
        Exit('SKILL END SKIPPED | no matching cast');
      ImpactAttack:=FPendingAttack;ImpactAttack.Timestamp:=AttackStart.Timestamp;
      ImpactAttack.ActionKind:=5;ImpactAttack.TargetKind:=1;ImpactAttack.TargetID:=FSkillEndTarget;
      SetLength(AReplies,1);AReplies[0]:=TB1008CombatWire.BuildSpiderStartAccepted(ImpactAttack,
        FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y);
      FSkillEndTarget:=0;FHasPendingAttack:=False;FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;
      if TB1008FlettaProc.YinSupported(AttackSkillID) then FFlettaProc.Clear;
      Exit(Format('SKILL END ACCEPTED | skill=%u clientTarget=%d/%u castTarget=%u; animation completed; no extra cost or damage',
        [AttackSkillID,AttackStart.TargetKind,AttackStart.TargetID,ImpactAttack.TargetID]));
    end;
    FClientInWorld:=True;
    StartWorldPatrol(GetTickCount64);
    SpiderIndex:=FindSpiderIndex(AttackStart.TargetID);
    if ((AttackStart.ActionKind=0) or IsAttackSkill) and (AttackStart.TargetKind=1) and
      (SpiderIndex>=0) then
    begin
      Spider:=@FSpiders[SpiderIndex];
      HitTick:=GetTickCount64;
      Spider^.AI.UpdatePosition(HitTick);
      Position:=FWorldState.Position;
      if FMovementAdmission.Allows(AttackStart.X,AttackStart.Z,AttackStart.Y,HitTick,
        FFlettaAttributes.MovementMultiplier) then
      begin
        Position.X:=AttackStart.X; Position.Z:=AttackStart.Z; Position.Y:=AttackStart.Y;
      end;
      ChargeNote:='';
      if IsAttackSkill and (AttackSkillID=B1008BodyBlowID) and
        FBodyBlowCharge.Allows(AttackStart.TargetID,AttackStart.X,AttackStart.Z,AttackStart.Y,HitTick,ChargeNote) then begin
        Position.X:=AttackStart.X;Position.Z:=AttackStart.Z;Position.Y:=AttackStart.Y;
      end;
      if not Spider^.Encounter.TryHit(AttackStart,Spider^.Handle,
        Position.X,Position.Z,Position.Y,Spider^.AI.X,Spider^.AI.Z,Spider^.AI.Y,
        PlayerHitRange(SpiderIndex,AttackStart.ActionKind,AttackStart.ActionID),
        HitTick,StateNote,False) then begin
        if ChargeNote<>'' then StateNote:=StateNote+' | charge '+ChargeNote;
        Exit(RejectPreparedAttack(Format('ATTACK PROBE SKIPPED | timestamp=%u action=%u | %s',
          [AttackStart.Timestamp,AttackStart.ActionID,StateNote])));
      end;
      if FHasPendingAttack and (FPendingAttack.ActionKind=1) and
        (HitTick<=FSkillImpactUntilTick) then Exit('ATTACK SKIPPED | skill impact already pending');
      if IsAttackSkill then begin
        if (TB1008FlettaProc.YinSupported(AttackSkillID)) and
          not FFlettaProc.Start(AttackStart.TargetID,AttackStart.Timestamp,HitTick) then
          Exit(RejectPreparedAttack('FLETTA START REJECTED | no matching server proc'));
        HasWeapon:=SkillWeaponAllowed(AttackSkillID);
        if not HasWeapon or not FSkillCast.Start(AttackStart.Timestamp,AttackStart.TargetID,HitTick,FPlayerMP,AttackSkillID) then
          Exit(RejectPreparedAttack('SKILL START REJECTED | missing/expired preparation, weapon, mana or cooldown'));
        FSkillImpactUntilTick:=HitTick+B1008SkillHandshakeMS;
        FSkillEndUntilTick:=HitTick+5000;FSkillEndTarget:=AttackStart.TargetID;
        FSkillEndSkillID:=AttackSkillID;
      end else begin FSkillCast.Cancel;FSkillEndTarget:=0;end;
      // The accepted 05/00 contains the actor's current point and has already
      // passed the tolerance check above. Keep chase targeting fresher than the
      // last movement report without treating it as a disk checkpoint.
      FWorldState.Position.X:=AttackStart.X;
      FWorldState.Position.Z:=AttackStart.Z;
      FWorldState.Position.Y:=AttackStart.Y;
      FWorldState.Moving:=False;
      FMovementAdmission.Reset;
      FirstEngagement:=False;
      for I:=0 to High(FSpiders) do
        if (FSpiders[I].Encounter.HP>0) and FSpiders[I].AI.Engaged and
          not FSpiders[I].AI.ReturningHome then FirstEngagement:=True;
      if not FirstEngagement then
        FCombatFormationHeading:=ArcTan2(Spider^.AI.Z-FWorldState.Position.Z,
          Spider^.AI.X-FWorldState.Position.X);
      FirstEngagement:=Spider^.AI.Engage(HitTick,SpiderStop);
      FPendingAttack:=AttackStart;
      FPendingSpiderHandle:=Spider^.Handle;
      FHasPendingAttack:=True;
      FPlayerAutoAttacking:=True;
      FRegeneration.EnterCombat;
      // The owner also needs the authoritative 05/00: without it the client
      // turns toward the target but never enters the attack animation.
      if FirstEngagement then
      begin
        SetLength(AReplies,2);
        AReplies[0]:=TB1008World.BuildActorMovement(
          HitTick and $FFFFFFFF,1,SpiderStop.Mode,Spider^.Handle,
          SpiderStop.FromX,SpiderStop.FromZ,SpiderStop.FromY,
          SpiderStop.ToX,SpiderStop.ToZ,SpiderStop.ToY,SpiderStop.Heading);
        I:=1;
      end
      else
      begin
        SetLength(AReplies,1);
        I:=0;
      end;
      AReplies[I]:=TB1008CombatWire.BuildSpiderStartAccepted(AttackStart,
        FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y);
      if IsAttackSkill then begin
        SetLength(AReplies,Length(AReplies)+1);AReplies[High(AReplies)]:=PlayerGage(AttackStart.Timestamp,False);
        if TB1008FlettaProc.YinSupported(AttackSkillID) then begin
          // Live b1008: action 1/0 has no animation impact callback. Resolve
          // the admitted proc immediately, then invoke the normal finish path.
          AttackDecide:=Default(TB1008AttackDecide);AttackDecide.Timestamp:=AttackStart.Timestamp;
          AttackDecide.ActorID:=1;AttackDecide.ActionKind:=1;AttackDecide.ActionID:=AttackSkillID;
          AttackDecide.X:=AttackStart.X;AttackDecide.Z:=AttackStart.Z;AttackDecide.Y:=AttackStart.Y;
          AttackDecide.Heading:=AttackStart.Heading;AttackDecide.TargetCount:=1;
          AttackDecide.TargetKind:=1;AttackDecide.TargetID:=AttackStart.TargetID;
          StateNote:=ResolveTargetImpact(AttackDecide,ProcReplies);
          Offset:=Length(AReplies);SetLength(AReplies,Offset+Length(ProcReplies)+2);
          AReplies[Offset]:=TB1008FlettaProc.BuildVisual(AttackStart.Timestamp,True,AttackSkillID);
          FTornadoVisualUntilTick:=HitTick+B1008TornadoVisualMS;
          FTornadoVisualSkillID:=AttackSkillID;
          if AttackSkillID=B1008RockStraightID then FTornadoVisualUntilTick:=HitTick+1300;
          for I:=0 to High(ProcReplies) do AReplies[Offset+1+I]:=ProcReplies[I];
          ImpactAttack:=AttackStart;ImpactAttack.ActionKind:=5;
          AReplies[High(AReplies)]:=TB1008CombatWire.BuildSpiderStartAccepted(ImpactAttack,
            FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y);
          FFlettaProc.Clear;FSkillCast.Cancel;FSkillEndTarget:=0;FHasPendingAttack:=False;
          FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;
          Exit('FLETTA INSTANT RESOLVED | '+StateNote+'; native finish sent');
        end;
        SkillParameters:=TB1008AttackSkillStats.Get(AttackSkillID,FSkillCast.ActiveRank);
        Exit(Format('SKILL START ACCEPTED | skill=%u rank=%u action=1/%u target=%u MP=%d cost=%d cooldown=%ums; waiting impact',
          [AttackSkillID,FSkillCast.ActiveRank,AttackStart.ActionID,Spider^.Handle,FPlayerMP,
           SkillParameters.MPCost,SkillParameters.CooldownMS]));
      end;
      Exit(Format('ATTACK START ACCEPTED | timestamp=%u action=%u target=%d | animation armed; damage waits for matching 05/01 impact',
        [AttackStart.Timestamp,AttackStart.ActionID,Spider^.Handle]));
    end;
    Exit(RejectPreparedAttack(Format('ATTACK START OBSERVED | actor=%d/%d action=%d/%d target=%d/%d from=(%.3f,%.3f,%.3f) heading=%.3f targetPos=(%.3f,%.3f,%.3f) parameter=%.3f | no damage or quest progress',
      [AttackStart.ActorKind,AttackStart.ActorID,AttackStart.ActionKind,AttackStart.ActionID,
       AttackStart.TargetKind,AttackStart.TargetID,AttackStart.X,AttackStart.Z,AttackStart.Y,
       AttackStart.Heading,AttackStart.TargetX,AttackStart.TargetZ,AttackStart.TargetY,
       AttackStart.TargetParameter],TFormatSettings.Invariant)));
  end;
  if (APayload[0]=3) and (APayload[1]=2) then
  begin
    ActionFlags:=TB1008CombatWire.ParseFlags(APayload);
    if (FLoginMode<>blMapLoadingProbe) or (FStage<>ssAppearanceProbe) or
      not FWorldState.Active then Exit('ACTION FLAGS SKIPPED | no admitted world session');
    if ActionFlags.CharacterID<>FWorldState.CharacterID then
      Exit('ACTION FLAGS SKIPPED | unsupported character ID');
    FRegeneration.ObserveState(ActionFlags.Timestamp,ActionFlags.FlagA);
    if ActionFlags.FlagA=0 then FPlayerAutoAttacking:=False;
    FClientInWorld:=True;
    Exit(Format('ACTION FLAGS OBSERVED | character=%d flags=%d/%d | no reply',
      [ActionFlags.CharacterID,ActionFlags.FlagA,ActionFlags.FlagB]));
  end;
  if (APayload[0]=5) and (APayload[1]=1) then
  begin
    SyncSpiderContent;
    if FPlayerHP<=0 then begin
      FHasPendingAttack:=False;FPlayerAutoAttacking:=False;FSkillCast.Cancel;
      Exit('ATTACK DECIDE SKIPPED | player dead');
    end;
    if (FLoginMode<>blMapLoadingProbe) or (FStage<>ssAppearanceProbe) or
      not FWorldState.Active then Exit('ATTACK DECIDE SKIPPED | no admitted world session');
    if (Length(APayload)>=16) and TB1008ProfessionSkill.Supported(TB1008Wire.ReadBE32(APayload,12)) then
      Exit(HandleProfessionImpact(APayload,AReplies));
    if (Length(APayload)>=16) and ((TB1008Wire.ReadBE32(APayload,12)=B1008ProvocationID) or
      (TB1008Wire.ReadBE32(APayload,12)=B1008CoerciveID)) then begin
      AreaTargets:=TB1008CombatWire.ParseAreaDecide(APayload);AttackDecide:=AreaTargets[0];
      SelfSkillID:=AttackDecide.ActionID;
      if SelfSkillID=B1008CoerciveID then SelfSkillName:='COERCIVE' else SelfSkillName:='PROVOCATION';
      HitTick:=GetTickCount64;
      if (AttackDecide.ActorKind<>0) or (AttackDecide.ActorID<>1) or (AttackDecide.ActionKind<>1) or
        not FHasPendingAttack or (TB1008AttackSkillStats.SelfFromAction(FPendingAttack.ActionID)<>SelfSkillID) or
        (FSkillCast.ActiveSkillID<>SelfSkillID) or (HitTick>FSkillImpactUntilTick) or
        (((Int64(AttackDecide.Timestamp)-Int64(FPendingAttack.Timestamp)+$100000000) mod $100000000)>=$80000000) then
        Exit(SelfSkillName+' IMPACT REJECTED | no matching area cast');
      for AreaTarget in AreaTargets do if AreaTarget.TargetKind<>1 then
        Exit(SelfSkillName+' IMPACT REJECTED | non-NPC area target');
      SkillParameters:=TB1008AttackSkillStats.Get(SelfSkillID,FSkillCast.ActiveRank);
      FHasPendingAttack:=False;FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;
      FirstEngagement:=True;
      for I:=0 to High(FSpiders) do
        if (FSpiders[I].Encounter.HP>0) and FSpiders[I].AI.Engaged and
          not FSpiders[I].AI.ReturningHome then FirstEngagement:=False;
      AreaCount:=0;
      for AreaTarget in AreaTargets do begin
        SpiderIndex:=FindSpiderIndex(AreaTarget.TargetID);
        if SpiderIndex<0 then Continue;
        Spider:=@FSpiders[SpiderIndex];
        if Spider^.Encounter.HP<=0 then Continue;
        Spider^.AI.UpdatePosition(HitTick);
        // Client 4D04BC: a 3D sphere expanded by NPC radius, without the
        // melee weapon tolerance. Client coordinates never move the center.
        AreaRadius:=SkillParameters.Range+TB1008Berneo.Mob(Spider^.Spawn.MobID).ClientRadius;
        if Sqr(Double(Spider^.AI.X)-FWorldState.Position.X)+
          Sqr(Double(Spider^.AI.Z)-FWorldState.Position.Z)+
          Sqr(Double(Spider^.AI.Y)-FWorldState.Position.Y)>Sqr(AreaRadius) then Continue;
        if FirstEngagement then begin
          FCombatFormationHeading:=ArcTan2(Spider^.AI.Z-FWorldState.Position.Z,
            Spider^.AI.X-FWorldState.Position.X);FirstEngagement:=False;
        end;
        Inc(AreaCount);
        if SelfSkillID=B1008CoerciveID then begin
          Spider^.Coercive.Start(FSkillCast.ActiveRank,HitTick);
          SetLength(AReplies,Length(AReplies)+1);
          AReplies[High(AReplies)]:=TB1008SkillWire.BuildMobCoercive(AttackDecide.Timestamp,
            Spider^.Handle,Spider^.Coercive.Rank,True);
        end;
        if Spider^.AI.Engage(HitTick,SpiderStop) then begin
          SetLength(AReplies,Length(AReplies)+1);
          AReplies[High(AReplies)]:=TB1008World.BuildActorMovement(AttackDecide.Timestamp,1,
            SpiderStop.Mode,Spider^.Handle,SpiderStop.FromX,SpiderStop.FromZ,SpiderStop.FromY,
            SpiderStop.ToX,SpiderStop.ToZ,SpiderStop.ToY,SpiderStop.Heading);
        end;
      end;
      if AreaCount>0 then FRegeneration.EnterCombat;
      Exit(Format('%s APPLIED | rank=%u listed=%d affected=%d radius=%.0f; no direct damage or rewards',
        [SelfSkillName,FSkillCast.ActiveRank,Length(AreaTargets),AreaCount,SkillParameters.Range]));
    end;
    AttackDecide:=TB1008CombatWire.ParseDecide(APayload);
    if AttackDecide.ActionID=B1008FrenzyID then begin
      HitTick:=GetTickCount64;
      if (AttackDecide.ActorKind<>0) or (AttackDecide.ActorID<>1) or (AttackDecide.ActionKind<>1) or
        (AttackDecide.TargetKind<>0) or (AttackDecide.TargetID<>1) or (AttackDecide.TargetCount<>1) or
        not FHasPendingAttack or (FPendingAttack.ActionID<>B1008FrenzyActionID) or
        (FSkillCast.ActiveSkillID<>B1008FrenzyID) or (HitTick>FSkillImpactUntilTick) or
        (((Int64(AttackDecide.Timestamp)-Int64(FPendingAttack.Timestamp)+$100000000) mod $100000000)>=$80000000) then
        Exit(Format('FRENZY IMPACT REJECTED | actor=%d/%u kind=%d target=%d/%u count=%d pending=%d active=%u; no matching self cast',
          [AttackDecide.ActorKind,AttackDecide.ActorID,AttackDecide.ActionKind,
           AttackDecide.TargetKind,AttackDecide.TargetID,AttackDecide.TargetCount,Ord(FHasPendingAttack),FSkillCast.ActiveSkillID]));
      FHasPendingAttack:=False;FPendingSpiderHandle:=0;
      FFrenzy.Start(FSkillCast.ActiveRank,HitTick);
      SetLength(AReplies,2);AReplies[0]:=TB1008SkillWire.BuildFrenzy(AttackDecide.Timestamp,FFrenzy.Rank,True);
      AReplies[1]:=TB1008ProgressWire.BuildParameters(AttackDecide.Timestamp,FPlayerClassID,FProgress.Level);
      ApplyPlayerParameters(AReplies[1]);
      Exit(Format('FRENZY APPLIED | rank=%u duration=15000ms attack=+%d defense=-%d',
        [FFrenzy.Rank,TB1008FrenzyRank.Get(FFrenzy.Rank).AttackBonus,TB1008FrenzyRank.Get(FFrenzy.Rank).DefensePenalty]));
    end;
    Exit(ResolveTargetImpact(AttackDecide,AReplies));
  end;
  if (APayload[0]=8) and (APayload[1]=4) then begin
    FlettaRequest:=TB1008FlettaInvestment.Parse(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active or
      (FPlayerHP<=0) then Exit('FLETTA SKIPPED | no living admitted character');
    // Do not echo untrusted axis indexes: the client indexes fixed-size arrays.
    if not FlettaRequest.Supported then
      Exit(Format('FLETTA UNSUPPORTED | character=%u category=%u attribute=%u amount=%u code=%d; no spend',
        [FlettaRequest.CharacterID,FlettaRequest.Category,FlettaRequest.Attribute,FlettaRequest.Amount,FlettaRequest.Code]));
    StateNote:=FInventorySessionID+'/fletta/'+UIntToStr(FlettaRequest.Timestamp);
    FlettaResult:=FLoot.InvestFletta(Self,StateNote,FlettaRequest,NewFletta,NewFlettaAttributes);
    FFletta:=NewFletta;FFlettaAttributes:=NewFlettaAttributes;
    if FlettaResult in [firInsufficient,firRejected] then begin
      SetLength(AReplies,1);AReplies[0]:=FlettaRequest.Ack(False);
    end else if FlettaResult=firApplied then begin
      SetLength(AReplies,3);
      AReplies[0]:=FlettaRequest.Ack(True);
      AReplies[1]:=PlayerGage(FlettaRequest.Timestamp,True);
      AReplies[2]:=TB1008ProgressWire.BuildParameters(FlettaRequest.Timestamp,FPlayerClassID,FProgress.Level);
      ApplyPlayerParameters(AReplies[2]);
      if TB1008FlettaProc.Enabled(TB1008FlettaProc.CombinedSkill(FFlettaAttributes)) then begin
        SetLength(AReplies,4);AReplies[3]:=PlayerSkillList(FlettaRequest.Timestamp);
      end;
    end;
    Exit(Format('FLETTA INVEST | result=%d category=%u attribute=%u amount=%u axis1=%u/%d axis2=%u/%d free=%d progress=%d; committed before delta',
      [Ord(FlettaResult),FlettaRequest.Category,FlettaRequest.Attribute,FlettaRequest.Amount,
       FFlettaAttributes.Selection(1),FFlettaAttributes.Invested(1),
       FFlettaAttributes.Selection(2),FFlettaAttributes.Invested(2),FFletta.Points,FFletta.Progress]));
  end;
  if (APayload[0]=6) and (APayload[1] in [$0B,$0C]) then begin
    QuickRequest:=TB1008QuickSlotRequest.Parse(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active then
      Exit('QUICKSLOT SKIPPED | no admitted owner');
    if not FLoot.SetQuickSlot(Self,QuickRequest) then
      Exit(Format('QUICKSLOT UNSUPPORTED | slot=%u reference=%u source=%d/%d; not saved',
        [QuickRequest.Entry.Slot,QuickRequest.Entry.ReferenceID,QuickRequest.Entry.SourcePage,QuickRequest.Entry.SourceSlot]));
    // UI already applies the edit locally. Restore the saved references on login.
    Exit(Format('QUICKSLOT SAVED | remove=%d slot=%u reference=%u source=%d/%d',
      [Ord(QuickRequest.Remove),QuickRequest.Entry.Slot,QuickRequest.Entry.ReferenceID,
       QuickRequest.Entry.SourcePage,QuickRequest.Entry.SourceSlot]));
  end;
  if (APayload[0]=6) and (APayload[1] in [0,1]) then begin
    GearRequest:=TB1008Equipment.ParseRequest(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active or
      (FPlayerHP<=0) then Exit('EQUIPMENT SKIPPED | no living admitted inventory');
    if FHasPendingAttack or FPlayerAutoAttacking then
      Exit('EQUIPMENT SKIPPED | player attacking');
    // User rule: taking hits alone must not lock equipment. The next incoming
    // impact reads the newly committed armor; the mob's attack is not cancelled.
    StateNote:=FInventorySessionID+Format(':gear:%d:%u:%d:%d:%u',
      [Ord(GearRequest.Wear),GearRequest.Timestamp,GearRequest.Page,GearRequest.Slot,GearRequest.ItemID]);
    if not FLoot.TransferEquipment(Self,StateNote,FPlayerClassID,GearRequest,BagItem) then
      Exit(Format('EQUIPMENT SKIPPED | wear=%d page=%d cell=%d equip=%d item=%u code=%d; stale/full/unsupported',
        [Ord(GearRequest.Wear),GearRequest.Page,GearRequest.Slot,GearRequest.EquipSlot,GearRequest.ItemID,GearRequest.Code]));
    FEquipment:=FLoot.Equipment(Self);FMinePending:=False;
    GearItem:=Default(TB1008EquipmentItem);GearItem.ItemID:=GearRequest.ItemID;
    GearItem.Slot:=TB1008Equipment.ItemSlot(GearRequest.ItemID,FPlayerClassID);
    if GearRequest.Wear then begin
      for ReplacedGearItem in FEquipment do if ReplacedGearItem.Slot=GearItem.Slot then begin GearItem:=ReplacedGearItem;Break;end;
    end else GearItem.Properties:=BagItem.Properties;
    GearRequest.EquipSlot:=GearItem.Slot;SetLength(AReplies,4);
    if GearRequest.Wear then begin
      AReplies[0]:=TB1008InventoryWire.BuildPutOut(GearRequest.Timestamp,1,GearRequest.ItemID,BagItem.Slot);
      Offset:=1;
      if BagItem.Amount<>0 then begin
        // Client 5054A9 keeps the old itemBase pointer in an occupied cell.
        // 06/06 removal -> 50F57D/505754 clears it before installing the new ID.
        SetLength(AReplies,6);ReplacedGearItem:=GearItem;ReplacedGearItem.ItemID:=BagItem.ItemID;
        ReplacedGearItem.Properties:=BagItem.Properties;
        AReplies[1]:=TB1008Equipment.BuildSlotUpdate(GearRequest.Timestamp,ReplacedGearItem,False);
        Offset:=2;
        // Wear ACK (525D3C) updates appearance only; restore the bag separately.
        AReplies[4]:=TB1008InventoryWire.BuildPutIn(GearRequest.Timestamp,1,BagItem);
      end;
      AReplies[Offset]:=TB1008Equipment.BuildSlotUpdate(GearRequest.Timestamp,GearItem,True);
      AReplies[Offset+1]:=TB1008Equipment.BuildWear(GearRequest);
    end else begin
      AReplies[0]:=TB1008Equipment.BuildSlotUpdate(GearRequest.Timestamp,GearItem,False);
      AReplies[1]:=TB1008InventoryWire.BuildPutIn(GearRequest.Timestamp,1,BagItem);
      AReplies[2]:=TB1008Equipment.BuildWear(GearRequest);
    end;
    AReplies[High(AReplies)]:=TB1008ProgressWire.BuildParameters(GearRequest.Timestamp,FPlayerClassID,FProgress.Level);
    ApplyPlayerParameters(AReplies[High(AReplies)]);FParameterLevel:=FProgress.Level;
    if GearItem.Slot=7 then begin
      SetLength(AReplies,Length(AReplies)+1);
      AReplies[High(AReplies)]:=PlayerGage(GearRequest.Timestamp,False);
    end;
    Exit(Format('EQUIPMENT COMMITTED | wear=%d item=%u equip=%d bag=%d; defense bonus=%d',
      [Ord(GearRequest.Wear),GearRequest.ItemID,GearItem.Slot,BagItem.Slot,TB1008Equipment.Defense(FEquipment)]));
  end;
  if (APayload[0]=6) and (APayload[1]=$0A) then begin
    ItemSplit:=TB1008InventoryWire.ParseSplit(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active or
      (FPlayerHP<=0) then Exit('SPLIT SKIPPED | no living admitted inventory');
    if (ItemSplit.CharacterID<>1) or (ItemSplit.Page<>1) or (ItemSplit.Code<>$38) then
      Exit('SPLIT SKIPPED | unsupported character/page/code');
    StateNote:=FInventorySessionID+Format(':split:%u:%d:%u:%s:%d',
      [ItemSplit.Timestamp,ItemSplit.Slot,ItemSplit.ItemID,UIntToStr(ItemSplit.SourceCount),ItemSplit.Amount]);
    SetLength(AReplies,1);
    AReplies[0]:=TB1008InventoryWire.BuildSplitAck(ItemSplit.Timestamp,1,False);
    try
      if not FLoot.SplitItem(Self,StateNote,ItemSplit.Slot,ItemSplit.ItemID,
        ItemSplit.SourceCount,ItemSplit.Amount,SplitSource,SplitCreated) then
        Exit(Format('SPLIT REJECTED | cell=%d item=%u source=%s amount=%d; stale/full/unsupported/duplicate',
          [ItemSplit.Slot,ItemSplit.ItemID,UIntToStr(ItemSplit.SourceCount),ItemSplit.Amount]));
    except on E:Exception do Exit('SPLIT NOT COMMITTED | inventory retained; '+E.Message);end;
    SetLength(AReplies,3);
    AReplies[0]:=TB1008InventoryWire.BuildPutIn(ItemSplit.Timestamp,1,
      SplitSource.ItemID,SplitSource.Amount,SplitSource.Slot);
    AReplies[1]:=TB1008InventoryWire.BuildPutIn(ItemSplit.Timestamp,1,
      SplitCreated.ItemID,SplitCreated.Amount,SplitCreated.Slot);
    AReplies[2]:=TB1008InventoryWire.BuildSplitAck(ItemSplit.Timestamp,1,True);
    Exit(Format('INVENTORY SPLIT | item=%u sourceCell=%d remaining=%u newCell=%d amount=%u; total unchanged',
      [SplitSource.ItemID,SplitSource.Slot,SplitSource.Amount,SplitCreated.Slot,SplitCreated.Amount]));
  end;
  if (APayload[0]=6) and (APayload[1]=8) then begin
    ItemSwap:=TB1008InventoryWire.ParseSwap(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active then
      Exit('SWAP SKIPPED | no admitted inventory');
    if (ItemSwap.CharacterID<>1) or (ItemSwap.SourcePage<>1) or (ItemSwap.TargetPage<>1) then
      Exit('SWAP SKIPPED | unsupported character/page');
    if (ItemSwap.SourceID<>0) and (ItemSwap.SourceID=ItemSwap.TargetID) then begin
      StateNote:=FInventorySessionID+Format(':merge:%u:%d:%d:%u',
        [ItemSwap.Timestamp,ItemSwap.SourceSlot,ItemSwap.TargetSlot,ItemSwap.SourceID]);
      try
        if not FLoot.MergeItems(Self,StateNote,ItemSwap.SourceSlot,ItemSwap.TargetSlot,
          ItemSwap.SourceID,SplitSource,SplitCreated) then
          Exit('MERGE SKIPPED | stale/full/unsupported/duplicate; no item change');
      except on E:Exception do Exit('MERGE NOT COMMITTED | inventory retained; '+E.Message);end;
      SetLength(AReplies,2);
      if SplitSource.Amount=0 then
        AReplies[0]:=TB1008InventoryWire.BuildPutOut(ItemSwap.Timestamp,1,SplitSource.ItemID,SplitSource.Slot)
      else AReplies[0]:=TB1008InventoryWire.BuildPutIn(ItemSwap.Timestamp,1,
        SplitSource.ItemID,SplitSource.Amount,SplitSource.Slot);
      AReplies[1]:=TB1008InventoryWire.BuildPutIn(ItemSwap.Timestamp,1,
        SplitCreated.ItemID,SplitCreated.Amount,SplitCreated.Slot);
      // 06/08 echoes would swap the cells again, so emit authoritative cell
      // updates only. Unlike Shift split, ordinary dragging has no count field.
      Exit(Format('INVENTORY MERGED | item=%u sourceCell=%d remaining=%u targetCell=%d amount=%u; total unchanged',
        [SplitSource.ItemID,SplitSource.Slot,SplitSource.Amount,SplitCreated.Slot,SplitCreated.Amount]));
    end;
    if not FLoot.Swap(Self,ItemSwap.SourceSlot,ItemSwap.TargetSlot,ItemSwap.SourceID,ItemSwap.TargetID) then
      Exit(Format('SWAP SKIPPED | stale or invalid slots %d/%d items %u/%u',
        [ItemSwap.SourceSlot,ItemSwap.TargetSlot,ItemSwap.SourceID,ItemSwap.TargetID]));
    SetLength(AReplies,1); AReplies[0]:=Copy(APayload);
    Exit('INVENTORY SWAPPED | committed before acknowledgement');
  end;
  if (APayload[0]=6) and (APayload[1]=7) then begin
    ItemThrow:=TB1008InventoryWire.ParseThrow(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active then
      Exit('THROW SKIPPED | no admitted inventory');
    if (ItemThrow.CharacterID<>1) or (ItemThrow.Page<>1) then
      Exit('THROW SKIPPED | unsupported character/page');
    DestroyThrownItem:=TB1008Items.IsQuestItem(ItemThrow.ItemID);
    DropIndex:=0;
    while (DropIndex<Length(FDrops)) and not FDrops[DropIndex].Collected do Inc(DropIndex);
    if not DestroyThrownItem and ((DropIndex=B1008LootGroundLimit) or (FNextDropID=High(Cardinal))) then
      Exit('THROW SKIPPED | ground capacity; item retained');
    GroundDrop:=Default(TB1008GroundDrop);GroundDrop.OwnerID:=1;
    if not DestroyThrownItem then GroundDrop.ID:=FNextDropID+1;
    GroundDrop.X:=FWorldState.Position.X; GroundDrop.Z:=FWorldState.Position.Z; GroundDrop.Y:=FWorldState.Position.Y;
    CreateGUID(G); GroundDrop.Receipt:=GUIDToString(G);
    StateNote:=FInventorySessionID+Format(':throw:%u:%d:%u:%d',
      [ItemThrow.Timestamp,ItemThrow.Slot,ItemThrow.ItemID,ItemThrow.Amount]);
    if not FLoot.ThrowItem(Self,StateNote,ItemThrow.Slot,ItemThrow.ItemID,
      ItemThrow.Amount,GroundDrop,LootCount) then Exit('THROW SKIPPED | stale, duplicate or invalid count');
    if DestroyThrownItem then begin
      SetLength(AReplies,1+Ord(LootCount>0));
      AReplies[0]:=TB1008InventoryWire.BuildPutOut(ItemThrow.Timestamp,1,ItemThrow.ItemID,ItemThrow.Slot);
      if LootCount>0 then AReplies[1]:=TB1008InventoryWire.BuildPutIn(ItemThrow.Timestamp,1,
        ItemThrow.ItemID,LootCount,ItemThrow.Slot);
      Exit(Format('QUEST ITEM DESTROYED | item=%u amount=%u remaining=%u | no ground item',
        [ItemThrow.ItemID,GroundDrop.Amount,LootCount]));
    end;
    Inc(FNextDropID);
    GroundDrop.Sent:=True; GroundDrop.ExpiresTick:=GetTickCount64+B1008ThrownLootLifetimeMS;
    if DropIndex=Length(FDrops) then SetLength(FDrops,DropIndex+1);
    FDrops[DropIndex]:=GroundDrop;
    SetLength(AReplies,2+Ord(LootCount>0));
    AReplies[0]:=TB1008InventoryWire.BuildPutOut(ItemThrow.Timestamp,1,ItemThrow.ItemID,ItemThrow.Slot);
    if LootCount>0 then AReplies[1]:=TB1008InventoryWire.BuildPutIn(ItemThrow.Timestamp,1,
      ItemThrow.ItemID,LootCount,ItemThrow.Slot);
    AReplies[High(AReplies)]:=TB1008LootWire.BuildDrop(ItemThrow.Timestamp,GroundDrop);
    Exit(Format('ITEM THROWN | item=%u amount=%u remaining=%u | durable ground',
      [ItemThrow.ItemID,GroundDrop.Amount,LootCount]));
  end;
  if (APayload[0]=$06) and (APayload[1]=$03) then
  begin
    Pickup:=TB1008LootWire.ParsePickup(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or
      not FWorldState.Active then Exit('PICKUP SKIPPED | no admitted loot session');
    if (Pickup.CharacterID<>FWorldState.CharacterID) or (Pickup.Code<>$33) then
      Exit('PICKUP SKIPPED | wrong character or unsupported code');
    DropIndex:=-1;
    for I:=0 to High(FDrops) do
      if FDrops[I].ID=Pickup.DropID then begin DropIndex:=I; Break; end;
    if DropIndex<0 then Exit('PICKUP SKIPPED | unknown drop');
    if FDrops[DropIndex].Collected then Exit('PICKUP duplicate ignored | no duplicate grant');
    if GetTickCount64>=FDrops[DropIndex].ExpiresTick then begin
      FLoot.RemoveGround(Self,FDrops[DropIndex].Receipt); FDrops[DropIndex].Collected:=True;
      if FDrops[DropIndex].Sent then begin
        SetLength(AReplies,1); AReplies[0]:=TB1008LootWire.BuildRemove(Pickup.Timestamp,FDrops[DropIndex]);
      end;
      Exit('PICKUP EXPIRED | no grant');
    end;
    if (FDrops[DropIndex].OwnerID<>Pickup.CharacterID) or
      (FDrops[DropIndex].ItemID<>Pickup.ItemID) then
      Exit('PICKUP SKIPPED | wrong owner or item');
    PickupDX:=Double(FWorldState.Position.X)-FDrops[DropIndex].X;
    PickupDZ:=Double(FWorldState.Position.Z)-FDrops[DropIndex].Z;
    // The client projects drops onto terrain (0x51B690); generated-spawn Y
    // is only estimated server-side. Validate ground range as for melee.
    if (Sqr(PickupDX)+Sqr(PickupDZ)>Sqr(B1008PickupRange)) and
      not FMovementAdmission.AllowsPickup(FDrops[DropIndex].X,FDrops[DropIndex].Z,
        B1008PickupRange,Max(B1008PlayerSpeedA,B1008PlayerSpeedB)*
          FFlettaAttributes.MovementMultiplier,GetTickCount64) then begin
      // A silent denial leaves b1008's object in its pending-pickup state.
      // Recreate that same object via known remove/appear packets; retain its
      // receipt, amount and original expiry, and grant no inventory item.
      SetLength(AReplies,2);
      AReplies[0]:=TB1008LootWire.BuildRemove(Pickup.Timestamp,FDrops[DropIndex]);
      AReplies[1]:=TB1008LootWire.BuildDrop(Pickup.Timestamp,FDrops[DropIndex]);
      Exit(Format('PICKUP RETRY | drop=%u item=%u distance=%.2f; no grant, expiry retained',
        [Pickup.DropID,Pickup.ItemID,Sqrt(Sqr(PickupDX)+Sqr(PickupDZ))]));
    end;
    // Construct replies before committing; do not remove a drop on a failed write.
    Reply:=TB1008LootWire.BuildPickup(Pickup);
    try
      if not FLoot.CollectItem(Self,FDrops[DropIndex].Receipt,Pickup.ItemID,
        FDrops[DropIndex].Amount,LootCount,PickupUpdates) then
      begin
        Pickup.Code:=$0B; // Client 0x52633C: inventory-full response.
        SetLength(AReplies,1); AReplies[0]:=TB1008LootWire.BuildPickup(Pickup);
        Exit('PICKUP FULL | no stack capacity/free cell or currency cap; drop retained');
      end;
    except
      on E: Exception do Exit('PICKUP NOT COMMITTED | drop retained; '+E.Message);
    end;
    FDrops[DropIndex].Collected:=True;
    SetLength(AReplies,Length(PickupUpdates)+1);
    StateNote:='';
    for I:=0 to High(PickupUpdates) do begin
      AReplies[I]:=TB1008InventoryWire.BuildPutIn(Pickup.Timestamp,Pickup.CharacterID,
        PickupUpdates[I]);
      StateNote:=StateNote+Format(' slot=%d count=%u',
        [PickupUpdates[I].Slot,PickupUpdates[I].Amount]);
    end;
    AReplies[High(AReplies)]:=Reply;
    Exit(Format('LOOT PICKED UP | drop=%u item=%u total=%u updatedCells=%d%s | durable before replies',
      [Pickup.DropID,Pickup.ItemID,LootCount,Length(PickupUpdates),StateNote]));
  end;
  if (APayload[0]=6) and (APayload[1] in [$1A,$1B,$1C,$28,$2A]) then
    Exit(HandleStash(APayload,AReplies));
  if (APayload[0]=6) and (APayload[1]=$23) then Exit(HandleReturn(APayload,AReplies));
  if (APayload[0]=8) and (APayload[1]=3) then Exit(HandleClassChange(APayload,AReplies));
  if (APayload[0]=$06) and (APayload[1]=$02) then
  begin
    ItemUse:=TB1008InventoryWire.ParseUse(APayload);
    if ItemUse.ItemID=B1008ReturningStoneID then Exit(HandleReturn(APayload,AReplies));
    if (FLoginMode<>blMapLoadingProbe) or (FStage<>ssAppearanceProbe) or
      not FWorldState.Active then Exit('ITEM USE SKIPPED | no admitted world session');
    if ItemUse.CharacterID<>FWorldState.CharacterID then
      Exit('ITEM USE SKIPPED | unsupported character ID');
    if (ItemUse.Page<>1) or (ItemUse.Slot>=B1008BagSlots) or
      not TB1008Items.IsPotion(ItemUse.ItemID) or
      (ItemUse.Parameter<>0) or (ItemUse.Code<>1) then
      Exit('ITEM USE SKIPPED | unsupported page, slot, item or parameters');
    if FPlayerHP<=0 then Exit('ITEM USE SKIPPED | potion cannot revive');
    DropIndex:=TB1008PotionEffect.Kind(ItemUse.ItemID);
    if FHasPotionUse[DropIndex] and
      (((Int64(ItemUse.Timestamp)-Int64(FLastPotionTimestamp[DropIndex])+$100000000) mod $100000000=0) or
       ((Int64(ItemUse.Timestamp)-Int64(FLastPotionTimestamp[DropIndex])+$100000000) mod $100000000>=$80000000)) then
      Exit('ITEM USE duplicate/stale ignored | no extra consumption or healing');
    if GetTickCount64<FPotionUntil[DropIndex] then Exit('ITEM USE SKIPPED | potion cooldown');
    if Assigned(FLoot) then begin
      if not FLoot.Consume(Self,ItemUse.Slot,ItemUse.ItemID,LootCount) then
        Exit('ITEM USE SKIPPED | cooldown, empty or wrong slot');
      I:=LootCount;
    end else begin
      if not Assigned(FQuests) then Exit('ITEM USE SKIPPED | no persistent inventory');
      if not (((ItemUse.Slot=0) and (ItemUse.ItemID=B1008BeginnerHealingPotionID)) or
        ((ItemUse.Slot=1) and (ItemUse.ItemID=B1008BeginnerManaPotionID))) then
        Exit('ITEM USE SKIPPED | wrong legacy slot');
      I:=FQuests.RewardItemCount(Self,ItemUse.ItemID);
      if I=0 then Exit('ITEM USE SKIPPED | reward-item stack empty');
      I:=FQuests.ConsumeRewardItem(Self,ItemUse.ItemID);
    end;
    TB1008PotionEffect.Apply(ItemUse.ItemID,FPlayerHP,FPlayerMP,PlayerMaxHP,PlayerMaxMP);
    FHasPotionUse[DropIndex]:=True;FLastPotionTimestamp[DropIndex]:=ItemUse.Timestamp;
    FPotionUntil[DropIndex]:=GetTickCount64+UInt64(TB1008PotionEffect.CooldownMS(ItemUse.ItemID));
    SetLength(AReplies,3);
    AReplies[0]:=TB1008InventoryWire.BuildUseAck(ItemUse);
    if I>0 then
      AReplies[1]:=TB1008InventoryWire.BuildPutIn(ItemUse.Timestamp,
        ItemUse.CharacterID,ItemUse.ItemID,I,ItemUse.Slot)
    else
      AReplies[1]:=TB1008InventoryWire.BuildPutOut(ItemUse.Timestamp,
        ItemUse.CharacterID,ItemUse.ItemID,ItemUse.Slot);
    AReplies[2]:=PlayerGage(ItemUse.Timestamp,True);
    Exit(Format('ITEM USED | character=%d page=%d slot=%d item=%d code=%d | durable remaining=%d before 06/02 ack and inventory update',
      [ItemUse.CharacterID,ItemUse.Page,ItemUse.Slot,ItemUse.ItemID,ItemUse.Code,I]));
  end;
  if (APayload[0]=5) and (APayload[1]=6) then begin
    SkillLearn:=TB1008SkillLearn.Parse(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active or
      (FPlayerHP<=0) then Exit('SKILL LEARN SKIPPED | no living admitted character');
    if SkillLearn.IsStarterRequest(FPlayerClassID) then begin
      SetLength(AReplies,2);
      AReplies[0]:=PlayerSkillList(SkillLearn.Timestamp);
      AReplies[1]:=PlayerGage(SkillLearn.Timestamp,True);
      Exit('SKILL STARTER ALREADY KNOWN | no SP spent; authoritative list restored');
    end;
    if not SkillLearn.Supported then
      Exit(Format('SKILL LEARN UNSUPPORTED | character=%u skill=%u code=%u; no SP spent',
        [SkillLearn.CharacterID,SkillLearn.SkillID,SkillLearn.Code]));
    SkillLearnResult:=slrRejected;
    if (FPlayerClassID=100) and not FHasPendingAttack then begin
      StateNote:=FInventorySessionID+'/learn/'+UIntToStr(SkillLearn.Timestamp);
      try SkillLearnResult:=FLoot.LearnSkill(Self,StateNote,SkillLearn);
      except on E:Exception do Exit('SKILL LEARN NOT COMMITTED | '+E.Message);end;
    end;
    SetLength(AReplies,2);
    if SkillLearnResult=slrApplied then AReplies[0]:=SkillLearn.Ack
    else AReplies[0]:=PlayerSkillList(SkillLearn.Timestamp);
    AReplies[1]:=PlayerGage(SkillLearn.Timestamp,True);
    if (SkillLearnResult=slrApplied) and ((SkillLearn.SkillID=B1008StrengthMasteryID) or
      (SkillLearn.SkillID=B1008SwordMasteryID) or (SkillLearn.SkillID=B1008PolearmMasteryID)) then begin
      SetLength(AReplies,3);AReplies[2]:=TB1008ProgressWire.BuildParameters(SkillLearn.Timestamp,FPlayerClassID,FProgress.Level);
      ApplyPlayerParameters(AReplies[2]);
    end;
    Exit(Format('SKILL LEARN | result=%d skill=%u freeSP=%u; committed before reply',
      [Ord(SkillLearnResult),SkillLearn.SkillID,FLoot.SkillPoints(Self)]));
  end;
  if (APayload[0]=5) and (APayload[1]=7) then begin
    SkillUpgrade:=TB1008SkillUpgrade.Parse(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active or
      (FPlayerHP<=0) then Exit('SKILL UPGRADE SKIPPED | no living admitted character');
    if not SkillUpgrade.Supported then
      Exit(Format('SKILL UPGRADE UNSUPPORTED | actor=%u skill=%u currentRank=%u code=%d',
        [SkillUpgrade.CharacterID,SkillUpgrade.SkillID,SkillUpgrade.CurrentRank,SkillUpgrade.Code]));
    SkillUpgradeResult:=surRejected;SkillRank:=0;
    if (FPlayerClassID=100) and not FHasPendingAttack then begin
      StateNote:=FInventorySessionID+'/upgrade/'+UIntToStr(SkillUpgrade.Timestamp);
      try SkillUpgradeResult:=FLoot.UpgradeSkill(Self,StateNote,SkillUpgrade,SkillRank);
      except on E:Exception do Exit('SKILL UPGRADE NOT COMMITTED | '+E.Message);end;
    end;
    SetLength(AReplies,2);
    // Success carries the resulting rank. Duplicate success would spend SP
    // again locally, so replay/rejection gets an absolute list and gage.
    if SkillUpgradeResult=surApplied then AReplies[0]:=SkillUpgrade.Ack(SkillRank)
    else AReplies[0]:=PlayerSkillList(SkillUpgrade.Timestamp);
    AReplies[1]:=PlayerGage(SkillUpgrade.Timestamp,True);
    if (SkillUpgradeResult=surApplied) and ((SkillUpgrade.SkillID=B1008StrengthMasteryID) or
      (SkillUpgrade.SkillID=B1008SwordMasteryID) or (SkillUpgrade.SkillID=B1008PolearmMasteryID)) then begin
      SetLength(AReplies,3);AReplies[2]:=TB1008ProgressWire.BuildParameters(SkillUpgrade.Timestamp,FPlayerClassID,FProgress.Level);
      ApplyPlayerParameters(AReplies[2]);
    end;
    Exit(Format('SKILL UPGRADE | result=%d skill=%u requestedFrom=%u rank=%u freeSP=%u; committed before reply',
      [Ord(SkillUpgradeResult),SkillUpgrade.SkillID,SkillUpgrade.CurrentRank,SkillRank,FLoot.SkillPoints(Self)]));
  end;
  if (APayload[0]=$0A) and (APayload[1]=2) then begin
    MiningRequest:=TB1008MiningRequest.Parse(APayload);MiningCode:=$60;
    MiningUpdates:=nil;MiningIDs:=nil;HitTick:=GetTickCount64;
    if Assigned(FLoot) and (FStage=ssAppearanceProbe) and FWorldState.Active and
      (FPlayerHP>0) and FMinePending and (HitTick-FMineStartedTick<=10000) and
      (MiningRequest.MapID=FWorldState.MapID) and
      (MiningRequest.Parameter=0) and (MiningRequest.ToolParameter=$FFFFFFFF) and
      (((Int64(MiningRequest.Timestamp)-Int64(FMineStartTimestamp)+$100000000) mod
        $100000000)<$80000000) and
      TB1008Mining.Near(FWorldState.MapID,FWorldState.Position.X,
        FWorldState.Position.Z,FWorldState.Position.Y) then begin
      if HitTick<FMineNextTick then MiningCode:=$5F // Authored no-yield cycle; no false location error.
      else begin
        StateNote:=FInventorySessionID+'/mine/'+UIntToStr(FMineStartTimestamp);
        try MiningCode:=FLoot.MineQuestItem(Self,StateNote,MiningUpdates);
        except on E:Exception do begin
          FMinePending:=False;
          SetLength(AReplies,1);AReplies[0]:=TB1008Mining.BuildResult(MiningRequest.Timestamp,1,$60,[]);
          Exit('MINING NOT COMMITTED | '+E.Message);
        end;end;
        FMineNextTick:=HitTick+B1008MiningMinimumCycleMS;
      end;
      if MiningCode=$5F then begin
        AppendQuestItems(MiningRequest.Timestamp,MiningUpdates,AReplies);
        for MiningItem in MiningUpdates do if MiningItem.ItemID=70079 then begin
          SetLength(MiningIDs,1);MiningIDs[0]:=70079;
        end;
      end;
    end;
    FMinePending:=False;
    SetLength(AReplies,Length(AReplies)+1);
    AReplies[High(AReplies)]:=TB1008Mining.BuildResult(MiningRequest.Timestamp,1,MiningCode,MiningIDs);
    Exit(Format('MINING RESULT | code=%d oreUpdates=%d; quest-only atomic award',
      [MiningCode,Length(MiningIDs)]));
  end;
  if (APayload[0]=6) and (APayload[1] in [$17,$19]) then begin
    EnhancementRequest:=TB1008EnhancementRequest.Parse(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active or
      (FPlayerHP<=0) then Exit('ENHANCEMENT SKIPPED | no living admitted character');
    if EnhancementRequest.Kind=$19 then EnhancementCode:=$57 else EnhancementCode:=$51;
    if not FHasPendingAttack and not FPlayerAutoAttacking then begin
      StateNote:=FInventorySessionID+Format('/enhance/%d/%u/%u/%u/%u/%u/%u',
        [EnhancementRequest.Kind,EnhancementRequest.Timestamp,EnhancementRequest.SlotA,
         EnhancementRequest.ItemA,EnhancementRequest.PageB,EnhancementRequest.SlotB,EnhancementRequest.Index]);
      try EnhancementCode:=FLoot.EnhanceItem(Self,StateNote,EnhancementRequest,EnhancementUpdates,EnhancementGear);
      except on E:Exception do begin
        SetLength(AReplies,1);AReplies[0]:=EnhancementRequest.Reply(EnhancementCode);
        Exit('ENHANCEMENT NOT COMMITTED | '+E.Message);
      end;end;
    end;
    if EnhancementCode in [$4D,$56] then begin
      AppendQuestItems(EnhancementRequest.Timestamp,EnhancementUpdates,AReplies);
    FEquipment:=FLoot.Equipment(Self);
    FMinePending:=False;
      if EnhancementGear.ItemID<>0 then begin
        SetLength(AReplies,Length(AReplies)+1);
        AReplies[High(AReplies)]:=TB1008Equipment.BuildSlotUpdate(EnhancementRequest.Timestamp,EnhancementGear,True);
        SetLength(AReplies,Length(AReplies)+1);
        AReplies[High(AReplies)]:=TB1008ProgressWire.BuildParameters(EnhancementRequest.Timestamp,FPlayerClassID,FProgress.Level);
        ApplyPlayerParameters(AReplies[High(AReplies)]);
      end;
    end;
    SetLength(AReplies,Length(AReplies)+1);AReplies[High(AReplies)]:=EnhancementRequest.Reply(EnhancementCode);
    Exit(Format('ENHANCEMENT RESULT | kind=%d material=%u target=%u code=%d',
      [EnhancementRequest.Kind,EnhancementRequest.ItemA,EnhancementRequest.ItemB,EnhancementCode]));
  end;
  if (APayload[0]=6) and (APayload[1]=$16) then begin
    CraftRequest:=TB1008CraftRequest.Parse(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active or
      (FPlayerHP<=0) then Exit('CRAFT SKIPPED | no living admitted character');
    CraftAllowed:=False;
    if FWorldState.MapID=19003 then
      for Npc in TB1008Npcs.All do if Npc.Handle=CraftRequest.NpcHandle then begin
        CraftAllowed:=TB1008Npcs.Near(Npc.ID,FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y);Break;
      end;
    if not CraftAllowed then begin
      SetLength(AReplies,1);AReplies[0]:=CraftRequest.Reply($4C);Exit('CRAFT REJECTED | distant or unknown NPC');
    end;
    // Native bulk crafting emits identical timestamp/recipe packets. Each
    // received frame is one attempt; a unique operation receipt protects its
    // transaction without collapsing legitimate consecutive attempts.
    Inc(FNextCraftOperation);
    StateNote:=FInventorySessionID+'/craft/'+UIntToStr(FNextCraftOperation);
    CraftBefore:=FLoot.Items(Self);
    try CraftCode:=FLoot.CraftItem(Self,StateNote,CraftRequest,CraftUpdates);
    except on E:Exception do begin
      SetLength(AReplies,1);AReplies[0]:=CraftRequest.Reply($4C);
      Exit('CRAFT NOT COMMITTED | '+E.Message);
    end;end;
    if CraftCode=$48 then begin
      for CraftNew in CraftUpdates do if CraftNew.Amount>0 then
        for CraftOld in CraftBefore do if (CraftOld.Slot=CraftNew.Slot) and (CraftOld.ItemID<>CraftNew.ItemID) then begin
          SetLength(AReplies,Length(AReplies)+1);
          AReplies[High(AReplies)]:=TB1008InventoryWire.BuildPutOut(CraftRequest.Timestamp,1,CraftOld.ItemID,CraftOld.Slot);Break;
        end;
      AppendQuestItems(CraftRequest.Timestamp,CraftUpdates,AReplies);
    end;
    SetLength(AReplies,Length(AReplies)+1);AReplies[High(AReplies)]:=CraftRequest.Reply(CraftCode);
    Exit(Format('CRAFT RESULT | npc=%u recipe=%u code=%d operation=%u',
      [CraftRequest.NpcHandle,CraftRequest.RecipeID,CraftCode,FNextCraftOperation]));
  end;
  if (APayload[0]=6) and (APayload[1]=$0D) then begin
    Purchase:=TB1008ShopBuy.Parse(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active or
      (FPlayerHP<=0) then Exit('SHOP BUY REJECTED | no living admitted inventory');
    if not Purchase.Supported or not TB1008Shop.CanSellAt(FWorldState.MapID,Purchase.NpcHandle,
      FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y) then
      Exit(Format('SHOP BUY REJECTED | npc=%u item=%u code=%u amount=%d; unsupported/distant',
        [Purchase.NpcHandle,Purchase.ItemID,Purchase.Code,Purchase.Amount]));
    StateNote:=FInventorySessionID+'/buy/'+UIntToStr(Purchase.Timestamp);
    try
      if not FLoot.BuyItem(Self,StateNote,Purchase,PickupUpdates,SplitCreated,SalePaid) then
        Exit('SHOP BUY REJECTED | duplicate/funds/capacity; no change');
    except on E:Exception do Exit('SHOP BUY NOT COMMITTED | inventory retained; '+E.Message);end;
    SetLength(AReplies,Length(PickupUpdates)+1+Ord(SalePaid>0));
    // Remove an exhausted wallet BEFORE filling its newly freed cell.
    if SalePaid>0 then
    if SplitCreated.Amount=0 then AReplies[0]:=TB1008InventoryWire.BuildPutOut(
      Purchase.Timestamp,1,B1008CaratID,SplitCreated.Slot)
    else AReplies[0]:=TB1008InventoryWire.BuildPutIn(Purchase.Timestamp,1,
      B1008CaratID,SplitCreated.Amount,SplitCreated.Slot);
    for I:=0 to High(PickupUpdates) do AReplies[I+Ord(SalePaid>0)]:=TB1008InventoryWire.BuildPutIn(
      Purchase.Timestamp,1,PickupUpdates[I].ItemID,PickupUpdates[I].Amount,PickupUpdates[I].Slot);
    AReplies[High(AReplies)]:=Purchase.Ack;
    Exit(Format('SHOP BUY COMMITTED | npc=%u item=%u amount=%u requestCode=%u paid=%u carat=%u; client prices; atomic receipt',
      [Purchase.NpcHandle,Purchase.ItemID,Purchase.Quantity,Purchase.Code,SalePaid,SplitCreated.Amount]));
  end;
  if (APayload[0]=6) and (APayload[1]=$0E) then begin
    Sale:=TB1008ShopSell.Parse(APayload);
    if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active or
      (FPlayerHP<=0) then Exit('SHOP SELL REJECTED | no living admitted inventory');
    if not Sale.Supported or not TB1008Shop.CanSellAt(FWorldState.MapID,Sale.NpcHandle,
      FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y) then
      Exit(Format('SHOP SELL REJECTED | npc=%u page=%u cell=%u item=%u amount=%d; unsupported/distant',
        [Sale.NpcHandle,Sale.Page,Sale.Slot,Sale.ItemID,Sale.Amount]));
    StateNote:=FInventorySessionID+'/sell/'+UIntToStr(Sale.Timestamp);
    try
      if not FLoot.SellItem(Self,StateNote,Sale,SplitSource,SplitCreated,SalePaid) then
        Exit('SHOP SELL REJECTED | stale/duplicate/unsellable/currency capacity; no change');
    except on E:Exception do Exit('SHOP SELL NOT COMMITTED | inventory retained; '+E.Message);end;
    SetLength(AReplies,2+Ord(SalePaid>0));
    if SplitSource.Amount=0 then
      AReplies[0]:=TB1008InventoryWire.BuildPutOut(Sale.Timestamp,1,SplitSource.ItemID,SplitSource.Slot)
    else AReplies[0]:=TB1008InventoryWire.BuildPutIn(Sale.Timestamp,1,
      SplitSource.ItemID,SplitSource.Amount,SplitSource.Slot);
    if SalePaid>0 then AReplies[1]:=TB1008InventoryWire.BuildPutIn(Sale.Timestamp,1,
      SplitCreated.ItemID,SplitCreated.Amount,SplitCreated.Slot);
    AReplies[High(AReplies)]:=Sale.Ack;
    Exit(Format('SHOP SELL COMMITTED | npc=%u slot=%u item=%u sold=%d remaining=%u paid=%u carat=%u; client prices; atomic receipt',
      [Sale.NpcHandle,Sale.Slot,Sale.ItemID,Sale.Amount,SplitSource.Amount,SalePaid,SplitCreated.Amount]));
  end;
  Result := Format('UNIMPLEMENTED %s/%s | %d decoded bytes | no reply; contents redacted',
    [IntToHex(APayload[0], 2), IntToHex(APayload[1], 2), Length(APayload)]);
end;

end.
