{ ... }:
{
  # nix-homebrew installs Homebrew; nix-darwin manages its packages and activation behavior.
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