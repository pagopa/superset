#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/.superset-build"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/SUPERSET_VERSION")"
DOCKERFILE="${BUILD_DIR}/Dockerfile"

echo "Preparing Superset ${VERSION} in ${BUILD_DIR}"

rm -rf "${BUILD_DIR}"
git clone --branch "${VERSION}" --depth 1 https://github.com/apache/superset.git "${BUILD_DIR}"

# Drop every dot-directory from the clone (.git, .github, .devcontainer,
# .storybook, etc.) — none of them are needed in the build context, and none
# should be mistaken for this repo's own. Only directories are targeted, not
# dotfiles.
find "${BUILD_DIR}" -mindepth 1 -type d -name '.*' -prune -exec rm -rf {} +

# A checkout on Windows (core.autocrlf=true) can turn LF-only shell scripts
# into CRLF, breaking their shebang during the Docker build. No-op on Linux CI checkouts.
find "${BUILD_DIR}" -type f -name '*.sh' -exec sed -i 's/\r$//' {} +

# Override the official Italian catalog with the one maintained in this repo.
cp "${REPO_ROOT}/custom_translations/messages.po" \
  "${BUILD_DIR}/superset/translations/it/LC_MESSAGES/messages.po"

# Insert a patch file's content into the cloned Dockerfile right after the
# first line matching the given literal anchor.
insert_after() {
  local anchor="$1"
  local patch_file="$2"
  local line
  line="$(grep -nF -- "${anchor}" "${DOCKERFILE}" | head -n1 | cut -d: -f1)"
  if [[ -z "${line}" ]]; then
    echo "ERROR: anchor not found in Dockerfile: ${anchor}" >&2
    exit 1
  fi
  sed -i "${line}r ${patch_file}" "${DOCKERFILE}"
}

# Patch perl-base to pick up the trixie-security fix for CVE-2026-13221,
# CVE-2026-42496 and CVE-2026-8376 (all CRITICAL), which the base image
# still ships unpatched.
PERL_BASE_PATCH="$(mktemp)"
cat > "${PERL_BASE_PATCH}" <<'EOF'

# Patch perl-base to pick up the trixie-security fix for CVE-2026-13221,
# CVE-2026-42496 and CVE-2026-8376 (all CRITICAL), which the base image
# still ships unpatched.
RUN apt-get update && \
    apt-get install --no-install-recommends -y --only-upgrade perl-base && \
    rm -rf /var/lib/apt/lists/*
EOF
insert_after 'FROM python:${PY_VER} AS python-base' "${PERL_BASE_PATCH}"
rm -f "${PERL_BASE_PATCH}"

# linux-libc-dev (kernel UAPI headers) is pulled in as a hard dependency of
# libc6-dev, which the -dev packages installed just above it require. It
# carries a CRITICAL CVE and is never needed at runtime (only for building
# things against raw kernel headers), so purge it explicitly.
LINUX_LIBC_DEV_PATCH="$(mktemp)"
cat > "${LINUX_LIBC_DEV_PATCH}" <<'EOF'

# linux-libc-dev (kernel UAPI headers) is pulled in as a hard
# dependency of libc6-dev, which the -dev packages above require. It carries
# a CRITICAL CVE and is never needed at runtime (only for building things
# against raw kernel headers), so purge it explicitly.
RUN apt-get purge -y --auto-remove linux-libc-dev \
    && rm -rf /var/lib/apt/lists/*
EOF
insert_after '      libldap2-dev' "${LINUX_LIBC_DEV_PATCH}"
rm -f "${LINUX_LIBC_DEV_PATCH}"

echo "Superset source ready at ${BUILD_DIR}"
