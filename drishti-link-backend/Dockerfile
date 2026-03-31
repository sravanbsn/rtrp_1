FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .

RUN pip install --no-cache-dir \
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

COPY . .

ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
