#!/bin/bash
# rsync-merge.sh — Two-way merge of insights across LAN teammates
#
# Replaces rsync-push.sh's destructive overwrite. For each teammate:
#   1. Pull remote index.json to staging
#   2. jq-merge: union by content_hash, earliest uploader wins,
#      raw_hashes/topic_slug taken as field-level union (no metadata loss)
#   3. Bidirectional rsync of raw/ (content-addressed, --ignore-existing safe)
#   4. Write merged to local AND push to remote, both sides backed up first
#
# Idempotent: running on already-converged state is a no-op.
#
# Usage:
#   scripts/rsync-merge.sh           # merge with all teammates
#   scripts/rsync-merge.sh <name>    # merge with one named teammate

set -e

TEAM_DIR="${HOME}/.claude-team"
CONFIG="${TEAM_DIR}/config/teammates.json"
INDEX="${TEAM_DIR}/insights/index.json"
RAW_DIR="${TEAM_DIR}/insights/raw/"
STAGING="${TEAM_DIR}/cache/merge-staging"
ONLY="${1:-}"

mkdir -p "${STAGING}" "${RAW_DIR}"

if [[ ! -f "${CONFIG}" ]]; then
  echo "[rsync-merge] no teammates config at ${CONFIG}" >&2
  exit 0
fi

if [[ ! -f "${INDEX}" ]]; then
  echo '{"insights":[]}' > "${INDEX}"
fi

# Field-level merge: content_hash groups → earliest entry as base,
# enriched with non-null topic_slug and union of raw_hashes from all peers.
JQ_MERGE='
  {
    insights: (
      (.[0].insights + .[1].insights)
      | group_by(.content_hash)
      | map(
          (sort_by(.created_at // "")[0]) as $base
          | $base + {
              topic_slug: (
                [.[] | .topic_slug] | map(select(. != null and . != "")) | (first // null)
              ),
              raw_hashes: (
                [.[] | (.raw_hashes // [])] | add | unique
              )
            }
        )
      | sort_by(.created_at // "")
    )
  }
'

TEAMMATES=$(jq -r '.teammates[] | @base64' "${CONFIG}" 2>/dev/null || echo "")

if [[ -z "${TEAMMATES}" ]]; then
  echo "[rsync-merge] no teammates listed"
  exit 0
fi

for entry in ${TEAMMATES}; do
  NAME=$(echo "${entry}" | base64 -d | jq -r '.name')
  IP=$(echo "${entry}" | base64 -d | jq -r '.ip')
  USERNAME=$(echo "${entry}" | base64 -d | jq -r '.username // "m1"')

  if [[ -n "${ONLY}" && "${ONLY}" != "${NAME}" ]]; then
    continue
  fi

  echo "[rsync-merge] === ${NAME} (${USERNAME}@${IP}) ==="

  REMOTE_INDEX="${STAGING}/${NAME}.index.json"
  MERGED="${STAGING}/${NAME}.merged.json"

  # 1. Pull remote index
  if ! rsync -az --timeout=30 \
       "${USERNAME}@${IP}:.claude-team/insights/index.json" \
       "${REMOTE_INDEX}" 2>/dev/null; then
    echo "[rsync-merge] ${NAME} unreachable, skipping"
    continue
  fi

  if [[ ! -s "${REMOTE_INDEX}" ]]; then
    echo '{"insights":[]}' > "${REMOTE_INDEX}"
  fi

  # 2. Merge
  if ! jq -s "${JQ_MERGE}" "${INDEX}" "${REMOTE_INDEX}" > "${MERGED}" 2>/dev/null; then
    echo "[rsync-merge] ${NAME} merge failed (malformed json?), skipping"
    continue
  fi

  LOCAL_N=$(jq '.insights | length' "${INDEX}")
  REMOTE_N=$(jq '.insights | length' "${REMOTE_INDEX}")
  MERGED_N=$(jq '.insights | length' "${MERGED}")

  # Idempotency: if no change on either side, skip writes
  LOCAL_HASH=$(shasum -a 256 "${INDEX}" | awk '{print $1}')
  MERGED_HASH=$(shasum -a 256 "${MERGED}" | awk '{print $1}')
  REMOTE_HASH=$(shasum -a 256 "${REMOTE_INDEX}" | awk '{print $1}')

  # 3. Bidirectional raw/ union (content-addressed, safe)
  rsync -az --ignore-existing --timeout=30 \
    "${RAW_DIR}" "${USERNAME}@${IP}:.claude-team/insights/raw/" 2>/dev/null || true
  rsync -az --ignore-existing --timeout=30 \
    "${USERNAME}@${IP}:.claude-team/insights/raw/" "${RAW_DIR}" 2>/dev/null || true

  TS=$(date +%Y%m%d-%H%M%S)

  # 4. Write merged to local (skip if unchanged)
  if [[ "${LOCAL_HASH}" != "${MERGED_HASH}" ]]; then
    cp "${INDEX}" "${INDEX}.bak-merge-${TS}"
    cp "${MERGED}" "${INDEX}"
    echo "[rsync-merge] ${NAME}: local ${LOCAL_N} → ${MERGED_N} (backup: index.json.bak-merge-${TS})"
  else
    echo "[rsync-merge] ${NAME}: local already at ${LOCAL_N}, no change"
  fi

  # 5. Push merged to remote (skip if unchanged)
  if [[ "${REMOTE_HASH}" != "${MERGED_HASH}" ]]; then
    ssh -o ConnectTimeout=10 "${USERNAME}@${IP}" \
      "cp ~/.claude-team/insights/index.json ~/.claude-team/insights/index.json.bak-merge-${TS}" \
      2>/dev/null || true
    if rsync -az --timeout=30 "${MERGED}" \
         "${USERNAME}@${IP}:.claude-team/insights/index.json" 2>/dev/null; then
      echo "[rsync-merge] ${NAME}: remote ${REMOTE_N} → ${MERGED_N}"
    else
      echo "[rsync-merge] ${NAME}: remote push failed"
    fi
  else
    echo "[rsync-merge] ${NAME}: remote already at ${REMOTE_N}, no change"
  fi

  rm -f "${REMOTE_INDEX}" "${MERGED}"
done

echo "[rsync-merge] done"
