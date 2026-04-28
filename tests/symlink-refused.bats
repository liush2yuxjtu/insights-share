#!/usr/bin/env bats
# Symlinked flag files must produce empty stdout (no terminal injection).

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/statusline-pulse.sh"
  TMP_HOME="$(mktemp -d)"
  export HOME="${TMP_HOME}"
  mkdir -p "${TMP_HOME}/.claude-team"
  TARGET="${TMP_HOME}/secret"
  printf 'INJECTED\033[31mEVIL\033[0m' > "${TARGET}"
}

teardown() {
  rm -rf "${TMP_HOME}"
}

@test "symlinked .pulse-hit produces empty output" {
  ln -s "${TARGET}" "${HOME}/.claude-team/.pulse-hit"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || [[ "$output" != *INJECTED* ]]
}

@test "symlinked .pulse-sync produces empty output" {
  ln -s "${TARGET}" "${HOME}/.claude-team/.pulse-sync"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" != *INJECTED* ]]
}

@test "symlinked .pulse-pipe produces empty output" {
  ln -s "${TARGET}" "${HOME}/.claude-team/.pulse-pipe"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
  [[ "$output" != *INJECTED* ]]
}

@test "symlink loop is harmless" {
  ln -s "${HOME}/.claude-team/.pulse-hit" "${HOME}/.claude-team/.pulse-hit"
  run bash "${SCRIPT}"
  [ "$status" -eq 0 ]
}
