#!/bin/sh
# Remove the system configuration installed by this repository.
set -eu

phase='startup'
log() {
  printf '%s\n' "==> $*"
}

warn() {
  printf '%s\n' "warning [$phase]: $*" >&2
}

die() {
  printf '%s\n' "error [$phase]: $*" >&2
  exit 1
}

run() {
  if [ "${CLEANUP_DRY_RUN:-0}" = 1 ]; then
    printf '%s\n' "+ $*"
  else
    "$@"
  fi
}

[ -n "${HOME:-}" ] || die 'HOME is empty'
USER_NAME=$(id -un) || die 'could not determine username'
OS_NAME=$(uname -s) || die 'could not determine operating system'
case "$OS_NAME" in
  Darwin) PLATFORM=darwin ;;
  Linux) PLATFORM=linux ;;
  *) die "unsupported operating system: $OS_NAME" ;;
esac

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
DOTFILES_DIR=${DOTFILES_DIR:-"$XDG_CONFIG_HOME/dotfiles"}
CLEANUP_INPUT=${CLEANUP_INPUT:-/dev/tty}
CLEANUP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-cleanup.XXXXXX") ||
  die 'could not create temporary directory'
[ -r "$CLEANUP_INPUT" ] || die "confirmation input is not readable: $CLEANUP_INPUT"
exec 3<"$CLEANUP_INPUT"

cleanup_temp() {
  rm -rf "$CLEANUP_DIR"
}
trap cleanup_temp EXIT HUP INT TERM

confirm() {
  prompt=$1
  printf '%s' "$prompt [y/N] " >&2
  IFS= read -r answer <&3 || answer=
  case "$answer" in
    y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

find_command() {
  command_name=$1
  shift
  if command -v "$command_name" >/dev/null 2>&1; then
    command -v "$command_name"
    return
  fi
  for candidate do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  return 1
}

remove_home_manager() {
  phase='removing Home Manager configuration'
  HOME_MANAGER=$(find_command home-manager \
    "$HOME/.nix-profile/bin/home-manager" \
    "/etc/profiles/per-user/$USER_NAME/bin/home-manager" \
    "/run/current-system/sw/bin/home-manager" 2>/dev/null || true)
  if [ -z "$HOME_MANAGER" ]; then
    log 'Home Manager is not installed; nothing to remove'
    return
  fi
  log 'Removing Home Manager profile and managed files'
  run "$HOME_MANAGER" uninstall
}

remove_nix_darwin() {
  [ "$PLATFORM" = darwin ] || return 0
  phase='removing nix-darwin configuration'
  DARWIN_UNINSTALLER=$(find_command darwin-uninstaller \
    "/run/current-system/sw/bin/darwin-uninstaller" \
    "/nix/var/nix/profiles/system/sw/bin/darwin-uninstaller" 2>/dev/null || true)
  if [ -n "$DARWIN_UNINSTALLER" ]; then
    log 'Removing nix-darwin configuration'
    run sudo "$DARWIN_UNINSTALLER"
    return
  fi
  if command -v nix >/dev/null 2>&1 || [ "${CLEANUP_DRY_RUN:-0}" = 1 ]; then
    log 'Removing nix-darwin configuration with the upstream uninstaller'
    run sudo nix --extra-experimental-features 'nix-command flakes' run \
      nix-darwin#darwin-uninstaller
    return
  fi
  log 'nix-darwin is not installed; nothing to remove'
}

remove_configuration() {
  if ! confirm 'Remove the Home Manager and platform configuration?'; then
    log 'Keeping the managed configuration'
    return 1
  fi
  remove_home_manager || return 1
  remove_nix_darwin || return 1
}

homebrew_exists() {
  prefix=$1
  [ -x "$prefix/bin/brew" ] || [ -d "$prefix/Homebrew/.git" ] || [ -d "$prefix/.git" ]
}

remove_homebrew() {
  [ "$PLATFORM" = darwin ] || return 0
  phase='removing Homebrew'
  if ! confirm 'Remove Homebrew and all packages installed through it?'; then
    log 'Keeping Homebrew'
    return
  fi

  HOMEBREW_UNINSTALLER=$CLEANUP_DIR/homebrew-uninstall.sh
  if [ "${CLEANUP_DRY_RUN:-0}" = 1 ]; then
    run curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
      --output "$HOMEBREW_UNINSTALLER" \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh
  else
    curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
      --output "$HOMEBREW_UNINSTALLER" \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh ||
      die 'could not download the Homebrew uninstaller'
  fi

  removed=0
  for prefix in /opt/homebrew /usr/local; do
    if homebrew_exists "$prefix" || [ "${CLEANUP_DRY_RUN:-0}" = 1 ]; then
      log "Removing Homebrew prefix $prefix"
      if [ "${CLEANUP_DRY_RUN:-0}" = 1 ]; then
        run /bin/bash "$HOMEBREW_UNINSTALLER" --dry-run --path "$prefix"
      else
        NONINTERACTIVE=1 /bin/bash "$HOMEBREW_UNINSTALLER" --path "$prefix" ||
          die "Homebrew uninstaller failed for $prefix"
      fi
      removed=1
    fi
  done
  [ "$removed" = 1 ] || log 'Homebrew is not installed; nothing to remove'
}

checkout_path_is_safe() {
  case "$DOTFILES_DIR" in
    '' | / | "$HOME" | "$HOME"/ | "$XDG_CONFIG_HOME" | "$XDG_CONFIG_HOME"/) return 1 ;;
  esac
  [ -d "$DOTFILES_DIR/.git" ]
}

remove_checkout() {
  phase='removing dotfiles checkout'
  if [ ! -e "$DOTFILES_DIR" ]; then
    log "Dotfiles checkout is already absent: $DOTFILES_DIR"
    return
  fi
  checkout_path_is_safe || die "refusing to remove an unsafe or non-Git checkout: $DOTFILES_DIR"
  if ! confirm "Remove the dotfiles checkout at $DOTFILES_DIR?"; then
    log 'Keeping the dotfiles checkout'
    return
  fi
  log "Removing dotfiles checkout at $DOTFILES_DIR"
  run rm -rf "$DOTFILES_DIR"
}

remove_lix() {
  phase='removing Lix'
  if ! confirm 'Remove Lix and the Nix store?'; then
    log 'Keeping Lix'
    return
  fi
  if [ ! -x /nix/nix-installer ] && [ "${CLEANUP_DRY_RUN:-0}" != 1 ]; then
    log 'The Lix installer receipt is already absent; nothing to remove'
    return
  fi
  log 'Removing Lix and the Nix store'
  run sudo /nix/nix-installer uninstall --no-confirm
}

main() {
  configuration_removed=1
  if ! remove_configuration; then
    configuration_removed=0
    warn 'configuration removal was skipped or failed'
  fi

  remove_homebrew
  remove_checkout

  if [ "$configuration_removed" = 1 ]; then
    remove_lix
  else
    phase='removing Lix'
    warn 'keeping Lix because the managed configuration was not removed'
  fi
}

log "Detected $PLATFORM for $USER_NAME"
main
log 'Cleanup complete. Start a new login shell; macOS may require a restart.'