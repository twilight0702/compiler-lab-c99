#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=""
FRONTEND_ONLY=0

usage() {
  cat <<USAGE
Usage:
  $0 --root <repo_root> [--frontend-only]
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

try_pull_repo() {
  local repo_dir="$1"
  local label="$2"
  if [[ ! -d "${repo_dir}/.git" ]]; then
    echo "[warn] skip pull (${label}): not a git repo"
    return 0
  fi
  local branch
  branch=$(git -C "${repo_dir}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  local remote_ref
  remote_ref=$(git -C "${repo_dir}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [[ -z "${remote_ref}" ]]; then
    echo "[warn] skip pull (${label}): no upstream set for branch '${branch:-unknown}'"
    return 0
  fi
  echo "[info] pulling ${label} (${branch} <- ${remote_ref})"
  if git -C "${repo_dir}" pull --ff-only --no-rebase >/dev/null 2>&1; then
    echo "[ok] pull success (${label})"
  else
    echo "[warn] pull failed (${label}), continue with local code"
  fi
}

echo "[info] root: ${ROOT_DIR}"
echo "[info] frontend_only: ${FRONTEND_ONLY}"

# Environment checks
require_cmd cmake
require_cmd gcc
require_cmd g++
require_cmd sed
require_cmd git
if [[ "${FRONTEND_ONLY}" -eq 0 ]]; then
  require_cmd mvn
fi

# Repo sync (best effort)
try_pull_repo "${ROOT_DIR}" "workspace"
try_pull_repo "${ROOT_DIR}/src/parser_c99_yacc" "parser_c99_yacc"
try_pull_repo "${ROOT_DIR}/src/backend_intermediate_codegen" "backend_intermediate_codegen"
try_pull_repo "${ROOT_DIR}/src/lexer_seulex" "lexer_seulex"
