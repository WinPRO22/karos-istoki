program B1008ProfessionEffectsTests;
{$APPTYPE CONSOLE}

uses System.SysUtils,Emulator.ProfessionSkills.B1008,Emulator.ProfessionEffects.B1008,
  Emulator.Skills.B1008,Emulator.Protocol.B1008,Emulator.FlettaProc.B1008;

const ActiveIDs:array[0..11] of Cardinal=(1101,1103,1104,1105,1106,1107,
  1901,1903,1904,1905,1906,1907);

procedure Check(B:Boolean;const Msg:string);
begin if not B then raise Exception.Create(Msg);end;

procedure EffectLifecycle;
var E,F:TB1008ProfessionEffect;Damage,I,Count,Total:Integer;R:Cardinal;
  Failed:Boolean;Edge:UInt64;
begin
  E:=Default(TB1008ProfessionEffect);Damage:=99;
  Check(not E.Active(0) and not E.TakeDue(High(UInt64),Damage) and (Damage=0),
    'Empty profession effect ticked');
  for R:=1 to 5 do begin
    E.Start(1106,R,10000);
    Check((E.SkillID=1106) and (E.Rank=R) and (E.UntilTick=15000) and
      (E.NextTick=11000) and (E.RemainingTicks=5),'Slater start profile');Total:=0;
    for I:=1 to 5 do begin
      Check(not E.TakeDue(10000+UInt64(I)*1000-1,Damage) and (Damage=0),'Slater tick before boundary');
      Check(E.TakeDue(10000+UInt64(I)*1000,Damage) and (Damage=5),'Slater exact-boundary tick');
      Inc(Total,Damage);
      Check(not E.TakeDue(10000+UInt64(I)*1000,Damage),'Slater boundary replay');
    end;
    Check((Total=25) and (E.RemainingTicks=0) and (E.SkillID=1106) and (E.Rank=R) and
      not E.Active(15000) and not E.TakeDue(High(UInt64),Damage),
      'Slater exhaustion lost removal identity or ticked again');
    E.Start(1906,R,10000);
    Check(E.Active(14999) and not E.Active(15000) and (E.RemainingTicks=5) and (E.NextTick=11000),
      'Phantom user-approved periodic start');Total:=0;
    for I:=1 to 5 do begin
      Check(not E.TakeDue(10000+UInt64(I)*1000-1,Damage),'Phantom periodic damage fired early');
      Check(E.TakeDue(10000+UInt64(I)*1000,Damage) and (Damage=Integer(R)+1),'Phantom approved tick magnitude');
      Inc(Total,Damage);Check(not E.TakeDue(10000+UInt64(I)*1000,Damage),'Phantom repeated due tick');
    end;
    Check((Total=5*(Integer(R)+1)) and not E.TakeDue(High(UInt64),Damage) and (Damage=0),
      'Phantom lost/repeated approved periodic damage');
    E.Start(1901,R,10000);Count:=0;Total:=0;
    while E.TakeDue(22000,Damage) do begin Inc(Count);Inc(Total,Damage);end;
    Check((Count=6) and (Total=6*(Integer(R)+1)) and (E.UntilTick=22000),
      'Generic Wind Blade diverged from six-tick contract');
  end;
  E.Start(1106,1,1000);Count:=0;
  while E.TakeDue(4999,Damage) do Inc(Count);
  Check((Count=3) and (E.RemainingTicks=2) and (E.NextTick=5000),'Delayed Slater poll drifted');
  Check(E.TakeDue(5000,Damage) and E.TakeDue(High(UInt64),Damage) and
    not E.TakeDue(High(UInt64),Damage),'Delayed Slater lost/cycled remaining ticks');
  E.Start(1106,1,1000);Check(E.TakeDue(2000,Damage),'Refresh fixture');
  E.Start(1901,5,2500);
  Check((E.SkillID=1901) and (E.Rank=5) and (E.RemainingTicks=6) and
    not E.TakeDue(4499,Damage) and E.TakeDue(4500,Damage) and (Damage=6),
    'Effect refresh retained previous skill/rank/schedule');
  E.Start(1105,2,1000);F:=Default(TB1008ProfessionEffect);F.Start(1107,3,2000);
  Check(E.Active(21000) and F.Active(21000) and (E.SkillID=1105) and (F.SkillID=1107),
    'Independent Revenge and Death Leap slots collided');
  Check(E.Active(22000) and not F.Active(22000),'Independent buff expiry collided');
  F.Clear;Check(E.Active(30000) and (E.Rank=2) and not F.Active(30000),'Clearing one buff cleared another');
  E.Clear;E.Clear;
  Check((E.SkillID=0) and (E.Rank=0) and (E.UntilTick=0) and (E.NextTick=0) and
    (E.RemainingTicks=0) and not E.TakeDue(High(UInt64),Damage),'Effect cleanup retained transient state');
  E.Start(1105,2,1000);Failed:=False;
  try E.Start(1105,0,2000);except on X:EArgumentException do Failed:=True;end;
  Check(Failed and (E.SkillID=1105) and (E.Rank=2) and (E.UntilTick=31000),
    'Invalid rank refresh mutated existing effect');
  Failed:=False;
  try E.Start(9999,1,2000);except on X:EArgumentException do Failed:=True;end;
  Check(Failed and (E.Rank=2),'Unsupported effect refresh mutated existing effect');
  Failed:=False;
  try E.Start(1105,1,High(UInt64)-29999);except on X:EArgumentOutOfRangeException do Failed:=True;end;
  Check(Failed and (E.SkillID=1105) and (E.Rank=2) and (E.UntilTick=31000),
    'Overflow refresh accepted or mutated existing effect');
  E.Start(1105,1,High(UInt64)-30000);
  Check(E.Active(High(UInt64)-1) and not E.Active(High(UInt64)),'Buff maximum clock boundary');
  Edge:=High(UInt64)-5000;E.Start(1106,1,Edge);Count:=0;
  for I:=1 to 5 do begin
    Check(E.TakeDue(Edge+UInt64(I)*1000,Damage) and (Damage=5),'Slater maximum-clock tick');Inc(Count);
  end;
  Check((Count=5) and (E.RemainingTicks=0) and (E.NextTick=0) and
    not E.TakeDue(High(UInt64),Damage),'Exhausted maximum-clock schedule overflowed');
  E.Start(1901,5,High(UInt64)-12000);Count:=0;
  while E.TakeDue(High(UInt64),Damage) do Inc(Count);
  Check((Count=6) and (E.NextTick=0),'Wind final next tick overflowed');
end;

procedure CooldownAdmission;
var C:TB1008AttackSkillCast;S:TB1008ProfessionSkill;ID,Target,Stamp:Cardinal;
  I,MP,Before:Integer;NowTick:UInt64;
begin
  C:=Default(TB1008AttackSkillCast);MP:=10000;Stamp:=1;
  for I:=0 to High(ActiveIDs) do begin
    ID:=ActiveIDs[I];S:=TB1008ProfessionSkill.Get(ID,1);Target:=120;
    if TB1008ProfessionSkill.IsSelf(ID) then Target:=1;NowTick:=1000+UInt64(I)*2;
    Check(C.Prepare(Stamp,Target,NowTick,MP,1,ID),'Other profession cooldown blocked first use');
    Check(C.PreparedSkillID=ID,'Prepared skill ID lost action alias identity');Inc(Stamp);Before:=MP;
    Check(C.Start(Stamp,Target,NowTick+1,MP,ID) and (MP=Before-S.MPCost) and
      (C.ActiveSkillID=ID) and (C.ActiveRank=1),'Active cast did not capture/debit prepared skill');Inc(Stamp);
  end;
  for I:=0 to High(ActiveIDs) do begin
    ID:=ActiveIDs[I];Target:=120;if TB1008ProfessionSkill.IsSelf(ID) then Target:=1;
    Check(not C.Prepare(Stamp,Target,3000,MP,1,ID),'Profession cooldown reset/collided');Inc(Stamp);
  end;
  for I:=0 to High(ActiveIDs) do begin
    ID:=ActiveIDs[I];S:=TB1008ProfessionSkill.Get(ID,5);Target:=120;
    if TB1008ProfessionSkill.IsSelf(ID) then Target:=1;
    C:=Default(TB1008AttackSkillCast);MP:=S.MPCost;
    Check(not C.Prepare(1,Target,1000,MP-1,5,ID),'Active rank-five mana gate');
    Check(C.Prepare(1,Target,1000,MP,5,ID) and C.Start(2,Target,1001,MP,ID) and
      (MP=0) and (C.ActiveRank=5),'Active rank-five snapshot/debit');
    C.Cancel;MP:=S.MPCost;
    Check(not C.Prepare(3,Target,1000+S.CooldownMS,MP,5,ID),'Cancel reset profession cooldown');
    Check(C.Prepare(3,Target,1001+S.CooldownMS,MP,5,ID),'Profession cooldown exact boundary');
    C.Cancel;
  end;
  Check((TB1008ProfessionSkill.Get(1107,1).ActionID=1019) and
    (TB1008ProfessionSkill.Get(1905,1).ActionID=1019) and
    (TB1008AttackSkillStats.SelfFromAction(1019)=1107),'Original 1019 alias contract');
  C:=Default(TB1008AttackSkillCast);MP:=100;
  Check(C.Prepare(1,1,1000,MP,1,1905) and (C.PreparedSkillID=1905),'Polearm Revenge preparation alias');
  Before:=MP;Check(not C.Start(2,1,1001,MP,1107) and (MP=Before),'1019 alias consumed wrong skill');
  Check(not C.RejectStart(2,1,1107) and C.Start(2,1,1001,MP,1905) and
    (C.ActiveSkillID=1905),'Wrong alias cancelled matching preparation');
  Check(C.Prepare(3,1,1002,MP,1,1107) and (C.PreparedSkillID=1107) and
    C.Start(4,1,1003,MP,1107),'Shared animation merged distinct skill cooldowns');
  C:=Default(TB1008AttackSkillCast);MP:=100;
  Check(not C.Prepare(1,1,1000,MP,1,1102) and not C.Prepare(1,1,1000,MP,1,1902),
    'Passive entered active cooldown/admission');
  Check(not C.Prepare(1,120,1000,MP,1,1903),'Self-centered Stun Attack prepared selected target');
end;

procedure GenericEffectWire;
var P:TBytes;I:Integer;Failed:Boolean;Kind:Byte;Actor,ID,Rank,Duration:Cardinal;
begin
  for I:=0 to 1 do begin
    P:=TB1008SkillWire.BuildProfessionEffect($12345678,I,$01234567,1106,5,5000,True);
    Check((Length(P)=26) and (P[0]=5) and (P[1]=9) and (P[6]=I) and
      (TB1008Wire.ReadBE32(P,2)=$12345678) and (TB1008Wire.ReadBE32(P,7)=$01234567) and
      (P[11]=1) and (P[12]=0) and (P[13]=1) and
      (TB1008Wire.ReadBE32(P,14)=1106) and (TB1008Wire.ReadBE32(P,18)=5) and
      (TB1008Wire.ReadBE32(P,22)=5),'Generic profession add actor/endian/seconds');
    P:=TB1008SkillWire.BuildProfessionEffect(9,I,123,1106,5,5000,False);
    Check((Length(P)=26) and (P[6]=I) and (P[11]=0) and
      (TB1008Wire.ReadBE32(P,7)=123) and (TB1008Wire.ReadBE32(P,14)=1106) and
      (TB1008Wire.ReadBE32(P,18)=5) and (TB1008Wire.ReadBE32(P,22)=0),
      'Generic profession remove omitted identity or retained add duration');
  end;
  for I:=0 to 6 do begin
    Kind:=0;Actor:=1;ID:=1105;Rank:=1;Duration:=30000;
    case I of
      0:Kind:=2;1:Actor:=0;2:ID:=9999;3:ID:=1102;
      4:Rank:=0;5:Rank:=6;6:Duration:=1001;
    end;
    Failed:=False;
    try P:=TB1008SkillWire.BuildProfessionEffect(1,Kind,Actor,ID,Rank,Duration,True);
    except on E:EKarosProtocol do Failed:=True;end;
    Check(Failed,'Malformed profession effect accepted');
  end;
end;

procedure ExpandedLearnedList;
var Skills:TArray<TB1008LearnedSkill>;P:TBytes;I:Integer;Value:Cardinal;Failed:Boolean;
begin
  SetLength(Skills,14);
  for I:=0 to 5 do begin Skills[I].ID:=1001+Cardinal(I);Skills[I].Rank:=5;end;
  for I:=0 to 6 do begin Skills[I+6].ID:=1101+Cardinal(I);Skills[I+6].Rank:=5;end;
  Skills[13].ID:=B1008TornadoID;Skills[13].Rank:=1;
  P:=TB1008SkillWire.BuildList(7,Skills);
  Check((Length(P)=124) and (P[10]=0) and (P[11]=14),
    'Full base/profession/Fletta learned list truncated');
  for I:=0 to 13 do begin
    Move(P[12+I*4],Value,4);Check(Value=Skills[I].ID,'Full skill list ID array/endian');
    Move(P[12+14*4+I*4],Value,4);Check(Value=Skills[I].Rank,'Full skill list rank array/endian');
  end;
  SetLength(Skills,15);Skills[14].ID:=B1008RockStraightID;Skills[14].Rank:=1;Failed:=False;
  try P:=TB1008SkillWire.BuildList(8,Skills);except on E:EKarosProtocol do Failed:=True;end;
  Check(Failed,'Beyond supported learned list capacity accepted');
end;

begin
  try
    EffectLifecycle;CooldownAdmission;GenericEffectWire;ExpandedLearnedList;
    Writeln('PASS: independent effects/cooldowns, approved Phantom ticks, 1019 admission, wire');
  except on E:Exception do begin
    Writeln('FAIL: ',E.ClassName,': ',E.Message);Halt(1);
  end;end;
end.
