from __future__ import annotations

from typing import Optional
import base64
import inspect
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


def _contains_yes(text: str) -> bool:
    normalized = text.strip().lower()
    return normalized.startswith("yes") or " yes" in normalized


def _extract_text(obj: object) -> str:
    if obj is None:
        return ""
    if isinstance(obj, str):
        return obj
    # Typical SDK response wrappers may expose `.text` or `.content`.
    for attr in ("text", "content", "message"):
        value = getattr(obj, attr, None)
        if isinstance(value, str):
            return value
    return str(obj)


def _verify_with_vision_agents(req: AnalyzeRequest) -> Optional[bool]:
    """
    Returns:
      True/False when Vision Agents SDK check succeeded,
      None when unavailable / not configured.
    """
    api_key = os.getenv("OPENAI_API_KEY")
    model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
    base_url = os.getenv("OPENAI_BASE_URL")
    if not api_key:
        return None

    try:
        from vision_agents.plugins import openai as va_openai  # type: ignore
    except Exception:
        return None

    llm_cls = getattr(va_openai, "ChatCompletionsVLM", None)
    if llm_cls is None:
        return None

    kwargs = {"model": model, "api_key": api_key}
    if base_url:
        kwargs["base_url"] = base_url
    try:
        llm = llm_cls(**kwargs)
    except Exception:
        return None

    prompt = (
        "You are a visual verifier for learning intervention. "
        "Given one screenshot and region metadata, answer strictly YES or NO: "
        "Should the app show a gentle nudge now? "
        f"stall_seconds={req.stall_seconds}, oscillation_count={req.oscillation_count}, "
        f"region_rect=({req.region_rect.x},{req.region_rect.y},{req.region_rect.w},{req.region_rect.h})."
    )

    image_url = f"data:image/png;base64,{req.frame_png_base64}"
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {"type": "image_url", "image_url": {"url": image_url}},
            ],
        }
    ]

    simple_response = getattr(llm, "simple_response", None)
    if not callable(simple_response):
        return None

    # Try call shapes defensively to match SDK wrapper evolution.
    attempts = [
        lambda: simple_response(messages=messages),
        lambda: simple_response(text=prompt, messages=messages),
        lambda: simple_response(prompt),
    ]
    for attempt in attempts:
        try:
            result = attempt()
            if inspect.isawaitable(result):
                # Keep endpoint sync for Day1; async SDK call can be added in Day2.
                return None
            text = _extract_text(result)
            if not text:
                continue
            return _contains_yes(text)
        except Exception:
            continue

    return None


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

    # Vision Agents SDK path:
    # If configured, use VA decision as final verifier.
    va_decision = _verify_with_vision_agents(req)
    if va_decision is not None:
        print(f"[analyze] verifier=vision_agents decision={va_decision} region={req.region_id}")
        return va_decision

    print(f"[analyze] verifier=heuristic decision=True region={req.region_id}")
    return True


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
