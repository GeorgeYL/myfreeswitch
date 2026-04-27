#!/usr/bin/env bash
set -euo pipefail

# Build FreeSWITCH with a minimal Linux module set aligned to Freeswitch.PTT.Minimal.2017.slnf
# Example:
#   ./build-ptt-minimal-linux.sh
#   ./build-ptt-minimal-linux.sh --prefix /usr/local/freeswitch --jobs 8
#   ./build-ptt-minimal-linux.sh --skip-install

PREFIX="/usr/local/freeswitch"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
SKIP_INSTALL=0
KEEP_MODULES_CONF=0
EXTRA_CONFIGURE_ARGS=""

usage() {
  cat <<'EOF'
Usage: build-ptt-minimal-linux.sh [options]

Options:
  --prefix <path>          Install prefix (default: /usr/local/freeswitch)
  --jobs <n>               Parallel build jobs (default: CPU cores)
  --skip-install           Build only, do not run make install
  --keep-modules-conf      Keep generated modules.conf after build (no restore)
  --configure-args "..."   Extra args passed to ./configure
  -h, --help               Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="$2"
      shift 2
      ;;
    --jobs)
      JOBS="$2"
      shift 2
      ;;
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    --keep-modules-conf)
      KEEP_MODULES_CONF=1
      shift
      ;;
    --configure-args)
      EXTRA_CONFIGURE_ARGS="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -f "configure.ac" || ! -f "bootstrap.sh" ]]; then
  echo "Run this script from the FreeSWITCH repository root." >&2
  exit 1
fi

if [[ ! -f "build/modules.conf.ptt.minimal" ]]; then
  echo "Missing build/modules.conf.ptt.minimal" >&2
  exit 1
fi

if [[ ! -f "scripts/ci/build-requirements.sh" ]]; then
  echo "Missing scripts/ci/build-requirements.sh" >&2
  echo "Your source tree looks incomplete. Re-sync the repository before building." >&2
  exit 1
fi

ORIG_MODULES_BACKUP="modules.conf.bak.ptt.$(date +%Y%m%d%H%M%S)"
HAD_ORIG_MODULES=0
if [[ -f modules.conf ]]; then
  cp modules.conf "$ORIG_MODULES_BACKUP"
  HAD_ORIG_MODULES=1
  echo "Backed up existing modules.conf -> $ORIG_MODULES_BACKUP"
fi

cleanup() {
  if [[ "$KEEP_MODULES_CONF" -eq 1 ]]; then
    echo "Keeping generated modules.conf as requested (--keep-modules-conf)."
    return
  fi

  if [[ "$HAD_ORIG_MODULES" -eq 1 ]]; then
    mv -f "$ORIG_MODULES_BACKUP" modules.conf
    echo "Restored original modules.conf"
  else
    rm -f modules.conf
    echo "Removed generated modules.conf"
  fi
}

trap cleanup EXIT

cp build/modules.conf.ptt.minimal modules.conf
echo "Loaded Windows-aligned minimal modules list from build/modules.conf.ptt.minimal"

if [[ -d "src/mod/applications/mod_audio_fork" ]]; then
  if ! grep -q '^applications/mod_audio_fork$' modules.conf; then
    echo "applications/mod_audio_fork" >> modules.conf
  fi
  echo "Detected src/mod/applications/mod_audio_fork; enabled in modules.conf"
else
  echo "mod_audio_fork source not found at src/mod/applications/mod_audio_fork; continuing without it"
fi

echo "==> bootstrap"
# Run bootstrap serially for stability. Parallel bootstrap (-j) can intermittently
# produce incomplete autotools metadata on some environments.
./bootstrap.sh -v

# Avoid stale configure cache poisoning when flags/environment changed between runs.
rm -f config.cache

echo "==> configure"
# shellcheck disable=SC2086
./configure --prefix="$PREFIX" $EXTRA_CONFIGURE_ARGS

echo "==> make"
make -j"$JOBS"

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
  echo "==> make install"
  make install
fi

echo "Build finished successfully."
