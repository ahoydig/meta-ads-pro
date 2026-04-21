#!/usr/bin/env bash
# upload_video.sh — 3 estratégias conforme tamanho do arquivo
#
#   ≤100MB  → direct upload (multipart -F source=@file)
#   >100MB  → resumable (start/transfer/finish, chunks)
#   >200MB  → resumable + sleep 30s entre chunks (rate limit cputime)
#
# Todos os modos fazem polling de status=ready (timeout 2min) após upload.
#
# Baseado no learning feedback_meta_ads_upload_video (MEMORY.md):
# erro 17 = cputime rate limit em uploads pesados.

set -euo pipefail

# ─── Tamanho cross-platform ───────────────────────────────────────────────────
# macOS: stat -f%z ; Linux: stat -c%s
_file_size() {
  stat -f%z "$1" 2>/dev/null || stat -c%s "$1"
}

# ─── upload_video <filepath> [title] → stdout: video_id ──────────────────────
upload_video() {
  local filepath="$1"
  local title="${2:-video}"
  local account="${AD_ACCOUNT_ID:?AD_ACCOUNT_ID obrigatório}"
  local token="${META_ACCESS_TOKEN:?META_ACCESS_TOKEN obrigatório}"
  local api_ver="${META_API_VERSION:-v25.0}"
  local api="https://graph.facebook.com/${api_ver}"

  [[ -f "$filepath" ]] || {
    echo "upload_video: arquivo não existe: $filepath" >&2
    return 1
  }

  local size_bytes size_mb
  size_bytes=$(_file_size "$filepath")
  size_mb=$(( size_bytes / 1024 / 1024 ))

  echo "⚙ upload_video: ${size_mb}MB — $filepath" >&2

  if (( size_mb <= 100 )); then
    _upload_video_direct "$filepath" "$title" "$account" "$token" "$api"
  else
    _upload_video_resumable "$filepath" "$title" \
      "$size_bytes" "$size_mb" "$account" "$token" "$api"
  fi
}

# ─── Estratégia 1: direct (≤100MB) ────────────────────────────────────────────
_upload_video_direct() {
  local filepath="$1" title="$2" account="$3" token="$4" api="$5"
  local response
  response=$(curl -sS -X POST "${api}/${account}/advideos" \
    -F "source=@${filepath}" \
    -F "title=${title}" \
    -F "access_token=${token}")
  local video_id
  video_id=$(echo "$response" | jq -r '.id // empty')
  [[ -n "$video_id" ]] || {
    echo "upload_video direct: falhou — $response" >&2
    return 1
  }
  _poll_video_ready "$video_id" "$token" "$api"
  echo "$video_id"
}

# ─── Estratégia 2+3: resumable (>100MB), sleep 30s se >200MB ──────────────────
_upload_video_resumable() {
  local filepath="$1" title="$2" size_bytes="$3" size_mb="$4"
  local account="$5" token="$6" api="$7"

  # Fase 1 — Start
  local start_response upload_session_id video_id start_offset end_offset
  start_response=$(curl -sS -X POST "${api}/${account}/advideos" \
    -F "upload_phase=start" \
    -F "file_size=${size_bytes}" \
    -F "access_token=${token}")
  upload_session_id=$(echo "$start_response" | jq -r '.upload_session_id // empty')
  video_id=$(echo "$start_response" | jq -r '.video_id // empty')
  start_offset=$(echo "$start_response" | jq -r '.start_offset')
  end_offset=$(echo "$start_response" | jq -r '.end_offset')

  [[ -n "$upload_session_id" && -n "$video_id" ]] || {
    echo "upload_video resumable start falhou — $start_response" >&2
    return 1
  }

  # Fase 2 — Transfer (loop até start_offset == size_bytes)
  local chunk_file transfer_response
  chunk_file=$(mktemp -t metavideo.XXXXXX.bin)
  # shellcheck disable=SC2064
  trap "rm -f \"$chunk_file\"" RETURN

  while (( start_offset < size_bytes )); do
    local chunk_size=$(( end_offset - start_offset ))
    # Extrai chunk via python (mais rápido que dd bs=1 e portable)
    python3 - "$filepath" "$chunk_file" "$start_offset" "$chunk_size" <<'PYEOF'
import sys
src, dst, offset, size = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
with open(src, "rb") as f:
    f.seek(offset)
    data = f.read(size)
with open(dst, "wb") as f:
    f.write(data)
PYEOF

    transfer_response=$(curl -sS -X POST "${api}/${account}/advideos" \
      -F "upload_phase=transfer" \
      -F "upload_session_id=${upload_session_id}" \
      -F "start_offset=${start_offset}" \
      -F "video_file_chunk=@${chunk_file}" \
      -F "access_token=${token}")

    local new_start new_end
    new_start=$(echo "$transfer_response" | jq -r '.start_offset // empty')
    new_end=$(echo "$transfer_response" | jq -r '.end_offset // empty')

    [[ -n "$new_start" ]] || {
      echo "upload_video transfer falhou — $transfer_response" >&2
      return 1
    }

    start_offset="$new_start"
    end_offset="$new_end"

    local pct=$(( start_offset * 100 / size_bytes ))
    echo "  ⚙ transfer ${start_offset}/${size_bytes} (${pct}%)" >&2

    # Se >200MB, sleep 30s entre chunks pra evitar cputime rate limit (erro 17)
    if (( size_mb > 200 )) && (( start_offset < size_bytes )); then
      sleep 30
    fi
  done

  # Fase 3 — Finish
  local finish_response
  finish_response=$(curl -sS -X POST "${api}/${account}/advideos" \
    -F "upload_phase=finish" \
    -F "upload_session_id=${upload_session_id}" \
    -F "title=${title}" \
    -F "access_token=${token}")
  local ok
  ok=$(echo "$finish_response" | jq -r '.success // empty')
  [[ "$ok" == "true" ]] || {
    echo "upload_video finish falhou — $finish_response" >&2
    return 1
  }

  _poll_video_ready "$video_id" "$token" "$api"
  echo "$video_id"
}

# ─── Polling até status=ready (máx 2min = 24 × 5s) ────────────────────────────
_poll_video_ready() {
  local video_id="$1" token="$2" api="$3"
  local max_polls="${META_ADS_VIDEO_POLL_MAX:-24}"
  local interval="${META_ADS_VIDEO_POLL_INTERVAL:-5}"
  local i=0 status
  while (( i < max_polls )); do
    status=$(curl -sS \
      "${api}/${video_id}?fields=status&access_token=${token}" \
      | jq -r '.status.video_status // "processing"')
    if [[ "$status" == "ready" ]]; then
      echo "  ✓ vídeo pronto (${video_id})" >&2
      return 0
    fi
    if [[ "$status" == "error" ]]; then
      echo "⚠ vídeo ${video_id} em status=error" >&2
      return 1
    fi
    sleep "$interval"
    ((i++))
  done
  echo "⚠ upload_video: polling timeout 2min — vídeo pode estar processando" >&2
  return 0
}
