#!/usr/bin/env bash
# =============================================================================
# Download the Lahman Baseball Database (CSV bundle) from Chadwick Bureau.
# Idempotent: only re-downloads if the target version's CSVs aren't present.
# =============================================================================
set -euo pipefail

LAHMAN_VERSION=${LAHMAN_VERSION:-2023.1}
LAHMAN_URL=${LAHMAN_URL:-https://github.com/chadwickbureau/baseballdatabank/archive/refs/tags/v${LAHMAN_VERSION}.tar.gz}
DATA_DIR=${DATA_DIR:-data/raw}
SENTINEL="${DATA_DIR}/.version-${LAHMAN_VERSION}"

mkdir -p "${DATA_DIR}"

if [[ -f "${SENTINEL}" ]]; then
    echo "✓ Lahman v${LAHMAN_VERSION} already present in ${DATA_DIR}/"
    exit 0
fi

echo "▶ Downloading Lahman v${LAHMAN_VERSION} from ${LAHMAN_URL}..."
TMP=$(mktemp -d)
trap "rm -rf '${TMP}'" EXIT

curl -fsSL --retry 3 --retry-delay 2 -o "${TMP}/lahman.tar.gz" "${LAHMAN_URL}"

echo "▶ Extracting..."
tar -xzf "${TMP}/lahman.tar.gz" -C "${TMP}"

SRC_DIR=$(find "${TMP}" -maxdepth 2 -type d -name 'core' | head -1)
if [[ -z "${SRC_DIR}" ]]; then
    SRC_DIR=$(find "${TMP}" -maxdepth 2 -type d -name 'contrib' | head -1)
fi
if [[ -z "${SRC_DIR}" ]]; then
    echo "✗ Could not locate Lahman core/ directory in archive." >&2
    exit 1
fi

cp "${SRC_DIR}"/*.csv "${DATA_DIR}/"

CONTRIB_DIR=$(find "${TMP}" -maxdepth 2 -type d -name 'contrib' | head -1)
if [[ -n "${CONTRIB_DIR}" ]]; then
    cp -n "${CONTRIB_DIR}"/*.csv "${DATA_DIR}/" 2>/dev/null || true
fi

touch "${SENTINEL}"
echo "✓ Loaded $(ls "${DATA_DIR}"/*.csv | wc -l | tr -d ' ') CSV files into ${DATA_DIR}/"
