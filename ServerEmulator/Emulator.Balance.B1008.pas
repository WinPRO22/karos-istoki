unit Emulator.Balance.B1008;

interface

uses System.SysUtils;

type
  TB1008BaseAttributes = record
    Strength,Vitality,Mentality,Dexterity,Intelligence: Word;
    CriticalBasisPoints: Integer;
    // Server-side bonus only; original base rating / character wire field unknown.
    AttackRatingBonus,DefenseRatingBonus: Integer;
    RegenHP,RegenMP,Evasion,BlockRate: Integer;
    PhysicalAttack,PhysicalDefense,MagicalAttack,MagicalDefense: Integer;
  end;

  // Immutable for the process lifetime: changing thresholds under online
  // characters would reinterpret their persisted EXP. Rewards stay data-driven.
  TB1008Balance = class
  private
    class var FThresholds: TArray<Int64>;
    class var FMaxEXP: Int64;
    class var FSpiderEXP, FFarmEXP, FPlayerDamage: Integer;
    class var FCriticalDamagePercent:Integer;
    class var FFlettaProcBasisPoints:Integer;
    class var FWindBarrierDefenseRating:Integer;
    class var FMissFailEqual,FMissFailHigherPerLevel,FMissFailZeroLead:Integer;
    class var FMissFailRatingScale,FMissFailMaximum:Integer;
    class var FPhysicalDefenseCurve,FMobDamageReferenceDefense:Integer;
    class var FHPGrowthTenths,FMPGrowth,FBladerAnchorLevel,FBladerHP,FBladerMP: Integer;
    class var FRogueAnchorLevel,FRogueHP,FRogueMP,FArcherHPPercent,FArcherMPPercent: Integer;
    class var FRegenInterval,FRegenHP,FRegenMP: Integer;
    class var FAttributes: array[0..2] of TB1008BaseAttributes;
    class var FGrowth: array[0..2] of TB1008BaseAttributes;
    class var FSwordSpeed,FSpearSpeed,FSpearAttack,FSpearDefense:Integer;
  public
    class constructor Create;
    class function LevelCap: Word; static;
    class function Threshold(Level: Word): Int64; static;
    class function MaxEXP: Int64; static;
    class function SpiderEXP: Integer; static;
    // Fixed fallback for standalone probes without a player/equipment store.
    // Normal sessions use Equipment.PhysicalAttack and CombatDamage.Roll.
    class function PlayerDamage: Integer; static;
    class function CriticalDamagePercent: Integer; static;
    class function FlettaProcBasisPoints:Integer; static;
    class function WindBarrierDefenseRating:Integer; static;
    class function MissFailBasisPoints(PlayerLevel,MobLevel,AttackRatingBonus:Integer):Integer; static;
    class function PhysicalDefenseCurve:Integer; static;
    class function MobDamageReferenceDefense:Integer; static;
    class function BladerMaxHP(Level: Word): Integer; static;
    class function BladerMaxMP(Level: Word): Integer; static;
    class function ClassMaxHP(ClassID,Level: Word): Integer; static;
    class function ClassMaxMP(ClassID,Level: Word): Integer; static;
    class function BaseAttributes(ClassID: Word; Level:Word=1): TB1008BaseAttributes; static;
    class function ProfessionAttributes(BaseClass,ClassID,Rank,Level:Word):TB1008BaseAttributes; static;
    class function WeaponAutoAttackSpeed(Subtype:Byte):Single; static;
    class function ProfessionPhysicalAttack(ClassID:Word;Value:Integer):Integer; static;
    class function ProfessionPhysicalDefense(ClassID:Word;Value:Integer):Integer; static;
    class function ProfessionMaxHP(BaseClass,ClassID,Level:Word):Integer; static;
    class function ProfessionMaxMP(BaseClass,ClassID,Level:Word):Integer; static;
    class function RegenIntervalMS: Cardinal; static;
    class function RegenHP: Integer; static;
    class function RegenMP: Integer; static;
    class function DeathEXPLoss(Level: Word): Int64; static;
    class function QuestEXP(QuestID: Cardinal): Integer; static;
    class function ProgressionSignature(Cap:Word=0): string; static;
  end;

implementation

uses System.IniFiles, System.IOUtils;

class constructor TB1008Balance.Create;
const Sections:array[0..2] of string=('blader','rogue','archer');
var Dir, Parent, FileName: string; I, Cap: Integer; Ini: TMemIniFile; N: Int64;
  function ReadAttribute(const Section,Key:string):Word;
  var V:Integer;
  begin
    V:=Ini.ReadInteger(Section,Key,-1);
    if (V<1) or (V>1000) then raise Exception.Create('Invalid base attribute '+Section+'.'+Key);
    Result:=V;
  end;
  function ReadCombat(const Section,Key:string;MaxValue:Integer):Integer;
  begin
    Result:=Ini.ReadInteger(Section,Key,-1);
    if (Result<0) or (Result>MaxValue) then raise Exception.Create('Invalid combat parameter '+Section+'.'+Key);
  end;
begin
  Dir:=ExtractFileDir(ExpandFileName(ParamStr(0))); FileName:='';
  for I:=0 to 6 do begin
    if FileExists(TPath.Combine(Dir,'KarosOldEmulator.dpr')) then begin
      FileName:=TPath.Combine(Dir,'data\b1008\balance-v2.ini'); Break;
    end;
    Parent:=ExtractFileDir(Dir); if SameText(Parent,Dir) then Break; Dir:=Parent;
  end;
  if not FileExists(FileName) then raise Exception.Create('Missing b1008 balance-v2.ini; refusing diagnostic fallback');
  Ini:=TMemIniFile.Create(FileName,TEncoding.UTF8);
  try
    if Ini.ReadString('balance','profile','')<>'b1008-reconstruction-v2' then
      raise Exception.Create('Unsupported b1008 balance profile');
    Cap:=Ini.ReadInteger('balance','level_cap',0);
    if (Cap<2) or (Cap>45) then raise Exception.Create('Balance phase level cap must be 2..45');
    SetLength(FThresholds,Cap);
    FMaxEXP:=0;
    for I:=1 to Cap-1 do begin
      if not TryStrToInt64(Ini.ReadString('thresholds',IntToStr(I),''),N) or
        (N<=0) or (N>100000000) then raise Exception.CreateFmt('Invalid EXP threshold at level %d',[I]);
      FThresholds[I]:=N; Inc(FMaxEXP,N);
    end;
    FSpiderEXP:=Ini.ReadInteger('balance','spider_exp',0);
    FFarmEXP:=Ini.ReadInteger('balance','quest_19003003_exp',-1);
    FPlayerDamage:=Ini.ReadInteger('combat','normal_hit_damage',0);
    FSwordSpeed:=ReadCombat('profession_balance','sword_attack_speed_percent',1000);
    FSpearSpeed:=ReadCombat('profession_balance','spear_attack_speed_percent',1000);
    FSpearAttack:=ReadCombat('profession_balance','spear_physical_attack_percent',1000);
    FSpearDefense:=ReadCombat('profession_balance','spear_physical_defense_percent',1000);
    if (FSwordSpeed=0) or (FSpearSpeed=0) or (FSpearAttack=0) or (FSpearDefense=0) then
      raise Exception.Create('Profession balance percentages must be positive');
    FCriticalDamagePercent:=Ini.ReadInteger('combat','critical_damage_percent',0);
    if (FCriticalDamagePercent<100) or (FCriticalDamagePercent>1000) then
      raise Exception.Create('Invalid critical damage multiplier');
    FMissFailEqual:=ReadCombat('combat','miss_fail_equal_basis_points',10000);
    FFlettaProcBasisPoints:=ReadCombat('combat','fletta_proc_basis_points',10000);
    FWindBarrierDefenseRating:=ReadCombat('combat','wind_barrier_defense_rating',1000);
    FMissFailHigherPerLevel:=ReadCombat('combat','miss_fail_higher_level_basis_points',10000);
    FMissFailZeroLead:=ReadCombat('combat','miss_fail_zero_player_lead',100);
    FMissFailRatingScale:=ReadCombat('combat','attack_rating_scale',10000);
    if FMissFailRatingScale=0 then raise Exception.Create('Attack rating scale must be positive');
    FMissFailMaximum:=ReadCombat('combat','miss_fail_max_basis_points',10000);
    if (FMissFailZeroLead<1) or (FMissFailMaximum<FMissFailEqual) then
      raise Exception.Create('Invalid miss/fail level profile');
    FPhysicalDefenseCurve:=ReadCombat('combat','physical_defense_curve',1000000);
    FMobDamageReferenceDefense:=ReadCombat('combat','mob_damage_reference_defense',1000000);
    if FPhysicalDefenseCurve<1 then raise Exception.Create('Physical defense curve must be positive');
    FHPGrowthTenths:=Ini.ReadInteger('class_vitals','hp_growth_tenths',0);
    FMPGrowth:=Ini.ReadInteger('class_vitals','mp_per_level',0);
    FBladerAnchorLevel:=Ini.ReadInteger('blader','anchor_level',0);
    FBladerHP:=Ini.ReadInteger('blader','anchor_hp',0);
    FBladerMP:=Ini.ReadInteger('blader','anchor_mp',0);
    FRogueAnchorLevel:=Ini.ReadInteger('rogue','anchor_level',0);
    FRogueHP:=Ini.ReadInteger('rogue','anchor_hp',0);
    FRogueMP:=Ini.ReadInteger('rogue','anchor_mp',0);
    FArcherHPPercent:=Ini.ReadInteger('archer','rogue_hp_percent',0);
    FArcherMPPercent:=Ini.ReadInteger('archer','blader_mp_percent',0);
    FRegenInterval:=Ini.ReadInteger('blader','regen_interval_ms',10000);
    FRegenHP:=Ini.ReadInteger('blader','regen_hp',13);
    FRegenMP:=Ini.ReadInteger('blader','regen_mp',1);
    for I:=0 to High(FAttributes) do begin
      FAttributes[I].Strength:=ReadAttribute(Sections[I],'strength');
      FAttributes[I].Vitality:=ReadAttribute(Sections[I],'vitality');
      FAttributes[I].Mentality:=ReadAttribute(Sections[I],'mentality');
      FAttributes[I].Dexterity:=ReadAttribute(Sections[I],'dexterity');
      FAttributes[I].Intelligence:=ReadAttribute(Sections[I],'intelligence');
      FAttributes[I].CriticalBasisPoints:=Ini.ReadInteger(Sections[I],'critical_basis_points',-1);
      FAttributes[I].AttackRatingBonus:=ReadCombat(Sections[I],'attack_rating_bonus',100000);
      FAttributes[I].DefenseRatingBonus:=ReadCombat(Sections[I],'defense_rating_bonus',100000);
      FGrowth[I].PhysicalAttack:=ReadCombat(Sections[I],'physical_attack_per_level',1000);
      FGrowth[I].MagicalAttack:=ReadCombat(Sections[I],'magical_attack_per_level',1000);
      FGrowth[I].CriticalBasisPoints:=ReadCombat(Sections[I],'critical_basis_points_per_level',100);
      FGrowth[I].AttackRatingBonus:=ReadCombat(Sections[I],'attack_rating_per_level',1000);
      FGrowth[I].DefenseRatingBonus:=ReadCombat(Sections[I],'defense_rating_per_level',1000);
      FAttributes[I].RegenHP:=ReadCombat(Sections[I],'regen_hp',5000);
      FAttributes[I].RegenMP:=ReadCombat(Sections[I],'regen_mp',150);
      FAttributes[I].Evasion:=ReadCombat(Sections[I],'evasion',100);
      FAttributes[I].BlockRate:=ReadCombat(Sections[I],'block_rate',100);
      FAttributes[I].PhysicalAttack:=ReadCombat(Sections[I],'physical_attack',100000);
      FAttributes[I].PhysicalDefense:=ReadCombat(Sections[I],'physical_defense',100000);
      FAttributes[I].MagicalAttack:=ReadCombat(Sections[I],'magical_attack',100000);
      FAttributes[I].MagicalDefense:=ReadCombat(Sections[I],'magical_defense',100000);
      if (FAttributes[I].CriticalBasisPoints<0) or (FAttributes[I].CriticalBasisPoints>10000) then
        raise Exception.Create('Invalid base critical chance '+Sections[I]);
    end;
    if (FRegenInterval<250) or (FRegenInterval>60000) or (FRegenHP<0) or
      (FRegenHP>5000) or (FRegenMP<0) or (FRegenMP>150) then
      raise Exception.Create('Invalid regeneration profile');
    if (FHPGrowthTenths<0) or (FHPGrowthTenths>2500) or (FMPGrowth<0) or (FMPGrowth>100) or
      (FBladerAnchorLevel<1) or (FBladerAnchorLevel>Cap) or
      (FRogueAnchorLevel<1) or (FRogueAnchorLevel>Cap) or
      (FBladerHP<1) or (FBladerHP>5000) or (FBladerMP<0) or (FBladerMP>5000) or
      (FRogueHP<1) or (FRogueHP>5000) or (FRogueMP<0) or (FRogueMP>5000) or
      (FArcherHPPercent<1) or (FArcherHPPercent>200) or
      (FArcherMPPercent<1) or (FArcherMPPercent>200) then
      raise Exception.Create('Invalid class vitals profile');
    for I:=1 to Cap do begin
      ClassMaxHP(100,I);ClassMaxMP(100,I);
      ClassMaxHP(300,I);ClassMaxMP(300,I);
      ClassMaxHP(500,I);ClassMaxMP(500,I);
    end;
    if (FPlayerDamage<1) or (FPlayerDamage>100000) then
      raise Exception.Create('Invalid reconstructed normal hit damage');
    if (FSpiderEXP<1) or (FSpiderEXP>1000000) or (FFarmEXP<0) or (FFarmEXP>1000000) then
      raise Exception.Create('Balance reward outside safe bounds');
  finally Ini.Free; end;
end;

class function TB1008Balance.LevelCap: Word;
begin Result:=Length(FThresholds); end;
class function TB1008Balance.Threshold(Level: Word): Int64;
begin
  if (Level<1) or (Level>LevelCap) then raise Exception.Create('Invalid balance level');
  // Keep a positive HUD denominator at the phase cap; no further EXP is awarded.
  if Level=LevelCap then Result:=FThresholds[Level-1] else Result:=FThresholds[Level];
end;
class function TB1008Balance.MaxEXP: Int64;
begin Result:=FMaxEXP; end;
class function TB1008Balance.SpiderEXP: Integer;
begin Result:=FSpiderEXP; end;
class function TB1008Balance.PlayerDamage: Integer;
begin Result:=FPlayerDamage; end;
class function TB1008Balance.CriticalDamagePercent: Integer;
begin Result:=FCriticalDamagePercent; end;
class function TB1008Balance.FlettaProcBasisPoints:Integer;
begin Result:=FFlettaProcBasisPoints;end;
class function TB1008Balance.WindBarrierDefenseRating:Integer;
begin Result:=FWindBarrierDefenseRating;end;
class function TB1008Balance.MissFailBasisPoints(PlayerLevel,MobLevel,AttackRatingBonus:Integer):Integer;
var Gap:Integer; Chance:Int64;
begin
  if (PlayerLevel<1) or (PlayerLevel>1000) or (MobLevel<1) or (MobLevel>1000) or
    (AttackRatingBonus<-100000) or (AttackRatingBonus>100000) then
    raise EArgumentOutOfRangeException.Create('Invalid hit rating or combat level');
  Gap:=MobLevel-PlayerLevel;
  // User rule: player +3 or more always connects; equal-level chance is tunable.
  if Gap<=-FMissFailZeroLead then Exit(0);
  if Gap<0 then Chance:=Int64(FMissFailEqual)*(FMissFailZeroLead+Gap) div FMissFailZeroLead
  else Chance:=Int64(FMissFailEqual)+Int64(Gap)*FMissFailHigherPerLevel;
  if Chance>FMissFailMaximum then Chance:=FMissFailMaximum;
  // Diminishing bonus: +100 halves the level-based failure chance. Negative
  // modifiers increase it linearly, avoiding a zero/negative denominator.
  if AttackRatingBonus>=0 then
    Chance:=Chance*FMissFailRatingScale div (FMissFailRatingScale+AttackRatingBonus)
  else Chance:=Chance*(FMissFailRatingScale-Int64(AttackRatingBonus)) div FMissFailRatingScale;
  if Chance<0 then Chance:=0;
  if Chance>FMissFailMaximum then Chance:=FMissFailMaximum;
  Result:=Integer(Chance);
end;
class function TB1008Balance.PhysicalDefenseCurve:Integer;
begin Result:=FPhysicalDefenseCurve;end;
class function TB1008Balance.MobDamageReferenceDefense:Integer;
begin Result:=FMobDamageReferenceDefense;end;
class function TB1008Balance.BaseAttributes(ClassID:Word;Level:Word):TB1008BaseAttributes;
var Index,Steps:Integer;
begin
  if (Level<1) or (Level>LevelCap) then raise EArgumentOutOfRangeException.Create('Invalid attributes level');
  case ClassID of
    100:Index:=0;
    300:Index:=1;
    500:Index:=2;
  else raise Exception.Create('Unsupported class base attributes');end;
  // Derived from level, never accumulated in the save: relog and delevel use
  // the same profile without duplicate bonuses or a character migration.
  Result:=FAttributes[Index];Steps:=Level-1;
  Inc(Result.PhysicalAttack,Steps*FGrowth[Index].PhysicalAttack);
  Inc(Result.MagicalAttack,Steps*FGrowth[Index].MagicalAttack);
  Inc(Result.CriticalBasisPoints,Steps*FGrowth[Index].CriticalBasisPoints);
  if Result.CriticalBasisPoints>10000 then Result.CriticalBasisPoints:=10000;
  Inc(Result.AttackRatingBonus,Steps*FGrowth[Index].AttackRatingBonus);
  Inc(Result.DefenseRatingBonus,Steps*FGrowth[Index].DefenseRatingBonus);
end;
// Authored Blader advancement balance: four levels of attack/critical growth
// at first profession, five further levels at rank1; no extra level/SP/ratings.
class function TB1008Balance.ProfessionAttributes(BaseClass,ClassID,Rank,Level:Word):TB1008BaseAttributes;
var Steps:Integer;
begin
  Result:=BaseAttributes(BaseClass,Level);
  if (BaseClass<>100) or not (ClassID in [110,120]) then Exit;
  if Rank>1 then raise EArgumentOutOfRangeException.Create('Invalid profession rank');
  Steps:=4+5*Rank;
  Inc(Result.PhysicalAttack,Steps*FGrowth[0].PhysicalAttack);
  Inc(Result.MagicalAttack,Steps*FGrowth[0].MagicalAttack);
  Inc(Result.CriticalBasisPoints,Steps*FGrowth[0].CriticalBasisPoints);
  if Result.CriticalBasisPoints>10000 then Result.CriticalBasisPoints:=10000;
end;

class function TB1008Balance.WeaponAutoAttackSpeed(Subtype:Byte):Single;
begin
  case Subtype of
    1:Result:=FSwordSpeed/100;
    2:Result:=FSpearSpeed/100;
  else Result:=1;end;
end;

class function TB1008Balance.ProfessionPhysicalAttack(ClassID:Word;Value:Integer):Integer;
begin
  if (Value<0) or (Value>1000000) then raise EArgumentOutOfRangeException.Create('Invalid permanent physical attack');
  Result:=Value;
  if ClassID=120 then Result:=Integer((Int64(Value)*FSpearAttack+50) div 100);
end;

class function TB1008Balance.ProfessionPhysicalDefense(ClassID:Word;Value:Integer):Integer;
begin
  if (Value<0) or (Value>1000000) then raise EArgumentOutOfRangeException.Create('Invalid permanent physical defense');
  Result:=Value;
  if ClassID=120 then Result:=Integer((Int64(Value)*FSpearDefense+50) div 100);
end;

class function TB1008Balance.ProfessionMaxHP(BaseClass,ClassID,Level:Word):Integer;
var Growth:Integer;
begin
  Result:=ClassMaxHP(BaseClass,Level);
  if (BaseClass<>100) or not (ClassID in [110,120]) then Exit;
  // User-approved transfer of measured paladin delta, not its class base pool.
  // Fixed level11 anchor keeps reconnect/death/grants independent of change time.
  Growth:=585*(Integer(Level)-11);
  if Growth<0 then Growth:=(Growth-9) div 10 else Growth:=Growth div 10;
  Result:=ClassMaxHP(BaseClass,11)+456+Growth;
end;

class function TB1008Balance.ProfessionMaxMP(BaseClass,ClassID,Level:Word):Integer;
begin
  Result:=ClassMaxMP(BaseClass,Level);
  if (BaseClass=100) and (ClassID in [110,120]) then
    Result:=ClassMaxMP(BaseClass,11)+104+10*(Integer(Level)-11);
end;

class function TB1008Balance.RegenIntervalMS: Cardinal;
begin Result:=FRegenInterval;end;
class function TB1008Balance.RegenHP: Integer;
begin Result:=FRegenHP;end;
class function TB1008Balance.RegenMP: Integer;
begin Result:=FRegenMP;end;
class function TB1008Balance.DeathEXPLoss(Level: Word): Int64;
begin
  // User memory: 4% of the full current-level threshold, level loss allowed.
  // Half-up integer rounding is an authored convention, not a recovered rule.
  Result:=(Threshold(Level)*4+50) div 100;
end;
class function TB1008Balance.BladerMaxHP(Level: Word): Integer;
begin
  Result:=ClassMaxHP(100,Level);
end;
class function TB1008Balance.BladerMaxMP(Level: Word): Integer;
begin
  Result:=ClassMaxMP(100,Level);
end;
function CeilTenths(N:Integer):Integer;
begin
  // Delphi div truncates toward zero: that is already ceil for negatives.
  if N>0 then Result:=(N+9) div 10 else Result:=N div 10;
end;
class function TB1008Balance.ClassMaxHP(ClassID,Level:Word):Integer;
begin
  if (Level<1) or (Level>LevelCap) then raise Exception.Create('Invalid vitals level');
  // Shared growth explicitly chosen by the user; anchored before rounding.
  // Profession bonuses are NOT awarded automatically on reaching a level.
  case ClassID of
    100:Result:=FBladerHP+CeilTenths(FHPGrowthTenths*(Integer(Level)-FBladerAnchorLevel));
    300:Result:=FRogueHP+CeilTenths(FHPGrowthTenths*(Integer(Level)-FRogueAnchorLevel));
    500:Result:=(ClassMaxHP(300,Level)*FArcherHPPercent+50) div 100;
  else raise Exception.Create('Unsupported class vitals');end;
  if (Result<1) or (Result>1000000) then raise Exception.Create('Class HP outside supported range');
end;
class function TB1008Balance.ClassMaxMP(ClassID,Level:Word):Integer;
begin
  if (Level<1) or (Level>LevelCap) then raise Exception.Create('Invalid vitals level');
  case ClassID of
    100:Result:=FBladerMP+FMPGrowth*(Integer(Level)-FBladerAnchorLevel);
    300:Result:=FRogueMP+FMPGrowth*(Integer(Level)-FRogueAnchorLevel);
    500:Result:=(ClassMaxMP(100,Level)*FArcherMPPercent+50) div 100;
  else raise Exception.Create('Unsupported class vitals');end;
  if (Result<0) or (Result>1000000) then raise Exception.Create('Class MP outside supported range');
end;
class function TB1008Balance.QuestEXP(QuestID: Cardinal): Integer;
begin
  if QuestID<>19003003 then raise Exception.Create('Quest reward handler not implemented');
  Result:=FFarmEXP;
end;

class function TB1008Balance.ProgressionSignature(Cap:Word): string;
var I: Integer;
begin
  if Cap=0 then Cap:=LevelCap;
  if (Cap<2) or (Cap>LevelCap) then raise Exception.Create('Invalid signature level cap');
  Result:='cap='+IntToStr(Cap);
  for I:=1 to Cap-1 do Result:=Result+'|'+IntToStr(I)+'='+IntToStr(FThresholds[I]);
end;

end.
