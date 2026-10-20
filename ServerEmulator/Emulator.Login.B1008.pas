unit Emulator.Login.B1008;

interface

uses System.SysUtils;

type
  TB1008LoginMode = (blObserveOnly, blEmptyAccountProbe, blCharacterPreview, blMapLoadingProbe);
  TB1008Replies = TArray<TBytes>;

  TB1008Login = class
  public
    class function BuildAcknowledgement(ATimestamp: Cardinal): TBytes; static;
    class function BuildEmptyListEnd(ATimestamp: Cardinal): TBytes; static;
    class function ReplyName(const APayload: TBytes): string; static;
  end;

implementation

procedure PutTimestamp(var AData: TBytes; AValue: Cardinal);
begin
  AData[2] := Byte(AValue shr 24);
  AData[3] := Byte((AValue shr 16) and $FF);
  AData[4] := Byte((AValue shr 8) and $FF);
  AData[5] := Byte(AValue and $FF);
end;

class function TB1008Login.BuildAcknowledgement(ATimestamp: Cardinal): TBytes;
begin
  // 0x524EBD accepts three UTF-8/NUL strings. 0x525150 consumes field8 and
  // string3 only. Keep field8/string3 empty; never echo the supplied credentials.
  // Field6=14 mirrors the observed request; its reply meaning is not established.
  Result := TBytes.Create($02,$00,0,0,0,0,0,$0E,0,0,0,0,0);
  PutTimestamp(Result, ATimestamp);
end;

class function TB1008Login.BuildEmptyListEnd(ATimestamp: Cardinal): TBytes;
begin
  // 0x524D19: ID at +7 is zero => no character body/name is read.
  // 0x52536C: final byte at +6 != 0 => GUI state 3, creation screen 30010.
  // Eleven bytes cover all actual reads on this branch. No invented padding.
  Result := TBytes.Create($02,$01,0,0,0,0,1,0,0,0,0);
  PutTimestamp(Result, ATimestamp);
end;

class function TB1008Login.ReplyName(const APayload: TBytes): string;
begin
  if Length(APayload) < 2 then Exit('invalid');
  if (APayload[0]=5) and (APayload[1]=2) then Exit('AttackDamageProbe');
  if (APayload[0]=8) and (APayload[1]=0) then Exit('SpiderGageProbe');
  if (APayload[0]=9) and (APayload[1]=0) then Exit('QuestStartAck');
  if (APayload[0]=9) and (APayload[1]=2) then Exit('QuestActiveList');
  if (APayload[0]=4) and (APayload[1]=3) then Exit('ActorDisappear');
  if (APayload[0] = $04) and (APayload[1] = $02) then
  begin
    if Length(APayload)<8 then Exit('invalid');
    if APayload[7]=0 then Exit('SelfAppearProbe');
    if APayload[7]=1 then
    begin
      if (Length(APayload)=200) and (APayload[8]=120) and
        (APayload[9]=0) and (APayload[10]=0) and (APayload[11]=0) then Exit('LittleSpiderAppearProbe');
      Exit('NpcAppearProbe');
    end;
    Exit('UnknownAppearKind');
  end;
  if (APayload[0] = $02) and (APayload[1] = $05) then Exit('CharacterInfoProbe');
  if (APayload[0] = $04) and (APayload[1] = $04) then Exit('BerneoZoneProbe');
  if (APayload[0] = $02) and (APayload[1] = $00) then Exit('LoginAckProbe');
  if (APayload[0] = $02) and (APayload[1] = $01) then
  begin
    if Length(APayload) > 11 then Exit('CharacterPreview');
    Exit('EmptyCharacterListEnd');
  end;
  if (APayload[0] = $0B) and (APayload[1] = $00) then Exit('SystemPing');
  Result := 'unknown';
end;

end.
