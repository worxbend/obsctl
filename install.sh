#!/bin/sh
# obsctl installer.
#
#   curl -fsSL https://worxbend.github.io/obsctl/install.sh | sh
#
# Downloads the published static binary for this machine, checks it against the
# release's SHA256SUMS.txt, and installs it. Nothing is installed if the
# checksum does not match.
#
# Options (pass through sh -s -- when piping: `... | sh -s -- --dir /usr/local/bin`):
#   --version VERSION   Release tag to install, e.g. v0.5.0 (default: latest)
#   --dir DIR           Where to put the binary (default: ~/.local/bin, or
#                       /usr/local/bin when running as root)
#   --help              Print this help
#
# The same values can come from the environment as OBSCTL_VERSION and
# OBSCTL_INSTALL_DIR; an explicit flag wins.

set -eu

REPO="worxbend/obsctl"
RELEASES="https://github.com/${REPO}/releases"

version="${OBSCTL_VERSION:-latest}"
install_dir="${OBSCTL_INSTALL_DIR:-}"

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'obsctl install: %s\n' "$*" >&2
  exit 1
}

# Printed rather than read out of this file, because piping into sh leaves no
# file to read.
usage() {
  cat <<'USAGE'
obsctl installer

  curl -fsSL https://worxbend.github.io/obsctl/install.sh | sh

Options (after `sh -s --` when piping):
  --version VERSION   Release tag to install, e.g. v0.5.0 (default: latest)
  --dir DIR           Where to put the binary (default: ~/.local/bin, or
                      /usr/local/bin when running as root)
  --help              Print this help

Environment: OBSCTL_VERSION, OBSCTL_INSTALL_DIR. An explicit flag wins.
USAGE
  exit 0
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || die "--version needs a value"
      version="$2"
      shift 2
      ;;
    --version=*)
      version="${1#--version=}"
      shift
      ;;
    --dir)
      [ "$#" -ge 2 ] || die "--dir needs a value"
      install_dir="$2"
      shift 2
      ;;
    --dir=*)
      install_dir="${1#--dir=}"
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      die "unknown option: $1 (try --help)"
      ;;
  esac
done

# Releases are Linux-only static builds; say so plainly rather than downloading
# something that cannot run here.
os="$(uname -s)"
[ "$os" = "Linux" ] || die "no published binary for ${os}; build from source: https://github.com/${REPO}#-quick-start"

machine="$(uname -m)"
case "$machine" in
  x86_64 | amd64) target="linux-amd64" ;;
  aarch64 | arm64) target="linux-arm64" ;;
  *) die "no published binary for ${machine}; build from source: https://github.com/${REPO}#-quick-start" ;;
esac

if command -v curl >/dev/null 2>&1; then
  fetcher="curl"
elif command -v wget >/dev/null 2>&1; then
  fetcher="wget"
else
  die "curl or wget is required"
fi

# Held as a command line rather than a name: `shasum` defaults to SHA-1 and
# would reject a SHA-256 sums file without the flag.
if command -v sha256sum >/dev/null 2>&1; then
  checker="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  checker="shasum -a 256"
else
  die "sha256sum or shasum is required to verify the download"
fi

# Writes a URL to a file, failing on any HTTP error rather than saving the
# error page.
download() {
  if [ "$fetcher" = "curl" ]; then
    curl -fsSL "$1" -o "$2"
  else
    wget -qO "$2" "$1"
  fi
}

# The archive name carries the version, so `releases/latest/download/...`
# cannot be used blind: resolve the tag first. The redirect from
# `releases/latest` costs no API quota; the API is the fallback for wget.
resolve_latest() {
  if [ "$fetcher" = "curl" ]; then
    resolved="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${RELEASES}/latest")"
    resolved="${resolved##*/}"
  else
    resolved="$(wget -qO- "https://api.github.com/repos/${REPO}/releases/latest" |
      sed -n 's/.*"tag_name" *: *"\([^"]*\)".*/\1/p' | head -n 1)"
  fi
  [ -n "$resolved" ] || die "could not determine the latest release"
  printf '%s' "$resolved"
}

if [ "$version" = "latest" ]; then
  version="$(resolve_latest)"
fi
case "$version" in
  v*) ;;
  *) version="v${version}" ;;
esac

if [ -z "$install_dir" ]; then
  if [ "$(id -u)" = "0" ]; then
    install_dir="/usr/local/bin"
  else
    install_dir="${HOME}/.local/bin"
  fi
fi

archive="obsctl-${version}-${target}.tar.gz"
base="${RELEASES}/download/${version}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM

log "obsctl ${version} (${target})"
download "${base}/${archive}" "${work}/${archive}" ||
  die "could not download ${base}/${archive}"
download "${base}/SHA256SUMS.txt" "${work}/SHA256SUMS.txt" ||
  die "could not download the checksum file"

# Only the line for this archive, so a sums file listing other targets does not
# fail the check for files that were never downloaded.
grep " ${archive}\$" "${work}/SHA256SUMS.txt" > "${work}/expected.txt" ||
  die "${archive} is not listed in SHA256SUMS.txt"

# Unquoted on purpose: `$checker` may carry its algorithm flag.
# shellcheck disable=SC2086
(cd "$work" && $checker -c expected.txt >/dev/null 2>&1) ||
  die "checksum mismatch for ${archive}; nothing was installed"

tar -xzf "${work}/${archive}" -C "$work" || die "could not unpack ${archive}"
[ -f "${work}/obsctl" ] || die "${archive} did not contain an obsctl binary"
chmod 755 "${work}/obsctl"

# Run it before it is installed, so a binary that cannot execute here never
# replaces a working one.
reported="$("${work}/obsctl" --version)" || die "the downloaded binary did not run on this machine"

mkdir -p "$install_dir" || die "could not create ${install_dir}"
if [ ! -w "$install_dir" ]; then
  die "${install_dir} is not writable; rerun with --dir DIR, or with sudo"
fi

# Written beside the target and moved into place so an interrupted install
# cannot leave a half-written binary where a working one used to be.
cp "${work}/obsctl" "${install_dir}/obsctl.new"
chmod 755 "${install_dir}/obsctl.new"
mv -f "${install_dir}/obsctl.new" "${install_dir}/obsctl"

log "installed ${reported} to ${install_dir}/obsctl"

case ":${PATH}:" in
  *":${install_dir}:"*) ;;
  *)
    log ""
    log "${install_dir} is not on your PATH. Add it:"
    log "  export PATH=\"${install_dir}:\${PATH}\""
    ;;
esac

log ""
log "Next: obsctl init && obsctl validate-config"
