FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for OpenCV and MediaPipe
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install EVERYTHING globally with no-cache to keep it under 1GB
# We install ultralytics explicitly to ensure YOLOv8 works
RUN pip install --no-cache-dir --extra-index-url https://download.pytorch.org/whl/cpu \
    torch torchvision torchaudio
    
RUN pip install --no-cache-dir \
    ultralytics \
    mediapipe \
    opencv-python-headless \
    fastapi \
    uvicorn \
    pydantic-settings \
    structlog \
    cachetools \
    python-multipart \
    psycopg2-binary \
    redis \
    firebase-admin \
    twilio \
    "python-jose[cryptography]" \
    "passlib[bcrypt]" \
    python-dotenv

# Copy the rest of the application
COPY . .

# Set environment variables to ensure Python finds the libraries
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
