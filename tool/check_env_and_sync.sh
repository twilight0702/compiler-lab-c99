#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=""
FRONTEND_ONLY=0
SKIP_REPO_CHECK=0

usage() {
  cat <<USAGE
Usage:
  $0 --root <repo_root> [--frontend-only] [--skip-repo-check]
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
    --skip-repo-check)
      SKIP_REPO_CHECK=1
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

ensure_src_layout() {
  local src_root="${ROOT_DIR}/src"
  mkdir -p "${src_root}"

  ensure_one_component() {
    local name="$1"
    local repo_url="$2"
    local src_dir="${src_root}/${name}"
    local legacy_dir="${ROOT_DIR}/${name}"
    local tmp_clone_dir="${src_root}/.__clone_${name}"
    if [[ -d "${src_dir}" ]]; then
      return 0
    fi
    if [[ -d "${legacy_dir}" ]]; then
      mv "${legacy_dir}" "${src_dir}"
      echo "[ok] moved ${name} -> src/${name}"
      return 0
    fi
    rm -rf "${tmp_clone_dir}"
    if git clone -q "${repo_url}" "${tmp_clone_dir}" >/dev/null 2>&1; then
      mv "${tmp_clone_dir}" "${src_dir}"
      echo "[ok] cloned ${name} into src/${name}"
      return 0
    fi
    rm -rf "${tmp_clone_dir}"
    echo "[warn] clone failed (${name}): ${repo_url}"
    return 0
  }

  ensure_one_component "parser_c99_yacc" "https://github.com/twilight0702/c99-yacc-lr-lalr-practice.git"
  ensure_one_component "backend_intermediate_codegen" "https://github.com/LJR-12138/IntermediateCodeGeneration.git"
  ensure_one_component "lexer_seulex" "https://github.com/ZhangYin256/seulex.git"
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

  echo "[info] checking remote updates (${label}: ${branch} <-> ${remote_ref})"
  if ! git -C "${repo_dir}" fetch --prune >/dev/null 2>&1; then
    echo "[warn] fetch failed (${label}), continue with local code"
    return 0
  fi

  local counts ahead behind
  counts=$(git -C "${repo_dir}" rev-list --left-right --count "${branch}...${remote_ref}" 2>/dev/null || echo "0 0")
  ahead=$(awk '{print $1}' <<< "${counts}")
  behind=$(awk '{print $2}' <<< "${counts}")

  if [[ "${behind}" -eq 0 && "${ahead}" -eq 0 ]]; then
    echo "[ok] up to date (${label})"
    return 0
  fi

  if [[ "${behind}" -gt 0 ]]; then
    echo "[warn] remote has updates (${label}): behind=${behind}, ahead=${ahead}"
    local answer=""
    if [[ -t 0 ]]; then
      read -r -p "Update ${label} now with fast-forward pull? [y/N]: " answer
    else
      echo "[warn] non-interactive shell, skip update prompt (${label})"
    fi
    if [[ "${answer}" =~ ^[Yy]$ ]]; then
      if git -C "${repo_dir}" pull --ff-only --no-rebase >/dev/null 2>&1; then
        echo "[ok] pull success (${label})"
      else
        echo "[warn] pull failed (${label}), continue with local code"
      fi
    else
      echo "[info] skipped update (${label})"
    fi
    return 0
  fi

  echo "[info] local branch ahead of upstream (${label}): ahead=${ahead}, behind=${behind}"
}

echo "[info] root: ${ROOT_DIR}"
echo "[info] frontend_only: ${FRONTEND_ONLY}"
echo "[info] skip_repo_check: ${SKIP_REPO_CHECK}"

# Environment checks
require_cmd cmake
require_cmd gcc
require_cmd g++
require_cmd sed
require_cmd git
if [[ "${FRONTEND_ONLY}" -eq 0 ]]; then
  require_cmd mvn
fi

ensure_src_layout

# Repo sync (best effort)
if [[ "${SKIP_REPO_CHECK}" -eq 1 ]]; then
  echo "[info] skip repo sync/check by flag: --skip-repo-check"
else
  try_pull_repo "${ROOT_DIR}" "workspace"
  try_pull_repo "${ROOT_DIR}/src/parser_c99_yacc" "parser_c99_yacc"
  try_pull_repo "${ROOT_DIR}/src/backend_intermediate_codegen" "backend_intermediate_codegen"
  try_pull_repo "${ROOT_DIR}/src/lexer_seulex" "lexer_seulex"
fi
