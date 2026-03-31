# ==========================================
# Production Dockerfile with Security Best Practices
# ==========================================
FROM python:3.11-slim as builder

# Setup virtual environment
ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Install system dependencies required for OpenCV
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1 \
    && rm -rf /var/lib/apt/lists/*

# Install CPU-specific PyTorch strictly first to bypass massive CUDA downloads
RUN pip install --no-cache-dir torch==2.5.1+cpu torchvision==0.20.1+cpu --index-url https://download.pytorch.org/whl/cpu

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

# Install runtime system dependencies
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgl1 \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

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
EXPOSE 8080

# Health check using fixed port
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run with gunicorn
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port $PORT"]
