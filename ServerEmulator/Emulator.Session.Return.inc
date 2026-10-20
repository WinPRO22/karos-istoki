procedure TEmulatorSession.ApplyReturnInfo(var Packet:TBytes);
begin
  if Assigned(FLoot) then TB1008ReturnWire.ApplyInfo(Packet,FLoot.ReturnState(Self).Point);
end;

procedure TEmulatorSession.AppendReturnCooldown(Timestamp:Cardinal;var Replies:TB1008Replies);
var Seconds:Int64;
begin
  Seconds:=(FLoot.ReturnState(Self).UntilMS-B1008UtcNowMS+999) div 1000;
  if Seconds<=0 then Exit;
  SetLength(Replies,Length(Replies)+1);
  Replies[High(Replies)]:=TB1008ReturnWire.Cooldown(Timestamp,Min(Int64(B1008ReturnCooldownMS div 1000),Seconds));
end;

procedure TEmulatorSession.RecoverReturn;
begin
  if not Assigned(FLoot) or not FLoot.ReturnState(Self).Pending then Exit;
  // SQLite commits intent first; the separate atomic world checkpoint follows.
  // A crash between these writes retries the same destination at the next login.
  FWorld.Checkpoint(Self,TB1008ReturnWire.Position);FLoot.CompleteReturn(Self);
end;

function TEmulatorSession.HandleReturn(const Packet:TBytes;out Replies:TB1008Replies):string;
var Bind:TB1008ReturnSave;UseItem:TB1008ItemUse;Near:Boolean;Npc:TB1008Npc;
  I,N:Integer;Stamp:Cardinal;P:TBytes;
begin
  Replies:=nil;
  if not Assigned(FLoot) or (FStage<>ssAppearanceProbe) or not FWorldState.Active or
    (FPlayerHP<=0) then Exit('RETURN REJECTED | no living admitted owner');
  if Packet[1]=$23 then begin
    Bind:=TB1008ReturnSave.Parse(Packet);Near:=False;
    for Npc in TB1008Npcs.All do if (Npc.Handle=Bind.NpcHandle) and (Npc.ID=99001) then
      Near:=TB1008Npcs.Near(Npc.ID,FWorldState.Position.X,FWorldState.Position.Z,FWorldState.Position.Y);
    Near:=Near and (Bind.Slot=1) and (Bind.Code=$5C) and (Bind.Destination=0);
    if Near then FLoot.BindReturn(Self);
    SetLength(Replies,1);Replies[0]:=Bind.Reply(Near);
    if Near then Exit('RETURN POINT SAVED | default slot=1, Berneo Remember Stone')
    else Exit('RETURN BIND REJECTED | NPC distance or unsupported slot');
  end;
  UseItem:=TB1008InventoryWire.ParseUse(Packet);Stamp:=UseItem.Timestamp;
  if (UseItem.CharacterID<>FWorldState.CharacterID) or (UseItem.Page<>1) or
    (UseItem.ItemID<>B1008ReturningStoneID) or (UseItem.Parameter<>0) or (UseItem.Code<>1) then
    Exit('RETURN REJECTED | unsupported item use');
  if not FLoot.UseReturn(Self,FInventorySessionID+':'+UIntToStr(Stamp),UseItem.Slot) then
    Exit('RETURN REJECTED | missing stone, unbound point, duplicate or cooldown');
  RecoverReturn;
  SetLength(Replies,1);Replies[0]:=TB1008InventoryWire.BuildUseAck(UseItem);
  RemoveFrenzy(Stamp,Replies);RemoveFlettaBarrier(Stamp,Replies);
  FRevenge.UntilTick:=0;FDeathLeap.UntilTick:=0;PollProfessionBuffs(Stamp,Replies);
  FHasPendingAttack:=False;FPendingSpiderHandle:=0;FSkillCast.Cancel;
  FFlettaProc:=Default(TB1008FlettaProc);FBodyBlowCharge:=Default(TB1008ChargeAdmission);
  FTornadoVisualUntilTick:=0;FSkillEndTarget:=0;FSkillImpactUntilTick:=0;
  FPlayerAutoAttacking:=False;FRegeneration.ResetPeaceful;
  FMovementAdmission.Reset;FWorldState.Moving:=False;
  FWorldState.Position:=TB1008ReturnWire.Position;FWorldState.HasCheckpoint:=True;
  FClientInWorld:=False;FWorldPatrolStarted:=False;FWorldState.Active:=False;
  FStashNpcHandle:=0;FRespawnLoading:=False;
  for I:=0 to High(FSpiders) do begin
    FSpiders[I].AI.Stop;FSpiders[I].StunEffectActive:=False;FSpiders[I].Coercive.Clear;
    FSpiders[I].WindBleed.Clear;
    FillChar(FSpiders[I].ProfessionEffects,SizeOf(FSpiders[I].ProfessionEffects),0);
    FSpiders[I].Encounter.Free;
    FSpiders[I].Encounter:=TB1008SpiderEncounter.Create(FSpiders[I].Definition.MaxHP,TB1008Balance.PlayerDamage);
  end;
  P:=TB1008World.BuildCharacterInfoProbe(FCharacters.Preview(Stamp),Stamp);
  TB1008ClassWire.ApplyCharacterInfo(P,FClassState);
  TB1008ProgressWire.ApplyBaseAttributes(P,FPlayerClassID);
  TB1008ProgressWire.ApplyCombatParameters(P,FPlayerClassID,FProgress.Level);
  TB1008Equipment.ApplyCharacterInfo(P,FEquipment);FFlettaAttributes.ApplyCharacterInfo(P);
  ApplyPlayerParameters(P);TB1008ProgressWire.ApplyCharacterInfo(P,FProgress);
  FFletta.Apply(P,FProgress.Level);ApplyReturnInfo(P);
  TB1008ProgressWire.ApplyVitals(P,FPlayerHP,FPlayerMP,PlayerMaxHP,PlayerMaxMP);
  N:=Length(Replies);SetLength(Replies,N+2);Replies[N]:=P;
  // Original 52A647 handles a same-map zone transition as a scene reload too.
  Replies[N+1]:=TB1008World.BuildZoneProbe(Stamp);FStage:=ssMapLoadingProbe;
  Result:='RETURN COMMITTED | Berneo, vitals retained, permanent stone, cooldown=600s';
end;
