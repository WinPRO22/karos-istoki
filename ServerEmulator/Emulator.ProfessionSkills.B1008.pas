unit Emulator.ProfessionSkills.B1008;

interface

uses System.SysUtils;

const
  B1008BladeCrashID=1101;
  B1008SwordMasteryID=1102;
  B1008SpineBreakerID=1103;
  B1008ThunderHowlID=1104;
  B1008SwordRevengeID=1105;
  B1008SlaterID=1106;
  B1008SwordDeathLeapID=1107;
  B1008WindBladeID=1901;
  B1008PolearmMasteryID=1902;
  B1008StunAttackID=1903;
  B1008CycloneID=1904;
  B1008PolearmRevengeID=1905;
  B1008PhantomThrustID=1906;
  B1008PolearmDeathLeapID=1907;

type
  TB1008ProfessionModifier=record
    DataID,TypeCode:Cardinal;
    Value18,Value20:Double;
  end;
  TB1008ProfessionSkill=record
    ClassID,RequiredLevel,RawRequiredLevel:Word;
    PrerequisiteID,ActionID,CooldownMS,DurationMS,IntervalMS,RawIntervalMS:Cardinal;
    MPCost,BonusMin,BonusMax,PeriodicDamage,AttackBonus,AttackPercent:Integer;
    Range,AreaRange,AreaSecondaryRange:Single;
    WeaponSubtype,AreaKind,PrerequisiteCount,RawModifierCount:Byte;
    PrerequisiteIDs,PrerequisiteRanks:array[0..2] of Cardinal;
    RawModifiers:array[0..3] of TB1008ProfessionModifier;
    StunMS,StunChanceBasisPoints:Cardinal;
    WeaponMask,HitCount:Cardinal;
    SlowPercent,AbsorbPercent,AttackSpeedPercent,DefensePenaltyPercent:Integer;
    // False means the catalog has no recovered probability, not a 0% roll.
    StunChanceKnown,WeaponRequired:Boolean;
    class function Supported(ID:Cardinal):Boolean;static;
    class function IsAttack(ID:Cardinal):Boolean;static;
    // READY target is the caster; 1104/1903 still impact surrounding NPCs.
    class function IsSelf(ID:Cardinal):Boolean;static;
    class function IsArea(ID:Cardinal):Boolean;static;
    class function IsPassive(ID:Cardinal):Boolean;static;
    class function Allowed(ID:Cardinal;ClassID:Word):Boolean;static;
    class function WeaponAllowed(ID:Cardinal;Subtype:Byte):Boolean;static;
    class function Get(ID,Rank:Cardinal):TB1008ProfessionSkill;static;
  end;

  // Transient state owned by one living NPC incarnation. Clear on death,
  // replacement, scene reset and return; never persist or reuse by handle alone.
  TB1008WindBleed=record
  private
    FRank:Cardinal;
    FRemainingTicks:Integer;
    FNextTick,FUntilTick:UInt64;
  public
    procedure Start(ARank:Cardinal;NowTick:UInt64);
    // Consume one due tick. A delayed poll may loop, stopping on target death.
    // Exhaustion retains Rank until Clear so the owner can send 05/09 remove.
    function TakeDue(NowTick:UInt64;out Damage:Integer):Boolean;
    procedure Clear;
    property Rank:Cardinal read FRank;
    property RemainingTicks:Integer read FRemainingTicks;
    property UntilTick:UInt64 read FUntilTick;
  end;

implementation

uses System.JSON,System.IOUtils,System.Math,Emulator.Items.B1008;

type
  TB1008ProfessionCatalog=class
  private
    class var FRows:array[0..13,1..5] of TB1008ProfessionSkill;
  public
    class constructor Create;
    class function Get(ID,Rank:Cardinal):TB1008ProfessionSkill;static;
  end;

function SkillIndex(ID:Cardinal):Integer;
begin
  if (ID>=1101) and (ID<=1107) then Exit(Integer(ID)-1101);
  if (ID>=1901) and (ID<=1907) then Exit(Integer(ID)-1901+7);
  Result:=-1;
end;

class function TB1008ProfessionSkill.Supported(ID:Cardinal):Boolean;
begin Result:=SkillIndex(ID)>=0;end;

class function TB1008ProfessionSkill.IsAttack(ID:Cardinal):Boolean;
begin Result:=(ID=1101) or (ID=1103) or (ID=1106) or
  (ID=1901) or (ID=1903) or (ID=1904) or (ID=1906);end;

class function TB1008ProfessionSkill.IsSelf(ID:Cardinal):Boolean;
begin Result:=(ID=1104) or (ID=1105) or (ID=1107) or
  (ID=1903) or (ID=1905) or (ID=1907);end;

class function TB1008ProfessionSkill.IsArea(ID:Cardinal):Boolean;
begin Result:=(ID=1104) or (ID=1106) or (ID=1903) or
  (ID=1904) or (ID=1906);end;

class function TB1008ProfessionSkill.IsPassive(ID:Cardinal):Boolean;
begin Result:=(ID=1102) or (ID=1902);end;

class function TB1008ProfessionSkill.Allowed(ID:Cardinal;ClassID:Word):Boolean;
begin
  Result:=((ClassID=110) and (ID>=1101) and (ID<=1107)) or
    ((ClassID=120) and (ID>=1901) and (ID<=1907));
end;

class function TB1008ProfessionSkill.WeaponAllowed(ID:Cardinal;Subtype:Byte):Boolean;
var D:TB1008ProfessionSkill;
begin
  if not Supported(ID) then Exit(True);
  D:=Get(ID,1);
  if IsPassive(ID) then Exit(Subtype=D.WeaponSubtype);
  if D.WeaponRequired and (Subtype=0) then Exit(False);
  if D.WeaponMask=0 then Exit(True);
  if Subtype>=32 then Exit(False);
  Result:=(D.WeaponMask and (Cardinal(1) shl Subtype))<>0;
end;

class function TB1008ProfessionSkill.Get(ID,Rank:Cardinal):TB1008ProfessionSkill;
begin
  if not Supported(ID) or (Rank<1) or (Rank>5) then
    raise EArgumentException.Create('Unsupported profession skill/rank');
  Result:=TB1008ProfessionCatalog.Get(ID,Rank);
end;

class constructor TB1008ProfessionCatalog.Create;
var Root:TJSONObject;Skills,Ranks,Children:TJSONArray;V,W,P:TJSONValue;
  D:TB1008ProfessionSkill;ID,Rank:Cardinal;I,J:Integer;
  Seen:array[0..13,1..5] of Boolean;
begin
  Root:=TJSONObject.ParseJSONValue(TFile.ReadAllText(TB1008Items.DataPath(
    'blader-profession-skills-v1.json'),TEncoding.UTF8)) as TJSONObject;
  if Root=nil then raise Exception.Create('Invalid b1008 profession skill catalog');
  try
    if Root.GetValue<string>('build')<>'b1008' then
      raise Exception.Create('Wrong profession skill catalog build');
    FillChar(Seen,SizeOf(Seen),0);
    Skills:=Root.GetValue<TJSONArray>('skills');
    if Skills.Count<>14 then raise Exception.Create('Incomplete profession skill catalog');
    for V in Skills do begin
      ID:=V.GetValue<Cardinal>('id');I:=SkillIndex(ID);
      if I<0 then raise Exception.Create('Unsupported profession catalog identity');
      Ranks:=V.GetValue<TJSONArray>('ranks');
      if Ranks.Count<>5 then raise Exception.Create('Incomplete profession skill ranks');
      for W in Ranks do begin
        Rank:=W.GetValue<Cardinal>('rank');
        if (Rank<1) or (Rank>5) then raise Exception.Create('Invalid profession rank');
        if Seen[I,Rank] then raise Exception.Create('Duplicate profession rank');
        D:=Default(TB1008ProfessionSkill);
        D.ClassID:=V.GetValue<Word>('classId');
        D.WeaponSubtype:=V.GetValue<Byte>('weaponSubtype');
        D.WeaponMask:=V.GetValue<Cardinal>('weaponMask');
        // base+$48 is retained in the raw catalog; only the native weapon
        // mask has a proven admission meaning (including unarmed actors).
        D.WeaponRequired:=D.WeaponMask<>0;
        if not TB1008ProfessionSkill.Allowed(ID,D.ClassID) or
          ((ID<1900) and (D.WeaponSubtype<>1)) or
          ((ID>=1900) and (D.WeaponSubtype<>2)) then
          raise Exception.Create('Invalid profession class/weapon');
        D.ActionID:=V.GetValue<Cardinal>('actionId');
        Children:=V.GetValue<TJSONArray>('prerequisites');
        if Children.Count>3 then raise Exception.Create('Too many profession prerequisites');
        D.PrerequisiteCount:=Children.Count;J:=0;
        for P in Children do begin
          D.PrerequisiteIDs[J]:=P.GetValue<Cardinal>('skillId');
          D.PrerequisiteRanks[J]:=P.GetValue<Cardinal>('rank');
          if (D.PrerequisiteIDs[J]=0) or (D.PrerequisiteRanks[J]>5) then
            raise Exception.Create('Invalid profession prerequisite');
          Inc(J);
        end;
        if D.PrerequisiteCount>0 then D.PrerequisiteID:=D.PrerequisiteIDs[0];
        D.RequiredLevel:=W.GetValue<Word>('requiredLevel');
        D.RawRequiredLevel:=W.GetValue<Word>('rawRequiredLevel');
        D.MPCost:=W.GetValue<Integer>('mp');
        D.BonusMin:=Floor(W.GetValue<Double>('damageBonusMin')+0.5);
        D.BonusMax:=Floor(W.GetValue<Double>('damageBonusMax')+0.5);
        D.CooldownMS:=W.GetValue<Cardinal>('cooldownMS');
        D.DurationMS:=W.GetValue<Cardinal>('durationMS');
        D.RawIntervalMS:=W.GetValue<Cardinal>('intervalMS');D.IntervalMS:=D.RawIntervalMS;
        if ID=B1008PhantomThrustID then
          D.IntervalMS:=Root.GetValue<Cardinal>('authoredPhantomIntervalMS');
        D.Range:=W.GetValue<Single>('targetRange');
        D.AreaKind:=W.GetValue<Byte>('areaKindRaw');
        D.AreaRange:=W.GetValue<Single>('areaRangeRaw');
        D.AreaSecondaryRange:=W.GetValue<Single>('areaSecondaryRangeRaw');
        D.HitCount:=W.GetValue<Cardinal>('hitCountRaw');
        D.PeriodicDamage:=W.GetValue<Integer>('periodicDamage');
        D.SlowPercent:=W.GetValue<Integer>('slowPercent');
        D.StunMS:=W.GetValue<Cardinal>('stunMS');
        D.StunChanceKnown:=W.GetValue<Boolean>('stunChanceKnown');
        D.StunChanceBasisPoints:=W.GetValue<Cardinal>('stunChanceBasisPoints');
        // Native type23 label identifies received damage absorption.
        D.AbsorbPercent:=W.GetValue<Integer>('absorbPercent');
        D.AttackPercent:=W.GetValue<Integer>('attackPercent');
        D.AttackSpeedPercent:=W.GetValue<Integer>('attackSpeedPercent');
        D.DefensePenaltyPercent:=W.GetValue<Integer>('defensePenaltyPercent');
        Children:=W.GetValue<TJSONArray>('modifiers');
        if Children.Count>4 then raise Exception.Create('Too many profession modifiers');
        D.RawModifierCount:=Children.Count;J:=0;
        for P in Children do begin
          D.RawModifiers[J].DataID:=P.GetValue<Cardinal>('dataId');
          D.RawModifiers[J].TypeCode:=P.GetValue<Cardinal>('typeCode');
          D.RawModifiers[J].Value18:=P.GetValue<Double>('rawDouble18');
          D.RawModifiers[J].Value20:=P.GetValue<Double>('rawDouble20');Inc(J);
        end;
        if (D.RequiredLevel=0) or (D.MPCost<0) or (D.BonusMin<0) or
          (D.BonusMax<D.BonusMin) or (D.AreaKind>2) or
          (D.StunChanceBasisPoints>10000) then
          raise Exception.Create('Invalid profession rank data');
        // User-authored physical mastery balance; type7 is retained above.
        if ID=B1008SwordMasteryID then D.AttackBonus:=Rank
        else if ID=B1008PolearmMasteryID then D.AttackPercent:=Rank;
        FRows[I,Rank]:=D;Seen[I,Rank]:=True;
      end;
    end;
    for I:=0 to 13 do for J:=1 to 5 do
      if not Seen[I,J] then raise Exception.Create('Missing profession rank');
  finally Root.Free;end;
end;

class function TB1008ProfessionCatalog.Get(ID,Rank:Cardinal):TB1008ProfessionSkill;
begin
  Result:=FRows[SkillIndex(ID),Rank];
end;

procedure TB1008WindBleed.Start(ARank:Cardinal;NowTick:UInt64);
begin
  if (ARank<1) or (ARank>5) then
    raise EArgumentOutOfRangeException.Create('Wind Blade rank outside 1..5');
  if NowTick>High(UInt64)-12000 then
    raise EArgumentOutOfRangeException.Create('Wind Blade clock overflow');
  FRank:=ARank;FRemainingTicks:=6;
  FNextTick:=NowTick+2000;FUntilTick:=NowTick+12000;
end;

function TB1008WindBleed.TakeDue(NowTick:UInt64;out Damage:Integer):Boolean;
begin
  Damage:=0;
  Result:=(FRemainingTicks>0) and (NowTick>=FNextTick);
  if not Result then Exit;
  Damage:=Integer(FRank)+1;
  Dec(FRemainingTicks);
  if FRemainingTicks=0 then FNextTick:=0
  else Inc(FNextTick,2000);
end;

procedure TB1008WindBleed.Clear;
begin
  FRank:=0;FRemainingTicks:=0;FNextTick:=0;FUntilTick:=0;
end;

end.
