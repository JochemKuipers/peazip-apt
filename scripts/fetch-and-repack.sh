#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT_DIR:-${ROOT}/out}"
WORKDIR="${WORKDIR:-${ROOT}/.work}"
UPSTREAM_REPO="${UPSTREAM_REPO:-peazip/PeaZip}"
UPSTREAM_TAG="${UPSTREAM_TAG:-}"

mkdir -p "${OUT}" "${WORKDIR}"
rm -rf "${OUT:?}"/* "${WORKDIR:?}"/*

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need gh
need sha256sum
need dpkg-deb

if [[ -z "${UPSTREAM_TAG}" ]]; then
  UPSTREAM_TAG="$(gh release view -R "${UPSTREAM_REPO}" --json tagName -q .tagName)"
fi

echo "Upstream tag: ${UPSTREAM_TAG}"

download_dir="${WORKDIR}/download"
mkdir -p "${download_dir}"

gh release download -R "${UPSTREAM_REPO}" "${UPSTREAM_TAG}" \
  --pattern 'peazip_*LINUX.Qt6*_amd64.deb' \
  --pattern 'peazip_*LINUX.GTK2*_amd64.deb' \
  --pattern 'SHA256.txt' \
  -D "${download_dir}" --clobber

shopt -s nullglob
qt_debs=("${download_dir}"/peazip_*LINUX.Qt6*_amd64.deb)
gtk_debs=("${download_dir}"/peazip_*LINUX.GTK2*_amd64.deb)

if (( ${#qt_debs[@]} != 1 )); then
  echo "expected exactly one Qt6 amd64 deb, found ${#qt_debs[@]}" >&2
  ls -la "${download_dir}" >&2 || true
  exit 1
fi
if (( ${#gtk_debs[@]} != 1 )); then
  echo "expected exactly one GTK2 amd64 deb, found ${#gtk_debs[@]}" >&2
  ls -la "${download_dir}" >&2 || true
  exit 1
fi

qt_deb="${qt_debs[0]}"
gtk_deb="${gtk_debs[0]}"
sha_file="${download_dir}/SHA256.txt"

if [[ ! -f "${sha_file}" ]]; then
  echo "SHA256.txt missing from upstream release ${UPSTREAM_TAG}" >&2
  exit 1
fi

verify_sha() {
  local file="$1"
  local base expected actual
  base="$(basename "${file}")"
  expected="$(awk -v f="${base}" '$2 == f { print $1; exit }' "${sha_file}")"
  if [[ -z "${expected}" ]]; then
    echo "no SHA256 entry for ${base}" >&2
    exit 1
  fi
  actual="$(sha256sum "${file}" | awk '{ print $1 }')"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "SHA256 mismatch for ${base}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi
  echo "SHA256 OK: ${base}"
}

verify_sha "${qt_deb}"
verify_sha "${gtk_deb}"

# Rewrite Package / Conflicts / Provides / Replaces in an extracted control file.
rewrite_control() {
  local control="$1"
  local new_pkg="$2"
  local other_pkg="$3"
  local label="$4"
  local tmp
  tmp="$(mktemp)"

  awk -v pkg="${new_pkg}" -v other="${other_pkg}" -v label="${label}" '
    /^Package:/ { print "Package: " pkg; next }
    /^Provides:/ { next }
    /^Conflicts:/ { next }
    /^Replaces:/ { next }
    /^Breaks:/ { next }
    /^Description:/ {
      if (!extra_printed) {
        print "Provides: peazip"
        print "Conflicts: peazip, " other
        print "Replaces: peazip"
        extra_printed = 1
      }
      desc = $0
      sub(/^Description:[[:space:]]*/, "", desc)
      if (desc !~ /\(Qt6\)/ && desc !~ /\(GTK2\)/) {
        print "Description: " desc " (" label ")"
      } else {
        print "Description: " desc
      }
      next
    }
    { print }
    END {
      if (!extra_printed) {
        print "Provides: peazip"
        print "Conflicts: peazip, " other
        print "Replaces: peazip"
      }
    }
  ' "${control}" > "${tmp}"

  mv "${tmp}" "${control}"
}

repack_one() {
  local src_deb="$1"
  local new_pkg="$2"
  local other_pkg="$3"
  local label="$4"

  local extract="${WORKDIR}/extract-${new_pkg}"
  rm -rf "${extract}"
  mkdir -p "${extract}"

  dpkg-deb -R "${src_deb}" "${extract}"

  local control="${extract}/DEBIAN/control"
  if [[ ! -f "${control}" ]]; then
    echo "missing DEBIAN/control in ${src_deb}" >&2
    exit 1
  fi

  rewrite_control "${control}" "${new_pkg}" "${other_pkg}" "${label}"

  local version arch
  version="$(awk -F': ' '/^Version:/{ print $2; exit }' "${control}")"
  arch="$(awk -F': ' '/^Architecture:/{ print $2; exit }' "${control}")"
  arch="${arch:-amd64}"

  if [[ -z "${version}" ]]; then
    echo "could not read Version from ${control}" >&2
    exit 1
  fi

  local out_deb="${OUT}/${new_pkg}_${version}_${arch}.deb"
  dpkg-deb -b "${extract}" "${out_deb}"
  echo "Wrote ${out_deb}"
}

repack_one "${qt_deb}" "peazip-qt6" "peazip-gtk2" "Qt6"
repack_one "${gtk_deb}" "peazip-gtk2" "peazip-qt6" "GTK2"

printf '%s\n' "${UPSTREAM_TAG}" > "${OUT}/version.txt"
printf '%s\n' "${UPSTREAM_TAG}" > "${OUT}/upstream-tag.txt"

echo "Repacked packages:"
ls -l "${OUT}"/*.deb
