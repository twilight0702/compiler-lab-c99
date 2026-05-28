#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=""
FRONTEND_ONLY=0
SKIP_SUBMODULE_CHECK=0

usage() {
  cat <<USAGE
Usage:
  $0 --root <repo_root> [--frontend-only] [--skip-submodule-check]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      shift
      ROOT_DIR="${1:-}"
      ;;
    --frontend-only)
      FRONTEND_ONLY=1
      ;;
    --skip-submodule-check|--skip-repo-check)
      SKIP_SUBMODULE_CHECK=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

if [[ -z "${ROOT_DIR}" || ! -d "${ROOT_DIR}" ]]; then
  echo "[error] invalid root dir: ${ROOT_DIR}" >&2
  exit 2
fi

require_cmd() {
  local c="$1"
  if command -v "$c" >/dev/null 2>&1; then
    echo "[ok] found command: $c"
  else
    echo "[error] missing required command: $c" >&2
    return 1
  fi
}

ensure_submodule_path() {
  local path="$1"
  local label="$2"
  if [[ ! -d "${ROOT_DIR}/${path}" ]]; then
    echo "[error] missing submodule directory (${label}): ${ROOT_DIR}/${path}" >&2
    return 1
  fi
  if ! git -C "${ROOT_DIR}/${path}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[error] invalid submodule checkout (${label}): ${ROOT_DIR}/${path}" >&2
    return 1
  fi
  echo "[ok] submodule ready (${label})"
}

sync_submodules() {
  if [[ ! -f "${ROOT_DIR}/.gitmodules" ]]; then
    echo "[error] .gitmodules not found at root: ${ROOT_DIR}" >&2
    return 1
  fi
  echo "[info] syncing submodule metadata"
  git -C "${ROOT_DIR}" submodule sync --recursive
  echo "[info] initializing/updating submodules"
  git -C "${ROOT_DIR}" submodule update --init --recursive
}

echo "[info] root: ${ROOT_DIR}"
echo "[info] frontend_only: ${FRONTEND_ONLY}"
echo "[info] skip_submodule_check: ${SKIP_SUBMODULE_CHECK}"

# Environment checks
require_cmd cmake
require_cmd gcc
require_cmd g++
require_cmd sed
require_cmd git
if [[ "${FRONTEND_ONLY}" -eq 0 ]]; then
  require_cmd mvn
fi

# Submodule sync/check
if [[ "${SKIP_SUBMODULE_CHECK}" -eq 1 ]]; then
  echo "[info] skip submodule sync/check by flag: --skip-submodule-check"
else
  sync_submodules
fi

ensure_submodule_path "src/parser_c99_yacc" "parser_c99_yacc"
ensure_submodule_path "src/backend_intermediate_codegen" "backend_intermediate_codegen"
ensure_submodule_path "src/lexer_seulex" "lexer_seulex"
