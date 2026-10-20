unit Emulator.QuestCatalog.B1008;

interface

uses System.SysUtils;

type
  TB1008QuestObjective = record
    Index,Kind,Target,Required,SourceMob,DropChanceBP,RequiredGemID:Cardinal;
    ItemSource:string;
  end;
  TB1008QuestAward = record
    Index,Kind,Value,Amount:Cardinal;
    Choice:Boolean;
  end;
  TB1008QuestDefinition = record
    ID,Giver,Receiver,Previous,MinLevel,MaxLevel,AcceptanceItem:Cardinal;
    Name:string;
    Enabled,Repeatable:Boolean;
    Objectives:TArray<TB1008QuestObjective>;
    AcceptanceItems:TArray<Cardinal>;
    Rewards:TArray<TB1008QuestAward>;
    function ValidChoice(Choice:Cardinal):Boolean;
  end;
  TB1008QuestEntry = record
    ID:Cardinal;
    Completed:Boolean;
    Counts:array[0..6] of Cardinal;
  end;
  TB1008QuestUpdate = record
    QuestID,Kind,Target,Count:Cardinal;
  end;
  TB1008QuestDropNeed = record
    ItemID,Missing,ChanceBP:Cardinal;
  end;
  TB1008QuestCatalog = class
  private
    class var FRows:TArray<TB1008QuestDefinition>;
  public
    class constructor Create;
    class function All:TArray<TB1008QuestDefinition>;static;
    class function Find(ID:Cardinal;out Q:TB1008QuestDefinition):Boolean;static;
    class function Get(ID:Cardinal):TB1008QuestDefinition;static;
    class function Ready(const Entry:TB1008QuestEntry):Boolean;static;
    class function RollDrop(var State:Cardinal;const Need:TB1008QuestDropNeed;
      GroundAmount:Cardinal;Rate:Integer):Cardinal;static;
  end;

implementation

uses System.JSON,System.IOUtils,Emulator.Items.B1008,Emulator.Rates.B1008;

function TB1008QuestDefinition.ValidChoice(Choice:Cardinal):Boolean;
var R:TB1008QuestAward;HasChoice:Boolean;
begin
  HasChoice:=False;
  for R in Rewards do if R.Choice then begin
    HasChoice:=True;if R.Index=Choice then Exit(True);
  end;
  Result:=not HasChoice and (Choice=High(Cardinal));
end;

class constructor TB1008QuestCatalog.Create;
var Root:TJSONObject;Rows,Children:TJSONArray;V,W:TJSONValue;Q:TB1008QuestDefinition;
  O:TB1008QuestObjective;R:TB1008QuestAward;I,J,K:Integer;N:Int64;D:TB1008ItemDefinition;
begin
  Root:=TJSONObject.ParseJSONValue(TFile.ReadAllText(TB1008Items.DataPath('quests-v1.json'),TEncoding.UTF8)) as TJSONObject;
  if Root=nil then raise Exception.Create('Invalid quest catalog');
  try
    if Root.GetValue<string>('build')<>'b1008' then raise Exception.Create('Wrong quest build');
    Rows:=Root.GetValue<TJSONArray>('quests');SetLength(FRows,Rows.Count);I:=0;
    for V in Rows do begin
      Q:=Default(TB1008QuestDefinition);Q.ID:=V.GetValue<Cardinal>('id');
      Q.Name:=V.GetValue<string>('name');Q.Giver:=V.GetValue<Cardinal>('giver');Q.Receiver:=V.GetValue<Cardinal>('receiver');
      Q.Previous:=V.GetValue<Cardinal>('previous');Q.MinLevel:=V.GetValue<Cardinal>('minLevel');
      Q.MaxLevel:=V.GetValue<Cardinal>('maxLevel');Q.AcceptanceItem:=V.GetValue<Cardinal>('acceptanceItem');
      Children:=V.GetValue<TJSONArray>('acceptanceItems',nil);
      if Children=nil then begin
        if Q.AcceptanceItem<>0 then begin SetLength(Q.AcceptanceItems,1);Q.AcceptanceItems[0]:=Q.AcceptanceItem;end;
      end else begin
        if Children.Count>5 then raise Exception.Create('Invalid acceptance item count');
        SetLength(Q.AcceptanceItems,Children.Count);
        for J:=0 to Children.Count-1 do begin
          if not (Children.Items[J] is TJSONNumber) or
            not TryStrToInt64(Children.Items[J].Value,N) or (N<1) or (N>High(Cardinal)) then
            raise Exception.Create('Invalid acceptance item number');
          Q.AcceptanceItems[J]:=Cardinal(N);
          if Q.AcceptanceItems[J]=0 then raise Exception.Create('Invalid acceptance item');
          for K:=0 to J-1 do if Q.AcceptanceItems[K]=Q.AcceptanceItems[J] then
            raise Exception.Create('Duplicate acceptance item');
        end;
        if ((Length(Q.AcceptanceItems)=0) and (Q.AcceptanceItem<>0)) or
          ((Length(Q.AcceptanceItems)>0) and (Q.AcceptanceItems[0]<>Q.AcceptanceItem)) then
          raise Exception.Create('Acceptance primary item mismatch');
      end;
      Q.Enabled:=V.GetValue<Boolean>('enabled');
      Q.Repeatable:=V.GetValue<Integer>('nativeType',0)=3;
      if (Q.ID<19003001) or (Q.ID>19003047) or (Q.MinLevel=0) or (Q.MaxLevel<Q.MinLevel) then raise Exception.Create('Invalid quest identity/level');
      for J:=0 to I-1 do if FRows[J].ID=Q.ID then raise Exception.Create('Duplicate quest');
      Children:=V.GetValue<TJSONArray>('objectives');SetLength(Q.Objectives,Children.Count);J:=0;
      if (Children.Count=0) or (Children.Count>7) then raise Exception.Create('Invalid quest objectives');
      for W in Children do begin
        O.Index:=W.GetValue<Cardinal>('index');O.Kind:=W.GetValue<Cardinal>('kind');
        O.Target:=W.GetValue<Cardinal>('target');O.Required:=W.GetValue<Cardinal>('required');
        O.SourceMob:=W.GetValue<Cardinal>('sourceMob');O.DropChanceBP:=W.GetValue<Cardinal>('dropChanceBP',0);
        O.ItemSource:=W.GetValue<string>('itemSource','mob');
        O.RequiredGemID:=W.GetValue<Cardinal>('requiredGemId',0);
        if (O.RequiredGemID<>0) and (not (O.Kind in [3,9]) or
          not TB1008Items.Find(O.RequiredGemID,D)) then raise Exception.Create('Invalid required quest gem');
        if (O.Index>6) or (O.Target=0) or (O.Required=0) or (O.Required>10000) or
          (Q.Enabled and not (O.Kind in [1,2,3,8,9])) then raise Exception.Create('Unsupported enabled objective');
        if Q.Enabled and (O.Kind=3) then begin
          if not TB1008Items.Find(O.Target,D) then raise Exception.Create('Invalid collection item');
          if O.ItemSource='mob' then begin
            if (O.SourceMob=0) or (O.DropChanceBP=0) or (O.DropChanceBP>10000) then
              raise Exception.Create('Invalid collection drop');
          end else if (O.SourceMob<>0) or (O.DropChanceBP<>0) or
            not ((O.ItemSource='mining') or (O.ItemSource='acceptance') or
                 (O.ItemSource='crafting')) then raise Exception.Create('Invalid non-mob collection source');
        end;
        for K:=0 to J-1 do if (Q.Objectives[K].Index=O.Index) or
          ((Q.Objectives[K].Kind=O.Kind) and (Q.Objectives[K].Target=O.Target)) then raise Exception.Create('Ambiguous objective');
        Q.Objectives[J]:=O;Inc(J);
      end;
      Children:=V.GetValue<TJSONArray>('rewards');SetLength(Q.Rewards,Children.Count);J:=0;
      for W in Children do begin
        R.Index:=W.GetValue<Cardinal>('index');R.Kind:=W.GetValue<Cardinal>('kind');
        R.Value:=W.GetValue<Cardinal>('value');R.Amount:=W.GetValue<Cardinal>('amount');R.Choice:=W.GetValue<Integer>('choice')<>0;
        if (R.Index>9) or not (R.Kind in [1,2,3]) or (R.Value=0) or
          (Q.Enabled and (R.Kind=3) and (not TB1008Items.Find(R.Value,D) or (R.Amount=0))) then raise Exception.Create('Unsupported enabled reward');
        Q.Rewards[J]:=R;Inc(J);
      end;
      if Q.Enabled and (Q.AcceptanceItem<>0) and not TB1008Items.Find(Q.AcceptanceItem,D) then raise Exception.Create('Unknown acceptance item');
      if Q.Enabled then for J:=0 to High(Q.AcceptanceItems) do
        if not TB1008Items.Find(Q.AcceptanceItems[J],D) then raise Exception.Create('Unknown acceptance item');
      FRows[I]:=Q;Inc(I);
    end;
    for Q in FRows do if Q.Enabled and (Q.Previous<>0) then
      if not Get(Q.Previous).Enabled then raise Exception.Create('Enabled quest depends on disabled predecessor');
  finally Root.Free;end;
end;

class function TB1008QuestCatalog.All:TArray<TB1008QuestDefinition>;
begin Result:=Copy(FRows);end;
class function TB1008QuestCatalog.Find(ID:Cardinal;out Q:TB1008QuestDefinition):Boolean;
var Row:TB1008QuestDefinition;
begin
  for Row in FRows do if Row.ID=ID then begin Q:=Row;Exit(True);end;
  Q:=Default(TB1008QuestDefinition);Result:=False;
end;
class function TB1008QuestCatalog.Get(ID:Cardinal):TB1008QuestDefinition;
begin if not Find(ID,Result) then raise EArgumentException.Create('Unknown quest');end;
class function TB1008QuestCatalog.Ready(const Entry:TB1008QuestEntry):Boolean;
var Q:TB1008QuestDefinition;O:TB1008QuestObjective;
begin
  Q:=Get(Entry.ID);Result:=False;if Entry.Completed or not Q.Enabled then Exit;
  for O in Q.Objectives do if Entry.Counts[O.Index]<O.Required then Exit;
  Result:=True;
end;

class function TB1008QuestCatalog.RollDrop(var State:Cardinal;const Need:TB1008QuestDropNeed;
  GroundAmount:Cardinal;Rate:Integer):Cardinal;
var Missing:Cardinal;
begin
  Result:=0;if (Need.Missing<=GroundAmount) or (Rate=0) then Exit;
  Missing:=Need.Missing-GroundAmount;
  if State=0 then State:=$9E3779B9;
  State:=State xor (State shl 13);State:=State xor (State shr 17);State:=State xor (State shl 5);
  Result:=TB1008Rates.DropIntervalCount(0,1,1,Need.ChanceBP,Rate,State mod 1000000);
  if Result>Missing then Result:=Missing;
end;

end.
