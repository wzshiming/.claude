#!/usr/bin/env bats
# Frontmatter rules AGENTS.md states for agents/*.md. Each rule is a check_* function on one
# file, reading only its first `---`...`---` block: silent with status 0 when the file obeys, else
# one `measured (limit)` line and status 1. Each rule's test runs its check on every agent and
# fails once listing `file: measured (limit)`; a heredoc fixture proves each check can fail.

load helpers

AGENTS_DIR="$BATS_TEST_DIRNAME/../agents"

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

# agent_names <file>...: every `name:` value, one per line.
agent_names() {
  local f
  for f in "$@"; do
    frontmatter "$f" | sed -n 's/^name:[[:space:]]*//p' | sed 's/[[:space:]]*$//'
  done
}

# has_word <text> <word>: <word> occurs in <text> with no alphanumeric on either side.
has_word() {
  local esc
  esc=$(printf '%s\n' "$2" | sed 's/[][\.*^$+?(){}|]/\\&/g')
  printf '%s\n' "$1" | grep -Eq -- "(^|[^[:alnum:]])${esc}([^[:alnum:]]|$)"
}

# each_agent <check>: run <check> on every agents/*.md; fail once with every violation.
each_agent() {
  local f msg bad=""
  for f in "$AGENTS_DIR"/*.md; do
    [ -e "$f" ] || { echo "no agents/*.md found" >&2; return 1; }
    if ! msg=$("$1" "$f"); then
      bad="$bad${f##*/}: $msg"$'\n'
    fi
  done
  [ -z "$bad" ] && return 0
  printf '%s' "$bad" >&2
  return 1
}

check_required_keys() {
  local fm key missing=""
  fm=$(frontmatter "$1")
  for key in name description model tools; do
    if ! printf '%s\n' "$fm" | grep -q "^$key:"; then
      missing="${missing:+$missing, }$key"
    fi
  done
  [ -z "$missing" ] && return 0
  echo "missing $missing (name, description, model, tools)"
  return 1
}

check_name_matches_file() {
  local name base
  name=$(agent_names "$1")
  base=${1##*/}
  base=${base%.md}
  [ "$name" = "$base" ] && return 0
  echo "name $name (file name $base)"
  return 1
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

check_no_model_name() {
  local desc name found=""
  desc=$(description_value "$1")
  while IFS= read -r name; do
    if [ -n "$name" ] && has_word "$desc" "$name"; then
      found="${found:+$found, }$name"
    fi
  done <<EOF
$(model_names "$AGENTS_DIR"/*.md "$1")
EOF
  [ -z "$found" ] && return 0
  echo "names $found (no model names)"
  return 1
}

# A dispatchable agent is one whose description carries a `Brief:` clause.
check_dispatchable_names_no_agent() {
  local fm self desc name found=""
  fm=$(frontmatter "$1")
  if ! printf '%s\n' "$fm" | grep -q '^description:.*Brief:'; then
    return 0
  fi
  self=$(agent_names "$1")
  desc=$(description_value "$1")
  while IFS= read -r name; do
    if [ -n "$name" ] && [ "$name" != "$self" ] && has_word "$desc" "$name"; then
      found="${found:+$found, }$name"
    fi
  done <<EOF
$(agent_names "$AGENTS_DIR"/*.md)
EOF
  [ -z "$found" ] && return 0
  echo "names $found (no other agent names)"
  return 1
}

setup() { FIXTURE="$BATS_TEST_TMPDIR/fixture.md"; }

@test "every agent's frontmatter has name, description, model, and tools" {
  each_agent check_required_keys
}

@test "every agent's name is its file name" {
  each_agent check_name_matches_file
}

@test "every agent's description is one double-quoted line with one 'Use when:' and at most one 'Brief:'" {
  each_agent check_description_form
}

@test "every agent's description is at most 35 words before 'Brief:'" {
  each_agent check_description_words
}

@test "every agent's description has at most 3 triggers after 'Use when:'" {
  each_agent check_trigger_count
}

@test "no agent's description names a model from any agent's model field" {
  [ -n "$(model_names "$AGENTS_DIR"/*.md)" ]
  each_agent check_no_model_name
}

@test "no dispatchable agent's description names another agent" {
  each_agent check_dispatchable_names_no_agent
}

@test "a well-formed fixture passes every check" {
  cat > "$FIXTURE" <<'EOF'
---
name: fixture
description: "Does one thing for tests — nothing more. Use when: checking a rule, proving a fixture. Brief: anything at all, however long this clause runs."
model: inherit
tools: Read
---

# Fixture
EOF
  local check
  for check in check_required_keys check_name_matches_file check_description_form \
    check_description_words check_trigger_count check_no_model_name \
    check_dispatchable_names_no_agent; do
    run "$check" "$FIXTURE"
    assert_status 0
  done
}

@test "check_required_keys rejects a frontmatter missing tools:" {
  cat > "$FIXTURE" <<'EOF'
---
name: fixture
description: "Does one thing. Use when: testing."
model: inherit
---
EOF
  run check_required_keys "$FIXTURE"
  assert_status 1
  assert_output_is "missing tools (name, description, model, tools)"
}

@test "check_name_matches_file rejects a name differing from the file name" {
  cat > "$FIXTURE" <<'EOF'
---
name: Fixture
description: "Does one thing. Use when: testing."
model: inherit
tools: Read
---
EOF
  run check_name_matches_file "$FIXTURE"
  assert_status 1
  assert_output_is "name Fixture (file name fixture)"
}

@test "check_description_form rejects a description without 'Use when:'" {
  cat > "$FIXTURE" <<'EOF'
---
name: fixture
description: "Does one thing for tests."
model: inherit
tools: Read
---
EOF
  run check_description_form "$FIXTURE"
  assert_status 1
  assert_output_is "0 'Use when:' (exactly 1)"
}

@test "check_description_form rejects a second 'Brief:'" {
  cat > "$FIXTURE" <<'EOF'
---
name: fixture
description: "Does one thing. Use when: testing. Brief: a path. Brief: a goal."
model: inherit
tools: Read
---
EOF
  run check_description_form "$FIXTURE"
  assert_status 1
  assert_output_is "2 'Brief:' (at most 1)"
}

@test "check_description_words rejects a 36-word description" {
  cat > "$FIXTURE" <<'EOF'
---
name: fixture
description: "Fixture outcome clause — Use when: a b c d e f g h i j k l m n o p q r s t u v w x y z aa bb cc dd ee."
model: inherit
tools: Read
---
EOF
  run check_description_words "$FIXTURE"
  assert_status 1
  assert_output_is "36 words (35)"
}

@test "check_trigger_count rejects 4 triggers after 'Use when:'" {
  cat > "$FIXTURE" <<'EOF'
---
name: fixture
description: "Does one thing. Use when: one case, another case; a third case, a fourth case."
model: inherit
tools: Read
---
EOF
  run check_trigger_count "$FIXTURE"
  assert_status 1
  assert_output_is "4 triggers (3)"
}

@test "check_no_model_name rejects a description naming a model" {
  cat > "$FIXTURE" <<'EOF'
---
name: fixture
description: "Wraps fable calls. Use when: testing."
model: inherit
tools: Read
---
EOF
  run check_no_model_name "$FIXTURE"
  assert_status 1
  assert_output_is "names fable (no model names)"
}

@test "check_dispatchable_names_no_agent rejects a dispatchable description naming executor" {
  cat > "$FIXTURE" <<'EOF'
---
name: fixture
description: "Hands commands to executor. Use when: testing. Brief: anything."
model: inherit
tools: Read
---
EOF
  run check_dispatchable_names_no_agent "$FIXTURE"
  assert_status 1
  assert_output_is "names executor (no other agent names)"
}
