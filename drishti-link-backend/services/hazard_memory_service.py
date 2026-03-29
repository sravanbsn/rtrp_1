"""
Local area hazard memory service.
Records observed hazards at GPS locations and builds a
probabilistic map of recurring hazards for predictive warnings.
"""
from __future__ import annotations

import hashlib
import math
from datetime import datetime, timezone
from typing import Optional

import structlog

from models.area_memory import AreaHazardRecord, AreaMemoryQuery

log = structlog.get_logger(__name__)

# In-memory store (replace with PostGIS / Redis geo hashes in production)
_hazard_memory: dict[str, AreaHazardRecord] = {}


def _geohash(lat: float, lng: float, precision: int = 5) -> str:
    """Simple geohash approximation using truncated coords."""
    lat_r = round(lat,  precision - 3)
    lng_r = round(lng,  precision - 3)
    return hashlib.md5(f"{lat_r},{lng_r}".encode()).hexdigest()[:8]


def _haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance in metres."""
    R = 6_371_000
    φ1, φ2 = math.radians(lat1), math.radians(lat2)
    dφ = math.radians(lat2 - lat1)
    dλ = math.radians(lng2 - lng1)
    a = math.sin(dφ / 2) ** 2 + math.cos(φ1) * math.cos(φ2) * math.sin(dλ / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


class HazardMemoryService:
    """Learns recurring hazards from observed events."""

    async def record_observation(
        self,
        lat:         float,
        lng:         float,
        hazard_type: str,
        pc_score:    float,
    ) -> AreaHazardRecord:
        area_id = _geohash(lat, lng)
        key     = f"{area_id}:{hazard_type}"
        now     = datetime.now(timezone.utc)
        hour    = now.hour

        if key in _hazard_memory:
            record = _hazard_memory[key]
            # EMA update
            n = record.observation_count + 1
            record.avg_pc_score    = ((record.avg_pc_score * (n - 1)) + pc_score) / n
            record.observation_count = n
            record.last_observed_at  = now
            if hour not in record.peak_hours:
                record.peak_hours.append(hour)
            record.confidence_score = min(1.0, n / 20.0)
        else:
            record = AreaHazardRecord(
                area_id=area_id,
                hazard_type=hazard_type,
                lat=lat, lng=lng,
                avg_pc_score=pc_score,
                peak_hours=[hour],
                plain_language=f"Recurring {hazard_type} in this area.",
            )
            _hazard_memory[key] = record

        log.debug(
            "hazard_memory.recorded",
            area_id=area_id,
            hazard_type=hazard_type,
            count=record.observation_count,
            confidence=record.confidence_score,
        )
        return record

    async def query_nearby(self, query: AreaMemoryQuery) -> list[AreaHazardRecord]:
        """Return hazards within radius_m of query point."""
        results = []
        for record in _hazard_memory.values():
            dist = _haversine_m(query.lat, query.lng, record.lat, record.lng)
            if (
                dist <= query.radius_m
                and record.confidence_score >= query.min_confidence
                and record.active
            ):
                results.append(record)
        results.sort(key=lambda r: r.avg_pc_score, reverse=True)
        return results[: query.limit]

    async def get_area_stats(self, lat: float, lng: float) -> dict:
        area_id = _geohash(lat, lng)
        area_records = [
            r for r in _hazard_memory.values()
            if r.area_id == area_id
        ]
        return {
            "area_id":       area_id,
            "hazard_count":  len(area_records),
            "hazards":       [r.hazard_type for r in area_records],
            "max_avg_pc":    max((r.avg_pc_score for r in area_records), default=0.0),
        }
