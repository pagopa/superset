#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/.superset-build"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/SUPERSET_VERSION")"

echo "Preparing Superset ${VERSION} in ${BUILD_DIR}"

rm -rf "${BUILD_DIR}"
git clone --branch "${VERSION}" --depth 1 https://github.com/apache/superset.git "${BUILD_DIR}"

# Drop the clone's own .git
rm -rf "${BUILD_DIR}/.git"

# A checkout on Windows (core.autocrlf=true) can turn LF-only shell scripts
# into CRLF, breaking their shebang during the Docker build. No-op on Linux CI checkouts.
find "${BUILD_DIR}" -type f -name '*.sh' -exec sed -i 's/\r$//' {} +

# Override the official Italian catalog with the one maintained in this repo.
cp "${REPO_ROOT}/custom_translations/messages.po" \
  "${BUILD_DIR}/superset/translations/it/LC_MESSAGES/messages.po"

echo "Superset source ready at ${BUILD_DIR}"
