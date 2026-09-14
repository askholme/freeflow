#!/usr/bin/env bash
#
# build-local.sh - one-shot build/test helper for the FreeFlow local-transcription PR.
#
# Køres på macOS. Ingen eksterne antagelser udover Xcode Command Line Tools.
# Eksempler:
#   ./build-local.sh help                - vis hjælp
#   ./build-local.sh test                - kør unit tests (hurtigst, ~10s)
#   ./build-local.sh typecheck           - kun syntaks- og typesjek
#   ./build-local.sh app                 - byg app til din egen Mac (hurtig, default)
#   ./build-local.sh app-asr             - byg app + lokal ASR-helper (kræver netværk)
#   ./build-local.sh app-universal       - byg universal binary (arm64 + x86_64)
#   ./build-local.sh clean               - slet build/-mappen

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

log()  { printf '%b==>%b %s\n' "$BLUE" "$NC" "$*"; }
ok()   { printf '%b✓%b %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b!%b %s\n' "$YELLOW" "$NC" "$*" >&2; }
die()  { printf '%b✗%b %s\n' "$RED" "$NC" "$*" >&2; exit 1; }

require_macos() {
  if [[ "$(uname)" != "Darwin" ]]; then
    die "Dette script skal køres på macOS (fundet: $(uname))."
  fi
}

require_toolchain() {
  log "Tjekker Xcode Command Line Tools..."
  if ! command -v swiftc >/dev/null 2>&1; then
    die "swiftc ikke fundet. Installer Xcode CLT: xcode-select --install"
  fi
  if ! command -v xcrun >/dev/null 2>&1; then
    die "xcrun ikke fundet. Installer Xcode Command Line Tools."
  fi
  local sdk
  sdk="$(xcrun --show-sdk-path 2>/dev/null || true)"
  [[ -n "$sdk" ]] || die "macOS SDK ikke fundet via xcrun. Kør 'sudo xcode-select --reset'."
  ok "swiftc $(swiftc --version 2>&1 | head -n1)"
  ok "SDK: $sdk"
}

arch() {
  case "$(uname -m)" in
    arm64) echo arm64 ;;
    x86_64) echo x86_64 ;;
    *) die "Ukendt arkitektur: $(uname -m)" ;;
  esac
}

do_test() {
  require_macos
  require_toolchain
  log "Kører tests via Makefile (make test)..."
  make test
  ok "Alle tests bestået."
}

do_typecheck() {
  require_macos
  require_toolchain
  log "Tjekker typer (make typecheck)..."
  make typecheck
  ok "Typecheck OK."
}

do_app() {
  local include_asr="${1:-0}"
  require_macos
  require_toolchain
  local current_arch
  current_arch="$(arch)"
  local identity="${CODESIGN_IDENTITY:--}"
  if [[ "$identity" == "-" ]]; then
    warn "Bruger ad-hoc codesigning (CODESIGN_IDENTITY=-). Appen kan køre lokalt men kan ikke distribueres."
  fi
  if [[ "$include_asr" == "1" ]]; then
    warn "Bygger med lokal ASR-helper (kræver netværk for at hente pinned dependencies)."
    make ARCH="$current_arch" INCLUDE_LOCAL_ASR=1 CODESIGN_IDENTITY="$identity"
  else
    log "Bygger standard app (uden lokal ASR)..."
    make ARCH="$current_arch" CODESIGN_IDENTITY="$identity"
  fi
  ok "App bygget: build/FreeFlow Dev.app"
  printf '\n'
  log "Åbn med:"
  printf '    open "build/FreeFlow Dev.app"\n'
  printf '\n'
  log "Tip: I appens Settings → Cleanup finder du de to nye toggles"
  log "     'Skip post-processing' og 'Skip context prompt' (uafhængige)."
}

do_app_universal() {
  local include_asr="${1:-0}"
  require_macos
  require_toolchain
  local identity="${CODESIGN_IDENTITY:--}"
  if [[ "$identity" == "-" ]]; then
    warn "Bruger ad-hoc codesigning (CODESIGN_IDENTITY=-)."
  fi
  if [[ "$include_asr" == "1" ]]; then
    warn "Bygger universal binary inkl. lokal ASR-helper..."
    make ARCH=universal INCLUDE_LOCAL_ASR=1 CODESIGN_IDENTITY="$identity"
  else
    log "Bygger universal binary (arm64 + x86_64)..."
    make ARCH=universal CODESIGN_IDENTITY="$identity"
  fi
  ok "Universal app bygget: build/FreeFlow Dev.app"
}

do_clean() {
  log "Sletter build/-mappen..."
  rm -rf build
  ok "Rent."
}

show_help() {
  cat <<EOF
${BLUE}build-local.sh${NC} - byg/test FreeFlow lokalt på macOS

${GREEN}Anvendelse:${NC}
  ./build-local.sh <kommando>

${GREEN}Kommandoer:${NC}
  help            Vis denne hjælp
  test            Kør alle unit tests (~10 sekunder)
  typecheck       Kun syntaks- og typecheck (hurtigst)
  app             Byg app til din Mac (standard, uden lokal ASR)
  app-asr         Byg app + lokal Parakeet ASR-helper (kræver netværk)
  app-universal   Byg universal binary (arm64 + x86_64)
  clean           Slet build/-mappen

${GREEN}Eksempler:${NC}
  ./build-local.sh test              # hurtig verifikation af ændringer
  ./build-local.sh app               # bygger build/FreeFlow Dev.app
  ./build-local.sh app-asr           # bygger app + lokal ASR-helper
  open "build/FreeFlow Dev.app"      # kør den byggede app

${GREEN}Efter bygning:${NC}
  De nye Settings-toggles 'Skip post-processing' og 'Skip context prompt'
  ligger i Settings → Cleanup og virker uafhængigt af hinanden.

${YELLOW}Forudsætninger:${NC}
  - macOS med Xcode Command Line Tools (swiftc, xcrun)
  - For app-asr: netværksadgang første gang (henter pinned dependencies)
  - ~1 GB ledig disk til build + (valgfrit) ASR-model
EOF
}

main() {
  local cmd="${1:-help}"
  case "$cmd" in
    help|--help|-h) show_help ;;
    test) do_test ;;
    typecheck) do_typecheck ;;
    app) do_app 0 ;;
    app-asr) do_app 1 ;;
    app-universal) do_app_universal 0 ;;
    app-universal-asr) do_app_universal 1 ;;
    clean) do_clean ;;
    *) die "Ukendt kommando: $1. Kør './build-local.sh help'." ;;
  esac
}

main "$@"