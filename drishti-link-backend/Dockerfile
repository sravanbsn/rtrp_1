FROM python:3.11-slim

WORKDIR /app

# 1. Install system dependencies
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Force install the specific version of Protobuf that both need
RUN pip install --no-cache-dir protobuf==3.20.3

# 3. Install AI libraries (using the legacy resolver to ignore the warning)
RUN pip install --no-cache-dir --extra-index-url https://download.pytorch.org/whl/cpu \
    torch torchvision torchaudio

# 4. Install the rest of the stack
RUN pip install --no-cache-dir \
    ultralytics==8.1.0 \
    mediapipe==0.10.9 \
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

# 5. Copy application code
COPY . .

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
