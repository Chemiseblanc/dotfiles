#!/bin/sh
set -eu

REPOSITORY_DIR=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cleanup-dry-run.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT HUP INT TERM
mkdir -p "$TEST_DIR/bin" "$TEST_DIR/run" "$TEST_DIR/home"

cat >"$TEST_DIR/bin/home-manager" <<'EOF_HOME_MANAGER'
#!/bin/sh
exit 0
EOF_HOME_MANAGER
chmod +x "$TEST_DIR/bin/home-manager"

make_checkout() {
  checkout=$1
  mkdir -p "$checkout/.git"
}

line_number() {
  pattern=$1
  content=$2
  printf '%s\n' "$content" | grep -n -F -- "$pattern" | sed -n '1s/:.*//p'
}

LINUX_CHECKOUT=$TEST_DIR/linux-dotfiles
make_checkout "$LINUX_CHECKOUT"
printf '%s\n' y y y >"$TEST_DIR/linux-answers"
SHELL_UNDER_TEST=${SHELL:-/bin/sh}
[ -x "$SHELL_UNDER_TEST" ] || SHELL_UNDER_TEST=/bin/sh

linux_output=$(
  cd "$TEST_DIR/run"
  PATH="$TEST_DIR/bin:$PATH" TMPDIR="$TEST_DIR" CLEANUP_DRY_RUN=1 \
    CLEANUP_INPUT="$TEST_DIR/linux-answers" DOTFILES_DIR="$LINUX_CHECKOUT" \
    "$SHELL_UNDER_TEST" <"$REPOSITORY_DIR/cleanup.sh" 2>&1
)
printf '%s\n' "$linux_output" | grep -F 'Detected linux' >/dev/null
printf '%s\n' "$linux_output" | grep -F "+ $TEST_DIR/bin/home-manager uninstall" >/dev/null
printf '%s\n' "$linux_output" | grep -F "+ rm -rf $LINUX_CHECKOUT" >/dev/null
printf '%s\n' "$linux_output" | grep -F '+ sudo /nix/nix-installer uninstall --no-confirm' >/dev/null
home_manager_line=$(line_number 'home-manager uninstall' "$linux_output")
checkout_line=$(line_number "rm -rf $LINUX_CHECKOUT" "$linux_output")
lix_line=$(line_number '/nix/nix-installer uninstall' "$linux_output")
[ "$home_manager_line" -lt "$checkout_line" ]
[ "$checkout_line" -lt "$lix_line" ]
if printf '%s\n' "$linux_output" | grep -F 'gh auth logout' >/dev/null; then
  printf '%s\n' 'cleanup must preserve GitHub CLI authentication' >&2
  exit 1
fi

mkdir -p "$TEST_DIR/darwin-bin"
cp "$TEST_DIR/bin/home-manager" "$TEST_DIR/darwin-bin/home-manager"
cat >"$TEST_DIR/darwin-bin/uname" <<'EOF_UNAME'
#!/bin/sh
case "$1" in
  -s) printf '%s\n' Darwin ;;
  -m) printf '%s\n' arm64 ;;
  *) exit 1 ;;
esac
EOF_UNAME
cat >"$TEST_DIR/darwin-bin/darwin-uninstaller" <<'EOF_DARWIN_UNINSTALLER'
#!/bin/sh
exit 0
EOF_DARWIN_UNINSTALLER
chmod +x "$TEST_DIR/darwin-bin/uname" "$TEST_DIR/darwin-bin/darwin-uninstaller"

DARWIN_CHECKOUT=$TEST_DIR/darwin-dotfiles
make_checkout "$DARWIN_CHECKOUT"
printf '%s\n' y y y y >"$TEST_DIR/darwin-answers"
darwin_output=$(PATH="$TEST_DIR/darwin-bin:$PATH" TMPDIR="$TEST_DIR" CLEANUP_DRY_RUN=1 \
  CLEANUP_INPUT="$TEST_DIR/darwin-answers" DOTFILES_DIR="$DARWIN_CHECKOUT" \
  sh "$REPOSITORY_DIR/cleanup.sh" 2>&1)
printf '%s\n' "$darwin_output" | grep -F 'Detected darwin' >/dev/null
printf '%s\n' "$darwin_output" | grep -F "+ sudo $TEST_DIR/darwin-bin/darwin-uninstaller" >/dev/null
printf '%s\n' "$darwin_output" | grep -F -- '--dry-run --path /opt/homebrew' >/dev/null
printf '%s\n' "$darwin_output" | grep -F -- '--dry-run --path /usr/local' >/dev/null
darwin_line=$(line_number 'darwin-uninstaller' "$darwin_output")
homebrew_line=$(line_number '--dry-run --path /opt/homebrew' "$darwin_output")
darwin_checkout_line=$(line_number "rm -rf $DARWIN_CHECKOUT" "$darwin_output")
darwin_lix_line=$(line_number '/nix/nix-installer uninstall' "$darwin_output")
[ "$darwin_line" -lt "$homebrew_line" ]
[ "$homebrew_line" -lt "$darwin_checkout_line" ]
[ "$darwin_checkout_line" -lt "$darwin_lix_line" ]

printf '%s\n' n >"$TEST_DIR/decline-answers"
decline_output=$(PATH="$TEST_DIR/bin:$PATH" TMPDIR="$TEST_DIR" CLEANUP_DRY_RUN=1 \
  CLEANUP_INPUT="$TEST_DIR/decline-answers" DOTFILES_DIR="$TEST_DIR/absent-dotfiles" \
  sh "$REPOSITORY_DIR/cleanup.sh" 2>&1)
printf '%s\n' "$decline_output" | grep -F 'Keeping the managed configuration' >/dev/null
printf '%s\n' "$decline_output" | grep -F 'keeping Lix because the managed configuration was not removed' >/dev/null
if printf '%s\n' "$decline_output" | grep -F '+ sudo /nix/nix-installer uninstall' >/dev/null; then
  printf '%s\n' 'cleanup attempted to remove Lix after configuration removal was declined' >&2
  exit 1
fi

printf '%s\n' y >"$TEST_DIR/unsafe-answers"
if HOME="$TEST_DIR/home" PATH="$TEST_DIR/bin:$PATH" TMPDIR="$TEST_DIR" CLEANUP_DRY_RUN=1 \
  CLEANUP_INPUT="$TEST_DIR/unsafe-answers" DOTFILES_DIR="$TEST_DIR/home" \
  sh "$REPOSITORY_DIR/cleanup.sh" >"$TEST_DIR/unsafe-output" 2>&1; then
  printf '%s\n' 'cleanup accepted the home directory as its checkout' >&2
  exit 1
fi
grep -F 'refusing to remove an unsafe or non-Git checkout' "$TEST_DIR/unsafe-output" >/dev/null

printf '%s\n' 'cleanup dry-run tests passed'