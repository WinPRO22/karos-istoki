unit Emulator.Protocol.B1008;

interface

uses System.SysUtils;

const
  B1008ProfileName = 'NHN-EN CBT1 b1008';
  B1008ClientSHA256 = '9d0a4ff1cf224e1637be3c0c99ab60eea962928747e0f1f1baad3fca0e082966';
  B1008MaxWireBody = 8192;
  B1008MaxPayload = B1008MaxWireBody - 2;
  B1008ReadChunk = 4096;

type
  EKarosProtocol = class(Exception);

  // Initial b1008 mode 2 only. Future negotiated keys belong to a new codec state.
  TB1008Wire = class sealed
  public
    class function Encode(const APayload: TBytes): TBytes; static;
    class function Decode(const ABody: TBytes): TBytes; static;
    class function ReadBE16(const AData: TBytes; AOffset: Integer): Word; static;
    class function ReadBE32(const AData: TBytes; AOffset: Integer): Cardinal; static;
  end;

  // One instance per connection, owned exclusively by its Indy worker.
  TB1008FrameDecoder = class
  private
    FBuffer: TBytes;
    FFaulted: Boolean;
    procedure Fail(const AMessage: string);
    function GetPendingBytes: Integer;
  public
    procedure Append(const AChunk: TBytes);
    function TryPop(out APayload: TBytes): Boolean;
    property PendingBytes: Integer read GetPendingBytes;
    property Faulted: Boolean read FFaulted;
  end;

implementation

procedure RequireRange(const AData: TBytes; AOffset, ACount: Integer);
begin
  if (AOffset < 0) or (ACount > Length(AData)) or
     (AOffset > Length(AData) - ACount) then
    raise EKarosProtocol.Create('Truncated packet field');
end;

class function TB1008Wire.ReadBE16(const AData: TBytes; AOffset: Integer): Word;
begin
  RequireRange(AData, AOffset, 2);
  Result := (Word(AData[AOffset]) shl 8) or AData[AOffset + 1];
end;

class function TB1008Wire.ReadBE32(const AData: TBytes; AOffset: Integer): Cardinal;
begin
  RequireRange(AData, AOffset, 4);
  Result := (Cardinal(AData[AOffset]) shl 24) or
    (Cardinal(AData[AOffset + 1]) shl 16) or
    (Cardinal(AData[AOffset + 2]) shl 8) or AData[AOffset + 3];
end;

class function TB1008Wire.Encode(const APayload: TBytes): TBytes;
var
  I, BodyLength: Integer;
  Value: Byte;
begin
  if (Length(APayload) < 1) or (Length(APayload) > B1008MaxPayload) then
    raise EKarosProtocol.Create('Payload length outside b1008 mode-2 limits');
  BodyLength := Length(APayload) + 2;
  SetLength(Result, BodyLength + 4);
  Result[0] := 0;
  Result[1] := 0;
  Result[2] := Byte(BodyLength shr 8);
  Result[3] := Byte(BodyLength and $FF);
  for I := 0 to BodyLength - 1 do
  begin
    if I < Length(APayload) then
      Value := APayload[I]
    else if I = Length(APayload) then
      Value := $4B
    else
      Value := $53;
    Value := Value xor Byte((I and $0F) xor $0E);
    Result[I + 4] := Byte((Value shr 1) or ((Value and 1) shl 7));
  end;
end;

class function TB1008Wire.Decode(const ABody: TBytes): TBytes;
var
  I: Integer;
  Value: Byte;
  Plain: TBytes;
begin
  if (Length(ABody) < 3) or (Length(ABody) > B1008MaxWireBody) then
    raise EKarosProtocol.Create('Invalid b1008 mode-2 body length');
  SetLength(Plain, Length(ABody));
  for I := 0 to High(ABody) do
  begin
    Value := Byte(((ABody[I] shl 1) and $FF) or (ABody[I] shr 7));
    Plain[I] := Value xor Byte((I and $0F) xor $0E);
  end;
  if (Plain[Length(Plain) - 2] <> $4B) or
     (Plain[Length(Plain) - 1] <> $53) then
    raise EKarosProtocol.Create('Invalid KS trailer: wrong profile/key or damaged packet');
  Result := Copy(Plain, 0, Length(Plain) - 2);
end;

procedure TB1008FrameDecoder.Fail(const AMessage: string);
begin
  FFaulted := True;
  FBuffer := nil;
  raise EKarosProtocol.Create(AMessage);
end;

function TB1008FrameDecoder.GetPendingBytes: Integer;
begin
  Result := Length(FBuffer);
end;

procedure TB1008FrameDecoder.Append(const AChunk: TBytes);
var
  OldLength: Integer;
begin
  if FFaulted then
    raise EKarosProtocol.Create('Decoder is faulted; reconnect required');
  OldLength := Length(FBuffer);
  if (Length(AChunk) > B1008ReadChunk) or
     (OldLength + Length(AChunk) > B1008MaxWireBody + 4 + B1008ReadChunk) then
    Fail('Receive buffer limit exceeded');
  if Length(AChunk) = 0 then
    Exit;
  SetLength(FBuffer, OldLength + Length(AChunk));
  Move(AChunk[0], FBuffer[OldLength], Length(AChunk));
end;

function TB1008FrameDecoder.TryPop(out APayload: TBytes): Boolean;
var
  BodyLength: Cardinal;
  Consumed: Integer;
begin
  APayload := nil;
  Result := False;
  if FFaulted then
    raise EKarosProtocol.Create('Decoder is faulted; reconnect required');
  if Length(FBuffer) < 4 then
    Exit;
  BodyLength := TB1008Wire.ReadBE32(FBuffer, 0);
  // Validate BEFORE allocation or waiting for the announced body.
  if (BodyLength < 3) or (BodyLength > B1008MaxWireBody) then
    Fail('Invalid length prefix (expected 3..8192, big-endian)');
  Consumed := Integer(BodyLength) + 4;
  if Length(FBuffer) < Consumed then
    Exit;
  try
    APayload := TB1008Wire.Decode(Copy(FBuffer, 4, Integer(BodyLength)));
  except
    on E: EKarosProtocol do
      Fail(E.Message);
  end;
  FBuffer := Copy(FBuffer, Consumed, Length(FBuffer) - Consumed);
  Result := True;
end;

end.
