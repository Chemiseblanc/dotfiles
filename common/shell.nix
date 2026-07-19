{ pkgs, ... }:
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
  };

  programs.bash.enable = true;
}