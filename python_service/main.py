from __future__ import annotations

from typing import Optional
import base64
import inspect
import json
import os
import time
import asyncio

from fastapi import FastAPI
from pydantic import BaseModel, Field
from openai import AsyncOpenAI


app = FastAPI(title="Pencil Stuck Marker - Analyze API")
_STICKY_TRUE_UNTIL_BY_REGION: dict[str, float] = {}
_STICKY_TRUE_SECONDS = 60.0


class XY(BaseModel):
    x: float
    y: float


class Rect(BaseModel):
    x: float
    y: float
    w: float
    h: float


class AnalyzeRequest(BaseModel):
    request_id: str
    region_id: str
    stall_seconds: float = Field(ge=0)
    oscillation_count: int = Field(ge=0)
    anchor: XY
    region_rect: Rect
    frame_png_base64: str


class Target(BaseModel):
    region_id: str


class AnalyzeResponse(BaseModel):
    request_id: str
    intervene: bool
    style: str
    message: str
    target: Target
    cooldown_seconds: int


class CoachRequest(BaseModel):
    region_id: str
    stall_seconds: float = Field(ge=0)
    oscillation_count: int = Field(ge=0)
    anchor: XY
    user_text: str = Field(min_length=1, max_length=400)
    previous_coach_line: str | None = None


class CoachResponse(BaseModel):
    summary: str
    question: str
    next_action: str


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


async def _verify_with_vision_agents(req: AnalyzeRequest) -> Optional[bool]:
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

    llm_cls = getattr(va_openai, "ChatCompletionsLLM", None)
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

    create_response = getattr(llm, "create_response", None)
    if not callable(create_response):
        return None

    # Use explicit messages so we don't depend on agent conversation initialization.
    attempts = [
        lambda: create_response(messages=messages, stream=False),
        lambda: create_response(messages=messages),
    ]
    for attempt in attempts:
        try:
            result = attempt()
            if inspect.isawaitable(result):
                result = await result
            text = _extract_text(result)
            if not text:
                continue
            return _contains_yes(text)
        except Exception:
            continue

    return None


def _short_line(text: str, limit: int = 45) -> str:
    t = " ".join(text.strip().split())
    if len(t) <= limit:
        return t
    return t[: limit - 1].rstrip() + "…"


def _normalize_next_action(text: str) -> str:
    t = _short_line(text)
    lowered = t.lower()
    banned = ("click next", "press next", "tap next", "proceed", "continue")
    if any(token in lowered for token in banned):
        return "Read one line aloud and circle one clue."
    return t


def _coach_rule_from_user_text(req: CoachRequest) -> Optional[CoachResponse]:
    text = req.user_text.lower()
    first_turn = not (req.previous_coach_line and req.previous_coach_line.strip())

    if first_turn:
        return CoachResponse(
            summary="",
            question="",
            next_action="Try reading it out loud once.",
        )

    ack_tokens = ("ok", "okay", "got it", "i see", "yes", "yep")
    if any(token in text for token in ack_tokens):
        return CoachResponse(
            summary="",
            question="",
            next_action="Great. Does it make sense now?",
        )

    solved_tokens = ("figured out", "i got it", "got it", "solved", "understand now")
    if any(token in text for token in solved_tokens):
        return CoachResponse(
            summary="",
            question="",
            next_action="Nice. Can you explain why in one line?",
        )
    if "don't know" in text or "stuck" in text:
        return CoachResponse(
            summary="",
            question="",
            next_action="Let's start small. Underline one given.",
        )
    return None


def _coach_fallback(req: CoachRequest) -> CoachResponse:
    return CoachResponse(
        summary="",
        question="",
        next_action="Try one small step. Circle one clue.",
    )


async def _coach_with_llm(req: CoachRequest) -> Optional[CoachResponse]:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        return None
    model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
    base_url = os.getenv("OPENAI_BASE_URL")
    client = AsyncOpenAI(api_key=api_key, base_url=base_url)

    system = (
        "You are a gentle study companion. You cannot see worksheet content and must not pretend you can. "
        "Do not provide answers or solution steps. Keep the learner focused on the current problem. "
        "Return only JSON with keys summary, question, next_action. "
        "Use very short text (<=45 chars each). "
        "If previous_coach_line is empty, next_action should be one concrete micro-step on the page. "
        "If previous_coach_line exists, respond naturally to learner_text with one short coaching line in next_action "
        "(acknowledge + one check question OR one tiny next step). "
        "Avoid repetitive wording. Never mention app navigation."
    )
    user = (
        f"region={req.region_id}, stall_seconds={req.stall_seconds}, oscillation_count={req.oscillation_count}, "
        f"anchor=({req.anchor.x},{req.anchor.y}), learner_text={req.user_text!r}, "
        f"previous_coach_line={req.previous_coach_line!r}"
    )
    try:
        response = await client.chat.completions.create(
            model=model,
            response_format={"type": "json_object"},
            temperature=0.2,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        )
        content = response.choices[0].message.content or "{}"
        raw = json.loads(content)
    except Exception:
        return None

    summary = _short_line(str(raw.get("summary", "")))
    question = _short_line(str(raw.get("question", "")))
    next_action = _normalize_next_action(
        str(raw.get("next_action", "Try one small step. Circle one clue."))
    )
    return CoachResponse(summary=summary, question=question, next_action=next_action)


async def _verify_intervention(req: AnalyzeRequest) -> bool:
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
    try:
        va_decision = await asyncio.wait_for(_verify_with_vision_agents(req), timeout=1.8)
    except asyncio.TimeoutError:
        va_decision = None
        print(f"[analyze] verifier=vision_agents timeout region={req.region_id}")
    if va_decision is not None:
        print(f"[analyze] verifier=vision_agents decision={va_decision} region={req.region_id}")
        return va_decision

    print(f"[analyze] verifier=heuristic decision=True region={req.region_id}")
    return True


@app.post("/analyze", response_model=AnalyzeResponse)
async def analyze(req: AnalyzeRequest) -> AnalyzeResponse:
    raw_intervene = await _verify_intervention(req)
    now = time.monotonic()
    sticky_until = _STICKY_TRUE_UNTIL_BY_REGION.get(req.region_id, 0.0)
    if (not raw_intervene) and now < sticky_until:
        intervene = True
        print(f"[analyze] sticky=true region={req.region_id}")
    else:
        intervene = raw_intervene

    if intervene:
        _STICKY_TRUE_UNTIL_BY_REGION[req.region_id] = now + _STICKY_TRUE_SECONDS

    if intervene:
        message = "Looks like you paused here a bit."
        cooldown = 45
    else:
        message = "Looks fine for now."
        cooldown = 45

    return AnalyzeResponse(
        request_id=req.request_id,
        intervene=intervene,
        style="highlight",
        message=message,
        target=Target(region_id=req.region_id),
        cooldown_seconds=cooldown,
    )


@app.post("/coach", response_model=CoachResponse)
async def coach(req: CoachRequest) -> CoachResponse:
    rule = _coach_rule_from_user_text(req)
    if rule is not None:
        return rule
    llm_response = await _coach_with_llm(req)
    if llm_response is not None:
        return llm_response
    return _coach_fallback(req)
