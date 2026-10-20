unit Emulator.MonsterBalance.B1008;

interface
type
  TB1008MonsterStats = record
    HP,AttackMin,AttackMax,Defense:Integer;
  end;
  TB1008MonsterBalance = class
  private
    class var FBase:TB1008MonsterStats;
    class var FGrowthPercent,FDefensePercent,FAttackCyclePercent:Integer;
  public
    class constructor Create;
    class function AtLevel(Level:Integer):TB1008MonsterStats;static;
    class function PhysicalDamage(RawDamage,Defense:Integer):Integer;static;
    class function AttackSpeed(BaseSpeed:Single):Single;static;
  end;

implementation
uses System.SysUtils,System.Math,System.IniFiles,Emulator.Items.B1008;

class constructor TB1008MonsterBalance.Create;
var Ini:TMemIniFile;
  function Read(const Key:string;Minimum,Maximum:Integer):Integer;
  begin
    Result:=Ini.ReadInteger('monsters',Key,-1);
    if (Result<Minimum) or (Result>Maximum) then
      raise Exception.Create('Invalid monster balance: '+Key);
  end;
begin
  Ini:=TMemIniFile.Create(TB1008Items.DataPath('balance-v2.ini'),TEncoding.UTF8);
  try
    FBase.HP:=Read('base_hp',1,10000);
    FBase.AttackMin:=Read('base_attack_min',1,10000);
    FBase.AttackMax:=Read('base_attack_max',FBase.AttackMin,10000);
    FBase.Defense:=Read('base_defense',0,10000);
    FGrowthPercent:=Read('growth_percent',0,30);
    FDefensePercent:=Read('physical_defense_percent',0,100);
    FAttackCyclePercent:=Read('attack_cycle_percent',50,1000);
    AtLevel(20); // Validate the whole supported world before accepting sessions.
  finally Ini.Free;end;
end;

class function TB1008MonsterBalance.AtLevel(Level:Integer):TB1008MonsterStats;
var Factor:Double;I:Integer;
  function Scale(Value:Integer):Integer;
  var Scaled:Int64;
  begin
    // Round once from the Lv1 anchor: repeated integer rounding loses growth.
    Scaled:=Floor(Value*Factor+0.5);
    if Scaled>1000000 then raise Exception.Create('Monster balance exceeds supported range');
    Result:=Scaled;
  end;
begin
  if (Level<1) or (Level>20) then raise Exception.Create('Unsupported monster level');
  Factor:=1;
  for I:=2 to Level do Factor:=Factor*(100+FGrowthPercent)/100;
  Result.HP:=Scale(FBase.HP);Result.AttackMin:=Scale(FBase.AttackMin);
  Result.AttackMax:=Scale(FBase.AttackMax);Result.Defense:=Scale(FBase.Defense);
end;

class function TB1008MonsterBalance.AttackSpeed(BaseSpeed:Single):Single;
begin
  if IsNan(BaseSpeed) or IsInfinite(BaseSpeed) or (BaseSpeed<=0) then
    raise Exception.Create('Invalid base monster attack speed');
  Result:=BaseSpeed*100/FAttackCyclePercent;
end;

class function TB1008MonsterBalance.PhysicalDamage(RawDamage,Defense:Integer):Integer;
begin
  if (RawDamage<0) or (RawDamage>1000000) or (Defense<0) or (Defense>1000000) then
    raise Exception.Create('Invalid physical damage inputs');
  if RawDamage=0 then Exit(0);
  // Authored fit to Classic controlled tests, not recovered historical code.
  Result:=Max(1,RawDamage-Integer(Int64(Defense)*FDefensePercent div 100));
end;
end.
