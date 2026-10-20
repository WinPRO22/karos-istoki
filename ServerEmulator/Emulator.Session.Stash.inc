function TEmulatorSession.HandleStash(const Packet:TBytes;out Replies:TB1008Replies):string;
var R:TB1008StashRequest;Npc:TB1008Npc;Near:Boolean;Handle,Amount:Cardinal;
  Updated,StashUpdated:TArray<TB1008BagItem>;Receipt:string;Ack:TB1008StashRequest;
  Item:TB1008BagItem;I:Integer;
begin
  Replies:=nil;
  if Packet[1]=$2A then begin
    // 4336AC -> 432484: NPC interaction requests paid extension levels.
    if (Length(Packet)<>16) or (Packet[14]<>0) or (Packet[15]<>0) then
      raise EKarosProtocol.Create('Invalid stash capacity request');
    R:=Default(TB1008StashRequest);R.Kind:=$2A;
    R.Timestamp:=TB1008Wire.ReadBE32(Packet,2);R.CharacterID:=TB1008Wire.ReadBE32(Packet,6);
    R.NpcHandle:=TB1008Wire.ReadBE32(Packet,10);
  end else R:=TB1008StashRequest.Parse(Packet);
  if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active or
    (FPlayerHP<=0) or (R.CharacterID<>FWorldState.CharacterID) then
    Exit('STASH REJECTED | no living admitted owner');
  Handle:=R.NpcHandle;
  // Native RMB withdrawal (479573 -> 512429) sends NPC=-1. Resolve it
  // only against an admitted open stash, still checking the NPC distance.
  if (R.Kind=$28) or ((R.Kind=$1B) and (Handle=High(Cardinal))) then
    Handle:=FStashNpcHandle;
  Near:=False;
  // npcInfo bit 17 -> 4FC85B -> bank service; Anne is its Berneo instance.
  for Npc in TB1008Npcs.All do if (Npc.Handle=Handle) and (Npc.ID=9300131) then
    Near:=TB1008Npcs.Near(Npc.ID,FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y);
  if not Near then begin
    FStashNpcHandle:=0;
    if R.Kind<>$2A then begin SetLength(Replies,1);Replies[0]:=R.Reply(False);end;
    Exit(Format('STASH REJECTED | NPC %d unavailable or out of range',[Handle]));
  end;
  if R.Kind=$2A then begin
    SetLength(Replies,1);Replies[0]:=TB1008StashWire.Capacity(R.Timestamp,R.CharacterID);
    Exit('STASH CAPACITY | 32 personal cells, no purchased extensions');
  end;
  if R.Kind=$1C then begin
    if (R.Code<>$91) or (R.Page<>0) or (R.Slot<>0) or (R.Amount<>0) then
      Exit('STASH LIST REJECTED | unsupported request fields');
    FStashNpcHandle:=Handle;SetLength(Replies,2);
    Replies[0]:=TB1008StashWire.Capacity(R.Timestamp,R.CharacterID);
    Replies[1]:=TB1008StashWire.List(R,FLoot.StashItems(Self));
    Exit('STASH OPEN | saved personal items restored');
  end;
  SetLength(Replies,1);Replies[0]:=R.Reply(False);
  if Handle<>FStashNpcHandle then Exit('STASH REJECTED | storage must be opened first');
  Receipt:=FInventorySessionID+':'+IntToHex(R.Kind,2)+':'+UIntToStr(R.Timestamp);
  try
    if not FLoot.TransferStash(Self,Receipt,R,Amount,Updated,StashUpdated) then
      Exit('STASH REJECTED | stale, duplicate, invalid or insufficient space');
  except on E:Exception do Exit('STASH NOT COMMITTED | inventory retained; '+E.Message);end;
  // Deposit handler copies source item quality. It must see the old bag cell.
  if R.Kind=$1A then begin
    SetLength(Replies,Length(StashUpdated));I:=0;
    for Item in StashUpdated do begin
      Ack:=R;Ack.TargetSlot:=Item.Slot;Replies[I]:=Ack.Reply(True,Item.Amount);Inc(I);
    end;
  end else if (R.Kind=$28) and (Length(StashUpdated)>0) then begin
    // The native swap ACK exchanges cells, so use exact cell updates for a merge.
    // First clear removed sources, then restore the full list/currency display.
    Replies:=nil;
    for Item in StashUpdated do if Item.Amount=0 then begin
      Ack:=Default(TB1008StashRequest);Ack.Kind:=$1B;Ack.Timestamp:=R.Timestamp;
      Ack.CharacterID:=R.CharacterID;Ack.Slot:=Item.Slot;Ack.Amount:=-1;
      I:=Length(Replies);SetLength(Replies,I+1);Replies[I]:=Ack.Reply(True);
    end;
    Ack:=R;Ack.Kind:=$1C;Ack.NpcHandle:=Handle;
    I:=Length(Replies);SetLength(Replies,I+1);Replies[I]:=TB1008StashWire.List(Ack,FLoot.StashItems(Self));
  end else Replies[0]:=R.Reply(True,Amount);
  AppendQuestItems(R.Timestamp,Updated,Replies);
  Result:=Format('STASH COMMITTED | command=%x slot=%d destination=%d balance=%d',
    [R.Kind,R.Slot,R.TargetSlot,Amount]);
end;
