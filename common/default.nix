{ ... }:
{
  imports = [
    ./home.nix
    ./git.nix
    ./shell.nix
    ./direnv.nix
    ./tools.nix
  ];

  programs.home-manager.enable = true;
}