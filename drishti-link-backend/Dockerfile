# Stage 1: Builder
FROM python:3.11-slim as builder
WORKDIR /app
RUN apt-get update && apt-get install -y build-essential libgl1 libglib2.0-0
COPY requirements.txt .
# Install CPU-only versions to a specific directory
RUN pip install --user --no-cache-dir --extra-index-url https://download.pytorch.org/whl/cpu \
    torch torchvision torchaudio opencv-python-headless mediapipe fastapi uvicorn \
    python-multipart psycopg2-binary redis firebase-admin twilio structlog

# Stage 2: Final Tiny Image
FROM python:3.11-slim
WORKDIR /app
# Install ONLY the necessary runtime graphics library
RUN apt-get update && apt-get install -y libgl1 libglib2.0-0 && rm -rf /var/lib/apt/lists/*
# Copy only the installed packages from the builder
COPY --from=builder /root/.local /root/.local
COPY . .
ENV PATH=/root/.local/bin:$PATH
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
