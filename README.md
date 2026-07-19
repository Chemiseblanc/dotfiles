# dotfiles

A cross-platform, flake-based development environment for macOS and Linux. The
bootstrap is deliberately small: it installs/reuses Lix, uses a disposable
configuration to expose Git and GitHub CLI and install Homebrew on macOS,
authenticates GitHub CLI when needed, clones a private repository selected by
the user, and activates the real configuration. Home Manager owns terminal
tooling and shell setup; nix-darwin owns macOS integrations.

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

The bootstrap prompts for the private repository in GitHub `OWNER/REPO` syntax.
If GitHub CLI has no existing login or `GH_TOKEN`, it starts the browser-based
login flow before cloning. The checkout is
`${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles`; override it with `DOTFILES_DIR`.

For an unattended run, set `DOTFILES_REPOSITORY=OWNER/REPO` and authenticate
GitHub CLI in advance or provide `GH_TOKEN`. An existing checkout is reused
without prompting for a repository or authenticating GitHub CLI.

## Configuration selection

The flake intentionally supplies safe example configurations rather than
pretending to know personal host names. After cloning the repository, bootstrap
lists the configurations whose Nix system matches the current platform and
prompts for one by number:

- macOS lists matching attributes from `darwinConfigurations`.
- Linux lists matching attributes from `homeConfigurations`.

For an unattended run, select a configuration explicitly, e.g.
`DOTFILES_HOME_CONFIG=example@linux-x86_64` or
`DOTFILES_DARWIN_CONFIG=example-darwin-aarch64`. These overrides skip the
prompt. Bootstrap does not rename an existing checkout.

Useful bootstrap controls are `BOOTSTRAP_KEEP_TEMP=1` to retain the disposable
flake, and `BOOTSTRAP_DRY_RUN=1` to print operations without installing,
activating, or cloning.

## Cleanup

Run the cleanup directly from the public repository:

```sh
curl -fsSL \
  https://raw.githubusercontent.com/chemiseblanc/dotfiles/main/cleanup.sh |
  "$SHELL"
```

The script reads confirmations from `/dev/tty`, so piping the script through the
shell does not consume its answers. Every destructive stage defaults to no. It
removes Home Manager and nix-darwin state first, both Homebrew prefixes on
Apple Silicon, the dotfiles checkout, and finally Lix and the Nix store. Lix and
Homebrew are treated as installations owned by this setup.

To inspect or preview it first:

```sh
curl -fsSLo /tmp/cleanup-dotfiles.sh \
  https://raw.githubusercontent.com/chemiseblanc/dotfiles/main/cleanup.sh

less /tmp/cleanup-dotfiles.sh
CLEANUP_DRY_RUN=1 "$SHELL" /tmp/cleanup-dotfiles.sh
```

`DOTFILES_DIR` overrides the checkout location, and `CLEANUP_INPUT` overrides
the confirmation input for automation. When configuration removal is declined
or fails, cleanup keeps Lix to avoid leaving active Nix-managed links without a
working package manager. GitHub CLI authentication is preserved. User-created
project `.envrc` files and Mac App Store applications are not removed.

After cleanup, start a new login shell to discard the old environment. A macOS
restart may be required after removing nix-darwin and Lix.

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

On macOS, the disposable nix-darwin configuration uses `nix-homebrew` to
install Homebrew before activating the real configuration. The real
configuration keeps ownership of its standard prefix. Existing installations
are migrated automatically, and Apple Silicon systems also receive the Intel
prefix through Rosetta. nix-darwin declares Homebrew packages; it does not use
Nix packages to emulate casks.

- Nixpkgs/Home Manager: ordinary terminal tools.
- Homebrew formulae: macOS-specific or Nix-incompatible command-line tools.
- Homebrew casks: non-App-Store GUI apps.
- `masApps`: Mac App Store apps.

Sign into the Mac App Store first. `mas` uses that existing session, and
removing an entry from `masApps` may not uninstall an already installed app.

`platforms/darwin/homebrew.nix` starts with `cleanup = "none"`, which is safest while
migrating. After the declaration is complete, consider `cleanup = "uninstall"`.
`cleanup = "zap"` is more destructive and is deliberately not the default.

## Identity and defaults

Git is enabled but no identity is invented. Set `programs.git.userName` and
`programs.git.userEmail` in a private host module or uncomment the documented
placeholders in `common/git.nix`. macOS defaults are isolated in
`platforms/darwin/defaults.nix` and are conservative by default.
