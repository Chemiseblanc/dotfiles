# dotfiles

A cross-platform, flake-based development environment for macOS and Linux. The
bootstrap is deliberately small: it installs/reuses Lix, uses a disposable
configuration to expose Git, clones this repository, and activates the real
configuration. Home Manager owns terminal tooling and shell setup; nix-darwin
owns macOS integrations.

## Quick start

```sh
curl -fsSL \
  https://raw.githubusercontent.com/chemiseblanc/dotfiles/main/bootstrap.sh |
  "$SHELL"
```

## Inspect first

```sh
curl -fsSLo /tmp/bootstrap-dotfiles.sh \
  https://raw.githubusercontent.com/chemiseblanc/dotfiles/main/bootstrap.sh

less /tmp/bootstrap-dotfiles.sh
sh /tmp/bootstrap-dotfiles.sh
```

The checkout is `${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles`. Override it with
`DOTFILES_DIR`, and override the public HTTPS source with `DOTFILES_REPOSITORY`
(for example, an already-authenticated SSH remote).

## Host configuration names

The flake intentionally supplies safe example configurations rather than
pretending to know personal host names. Copy or rename the relevant example in
`flake.nix` to match the value below before bootstrapping:

- macOS uses `scutil --get LocalHostName` (or `hostname -s` as a fallback).
  Its attribute must be `darwinConfigurations.<LocalHostName>`.
- Linux uses `$(id -un)@$(hostname -s)`. Its attribute must be
  `homeConfigurations."<user>@<short-hostname>"`.

Until an attribute has that name, select the example explicitly, e.g.
`DOTFILES_HOME_CONFIG=example@linux-x86_64` or
`DOTFILES_DARWIN_CONFIG=example-darwin-aarch64`. The bootstrap supports these
overrides and does not rename an existing checkout.

Useful bootstrap controls are `BOOTSTRAP_KEEP_TEMP=1` to retain the disposable
flake, and `BOOTSTRAP_DRY_RUN=1` to print operations without installing,
activating, cloning, or installing Homebrew.

## Rebuild and update

macOS:

```sh
sudo darwin-rebuild switch \
  --flake "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles#<config-name>"
```

Linux:

```sh
home-manager switch \
  --flake "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles#<config-name>"
```

Update pinned inputs, then rebuild with the appropriate command:

```sh
cd "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
nix flake update
```

## Project environments

Home Manager enables `direnv`, `nix-direnv`, and shell integration. In a
project with a flake:

```sh
echo 'use flake' > .envrc
direnv allow
```

## macOS package policy

On macOS, bootstrap installs Homebrew if it is absent, after Git is available
and before the real nix-darwin activation. This uses Homebrew's official
installer and then recognizes either `/opt/homebrew` (Apple Silicon) or
`/usr/local` (Intel). nix-darwin declares Homebrew packages; it does not use
Nix packages to emulate casks.

- Nixpkgs/Home Manager: ordinary terminal tools.
- Homebrew formulae: macOS-specific or Nix-incompatible command-line tools.
- Homebrew casks: non-App-Store GUI apps.
- `masApps`: Mac App Store apps.

Sign into the Mac App Store first. `mas` uses that existing session, and
removing an entry from `masApps` may not uninstall an already installed app.

`darwin/homebrew.nix` starts with `cleanup = "none"`, which is safest while
migrating. After the declaration is complete, consider `cleanup = "uninstall"`.
`cleanup = "zap"` is more destructive and is deliberately not the default.

## Identity and defaults

Git is enabled but no identity is invented. Set `programs.git.userName` and
`programs.git.userEmail` in a private host module or uncomment the documented
placeholders in `home/git.nix`. macOS defaults are isolated in
`darwin/defaults.nix` and are conservative by default.
