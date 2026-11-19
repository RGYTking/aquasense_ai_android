from datetime import datetime, timezone
from pathlib import Path
from typing import Literal, Optional

import joblib
import pandas as pd
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field


# ============================================================
# AquaSense AI Backend
# Option B: Flutter APK selects profile -> Render -> ESP8266 -> OLED
#
# Existing routes are preserved:
#   GET  /
#   POST /api/analyze
#   POST /api/sensors
#   GET  /api/sensors
#   POST /api/samples/capture
#   GET  /api/samples
#   GET  /api/samples/compare
#   DELETE /api/samples
#
# New routes:
#   POST /api/profile/select
#   GET  /api/profile/current
# ============================================================

app = FastAPI(title="AquaSense AI API")


# Load the ML model relative to this Python file so Render does not
# depend on an unexpected working directory.
MODEL_PATH = Path(__file__).resolve().parent / "water_quality_model.pkl"

try:
    model = joblib.load(MODEL_PATH)
    print("Water quality model loaded:", MODEL_PATH)
    if hasattr(model, "classes_"):
        print("Model classes:", model.classes_)
except Exception as exc:
    raise RuntimeError(
        f"Could not load ML model at {MODEL_PATH}. "
        "Ensure water_quality_model.pkl is included in the backend deployment."
    ) from exc


# The ESP8266 must POST sensor data within this period to be considered online.
DEVICE_STALE_AFTER_SECONDS = 20

# Profiles are considered current for 5 minutes after being set.
PROFILE_STALE_AFTER_SECONDS = 300

# Last physical sensor payload received from the ESP8266.
# This is retained separately from the APK-selected profile.
latest_sensor_data: Optional[dict] = None

# Current profile selected/completed by the Flutter APK.
current_selected_profile: Optional[dict] = None

water_sample_history = []


# ============================================================
# The six profiles must match the Flutter APK and OLED values.
# Flow rate is 0.0 for all six profiles, as agreed.
# ============================================================

WATER_PROFILES = {
    "Clean Water": {
        "profile_name": "Clean Water",
        "ph": 7.2,
        "tds": 110.0,
        "turbidity": 2.0,
        "flow_rate": 0.0,
    },
    "Normal Water": {
        "profile_name": "Normal Water",
        "ph": 7.5,
        "tds": 160.0,
        "turbidity": 3.0,
        "flow_rate": 0.0,
    },
    "High Turbidity": {
        "profile_name": "High Turbidity",
        "ph": 7.2,
        "tds": 110.0,
        "turbidity": 10.0,
        "flow_rate": 0.0,
    },
    "Low pH": {
        "profile_name": "Low pH",
        "ph": 5.6,
        "tds": 110.0,
        "turbidity": 2.0,
        "flow_rate": 0.0,
    },
    "High pH": {
        "profile_name": "High pH",
        "ph": 9.0,
        "tds": 110.0,
        "turbidity": 2.0,
        "flow_rate": 0.0,
    },
    "High TDS": {
        "profile_name": "High TDS",
        "ph": 7.2,
        "tds": 650.0,
        "turbidity": 2.0,
        "flow_rate": 0.0,
    },
}


# ============================================================
# Request models
# ============================================================

class WaterQualityData(BaseModel):
    ph: float = Field(ge=0, le=14)
    tds: float = Field(ge=0)
    turbidity: float = Field(ge=0)
    flow_rate: float = Field(default=0.0, ge=0)


class SensorData(BaseModel):
    ph: float = Field(ge=0, le=14)
    tds: float = Field(ge=0)
    turbidity: float = Field(ge=0)
    flow_rate: float = Field(default=0.0, ge=0)


class SampleCaptureRequest(BaseModel):
    sample_type: Literal["Clean water", "Tap/Borewell water", "Dirty water"]


class ProfileSelectionRequest(BaseModel):
    profile_name: Literal[
        "Clean Water",
        "Normal Water",
        "High Turbidity",
        "Low pH",
        "High pH",
        "High TDS",
    ]


class ProfileUpdateRequest(BaseModel):
    profile_name: str = Field(min_length=1)
    ph: float = Field(ge=0, le=14)
    tds: float = Field(ge=0)
    turbidity: float = Field(ge=0)
    flow_rate: Optional[float] = None


# ============================================================
# Time and device status helpers
# ============================================================

def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _parse_timestamp(value):
    if not value:
        return None

    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except (TypeError, ValueError, AttributeError):
        return None


def _get_live_flow_rate() -> Optional[float]:
    """
    Obtain flow_rate from the existing live hardware sensor data if online.
    Distinguishes an actual zero-flow reading (0.0) from an unavailable measurement (None).
    Does not fabricate a flow value.
    """
    if latest_sensor_data is None:
        return None

    received_at = _parse_timestamp(latest_sensor_data.get("received_at"))
    if received_at is None:
        return None

    age = max(0.0, (_utc_now() - received_at).total_seconds())
    if age > DEVICE_STALE_AFTER_SECONDS:
        return None

    val = latest_sensor_data.get("flow_rate")
    if val is not None and isinstance(val, (int, float)):
        return float(val)
    return None


def _get_active_profile() -> Optional[dict]:
    """
    Returns the latest completed profile if available and not stale.
    Dynamically updates flow_rate from live hardware sensor data.
    Returns None if no profile has been completed or if the profile is stale.
    """
    if current_selected_profile is None:
        return None

    updated_at = _parse_timestamp(
        current_selected_profile.get("updated_at")
        or current_selected_profile.get("selected_at")
    )
    if updated_at is None:
        return None

    age = max(0.0, (_utc_now() - updated_at).total_seconds())
    if age > PROFILE_STALE_AFTER_SECONDS:
        return None

    profile = dict(current_selected_profile)
    profile["flow_rate"] = _get_live_flow_rate()
    return profile


def _device_status() -> dict:
    if latest_sensor_data is None:
        return {
            "status": "no_data",
            "device_online": False,
            "data": None,
            "last_seen": None,
            "age_seconds": None,
            "stale_after_seconds": DEVICE_STALE_AFTER_SECONDS,
        }

    received_at = _parse_timestamp(latest_sensor_data.get("received_at"))

    if received_at is None:
        return {
            "status": "stale",
            "device_online": False,
            "data": None,
            "last_seen": latest_sensor_data.get("received_at"),
            "age_seconds": None,
            "stale_after_seconds": DEVICE_STALE_AFTER_SECONDS,
        }

    age = max(0.0, (_utc_now() - received_at).total_seconds())
    online = age <= DEVICE_STALE_AFTER_SECONDS

    active_prof = _get_active_profile()

    displayed_data = (
        active_prof
        if active_prof is not None
        else {
            "profile_name": "Live Sensor Readings",
            "ph": latest_sensor_data["ph"],
            "tds": latest_sensor_data["tds"],
            "turbidity": latest_sensor_data["turbidity"],
            "flow_rate": latest_sensor_data["flow_rate"],
        }
    )

    return {
        "status": "connected" if online else "stale",
        "device_online": online,
        "data": displayed_data,
        "last_seen": latest_sensor_data.get("received_at"),
        "age_seconds": round(age, 1),
        "stale_after_seconds": DEVICE_STALE_AFTER_SECONDS,
        "sensor_data": latest_sensor_data,
        "selected_profile": current_selected_profile,
    }


def _current_readings() -> Optional[dict]:
    """Return the profile currently selected by the APK, if one exists."""
    if current_selected_profile is not None:
        return dict(current_selected_profile)
    return None


# ============================================================
# Parameter analysis
# ============================================================

def get_parameter_analysis(data: WaterQualityData) -> dict:
    findings = []
    recommendations = []

    # pH Analysis
    if data.ph < 6.5:
        findings.append(
            f"Low pH detected ({data.ph:.1f}): Water is acidic "
            "(below 6.5–8.5 reference range)."
        )
        recommendations.append(
            "Acidic water can cause metal pipe corrosion and leaching. "
            "A calcite neutralizer or suitable pH correction system is recommended."
        )
    elif data.ph > 8.5:
        findings.append(
            f"High pH detected ({data.ph:.1f}): Water is alkaline "
            "(above 6.5–8.5 reference range)."
        )
        recommendations.append(
            "Highly alkaline water can cause pipe scaling and bitter taste. "
            "A suitable pH correction system is recommended."
        )
    else:
        findings.append(
            f"pH level ({data.ph:.1f}) is within standard reference range (6.5–8.5)."
        )

    # TDS Analysis
    if data.tds > 500:
        findings.append(
            f"Elevated TDS detected ({data.tds:.0f} mg/L): "
            "Exceeds 500 mg/L threshold."
        )
        recommendations.append(
            "Elevated TDS indicates excessive dissolved minerals and salts. "
            "A Reverse Osmosis (RO) purification system is recommended."
        )
    else:
        findings.append(
            f"TDS ({data.tds:.0f} mg/L) is within the safe 500 mg/L threshold."
        )

    # Turbidity Analysis
    if data.turbidity > 5.0:
        findings.append(
            f"Elevated Turbidity detected ({data.turbidity:.1f} NTU): "
            "Exceeds 5.0 NTU threshold."
        )
        recommendations.append(
            "Elevated turbidity indicates excessive suspended particles, "
            "silt, or sediment. Multi-stage sediment pre-filtration is recommended."
        )
    else:
        findings.append(
            f"Turbidity ({data.turbidity:.1f} NTU) is within the safe 5.0 NTU threshold."
        )

    if recommendations:
        purification_rec = "\n\n".join(recommendations)
    else:
        purification_rec = (
            "No issue detected in the measured parameters. "
            "Continue routine monitoring and maintain clean storage and filtration equipment."
        )

    return {
        "parameter_findings": findings,
        "purification_recommendation": purification_rec,
    }


# ============================================================
# Root
# ============================================================

@app.get("/")
async def root():
    return {
        "message": "AquaSense AI Backend is running",
        "status": "online",
        "profile_control": "enabled",
    }


# ============================================================
# Profile Synchronization Endpoints
# POST /api/profile/current -> Flutter posts completed active water profile
# POST /api/profile/select  -> Legacy/alias route for selecting profile by name
# GET  /api/profile/current -> ESP8266/clients fetch active water profile
# ============================================================

@app.post("/api/profile/current")
async def update_current_water_profile(request: ProfileUpdateRequest):
    global current_selected_profile

    # Obtain flow_rate from live hardware sensor data (not fabricated)
    live_flow = _get_live_flow_rate()

    timestamp = _utc_now().isoformat()
    current_selected_profile = {
        "profile_name": request.profile_name,
        "ph": request.ph,
        "tds": request.tds,
        "turbidity": request.turbidity,
        "flow_rate": live_flow,
        "updated_at": timestamp,
        "selected_at": timestamp,
        "source": "Flutter APK",
    }

    print(
        f"Profile updated via POST /api/profile/current: {request.profile_name} (flow_rate={live_flow})"
    )

    return {
        "status": "updated",
        "message": "Water profile synchronized successfully.",
        "profile": {
            "profile_name": current_selected_profile["profile_name"],
            "ph": current_selected_profile["ph"],
            "tds": current_selected_profile["tds"],
            "turbidity": current_selected_profile["turbidity"],
            "flow_rate": current_selected_profile["flow_rate"],
            "updated_at": current_selected_profile["updated_at"],
        },
    }


@app.post("/api/profile/select")
async def select_water_profile(request: ProfileSelectionRequest):
    global current_selected_profile

    selected = WATER_PROFILES.get(request.profile_name)

    if selected is None:
        raise HTTPException(status_code=400, detail="Unknown water profile.")

    live_flow = _get_live_flow_rate()
    timestamp = _utc_now().isoformat()

    current_selected_profile = {
        **selected,
        "flow_rate": live_flow,
        "selected_at": timestamp,
        "updated_at": timestamp,
        "source": "Flutter APK",
    }

    print(
        f"Profile selected via POST /api/profile/select: {request.profile_name} (flow_rate={live_flow})"
    )

    return {
        "status": "selected",
        "message": "Water profile selected successfully.",
        "profile": current_selected_profile,
    }


@app.get("/api/profile/current")
async def get_current_water_profile():
    active = _get_active_profile()

    if active is None:
        raise HTTPException(
            status_code=404,
            detail="No active completed profile available.",
        )

    return {
        "profile_name": active["profile_name"],
        "ph": active["ph"],
        "tds": active["tds"],
        "turbidity": active["turbidity"],
        "flow_rate": active["flow_rate"],
        "updated_at": active.get("updated_at") or active.get("selected_at"),
        "source": active.get("source", "Flutter APK"),
    }


# ============================================================
# AI water analysis
# ============================================================

@app.post("/api/analyze")
async def analyze_water(data: WaterQualityData):
    try:
        input_data = pd.DataFrame([{
            "pH": data.ph,
            "TDS_ppm": data.tds,
            "Turbidity_NTU": data.turbidity,
        }])

        prediction = model.predict(input_data)[0]

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail="Water quality model prediction failed.",
        ) from exc

    # Enforce threshold rule consistency for low/high pH, high TDS,
    # and high turbidity.
    if (
        data.ph < 6.5
        or data.ph > 8.5
        or data.tds > 500
        or data.turbidity > 5.0
    ):
        assessment = "Unsafe"
    else:
        assessment = "Safe" if prediction == 1 else "Unsafe"

    details = get_parameter_analysis(data)

    return {
        "ph": data.ph,
        "tds": data.tds,
        "turbidity": data.turbidity,
        "flow_rate": data.flow_rate,
        "assessment": assessment,
        "analysis_type": "ML prediction with rule-based guidance",
        "parameter_findings": details["parameter_findings"],
        "purification_recommendation": details["purification_recommendation"],
    }


# ============================================================
# ESP8266 sensor upload (existing route preserved)
# POST /api/sensors
#
# This endpoint records that the physical ESP8266 is alive.
# Its payload is kept separately from the APK-selected profile.
# ============================================================

@app.post("/api/sensors")
async def receive_sensor_data(data: SensorData):
    global latest_sensor_data

    latest_sensor_data = {
        "ph": data.ph,
        "tds": data.tds,
        "turbidity": data.turbidity,
        "flow_rate": data.flow_rate,
        "received_at": _utc_now().isoformat(),
    }

    return {
        "status": "received",
        "device_online": True,
        "data": latest_sensor_data,
    }


# ============================================================
# Flutter checks device status and receives the selected profile
# GET /api/sensors
# ============================================================

@app.get("/api/sensors")
async def get_sensor_data():
    return _device_status()


# ============================================================
# Sample capture
# Captures the same selected profile shown in Flutter and OLED.
# Requires a fresh ESP8266 heartbeat, as before.
# ============================================================

@app.post("/api/samples/capture")
async def capture_water_sample(request: SampleCaptureRequest):
    status = _device_status()

    if not status["device_online"] or status["data"] is None:
        raise HTTPException(
            status_code=409,
            detail="No fresh sensor readings available. Connect the device first.",
        )

    data = status["data"]

    sample = {
        "sample_id": len(water_sample_history) + 1,
        "sample_type": request.sample_type,
        "captured_at": _utc_now().isoformat(),
        "profile_name": data.get("profile_name", "Live Sensor Readings"),
        "ph": data["ph"],
        "tds": data["tds"],
        "turbidity": data["turbidity"],
        "flow_rate": data["flow_rate"],
    }

    water_sample_history.append(sample)

    return {
        "status": "captured",
        "message": "Water sample recorded successfully",
        "sample": sample,
    }


@app.get("/api/samples")
async def get_water_samples():
    return {
        "count": len(water_sample_history),
        "samples": water_sample_history,
    }


@app.get("/api/samples/compare")
async def compare_water_samples():
    if not water_sample_history:
        raise HTTPException(
            status_code=404,
            detail="No water samples recorded yet.",
        )

    return {
        "count": len(water_sample_history),
        "comparison": water_sample_history,
    }


@app.delete("/api/samples")
async def clear_water_samples():
    deleted_count = len(water_sample_history)
    water_sample_history.clear()

    return {
        "status": "cleared",
        "deleted": deleted_count,
    }
