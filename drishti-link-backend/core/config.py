import os
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field
import logging

class Settings(BaseSettings):
    # Database
    DATABASE_URL: str = Field(default="postgresql+asyncpg://postgres:postgres@localhost:5432/drishti")
    DATABASE_POOL_SIZE: int = Field(default=20)
    DATABASE_MAX_OVERFLOW: int = Field(default=10)
    DATABASE_POOL_TIMEOUT: int = Field(default=30)
    DATABASE_ECHO: bool = Field(default=False)
    
    # Redis
    REDIS_URL: str = Field(default="redis://localhost:6379/0")
    REDIS_ENABLED: bool = Field(default=False, description="Set True to enable Redis caching. Falls back to in-memory if False or unavailable.")
    
    # App
    APP_ENV: str = Field(default="development")
    DEBUG: bool = Field(default=True)
    PORT: int = Field(default=8000)
    APP_VERSION: str = Field(default="1.0.0")
    
    # Firebase
    FIREBASE_PROJECT_ID: str = Field(default="drishti-link")
    FIREBASE_CREDENTIALS_PATH: str = Field(default="firebase-service-account.json")
    FIREBASE_SERVICE_ACCOUNT_JSON: str = Field(default="", description="Base64 encoded service account JSON")
    FIREBASE_DATABASE_URL: str = Field(
        default="https://drishti-link-default-rtdb.asia-southeast1.firebasedatabase.app"
    )
    FIREBASE_STORAGE_BUCKET: str = Field(default="drishti-link.firebasestorage.app")
    
    # Notifications
    TWILIO_ACCOUNT_SID: str = Field(default="dummy_sid")
    TWILIO_AUTH_TOKEN: str = Field(default="dummy_token")
    TWILIO_FROM_NUMBER: str = Field(default="dummy_phone")
    TWILIO_WHATSAPP_FROM: str = Field(default="whatsapp:dummy_phone")
    
    # Security
    ALLOWED_ORIGINS: str = Field(
        default="http://localhost:3000,https://drishti-link.web.app"
    )
    # AI Models
    YOLO_MODEL_PATH: str = Field(default="ml/models/yolov8_indian_streets_v1.pt")
    YOLO_CONFIDENCE: float = Field(default=0.45)
    YOLO_IOU: float = Field(default=0.45)
    MODEL_VERSION: str = Field(default="v1")
    ADAPTIVE_LEARNING: bool = Field(default=True)
    MIN_SESSIONS_FOR_ADAPTATION: int = Field(default=5)
    MIN_FEEDBACK_SAMPLES: int = Field(default=10)
    DEFAULT_PC_THRESHOLD: float = Field(default=0.75)
    DEFAULT_WARNING_THRESHOLD: float = Field(default=0.50)
    RATE_LIMIT_USER: int = Field(default=10)
    RATE_LIMIT_IP: int = Field(default=100)
    
    # Performance
    FRAME_SKIP_NORMAL: int = Field(default=3)
    FRAME_SKIP_ALERT: int = Field(default=1)
    PROCESSING_TARGET_MS: int = Field(default=80)
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="allow"
    )

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.ALLOWED_ORIGINS.split(",")]


# Initialize early to throw validation errors synchronously at startup
try:
    settings = Settings()
except Exception as e:
    logging.critical(f"Configuration Validation Error: {e}")
    raise RuntimeError("Failed to load application settings. Check .env variables.") from e
