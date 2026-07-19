#!/bin/sh
# Bootstrap only the disposable initial configuration. Long-term settings live in this repo.
set -eu

phase='startup'
log() {
  printf '%s\n' "==> $*"
}

die() {
  printf '%s\n' "error [$phase]: $*" >&2
  exit 1
}

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

case "$OS_NAME" in
  Darwin)
    PLATFORM=darwin
    CONFIG_OUTPUT=darwinConfigurations
    CONFIG_OVERRIDE=${DOTFILES_DARWIN_CONFIG:-}
    ;;
  Linux)
    PLATFORM=linux
    CONFIG_OUTPUT=homeConfigurations
    CONFIG_OVERRIDE=${DOTFILES_HOME_CONFIG:-}
    ;;
esac

short_hostname() { hostname -s 2>/dev/null || hostname; }
HOST_NAME=$(short_hostname) || die 'could not determine hostname'
if [ "$PLATFORM" = darwin ] && command -v scutil >/dev/null 2>&1; then
  HOST_NAME=$(scutil --get LocalHostName 2>/dev/null || short_hostname)
fi

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
DOTFILES_DIR=${DOTFILES_DIR:-"$XDG_CONFIG_HOME/dotfiles"}
DOTFILES_REPOSITORY=${DOTFILES_REPOSITORY:-https://github.com/chemiseblanc/dotfiles.git}
BOOTSTRAP_INPUT=${BOOTSTRAP_INPUT:-/dev/tty}
BOOTSTRAP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-bootstrap.XXXXXX") || die 'could not create temporary directory'

cleanup() {
  if [ "${BOOTSTRAP_KEEP_TEMP:-0}" = 1 ] || [ "${BOOTSTRAP_DRY_RUN:-0}" = 1 ]; then
    printf '%s\n' "==> Preserving temporary bootstrap files: $BOOTSTRAP_DIR"
  else
    rm -rf "$BOOTSTRAP_DIR"
  fi
}
trap cleanup EXIT HUP INT TERM

write_flake_prelude() {
  cat >"$BOOTSTRAP_DIR/flake.nix" <<EOF_DARWIN
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
EOF_DARWIN

  if [ "$PLATFORM" = darwin ]; then
    cat >>"$BOOTSTRAP_DIR/flake.nix" <<EOF_DARWIN
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
EOF_DARWIN
    OUTPUT_INPUTS='nix-darwin, '
  else
    OUTPUT_INPUTS=
  fi

  cat >>"$BOOTSTRAP_DIR/flake.nix" <<EOF_DARWIN
  };

  outputs = { nixpkgs, home-manager, ${OUTPUT_INPUTS}... }:
    let
      homeModule = { pkgs, ... }: {
        home.username = "$USER_NAME";
        home.homeDirectory = "$HOME";
        home.stateVersion = "26.05";
        home.packages = [ pkgs.git ];
        programs.home-manager.enable = true;
      };
    in
EOF_DARWIN
}

write_darwin_flake() {
  write_flake_prelude
  cat >>"$BOOTSTRAP_DIR/flake.nix" <<EOF_DARWIN
  {
    darwinConfigurations.bootstrap = nix-darwin.lib.darwinSystem {
      system = "$NIX_SYSTEM";
      modules = [
        home-manager.darwinModules.home-manager
        {
          nixpkgs.hostPlatform = "$NIX_SYSTEM";
          # Lix is externally installed; do not let nix-darwin manage Nix.
          nix.enable = false;
          system.primaryUser = "$USER_NAME";
          users.users."$USER_NAME".home = "$HOME";
          # Do not casually change after initial activation.
          system.stateVersion = 5;
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users."$USER_NAME" = homeModule;
        }
      ];
    };
  };
}
EOF_DARWIN
}

write_linux_flake() {
  write_flake_prelude
  cat >>"$BOOTSTRAP_DIR/flake.nix" <<EOF_LINUX
  {
    homeConfigurations."$USER_NAME@$HOST_NAME" = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { system = "$NIX_SYSTEM"; };
      modules = [ homeModule ];
    };
  };
}
EOF_LINUX
}

write_temporary_flake() {
  phase='creating temporary flake'
  log "Creating temporary flake for $NIX_SYSTEM"

  if [ "$PLATFORM" = darwin ]; then
    write_darwin_flake
  else
    write_linux_flake
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
  LIX_INSTALLER=$BOOTSTRAP_DIR/lix-installer.sh
  run curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    --output "$LIX_INSTALLER" https://install.lix.systems/lix || die 'could not download Lix installer'
  run sh "$LIX_INSTALLER" install --no-confirm || die 'Lix installer failed'
  if [ "${BOOTSTRAP_DRY_RUN:-0}" = 1 ]; then
    return
  fi

  if [ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  command -v nix >/dev/null 2>&1 || die 'nix is unavailable after installing Lix and loading its profile'
}

activate_temporary() {
  phase='activating temporary configuration'
  if [ "$PLATFORM" = darwin ]; then
    log 'Activating temporary nix-darwin and Home Manager configuration'
    run sudo nix run github:nix-darwin/nix-darwin/master#darwin-rebuild -- \
      switch --flake "path:$BOOTSTRAP_DIR#bootstrap" ||
      die 'temporary nix-darwin activation failed'
  else
    log 'Activating temporary Home Manager configuration'
    run nix run github:nix-community/home-manager/master -- \
      switch --flake "path:$BOOTSTRAP_DIR#$USER_NAME@$HOST_NAME" ||
      die 'temporary Home Manager activation failed'
  fi
}

find_git() {
  if command -v git >/dev/null 2>&1; then
    command -v git
    return
  fi

  for candidate in "$HOME/.nix-profile/bin/git" "/etc/profiles/per-user/$USER_NAME/bin/git" /run/current-system/sw/bin/git; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return
    fi
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

select_configuration() {
  phase='selecting configuration'
  if [ -n "$CONFIG_OVERRIDE" ]; then
    SELECTED_CONFIG=$CONFIG_OVERRIDE
    return
  fi

  CONFIG_NAMES=$(nix --extra-experimental-features 'nix-command flakes' eval --raw "$DOTFILES_DIR#$CONFIG_OUTPUT" \
    --apply "configs: builtins.concatStringsSep \"\\n\" (builtins.filter (name: configs.\${name}.pkgs.stdenv.hostPlatform.system == \"$NIX_SYSTEM\") (builtins.attrNames configs))") ||
    die "could not list $CONFIG_OUTPUT"
  [ -n "$CONFIG_NAMES" ] || die "no $CONFIG_OUTPUT entries support $NIX_SYSTEM"
  [ -r "$BOOTSTRAP_INPUT" ] || die "cannot prompt for a configuration; set DOTFILES_DARWIN_CONFIG or DOTFILES_HOME_CONFIG"

  log "Configurations for $NIX_SYSTEM:"
  printf '%s\n' "$CONFIG_NAMES" | awk '{ printf "  %d) %s\n", NR, $0 }' >&2
  printf '%s' 'Select a configuration: ' >&2
  IFS= read -r CONFIG_CHOICE <"$BOOTSTRAP_INPUT" || die 'could not read configuration selection'
  case "$CONFIG_CHOICE" in
    '' | *[!0-9]*) die 'configuration selection must be a listed number' ;;
  esac
  SELECTED_CONFIG=$(printf '%s\n' "$CONFIG_NAMES" | sed -n "${CONFIG_CHOICE}p")
  [ -n "$SELECTED_CONFIG" ] || die "configuration selection is out of range: $CONFIG_CHOICE"
}

install_homebrew() {
  if [ "$PLATFORM" != darwin ]; then
    return
  fi

  phase='installing Homebrew'
  if command -v brew >/dev/null 2>&1; then
    return
  fi

  log 'Installing Homebrew for nix-darwin-managed applications'
  run /bin/sh -c '$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)' ||
    die 'Homebrew installation failed'

  if [ -x /opt/homebrew/bin/brew ]; then
    PATH=/opt/homebrew/bin:$PATH
    export PATH
  fi
  if [ -x /usr/local/bin/brew ]; then
    PATH=/usr/local/bin:$PATH
    export PATH
  fi
}

activate_real() {
  phase='activating real configuration'
  if [ "$PLATFORM" = darwin ]; then
    log "Activating nix-darwin configuration $SELECTED_CONFIG"
    if command -v darwin-rebuild >/dev/null 2>&1; then
      run sudo darwin-rebuild switch --flake "$DOTFILES_DIR#$SELECTED_CONFIG" ||
        die 'real nix-darwin activation failed'
    else
      run sudo nix run github:nix-darwin/nix-darwin/master#darwin-rebuild -- \
        switch --flake "$DOTFILES_DIR#$SELECTED_CONFIG" ||
        die 'real nix-darwin activation failed'
    fi
  else
    log "Activating Home Manager configuration $SELECTED_CONFIG"
    if command -v home-manager >/dev/null 2>&1; then
      run home-manager switch --flake "$DOTFILES_DIR#$SELECTED_CONFIG" ||
        die 'real Home Manager activation failed'
    else
      run nix run github:nix-community/home-manager/master -- \
        switch --flake "$DOTFILES_DIR#$SELECTED_CONFIG" ||
        die 'real Home Manager activation failed'
    fi
  fi
}

main() {
  write_temporary_flake
  ensure_nix
  activate_temporary
  clone_dotfiles
  select_configuration
  install_homebrew
  activate_real
}

log "Detected $NIX_SYSTEM for $USER_NAME; temporary files: $BOOTSTRAP_DIR"
main
log 'Bootstrap complete'
