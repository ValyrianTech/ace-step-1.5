# =============================================================================
# ACE-Step 1.5 FastAPI Server - Multi-stage Dockerfile
# =============================================================================
# This image includes the ACE-Step models (~15GB total)
# Build with: docker build --build-arg HF_TOKEN=your_token -t acestep-api:latest .
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Builder - Install dependencies and build wheels
# -----------------------------------------------------------------------------
FROM python:3.11-slim as builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv for faster dependency resolution
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# Create virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Clone ACE-Step and install using uv (handles all dependencies including nano-vllm)
RUN git clone https://github.com/ace-step/ACE-Step-1.5.git /tmp/acestep && \
    cd /tmp/acestep && \
    uv pip install --no-cache . && \
    rm -rf /tmp/acestep/.git

# -----------------------------------------------------------------------------
# Stage 2: Model Downloader - Download models from HuggingFace
# -----------------------------------------------------------------------------
FROM python:3.11-slim as model-downloader

# Accept HuggingFace token as build argument (required for gated models)
ARG HF_TOKEN
ENV HF_TOKEN=${HF_TOKEN}

WORKDIR /models

# Install huggingface-hub with hf_transfer for faster downloads
RUN pip install --no-cache-dir "huggingface-hub[cli,hf_transfer]"

# Enable fast transfers
ENV HF_HUB_ENABLE_HF_TRANSFER=1

# Download main model package (includes VAE, Qwen3-Embedding, acestep-v15-turbo, acestep-5Hz-lm-1.7B)
# Uses HF_TOKEN for authentication with gated repos
RUN python -c "import os; from huggingface_hub import snapshot_download; snapshot_download('ACE-Step/Ace-Step1.5', local_dir='/models/checkpoints', token=os.environ.get('HF_TOKEN'))"

# Optional: Download additional LM models (uncomment if needed)
# RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('ACE-Step/acestep-5Hz-lm-0.6B', local_dir='/models/checkpoints/acestep-5Hz-lm-0.6B')"
# RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('ACE-Step/acestep-5Hz-lm-4B', local_dir='/models/checkpoints/acestep-5Hz-lm-4B')"

# Optional: Download additional DiT models (uncomment if needed)
# RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('ACE-Step/acestep-v15-turbo-shift3', local_dir='/models/checkpoints/acestep-v15-turbo-shift3')"

# -----------------------------------------------------------------------------
# Stage 3: Runtime - Minimal image for running the application
# -----------------------------------------------------------------------------
FROM nvidia/cuda:12.8.0-runtime-ubuntu22.04 as runtime

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PATH="/opt/venv/bin:$PATH" \
    # ACE-Step configuration
    ACESTEP_PROJECT_ROOT=/app \
    ACESTEP_CHECKPOINT_DIR=/app/checkpoints \
    ACESTEP_OUTPUT_DIR=/app/outputs \
    ACESTEP_DEVICE=cuda \
    ACESTEP_DIT_CONFIG=acestep-v15-turbo \
    ACESTEP_LM_MODEL=acestep-5Hz-lm-1.7B \
    ACESTEP_LM_BACKEND=vllm \
    # Server configuration
    HOST=0.0.0.0 \
    PORT=8000

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-venv \
    libsndfile1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.11 /usr/bin/python

# Copy virtual environment from builder
COPY --from=builder /opt/venv /opt/venv

# Fix venv Python symlink to point to runtime Python
RUN ln -sf /usr/bin/python3.11 /opt/venv/bin/python && \
    ln -sf /usr/bin/python3.11 /opt/venv/bin/python3 && \
    ln -sf /usr/bin/python3.11 /opt/venv/bin/python3.11

# Copy models from model-downloader stage
COPY --from=model-downloader /models/checkpoints /app/checkpoints

# No custom application code needed - using ACE-Step's built-in API server

# Create output directory
RUN mkdir -p /app/outputs

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash appuser && \
    chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Run ACE-Step's built-in API server
CMD ["acestep-api", "--host", "0.0.0.0", "--port", "8000"]
