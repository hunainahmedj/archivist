#!/bin/bash
# Test harness for the archivist doc gate. Plain bash, no framework.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HERE/../hooks/doc-gate.sh"
PASS=0; FAIL=0; SANDBOX=""

setup()    { SANDBOX="$(mktemp -d)"; }
teardown() { rm -rf "$SANDBOX"; }

mkrepo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}

embedded_ws() {  # monorepo: ws/ is one git repo with docs/ + web/ inside
  mkrepo "$SANDBOX/ws"
  mkdir -p "$SANDBOX/ws/docs/07-meta" "$SANDBOX/ws/web"
  cat > "$SANDBOX/ws/docs/.archivist.json" <<'EOF'
{"project":"t","layout":"embedded","repos":[{"path":"web","role":"app"}],"tracker":{"type":"self","prefix":"T"}}
EOF
  git -C "$SANDBOX/ws" add -A
  git -C "$SANDBOX/ws" -c user.email=t@t -c user.name=t commit -qm docs
}

sibling_ws() {  # multi-repo: ws/backend and ws/docs are separate git repos
  mkdir -p "$SANDBOX/ws"
  mkrepo "$SANDBOX/ws/backend"
  mkrepo "$SANDBOX/ws/docs"
  mkdir -p "$SANDBOX/ws/docs/07-meta"
  cat > "$SANDBOX/ws/docs/.archivist.json" <<'EOF'
{"project":"t","layout":"sibling","repos":[{"path":"backend","role":"api"}],"tracker":{"type":"jira","projectKey":"T"}}
EOF
  git -C "$SANDBOX/ws/docs" add -A
  git -C "$SANDBOX/ws/docs" -c user.email=t@t -c user.name=t commit -qm docs
}

run_gate() {  # $1=cwd  $2=stop_active(optional)  $3=session_id(optional)
  ARCHIVIST_CWD="$1" \
  ARCHIVIST_STOP_ACTIVE="${2:-}" \
  ARCHIVIST_SESSION_ID="${3:-test-$$}" \
  bash "$GATE"
}

check() {  # $1=description  $2=expected_exit  $3=actual_exit
  if [ "$2" -eq "$3" ]; then PASS=$((PASS+1)); echo "ok   - $1"
  else FAIL=$((FAIL+1)); echo "FAIL - $1 (expected exit $2, got $3)"; fi
}

test_no_config_allows() {
  setup; mkrepo "$SANDBOX/plain"
  run_gate "$SANDBOX/plain" >/dev/null 2>&1; check "no .archivist.json -> allow" 0 $?
  teardown
}

test_embedded_code_change_blocks() {
  setup; embedded_ws
  echo "x" > "$SANDBOX/ws/web/app.ts"
  run_gate "$SANDBOX/ws/web" >/dev/null 2>&1; check "embedded: code changed, docs untouched -> block" 3 $?
  teardown
}

test_embedded_code_plus_docs_allows() {
  setup; embedded_ws
  echo "x" > "$SANDBOX/ws/web/app.ts"
  echo "entry" >> "$SANDBOX/ws/docs/07-meta/changelog.md"
  run_gate "$SANDBOX/ws/web" >/dev/null 2>&1; check "embedded: code + docs changed -> allow" 0 $?
  teardown
}

test_md_only_change_allows() {
  setup; embedded_ws
  echo "notes" > "$SANDBOX/ws/web/README.md"
  run_gate "$SANDBOX/ws/web" >/dev/null 2>&1; check "markdown-only change -> allow" 0 $?
  teardown
}

test_no_changes_allows() {
  setup; embedded_ws
  run_gate "$SANDBOX/ws/web" >/dev/null 2>&1; check "clean tree -> allow" 0 $?
  teardown
}

test_stop_active_allows() {
  setup; embedded_ws
  echo "x" > "$SANDBOX/ws/web/app.ts"
  run_gate "$SANDBOX/ws/web" "1" >/dev/null 2>&1; check "stop_hook_active -> allow (loop protection)" 0 $?
  teardown
}

test_sibling_code_change_blocks() {
  setup; sibling_ws
  echo "x" > "$SANDBOX/ws/backend/api.ts"
  run_gate "$SANDBOX/ws/backend" >/dev/null 2>&1; check "sibling: code changed, docs repo untouched -> block" 3 $?
  teardown
}

test_sibling_docs_touched_allows() {
  setup; sibling_ws
  echo "x" > "$SANDBOX/ws/backend/api.ts"
  echo "entry" >> "$SANDBOX/ws/docs/07-meta/changelog.md"
  run_gate "$SANDBOX/ws/backend" >/dev/null 2>&1; check "sibling: code + docs changed -> allow" 0 $?
  teardown
}

test_missing_docs_repo_blocks_once_per_session() {
  setup
  mkdir -p "$SANDBOX/ws"; mkrepo "$SANDBOX/ws/backend"
  printf '@../docs/AGENTS.md\n' > "$SANDBOX/ws/backend/CLAUDE.md"
  sid="warn-$RANDOM"
  out="$(run_gate "$SANDBOX/ws/backend" "" "$sid" 2>/dev/null)"
  check "missing sibling docs repo -> block first call" 3 $?
  printf '%s' "$out" | grep -q "not cloned"
  check "missing docs repo message mentions not cloned" 0 $?
  printf '%s' "$out" | grep -q "git clone"
  check "missing docs repo message mentions git clone" 0 $?
  out2="$(run_gate "$SANDBOX/ws/backend" "" "$sid" 2>/dev/null)"
  check "missing docs repo -> allow second call, same session" 0 $?
  [ -z "$out2" ]
  check "no repeat message on second call" 0 $?
  teardown
}

test_block_message_names_docs_root() {
  setup; embedded_ws
  echo "x" > "$SANDBOX/ws/web/app.ts"
  out="$(run_gate "$SANDBOX/ws/web" 2>/dev/null)"
  printf '%s' "$out" | grep -q "documentation-guide.md"
  check "block message points at the rulebook" 0 $?
  teardown
}

test_verdict_persists_same_changes() {
  setup; embedded_ws
  echo "x" > "$SANDBOX/ws/web/app.ts"
  run_gate "$SANDBOX/ws/web" "" "A" >/dev/null 2>&1
  check "verdict: first block for change-set" 3 $?
  run_gate "$SANDBOX/ws/web" "" "A" >/dev/null 2>&1
  check "verdict: same session + same changes -> silent allow" 0 $?
  teardown
}

test_verdict_invalidated_by_new_changes() {
  setup; embedded_ws
  echo "x" > "$SANDBOX/ws/web/app.ts"
  run_gate "$SANDBOX/ws/web" "" "A" >/dev/null 2>&1
  check "verdict: first block for change-set" 3 $?
  run_gate "$SANDBOX/ws/web" "" "A" >/dev/null 2>&1
  check "verdict: rerun same changes -> silent allow" 0 $?
  echo "y" > "$SANDBOX/ws/web/other.ts"
  run_gate "$SANDBOX/ws/web" "" "A" >/dev/null 2>&1
  check "verdict: new file added to change-set -> block again" 3 $?
  teardown
}

test_verdict_is_per_session() {
  setup; embedded_ws
  echo "x" > "$SANDBOX/ws/web/app.ts"
  run_gate "$SANDBOX/ws/web" "" "A" >/dev/null 2>&1
  check "verdict: session A blocks" 3 $?
  run_gate "$SANDBOX/ws/web" "" "B" >/dev/null 2>&1
  check "verdict: different session, same changes -> blocks again" 3 $?
  teardown
}

test_verdict_sibling_layout() {
  setup; sibling_ws
  echo "x" > "$SANDBOX/ws/backend/api.ts"
  run_gate "$SANDBOX/ws/backend" "" "C" >/dev/null 2>&1
  check "verdict (sibling): first block for change-set" 3 $?
  run_gate "$SANDBOX/ws/backend" "" "C" >/dev/null 2>&1
  check "verdict (sibling): same session + same changes -> silent allow" 0 $?
  teardown
}

ADAPTER="$HERE/../hooks/claude-stop.sh"
CODEX_START="$HERE/../hooks/codex/codex-session-start.sh"

claude_payload() {  # $1=cwd $2=stop_hook_active(json bool)
  printf '{"session_id":"s-test","transcript_path":"/tmp/t","cwd":"%s","stop_hook_active":%s}' "$1" "$2"
}

vendored_hooks() {  # mirrors what /docs-init installs
  mkdir -p "$SANDBOX/vendored"
  cp "$HERE/../hooks/doc-gate.sh" "$HERE/../hooks/codex/codex-stop.sh" "$SANDBOX/vendored/"
}

test_claude_adapter_blocks_with_exit_2() {
  setup; embedded_ws
  echo "x" > "$SANDBOX/ws/web/app.ts"
  err="$(claude_payload "$SANDBOX/ws/web" false | bash "$ADAPTER" 2>&1 >/dev/null)"
  code=$?
  check "claude adapter: block -> exit 2" 2 $code
  printf '%s' "$err" | grep -q "archivist"
  check "claude adapter: message on stderr" 0 $?
  teardown
}

test_claude_adapter_allows() {
  setup; embedded_ws
  claude_payload "$SANDBOX/ws/web" false | bash "$ADAPTER" >/dev/null 2>&1
  check "claude adapter: clean tree -> exit 0" 0 $?
  teardown
}

test_claude_adapter_respects_stop_active() {
  setup; embedded_ws
  echo "x" > "$SANDBOX/ws/web/app.ts"
  claude_payload "$SANDBOX/ws/web" true | bash "$ADAPTER" >/dev/null 2>&1
  check "claude adapter: stop_hook_active=true -> exit 0" 0 $?
  teardown
}

test_codex_adapter_blocks_alt_fields() {
  setup; embedded_ws; vendored_hooks
  echo "x" > "$SANDBOX/ws/web/app.ts"
  printf '{"thread_id":"t1","working_directory":"%s","stopHookActive":false}' "$SANDBOX/ws/web" \
    | bash "$SANDBOX/vendored/codex-stop.sh" >/dev/null 2>&1
  check "codex adapter (vendored): block with alternate field names -> exit 2" 2 $?
  teardown
}

test_codex_session_start_injects_briefing() {
  setup; sibling_ws
  echo "BRIEFING-SENTINEL" > "$SANDBOX/ws/docs/AGENTS.md"
  out="$(cd "$SANDBOX/ws/backend" && bash "$CODEX_START" 2>/dev/null)"
  printf '%s' "$out" | grep -q "BRIEFING-SENTINEL"
  check "codex session-start: injects docs AGENTS.md" 0 $?
  teardown
}

CLAUDE_SESSION_START="$HERE/../hooks/claude-session-start.sh"

test_claude_session_start_notices_missing_docs() {
  setup
  mkdir -p "$SANDBOX/ws"; mkrepo "$SANDBOX/ws/backend"
  printf '@../docs/AGENTS.md\n' > "$SANDBOX/ws/backend/CLAUDE.md"
  out="$(cd "$SANDBOX/ws/backend" && bash "$CLAUDE_SESSION_START" 2>/dev/null)"
  printf '%s' "$out" | grep -q "not cloned"
  check "claude session-start: notices missing docs repo" 0 $?
  teardown
}

test_claude_session_start_silent_when_healthy() {
  setup; sibling_ws
  out="$(cd "$SANDBOX/ws/backend" && bash "$CLAUDE_SESSION_START" 2>/dev/null)"
  [ -z "$out" ]
  check "claude session-start: silent when docs repo present" 0 $?
  teardown
}

test_claude_session_start_silent_when_not_archivist() {
  setup; mkrepo "$SANDBOX/plain"
  out="$(cd "$SANDBOX/plain" && bash "$CLAUDE_SESSION_START" 2>/dev/null)"
  [ -z "$out" ]
  check "claude session-start: silent in non-archivist dir" 0 $?
  teardown
}

vendored_cursor() {  # mirrors what /docs-init installs
  mkdir -p "$SANDBOX/vendored-cursor"
  cp "$HERE/../hooks/doc-gate.sh" "$HERE/../hooks/cursor/cursor-stop.sh" "$SANDBOX/vendored-cursor/"
}

test_cursor_adapter_prints_checklist_but_exits_0() {
  setup; embedded_ws; vendored_cursor
  echo "x" > "$SANDBOX/ws/web/app.ts"
  out="$(printf '{"cwd":"%s","conversation_id":"c1"}' "$SANDBOX/ws/web" \
    | bash "$SANDBOX/vendored-cursor/cursor-stop.sh" 2>&1)"
  code=$?
  check "cursor adapter (vendored): block condition -> exit 0" 0 $code
  printf '%s' "$out" | grep -q "documentation-guide.md"
  check "cursor adapter: prints doc-gate checklist" 0 $?
  teardown
}

CODEX_TEMPLATE="$HERE/../hooks/codex/hooks.json.template"

test_codex_template_valid_json_after_substitution() {
  python3 -c "
import json
t = open('$CODEX_TEMPLATE').read().replace('{{HOOKS_DIR}}', '../docs/07-meta/hooks')
json.loads(t)
"
  check "guarded codex template parses as JSON after substitution" 0 $?
}

INSTALL_SH="$HERE/../install.sh"
SKILLS_DIR="$HERE/../skills"

test_install_sh_creates_catalogs() {
  setup
  HOME="$SANDBOX/home" bash "$INSTALL_SH" >/dev/null 2>&1
  check "install.sh: exits 0 on fresh HOME" 0 $?

  test -f "$SANDBOX/home/.archivist/skills/docs-init/SKILL.md"
  check "install.sh: ~/.archivist/skills/docs-init/SKILL.md exists" 0 $?

  test -L "$SANDBOX/home/.config/opencode/skills/docs-init"
  check "install.sh: opencode docs-init is a symlink" 0 $?

  python3 -c "
import os, sys
p = '$SANDBOX/home/.config/opencode/skills/docs-init/SKILL.md'
sys.exit(0 if os.path.isfile(os.path.realpath(p)) else 1)
"
  check "install.sh: opencode docs-init resolves to a real SKILL.md" 0 $?

  test -L "$SANDBOX/home/.codex/skills/docs-audit"
  check "install.sh: codex docs-audit is a symlink" 0 $?

  python3 -c "
import os, sys
p = '$SANDBOX/home/.codex/skills/docs-audit/SKILL.md'
sys.exit(0 if os.path.isfile(os.path.realpath(p)) else 1)
"
  check "install.sh: codex docs-audit resolves to a real SKILL.md" 0 $?

  [ ! -e "$SANDBOX/home/.claude/skills/docs-init" ]
  check "install.sh: claude skills docs-init absent by default" 0 $?
  teardown
}

test_install_sh_uninstall_removes_symlinks_keeps_tree() {
  setup
  HOME="$SANDBOX/home" bash "$INSTALL_SH" >/dev/null 2>&1
  HOME="$SANDBOX/home" bash "$INSTALL_SH" --uninstall >/dev/null 2>&1
  check "install.sh --uninstall: exits 0" 0 $?

  [ ! -e "$SANDBOX/home/.config/opencode/skills/docs-init" ]
  check "install.sh --uninstall: opencode symlink removed" 0 $?

  [ ! -e "$SANDBOX/home/.codex/skills/docs-audit" ]
  check "install.sh --uninstall: codex symlink removed" 0 $?

  test -d "$SANDBOX/home/.archivist"
  check "install.sh --uninstall: ~/.archivist tree still present" 0 $?
  teardown
}

test_skill_naming_rules() {
  for dir in "$SKILLS_DIR"/*/; do
    name="$(basename "$dir")"
    fm_name="$(grep -m1 '^name:' "$dir/SKILL.md" | sed 's/^name: *//' | tr -d '\r')"
    [ "$name" = "$fm_name" ]
    check "naming: $name dirname matches frontmatter name" 0 $?

    echo "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'
    check "naming: $name matches skill-name regex" 0 $?
  done
}

test_no_config_allows
test_embedded_code_change_blocks
test_embedded_code_plus_docs_allows
test_md_only_change_allows
test_no_changes_allows
test_stop_active_allows
test_sibling_code_change_blocks
test_sibling_docs_touched_allows
test_verdict_persists_same_changes
test_verdict_invalidated_by_new_changes
test_verdict_is_per_session
test_verdict_sibling_layout
test_missing_docs_repo_blocks_once_per_session
test_block_message_names_docs_root
test_claude_adapter_blocks_with_exit_2
test_claude_adapter_allows
test_claude_adapter_respects_stop_active
test_codex_adapter_blocks_alt_fields
test_codex_session_start_injects_briefing
test_claude_session_start_notices_missing_docs
test_claude_session_start_silent_when_healthy
test_claude_session_start_silent_when_not_archivist
test_cursor_adapter_prints_checklist_but_exits_0
test_codex_template_valid_json_after_substitution
test_install_sh_creates_catalogs
test_install_sh_uninstall_removes_symlinks_keeps_tree
test_skill_naming_rules

echo "---"
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
