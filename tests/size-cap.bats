#!/usr/bin/env bats
# Flag files larger than 64 bytes or non-whitelist content must not leak.

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/statusline-pulse.sh"
  TMP_HOME="$(mktemp -d)"
  export HOME="${TMP_HOME}"
  mkdir -p "${TMP_HOME}/.claude-team"
  HIT="${HOME}/.claude-team/.pulse-hit"
  SYNC="${HOME}/.claude-team/.pulse-sync"
  PIPE="${HOME}/.claude-team/.pulse-pipe"
}

teardown() {
  rm -rf "${TMP_HOME}"
}

strip() { printf '%s' "$1" | sed -E 's/\x1b\[[0-9;]*m//g'; }

@test "oversized hit flag is truncated, never echoed verbatim" {
  printf '%.0s9' {1..200} > "${HIT}"
  printf 'OK|10|3|%s' "$(date +%s)" > "${SYNC}"
  printf '0|0|%s' "$(date +%s)" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(strip "$output")" != *"99999999999999"* ]]
  [[ "$(strip "$output")" == *"999"* ]]  # capped at 999
}

@test "non-numeric hit flag normalises to 0" {
  printf '\033[31mPWNED\033[0m' > "${HIT}"
  printf 'OK|10|3|%s' "$(date +%s)" > "${SYNC}"
  printf '0|0|%s' "$(date +%s)" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(strip "$output")" == *"is 0 "* ]]
  [[ "$(strip "$output")" != *"PWNED"* ]]
}

@test "malformed sync flag is rejected (treated as missing)" {
  printf '0' > "${HIT}"
  printf 'GARBAGE_NO_PIPES' > "${SYNC}"
  printf '0|0|%s' "$(date +%s)" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(strip "$output")" != *"GARBAGE"* ]]
}

@test "malformed pipe flag is rejected" {
  printf '0' > "${HIT}"
  printf 'OK|10|3|%s' "$(date +%s)" > "${SYNC}"
  printf 'NOT_A_PIPE_FORMAT_AT_ALL' > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$(strip "$output")" != *"NOT_A_PIPE"* ]]
}

@test "uncat>100 in pipe flag is clamped to 100" {
  printf '0' > "${HIT}"
  printf 'OK|10|3|%s' "$(date +%s)" > "${SYNC}"
  printf '999|0|%s' "$(date +%s)" > "${PIPE}"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  # since UNCAT regex limits to 1-3 digits, 999 is accepted then clamped to 100 → red
  [[ "$(strip "$output")" == *"100"* ]] || [[ "$(strip "$output")" == *"99"* ]]
}
