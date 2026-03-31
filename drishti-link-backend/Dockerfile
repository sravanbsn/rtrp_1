# ==========================================
# Production Dockerfile optimized for CPU and Headless AI
# ==========================================
FROM python:3.11-slim as builder

# Setup virtual environment
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Install basic dependencies (headless doesn't need libglib2.0 etc.)
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Force CPU-only PyTorch first
RUN pip install --no-cache-dir --extra-index-url https://download.pytorch.org/whl/cpu torch torchvision torchaudio

# Install Headless AI packages
RUN pip install --no-cache-dir opencv-python-headless mediapipe

# Install remaining python dependencies in virtualenv
WORKDIR /app
COPY requirements.prod.txt .
RUN pip install --no-cache-dir -r requirements.prod.txt

# ==========================================
# Final Production Stage - Security Hardened
# ==========================================
FROM python:3.11-slim

# Create non-root user for security
RUN groupadd -r drishti && useradd -r -g drishti drishti

# Install runtime system dependencies and clean apt cache
RUN apt-get update && apt-get install -y \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy virtual env from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Create app directory with proper permissions
WORKDIR /app
RUN chown -R drishti:drishti /opt/venv /app

# Copy application code with proper ownership
COPY --chown=drishti:drishti . .

# Switch to non-root user
USER drishti

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -f http://localhost:${PORT:-8000}/health || exit 1

# Run with gunicorn and uvicorn worker
CMD ["sh", "-c", "gunicorn app.main:app --bind 0.0.0.0:${PORT:-8000} --workers 4 --worker-class uvicorn.workers.UvicornWorker --keep-alive 2"]
