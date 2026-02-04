# =============================================================================
# ACE-Step 1.5 FastAPI Server - Multi-stage Dockerfile
# =============================================================================
# This image includes the ACE-Step models (~15GB total)
# Build with: docker build --build-arg HF_TOKEN=your_token -t acestep-api:latest .
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Model Downloader - Download models from HuggingFace
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

# Download main model package (includes VAE, Qwen3-Embedding, acestep-5Hz-lm-1.7B)
# Uses HF_TOKEN for authentication with gated repos
# Exclude acestep-v15-turbo since we use acestep-v15-base instead
RUN python -c "import os; from huggingface_hub import snapshot_download; snapshot_download('ACE-Step/Ace-Step1.5', local_dir='/models/checkpoints', token=os.environ.get('HF_TOKEN'), ignore_patterns=['acestep-v15-turbo/*'])"

# Download acestep-v15-base as the primary DiT model
RUN python -c "import os; from huggingface_hub import snapshot_download; snapshot_download('ACE-Step/acestep-v15-base', local_dir='/models/checkpoints/acestep-v15-base', token=os.environ.get('HF_TOKEN'))"

# Optional: Download additional LM models (uncomment if needed)
# RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('ACE-Step/acestep-5Hz-lm-0.6B', local_dir='/models/checkpoints/acestep-5Hz-lm-0.6B')"
# RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('ACE-Step/acestep-5Hz-lm-4B', local_dir='/models/checkpoints/acestep-5Hz-lm-4B')"

# Optional: Download additional DiT models (uncomment if needed)
# RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('ACE-Step/acestep-v15-turbo-shift3', local_dir='/models/checkpoints/acestep-v15-turbo-shift3')"

# -----------------------------------------------------------------------------
# Stage 2: Runtime - Install ACE-Step and run from /app
# -----------------------------------------------------------------------------
FROM nvidia/cuda:12.8.0-runtime-ubuntu22.04 as runtime

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    # ACE-Step configuration
    ACESTEP_PROJECT_ROOT=/app \
    ACESTEP_OUTPUT_DIR=/app/outputs \
    ACESTEP_TMPDIR=/app/outputs \
    ACESTEP_DEVICE=cuda \
    # ACE-Step API model paths (full paths to pre-baked models)
    ACESTEP_CONFIG_PATH=/app/checkpoints/acestep-v15-base \
    ACESTEP_LM_MODEL_PATH=/app/checkpoints/acestep-5Hz-lm-1.7B \
    ACESTEP_LM_BACKEND=pt \
    # Server configuration
    ACESTEP_API_HOST=0.0.0.0 \
    ACESTEP_API_PORT=8000

WORKDIR /app

# Install system dependencies including Python, pip, git, and build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-dev \
    python3-pip \
    git \
    curl \
    build-essential \
    libsndfile1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.11 /usr/bin/python

# Install uv for faster dependency resolution
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"

# Clone ACE-Step directly into /app and install
RUN git clone https://github.com/ace-step/ACE-Step-1.5.git /app && \
    rm -rf /app/.git && \
    uv pip install --system --no-cache .

# Create symlink so ACE-Step's model discovery finds /app/checkpoints
# ACE-Step uses __file__ to locate checkpoints relative to its install path
RUN ln -s /app/checkpoints /usr/local/lib/python3.11/dist-packages/checkpoints

# Copy models from model-downloader stage into /app/checkpoints
COPY --from=model-downloader /models/checkpoints /app/checkpoints

# Create placeholder for acestep-v15-turbo to satisfy check_main_model_exists()
# We use acestep-v15-base instead, but the check looks for all MAIN_MODEL_COMPONENTS
RUN mkdir -p /app/checkpoints/acestep-v15-turbo

# Copy startup script
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Create output directory
RUN mkdir -p /app/outputs

# Expose ports (8000 for API, 7860 for Gradio UI)
EXPOSE 8000 7860

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

# Run both API server and Gradio UI
CMD ["/app/start.sh"]
