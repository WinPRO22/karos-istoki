program KarosOldEmulator;

uses
  Vcl.Forms,
  serverGUI in 'serverGUI.pas' {Form23},
  Emulator.Server in 'Emulator.Server.pas',
  Emulator.Protocol.B1008 in 'Emulator.Protocol.B1008.pas',
  Emulator.Session in 'Emulator.Session.pas',
  Emulator.Client.B1008 in 'Emulator.Client.B1008.pas',
  Emulator.Login.B1008 in 'Emulator.Login.B1008.pas',
  Emulator.Character.B1008 in 'Emulator.Character.B1008.pas',
  Emulator.World.B1008 in 'Emulator.World.B1008.pas',
  Emulator.Combat.B1008 in 'Emulator.Combat.B1008.pas',
  Emulator.Quest.B1008 in 'Emulator.Quest.B1008.pas',
  Emulator.QuestState.B1008 in 'Emulator.QuestState.B1008.pas',
  Emulator.WorldState.B1008 in 'Emulator.WorldState.B1008.pas',
  Emulator.Content in 'Emulator.Content.pas',
  Emulator.Repository in 'Emulator.Repository.pas',
  Emulator.Repository.SQLite in 'Emulator.Repository.SQLite.pas',
  Emulator.Runtime in 'Emulator.Runtime.pas',
  Emulator.Profile.B1008 in 'Emulator.Profile.B1008.pas',
  Emulator.AI.B1008 in 'Emulator.AI.B1008.pas',
  Emulator.Loot.B1008 in 'Emulator.Loot.B1008.pas',
  Emulator.LootStore.B1008 in 'Emulator.LootStore.B1008.pas',
  Emulator.Progression.B1008 in 'Emulator.Progression.B1008.pas',
  Emulator.Balance.B1008 in 'Emulator.Balance.B1008.pas',
  Emulator.Regen.B1008 in 'Emulator.Regen.B1008.pas',
  Emulator.Fletta.B1008 in 'Emulator.Fletta.B1008.pas',
  Emulator.Equipment.B1008 in 'Emulator.Equipment.B1008.pas',
  Emulator.Items.B1008 in 'Emulator.Items.B1008.pas',
  Emulator.DropProfile.B1008 in 'Emulator.DropProfile.B1008.pas',
  Emulator.Shop.B1008 in 'Emulator.Shop.B1008.pas',
  Emulator.Skills.B1008 in 'Emulator.Skills.B1008.pas',
  Emulator.QuickSlots.B1008 in 'Emulator.QuickSlots.B1008.pas';

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm23, Form23);
  Application.Run;
end.
