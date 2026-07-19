{ pkgs, ... }:
let
  dotfilesCleanup = ''
    dotfiles-cleanup() {
      if [ "$#" -gt 1 ]; then
        printf '%s\n' 'usage: dotfiles-cleanup [duration]' >&2
        return 2
      fi

      local duration="''${1:-30d}"
      nix-collect-garbage --delete-older-than "$duration"
    }
  '';
in
{
  home.shellAliases = {
    dotfiles-update = ''
      git -C "''${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles" pull --ff-only
    '';
    dotfiles-apply =
      if pkgs.stdenv.isDarwin then
        ''
          sudo darwin-rebuild switch --flake "path:''${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles#''${DOTFILES_CONFIG}"
        ''
      else
        ''
          home-manager switch --flake "path:''${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles#''${DOTFILES_CONFIG}"
        '';
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initContent = dotfilesCleanup;
  };

  programs.bash = {
    enable = true;
    initExtra = dotfilesCleanup;
  };
}