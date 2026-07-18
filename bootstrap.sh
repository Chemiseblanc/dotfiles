#!/bin/sh
# Bootstrap only the disposable initial configuration. Long-term settings live in this repo.
set -eu

phase='startup'
log() { printf '%s\n' "==> $*"; }
die() { printf '%s\n' "error [$phase]: $*" >&2; exit 1; }
run() {
  if [ "${BOOTSTRAP_DRY_RUN:-0}" = 1 ]; then
    printf '%s\n' "+ $*"
  else
    "$@"
  fi
}

[ -n "${HOME:-}" ] || die 'HOME is empty'
USER_NAME=$(id -un) || die 'could not determine username'
OS_NAME=$(uname -s) || die 'could not determine operating system'
ARCH_NAME=$(uname -m) || die 'could not determine architecture'
case "$OS_NAME:$ARCH_NAME" in
  Darwin:arm64) NIX_SYSTEM=aarch64-darwin ;;
  # Darwin:x86_64) NIX_SYSTEM=x86_64-darwin ;;
  Linux:x86_64) NIX_SYSTEM=x86_64-linux ;;
  Linux:aarch64 | Linux:arm64) NIX_SYSTEM=aarch64-linux ;;
  *) die "unsupported platform: $OS_NAME $ARCH_NAME" ;;
esac

short_hostname() { hostname -s 2>/dev/null || hostname; }
HOST_NAME=$(short_hostname) || die 'could not determine hostname'
if [ "$OS_NAME" = Darwin ] && command -v scutil >/dev/null 2>&1; then
  HOST_NAME=$(scutil --get LocalHostName 2>/dev/null || short_hostname)
fi

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
DOTFILES_DIR=${DOTFILES_DIR:-"$XDG_CONFIG_HOME/dotfiles"}
DOTFILES_REPOSITORY=${DOTFILES_REPOSITORY:-https://github.com/chemiseblanc/dotfiles.git}
DARWIN_CONFIG=${DOTFILES_DARWIN_CONFIG:-"$HOST_NAME"}
HOME_CONFIG=${DOTFILES_HOME_CONFIG:-"$USER_NAME@$HOST_NAME"}
BOOTSTRAP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bootstrap.XXXXXX") || die 'could not create temporary directory'

cleanup() {
  if [ "${BOOTSTRAP_KEEP_TEMP:-0}" = 1 ] || [ "${BOOTSTRAP_DRY_RUN:-0}" = 1 ]; then
    printf '%s\n' "==> Preserving temporary bootstrap files: $BOOTSTRAP_DIR"
  else
    rm -rf "$BOOTSTRAP_DIR"
  fi
}
trap cleanup EXIT HUP INT TERM

write_temporary_flake() {
  phase='creating temporary flake'
  log "Creating temporary flake for $NIX_SYSTEM"
  if [ "$OS_NAME" = Darwin ]; then
    cat >"$BOOTSTRAP_DIR/flake.nix" <<EOF_DARWIN
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = { url = "github:nix-community/home-manager/master"; inputs.nixpkgs.follows = "nixpkgs"; };
    nix-darwin = { url = "github:nix-darwin/nix-darwin/master"; inputs.nixpkgs.follows = "nixpkgs"; };
  };
  outputs = { nixpkgs, home-manager, nix-darwin, ... }: {
    darwinConfigurations."$HOST_NAME" = nix-darwin.lib.darwinSystem {
      system = "$NIX_SYSTEM";
      modules = [ home-manager.darwinModules.home-manager {
        nixpkgs.hostPlatform = "$NIX_SYSTEM";
        # Lix is externally installed; do not let nix-darwin manage Nix.
        nix.enable = false;
        system.primaryUser = "$USER_NAME";
        users.users."$USER_NAME".home = "$HOME";
        # Do not casually change after initial activation.
        system.stateVersion = 5;
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users."$USER_NAME" = { pkgs, ... }: {
          home.username = "$USER_NAME";
          home.homeDirectory = "$HOME";
          home.stateVersion = "24.11";
          home.packages = [ pkgs.git ];
          programs.home-manager.enable = true;
        };
      } ];
    };
  };
}
EOF_DARWIN
  else
    cat >"$BOOTSTRAP_DIR/flake.nix" <<EOF_LINUX
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = { url = "github:nix-community/home-manager/master"; inputs.nixpkgs.follows = "nixpkgs"; };
  };
  outputs = { nixpkgs, home-manager, ... }: {
    homeConfigurations."$USER_NAME@$HOST_NAME" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = "$NIX_SYSTEM"; };
      modules = [{
        home.username = "$USER_NAME";
        home.homeDirectory = "$HOME";
        home.stateVersion = "26.11";
        home.packages = [ pkgs.git ];
        programs.home-manager.enable = true;
      }];
    };
  };
}
EOF_LINUX
  fi
}

ensure_nix() {
  phase='installing Lix'
  if command -v nix >/dev/null 2>&1; then
    log 'Using existing Nix-compatible installation'
    nix --version || die 'existing nix failed to run'
    return
  fi
  log 'Installing Lix'
  if [ "${BOOTSTRAP_DRY_RUN:-0}" = 1 ]; then
    printf '%s\n' '+ curl --proto =https --tlsv1.2 ... https://install.lix.systems/lix | sh -s -- install --no-confirm'
    return
  fi
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location https://install.lix.systems/lix |
    sh -s -- install --no-confirm || die 'Lix installer failed'
  if [ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  command -v nix >/dev/null 2>&1 || die 'nix is unavailable after installing Lix and loading its profile'
}

activate_temporary() {
  phase='activating temporary configuration'
  if [ "$OS_NAME" = Darwin ]; then
    log 'Activating temporary nix-darwin and Home Manager configuration'
    run sudo nix run github:nix-darwin/nix-darwin/master#darwin-rebuild -- switch --flake "$BOOTSTRAP_DIR#$HOST_NAME" || die 'temporary nix-darwin activation failed'
  else
    log 'Activating temporary Home Manager configuration'
    run nix run github:nix-community/home-manager/master -- switch --flake "$BOOTSTRAP_DIR#$USER_NAME@$HOST_NAME" || die 'temporary Home Manager activation failed'
  fi
}

find_git() {
  if command -v git >/dev/null 2>&1; then command -v git; return; fi
  for candidate in "$HOME/.nix-profile/bin/git" "/etc/profiles/per-user/$USER_NAME/bin/git" /run/current-system/sw/bin/git; do
    [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return; }
  done
  return 1
}

clone_dotfiles() {
  phase='cloning dotfiles repository'
  if [ "${BOOTSTRAP_DRY_RUN:-0}" = 1 ]; then
    log "Would clone $DOTFILES_REPOSITORY to $DOTFILES_DIR"
    return
  fi
  GIT=$(find_git) || die 'Git was not found after temporary activation'
  mkdir -p "$(dirname "$DOTFILES_DIR")" || die 'could not create dotfiles parent directory'
  if [ -e "$DOTFILES_DIR" ]; then
    [ -d "$DOTFILES_DIR/.git" ] || die "destination exists and is not a Git repository: $DOTFILES_DIR"
    log "Reusing existing repository ($($GIT -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || printf 'origin unavailable'))"
  else
    log 'Cloning dotfiles repository'
    "$GIT" clone "$DOTFILES_REPOSITORY" "$DOTFILES_DIR" || die 'Git clone failed'
  fi
}

install_homebrew() {
  if [ "$OS_NAME" != Darwin ]; then return 0; fi
  phase='installing Homebrew'
  if command -v brew >/dev/null 2>&1; then return; fi
  log 'Installing Homebrew for nix-darwin-managed applications'
  run /bin/sh -c '$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)' || die 'Homebrew installation failed'
  if [ -x /opt/homebrew/bin/brew ]; then PATH=/opt/homebrew/bin:$PATH; export PATH; fi
  if [ -x /usr/local/bin/brew ]; then PATH=/usr/local/bin:$PATH; export PATH; fi
}

activate_real() {
  phase='activating real configuration'
  if [ "$OS_NAME" = Darwin ]; then
    log "Activating nix-darwin configuration $DARWIN_CONFIG"
    if command -v darwin-rebuild >/dev/null 2>&1; then
      run sudo darwin-rebuild switch --flake "$DOTFILES_DIR#$DARWIN_CONFIG" || die 'real nix-darwin activation failed'
    else
      run sudo nix run github:nix-darwin/nix-darwin/master#darwin-rebuild -- switch --flake "$DOTFILES_DIR#$DARWIN_CONFIG" || die 'real nix-darwin activation failed'
    fi
  else
    log "Activating Home Manager configuration $HOME_CONFIG"
    if command -v home-manager >/dev/null 2>&1; then
      run home-manager switch --flake "$DOTFILES_DIR#$HOME_CONFIG" || die 'real Home Manager activation failed'
    else
      run nix run github:nix-community/home-manager/master -- switch --flake "$DOTFILES_DIR#$HOME_CONFIG" || die 'real Home Manager activation failed'
    fi
  fi
}

log "Detected $NIX_SYSTEM for $USER_NAME; temporary files: $BOOTSTRAP_DIR"
write_temporary_flake
ensure_nix
activate_temporary
clone_dotfiles
install_homebrew
activate_real
log 'Bootstrap complete'
