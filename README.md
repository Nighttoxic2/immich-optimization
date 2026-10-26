# Immich Optimization

Performance tuning and configuration for Immich photo server on resource-constrained hardware (Intel i7-7700HQ, GTX 1050 Ti 4GB, 16GB RAM).

## 🎯 Optimization Summary

| Component | Before | After | Improvement |
|-----------|--------|-------|-------------|
| **Transcoding** | CPU (libx264) | Intel QuickSync (VAAPI) | **4.3x faster**, 80% less CPU |
| **ML Inference** | CUDA (GTX 1050 Ti) | CPU (SigLIP, 6GB limit) | **Stable**, no OOM kills |
| **CLIP Model** | ViT-B-32 | ViT-B-16-SigLIP | Better zero-shot, faster |
| **Job Processing** | Crash loop (12k restarts) | Healthy pipeline | **100% success** |

## 📁 Repository Structure

```
immich-optimization/
├── config/
│   ├── hwaccel.transcoding.yml    # QuickSync VAAPI config
│   └── ml.env.example             # ML container env (CPU, SigLIP)
├── scripts/
│   └── reindex-all.sh             # Full pipeline: metadata→thumbs→faces→CLIP→video
└── benchmarks/
    └── transcoding-comparison.md  # CPU vs QuickSync benchmarks
```

## ⚡ QuickSync Configuration

**Hardware:** Intel HD 630 (Kaby Lake, 24 EUs) via `/dev/dri/renderD128`

```yaml
# docker-compose.yml
services:
  immich-server:
    extends:
      file: hwaccel.transcoding.yml
      service: quicksync
```

```yaml
# hwaccel.transcoding.yml
services:
  quicksync:
    devices:
      - /dev/dri/renderD128:/dev/dri/renderD128
      - /dev/dri/card0:/dev/dri/card0
    environment:
      - FFMPEG_HWACCEL=vaapi
      - FFMPEG_VAAPI_DEVICE=/dev/dri/renderD128
      - HWACCEL_TRANSCODE=1
```

## 🧠 ML Configuration (CPU-Optimized)

```yaml
# ML container
immich-machine-learning:
  environment:
    - MACHINE_LEARNING_PRELOAD__CLIP=ViT-B-16-SigLIP__webli
    - MACHINE_LEARNING_MODEL_TTL=0
  deploy:
    resources:
      limits:
        memory: 6G
```

**Why CPU?** GTX 1050 Ti (4GB VRAM) insufficient for ML inference → OOM kills. CPU with SigLIP model is faster and stable.

## 🔄 Re-index Pipeline

```bash
# Run full re-index after config changes
./scripts/reindex-all.sh

# Or selective
./scripts/reindex-all.sh --skip-video
./scripts/reindex-all.sh --skip-faces --skip-clip
```

Jobs: `metadata` → `thumbnails` → `faces` → `clip` → `video-transcode`

## 📊 Benchmarks

See [transcoding-comparison.md](benchmarks/transcoding-comparison.md) for detailed CPU vs QuickSync results (VMAF quality, speedup, power).

## 🔒 Security

- No secrets in this repo
- Hardware device paths are standard Linux paths
- All configuration uses environment variable substitution

## 📄 License

MIT
