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
    && rm -rf /var/lib/apt/lists/*

# Install python dependencies in virtualenv (production only)
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

# Expose railway/docker port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run with gunicorn for production scaling
CMD ["gunicorn", "main:app", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "4", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--worker-tmp-dir", "/dev/shm", \
     "--max-requests", "1000", \
     "--max-requests-jitter", "50", \
     "--preload", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "--log-level", "info", \
     "--timeout", "120", \
     "--keepalive", "2", \
     "--graceful-timeout", "30"]
