unit Emulator.Regen.B1008;

interface

type
  // Session-local monotonic timer. No offline or catch-up healing.
  TB1008Regeneration = record
  private
    FPeaceful, FHasFlags, FArmed: Boolean;
    FFlagsTimestamp: Cardinal;
    FLastTick, FDueTick: UInt64;
    FHPFraction,FMPFraction: Double;
  public
    property Peaceful:Boolean read FPeaceful;
    function ObserveState(Timestamp: Cardinal; State: Byte): Boolean;
    procedure EnterCombat;
    procedure ResetPeaceful;
    function Poll(NowTick: UInt64; Blocked: Boolean; IntervalMS: Cardinal;
      HPAmount,MPAmount:Double;MaxHP,MaxMP: Integer; var HP,MP: Integer): Boolean;
  end;

implementation

uses System.SysUtils, System.Math;

function TB1008Regeneration.ObserveState(Timestamp: Cardinal; State: Byte): Boolean;
var Delta:UInt64;
begin
  Result:=False;
  if FHasFlags then begin
    Delta:=(UInt64(Timestamp)+$100000000-UInt64(FFlagsTimestamp)) and $FFFFFFFF;
    if (Delta=0) or (Delta>=$80000000) then Exit;
  end;
  FHasFlags:=True;FFlagsTimestamp:=Timestamp;
  // Sender 0x4FF026 serializes actorData+5C as state 0/1 into 03/02.
  // State 2 has a separate sender; do not assume sitting regen semantics.
  // Unknown states fail closed. FlagB is unrelated and intentionally ignored.
  if FPeaceful<>(State=0) then FArmed:=False;
  FPeaceful:=State=0;Result:=True;
end;

procedure TB1008Regeneration.EnterCombat;
begin FPeaceful:=False;FArmed:=False;end;

procedure TB1008Regeneration.ResetPeaceful;
begin
  Self:=Default(TB1008Regeneration);FPeaceful:=True;
end;

function TB1008Regeneration.Poll(NowTick: UInt64; Blocked: Boolean;
  IntervalMS: Cardinal; HPAmount,MPAmount:Double;MaxHP,MaxMP: Integer; var HP,MP: Integer): Boolean;
var OldHP,OldMP,Gain:Integer;
begin
  Result:=False;
  if (IntervalMS<250) or IsNan(HPAmount) or IsNan(MPAmount) or
    IsInfinite(HPAmount) or IsInfinite(MPAmount) or
    (HPAmount<0) or (MPAmount<0) or (HPAmount>1000000) or (MPAmount>1000000) or
    (HP<0) or (MP<0) or (MaxHP<=0) or (MaxMP<0) or (HP>MaxHP) or (MP>MaxMP) then
    raise EArgumentException.Create('Invalid regeneration bounds');
  if NowTick<FLastTick then FArmed:=False;
  FLastTick:=NowTick;
  if HP=MaxHP then FHPFraction:=0;
  if MP=MaxMP then FMPFraction:=0;
  if Blocked or not FPeaceful or (HP=0) or ((HP=MaxHP) and (MP=MaxMP)) then begin
    FArmed:=False;Exit;
  end;
  if not FArmed then begin FArmed:=True;FDueTick:=NowTick+IntervalMS;Exit;end;
  if NowTick<FDueTick then Exit;
  FDueTick:=NowTick+IntervalMS;
  OldHP:=HP;OldMP:=MP;
  // Carry fractional Yin regeneration across ticks, never bank healing at cap.
  FHPFraction:=FHPFraction+HPAmount;Gain:=Trunc(FHPFraction+1E-9);
  FHPFraction:=Max(0.0,FHPFraction-Gain);Inc(HP,Min(Gain,MaxHP-HP));
  FMPFraction:=FMPFraction+MPAmount;Gain:=Trunc(FMPFraction+1E-9);
  FMPFraction:=Max(0.0,FMPFraction-Gain);Inc(MP,Min(Gain,MaxMP-MP));
  if HP=MaxHP then FHPFraction:=0;
  if MP=MaxMP then FMPFraction:=0;
  Result:=(HP<>OldHP) or (MP<>OldMP);
end;

end.
