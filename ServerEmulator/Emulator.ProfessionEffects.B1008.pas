unit Emulator.ProfessionEffects.B1008;

interface

uses System.SysUtils,Emulator.ProfessionSkills.B1008;

type
  // Transient, independent effect slots; never stored in a character save.
  TB1008ProfessionEffect=record
    SkillID,Rank:Cardinal;
    UntilTick,NextTick:UInt64;
    RemainingTicks:Integer;
    procedure Start(ID,ARank:Cardinal;NowTick:UInt64);
    function Active(NowTick:UInt64):Boolean;
    function TakeDue(NowTick:UInt64;out Damage:Integer):Boolean;
    procedure Clear;
  end;

implementation

procedure TB1008ProfessionEffect.Start(ID,ARank:Cardinal;NowTick:UInt64);
var D:TB1008ProfessionSkill;
begin
  D:=TB1008ProfessionSkill.Get(ID,ARank);
  if NowTick>High(UInt64)-D.DurationMS then
    raise EArgumentOutOfRangeException.Create('Profession effect clock overflow');
  Clear;SkillID:=ID;Rank:=ARank;UntilTick:=NowTick+D.DurationMS;
  // A missing interval is not permission to invent a periodic damage rule.
  if (D.IntervalMS>0) and (D.PeriodicDamage>0) then begin
    RemainingTicks:=D.DurationMS div D.IntervalMS;
    NextTick:=NowTick+D.IntervalMS;
  end;
end;

function TB1008ProfessionEffect.Active(NowTick:UInt64):Boolean;
begin Result:=(SkillID<>0) and (NowTick<UntilTick);end;

function TB1008ProfessionEffect.TakeDue(NowTick:UInt64;out Damage:Integer):Boolean;
var D:TB1008ProfessionSkill;
begin
  Damage:=0;Result:=(RemainingTicks>0) and (NowTick>=NextTick);
  if not Result then Exit;
  D:=TB1008ProfessionSkill.Get(SkillID,Rank);Damage:=D.PeriodicDamage;
  Dec(RemainingTicks);if RemainingTicks=0 then NextTick:=0 else Inc(NextTick,D.IntervalMS);
end;

procedure TB1008ProfessionEffect.Clear;
begin Self:=Default(TB1008ProfessionEffect);end;

end.
