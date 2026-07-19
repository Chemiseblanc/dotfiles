{ ... }:
{
  launchd.daemons.nix-garbage-collect.serviceConfig = {
    ProgramArguments = [
      "/nix/var/nix/profiles/default/bin/nix-collect-garbage"
      "--delete-older-than"
      "30d"
    ];
    StartCalendarInterval = {
      Weekday = 7;
      Hour = 3;
      Minute = 15;
    };
    ProcessType = "Background";
    LowPriorityIO = true;
  };
}