{ ... }:
{
  # Homebrew itself is installed by bootstrap.sh before this configuration activates.
  homebrew = {
    enable = true;
    brews = [ "mas" ];
    casks = [
      "1password"
      "firefox"
      "ghostty"
      "visual-studio-code"
    ];
    masApps = {
      WireGuard = 1451685025;
      Xcode = 497799835;
    };
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };
  };
}
