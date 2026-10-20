unit Emulator.ItemProperties.B1008;

interface

uses System.SysUtils;

type
  TB1008ItemProperties = record
    // Durable server identity; this value has no field in the native packet.
    InstanceID: Int64;
    // Ordinary enchant level or Fletta grade, depending on the item template.
    NativeGrade: ShortInt;
    // Preserve the native fields without assigning unconfirmed semantics.
    NativeData8, NativeData12: Cardinal;
    GemIDs: array[0..2] of Cardinal;
    procedure WritePacked(var P:TBytes;Offset:Integer);
    procedure WriteStash(var P:TBytes;Offset:Integer);
  end;

implementation

procedure RequireRecord(const P:TBytes;Offset,Size:Integer);
begin
  if (Offset<0) or (Offset>Length(P)-Size) then
    raise EArgumentOutOfRangeException.Create('Item properties outside packet record');
end;

procedure TB1008ItemProperties.WritePacked(var P:TBytes;Offset:Integer);
begin
  // Archived copier 484AC3: native 36-byte inventory/equipment record.
  RequireRecord(P,Offset,36);
  Move(NativeGrade,P[Offset+7],1);
  Move(NativeData8,P[Offset+8],4);
  Move(NativeData12,P[Offset+12],4);
  Move(GemIDs[0],P[Offset+24],12);
end;

procedure TB1008ItemProperties.WriteStash(var P:TBytes;Offset:Integer);
begin
  // 511D78..511DA3 restores grade and gems from the 35-byte stash record.
  // The two DWORDs remain durable on the server even though this client
  // handler does not copy them into the displayed inventory record.
  RequireRecord(P,Offset,35);
  Move(NativeGrade,P[Offset+6],1);
  Move(NativeData8,P[Offset+7],4);
  Move(NativeData12,P[Offset+11],4);
  Move(GemIDs[0],P[Offset+23],12);
end;

end.
