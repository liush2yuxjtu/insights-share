#!/usr/bin/env bats
# statusline-renders.bats — colour matrix for statusline-pulse.sh

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/statusline-pulse.sh"
  TMP_HOME="$(mktemp -d)"
  export HOME="${TMP_HOME}"
  mkdir -p "${TMP_HOME}/.claude-team"
  HIT="${TMP_HOME}/.claude-team/.pulse-hit"
  SYNC="${TMP_HOME}/.claude-team/.pulse-sync"
  PIPE="${TMP_HOME}/.claude-team/.pulse-pipe"
  NOW=$(date +%s)
}

teardown() {
  rm -rf "${TMP_HOME}"
}

# Strip ANSI escapes for content assertions.
strip() { printf '%s' "$1" | sed -E 's/\x1b\[[0-9;]*m//g'; }

@test "all flags missing → minimal grey [is]" {
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ "$(strip "$output")" = "[is]" ]
  [[ "$output" == *$'\033[38;5;244m'* ]]
}

@test "green path: 0 hits, OK sync now, healthy pipe" {
  printf '0' > "${HIT}"
  printf 'OK|324|3|%s' "${NOW}" > "${SYNC}"
  printf '12|0|%s' "${NOW}" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(strip "$output")" == "[is 0 │ 324✓"*"s │ 12%cat]" ]] || [[ "$(strip "$output")" == "[is 0 │ 324✓0s │ 12%cat]" ]]
  [[ "$output" == *$'\033[38;5;71m'* ]]
}

@test "yellow hit: 3 hits triggers ⚠ marker and yellow frame" {
  printf '3' > "${HIT}"
  printf 'OK|324|3|%s' "${NOW}" > "${SYNC}"
  printf '12|0|%s' "${NOW}" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(strip "$output")" == *"3⚠"* ]]
  [[ "$output" == *$'\033[38;5;179m'* ]]
}

@test "red hit: 7 hits triggers ☠ and red frame" {
  printf '7' > "${HIT}"
  printf 'OK|324|3|%s' "${NOW}" > "${SYNC}"
  printf '12|0|%s' "${NOW}" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(strip "$output")" == *"7☠"* ]]
  [[ "$output" == *$'\033[38;5;167m'* ]]
}

@test "red vault: FAIL state forces ✗sync and red frame" {
  printf '0' > "${HIT}"
  printf 'FAIL|324|0|%s' "$(( NOW - 7200 ))" > "${SYNC}"
  printf '12|0|%s' "${NOW}" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(strip "$output")" == *"✗sync"* ]]
  [[ "$output" == *$'\033[38;5;167m'* ]]
}

@test "red pipe: 70% uncategorized triggers ☠" {
  printf '0' > "${HIT}"
  printf 'OK|324|3|%s' "${NOW}" > "${SYNC}"
  printf '70|3|%s' "${NOW}" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(strip "$output")" == *"70%☠"* ]]
  [[ "$output" == *$'\033[38;5;167m'* ]]
}

@test "yellow vault: lopsided sharing (peers<3 with TOTAL>50)" {
  printf '0' > "${HIT}"
  printf 'OK|322|2|%s' "${NOW}" > "${SYNC}"
  printf '12|0|%s' "${NOW}" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(strip "$output")" == *"322/2⚠"* ]]
  [[ "$output" == *$'\033[38;5;179m'* ]]
}

@test "yellow vault: peers<3 with low total still yellow via since-rule path" {
  printf '0' > "${HIT}"
  printf 'OK|10|0|%s' "${NOW}" > "${SYNC}"
  printf '0|0|%s' "${NOW}" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;179m'* ]]
}

@test "yellow pipe: staging backlog 12 in mid range" {
  printf '0' > "${HIT}"
  printf 'OK|324|3|%s' "${NOW}" > "${SYNC}"
  printf '20|12|%s' "${NOW}" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(strip "$output")" == *"12stg⚠"* ]]
  [[ "$output" == *$'\033[38;5;179m'* ]]
}

@test "highest severity wins: hit yellow + pipe red → red frame" {
  printf '3' > "${HIT}"
  printf 'OK|324|3|%s' "${NOW}" > "${SYNC}"
  printf '70|3|%s' "${NOW}" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\033[38;5;167m'* ]]
}
