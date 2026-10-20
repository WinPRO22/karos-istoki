unit Emulator.Repository;

interface

uses
  Emulator.Content;

type
  IEmulatorContentRepository = interface
    ['{23FD263A-CE57-421D-B529-A19BB18523CE}']
    function GetDatabasePath: string;
    function LoadSnapshot(const ABuildID: string): IEmulatorContentSnapshot;
    function PublishMob(const ADefinition: TEmulatorMobDefinition): Int64;
    function PublishSpawn(const ADefinition: TEmulatorSpawnDefinition): Int64;
    property DatabasePath: string read GetDatabasePath;
  end;

implementation

end.
