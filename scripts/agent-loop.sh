#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUDGET="${BUDGET:-5h}"
ITERATIONS="${ITERATIONS:-20}"
PUSH="${PUSH:-0}"
MODEL="${MODEL:-}"
VALIDATE="${VALIDATE:-make format && CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test && CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build && make lint}"

usage() {
  cat <<'USAGE'
Usage: scripts/agent-loop.sh [--iterations 20] [--budget 5h] [--push] [--model MODEL]

Simple full-auto Codex loop in the current repo over the Markdown control files:
  AGENT.md
  seed_plan.md
  TODO.md
  MEMORY.md
  IMPLEMENTATION_CHECK_PLAN.md
  AGENT_LOG.md

Each iteration:
  1. feeds the Markdown files to Codex
  2. asks Codex to implement the next TODO slice
  3. runs validation
  4. commits changed files
  5. optionally pushes

Defaults:
  BUDGET=5h
  ITERATIONS=20
  PUSH=0
  MODEL=
  VALIDATE='make format && ...'

Codex runs with --dangerously-bypass-approvals-and-sandbox, which already disables approvals.
USAGE
}

seconds() {
  case "$1" in
    *h) echo "$((${1%h} * 3600))" ;;
    *m) echo "$((${1%m} * 60))" ;;
    *s) echo "${1%s}" ;;
    *) echo "$1" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --budget) BUDGET="${2:?missing --budget value}"; shift 2 ;;
    --iterations) ITERATIONS="${2:?missing --iterations value}"; shift 2 ;;
    --push) PUSH=1; shift ;;
    --model) MODEL="${2:?missing --model value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

cd "$ROOT"

for file in AGENT.md seed_plan.md TODO.md MEMORY.md IMPLEMENTATION_CHECK_PLAN.md AGENT_LOG.md; do
  [[ -f "$file" ]] || { echo "missing $file" >&2; exit 2; }
done

START="$(date +%s)"
LIMIT="$(seconds "$BUDGET")"
ITERATION=0

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a AGENT_LOG.md
}

log ""
log "autonomous md loop started iterations=${ITERATIONS} budget=${BUDGET} push=${PUSH}"

while true; do
  elapsed=$(($(date +%s) - START))
  [[ "$elapsed" -lt "$LIMIT" ]] || { log "time budget reached elapsed=${elapsed}s"; exit 0; }
  [[ "$ITERATION" -lt "$ITERATIONS" ]] || { log "iteration limit reached iterations=${ITERATION}"; exit 0; }

  ITERATION=$((ITERATION + 1))
  log "iteration ${ITERATION} started"

  prompt="$(mktemp)"
  {
    echo "You are an autonomous full-auto implementation agent."
    echo
    echo "Read the Markdown control files below. TODO.md is the canonical progress tracker."
    echo "Choose the next highest-value implementation slice, implement it, validate it, update TODO.md and AGENT_LOG.md, and commit if successful."
    echo
    echo "Rules:"
    echo "- Use IMPLEMENTATION_CHECK_PLAN.md to prevent architectural drift."
    echo "- Prefer daemon/client-server architecture tasks."
    echo "- Keep the repo buildable."
    echo "- Do not fake tests."
    echo "- Do not ask for approval."
    echo
    for file in AGENT.md seed_plan.md TODO.md MEMORY.md IMPLEMENTATION_CHECK_PLAN.md AGENT_LOG.md; do
      echo
      echo "===== ${file} ====="
      cat "$file"
    done
  } > "$prompt"

  codex_args=(--dangerously-bypass-approvals-and-sandbox)
  [[ -z "$MODEL" ]] || codex_args+=(--model "$MODEL")
  codex_args+=(exec -C "$ROOT")

  if ! codex "${codex_args[@]}" - < "$prompt"; then
    rm -f "$prompt"
    log "iteration ${ITERATION} codex failed"
    exit 1
  fi
  rm -f "$prompt"

  log "iteration ${ITERATION} validation started"
  if ! bash -lc "$VALIDATE"; then
    log "iteration ${ITERATION} validation failed"
    git status --short >> AGENT_LOG.md
    continue
  fi

  if [[ -n "$(git status --short)" ]]; then
    git add -A
    git commit -m "Autonomous iteration ${ITERATION}"
    log "iteration ${ITERATION} committed"
    if [[ "$PUSH" -eq 1 ]]; then
      git push
      log "iteration ${ITERATION} pushed"
    fi
  else
    log "iteration ${ITERATION} no changes"
  fi
done
