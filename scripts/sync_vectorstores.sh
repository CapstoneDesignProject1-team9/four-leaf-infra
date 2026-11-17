#!/usr/bin/env bash
# ------------------------------------------------------------------
# Sync RAG vector‑store data from the project's S3 bucket into the
# Docker‑compose volume that is mounted into the AI container.
#
#   • S3 source : s3://four-leaf-rag-data/vectorstores/
#   • Destination : ./ai-data/vectorstores/
#   • The bucket contains three sub‑folders (e.g., knu_notice_bge_m3,
#     knu_syllabi_bge_m3, everyother_folder). They must be copied with
#     the same names so the AI service can find them via the paths in
#     app/core/config.py.
# ------------------------------------------------------------------

set -euo pipefail

# ------------------------------------------------------------------
# 1️⃣  Verify AWS CLI is installed
# ------------------------------------------------------------------
if ! command -v aws &>/dev/null; then
  echo "❌  AWS CLI not found. Install with 'brew install awscli' and configure credentials."
  exit 1
fi

# ------------------------------------------------------------------
# 2️⃣  Resolve repository root (script may be called from any cwd)
# ------------------------------------------------------------------
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$REPO_ROOT"

# ------------------------------------------------------------------
# 3️⃣  Destination directory – must match the volume mount in
#     docker-compose.yml (./ai-data/vectorstores -> /app/knowledge/vectorstores)
# ------------------------------------------------------------------
DEST="./ai-data/vectorstores"
mkdir -p "$DEST"

# ------------------------------------------------------------------
# 4️⃣  Sync the entire bucket, preserving sub‑folder names
# ------------------------------------------------------------------
echo "🔄  Syncing S3 vector‑store data…"
aws s3 sync \
  "s3://four-leaf-rag-data/vectorstores/" \
  "$DEST" \
  --only-show-errors

echo "✅  Sync completed. Size:" $(du -sh "$DEST" | cut -f1) "stored in $DEST"

