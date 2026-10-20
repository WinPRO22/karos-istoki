unit Emulator.Npcs.B1008;

interface

uses System.SysUtils,System.Generics.Collections;

type
  TB1008Npc = record
    Handle,ID:Cardinal;
    Name:string;
    X,Z,Y:Single;
  end;
  TB1008Npcs = class
  private
    class var FRows:TArray<TB1008Npc>;
    class var FModels:TArray<TPair<Cardinal,Cardinal>>;
  public
    class constructor Create;
    class function All:TArray<TB1008Npc>;static;
    class function Near(ID:Cardinal;X,Z,Y:Single):Boolean;static;
    class function MobModel(ClientID:Cardinal):Cardinal;static;
    class function BuildAppear(Timestamp:Cardinal;const Npc:TB1008Npc):TBytes;static;
  end;

implementation

uses System.JSON,System.IOUtils,System.Math,Emulator.Items.B1008,Emulator.World.B1008;

class constructor TB1008Npcs.Create;
var Root:TJSONObject;V:TJSONValue;Rows:TJSONArray;N:TB1008Npc;I,J:Integer;
begin
  Root:=TJSONObject.ParseJSONValue(TFile.ReadAllText(TB1008Items.DataPath('npcs-v1.json'),TEncoding.UTF8)) as TJSONObject;
  if Root=nil then raise Exception.Create('Invalid NPC catalog');
  try
    if Root.GetValue<string>('build')<>'b1008' then raise Exception.Create('Wrong NPC build');
    Rows:=Root.GetValue<TJSONArray>('npcs');SetLength(FRows,Rows.Count);I:=0;
    for V in Rows do begin
      N.Handle:=V.GetValue<Cardinal>('handle');N.ID:=V.GetValue<Cardinal>('npcId');
      N.Name:=V.GetValue<string>('name');N.X:=V.GetValue<Double>('x');
      N.Z:=V.GetValue<Double>('z');N.Y:=V.GetValue<Double>('y');
      if (V.GetValue<Integer>('mapId')<>19003) or (N.Handle=0) or (N.Handle>=1000) or
        (N.ID=0) or (N.Name='') or IsNan(N.X) or IsNan(N.Z) or IsNan(N.Y) or
        IsInfinite(N.X) or IsInfinite(N.Z) or IsInfinite(N.Y) then raise Exception.Create('Invalid NPC placement');
      for J:=0 to I-1 do if FRows[J].Handle=N.Handle then raise Exception.Create('Duplicate NPC handle');
      FRows[I]:=N;Inc(I);
    end;
    Rows:=Root.GetValue<TJSONArray>('mobModels');SetLength(FModels,Rows.Count);I:=0;
    for V in Rows do begin
      FModels[I]:=TPair<Cardinal,Cardinal>.Create(V.GetValue<Cardinal>('clientId'),V.GetValue<Cardinal>('modelId'));Inc(I);
    end;
  finally Root.Free;end;
end;

class function TB1008Npcs.All:TArray<TB1008Npc>;
begin Result:=Copy(FRows);end;

class function TB1008Npcs.MobModel(ClientID:Cardinal):Cardinal;
var P:TPair<Cardinal,Cardinal>;
begin
  for P in FModels do if P.Key=ClientID then Exit(P.Value);
  raise EArgumentException.Create('Unknown NPC model mapping');
end;

class function TB1008Npcs.Near(ID:Cardinal;X,Z,Y:Single):Boolean;
var N:TB1008Npc;
begin
  Result:=False;
  if IsNan(X) or IsNan(Z) or IsNan(Y) or IsInfinite(X) or IsInfinite(Z) or IsInfinite(Y) then Exit;
  // Same 100-unit interaction radius as the native NPC dialogue/shops.
  for N in FRows do if (N.ID=ID) and (Sqr(Double(X)-N.X)+Sqr(Double(Z)-N.Z)+Sqr(Double(Y)-N.Y)<=10000) then Exit(True);
end;

class function TB1008Npcs.BuildAppear(Timestamp:Cardinal;const Npc:TB1008Npc):TBytes;
begin
  Result:=TB1008World.BuildDomingoAppearProbe(Timestamp);
  Move(Npc.Handle,Result[8],4);Move(Npc.Handle,Result[$46],4);
  Move(Npc.X,Result[12],4);Move(Npc.Z,Result[16],4);Move(Npc.Y,Result[20],4);
end;

end.
