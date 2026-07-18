{ ... }:
{
  # Homebrew itself is installed by bootstrap.sh before this configuration activates.
  homebrew = {
    enable = true;
    brews = [ "mas" ];
    casks = [
      "ghostty"
    ];
    masApps = {
      # Xcode = 497799835;
    };
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };
  };
}
