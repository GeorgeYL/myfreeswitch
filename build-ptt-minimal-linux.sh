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
BOOTSTRAP_REQS_SHIM_CREATED=0
BOOTSTRAP_REQS_PATH="scripts/ci/build-requirements.sh"

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

check_source_integrity() {
  local missing=0
  local required_files=(
    "acinclude.m4"
    "configure.ac"
    "build/config/sac-pkg-config.m4"
    "build/standalone_module/freeswitch.pc.in"
    "scripts/ci/build-requirements.sh"
    "src/mod/databases/mod_mariadb/Makefile.am"
    "src/mod/databases/mod_pgsql/Makefile.am"
    "src/mod/formats/mod_png/Makefile.am"
    "src/mod/languages/mod_python3/Makefile.am"
  )

  for f in "${required_files[@]}"; do
    if [[ ! -f "$f" ]]; then
      echo "Missing required source file: $f" >&2
      missing=1
    fi
  done

  if [[ "$missing" -ne 0 ]]; then
    echo "Source tree is incomplete; bootstrap/autotools will fail with AM_CONDITIONAL/AC_* macro errors." >&2
    echo "Fix on Linux host:" >&2
    echo "  1) Ensure you are in the correct repository root" >&2
    echo "  2) Restore tracked files: git checkout -- ." >&2
    echo "  3) Sync latest code: git pull --rebase" >&2
    echo "  4) If needed: git submodule update --init --recursive" >&2
    exit 1
  fi
}

check_build_dependencies() {
  if ! command -v pkg-config >/dev/null 2>&1; then
    echo "Missing required tool: pkg-config" >&2
    exit 1
  fi

  if ! pkg-config --exists 'sofia-sip-ua >= 1.13.17'; then
    echo "Missing required dependency: sofia-sip-ua >= 1.13.17" >&2
    echo "Install package by distro, then re-run this script:" >&2
    echo "  Debian/Ubuntu: sudo apt-get install -y libsofia-sip-ua-dev" >&2
    echo "  RHEL/Rocky/Alma/CentOS: sudo dnf install -y sofia-sip-devel" >&2
    echo "  Fedora: sudo dnf install -y sofia-sip-devel" >&2
    echo "  openSUSE: sudo zypper install -y libsofia-sip-ua-devel" >&2
    echo "  Arch: sudo pacman -S --needed sofia-sip" >&2
    exit 1
  fi
}

ensure_bootstrap_requirements() {
  if [[ -f "$BOOTSTRAP_REQS_PATH" ]]; then
    return
  fi

  mkdir -p "$(dirname "$BOOTSTRAP_REQS_PATH")"
  cat > "$BOOTSTRAP_REQS_PATH" <<'EOF'
#!/bin/sh

find_first_tool() {
  for tool in "$@"; do
    if command -v "$tool" >/dev/null 2>&1; then
      command -v "$tool"
      return 0
    fi
  done
  return 1
}

check_ac_ver() {
  AUTOCONF=${AUTOCONF:-autoconf}
  if ! command -v "$AUTOCONF" >/dev/null 2>&1; then
    echo "build-requirements: autoconf not found." >&2
    exit 1
  fi
}

check_am_ver() {
  AUTOMAKE=${AUTOMAKE:-automake}
  if ! command -v "$AUTOMAKE" >/dev/null 2>&1; then
    echo "build-requirements: automake not found." >&2
    exit 1
  fi
}

check_acl_ver() {
  ACLOCAL=${ACLOCAL:-aclocal}
  if ! command -v "$ACLOCAL" >/dev/null 2>&1; then
    echo "build-requirements: aclocal not found." >&2
    exit 1
  fi
}

check_lt_ver() {
  libtool=${LIBTOOL:-$(find_first_tool glibtool libtool libtool22 libtoolize)}
  if [ "x$libtool" = "x" ]; then
    echo "build-requirements: libtool not found." >&2
    exit 1
  fi
  lt_pversion=`$libtool --version 2>/dev/null | sed -e 's/([^)]*)//g;s/^[^0-9]*//;s/[- ].*//g;q'`
  if [ -z "$lt_pversion" ]; then
    echo "build-requirements: unable to determine libtool version." >&2
    exit 1
  fi
  lt_version=`echo $lt_pversion | sed -e 's/\([a-z]*\)$/\.\1/'`
  IFS=.; set $lt_version; IFS=' '
  if [ -z "$1" ]; then
    lt_major=0
  else
    lt_major=$1
  fi
}

check_libtoolize() {
  if [ -n "${LIBTOOLIZE:-}" ]; then
    libtoolize="$LIBTOOLIZE"
  else
    libtoolize=$(find_first_tool glibtoolize libtoolize libtoolize22 libtoolize15 libtoolize14)
  fi
  if [ "x$libtoolize" = "x" ] || [ ! -x "$libtoolize" ]; then
    echo "build-requirements: libtoolize not found." >&2
    exit 1
  fi
}

check_make() {
  make=$(find_first_tool make gmake)
  if [ "x$make" = "x" ]; then
    echo "build-requirements: GNU make not found." >&2
    exit 1
  fi
  make_version=`$make --version 2>/dev/null | head -1`
}

check_awk() {
  awk=${AWK:-awk}
  if ! command -v "$awk" >/dev/null 2>&1; then
    echo "build-requirements: awk not found." >&2
    exit 1
  fi
  awk_version=`$awk -W version 2>/dev/null | head -1`
}
EOF
  chmod +x "$BOOTSTRAP_REQS_PATH"
  BOOTSTRAP_REQS_SHIM_CREATED=1
  echo "Generated compatibility shim: $BOOTSTRAP_REQS_PATH"
}

ORIG_MODULES_BACKUP="modules.conf.bak.ptt.$(date +%Y%m%d%H%M%S)"
HAD_ORIG_MODULES=0
if [[ -f modules.conf ]]; then
  cp modules.conf "$ORIG_MODULES_BACKUP"
  HAD_ORIG_MODULES=1
  echo "Backed up existing modules.conf -> $ORIG_MODULES_BACKUP"
fi

cleanup() {
  if [[ "$BOOTSTRAP_REQS_SHIM_CREATED" -eq 1 ]]; then
    rm -f "$BOOTSTRAP_REQS_PATH"
    rmdir --ignore-fail-on-non-empty "$(dirname "$BOOTSTRAP_REQS_PATH")" 2>/dev/null || true
    echo "Removed generated bootstrap requirements shim"
  fi

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

# mod_spandsp is not part of the Windows-aligned minimal set. Remove it
# defensively so configure does not hard-require spandsp >= 3.0.
sed -i '/^[[:space:]]*applications\/mod_spandsp[[:space:]]*$/d' modules.conf

check_source_integrity
ensure_bootstrap_requirements
check_build_dependencies

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
FS_REQUIRE_SPANDSP=no ./configure --prefix="$PREFIX" $EXTRA_CONFIGURE_ARGS

echo "==> make"
make -j"$JOBS"

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
  echo "==> make install"
  make install
fi

echo "Build finished successfully."
