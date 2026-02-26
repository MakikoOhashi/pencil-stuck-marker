from __future__ import annotations

from typing import Optional
import base64
import os

from fastapi import FastAPI
from pydantic import BaseModel, Field


app = FastAPI(title="Pencil Stuck Marker - Analyze API")


class XY(BaseModel):
    x: float
    y: float


class Rect(BaseModel):
    x: float
    y: float
    w: float
    h: float


class AnalyzeRequest(BaseModel):
    region_id: str
    stall_seconds: float = Field(ge=0)
    oscillation_count: int = Field(ge=0)
    anchor: XY
    region_rect: Rect
    frame_png_base64: str


class Target(BaseModel):
    region_id: str


class AnalyzeResponse(BaseModel):
    intervene: bool
    style: str
    message: str
    target: Target
    cooldown_seconds: int


def _verify_intervention(req: AnalyzeRequest) -> bool:
    # Day1 baseline rule: only consider intervention after meaningful stall/oscillation.
    heuristic_flag = req.stall_seconds >= 10 or req.oscillation_count >= 3
    if not heuristic_flag:
        return False

    # Validate image payload exists (future: send this to Vision Agents SDK for final yes/no).
    if not req.frame_png_base64:
        return False
    try:
        base64.b64decode(req.frame_png_base64, validate=True)
    except Exception:
        return False

    # Optional hook for Vision Agents SDK integration.
    # If enabled and importable, this function is the place to call the agent and replace the heuristic return.
    if os.getenv("USE_VISION_AGENTS", "0") == "1":
        _ = _try_vision_agents_verify(req)

    return True


def _try_vision_agents_verify(req: AnalyzeRequest) -> Optional[bool]:
    try:
        import vision_agents  # type: ignore  # noqa: F401
    except Exception:
        return None

    # TODO: wire actual Vision Agents SDK call for one-frame verification.
    # This placeholder keeps Day1 endpoint stable while VA setup is finalized.
    return None


@app.post("/analyze", response_model=AnalyzeResponse)
def analyze(req: AnalyzeRequest) -> AnalyzeResponse:
    intervene = _verify_intervention(req)
    if intervene:
        message = "ここで少し止まってるみたい"
        cooldown = 45
    else:
        message = "今は様子見でよさそう"
        cooldown = 15

    return AnalyzeResponse(
        intervene=intervene,
        style="highlight",
        message=message,
        target=Target(region_id=req.region_id),
        cooldown_seconds=cooldown,
    )
