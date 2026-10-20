unit Emulator.ItemEnhancement.B1008;

interface

uses System.SysUtils;

type
  TB1008EnhancementRequest=record
    Kind:Byte;
    Timestamp,CharacterID,PageA,SlotA,ItemA,PageB,SlotB,ItemB,Index:Cardinal;
    Code:Byte;
    class function Parse(const P:TBytes):TB1008EnhancementRequest;static;
    function Reply(ACode:Byte):TBytes;
  end;
  TB1008EnhancementStats=record
    ItemID:Cardinal;
    Grade,AttackMin100,AttackMax100,Defense:Integer;
  end;
  TB1008Enhancement=class
  private
    class var FStats:TArray<TB1008EnhancementStats>;
  public
    class constructor Create;
    class function FindStats(ItemID:Cardinal;Grade:Integer;
      out AttackMin100,AttackMax100,Defense:Integer):Boolean;static;
    class function ScrollMatches(ScrollID,ItemID:Cardinal):Boolean;static;
    // Zero denotes an unsupported gem, not a supported zero-effect gem.
    class function GemStrength(GemID:Cardinal):Integer;static;
  end;
  TB1008ItemEnhancement=TB1008Enhancement;

implementation

uses System.IOUtils,System.JSON,Emulator.Protocol.B1008,Emulator.Items.B1008;

procedure EnhancementBE(var P:TBytes;Offset:Integer;Value:Cardinal);
begin
  P[Offset]:=Byte(Value shr 24);P[Offset+1]:=Byte((Value shr 16) and 255);
  P[Offset+2]:=Byte((Value shr 8) and 255);P[Offset+3]:=Byte(Value and 255);
end;

class function TB1008EnhancementRequest.Parse(const P:TBytes):TB1008EnhancementRequest;
begin
  Result:=Default(TB1008EnhancementRequest);
  if Length(P)<2 then raise EKarosProtocol.Create('Invalid enhancement size');
  if (P[0]<>6) or not (P[1] in [$17,$19]) then
    raise EKarosProtocol.Create('Not item enhancement');
  if ((P[1]=$17) and (Length(P)<>35)) or
    ((P[1]=$19) and (Length(P)<>39)) then
    raise EKarosProtocol.Create('Invalid enhancement size');
  Result.Kind:=P[1];Result.Timestamp:=TB1008Wire.ReadBE32(P,2);
  Result.CharacterID:=TB1008Wire.ReadBE32(P,6);
  Result.PageA:=TB1008Wire.ReadBE32(P,10);Result.SlotA:=TB1008Wire.ReadBE32(P,14);
  Result.ItemA:=TB1008Wire.ReadBE32(P,18);Result.PageB:=TB1008Wire.ReadBE32(P,22);
  Result.SlotB:=TB1008Wire.ReadBE32(P,26);Result.ItemB:=TB1008Wire.ReadBE32(P,30);
  if Result.Kind=$19 then Result.Index:=TB1008Wire.ReadBE32(P,34);
  Result.Code:=P[High(P)];
end;

function TB1008EnhancementRequest.Reply(ACode:Byte):TBytes;
begin
  Result:=nil;
  case Kind of
    $17:SetLength(Result,35);
    $19:SetLength(Result,39);
  else raise EKarosProtocol.Create('Invalid enhancement kind');end;
  Result[0]:=6;Result[1]:=Kind;
  EnhancementBE(Result,2,Timestamp);EnhancementBE(Result,6,CharacterID);
  EnhancementBE(Result,10,PageA);EnhancementBE(Result,14,SlotA);
  EnhancementBE(Result,18,ItemA);EnhancementBE(Result,22,PageB);
  EnhancementBE(Result,26,SlotB);EnhancementBE(Result,30,ItemB);
  if Kind=$19 then EnhancementBE(Result,34,Index);
  Result[High(Result)]:=ACode;
end;

function EnhancementNumber(Row:TJSONValue;const Field:string):Integer;
var V:TJSONValue;N:Int64;
begin
  if not (Row is TJSONObject) then raise Exception.Create('Invalid enhancement record');
  V:=TJSONObject(Row).GetValue(Field);
  if not (V is TJSONNumber) then raise Exception.Create('Invalid enhancement number: '+Field);
  if not TryStrToInt64(V.Value,N) then raise Exception.Create('Invalid enhancement integer: '+Field);
  if (N<0) or (N>High(Integer)) then raise Exception.Create('Invalid enhancement range: '+Field);
  Result:=Integer(N);
end;

class constructor TB1008Enhancement.Create;
var Parsed,V:TJSONValue;Root:TJSONObject;Rows:TJSONArray;R:TB1008EnhancementStats;
  D:TB1008ItemDefinition;I,J,G:Integer;Found:Boolean;
begin
  Parsed:=TJSONObject.ParseJSONValue(TFile.ReadAllText(
    TB1008Items.DataPath('item-enhancement-v1.json'),TEncoding.UTF8));
  if not (Parsed is TJSONObject) then begin Parsed.Free;raise Exception.Create('Invalid enhancement catalog');end;
  Root:=TJSONObject(Parsed);
  try
    if Root.GetValue<string>('build')<>'b1008' then raise Exception.Create('Wrong enhancement catalog build');
    Rows:=Root.GetValue<TJSONArray>('stats');
    if (Rows=nil) then raise Exception.Create('Missing enhancement stats');
    if (Rows.Count=0) or (Rows.Count>4187) then raise Exception.Create('Invalid enhancement stat count');
    SetLength(FStats,Rows.Count);I:=0;
    for V in Rows do begin
      R.ItemID:=EnhancementNumber(V,'itemId');R.Grade:=EnhancementNumber(V,'grade');
      R.AttackMin100:=EnhancementNumber(V,'attackMin100');
      R.AttackMax100:=EnhancementNumber(V,'attackMax100');R.Defense:=EnhancementNumber(V,'defense');
      if (R.Grade>3) or (R.AttackMax100<R.AttackMin100) or
        not TB1008Items.Find(R.ItemID,D) then raise Exception.Create('Unsupported enhancement stats');
      if D.InventoryOnly or not (D.Slot in [1,2,3,4,7]) then
        raise Exception.Create('Invalid enhancement equipment');
      if (R.Grade=0) and ((R.AttackMin100<>D.AttackMin100) or
        (R.AttackMax100<>D.AttackMax100) or (R.Defense<>D.Defense)) then
        raise Exception.Create('Enhancement base stats mismatch');
      for J:=0 to I-1 do if (FStats[J].ItemID=R.ItemID) and (FStats[J].Grade=R.Grade) then
        raise Exception.Create('Duplicate enhancement grade');
      FStats[I]:=R;Inc(I);
    end;
    for D in TB1008Items.All do if not D.InventoryOnly and (D.Slot in [1,2,3,4,7]) and
      (D.Subtype<>17) then
      for G:=0 to 3 do begin
        Found:=False;
        for R in FStats do if (R.ItemID=D.ID) and (R.Grade=G) then begin Found:=True;Break;end;
        if not Found then raise Exception.Create('Missing equipment enhancement grade');
      end;
  finally Root.Free;end;
end;

class function TB1008Enhancement.FindStats(ItemID:Cardinal;Grade:Integer;
  out AttackMin100,AttackMax100,Defense:Integer):Boolean;
var R:TB1008EnhancementStats;
begin
  AttackMin100:=0;AttackMax100:=0;Defense:=0;
  for R in FStats do if (R.ItemID=ItemID) and (R.Grade=Grade) then begin
    AttackMin100:=R.AttackMin100;AttackMax100:=R.AttackMax100;Defense:=R.Defense;Exit(True);
  end;
  Result:=False;
end;

class function TB1008Enhancement.ScrollMatches(ScrollID,ItemID:Cardinal):Boolean;
var D:TB1008ItemDefinition;
begin
  Result:=False;
  if not TB1008Items.Find(ItemID,D) then Exit;
  if D.InventoryOnly or (D.Subtype=17) then Exit;
  Result:=((ScrollID=60901) and (D.Slot=7)) or
    ((ScrollID=60902) and (D.Slot in [1,2,3,4]));
end;

class function TB1008Enhancement.GemStrength(GemID:Cardinal):Integer;
begin
  if GemID=55001 then Result:=1 else Result:=0;
end;

end.
