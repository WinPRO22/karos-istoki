procedure TEmulatorSession.ApplyProfessionSpeeds(var Packet:TBytes);
var Offset:Integer;Value:Single;Gear:TB1008EquipmentItem;Multiplier:Single;
begin
  Multiplier:=1;
  for Gear in FEquipment do if Gear.Slot=7 then
    Multiplier:=TB1008Balance.WeaponAutoAttackSpeed(TB1008Items.Get(Gear.ItemID).Subtype);
  if (Packet[0]=2) and (Packet[1]=5) then Offset:=$2C
  else if (Packet[0]=4) and (Packet[1]=2) then Offset:=52
  else if (Packet[0]=8) and (Packet[6]=0) then Offset:=35 else Exit;
  Move(Packet[Offset],Value,4);Value:=Value*Multiplier;
  if FDeathLeap.Active(GetTickCount64) then Value:=Value*(1+
    TB1008ProfessionSkill.Get(FDeathLeap.SkillID,FDeathLeap.Rank).AttackSpeedPercent/100);
  Move(Value,Packet[Offset],4);
end;

procedure TEmulatorSession.PollProfessionBuffs(NowTick:UInt64;var Replies:TB1008Replies);
var I:Integer;E:^TB1008ProfessionEffect;Changed:Boolean;
begin
  Changed:=False;
  for I:=0 to 1 do begin
    if I=0 then E:=@FRevenge else E:=@FDeathLeap;
    if (E^.SkillID=0) or ((FPlayerHP>0) and E^.Active(NowTick)) then Continue;
    SetLength(Replies,Length(Replies)+1);
    Replies[High(Replies)]:=TB1008SkillWire.BuildProfessionEffect(NowTick and $FFFFFFFF,
      0,1,E^.SkillID,E^.Rank,0,False);E^.Clear;Changed:=True;
  end;
  if Changed then begin
    SetLength(Replies,Length(Replies)+2);
    Replies[High(Replies)-1]:=TB1008ProgressWire.BuildParameters(NowTick and $FFFFFFFF,FPlayerClassID,FProgress.Level);
    ApplyPlayerParameters(Replies[High(Replies)-1]);Replies[High(Replies)]:=PlayerGage(NowTick and $FFFFFFFF,False);
  end;
end;

function TEmulatorSession.MobProfessionSpeed(AIndex:Integer;NowTick:UInt64;ModifierType:Cardinal):Single;
var E:TB1008ProfessionEffect;Slow,J:Integer;D:TB1008ProfessionSkill;
begin
  Slow:=0;
  for E in FSpiders[AIndex].ProfessionEffects do if E.Active(NowTick) then begin
    D:=TB1008ProfessionSkill.Get(E.SkillID,E.Rank);
    for J:=0 to D.RawModifierCount-1 do if D.RawModifiers[J].TypeCode=ModifierType then
      Slow:=Max(Slow,Round(-D.RawModifiers[J].Value20));
  end;
  Result:=Max(0.01,1-Slow/100);
end;

procedure TEmulatorSession.RefreshProfessionSpeed(AIndex:Integer;Timestamp:Cardinal;NowTick:UInt64;var Replies:TB1008Replies);
var M:TB1008MobMovement;Factor:Single;Moving:Boolean;
begin
  Factor:=MobProfessionSpeed(AIndex,NowTick);
  Moving:=FSpiders[AIndex].AI.SetSpeedMultiplier(NowTick,Factor,M);
  if not FSpiders[AIndex].Visible then Exit;
  SetLength(Replies,Length(Replies)+1);
  Replies[High(Replies)]:=TB1008CombatWire.BuildSpiderGageProbe(Timestamp,FSpiders[AIndex].Handle,
    FSpiders[AIndex].Encounter.HP,FSpiders[AIndex].Definition.MaxHP,
    FSpiders[AIndex].Definition.MovementSpeed*Factor,FSpiders[AIndex].AI.ActiveChaseSpeed,
    FSpiders[AIndex].Definition.AttackSpeed*MobProfessionSpeed(AIndex,NowTick,13));
  FSpiders[AIndex].SentChaseSpeed:=FSpiders[AIndex].AI.ActiveChaseSpeed;
  // Native NPC movement reads the speed at dispatch: publish gage first.
  if Moving then begin
    SetLength(Replies,Length(Replies)+1);
    Replies[High(Replies)]:=TB1008World.BuildActorMovement(Timestamp,1,M.Mode,FSpiders[AIndex].Handle,
      M.FromX,M.FromZ,M.FromY,M.ToX,M.ToZ,M.ToY,M.Heading);
  end;
end;

procedure TEmulatorSession.RemoveProfessionEffects(AIndex:Integer;Timestamp:Cardinal;var Replies:TB1008Replies);
var I:Integer;E:^TB1008ProfessionEffect;Changed:Boolean;
begin
  Changed:=False;
  for I:=0 to 2 do begin
    E:=@FSpiders[AIndex].ProfessionEffects[I];if E^.SkillID=0 then Continue;
    if FSpiders[AIndex].Visible then begin
      SetLength(Replies,Length(Replies)+1);
      Replies[High(Replies)]:=TB1008SkillWire.BuildProfessionEffect(Timestamp,1,FSpiders[AIndex].Handle,
        E^.SkillID,E^.Rank,0,False);
    end;
    E^.Clear;Changed:=True;
  end;
  if Changed then RefreshProfessionSpeed(AIndex,Timestamp,GetTickCount64,Replies);
end;

procedure TEmulatorSession.ApplyProfessionHit(AIndex:Integer;Timestamp:Cardinal;NowTick:UInt64;var Replies:TB1008Replies);
var ID,Rank:Cardinal;D:TB1008ProfessionSkill;Slot:Integer;M:TB1008MobMovement;
begin
  ID:=FSkillCast.ActiveSkillID;Rank:=FSkillCast.ActiveRank;
  if not TB1008ProfessionSkill.Supported(ID) or (FSpiders[AIndex].Encounter.HP=0) then Exit;
  D:=TB1008ProfessionSkill.Get(ID,Rank);
  if (D.StunMS>0) and D.StunChanceKnown and
    (TB1008CombatDamage.Roll(FCombatRandomState,1,10000)<=Integer(D.StunChanceBasisPoints)) and
    FSpiders[AIndex].AI.Stun(NowTick,D.StunMS,M) then begin
    RemoveSpiderStunEffect(AIndex,Timestamp,Replies);
    SetLength(Replies,Length(Replies)+2);
    Replies[High(Replies)-1]:=TB1008World.BuildActorMovement(Timestamp,1,2,FSpiders[AIndex].Handle,
      M.FromX,M.FromZ,M.FromY,M.ToX,M.ToZ,M.ToY,M.Heading);
    Replies[High(Replies)]:=TB1008SkillWire.BuildProfessionEffect(Timestamp,1,FSpiders[AIndex].Handle,
      ID,Rank,D.StunMS,True);FSpiders[AIndex].StunEffectActive:=True;FSpiders[AIndex].StunEffectSkillID:=ID;
  end;
  case ID of
    B1008SpineBreakerID:Slot:=0;
    B1008SlaterID:Slot:=1;
    B1008PhantomThrustID:Slot:=2;
  else Exit;end;
  FSpiders[AIndex].ProfessionEffects[Slot].Start(ID,Rank,NowTick);
  SetLength(Replies,Length(Replies)+1);
  Replies[High(Replies)]:=TB1008SkillWire.BuildProfessionEffect(Timestamp,1,FSpiders[AIndex].Handle,
    ID,Rank,D.DurationMS,True);
  RefreshProfessionSpeed(AIndex,Timestamp,NowTick,Replies);
end;

procedure TEmulatorSession.PollProfessionEffects(AIndex:Integer;NowTick:UInt64;var Replies:TB1008Replies);
var I,Damage:Integer;E:^TB1008ProfessionEffect;Due:TB1008ProfessionEffect;
  R:TB1008AttackStart;Changed,LegacyQuest:Boolean;QuestProgress:Cardinal;
begin
  if (FPlayerHP<=0) or (FSpiders[AIndex].Encounter.HP=0) or not FSpiders[AIndex].Visible then begin
    RemoveProfessionEffects(AIndex,NowTick and $FFFFFFFF,Replies);Exit;
  end;
  Changed:=False;
  for I:=0 to 2 do begin
    E:=@FSpiders[AIndex].ProfessionEffects[I];if E^.SkillID=0 then Continue;
    Due:=E^;
    while Due.TakeDue(NowTick,Damage) do begin
      LegacyQuest:=(FSpiders[AIndex].Encounter.HP<=Damage) and (FSpiders[AIndex].Spawn.MobID=120) and
        Assigned(FQuests) and FQuests.Active(Self) and (FQuests.Progress(Self)<5);
      QuestProgress:=0;if LegacyQuest then QuestProgress:=FQuests.RecordSpiderKill(Self);
      E^:=Due;
      if not FSpiders[AIndex].Encounter.ApplyPeriodicDamage(Damage,NowTick) then Break;
      R:=Default(TB1008AttackStart);R.ActorID:=1;R.Timestamp:=NowTick and $FFFFFFFF;
      R.ActionKind:=1;R.ActionID:=TB1008ProfessionSkill.Get(E^.SkillID,E^.Rank).ActionID;
      R.TargetKind:=1;R.TargetID:=FSpiders[AIndex].Handle;
      SetLength(Replies,Length(Replies)+2);
      Replies[High(Replies)-1]:=TB1008CombatWire.BuildSpiderDamageProbe(R,
        FSpiders[AIndex].AI.X,FSpiders[AIndex].AI.Z,FSpiders[AIndex].AI.Y,Damage);
      Replies[High(Replies)]:=TB1008CombatWire.BuildSpiderGageProbe(R.Timestamp,R.TargetID,
        FSpiders[AIndex].Encounter.HP,FSpiders[AIndex].Definition.MaxHP,
        FSpiders[AIndex].Definition.MovementSpeed*MobProfessionSpeed(AIndex,NowTick),
        FSpiders[AIndex].AI.ActiveChaseSpeed,FSpiders[AIndex].Definition.AttackSpeed*MobProfessionSpeed(AIndex,NowTick,13));
      if LegacyQuest then begin
        SetLength(Replies,Length(Replies)+1);Replies[High(Replies)]:=TB1008QuestWire.BuildProgress(R.Timestamp,QuestProgress);
      end;
      if FSpiders[AIndex].Encounter.HP=0 then begin
        RemoveSpiderStunEffect(AIndex,R.Timestamp,Replies);RemoveSpiderCoercive(AIndex,R.Timestamp,Replies);
        RemoveWindBleed(AIndex,R.Timestamp,Replies);RemoveProfessionEffects(AIndex,R.Timestamp,Replies);
        if FPendingAttack.TargetID=R.TargetID then begin FHasPendingAttack:=False;FPendingSpiderHandle:=0;FPlayerAutoAttacking:=False;end;
        if (FFlettaProc.Phase<>fppIdle) and (FFlettaProc.Target=R.TargetID) then begin
          FFlettaProc.Clear;SetLength(Replies,Length(Replies)+1);
          Replies[High(Replies)]:=TB1008FlettaProc.BuildTrigger(R.Timestamp,High(Cardinal));
        end;
        CommitMobKill(AIndex,R.Timestamp,Replies);Exit;
      end;
    end;
    if not E^.Active(NowTick) then begin
      SetLength(Replies,Length(Replies)+1);
      Replies[High(Replies)]:=TB1008SkillWire.BuildProfessionEffect(NowTick and $FFFFFFFF,1,
        FSpiders[AIndex].Handle,E^.SkillID,E^.Rank,0,False);E^.Clear;Changed:=True;
    end;
  end;
  if Changed then RefreshProfessionSpeed(AIndex,NowTick and $FFFFFFFF,NowTick,Replies);
end;

function TEmulatorSession.HandleProfessionImpact(const Packet:TBytes;out Replies:TB1008Replies):string;
var Targets:TArray<TB1008AttackDecide>;T:TB1008AttackDecide;D:TB1008ProfessionSkill;
  ID:Cardinal;NowTick:UInt64;Saved:TB1008AttackStart;One:TB1008Replies;
  I,J,Index,CenterIndex:Integer;CX,CZ,CY,DX,DZ,LX,LZ:Double;A:Single;E:^TB1008ProfessionEffect;
begin
  Replies:=nil;Targets:=TB1008CombatWire.ParseAreaDecide(Packet);T:=Targets[0];ID:=T.ActionID;
  NowTick:=GetTickCount64;
  if not FHasPendingAttack or (FPendingAttack.ActionKind<>1) or
    (T.ActionKind<>1) or (T.ActorKind<>0) or (T.ActorID<>FWorldState.CharacterID) or
    (FSkillCast.ActiveSkillID<>ID) or (NowTick>FSkillImpactUntilTick) or
    (((Int64(T.Timestamp)-Int64(FPendingAttack.Timestamp)+$100000000) mod $100000000)>=$80000000) then
    Exit('PROFESSION IMPACT REJECTED | no matching cast');
  D:=TB1008ProfessionSkill.Get(ID,FSkillCast.ActiveRank);
  Saved:=FPendingAttack;
  if TB1008ProfessionSkill.IsSelf(ID) and not TB1008ProfessionSkill.IsArea(ID) then begin
    if (Length(Targets)<>1) or (T.TargetKind>1) or (T.TargetID<>1) then
      Exit('PROFESSION BUFF REJECTED | invalid self target');
    FHasPendingAttack:=False;FPendingSpiderHandle:=0;
    if (ID=B1008SwordRevengeID) or (ID=B1008PolearmRevengeID) then E:=@FRevenge else E:=@FDeathLeap;
    E^.Start(ID,FSkillCast.ActiveRank,NowTick);
    SetLength(Replies,3);Replies[0]:=TB1008SkillWire.BuildProfessionEffect(T.Timestamp,0,1,ID,E^.Rank,D.DurationMS,True);
    Replies[1]:=TB1008ProgressWire.BuildParameters(T.Timestamp,FPlayerClassID,FProgress.Level);
    ApplyPlayerParameters(Replies[1]);Replies[2]:=PlayerGage(T.Timestamp,False);
    Exit(Format('PROFESSION BUFF APPLIED | skill=%u rank=%u duration=%u',[ID,E^.Rank,D.DurationMS]));
  end;
  if not TB1008ProfessionSkill.IsArea(ID) then begin
    if Length(Targets)<>1 then Exit('PROFESSION IMPACT REJECTED | single target skill');
    Exit(ResolveTargetImpact(T,Replies));
  end;
  CX:=FWorldState.Position.X;CZ:=FWorldState.Position.Z;CY:=FWorldState.Position.Y;
  if not TB1008ProfessionSkill.IsSelf(ID) then begin
    CenterIndex:=FindSpiderIndex(Saved.TargetID);
    if (CenterIndex<0) or not FSpiders[CenterIndex].Visible then Exit('PROFESSION AREA REJECTED | center disappeared');
    FSpiders[CenterIndex].AI.UpdatePosition(NowTick);
    CX:=FSpiders[CenterIndex].AI.X;CZ:=FSpiders[CenterIndex].AI.Z;CY:=FSpiders[CenterIndex].AI.Y;
  end;
  // Validate the entire list before consuming the cast or applying any damage.
  for T in Targets do begin
    if T.TargetKind<>1 then Exit('PROFESSION AREA REJECTED | non-NPC target');
    Index:=FindSpiderIndex(T.TargetID);
    if (Index<0) or not FSpiders[Index].Visible then Exit('PROFESSION AREA REJECTED | unknown target');
    FSpiders[Index].AI.UpdatePosition(NowTick);
    DX:=FSpiders[Index].AI.X-CX;DZ:=FSpiders[Index].AI.Z-CZ;
    if D.AreaKind=2 then begin
      A:=3.14159274101257-Saved.Heading;LX:=DX*Cos(A)+DZ*Sin(A);LZ:=-DX*Sin(A)+DZ*Cos(A);
      if (Abs(LX)>D.AreaRange/2) or (LZ<0) or (LZ>D.AreaSecondaryRange) then
        Exit('PROFESSION AREA REJECTED | outside rectangle');
    end else if Sqr(DX)+Sqr(DZ)+Sqr(FSpiders[Index].AI.Y-CY)>
      Sqr(D.AreaRange+TB1008Berneo.Mob(FSpiders[Index].Spawn.MobID).ClientRadius) then
      Exit('PROFESSION AREA REJECTED | outside sphere');
  end;
  FHasPendingAttack:=False;FPendingSpiderHandle:=0;
  Result:=Format('PROFESSION AREA APPLIED | skill=%u targets=%d',[ID,Length(Targets)]);
  for I:=0 to High(Targets) do begin
    T:=Targets[I];Index:=FindSpiderIndex(T.TargetID);
    if FSpiders[Index].Encounter.HP=0 then Continue;
    FPendingAttack:=Saved;FPendingAttack.TargetKind:=1;FPendingAttack.TargetID:=T.TargetID;
    FPendingAttack.X:=FWorldState.Position.X;FPendingAttack.Z:=FWorldState.Position.Z;FPendingAttack.Y:=FWorldState.Position.Y;
    FPendingAttack.TargetX:=FSpiders[Index].AI.X;FPendingAttack.TargetZ:=FSpiders[Index].AI.Z;FPendingAttack.TargetY:=FSpiders[Index].AI.Y;
    FHasPendingAttack:=True;FPendingSpiderHandle:=T.TargetID;T.TargetCount:=1;
    T.X:=FWorldState.Position.X;T.Z:=FWorldState.Position.Z;T.Y:=FWorldState.Position.Y;
    Result:=Result+' | '+ResolveTargetImpact(T,One,True);
    J:=Length(Replies);SetLength(Replies,J+Length(One));for Index:=0 to High(One) do Replies[J+Index]:=One[Index];
  end;
  FPendingAttack:=Saved;FHasPendingAttack:=False;FPendingSpiderHandle:=0;
end;
