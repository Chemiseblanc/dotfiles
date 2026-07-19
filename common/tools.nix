{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bat
    eza
    fd
    fzf
    jq
    neovim
    ripgrep
    lazygit
  ];
}