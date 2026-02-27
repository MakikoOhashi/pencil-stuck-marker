from __future__ import annotations

from typing import Optional
import base64
import inspect
import json
import os

from fastapi import FastAPI
from pydantic import BaseModel, Field
from openai import AsyncOpenAI


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
    solved_tokens = ("figured out", "i got it", "got it", "solved", "understand now")
    if any(token in text for token in solved_tokens):
        return CoachResponse(
            summary="Nice, you got it.",
            question="Want a quick self-check?",
            next_action="Say in one sentence why it works.",
        )
    if "don't know" in text or "stuck" in text:
        return CoachResponse(
            summary="Makes sense to feel stuck.",
            question="Start from givens first?",
            next_action="Underline one given condition.",
        )
    return None


def _coach_fallback(req: CoachRequest) -> CoachResponse:
    summary = "You paused for a bit here."
    if req.oscillation_count >= 3:
        summary = "You may be rewriting repeatedly."
    return CoachResponse(
        summary=summary,
        question="Try one tiny step now?",
        next_action="Read one line aloud and circle one clue.",
    )


async def _coach_with_llm(req: CoachRequest) -> Optional[CoachResponse]:
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        return None
    model = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
    base_url = os.getenv("OPENAI_BASE_URL")
    client = AsyncOpenAI(api_key=api_key, base_url=base_url)

    system = (
        "You are a study companion. You cannot see worksheet content and must not pretend you can. "
        "Never provide answers, solutions, or problem explanations. "
        "Return only JSON with keys summary, question, next_action. "
        "Each value must be one short sentence (<=45 chars). "
        "question must be yes/no or two-choice style. "
        "next_action must be one concrete page action (read aloud, circle, underline, restate). "
        "Never mention app navigation (e.g., click next / continue)."
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

    summary = _short_line(str(raw.get("summary", "You paused for a bit here.")))
    question = _short_line(str(raw.get("question", "Try one tiny step now?")))
    next_action = _normalize_next_action(
        str(raw.get("next_action", "Circle one clue and restate the goal."))
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
    va_decision = await _verify_with_vision_agents(req)
    if va_decision is not None:
        print(f"[analyze] verifier=vision_agents decision={va_decision} region={req.region_id}")
        return va_decision

    print(f"[analyze] verifier=heuristic decision=True region={req.region_id}")
    return True


@app.post("/analyze", response_model=AnalyzeResponse)
async def analyze(req: AnalyzeRequest) -> AnalyzeResponse:
    intervene = await _verify_intervention(req)
    if intervene:
        message = "Looks like you paused here a bit."
        cooldown = 45
    else:
        message = "Looks fine for now."
        cooldown = 15

    return AnalyzeResponse(
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
