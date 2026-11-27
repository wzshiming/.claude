# shellcheck disable=SC2154 # status, output, lines: set by bats `run` in the calling test
# Shared by every tests/*.bats: the assertions serve all of them, the fixture only the
# worktree-*.sh tests — a bare origin seeded with one commit on master, and a clone MAIN
# whose origin/HEAD points at origin/master.
# Paths are compared as git prints them (macOS /var -> /private/var).

bats_require_minimum_version 1.5.0

# shellcheck disable=SC2034 # read by the tests/*.bats files
SCRIPTS="$BATS_TEST_DIRNAME/../scripts"

setup_fixture() {
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_NOSYSTEM=1
  unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  MAIN="$BATS_TEST_TMPDIR/main"
  git init -q --bare -b master "$ORIGIN"
  init_repo "$BATS_TEST_TMPDIR/seed"
  git -C "$BATS_TEST_TMPDIR/seed" push -q "$ORIGIN" master
  git clone -q "$ORIGIN" "$MAIN"
  set_identity "$MAIN"
  MAIN_ROOT=$(main_root_of "$MAIN")
  WORKTREES="$MAIN_ROOT/.worktrees"
}

# init_repo <path>: standalone repository on master with one commit and no remote.
init_repo() {
  git init -q -b master "$1"
  set_identity "$1"
  commit_file "$1" README.md "init"
}

set_identity() {
  git -C "$1" config user.name "Tester"
  git -C "$1" config user.email "tester@example.com"
}

# commit_file <repo> <relpath> <message>: append <message> to <relpath> and commit it.
commit_file() {
  mkdir -p "$1/$(dirname "$2")"
  printf '%s\n' "$3" >> "$1/$2"
  git -C "$1" add -- "$2"
  git -C "$1" commit -q -m "$3"
}

# advance_origin <branch>: from a throwaway clone, add one commit on <branch>
# (created from master when origin lacks it) and push it; MAIN's refs stay untouched.
advance_origin() {
  local pusher="$BATS_TEST_TMPDIR/pusher"
  rm -rf "$pusher"
  git clone -q "$ORIGIN" "$pusher"
  set_identity "$pusher"
  if git -C "$pusher" rev-parse -q --verify "origin/$1" >/dev/null; then
    git -C "$pusher" checkout -q "$1"
  else
    git -C "$pusher" checkout -q -b "$1" master
  fi
  commit_file "$pusher" "$1.txt" "advance $1"
  git -C "$pusher" push -q origin "$1"
}

# main_root_of <path>: first path of `git worktree list --porcelain`, as git prints it.
main_root_of() {
  git -C "$1" worktree list --porcelain | sed -n '1s/^worktree //p'
}

# worktree_of_branch <branch>: path MAIN registers for <branch>, empty when none.
worktree_of_branch() {
  git -C "$MAIN" worktree list --porcelain | awk -v want="branch refs/heads/$1" '
    /^worktree / { path = substr($0, 10) }
    $0 == want { print path }'
}

branch_exists() {
  git -C "$MAIN" show-ref --verify -q "refs/heads/$1"
}

# exclude_worktrees: what worktree-add.sh does before creating, so MAIN's status stays clean.
exclude_worktrees() {
  local exclude="$MAIN/.git/info/exclude"
  mkdir -p "${exclude%/*}"
  grep -qx '/\.worktrees' "$exclude" 2>/dev/null || printf '/.worktrees\n' >> "$exclude"
}

# add_linked <branch> [<start>]: register <branch> at the conventional path with plain git.
add_linked() {
  exclude_worktrees
  git -C "$MAIN" worktree add -q --no-track "$WORKTREES/$1" -b "$1" "${2:-origin/master}"
}

# lock_path: the per-repo lock directory both worktree scripts take, in MAIN's common git dir.
lock_path() {
  printf '%s/worktree-scripts.lock\n' "$(git -C "$MAIN" rev-parse --path-format=absolute --git-common-dir)"
}

# hold_lock <pid>: leave the lock behind as a holder running as <pid> would — the directory,
# <pid> in its pid file.
hold_lock() {
  local lock
  lock=$(lock_path)
  mkdir "$lock"
  printf '%s\n' "$1" > "$lock/pid"
}

# lock_entries: every worktree-scripts.lock* path in MAIN's common git dir, one per line — the
# lock itself plus any litter a waiter left (a stale rename, a temporary file).
lock_entries() {
  local lock
  lock=$(lock_path)
  find "${lock%/*}" -maxdepth 1 -name 'worktree-scripts.lock*'
}

# await_lock_holder <pid>: wait up to 5 s until the lock's pid file names <pid>.
await_lock_holder() {
  local pidfile tries=0
  pidfile="$(lock_path)/pid"
  until [ "$(cat "$pidfile" 2>/dev/null)" = "$1" ]; do
    tries=$((tries + 1))
    [ "$tries" -le 50 ] || { printf 'pid %s holds no lock after 5 s\n' "$1" >&2; return 1; }
    sleep 0.1
  done
}

# await_sleeping <pid>: wait up to 10 s until <pid> has a `sleep` child — a worktree script
# forks one only once its traps are set and the lock was found held, so it is inside the wait.
await_sleeping() {
  local tries=0
  until pgrep -P "$1" -x sleep >/dev/null; do
    kill -0 "$1" 2>/dev/null || { printf 'pid %s exited before it slept\n' "$1" >&2; return 1; }
    tries=$((tries + 1))
    [ "$tries" -le 200 ] || { printf 'pid %s forked no sleep within 10 s\n' "$1" >&2; return 1; }
    sleep 0.05
  done
}

# with_fake_sleep <log> <cmd...>: run <cmd> with tests/mock/sleep first on PATH, each of its
# sleeps returning at once and appending its argument as one line of <log>.
with_fake_sleep() {
  local log=$1
  shift
  env PATH="$BATS_TEST_DIRNAME/mock:$PATH" SLEEP_MOCK_LOG="$log" "$@"
}

# assert_full_lock_wait <log>: <log> holds exactly ten lines of `1` — a whole lock wait of 1 s steps.
assert_full_lock_wait() {
  local want
  want=$(printf '1\n%.0s' 1 2 3 4 5 6 7 8 9 10)
  [ "$(cat "$1" 2>/dev/null)" = "$want" ] && return 0
  printf -- '--- expected sleep log: ten lines of 1 ---\n--- actual ---\n%s\n' "$(cat "$1" 2>/dev/null)" >&2
  return 1
}

# dead_pid: pid of a child that has already exited, so kill -0 fails on it.
dead_pid() { sh -c 'echo $$'; }

# fails <cmd...>: succeed only when the command fails (a bare `!` is not caught mid-test).
fails() {
  if "$@"; then return 1; else return 0; fi
}

assert_status() {
  [ "$status" -eq "$1" ] && return 0
  printf 'expected exit %s, got %s\n--- stdout ---\n%s\n--- stderr ---\n%s\n' \
    "$1" "$status" "$output" "${stderr-}" >&2
  return 1
}

assert_output_is() {
  [ "$output" = "$1" ] && return 0
  printf -- '--- expected stdout ---\n%s\n--- actual stdout ---\n%s\n' "$1" "$output" >&2
  return 1
}

# has_line <exact>: succeed when stdout contains <exact> as a whole line.
has_line() {
  local l
  for l in "${lines[@]}"; do
    [ "$l" = "$1" ] && return 0
  done
  printf 'missing line: %s\n--- stdout ---\n%s\n' "$1" "$output" >&2
  return 1
}

# count_lines_matching <regex>: number of stdout lines matching <regex>.
count_lines_matching() {
  printf '%s\n' "${lines[@]}" | grep -c -- "$1" || true
}

# known_orphan <name>: the unregistered .worktrees/coder/<name> holding a copy of MAIN's README.md —
# a blob the repository has, as an editor re-saving a removed coder worktree's open files leaves them.
known_orphan() {
  exclude_worktrees
  mkdir -p "$WORKTREES/coder/$1"
  cp "$MAIN/README.md" "$WORKTREES/coder/$1/README.md"
}

# from_deleted_cwd <cmd...>: run <cmd> from a working directory removed after entering it, as a
# caller whose directory another process has since deleted; the caller's own cwd stays put.
from_deleted_cwd() (
  mkdir -p "$BATS_TEST_TMPDIR/gone" && cd "$BATS_TEST_TMPDIR/gone" && rmdir "$BATS_TEST_TMPDIR/gone" && "$@"
)

# Frontmatter checks shared by agents.bats and skills.bats. Each check_* reads one file's first
# `---`...`---` block: silent with status 0 when the file obeys, else one `measured (limit)` line
# and status 1.

# frontmatter <file>: the lines between the file's first two `---` lines.
frontmatter() {
  awk '$0 == "---" { if (open) exit; open = 1; next } open { print }' "$1"
}

# description_value <file>: the description's text before its `Brief:` clause, its enclosing
# double quotes removed — the outcome clause and the `Use when:` triggers.
description_value() {
  frontmatter "$1" | sed -n 's/^description:[[:space:]]*//p' | head -n 1 |
    sed 's/^"//; s/"[[:space:]]*$//; s/[[:space:]]*Brief:.*$//'
}

# model_names <file>...: every `model:` value, one per line, sorted.
model_names() {
  local f
  for f in "$@"; do
    frontmatter "$f" | sed -n 's/^model:[[:space:]]*//p' | sed 's/[[:space:]]*$//'
  done | sort -u
}

# has_word <text> <word>: <word> occurs in <text> with no alphanumeric on either side.
has_word() {
  local esc
  esc=$(printf '%s\n' "$2" | sed 's/[][\.*^$+?(){}|]/\\&/g')
  printf '%s\n' "$1" | grep -Eq -- "(^|[^[:alnum:]])${esc}([^[:alnum:]]|$)"
}

check_description_form() {
  local line uses briefs
  line=$(frontmatter "$1" | grep '^description:' | head -n 1)
  if ! printf '%s\n' "$line" | grep -Eq '^description:[[:space:]]*"([^"\\]|\\.)*"[[:space:]]*$'; then
    echo "description not one double-quoted line (single-line \"...\")"
    return 1
  fi
  uses=$(printf '%s\n' "$line" | awk '{ print gsub(/Use when:/, "") }')
  if [ "$uses" -ne 1 ]; then
    echo "$uses 'Use when:' (exactly 1)"
    return 1
  fi
  briefs=$(printf '%s\n' "$line" | awk '{ print gsub(/Brief:/, "") }')
  [ "$briefs" -le 1 ] && return 0
  echo "$briefs 'Brief:' (at most 1)"
  return 1
}

check_description_words() {
  local n
  n=$(description_value "$1" | awk '
    { for (i = 1; i <= NF; i++) if ($i ~ /[[:alnum:]]/) n++ }
    END { print n + 0 }')
  [ "$n" -le 35 ] && return 0
  echo "$n words (35)"
  return 1
}

check_trigger_count() {
  local n
  n=$(description_value "$1" | awk '{
    i = index($0, "Use when:")
    if (i == 0) { print 0; exit }
    t = substr($0, i + 9)
    sub(/\.[[:space:]]*$/, "", t)
    k = split(t, seg, /[,;]/)
    n = 0
    for (j = 1; j <= k; j++) if (seg[j] ~ /[^[:space:]]/) n++
    print n
    exit
  }')
  [ "${n:-0}" -le 3 ] && return 0
  echo "$n triggers (3)"
  return 1
}
