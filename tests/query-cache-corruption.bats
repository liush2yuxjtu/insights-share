#!/usr/bin/env bats
# Regression: query-insights.sh used to corrupt query_cache.json on the very
# first write (echoed RESULTS verbatim with embedded LFs into a JSON string
# field). Subsequent runs would leak `jq: parse error` to stderr.

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  TMP_HOME="$(mktemp -d)"
  export HOME="${TMP_HOME}"
  mkdir -p "${HOME}/.claude-team/insights" "${HOME}/.claude-team/cache"
  # Fake index that matches "jsonl" and "mock"
  cat > "${HOME}/.claude-team/insights/index.json" <<'EOF'
{"insights":[
  {"name":"jsonl smoke test 用 mtime 倒序","when_to_use":"jsonl files","description":"用 ls -t","uploader":"x","uploader_ip":"x","topic_slug":"jsonl","created_at":"2026-04-28T00:00:00Z"},
  {"name":"don't mock the database","when_to_use":"integration tests","description":"hit a real DB","uploader":"x","uploader_ip":"x","topic_slug":"testing","created_at":"2026-04-28T00:00:00Z"}
]}
EOF
  SCRIPT="${REPO_ROOT}/scripts/query-insights.sh"
}

teardown() {
  rm -rf "${TMP_HOME}"
}

@test "first write produces valid JSON cache" {
  bash "${SCRIPT}" "jsonl" >/dev/null
  run jq -e '.' "${HOME}/.claude-team/cache/query_cache.json"
  [ "$status" -eq 0 ]
}

@test "second different prompt does not leak jq parse error to stderr" {
  bash "${SCRIPT}" "jsonl" >/dev/null
  stderr_output="$(bash "${SCRIPT}" "mock" 2>&1 1>/dev/null)"
  [[ "${stderr_output}" != *"parse error"* ]]
  [[ "${stderr_output}" != *"control characters"* ]]
}

@test "cache stays valid JSON across 4 distinct prompts" {
  for q in jsonl mock not_a_match xyz; do bash "${SCRIPT}" "${q}" >/dev/null; done
  run jq -e '.' "${HOME}/.claude-team/cache/query_cache.json"
  [ "$status" -eq 0 ]
}

@test "results in cache JSON-escape embedded newlines" {
  bash "${SCRIPT}" "jsonl" >/dev/null
  result_str="$(jq -r '.[0].result' "${HOME}/.claude-team/cache/query_cache.json")"
  [[ "${result_str}" == *"### "* ]]
  [[ "${result_str}" == *$'\n'* ]]
}

@test "pre-corrupted cache is detected and rebuilt cleanly" {
  printf '[{"prompt":"x","result":"line1\nline2"}]' > "${HOME}/.claude-team/cache/query_cache.json"
  ! jq -e '.' "${HOME}/.claude-team/cache/query_cache.json" >/dev/null 2>&1
  stderr_output="$(bash "${SCRIPT}" "jsonl" 2>&1 1>/dev/null)"
  [[ "${stderr_output}" != *"parse error"* ]]
  run jq -e '.' "${HOME}/.claude-team/cache/query_cache.json"
  [ "$status" -eq 0 ]
}

@test "pulse-hit still updates even when cache was corrupt" {
  printf 'BROKEN' > "${HOME}/.claude-team/cache/query_cache.json"
  bash "${SCRIPT}" "jsonl" >/dev/null 2>&1
  [ "$(cat "${HOME}/.claude-team/.pulse-hit")" = "1" ]
}
