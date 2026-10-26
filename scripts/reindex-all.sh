#!/bin/bash
# Full Immich Re-index Pipeline
# Run after: config changes, version upgrades, corruption recovery
# Usage: ./reindex-all.sh [--skip-video] [--skip-faces] [--skip-clip]

set -euo pipefail

# ===== PARSE ARGS =====
SKIP_VIDEO=false
SKIP_FACES=false
SKIP_CLIP=false

for arg in "$@"; do
    case $arg in
        --skip-video) SKIP_VIDEO=true ;;
        --skip-faces) SKIP_FACES=true ;;
        --skip-clip) SKIP_CLIP=true ;;
    esac
done

# ===== COLORS =====
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%F %T')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +'%F %T')]${NC} $*"; }
error() { echo -e "${RED}[$(date +'%F %T')]${NC} $*"; }

# ===== PRE-CHECKS =====
if ! docker ps --format '{{.Names}}' | grep -q '^immich_server$'; then
    error "immich_server not running"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q '^immich_machine_learning$'; then
    error "immich_machine_learning not running"
    exit 1
fi

# ===== JOB QUEUE =====
JOBS=(
    "metadata:Metadata Extraction"
    "thumbnails:Thumbnail Generation"
    "faces:Face Detection & Recognition"
    "clip:CLIP Embeddings (Semantic Search)"
)

if [[ "$SKIP_VIDEO" != "true" ]]; then
    JOBS+=("video-transcode:Video Transcoding (QuickSync)")
fi

# ===== EXECUTE =====
TOTAL=${#JOBS[@]}
CURRENT=0

for job in "${JOBS[@]}"; do
    IFS=':' read -r cmd name <<< "$job"
    CURRENT=$((CURRENT + 1))
    
    log "[${CURRENT}/${TOTAL}] Starting: ${name}"
    
    START=$(date +%s)
    
    if docker exec immich_server npm run "immich:${cmd}"; then
        ELAPSED=$(( $(date +%s) - START ))
        log "[${CURRENT}/${TOTAL}] Completed: ${name} (${ELAPSED}s)"
    else
        error "[${CURRENT}/${TOTAL}] FAILED: ${name}"
        exit 1
    fi
done

log "All re-index jobs completed successfully"

# ===== VERIFY =====
log "Verifying results..."
docker exec immich_postgres psql -U postgres -d immich -c "
SELECT 
  (SELECT COUNT(*) FROM asset) as total_assets,
  (SELECT COUNT(DISTINCT assetId) FROM asset_metadata WHERE key='thumbnail') as thumbnails,
  (SELECT COUNT(DISTINCT assetId) FROM asset_metadata WHERE key='clipEmbedding') as clip_embeddings,
  (SELECT COUNT(*) FROM asset_face WHERE personGroupId IS NOT NULL) as faces_assigned,
  (SELECT COUNT(DISTINCT assetId) FROM asset_metadata WHERE key='videoConversion') as videos_transcoded;
"

log "Verification complete"
