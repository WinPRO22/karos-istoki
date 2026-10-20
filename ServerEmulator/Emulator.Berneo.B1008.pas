unit Emulator.Berneo.B1008;

interface
uses System.SysUtils, Emulator.Content;
type
  TB1008BerneoMob = record
    Definition:TEmulatorMobDefinition;
    ClientID:Cardinal;
    Level,BaseEXP,CaratMin,CaratMax:Integer;
    LegacyHP,LegacyDamage:Integer;
    PlayerMeleeRange,ClientRadius:Single;
    IDs,Weights:array[0..2] of TArray<Integer>;
  end;
  TB1008Berneo = class
  private
    class var FMobs:TArray<TB1008BerneoMob>;
    class var FGroups:TArray<TEmulatorSpawnDefinition>;
    class var FTemplates:array[0..3999] of Cardinal;
    class var FLevels:array[0..3999] of Word;
  public
    class constructor Create;
    class function Mobs:TArray<TB1008BerneoMob>;static;
    class function Groups:TArray<TEmulatorSpawnDefinition>;static;
    class function Mob(ID:Cardinal):TB1008BerneoMob;static;
    class function TemplateForHandle(Handle:Cardinal):Cardinal;static;
    class function LevelForHandle(Handle:Cardinal):Word;static;
    class function MemberHandle(Template:Cardinal;Member:Integer):Cardinal;static;
  end;
implementation
uses System.JSON,System.IOUtils,Emulator.Items.B1008,Emulator.MonsterBalance.B1008;

class constructor TB1008Berneo.Create;
const Names:array[0..2] of string=('ordinary','craft','potion');
var Root:TJSONObject;V:TJSONValue;Rows,A,W:TJSONArray;M:TB1008BerneoMob;
  G:TEmulatorSpawnDefinition;I,J,K,Total,SpiderHandle,OtherHandle:Integer;
  D:TB1008ItemDefinition;
  Stats:TB1008MonsterStats;
begin
  Root:=TJSONObject.ParseJSONValue(TFile.ReadAllText(TB1008Items.DataPath('berneo-v1.json'),TEncoding.UTF8)) as TJSONObject;
  if Root=nil then raise Exception.Create('Missing Berneo content');
  try
    if Root.GetValue<string>('build')<>'b1008' then raise Exception.Create('Wrong Berneo build');
    Rows:=Root.GetValue<TJSONArray>('monsters');SetLength(FMobs,Rows.Count);I:=0;
    for V in Rows do begin
      M:=Default(TB1008BerneoMob);
      M.Definition.BuildID:='b1008';M.Definition.MobID:=V.GetValue<Cardinal>('mobId');
      M.Definition.Name:=V.GetValue<string>('name');M.ClientID:=V.GetValue<Cardinal>('clientId');
      M.Level:=V.GetValue<Integer>('level');M.BaseEXP:=V.GetValue<Integer>('baseEXP');
      M.PlayerMeleeRange:=V.GetValue<Double>('playerMeleeRange');
      if (M.PlayerMeleeRange<1) or (M.PlayerMeleeRange>100) then raise Exception.Create('Invalid melee admission range');
      // Original NPCInfo+30, uint32 radius read by 0x4DAF61.
      M.ClientRadius:=V.GetValue<Integer>('clientRadius');
      if (M.ClientRadius<1) or (M.ClientRadius>100) then raise Exception.Create('Invalid client monster radius');
      M.CaratMin:=V.GetValue<Integer>('caratMin');M.CaratMax:=V.GetValue<Integer>('caratMax');
      M.LegacyHP:=V.GetValue<Integer>('maxHP');M.LegacyDamage:=V.GetValue<Integer>('attackDamage');
      Stats:=TB1008MonsterBalance.AtLevel(M.Level);
      M.Definition.MaxHP:=Stats.HP*V.GetValue<Integer>('hpMultiplier',1);
      M.Definition.AttackMin:=Stats.AttackMin;
      M.Definition.AttackDamage:=Stats.AttackMax;M.Definition.PhysicalDefense:=Stats.Defense;
      M.Definition.AttackSpeed:=V.GetValue<Double>('attackSpeed');
      M.Definition.MovementSpeed:=V.GetValue<Double>('movementSpeed');M.Definition.ChaseSpeed:=V.GetValue<Double>('chaseSpeed');
      M.Definition.PatrolRadius:=V.GetValue<Double>('patrolRadius');M.Definition.AttackRange:=V.GetValue<Double>('attackRange');
      M.Definition.LeashRadius:=V.GetValue<Double>('leashRadius');M.Definition.RespawnMS:=V.GetValue<Integer>('respawnMS');
      M.Definition.Enabled:=True;M.Definition.Revision:=1;
      ValidateMobDefinition(M.Definition);
      if (M.Level<1) or (M.Level>20) or (M.BaseEXP<=0) or (M.CaratMin<=0) or
        (M.CaratMax<M.CaratMin) or (M.CaratMax>1000000) then raise Exception.Create('Invalid Berneo reward');
      for K:=0 to I-1 do if FMobs[K].Definition.MobID=M.Definition.MobID then raise Exception.Create('Duplicate Berneo mob');
      for J:=0 to 2 do begin
        A:=V.GetValue<TJSONArray>(Names[J]);W:=V.GetValue<TJSONArray>(Names[J]+'Weights');
        if A.Count<>W.Count then raise Exception.Create('Berneo pool/weight mismatch');
        SetLength(M.IDs[J],A.Count);SetLength(M.Weights[J],A.Count);
        for K:=0 to A.Count-1 do begin
          M.IDs[J][K]:=StrToInt(A.Items[K].Value);M.Weights[J][K]:=StrToInt(W.Items[K].Value);
          D:=TB1008Items.Get(M.IDs[J][K]);
          if (D.Slot<>0) or (D.ID=999999) or ((J=2)<>TB1008Items.IsPotion(D.ID)) or
            (M.Weights[J][K]<1) or (M.Weights[J][K]>10000) then raise Exception.Create('Invalid Berneo drop item');
          for var P:=0 to K-1 do if M.IDs[J][P]=M.IDs[J][K] then raise Exception.Create('Duplicate Berneo pool item');
        end;
      end;
      FMobs[I]:=M;Inc(I);
    end;
    Rows:=Root.GetValue<TJSONArray>('groups');SetLength(FGroups,Rows.Count);I:=0;Total:=0;
    SpiderHandle:=1000;OtherHandle:=2000;
    for V in Rows do begin
      G:=Default(TEmulatorSpawnDefinition);G.BuildID:='b1008';
      G.SpawnID:=V.GetValue<Cardinal>('spawnId');G.EntityHandle:=V.GetValue<Cardinal>('templateHandle');
      G.MobID:=V.GetValue<Cardinal>('mobId');G.MapID:=V.GetValue<Cardinal>('mapId');
      G.X:=V.GetValue<Double>('x');G.Z:=V.GetValue<Double>('z');G.Y:=V.GetValue<Double>('y');
      G.Heading:=V.GetValue<Double>('heading');G.Population:=V.GetValue<Integer>('population');
      G.SpawnRadius:=V.GetValue<Double>('radius');G.Enabled:=True;G.Revision:=1;
      ValidateSpawnDefinition(G);Mob(G.MobID);
      if (G.EntityHandle<1) or (G.EntityHandle>198) or (G.SpawnID<>G.EntityHandle) or
        (G.MapID<>19003) or (G.Population>100) or (FTemplates[G.EntityHandle]<>0) then
        raise Exception.Create('Invalid Berneo source handle');
      FTemplates[G.EntityHandle]:=G.EntityHandle;
      FLevels[G.EntityHandle]:=Mob(G.MobID).Level;
      for J:=1 to G.Population-1 do begin
        if G.MobID=120 then begin K:=SpiderHandle;Inc(SpiderHandle);end
        else begin K:=OtherHandle;Inc(OtherHandle);end;
        if K>High(FTemplates) then raise Exception.Create('Berneo handle capacity exceeded');
        FTemplates[K]:=G.EntityHandle;
        FLevels[K]:=FLevels[G.EntityHandle];
      end;
      Inc(Total,G.Population);FGroups[I]:=G;Inc(I);
    end;
    if (Length(FMobs)<>18) or (Length(FGroups)<>169) or (Total<>955) or (SpiderHandle<>1091) then
      raise Exception.Create('Incomplete Berneo content');
  finally Root.Free;end;
end;
class function TB1008Berneo.Mobs:TArray<TB1008BerneoMob>;
begin Result:=Copy(FMobs);end;
class function TB1008Berneo.Groups:TArray<TEmulatorSpawnDefinition>;
begin Result:=Copy(FGroups);end;
class function TB1008Berneo.Mob(ID:Cardinal):TB1008BerneoMob;
var M:TB1008BerneoMob;
begin
  for M in FMobs do if M.Definition.MobID=ID then Exit(M);
  raise EArgumentException.CreateFmt('Unknown Berneo mob %u',[ID]);
end;
class function TB1008Berneo.TemplateForHandle(Handle:Cardinal):Cardinal;
begin
  Result:=0;if Handle<=High(FTemplates) then Result:=FTemplates[Handle];
end;
class function TB1008Berneo.MemberHandle(Template:Cardinal;Member:Integer):Cardinal;
begin
  if (Member=0) and (TemplateForHandle(Template)=Template) then Exit(Template);
  for Result:=1000 to High(FTemplates) do if FTemplates[Result]=Template then begin
    Dec(Member);if Member=0 then Exit;
  end;
  raise EArgumentException.Create('Population exceeds original Berneo group');
end;
class function TB1008Berneo.LevelForHandle(Handle:Cardinal):Word;
begin
  Result:=0;if Handle<=High(FLevels) then Result:=FLevels[Handle];
end;
end.
