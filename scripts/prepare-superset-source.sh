#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/.superset-build"
VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/SUPERSET_VERSION")"

echo "Preparing Superset ${VERSION} in ${BUILD_DIR}"

rm -rf "${BUILD_DIR}"
git clone --branch "${VERSION}" --depth 1 https://github.com/apache/superset.git "${BUILD_DIR}"

# Drop every dot-directory from the clone (.git, .github, .devcontainer,
# .storybook, etc.) — none of them are needed in the build context, and none
# should be mistaken for this repo's own. Only directories are targeted, not
# dotfiles.
find "${BUILD_DIR}" -mindepth 1 -type d -name '.*' -prune -exec rm -rf {} +

# Drop frontend test files (*.test.ts(x)/*.test.js(x)) — webpack.config.js
# explicitly excludes them from both the production bundle and the TS
# type-check, and no build stage ever runs jest/cypress inside the image.
find "${BUILD_DIR}/superset-frontend" -type f \
  \( -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' -o -name '*.test.jsx' \) \
  -delete

# A checkout on Windows (core.autocrlf=true) can turn LF-only shell scripts
# into CRLF, breaking their shebang during the Docker build. No-op on Linux CI checkouts.
find "${BUILD_DIR}" -type f -name '*.sh' -exec sed -i 's/\r$//' {} +

# Override the official Italian catalog with the one maintained in this repo.
cp "${REPO_ROOT}/custom_translations/messages.po" \
  "${BUILD_DIR}/superset/translations/it/LC_MESSAGES/messages.po"

# Patch the cloned Dockerfile to remediate known CVEs in the base image.
"${REPO_ROOT}/scripts/fix_cve.sh" "${BUILD_DIR}"

echo "Superset source ready at ${BUILD_DIR}"
