#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <build-dir>" >&2
  exit 1
fi

BUILD_DIR="$1"
DOCKERFILE="${BUILD_DIR}/Dockerfile"

# Insert the given patch content into the Dockerfile right after the
# first line matching the given literal anchor.
insert_after() {
  local anchor="$1"
  local patch_content="$2"
  local anchor_line_number
  anchor_line_number="$(grep -nF -- "${anchor}" "${DOCKERFILE}" | head -n1 | cut -d: -f1)"
  if [[ -z "${anchor_line_number}" ]]; then
    echo "ERROR: anchor not found in Dockerfile: ${anchor}" >&2
    exit 1
  fi
  local patch_file
  patch_file="$(mktemp)"
  printf '%s\n' "${patch_content}" > "${patch_file}"
  sed "${anchor_line_number}r ${patch_file}" "${DOCKERFILE}" > "${DOCKERFILE}.tmp"
  mv "${DOCKERFILE}.tmp" "${DOCKERFILE}"
  rm -f "${patch_file}"
}

PERL_BASE_PATCH='
# Patch perl-base to pick up the trixie-security fix for CVE-2026-13221,
# CVE-2026-42496 and CVE-2026-8376 (all CRITICAL), which the base image
# still ships unpatched.
RUN apt-get update && \
    apt-get install --no-install-recommends -y --only-upgrade perl-base && \
    rm -rf /var/lib/apt/lists/*
'
insert_after 'FROM python:${PY_VER} AS python-base' "${PERL_BASE_PATCH}"

LINUX_LIBC_DEV_PATCH='
# linux-libc-dev (kernel UAPI headers) is pulled in as a hard
# dependency of libc6-dev, which the -dev packages above require. It carries
# a CRITICAL CVE and is never needed at runtime (only for building things
# against raw kernel headers), so purge it explicitly.
RUN apt-get purge -y --auto-remove linux-libc-dev \
    && rm -rf /var/lib/apt/lists/*
'
insert_after '      libldap2-dev' "${LINUX_LIBC_DEV_PATCH}"
