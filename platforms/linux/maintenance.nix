{ pkgs, ... }:
{
  systemd.user.services.nix-garbage-collect = {
    Unit.Description = "Remove old Nix generations and unreachable store paths";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.nix}/bin/nix-collect-garbage --delete-older-than 30d";
    };
  };

  systemd.user.timers.nix-garbage-collect = {
    Unit.Description = "Weekly Nix garbage collection";
    Timer = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}