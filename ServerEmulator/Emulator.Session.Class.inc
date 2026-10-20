function TEmulatorSession.HandleClassChange(const Packet:TBytes;out Replies:TB1008Replies):string;
var R:TB1008ClassChange;Code:Word;Items:TArray<TB1008BagItem>;State:TB1008ClassState;
  Changed:Boolean;OldHP,OldMP:Integer;
begin
  Replies:=nil;R:=TB1008ClassChange.Parse(Packet);Code:=$86;Changed:=False;
  OldHP:=PlayerMaxHP;OldMP:=PlayerMaxMP;
  // Native stash close has no server notification. Leaving Anne invalidates
  // the remembered service context before another NPC operation is admitted.
  if (FStashNpcHandle<>0) and FWorldState.Active and
    not TB1008Npcs.Near(9300131,FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y) then
    FStashNpcHandle:=0;
  if Assigned(FLoot) and (FStage=ssAppearanceProbe) and FWorldState.Active and
    (FPlayerHP>0) and not FHasPendingAttack and not FPlayerAutoAttacking and
    (FStashNpcHandle=0) then begin
    try
      Code:=FLoot.ChangeClass(Self,FInventorySessionID+'/class/'+UIntToStr(R.Timestamp),R,State,Items);
      if Code=$81 then begin
        Changed:=(FClassState.ClassID<>State.ClassID) or (FClassState.Rank<>State.Rank);
        FClassState:=State;
      end;
    except on E:Exception do begin
      SetLength(Replies,1);Replies[0]:=R.Ack($86);
      Exit('CLASS CHANGE NOT COMMITTED | '+E.Message);
    end;end;
  end;
  // Absolute inventory updates precede native success: the ACK itself does not pay.
  if Code=$81 then AppendQuestItems(R.Timestamp,Items,Replies);
  SetLength(Replies,Length(Replies)+1);Replies[High(Replies)]:=R.Ack(Code);
  if (Code=$81) and Changed then begin
    FPlayerHP:=Min(PlayerMaxHP,FPlayerHP+Max(0,PlayerMaxHP-OldHP));
    FPlayerMP:=Min(PlayerMaxMP,FPlayerMP+Max(0,PlayerMaxMP-OldMP));
    SetLength(Replies,Length(Replies)+2);
    Replies[High(Replies)-1]:=TB1008ProgressWire.BuildParameters(R.Timestamp,FPlayerClassID,FProgress.Level);
    ApplyPlayerParameters(Replies[High(Replies)-1]);
    Replies[High(Replies)]:=PlayerGage(R.Timestamp,False);
  end;
  Result:=Format('CLASS CHANGE | target=%u rank=%u result=%u; durable profession, base family preserved',
    [R.TargetClass,R.TargetRank,Code]);
end;
