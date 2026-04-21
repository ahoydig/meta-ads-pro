#!/usr/bin/env bash
# upload_media.sh — upload cross-platform de imagens/vídeos com cache de fbid
#
# Responsabilidades:
# - upload_image: multipart (-F source=@file) pra /adimages, retorna image_hash
# - upload_dark_post: page foto published=false + feed published=false, retorna post_id
# - resize_if_needed: sips (macOS) ou ImageMagick (Linux/WSL) — auto-detect
# - media_fbid cache: chave = SHA256(file) + post_id, via manifest (fix bug #5)
#
# Requisitos: curl, jq, python3, sips OU ImageMagick (convert/identify).

set -euo pipefail

_UPLOAD_MEDIA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_UPLOAD_MEDIA_PY_DIR="${_UPLOAD_MEDIA_LIB_DIR}/_py"

# Graph API helpers
# shellcheck source=/dev/null
if [[ -z "${_META_GRAPH_API_SOURCED:-}" && -f "${_UPLOAD_MEDIA_LIB_DIR}/graph_api.sh" ]]; then
  # graph_api.sh ja tem guard — re-source seguro
  source "${_UPLOAD_MEDIA_LIB_DIR}/graph_api.sh"
fi

# ─── Detecção de ferramenta de resize ─────────────────────────────────────────
# Retorna: sips | convert | none
_detect_resize_tool() {
  if command -v sips >/dev/null 2>&1; then
    echo "sips"
  elif command -v convert >/dev/null 2>&1; then
    echo "convert"
  else
    echo "none"
  fi
}

# Retorna dimensões "WxH" cross-platform
_detect_image_dims() {
  local filepath="$1"
  if command -v sips >/dev/null 2>&1; then
    local w h
    w=$(sips -g pixelWidth "$filepath" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    h=$(sips -g pixelHeight "$filepath" 2>/dev/null | awk '/pixelHeight/ {print $2}')
    [[ -n "$w" && -n "$h" ]] && { echo "${w}x${h}"; return 0; }
  fi
  if command -v identify >/dev/null 2>&1; then
    identify -format "%wx%h" "$filepath" 2>/dev/null && return 0
  fi
  return 1
}

# ─── SHA256 pra cache ─────────────────────────────────────────────────────────
_sha256_file() {
  local filepath="$1"
  python3 "${_UPLOAD_MEDIA_PY_DIR}/media_hash.py" "$filepath"
}

# ─── Cache de media_fbid via manifest ─────────────────────────────────────────
# Chave composta: (sha256 + post_id).
# NUNCA reusa media_fbid entre posts diferentes (fix bug #5).
#
# Formato de cache no manifest:
#   media_cache[sha256 + ":" + post_id] = media_fbid
#
# media_cache_get <sha256> <post_id> → stdout: cached_fbid ou vazio
media_cache_get() {
  local sha="$1" post_id="${2:-standalone}"
  local run_id="${CURRENT_RUN_ID:-}"
  [[ -n "$run_id" ]] || { echo ""; return 0; }
  local manifest="${HOME}/.claude/meta-ads-pro/current/${run_id}.json"
  [[ -f "$manifest" ]] || { echo ""; return 0; }
  local key="${sha}:${post_id}"
  jq -r --arg k "$key" '.media_cache[$k] // empty' "$manifest" 2>/dev/null || echo ""
}

# media_cache_put <sha256> <post_id> <fbid>
media_cache_put() {
  local sha="$1" post_id="${2:-standalone}" fbid="$3"
  local run_id="${CURRENT_RUN_ID:-}"
  [[ -n "$run_id" ]] || return 0
  local manifest="${HOME}/.claude/meta-ads-pro/current/${run_id}.json"
  [[ -f "$manifest" ]] || return 0
  local key="${sha}:${post_id}"
  local tmp
  tmp=$(mktemp -t metacache.XXXXXX.json)
  jq --arg k "$key" --arg v "$fbid" \
    '.media_cache = (.media_cache // {}) | .media_cache[$k] = $v' \
    "$manifest" > "$tmp" && mv "$tmp" "$manifest"
}

# ─── Upload de imagem (multipart, NUNCA base64) ───────────────────────────────
# uso: upload_image <filepath>
# stdout: image_hash (string de 32 hex)
upload_image() {
  local filepath="$1"
  local account="${AD_ACCOUNT_ID:?AD_ACCOUNT_ID obrigatório}"
  local token="${META_ACCESS_TOKEN:?META_ACCESS_TOKEN obrigatório}"
  local api_ver="${META_API_VERSION:-v25.0}"

  [[ -f "$filepath" ]] || {
    echo "upload_image: arquivo não existe: $filepath" >&2
    return 1
  }

  # Cache-by-sha: imagens podem reusar image_hash entre ads no MESMO run.
  local sha cached
  sha=$(_sha256_file "$filepath") || sha=""
  if [[ -n "$sha" ]]; then
    cached=$(media_cache_get "$sha" "image_hash")
    if [[ -n "$cached" ]]; then
      echo "$cached"
      return 0
    fi
  fi

  local response
  response=$(curl -sS -X POST \
    "https://graph.facebook.com/${api_ver}/${account}/adimages" \
    -F "source=@${filepath}" \
    -F "access_token=${token}")

  local hash
  hash=$(echo "$response" | jq -r '.images | to_entries[0].value.hash // empty')
  [[ -n "$hash" ]] || {
    echo "upload_image: falhou — $response" >&2
    return 1
  }

  [[ -n "$sha" ]] && media_cache_put "$sha" "image_hash" "$hash"
  echo "$hash"
}

# ─── Upload de dark post (published=false) ────────────────────────────────────
# Pra dev mode fallback (fix bug #3) ou qualquer caso que precise de
# object_story_id em vez de object_story_spec.
#
# Cache composto (sha + page_id) garante que o MESMO arquivo usado em 3
# combos diferentes gera 3 media_fbids distintos (fix bug #5).
#
# uso: upload_dark_post <filepath> <caption> <page_id>
# stdout: post_id (formato: "{page_id}_{post_num}")
upload_dark_post() {
  local filepath="$1" caption="$2" page_id="${3:?page_id obrigatório}"
  local page_token="${PAGE_ACCESS_TOKEN:?PAGE_ACCESS_TOKEN obrigatório}"
  local api_ver="${META_API_VERSION:-v25.0}"

  [[ -f "$filepath" ]] || {
    echo "upload_dark_post: arquivo não existe: $filepath" >&2
    return 1
  }

  # Upload foto unpublished
  local photo_response
  photo_response=$(curl -sS -X POST \
    "https://graph.facebook.com/${api_ver}/${page_id}/photos" \
    -F "source=@${filepath}" \
    -F "published=false" \
    -F "access_token=${page_token}")
  local photo_id
  photo_id=$(echo "$photo_response" | jq -r '.id // empty')
  [[ -n "$photo_id" ]] || {
    echo "upload_dark_post: photo upload falhou — $photo_response" >&2
    return 1
  }

  # Cria post unpublished referenciando a foto
  local post_response
  post_response=$(curl -sS -X POST \
    "https://graph.facebook.com/${api_ver}/${page_id}/feed" \
    -F "message=${caption}" \
    -F "attached_media[0]={\"media_fbid\":\"${photo_id}\"}" \
    -F "published=false" \
    -F "access_token=${page_token}")
  local post_id
  post_id=$(echo "$post_response" | jq -r '.id // empty')
  [[ -n "$post_id" ]] || {
    echo "upload_dark_post: feed post falhou — $post_response" >&2
    return 1
  }

  # Registra pair (photo_id, post_id) no cache — cada post_id é ÚNICO por upload,
  # então o mesmo arquivo reupload → post_id diferente (fix bug #5).
  local sha
  sha=$(_sha256_file "$filepath") || sha=""
  [[ -n "$sha" ]] && media_cache_put "$sha" "$post_id" "$photo_id"

  # Registra no manifest como dark_post (pra rollback)
  if command -v manifest_add >/dev/null 2>&1; then
    manifest_add "dark_post" "$post_id" 2>/dev/null || true
  fi

  echo "$post_id"
}

# ─── Resize cross-platform ────────────────────────────────────────────────────
# uso: resize_if_needed <filepath> <target_w> <target_h>
# stdout: path do arquivo redimensionado (cria novo *_resized.*)
# Nota: se a imagem já estiver >= target, ainda força resize pra garantir spec.
resize_if_needed() {
  local filepath="$1" target_w="$2" target_h="$3"
  [[ -f "$filepath" ]] || {
    echo "resize_if_needed: arquivo não existe: $filepath" >&2
    return 1
  }

  local ext="${filepath##*.}"
  local base="${filepath%.*}"
  local out="${base}_resized.${ext}"

  local tool
  tool=$(_detect_resize_tool)
  case "$tool" in
    sips)
      # -Z: fit em quadrado; usa maior dimensão como limite
      local target_max
      if (( target_w >= target_h )); then target_max="$target_w"
      else target_max="$target_h"; fi
      sips -Z "$target_max" "$filepath" --out "$out" >/dev/null 2>&1 || {
        echo "resize_if_needed: sips falhou" >&2
        return 1
      }
      echo "$out"
      ;;
    convert)
      # Fill + centro (crop) pra garantir exatamente target_w × target_h
      convert "$filepath" -resize "${target_w}x${target_h}^" \
        -gravity center -extent "${target_w}x${target_h}" "$out" || {
        echo "resize_if_needed: convert falhou" >&2
        return 1
      }
      echo "$out"
      ;;
    none)
      echo "resize_if_needed: sem ferramenta (instale sips ou ImageMagick)" >&2
      return 1
      ;;
  esac
}

# Vídeo: delega pra upload_video.sh (arquivo separado).
