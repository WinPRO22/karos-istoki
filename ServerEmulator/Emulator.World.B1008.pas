unit Emulator.World.B1008;

interface

uses System.SysUtils;

const B1008BerneoMapID = 19003;
  // Diagnostic values, not reconstructed historical class/buff speeds.
  B1008ProbeSpeedA: Single = 150;
  B1008ProbeSpeedB: Single = 300;
  // Player-only movement at half the diagnostic baseline. Keep NPC probes
  // and attack playback independent from this tuning.
  B1008PlayerMovementScale = 0.5;
  // 0x4EC784 uses characterData+0x630 as the playback multiplier for the
  // normal attack action range. A zero placeholder collapses that action.
  B1008ProbeAttackSpeed: Single = 1.0;
  // Temporary full bars for protocol testing, NOT historical level-1 balance.
  B1008ProbeHP: Integer = 5000;
  B1008ProbeMP: Integer = 150;
  B1008SpiderHandle = 120;
  B1008SecondSpiderHandle = 119;
  B1008SpiderHandles: array[0..9] of Cardinal =
    (107,108,109,118,119,120,132,133,134,135);
  // BERNEO65.NPC version-5 records: the trailing integer/float pairs are
  // consistently shaped as population and distribution radius. Live group
  // rendering remains the final semantic check, so the source values stay
  // separate from the independently confirmed patrol radius.
  B1008SpiderGroupPopulations: array[0..9] of Integer =
    (10,10,10,10,10,5,12,12,10,12);
  B1008SpiderGroupRadii: array[0..9] of Single =
    (300,300,300,300,300,150,300,300,500,500);
  B1008SpiderPopulationCount = 101;
  B1008GeneratedSpiderHandleBase = 1000;
  B1008GeneratedSpiderHandleLast = 1090;
  B1008SpiderProbeHP: Integer = 500; // Diagnostic only, extended for animation tests.

var
  B1008PlayerSpeedA: Single = 150 * B1008PlayerMovementScale;
  B1008PlayerSpeedB: Single = 300 * B1008PlayerMovementScale;

// Test host startup only, before sessions/threads exist. Never saved to a hero.
procedure ConfigureB1008TestPlayerSpeed(Multiplier: Integer);
function IsB1008SpiderHandle(AHandle: Cardinal): Boolean;
function IsB1008SpiderGroupHandle(AHandle: Cardinal): Boolean;
function B1008SpiderGroupPopulation(AHandle: Cardinal): Integer;
function B1008SpiderGroupRadius(AHandle: Cardinal): Single;

type
  TB1008StartCharacter = record
    Timestamp, CharacterID, Option: Cardinal;
  end;
  TB1008Regen = record
    Timestamp, CharacterID: Cardinal;
    Kind, Option: Byte;
    X, Z, Y, Heading: Single;
  end;
  TB1008Movement = record
    Timestamp, CharacterID: Cardinal;
    Kind, Mode, FlagA, FlagB: Byte;
    FromX, FromZ, FromY, ToX, ToZ, ToY, Parameter: Single;
  end;
  TB1008World = class
  public
    class function ParseStart(const Payload: TBytes): TB1008StartCharacter; static;
    class function BuildCharacterInfoProbe(const Preview: TBytes;
      Timestamp: Cardinal): TBytes; static;
    class function BuildZoneProbe(Timestamp: Cardinal): TBytes; static;
    class function ParseRegen(const Payload: TBytes): TB1008Regen; static;
    class function ParseMovement(const Payload: TBytes): TB1008Movement; static;
    class function BuildActorMovement(Timestamp: Cardinal; Kind, Mode: Byte;
      ActorID: Cardinal; FromX,FromZ,FromY,ToX,ToZ,ToY,
      Parameter: Single): TBytes; static;
    class function BuildActorDisappear(Timestamp: Cardinal; Kind: Byte;
      ActorID: Cardinal): TBytes; static;
    class function BuildAppearProbe(const Preview: TBytes;
      const Regen: TB1008Regen): TBytes; static;
    class function BuildDomingoAppearProbe(Timestamp: Cardinal): TBytes; static;
    class function BuildSullibentAppearProbe(Timestamp: Cardinal): TBytes; static;
    class function BuildSpiderAppearProbe(Timestamp: Cardinal): TBytes; overload; static;
    class function BuildSpiderAppearProbe(Timestamp: Cardinal; MaxHP: Integer;
      MovementSpeed, AttackSpeed: Single): TBytes; overload; static;
    class function BuildSpiderAppearProbe(Timestamp: Cardinal; MaxHP: Integer;
      MovementSpeed, AttackSpeed, X, Z, Y, Heading: Single): TBytes; overload; static;
    class function BuildSpiderAppearProbe(Timestamp, EntityHandle: Cardinal;
      MaxHP: Integer; MovementSpeed, AttackSpeed, X, Z, Y,
      Heading: Single): TBytes; overload; static;
    class function BuildSpiderAppearProbe(Timestamp, EntityHandle: Cardinal;
      MaxHP: Integer; MovementSpeed, ChaseSpeed, AttackSpeed, X, Z, Y,
      Heading: Single): TBytes; overload; static;
  end;

implementation

uses System.Math, Emulator.Protocol.B1008, Emulator.Berneo.B1008;

procedure ConfigureB1008TestPlayerSpeed(Multiplier: Integer);
begin
  if (Multiplier<1) or (Multiplier>20) then
    raise EArgumentException.Create('Test player speed multiplier must be 1..20');
  B1008PlayerSpeedA:=150*B1008PlayerMovementScale*Multiplier;
  B1008PlayerSpeedB:=300*B1008PlayerMovementScale*Multiplier;
end;

function IsB1008SpiderHandle(AHandle: Cardinal): Boolean;
begin
  Result:=IsB1008SpiderGroupHandle(AHandle) or
    ((AHandle>=B1008GeneratedSpiderHandleBase) and
     (AHandle<=B1008GeneratedSpiderHandleLast));
end;

function IsB1008SpiderGroupHandle(AHandle: Cardinal): Boolean;
var
  Handle: Cardinal;
begin
  Result:=False;
  for Handle in B1008SpiderHandles do
    if Handle=AHandle then Exit(True);
end;

function B1008SpiderGroupPopulation(AHandle: Cardinal): Integer;
var I: Integer;
begin
  for I:=Low(B1008SpiderHandles) to High(B1008SpiderHandles) do
    if B1008SpiderHandles[I]=AHandle then
      Exit(B1008SpiderGroupPopulations[I]);
  Result:=0;
end;

function B1008SpiderGroupRadius(AHandle: Cardinal): Single;
var I: Integer;
begin
  for I:=Low(B1008SpiderHandles) to High(B1008SpiderHandles) do
    if B1008SpiderHandles[I]=AHandle then
      Exit(B1008SpiderGroupRadii[I]);
  Result:=0;
end;

class function TB1008World.BuildActorDisappear(Timestamp: Cardinal;
  Kind: Byte; ActorID: Cardinal): TBytes;
begin
  if (Kind>1) or (ActorID=0) then
    raise EKarosProtocol.Create('Unsupported actor disappearance');
  // Original parser 0x52926A accepts exactly the 11-byte minimum for 04/03.
  // Handler 0x52A3EC resolves kind=1 by BE handle and removes that NPC actor.
  SetLength(Result,11); Result[0]:=4; Result[1]:=3;
  Result[2]:=Byte(Timestamp shr 24); Result[3]:=Byte(Timestamp shr 16);
  Result[4]:=Byte(Timestamp shr 8); Result[5]:=Byte(Timestamp);
  Result[6]:=Kind;
  Result[7]:=Byte(ActorID shr 24); Result[8]:=Byte(ActorID shr 16);
  Result[9]:=Byte(ActorID shr 8); Result[10]:=Byte(ActorID);
end;

class function TB1008World.BuildActorMovement(Timestamp: Cardinal;
  Kind, Mode: Byte; ActorID: Cardinal; FromX,FromZ,FromY,ToX,ToZ,ToY,
  Parameter: Single): TBytes;
var
  Value: Single;
begin
  if (Kind>1) or (Mode>2) or (ActorID=0) then
    raise EKarosProtocol.Create('Unsupported actor movement header');
  Value:=FromX; if IsNan(Value) or IsInfinite(Value) then
    raise EKarosProtocol.Create('Invalid actor movement coordinate');
  Value:=FromZ; if IsNan(Value) or IsInfinite(Value) then
    raise EKarosProtocol.Create('Invalid actor movement coordinate');
  Value:=FromY; if IsNan(Value) or IsInfinite(Value) then
    raise EKarosProtocol.Create('Invalid actor movement coordinate');
  Value:=ToX; if IsNan(Value) or IsInfinite(Value) then
    raise EKarosProtocol.Create('Invalid actor movement coordinate');
  Value:=ToZ; if IsNan(Value) or IsInfinite(Value) then
    raise EKarosProtocol.Create('Invalid actor movement coordinate');
  Value:=ToY; if IsNan(Value) or IsInfinite(Value) then
    raise EKarosProtocol.Create('Invalid actor movement coordinate');
  if IsNan(Parameter) or IsInfinite(Parameter) then
    raise EKarosProtocol.Create('Invalid actor movement parameter');
  SetLength(Result,42); Result[0]:=4; Result[1]:=1;
  Result[2]:=Byte(Timestamp shr 24); Result[3]:=Byte(Timestamp shr 16);
  Result[4]:=Byte(Timestamp shr 8); Result[5]:=Byte(Timestamp);
  Result[6]:=Kind; Result[7]:=Mode;
  Result[8]:=Byte(ActorID shr 24); Result[9]:=Byte(ActorID shr 16);
  Result[10]:=Byte(ActorID shr 8); Result[11]:=Byte(ActorID);
  Move(FromX,Result[12],4); Move(FromZ,Result[16],4); Move(FromY,Result[20],4);
  Move(ToX,Result[24],4); Move(ToZ,Result[28],4); Move(ToY,Result[32],4);
  Move(Parameter,Result[36],4);
end;

class function TB1008World.BuildSpiderAppearProbe(Timestamp: Cardinal): TBytes;
begin
  Result := BuildSpiderAppearProbe(Timestamp, B1008SpiderProbeHP,
    B1008ProbeSpeedA, B1008ProbeAttackSpeed);
end;

class function TB1008World.BuildSpiderAppearProbe(Timestamp: Cardinal;
  MaxHP: Integer; MovementSpeed, AttackSpeed: Single): TBytes;
begin
  Result := BuildSpiderAppearProbe(Timestamp,MaxHP,MovementSpeed,AttackSpeed,
    8669.7763671875,6668.01025390625,604.350341796875,0);
end;

class function TB1008World.BuildSpiderAppearProbe(Timestamp: Cardinal;
  MaxHP: Integer; MovementSpeed, AttackSpeed, X, Z, Y, Heading: Single): TBytes;
begin
  Result:=BuildSpiderAppearProbe(Timestamp,B1008SpiderHandle,MaxHP,
    MovementSpeed,AttackSpeed,X,Z,Y,Heading);
end;

class function TB1008World.BuildSpiderAppearProbe(Timestamp,
  EntityHandle: Cardinal; MaxHP: Integer; MovementSpeed, AttackSpeed,
  X, Z, Y, Heading: Single): TBytes;
begin
  Result:=BuildSpiderAppearProbe(Timestamp,EntityHandle,MaxHP,MovementSpeed,
    MovementSpeed*2,AttackSpeed,X,Z,Y,Heading);
end;

class function TB1008World.BuildSpiderAppearProbe(Timestamp,
  EntityHandle: Cardinal; MaxHP: Integer; MovementSpeed, ChaseSpeed,
  AttackSpeed, X, Z, Y, Heading: Single): TBytes;
var
  TemplateHandle: Cardinal;
  MonsterLevel: Word;
begin
  TemplateHandle:=TB1008Berneo.TemplateForHandle(EntityHandle);
  if TemplateHandle=0 then
    raise EKarosProtocol.Create('Unsupported b1008 monster handle');
  if MaxHP<=0 then raise EKarosProtocol.Create('Spider maximum HP must be positive');
  if IsNan(MovementSpeed) or IsInfinite(MovementSpeed) or (MovementSpeed<0) or
    IsNan(ChaseSpeed) or IsInfinite(ChaseSpeed) or (ChaseSpeed<=0) or
    IsNan(AttackSpeed) or IsInfinite(AttackSpeed) or (AttackSpeed<=0) or
    IsNan(X) or IsInfinite(X) or IsNan(Z) or IsInfinite(Z) or
    IsNan(Y) or IsInfinite(Y) or IsNan(Heading) or IsInfinite(Heading) then
    raise EKarosProtocol.Create('Invalid live spider speed');
  // Offset 8 is the live entity ID; offset $46 is the source NPC/template
  // handle. Generated entities must retain a real Little Spider template or
  // b1008 accepts their movement but has no model to render.
  Result:=BuildDomingoAppearProbe(Timestamp);
  Move(EntityHandle,Result[8],4);
  // Each clone retains its own species/level source, never a spider fallback.
  Move(TemplateHandle,Result[$46],4);
  Move(X,Result[12],4); Move(Z,Result[16],4); Move(Y,Result[20],4);
  Move(Heading,Result[24],4);
  Move(MaxHP,Result[28],4); Move(MaxHP,Result[32],4);
  Move(MovementSpeed,Result[44],4); Move(ChaseSpeed,Result[48],4);
  // The NPC ordinary-attack state uses the same packed playback multiplier
  // as characters. Zero collapses the animation before its hit event.
  Move(AttackSpeed,Result[52],4);
  // 0x4E0ECE: packet+6 -> NPC+0x368; target UI getter 0x4DAE80
  // reads word NPC+0x39A. Thus level is LE16 at packet+0x38.
  // Gage 08/00 copies this field too, preserving level after damage.
  MonsterLevel:=TB1008Berneo.LevelForHandle(EntityHandle);
  Move(MonsterLevel,Result[56],2);
end;

class function TB1008World.BuildSullibentAppearProbe(Timestamp: Cardinal): TBytes;
const
  // BERNEO65.NPC record 43. Domingo is record 28/handle 121, therefore the
  // original Sullibent instance is handle 136. Coordinates use X/Z + 5120.
  Handle: Cardinal = 136;
  X: Single = 8495.849609375;
  Z: Single = 7442.27001953125;
  Y: Single = 587.1530151367188;
begin
  Result:=BuildDomingoAppearProbe(Timestamp);
  Move(Handle,Result[8],4); Move(Handle,Result[$46],4);
  Move(X,Result[12],4); Move(Z,Result[16],4); Move(Y,Result[20],4);
end;

function ReadFiniteSingle(const Data: TBytes; Offset: Integer): Single;
begin
  Move(Data[Offset],Result,4); // Raw little-endian float, serializer 0x4FD516.
  if IsNan(Result) or IsInfinite(Result) then
    raise EKarosProtocol.Create('Non-finite world coordinate');
  if Abs(Result) > 1000000 then
    raise EKarosProtocol.Create('World coordinate outside diagnostic bounds');
end;

class function TB1008World.ParseMovement(const Payload: TBytes): TB1008Movement;
begin
  // 0x4FDCA3: two bytes, BE ID, seven raw LE floats, two bytes.
  if Length(Payload)<>42 then raise EKarosProtocol.Create('Invalid Move size');
  if (Payload[0]<>4) or (Payload[1]<>1) then raise EKarosProtocol.Create('Not a Move request');
  Result.Timestamp := TB1008Wire.ReadBE32(Payload,2);
  Result.Kind := Payload[6]; Result.Mode := Payload[7];
  Result.CharacterID := TB1008Wire.ReadBE32(Payload,8);
  Result.FromX := ReadFiniteSingle(Payload,12); Result.FromZ := ReadFiniteSingle(Payload,16);
  Result.FromY := ReadFiniteSingle(Payload,20); Result.ToX := ReadFiniteSingle(Payload,24);
  Result.ToZ := ReadFiniteSingle(Payload,28); Result.ToY := ReadFiniteSingle(Payload,32);
  Result.Parameter := ReadFiniteSingle(Payload,36);
  Result.FlagA := Payload[40]; Result.FlagB := Payload[41];
end;

class function TB1008World.ParseRegen(const Payload: TBytes): TB1008Regen;
begin
  // 0x4FDC17; caller 0x4FE39C sends kind=0, selected ID, X/Z/Y/heading, option=0.
  if Length(Payload) <> 28 then raise EKarosProtocol.Create('Invalid Regen size');
  if (Payload[0] <> 4) or (Payload[1] <> 0) then
    raise EKarosProtocol.Create('Not a Regen request');
  Result.Timestamp := TB1008Wire.ReadBE32(Payload,2);
  Result.Kind := Payload[6]; Result.CharacterID := TB1008Wire.ReadBE32(Payload,7);
  Result.X := ReadFiniteSingle(Payload,11); Result.Z := ReadFiniteSingle(Payload,15);
  Result.Y := ReadFiniteSingle(Payload,19); Result.Heading := ReadFiniteSingle(Payload,23);
  Result.Option := Payload[27];
end;

procedure PutBE32(var Data: TBytes; Offset: Integer; Value: Cardinal);
begin
  Data[Offset] := Byte(Value shr 24);
  Data[Offset+1] := Byte((Value shr 16) and $FF);
  Data[Offset+2] := Byte((Value shr 8) and $FF);
  Data[Offset+3] := Byte(Value and $FF);
end;

class function TB1008World.ParseStart(const Payload: TBytes): TB1008StartCharacter;
begin
  // 0x4CC212: two BE32 values after the common header. The Play button
  // 0x4CC498 pushes option=0 and the selected character ID.
  if Length(Payload) <> 14 then
    raise EKarosProtocol.Create('Invalid StartChar size (expected 14)');
  if (Payload[0] <> 2) or (Payload[1] <> 4) then
    raise EKarosProtocol.Create('Not a StartChar request');
  Result.Timestamp := TB1008Wire.ReadBE32(Payload,2);
  Result.CharacterID := TB1008Wire.ReadBE32(Payload,6);
  Result.Option := TB1008Wire.ReadBE32(Payload,10);
end;

class function TB1008World.BuildCharacterInfoProbe(const Preview: TBytes;
  Timestamp: Cardinal): TBytes;
begin
  if Length(Preview) < $152 then
    raise EKarosProtocol.Create('StartChar requires a nonempty character preview');
  if (Preview[0] <> 2) or (Preview[1] <> 1) or
    (TB1008Wire.ReadBE32(Preview,7) <> 1) then
    raise EKarosProtocol.Create('Unexpected character preview for StartChar');
  // 0x524C04 checks 0x4B3 bytes. Handler 0x52541C copies:
  // +0xA:0x141 -> character+0x60E; +0x14B:0x228 -> +0x74F;
  // +0x373:0x140 -> +0x4CE. These are packed LE records, not BE fields.
  Result := nil;
  SetLength(Result,$4B3);
  Result[0] := 2; Result[1] := 5;
  PutBE32(Result,2,Timestamp); PutBE32(Result,6,1);
  Move(Preview[15],Result[10],$141);
  // HUD 0x462AE6/0x462B6B reads signed LE current/max pairs at
  // characterData+0x618/+0x61C (HP), +0x620/+0x624 (MP).
  Move(B1008ProbeHP,Result[$14],4);
  Move(B1008ProbeHP,Result[$18],4);
  Move(B1008ProbeMP,Result[$1C],4);
  Move(B1008ProbeMP,Result[$20],4);
  // 0x4EC582 selects characterData+0x628 or +0x62C. Zero stops movement.
  Move(B1008PlayerSpeedA,Result[$24],4);
  Move(B1008PlayerSpeedB,Result[$28],4);
  Move(B1008ProbeAttackSpeed,Result[$2C],4);
  // Diagnostic only: additional stats/skills remain neutral placeholders.
  // No historical HP/MP, speeds, items or world-spawn position are claimed.
end;

class function TB1008World.BuildZoneProbe(Timestamp: Cardinal): TBytes;
begin
  // 0x4FE2E3 requires 15 bytes, 04/04. 0x52A695 reads ID at +6;
  // 0x52A6E3 passes mapID at +10 into map-list selector 0x4E40A4.
  // Byte +14 has no established meaning; use neutral zero for this probe.
  Result := nil; SetLength(Result,15);
  Result[0] := 4; Result[1] := 4;
  PutBE32(Result,2,Timestamp); PutBE32(Result,6,1);
  PutBE32(Result,10,B1008BerneoMapID);
end;

class function TB1008World.BuildAppearProbe(const Preview: TBytes;
  const Regen: TB1008Regen): TBytes;
var I, NameLength: Integer; CheckedInfo: TBytes;
begin
  CheckedInfo := BuildCharacterInfoProbe(Preview,Regen.Timestamp);
  if (Regen.CharacterID<>1) or (Regen.Kind<>0) or (Regen.Option<>0) then
    raise EKarosProtocol.Create('Unsupported self appearance');
  NameLength := TB1008Wire.ReadBE16(Preview,$150);
  if (NameLength<4) or (NameLength>14) or (Length(Preview)<>$152+4*(NameLength+1)) then
    raise EKarosProtocol.Create('Invalid preview name size');
  Result := nil; SetLength(Result,$D4+NameLength+1);
  Result[0] := 4; Result[1] := 2; PutBE32(Result,2,Regen.Timestamp);
  // Packed record starts at +6: kind +7, ID little-endian +8, floats +12.
  // 52A107 -> CHero.4FD52B: flag +6 selects 4E9D6E, which enters the
  // native idle state (4ECC36 -> 4EF843 -> 4E96C7). Zero only refreshes
  // animation via 4E9E05 and can retain the previous movement flag.
  // Initialize movement inside appearance, not through an early Move packet.
  Result[6] := 1;
  Result[8] := 1;
  Move(Regen.X,Result[12],4); Move(Regen.Z,Result[16],4);
  Move(Regen.Y,Result[20],4); Move(Regen.Heading,Result[24],4);
  Move(CheckedInfo[20],Result[28],$26);
  // The shared record carries the SAME full-width HP/MP as CharInfo.
  // 0x52A2EC treats zero current-HP as dead; no separate one-byte override.
  // State at +0x42 remains 0. Appearance at +0xC8; UTF-8/NUL name at +0xD4.
  Move(Preview[15],Result[$C8],10);
  for I := 0 to NameLength-1 do
  begin
    if (Preview[$152+4*I+1]<>0) or (Preview[$152+4*I+2]<>0) or
      (Preview[$152+4*I+3]<>0) or (Preview[$152+4*I]<32) or (Preview[$152+4*I]>126) then
      raise EKarosProtocol.Create('Non-ASCII preview name');
    Result[$D4+I] := Preview[$152+4*I];
  end;
end;

class function TB1008World.BuildDomingoAppearProbe(Timestamp: Cardinal): TBytes;
const
  // Pinned Berneo placement handle, NOT npcInfo ID 9300141. Verified in the
  // original map's live NPC pool. Only this one stationary NPC is activated.
  DomingoHandle: Cardinal = 121;
  X: Single = 8910.169921875;
  Z: Single = 6723.4501953125;
  Y: Single = 627.7269897460938;
begin
  // 0x52A329 kind=1 -> lookup handle -> 0x4E0ECE copies 0xC2 bytes
  // from packet+6 -> 0x4DB582 -> 0x4DB189 enables npc+0x357.
  // Existing static placement is reused; no cloned object or client patch.
  Result := nil; SetLength(Result,6+$C2);
  Result[0] := 4; Result[1] := 2; PutBE32(Result,2,Timestamp);
  Result[7] := 1;
  Move(DomingoHandle,Result[8],4); // Packed UInt32 LE, unlike request IDs.
  Move(X,Result[12],4); Move(Z,Result[16],4); Move(Y,Result[20],4);
  Move(DomingoHandle,Result[$46],4); // Same template handle: do not clone on miss.
  // Neutral stationary record; no combat stats, rewards or quests asserted.
end;

end.
