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

# Expose port
EXPOSE 8080

# Health check using fixed port
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run with gunicorn
CMD uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}
