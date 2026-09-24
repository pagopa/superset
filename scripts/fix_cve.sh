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

OS_HIGH_CVE_PATCH='
# Patch util-linux, pcre2, sqlite3, libcap2 and gzip to pick up the
# trixie-security fixes for their outstanding HIGH CVEs (util-linux:
# CVE-2026-53612, CVE-2026-53613, CVE-2026-53614; pcre2: CVE-2026-86145,
# CVE-2026-89157, CVE-2026-89161; sqlite3: CVE-2026-11822, CVE-2026-11824;
# libcap2: CVE-2026-4878; gzip: CVE-2026-41992), which the base image still
# ships unpatched.
RUN apt-get update && \
    apt-get install --no-install-recommends -y --only-upgrade \
      util-linux \
      bsdutils \
      libblkid1 \
      libmount1 \
      libsmartcols1 \
      libuuid1 \
      liblastlog2-2 \
      login \
      mount \
      libpcre2-8-0 \
      libsqlite3-0 \
      libcap2 \
      gzip && \
    rm -rf /var/lib/apt/lists/*
'
insert_after 'FROM python:${PY_VER} AS python-base' "${OS_HIGH_CVE_PATCH}"

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

PYTHON_HIGH_CVE_PATCH='
# Bump Pillow, PyJWT, Mako, urllib3, pyasn1 and pyOpenSSL to pick up their
# fixes for outstanding HIGH CVEs (Pillow: CVE-2026-40192, CVE-2026-25990,
# CVE-2026-42311, CVE-2026-54058, CVE-2026-54059, CVE-2026-54060,
# CVE-2026-55379, CVE-2026-55380, CVE-2026-59197, CVE-2026-59199,
# CVE-2026-59200, CVE-2026-59204, CVE-2026-59205; PyJWT: CVE-2026-32597,
# CVE-2026-48526; Mako: CVE-2026-41205, CVE-2026-44307; urllib3:
# CVE-2026-44431, CVE-2026-44432; pyasn1: CVE-2026-59884, CVE-2026-30922,
# CVE-2026-59885, CVE-2026-59886; pyOpenSSL: CVE-2026-27459). All six stay
# within the version ranges declared by Superset (pyproject.toml) or by
# their actual consumers (pyasn1-modules requires pyasn1<0.7.0,>=0.6.1;
# shillelagh requires pyopenssl>=24.0.0), unlike cryptography/msgpack/
# pyarrow which would need a major bump beyond those declared constraints.
RUN uv pip install --upgrade \
      "Pillow==12.3.0" \
      "PyJWT==2.13.0" \
      "Mako==1.3.12" \
      "urllib3==2.7.0" \
      "pyasn1==0.6.4" \
      "pyOpenSSL==26.0.0"
'
insert_after '/app/docker/pip-install.sh --requires-build-essential -r requirements/base.txt' "${PYTHON_HIGH_CVE_PATCH}"
