unit Emulator.Quest.B1008;

interface

uses System.SysUtils,Emulator.QuestCatalog.B1008;

const
  B1008ProtectingTheFarmID = 19003003;
  B1008QuestStartCode = $2B;

type
  TB1008QuestStart = record
    Timestamp, CharacterID, QuestID: Cardinal;
    Code: Byte;
  end;
  TB1008QuestReward = record
    Timestamp, CharacterID, QuestID, Choice, Code: Cardinal;
    WireSize: Integer;
  end;
  TB1008QuestPerform = record
    Timestamp,CharacterID,QuestID,Kind,Target,Count,Code:Cardinal;
  end;
  TB1008QuestWire = class
  public
    class function ParseStart(const Payload: TBytes): TB1008QuestStart; static;
    class function ParseReward(const Payload: TBytes): TB1008QuestReward; static;
    class function ParsePerform(const Payload:TBytes):TB1008QuestPerform;static;
    class function BuildStartAck(Timestamp: Cardinal): TBytes; overload; static;
    class function BuildStartAck(Timestamp,CharacterID,QuestID:Cardinal;Code:Byte):TBytes;overload;static;
    class function BuildRewardAck(Timestamp, CharacterID, QuestID,
      Choice: Cardinal; Code: Byte): TBytes; static;
    class function BuildActiveList(Timestamp: Cardinal; Progress: Cardinal = 0): TBytes; static;
    class function BuildProgress(Timestamp, Progress: Cardinal): TBytes; static;
    class function BuildCompleteList(Timestamp, CharacterID: Cardinal): TBytes; static;
    class function BuildEntries(Timestamp,CharacterID:Cardinal;const Entries:TArray<TB1008QuestEntry>):TBytes;static;
    class function BuildCompleted(Timestamp,CharacterID:Cardinal;const IDs:TArray<Cardinal>):TBytes;static;
    class function BuildUpdate(Timestamp,CharacterID:Cardinal;const Update:TB1008QuestUpdate):TBytes;static;
  end;

implementation

uses Emulator.Protocol.B1008;

procedure PutBE32(var B: TBytes; Offset: Integer; Value: Cardinal);
begin
  B[Offset]:=Byte(Value shr 24); B[Offset+1]:=Byte((Value shr 16) and $FF);
  B[Offset+2]:=Byte((Value shr 8) and $FF); B[Offset+3]:=Byte(Value and $FF);
end;

class function TB1008QuestWire.BuildStartAck(Timestamp: Cardinal): TBytes;
begin
  Result:=BuildStartAck(Timestamp,1,B1008ProtectingTheFarmID,B1008QuestStartCode);
end;

class function TB1008QuestWire.BuildStartAck(Timestamp,CharacterID,QuestID:Cardinal;Code:Byte):TBytes;
begin
  Result:=nil;SetLength(Result,15);Result[0]:=9;
  PutBE32(Result,2,Timestamp);PutBE32(Result,6,CharacterID);PutBE32(Result,10,QuestID);Result[14]:=Code;
end;

class function TB1008QuestWire.ParsePerform(const Payload:TBytes):TB1008QuestPerform;
begin
  // Native 489BA8: 09/03 + timestamp + five BE32 values + one-byte code.
  // 48A1C6 / 48A409 send kind 8; 48A12D / 48A370 send kind 9.
  if (Length(Payload)<>27) or (Payload[0]<>9) or (Payload[1]<>3) then
    raise EKarosProtocol.Create('Invalid quest perform request');
  Result.Timestamp:=TB1008Wire.ReadBE32(Payload,2);Result.CharacterID:=TB1008Wire.ReadBE32(Payload,6);
  Result.QuestID:=TB1008Wire.ReadBE32(Payload,10);Result.Kind:=TB1008Wire.ReadBE32(Payload,14);
  Result.Target:=TB1008Wire.ReadBE32(Payload,18);Result.Count:=TB1008Wire.ReadBE32(Payload,22);
  Result.Code:=Payload[26];
end;

class function TB1008QuestWire.BuildUpdate(Timestamp,CharacterID:Cardinal;const Update:TB1008QuestUpdate):TBytes;
begin
  Result:=nil;SetLength(Result,27);Result[0]:=9;Result[1]:=3;
  PutBE32(Result,2,Timestamp);PutBE32(Result,6,CharacterID);PutBE32(Result,10,Update.QuestID);
  PutBE32(Result,14,Update.Kind);PutBE32(Result,18,Update.Target);PutBE32(Result,22,Update.Count);
end;

class function TB1008QuestWire.BuildEntries(Timestamp,CharacterID:Cardinal;const Entries:TArray<TB1008QuestEntry>):TBytes;
var I,O:Integer;D:TB1008QuestDefinition;Goal:TB1008QuestObjective;V:Cardinal;
begin
  if Length(Entries)>20 then raise EKarosProtocol.Create('Too many active quests');
  Result:=nil;SetLength(Result,12+Length(Entries)*228);Result[0]:=9;Result[1]:=2;
  PutBE32(Result,2,Timestamp);PutBE32(Result,6,CharacterID);Result[11]:=Length(Entries);
  for I:=0 to High(Entries) do begin
    D:=TB1008QuestCatalog.Get(Entries[I].ID);O:=12+I*228;V:=D.ID;Move(V,Result[O],4);
    for Goal in D.Objectives do begin
      O:=16+I*228+Integer(Goal.Index)*32;
      Move(Goal.Kind,Result[O],4);Move(Goal.Target,Result[O+4],4);
      V:=Entries[I].Counts[Goal.Index];
      if V>Goal.Required then raise EKarosProtocol.Create('Quest counter exceeds requirement');
      Move(V,Result[O+8],4);
    end;
  end;
end;

class function TB1008QuestWire.BuildCompleted(Timestamp,CharacterID:Cardinal;const IDs:TArray<Cardinal>):TBytes;
var I:Integer;
begin
  if Length(IDs)>65535 then raise EKarosProtocol.Create('Too many completed quests');
  Result:=nil;SetLength(Result,14+Length(IDs)*4);Result[0]:=9;Result[1]:=4;
  PutBE32(Result,2,Timestamp);PutBE32(Result,6,CharacterID);
  // 52BE19: first array restores ready active entries (4F6C5D); second
  // appends completed IDs to hero+4B0 (4F77B0), also used by live hand-in
  // at 4FE280. Counts are BE16, but both ID arrays are raw LE32.
  Result[12]:=Byte(Length(IDs) shr 8);Result[13]:=Byte(Length(IDs));
  for I:=0 to High(IDs) do Move(IDs[I],Result[14+I*4],4);
end;

class function TB1008QuestWire.BuildRewardAck(Timestamp, CharacterID,
  QuestID, Choice: Cardinal; Code: Byte): TBytes;
begin
  // 0x525AB3 / 0x52BC3B consume the compact 19-byte form.  Echo the
  // admitted request fields; byte +18 is the result code.
  Result:=nil; SetLength(Result,19); Result[0]:=9; Result[1]:=1;
  PutBE32(Result,2,Timestamp); PutBE32(Result,6,CharacterID);
  PutBE32(Result,10,QuestID); PutBE32(Result,14,Choice); Result[18]:=Code;
end;

class function TB1008QuestWire.BuildActiveList(Timestamp, Progress: Cardinal): TBytes;
var V: Cardinal;
begin
  // 0x52BD02: 12-byte BE header, then 228-byte raw LE records.
  // 0x4F6D46 -> 0x4FF86F: QuestID + seven 32-byte objective records.
  // quest.lod_eng: kind=1, target=10018, required=5. Wire counter is current,
  // NOT the required count! Other six objectives and unknown fields are zero.
  if Progress>5 then raise EKarosProtocol.Create('Quest progress outside range');
  Result:=nil; SetLength(Result,240); Result[0]:=9; Result[1]:=2;
  PutBE32(Result,2,Timestamp); PutBE32(Result,6,1); Result[11]:=1;
  V:=B1008ProtectingTheFarmID; Move(V,Result[12],4);
  V:=1; Move(V,Result[16],4); V:=10018; Move(V,Result[20],4);
  Move(Progress,Result[24],4);
end;

class function TB1008QuestWire.BuildProgress(Timestamp, Progress: Cardinal): TBytes;
begin
  if (Progress<1) or (Progress>5) then raise EKarosProtocol.Create('Quest progress outside range');
  // 09/03 -> 0x615980 -> vtable+90 -> 0x52BD8E; 0x4FF6C7 SETS counter.
  Result:=nil; SetLength(Result,27); Result[0]:=9; Result[1]:=3;
  PutBE32(Result,2,Timestamp); PutBE32(Result,6,1);
  PutBE32(Result,10,B1008ProtectingTheFarmID); PutBE32(Result,14,1);
  PutBE32(Result,18,10018); PutBE32(Result,22,Progress);
  // Unread trailing byte stays neutral.
end;

class function TB1008QuestWire.BuildCompleteList(Timestamp,
  CharacterID: Cardinal): TBytes;
begin
  Result:=BuildCompleted(Timestamp,CharacterID,TArray<Cardinal>.Create(B1008ProtectingTheFarmID));
end;

class function TB1008QuestWire.ParseStart(const Payload: TBytes): TB1008QuestStart;
begin
  // Serializer 0x48906B, Accept caller 0x489CE5 (code=0x2B).
  // Receiver 0x52BB79 reads BE32 +6/+10 and byte +14.
  // Observed real Accept request: 09/00, exactly 15 decoded bytes.
  if Length(Payload)<>15 then raise EKarosProtocol.Create('Invalid QuestStart size');
  if (Payload[0]<>9) or (Payload[1]<>0) then raise EKarosProtocol.Create('Not QuestStart');
  Result.Timestamp := TB1008Wire.ReadBE32(Payload,2);
  Result.CharacterID := TB1008Wire.ReadBE32(Payload,6);
  Result.QuestID := TB1008Wire.ReadBE32(Payload,10);
  Result.Code := Payload[14];
end;

class function TB1008QuestWire.ParseReward(const Payload: TBytes): TB1008QuestReward;
begin
  // Native 489B4C emits 19 bytes (last field is a byte). Preserve the
  // previously recorded 22-byte request form admitted by the legacy handler.
  if (Length(Payload)<>19) and (Length(Payload)<>22) then
    raise EKarosProtocol.Create('Invalid QuestReward size');
  if (Payload[0]<>9) or (Payload[1]<>1) then raise EKarosProtocol.Create('Not QuestReward');
  Result.Timestamp := TB1008Wire.ReadBE32(Payload,2);
  Result.CharacterID := TB1008Wire.ReadBE32(Payload,6);
  Result.QuestID := TB1008Wire.ReadBE32(Payload,10);
  Result.Choice := TB1008Wire.ReadBE32(Payload,14);
  if Length(Payload)=22 then Result.Code := TB1008Wire.ReadBE32(Payload,18)
  else Result.Code := Payload[18];
  Result.WireSize := Length(Payload);
end;

end.
