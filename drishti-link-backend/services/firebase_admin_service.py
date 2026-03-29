import base64
import json
import logging
import os
import asyncio
from typing import Dict, Any, Optional
import firebase_admin
from firebase_admin import credentials, firestore, db, messaging, auth
from google.cloud.firestore_v1.transaction import Transaction
from fastapi import HTTPException
from cachetools import TTLCache
from core.config import settings

logger = logging.getLogger(__name__)

# Caches
_guardian_cache = TTLCache(maxsize=1000, ttl=3600)  # 1 hour
_profile_cache = TTLCache(maxsize=1000, ttl=60)    # 60 seconds
_token_cache = TTLCache(maxsize=5000, ttl=300)     # 5 minutes

class FirebaseAdminService:
    _initialized = False

    @classmethod
    def initialize(cls):
        if cls._initialized:
            return

        try:
            # Try file path first, then base64
            cred_path = settings.FIREBASE_CREDENTIALS_PATH
            if os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                logger.info(f"Using Firebase credentials from file: {cred_path}")
            elif settings.FIREBASE_SERVICE_ACCOUNT_JSON:
                # Decode Base64 JSON
                b64_str = settings.FIREBASE_SERVICE_ACCOUNT_JSON
                json_str = base64.b64decode(b64_str).decode('utf-8')
                cred_dict = json.loads(json_str)
                cred = credentials.Certificate(cred_dict)
                logger.info("Using Firebase credentials from base64 environment variable")
            else:
                raise ValueError("No Firebase credentials provided - neither file nor base64 JSON")
            
            firebase_admin.initialize_app(cred, {
                'databaseURL': settings.FIREBASE_DATABASE_URL,
                'projectId': settings.FIREBASE_PROJECT_ID
            })

            cls.firestore_client = firestore.client()
            cls._initialized = True
            logger.info("✅ Firebase Admin Service initialized successfully.")

        except Exception as e:
            logger.critical(f"❌ Failed to initialize Firebase Admin: {e}")
            raise

    # --- Firestore Operations ---

    @classmethod
    async def get_user_adaptive_profile(cls, user_id: str) -> Dict[str, Any]:
        """Fetch adaptive profile with 60-second TTL cache."""
        cache_key = f"profile_{user_id}"
        if cache_key in _profile_cache:
            return _profile_cache[cache_key]

        # Run block IO in executor
        loop = asyncio.get_running_loop()
        def _fetch():
            doc_ref = cls.firestore_client.collection('users').document(user_id)
            doc = doc_ref.get()
            if doc.exists:
                return doc.to_dict().get('adaptive_profile', {})
            return {}

        profile = await loop.run_in_executor(None, _fetch)
        
        # Default fallback
        if not profile:
            profile = {
                'warning_threshold': 40,
                'override_threshold': 75,
                'sos_timeout_seconds': 45
            }

        _profile_cache[cache_key] = profile
        return profile

    @classmethod
    async def write_navigation_alert(cls, user_id: str, session_id: str, alert_data: dict) -> str:
        """Writes alert to Firestore and increments session count in a batch."""
        loop = asyncio.get_running_loop()
        
        def _write():
            batch = cls.firestore_client.batch()
            
            # 1. Alert Document
            alert_ref = cls.firestore_client.collection('alerts').document()
            batch.set(alert_ref, alert_data)
            
            # 2. Session Summary Update
            session_ref = cls.firestore_client.collection('sessions').document(session_id)
            batch.update(session_ref, {
                'summary.alerts_count': firestore.Increment(1)
            })
            if alert_data.get('type') == 'override':
                batch.update(session_ref, {
                    'summary.overrides_count': firestore.Increment(1)
                })

            batch.commit()
            return alert_ref.id

        alert_id = await loop.run_in_executor(None, _write)

        # Trigger FCM if override
        if alert_data.get('type') == 'override':
            guardian_id = await cls.get_guardian_id(user_id)
            if guardian_id:
                asyncio.create_task(cls.send_guardian_notification(
                    guardian_id=guardian_id,
                    notification_type='override',
                    data={'user_name': 'Arjun', 'hazard': alert_data.get('hazard_type', 'Unknown hazard')} # TODO dynamic name
                ))

        return alert_id

    @classmethod
    async def update_area_memory(cls, geo_hash: str, hazard_data: dict):
        """Thread-safe transactional update of area memory."""
        loop = asyncio.get_running_loop()
        hazard_type = hazard_data.get('hazard_type')
        composite_key = f"{geo_hash}_{hazard_type}"

        def _transactional_update():
            transaction = cls.firestore_client.transaction()
            doc_ref = cls.firestore_client.collection('area_memory').document(composite_key)
            
            @firestore.transactional
            def update_in_transaction(transaction: Transaction, doc_ref):
                snapshot = doc_ref.get(transaction=transaction)
                if snapshot.exists:
                    current_count = snapshot.get('detection_count') or 1
                    transaction.update(doc_ref, {
                        'detection_count': current_count + 1,
                        'last_detected': firestore.SERVER_TIMESTAMP
                    })
                else:
                    transaction.set(doc_ref, {
                        'location': firestore.GeoPoint(hazard_data['lat'], hazard_data['lng']),
                        'hazard_type': hazard_type,
                        'detection_count': 1,
                        'first_detected': firestore.SERVER_TIMESTAMP,
                        'last_detected': firestore.SERVER_TIMESTAMP,
                    })
            
            update_in_transaction(transaction, doc_ref)
            
        await loop.run_in_executor(None, _transactional_update)

    @classmethod
    async def sync_session_summary(cls, session_id: str, summary: dict):
        """Finalize session in Firestore and remove from RTDB."""
        loop = asyncio.get_running_loop()
        def _sync():
            # Update Firestore
            cls.firestore_client.collection('sessions').document(session_id).update({
                'summary': summary,
                'status': 'ended'
            })
            # Remove from RTDB
            db.reference(f'live_sessions/{session_id}').delete()
            
        await loop.run_in_executor(None, _sync)

    # --- Realtime Database Operations ---

    @classmethod
    async def update_live_session(cls, session_id: str, data: dict):
        """Fire and forget non-blocking delta update to RTDB."""
        def _update():
            try:
                db.reference(f'live_sessions/{session_id}').update(data)
            except Exception as e:
                logger.warning(f"RTDB update failed for {session_id}: {e}")
        
        # Do not await the result to ensure low latency
        asyncio.get_running_loop().run_in_executor(None, _update)

    @classmethod
    async def get_guardian_id(cls, user_id: str) -> Optional[str]:
        """Fetch linked guardian with caching."""
        if user_id in _guardian_cache:
            return _guardian_cache[user_id]

        loop = asyncio.get_running_loop()
        def _fetch():
            docs = cls.firestore_client.collection('guardians').where('user_id', '==', user_id).limit(1).get()
            return docs[0].id if docs else None
            
        guardian_id = await loop.run_in_executor(None, _fetch)
        if guardian_id:
            _guardian_cache[user_id] = guardian_id
        return guardian_id

    # --- FCM Notifications ---

    @classmethod
    async def send_guardian_notification(cls, guardian_id: str, notification_type: str, data: dict) -> dict:
        """Format and dispatch FCM push to all guardian devices."""
        loop = asyncio.get_running_loop()
        
        def _fetch_tokens():
            doc = cls.firestore_client.collection('guardians').document(guardian_id).get()
            if doc.exists:
                return doc.to_dict().get('fcm_tokens', [])
            return []

        tokens = await loop.run_in_executor(None, _fetch_tokens)
        if not tokens:
            return {'sent': 0, 'failed': 0}

        # Build message
        title = "Notification"
        body = ""
        priority = "normal"
        android_config = None

        user_name = data.get('user_name', 'User')

        if notification_type == 'override':
            title = "⚠️ Alert"
            body = f"{user_name} ko rokna pada — {data.get('hazard', 'Hazard detected')}"
            priority = "high"
        elif notification_type == 'sos':
            title = "🆘 EMERGENCY"
            body = f"{user_name} ko madad chahiye!"
            priority = "high"
            android_config = messaging.AndroidConfig(
                priority='high',
                notification=messaging.AndroidNotification(
                    sound="sos_alarm",
                    default_vibrate_timings=True,
                    default_light_settings=True,
                )
            )
        elif notification_type == 'session_start':
            title = "✅ Navigation Started"
            body = f"{user_name} ne chalna shuru kiya"
        elif notification_type == 'session_end':
            distance = data.get('distance', 0)
            title = "🏠 Safe"
            body = f"{user_name} safely pahunch gaye. {distance}km"
        elif notification_type == 'battery_low':
            level = data.get('level', 0)
            title = "🔋 Battery Low"
            body = f"{user_name} ke phone mein {level}% battery bachi hai"

        message = messaging.MulticastMessage(
            tokens=tokens,
            notification=messaging.Notification(title=title, body=body),
            data={'type': notification_type},
            android=android_config
        )

        def _send():
            response = messaging.send_each_for_multicast(message)
            
            # Clean up invalid tokens
            if response.failure_count > 0:
                failed_tokens = [tokens[i] for i, resp in enumerate(response.responses) if not resp.success]
                if failed_tokens:
                    doc_ref = cls.firestore_client.collection('guardians').document(guardian_id)
                    doc_ref.update({'fcm_tokens': firestore.ArrayRemove(failed_tokens)})
            
            return {'sent': response.success_count, 'failed': response.failure_count}

        return await loop.run_in_executor(None, _send)

    # --- Auth Token Verification ---

    @classmethod
    async def verify_firebase_token(cls, token: str) -> dict:
        """Verify Firebase IdToken. Caches results for 5 minutes."""
        if token in _token_cache:
            return _token_cache[token]

        loop = asyncio.get_running_loop()
        def _verify():
            try:
                decoded = auth.verify_id_token(token)
                return decoded
            except Exception as e:
                logger.error(f"Token verification failed: {e}")
                return None

        decoded_token = await loop.run_in_executor(None, _verify)
        
        if not decoded_token:
            raise HTTPException(status_code=401, detail="Invalid Firebase Auth Token")

        _token_cache[token] = decoded_token
        return decoded_token
