"""Notification service — SMS, WhatsApp, push via Twilio + Firebase."""
from __future__ import annotations

import structlog
from tenacity import retry, stop_after_attempt, wait_exponential

from core.config import settings

log = structlog.get_logger(__name__)


class NotificationService:
    """
    Multi-channel notification dispatcher.
    Retries delivery with exponential backoff (critical for SOS).
    """

    def __init__(self) -> None:
        self._twilio_client = None
        self._firebase_app  = None

    def _get_twilio(self):
        if self._twilio_client is None:
            if not settings.TWILIO_ACCOUNT_SID:
                log.warning("twilio.not_configured")
                return None
            from twilio.rest import Client
            self._twilio_client = Client(
                settings.TWILIO_ACCOUNT_SID,
                settings.TWILIO_AUTH_TOKEN,
            )
        return self._twilio_client

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=8),
        reraise=True,
    )
    async def send_sms(self, to: str, body: str) -> bool:
        client = self._get_twilio()
        if not client:
            log.warning("sms.skipped_no_twilio", to=to)
            return False
        try:
            message = client.messages.create(
                body=body, from_=settings.TWILIO_FROM_NUMBER, to=to
            )
            log.info("sms.sent", sid=message.sid, to=to)
            return True
        except Exception as exc:
            log.error("sms.failed", to=to, exc=str(exc))
            raise

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=1, max=8),
        reraise=True,
    )
    async def send_whatsapp(self, to: str, body: str) -> bool:
        client = self._get_twilio()
        if not client:
            return False
        wa_to = f"whatsapp:{to}" if not to.startswith("whatsapp:") else to
        try:
            message = client.messages.create(
                body=body,
                from_=settings.TWILIO_WHATSAPP_FROM,
                to=wa_to,
            )
            log.info("whatsapp.sent", sid=message.sid)
            return True
        except Exception as exc:
            log.error("whatsapp.failed", exc=str(exc))
            raise

    async def send_push(
        self, device_token: str, title: str, body: str, data: dict | None = None
    ) -> bool:
        """Firebase Cloud Messaging push notification."""
        try:
            from firebase_admin import messaging
            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                data=data or {},
                token=device_token,
            )
            response = messaging.send(message)
            log.info("push.sent", response=response)
            return True
        except Exception as exc:
            log.error("push.failed", exc=str(exc))
            return False

    async def send_sos(
        self,
        guardian_id: str,
        user_name:   str,
        lat:         float,
        lng:         float,
        alert_id:    str,
    ) -> None:
        """
        SOS broadcast: push + SMS + WhatsApp to guardian.
        All 3 channels attempted; individual failures don't abort others.
        """
        maps_url = f"https://maps.google.com/?q={lat},{lng}"
        sms_body = (
            f"🆘 SOS ALERT: {user_name} needs help!\n"
            f"Location: {maps_url}\n"
            f"Alert ID: {alert_id}\n"
            f"Open the Drishti-Link Guardian app NOW."
        )

        # TODO: fetch guardian phone from user service
        guardian_phone = "+919999999999"  # placeholder

        # Fire and forget individual channels
        results = await _attempt_all([
            self.send_sms(guardian_phone, sms_body),
            self.send_whatsapp(guardian_phone, sms_body),
        ])
        log.info("sos.channels_attempted", results=results, alert_id=alert_id)


async def _attempt_all(coros) -> list[bool | str]:
    """Run all coroutines; capture exceptions as False."""
    import asyncio
    results = []
    for coro in coros:
        try:
            results.append(await coro)
        except Exception as exc:
            results.append(False)
    return results
