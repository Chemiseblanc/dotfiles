{ pkgs, ... }:
let
  oh-my-pi = pkgs.callPackage ../packages/oh-my-pi { };
in
{
  home.packages = with pkgs; [
    bat
    codex
    eza
    fd
    fzf
    github-copilot-cli
    jq
    neovim
    oh-my-pi
    ripgrep
    lazygit
  ];
}