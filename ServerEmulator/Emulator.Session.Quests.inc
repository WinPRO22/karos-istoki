function TEmulatorSession.HandlePacket(const APayload:TBytes;out AReplies:TB1008Replies):string;
var Before:TArray<TB1008QuestEntry>;E,Old:TB1008QuestEntry;D:TB1008QuestDefinition;
  O:TB1008QuestObjective;U:TB1008QuestUpdate;Previous:Cardinal;Track:Boolean;
begin
  // Only inventory/quest commands can change collection progress. Movement
  // and combat packets do not incur an extra inventory scan.
  Track:=(Length(APayload)>=6) and (APayload[0] in [6,8,9]) and Assigned(FLoot) and
    (FStage=ssAppearanceProbe) and FWorldState.Active;
  Before:=nil;if Track then Before:=FLoot.QuestEntries(Self);
  Result:=HandlePacketCore(APayload,AReplies);
  if not Track or not FWorldState.Active then Exit;
  for E in FLoot.QuestEntries(Self) do if not E.Completed then begin
    D:=TB1008QuestCatalog.Get(E.ID);
    for O in D.Objectives do if O.Kind in [3,9] then begin
      Previous:=0;
      for Old in Before do if Old.ID=E.ID then begin Previous:=Old.Counts[O.Index];Break;end;
      if Previous=E.Counts[O.Index] then Continue;
      // Perform already emits the native delivery update itself.
      if (O.Kind=9) and (APayload[0]=9) and (APayload[1]=3) then Continue;
      U.QuestID:=E.ID;U.Kind:=O.Kind;U.Target:=O.Target;U.Count:=E.Counts[O.Index];
      SetLength(AReplies,Length(AReplies)+1);
      AReplies[High(AReplies)]:=TB1008QuestWire.BuildUpdate(TB1008Wire.ReadBE32(APayload,2),1,U);
    end;
  end;
end;

procedure TEmulatorSession.AppendQuestItems(Timestamp:Cardinal;const Items:TArray<TB1008BagItem>;var Replies:TB1008Replies);
var Item:TB1008BagItem;
begin
  for Item in Items do begin
    SetLength(Replies,Length(Replies)+1);
    if Item.Amount=0 then Replies[High(Replies)]:=TB1008InventoryWire.BuildPutOut(Timestamp,1,Item.ItemID,Item.Slot)
    else Replies[High(Replies)]:=TB1008InventoryWire.BuildPutIn(Timestamp,1,Item);
  end;
end;

procedure TEmulatorSession.AppendCatalogQuests(Timestamp:Cardinal;var Replies:TB1008Replies);
var E:TB1008QuestEntry;Active:TArray<TB1008QuestEntry>;Done:TArray<Cardinal>;
  D:TB1008QuestDefinition;O:TB1008QuestObjective;U:TB1008QuestUpdate;
begin
  if not Assigned(FLoot) then Exit;
  Active:=nil;Done:=nil;
  for E in FLoot.QuestEntries(Self) do
    if E.Completed then begin
      if not TB1008QuestCatalog.Get(E.ID).Repeatable then begin
        SetLength(Done,Length(Done)+1);Done[High(Done)]:=E.ID;
      end;
    end
    else begin SetLength(Active,Length(Active)+1);Active[High(Active)]:=E;end;
  if Length(Active)>0 then begin
    SetLength(Replies,Length(Replies)+1);Replies[High(Replies)]:=TB1008QuestWire.BuildEntries(Timestamp,1,Active);
    // Native restoration initially marks entries active. Progress notifications
    // rebuild each completed objective and promote a ready entry for hand-in.
    for E in Active do begin
      D:=TB1008QuestCatalog.Get(E.ID);
      for O in D.Objectives do if E.Counts[O.Index]>0 then begin
        U.QuestID:=E.ID;U.Kind:=O.Kind;U.Target:=O.Target;U.Count:=E.Counts[O.Index];
        SetLength(Replies,Length(Replies)+1);Replies[High(Replies)]:=TB1008QuestWire.BuildUpdate(Timestamp,1,U);
      end;
    end;
  end;
  if Length(Done)>0 then begin
    SetLength(Replies,Length(Replies)+1);Replies[High(Replies)]:=TB1008QuestWire.BuildCompleted(Timestamp,1,Done);
  end;
end;

function TEmulatorSession.HandleCatalogQuest(const Packet:TBytes;out Replies:TB1008Replies):string;
var Start:TB1008QuestStart;Reward:TB1008QuestReward;Perform:TB1008QuestPerform;
  D:TB1008QuestDefinition;U:TB1008QuestUpdate;Updated:TArray<TB1008BagItem>;P:TB1008Progress;
  Stamp,CharacterID,ID,Code,NpcID:Cardinal;Accepted:Boolean;ResultCode:Byte;
begin
  Replies:=nil;
  case Packet[1] of
    0:begin Start:=TB1008QuestWire.ParseStart(Packet);Stamp:=Start.Timestamp;CharacterID:=Start.CharacterID;ID:=Start.QuestID;Code:=Start.Code;end;
    1:begin Reward:=TB1008QuestWire.ParseReward(Packet);Stamp:=Reward.Timestamp;CharacterID:=Reward.CharacterID;ID:=Reward.QuestID;Code:=Reward.Code;end;
    3:begin Perform:=TB1008QuestWire.ParsePerform(Packet);Stamp:=Perform.Timestamp;CharacterID:=Perform.CharacterID;ID:=Perform.QuestID;Code:=Perform.Code;end;
  else raise EKarosProtocol.Create('Unsupported quest operation');end;
  if (FLoginMode<>blMapLoadingProbe) or (FStage<>ssAppearanceProbe) or not FWorldState.Active or
    (FPlayerHP<=0) or (CharacterID<>FWorldState.CharacterID) or (Code<>B1008QuestStartCode) then
    Exit('QUEST REJECTED | invalid living session/identity/code');
  Accepted:=TB1008QuestCatalog.Find(ID,D) and D.Enabled;
  if Accepted then begin
    if Packet[1]=0 then NpcID:=D.Giver else NpcID:=D.Receiver;
    Accepted:=TB1008Npcs.Near(NpcID,FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y);
  end;
  Updated:=nil;
  if Accepted then case Packet[1] of
    0:Accepted:=FLoot.AcceptQuest(Self,ID,Assigned(FQuests) and FQuests.Active(Self),Updated);
    1:Accepted:=FLoot.RewardQuest(Self,ID,Reward.Choice,Updated,P);
    3:Accepted:=FLoot.PerformQuest(Self,ID,Perform.Kind,Perform.Target,Perform.Count,U);
  end;
  ResultCode:=$A3;if Accepted then ResultCode:=B1008QuestStartCode;
  if Accepted then AppendQuestItems(Stamp,Updated,Replies);
  case Packet[1] of
    0:begin SetLength(Replies,Length(Replies)+1);Replies[High(Replies)]:=TB1008QuestWire.BuildStartAck(Stamp,1,ID,ResultCode);end;
    1:begin
      if Accepted then begin
        AcceptProgress(P);FFletta:=FLoot.Fletta(Self);
        SetLength(Replies,Length(Replies)+1);Replies[High(Replies)]:=PlayerGage(Stamp,True);
      end;
      SetLength(Replies,Length(Replies)+1);Replies[High(Replies)]:=TB1008QuestWire.BuildRewardAck(Stamp,1,ID,Reward.Choice,ResultCode);
    end;
    3:if Accepted then begin SetLength(Replies,1);Replies[0]:=TB1008QuestWire.BuildUpdate(Stamp,1,U);end;
  end;
  if Accepted then Result:='QUEST CATALOG COMMITTED' else Result:='QUEST CATALOG REJECTED';
  Result:=Result+Format(' | command=09/%d quest=%u; authoritative conditions and atomic reward',[Packet[1],ID]);
end;
