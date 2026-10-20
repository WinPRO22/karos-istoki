unit Emulator.Rates.B1008;

interface

uses System.SysUtils;

const B1008RateOne=100; B1008RateMax=2000; // 0..20x, in hundredths.

type
  TB1008Rates = record
    Drop,Experience,Fletta,Carat:Integer;
    class function Default:TB1008Rates;static;
    class function Load(const Path:string):TB1008Rates;static;
    procedure Validate;
    class function Scale(Value:Int64;Rate:Integer;Cap:Int64):Int64;static;
    class function DropIntervalCount(PreviousWeight,NextWeight,TotalWeight:Int64;
      ChanceBP,Rate,RollMillion:Integer):Integer;static;
  end;

implementation

uses System.IniFiles,Emulator.Items.B1008;

type TDefaultRates=class
  class var Value:TB1008Rates;
  class constructor Create;
end;

class constructor TDefaultRates.Create;
begin Value:=TB1008Rates.Load(TB1008Items.DataPath('rates-v1.ini'));end;

procedure CheckRate(Rate:Integer);
begin
  if (Rate<0) or (Rate>B1008RateMax) then raise EArgumentException.Create('Rate must be between 0 and 20x');
end;

procedure TB1008Rates.Validate;
begin CheckRate(Drop);CheckRate(Experience);CheckRate(Fletta);CheckRate(Carat);end;

class function TB1008Rates.Load(const Path:string):TB1008Rates;
var Ini:TMemIniFile;
  function ReadRate(const Name:string):Integer;
  var V:Double;FS:TFormatSettings;S:string;
  begin
    FS:=TFormatSettings.Invariant;S:=Trim(Ini.ReadString('rates',Name,''));
    if not TryStrToFloat(S,V,FS) or (V<0) or (V>20) then
      raise EArgumentException.Create('Invalid rate: '+Name);
    Result:=Round(V*100);
    if Abs(V*100-Result)>0.000001 then raise EArgumentException.Create('Rate supports two decimal places: '+Name);
    CheckRate(Result);
  end;
begin
  if not FileExists(Path) then raise Exception.Create('Missing rates profile: '+Path);
  Ini:=TMemIniFile.Create(Path,TEncoding.UTF8);
  try
    Result.Drop:=ReadRate('drop');Result.Experience:=ReadRate('experience');
    Result.Fletta:=ReadRate('fletta');Result.Carat:=ReadRate('carat');Result.Validate;
  finally Ini.Free;end;
end;

class function TB1008Rates.Default:TB1008Rates;
begin Result:=TDefaultRates.Value;end;

class function TB1008Rates.Scale(Value:Int64;Rate:Integer;Cap:Int64):Int64;
begin
  CheckRate(Rate);
  if (Value<0) or (Cap<0) or (Cap>High(Int64) div B1008RateMax) then
    raise EArgumentException.Create('Invalid rate amount/cap');
  if Rate=0 then Exit(0);
  // Compare before multiplying; exact nonnegative half-up rounding.
  if Value>(Cap*100+49) div Rate then Exit(Cap);
  Result:=(Value*Rate+50) div 100;
  if Result>Cap then Result:=Cap;
end;

class function TB1008Rates.DropIntervalCount(PreviousWeight,NextWeight,TotalWeight:Int64;
  ChanceBP,Rate,RollMillion:Integer):Integer;
var Mass,Left,Right:Int64;
begin
  CheckRate(Rate);
  if (PreviousWeight<0) or (NextWeight<PreviousWeight) or (NextWeight>TotalWeight) or
    (TotalWeight<=0) or (TotalWeight>100000000) or (ChanceBP<0) or (ChanceBP>10000) or
    (RollMillion<0) or (RollMillion>=1000000) then raise EArgumentException.Create('Invalid drop interval');
  Mass:=Int64(ChanceBP)*Rate;
  Left:=Mass*PreviousWeight div TotalWeight;
  Right:=Mass*NextWeight div TotalWeight;
  // One random offset on consecutive weighted intervals. This preserves
  // each item's scaled probability (up to one millionth), creates separate
  // bags above 100%, and keeps the whole pool's floor + fractional bag count.
  Result:=(Right+RollMillion) div 1000000-(Left+RollMillion) div 1000000;
end;

end.
