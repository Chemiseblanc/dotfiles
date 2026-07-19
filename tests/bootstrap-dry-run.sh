#!/bin/sh
set -eu

TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-dry-run.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir "$TEST_DIR/bin"
TEST_USER=$(id -un)

cat >"$TEST_DIR/bin/hostname" <<'EOF_HOSTNAME'
#!/bin/sh
printf '%s\n' test-host
EOF_HOSTNAME
cat >"$TEST_DIR/bin/nix" <<'EOF_NIX'
#!/bin/sh
printf '%s\n' "$*" >>"$NIX_LOG"
for argument do
	if [ "$argument" = eval ]; then
		printf '%s\n' example@linux-x86_64 work@linux-x86_64
		exit
	fi
done
printf '%s\n' 'nix (Lix) test'
EOF_NIX
chmod +x "$TEST_DIR/bin/hostname" "$TEST_DIR/bin/nix"
printf '%s\n' 2 >"$TEST_DIR/choice"

export NIX_LOG="$TEST_DIR/nix.log"
output=$(PATH="$TEST_DIR/bin:$PATH" TMPDIR="$TEST_DIR" BOOTSTRAP_DRY_RUN=1 \
	BOOTSTRAP_INPUT="$TEST_DIR/choice" DOTFILES_DIR=$PWD sh ./bootstrap.sh 2>&1)
printf '%s\n' "$output" | grep -F 'Detected x86_64-linux' >/dev/null
printf '%s\n' "$output" | grep -F 'Configurations for x86_64-linux:' >/dev/null
printf '%s\n' "$output" | grep -F '2) work@linux-x86_64' >/dev/null
printf '%s\n' "$output" | grep -F 'Activating Home Manager configuration work@linux-x86_64' >/dev/null
grep -F 'homeConfigurations' "$NIX_LOG" >/dev/null
grep -F "path:$PWD#homeConfigurations" "$NIX_LOG" >/dev/null
grep -F 'pkgs.stdenv.hostPlatform.system == "x86_64-linux"' "$NIX_LOG" >/dev/null
printf '%s\n' "$output" | grep -F 'Preserving temporary bootstrap files:' >/dev/null

mkdir "$TEST_DIR/darwin-bin"
cat >"$TEST_DIR/darwin-bin/uname" <<'EOF_UNAME'
#!/bin/sh
case "$1" in
	-s) printf '%s\n' Darwin ;;
	-m) printf '%s\n' arm64 ;;
	*) exit 1 ;;
esac
EOF_UNAME
cp "$TEST_DIR/bin/hostname" "$TEST_DIR/bin/nix" "$TEST_DIR/darwin-bin/"
chmod +x "$TEST_DIR/darwin-bin/uname"

darwin_output=$(PATH="$TEST_DIR/darwin-bin:$PATH" TMPDIR="$TEST_DIR" BOOTSTRAP_DRY_RUN=1 \
	DOTFILES_DARWIN_CONFIG=work-darwin DOTFILES_DIR=$PWD sh ./bootstrap.sh 2>&1)
printf '%s\n' "$darwin_output" | grep -F 'Detected aarch64-darwin' >/dev/null
printf '%s\n' "$darwin_output" | grep -F \
	"switch --flake path:$TEST_DIR/dotfiles-bootstrap." >/dev/null
printf '%s\n' "$darwin_output" | grep -F '#bootstrap' >/dev/null
printf '%s\n' "$darwin_output" | grep -F "Activating nix-darwin configuration work-darwin" >/dev/null
printf '%s\n' "$darwin_output" | grep -F "path:$PWD#work-darwin" >/dev/null
if printf '%s\n' "$darwin_output" | grep -F 'Installing Homebrew' >/dev/null; then
	printf '%s\n' 'bootstrap must leave Homebrew installation to nix-homebrew' >&2
	exit 1
fi
grep -F 'darwinConfigurations.bootstrap = nix-darwin.lib.darwinSystem {' \
	"$TEST_DIR"/dotfiles-bootstrap.*/flake.nix >/dev/null
grep -F 'nix-homebrew.darwinModules.nix-homebrew' \
	"$TEST_DIR"/dotfiles-bootstrap.*/flake.nix >/dev/null
grep -F 'enableRosetta = true;' "$TEST_DIR"/dotfiles-bootstrap.*/flake.nix >/dev/null
test "$(grep -l 'homeModule = { pkgs, ... }:' "$TEST_DIR"/dotfiles-bootstrap.*/flake.nix | wc -l)" -eq 2
grep -F 'modules = [ homeModule ];' "$TEST_DIR"/dotfiles-bootstrap.*/flake.nix >/dev/null
grep -F "home-manager.users.\"$TEST_USER\" = homeModule;" \
	"$TEST_DIR"/dotfiles-bootstrap.*/flake.nix >/dev/null

if command -v nix-instantiate >/dev/null 2>&1; then
	for flake in "$TEST_DIR"/dotfiles-bootstrap.*/flake.nix; do
		nix-instantiate --parse "$flake" >/dev/null
	done
fi
