#!/usr/bin/env bats
# Frontmatter rules AGENTS.md states for skills/<name>/SKILL.md, in the style of agents.bats: each
# rule is a check_* function on one file, silent with status 0 when it obeys, else one
# `measured (limit)` line and status 1; each rule's test runs its check on every skill and fails
# once listing every violation; a heredoc fixture proves each skill-only check can fail.

load helpers

AGENTS_DIR="$BATS_TEST_DIRNAME/../agents"
SKILLS_DIR="$BATS_TEST_DIRNAME/../skills"

# each_skill <check>: run <check> on every skills/*/SKILL.md; fail once with every violation.
each_skill() {
  local f msg bad=""
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    [ -e "$f" ] || { echo "no skills/*/SKILL.md found" >&2; return 1; }
    if ! msg=$("$1" "$f"); then
      bad="$bad${f#"$SKILLS_DIR"/}: $msg"$'\n'
    fi
  done
  [ -z "$bad" ] && return 0
  printf '%s' "$bad" >&2
  return 1
}

# field <file> <key>: the frontmatter value of <key>, trailing blanks removed.
field() {
  frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n 1 | sed 's/[[:space:]]*$//'
}

check_skill_keys() {
  local fm key missing=""
  fm=$(frontmatter "$1")
  for key in name description model disable-model-invocation disallowed-tools; do
    if ! printf '%s\n' "$fm" | grep -q "^$key:"; then
      missing="${missing:+$missing, }$key"
    fi
  done
  [ -z "$missing" ] && return 0
  echo "missing $missing (name, description, model, disable-model-invocation, disallowed-tools)"
  return 1
}

check_name_matches_dir() {
  local name dir
  name=$(field "$1" name)
  dir=${1%/SKILL.md}
  dir=${dir##*/}
  [ "$name" = "$dir" ] && return 0
  echo "name $name (directory name $dir)"
  return 1
}

# A skill is never dispatched, so it has no `Brief:` clause.
check_no_brief() {
  local n
  n=$(frontmatter "$1" | grep '^description:' | awk '{ print gsub(/Brief:/, "") }')
  [ "${n:-0}" -eq 0 ] && return 0
  echo "$n 'Brief:' (0)"
  return 1
}

check_user_only() {
  local v
  v=$(field "$1" disable-model-invocation)
  [ "$v" = "true" ] && return 0
  echo "disable-model-invocation ${v:-unset} (true)"
  return 1
}

# Every command is an executor dispatch, so no skill keeps Bash.
check_no_bash() {
  local v
  v=$(field "$1" disallowed-tools)
  has_word "$v" Bash && return 0
  echo "disallowed-tools ${v:-unset} (includes Bash)"
  return 1
}

check_skill_no_model_name() {
  local desc name found=""
  desc=$(description_value "$1")
  while IFS= read -r name; do
    if [ -n "$name" ] && has_word "$desc" "$name"; then
      found="${found:+$found, }$name"
    fi
  done <<EOF
$(model_names "$AGENTS_DIR"/*.md "$SKILLS_DIR"/*/SKILL.md "$1")
EOF
  [ -z "$found" ] && return 0
  echo "names $found (no model names)"
  return 1
}

# The body's `## Rules` carries the Precedence and Tools items the harness cannot enforce.
check_rules_items() {
  local rules label missing=""
  rules=$(awk '$0 == "## Rules" { r = 1; next } r && /^## / { exit } r { print }' "$1")
  for label in Precedence Tools; do
    if ! printf '%s\n' "$rules" | grep -q "^- $label: "; then
      missing="${missing:+$missing, }$label"
    fi
  done
  [ -z "$missing" ] && return 0
  echo "Rules lacks $missing (Precedence, Tools)"
  return 1
}

setup() {
  FIXTURE="$BATS_TEST_TMPDIR/fixture/SKILL.md"
  mkdir -p "${FIXTURE%/*}"
}

@test "every skill's frontmatter has name, description, model, disable-model-invocation, and disallowed-tools" {
  each_skill check_skill_keys
}

@test "every skill's name is its directory name" {
  each_skill check_name_matches_dir
}

@test "no skill shares a name with an agent" {
  local f name dup=""
  for f in "$SKILLS_DIR"/*/SKILL.md; do
    name=$(field "$f" name)
    [ -e "$AGENTS_DIR/$name.md" ] && dup="${dup:+$dup, }$name"
  done
  [ -z "$dup" ] || { echo "shared name: $dup" >&2; return 1; }
}

@test "every skill's description is one double-quoted line with one 'Use when:' and no 'Brief:'" {
  each_skill check_description_form
  each_skill check_no_brief
}

@test "every skill's description is at most 35 words with at most 3 triggers" {
  each_skill check_description_words
  each_skill check_trigger_count
}

@test "no skill's description names a model" {
  each_skill check_skill_no_model_name
}

@test "every skill runs only when the user invokes it" {
  each_skill check_user_only
}

@test "every skill disallows Bash" {
  each_skill check_no_bash
}

@test "every skill's Rules carry Precedence and Tools items" {
  each_skill check_rules_items
}

@test "a well-formed fixture passes every skill check" {
  cat > "$FIXTURE" <<'EOF'
---
name: fixture
description: "Does one thing for tests. Use when: checking a rule."
model: inherit
disable-model-invocation: true
disallowed-tools: Bash, Grep
---

# Fixture

## Rules

- Precedence: these win
- Tools: only `Read`
EOF
  local check
  for check in check_skill_keys check_name_matches_dir check_description_form check_no_brief \
    check_description_words check_trigger_count check_skill_no_model_name check_user_only \
    check_no_bash check_rules_items; do
    run "$check" "$FIXTURE"
    assert_status 0
  done
}

@test "skill checks reject a fixture breaking each skill-only rule" {
  cat > "$FIXTURE" <<'EOF'
---
name: other
description: "Does one thing. Use when: testing. Brief: a path."
model: inherit
disallowed-tools: Grep
---

## Rules

- Tools: only `Read`
EOF
  run check_skill_keys "$FIXTURE"
  assert_status 1
  assert_output_is "missing disable-model-invocation (name, description, model, disable-model-invocation, disallowed-tools)"
  run check_name_matches_dir "$FIXTURE"
  assert_status 1
  assert_output_is "name other (directory name fixture)"
  run check_no_brief "$FIXTURE"
  assert_status 1
  assert_output_is "1 'Brief:' (0)"
  run check_user_only "$FIXTURE"
  assert_status 1
  assert_output_is "disable-model-invocation unset (true)"
  run check_no_bash "$FIXTURE"
  assert_status 1
  assert_output_is "disallowed-tools Grep (includes Bash)"
  run check_rules_items "$FIXTURE"
  assert_status 1
  assert_output_is "Rules lacks Precedence (Precedence, Tools)"
}
