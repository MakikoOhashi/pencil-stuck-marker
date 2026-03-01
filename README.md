# Pencil Stuck Marker

🎥 Demo video: https://youtu.be/YvEoh3dscvs

An iPad learning companion prototype that detects writing stalls and offers a gentle, spatial nudge without solving problems.

## Current Status (2026-03-01)
- Swift -> Python `/analyze` -> Swift loop is working.
- Vision Agents SDK path is integrated in Python (`vision_agents.plugins.openai`) with timeout fallback.
- Coach chat is integrated (`/coach`) with short, non-answer coaching responses.
- Race-condition hardening is applied (request-id matching, cooldown, UI phase guards).
- Demo worksheet is bundled and shown by default: `cube_worksheet.pdf`.

## What This Prototype Does
- Captures PencilKit writing over a worksheet PDF.
- Detects local stuck candidates (`elapsedSeconds >= 10`).
- Sends a screenshot + region metadata to Python `/analyze`.
- Uses Vision Agents SDK as visual verifier when configured.
- Shows a small anchored bubble and optional coach chat.
- Does not solve the worksheet and does not parse worksheet meaning.

## Non-Goals
- No OCR-based solving.
- No answer generation.
- No semantic understanding of worksheet content.

## Architecture

### iOS (SwiftUI + PencilKit)
- PDF background rendering (`cube_worksheet.pdf` bundled resource).
- Stroke tracking and local stuck-candidate detection.
- Intervention UI (bubble -> Talk with coach -> short chat).
- Request-id based response validation and UI state protection.

### Python (FastAPI)
- `/analyze`: verify intervention necessity.
  - Heuristic gate first.
  - Vision Agents SDK check with timeout.
  - Sticky stabilization to avoid True/False flicker.
- `/coach`: short coaching line generation with anti-answer guardrails.

### Vision Agents SDK
- Used in Python for final visual verification (`YES/NO`) on frame + metadata.
- If unavailable/slow, service falls back safely to heuristic behavior.

## Runtime Data Flow
1. Swift detects stuck candidate locally.
2. Swift sends `/analyze` with `request_id`, frame, and region metrics.
3. Python returns decision + same `request_id`.
4. Swift applies response only if `request_id` matches current active request.
5. User can open coach panel and send short text.

## API Contract

### POST `/analyze`
Request
```json
{
  "request_id": "uuid-string",
  "region_id": "ALL",
  "stall_seconds": 12.4,
  "oscillation_count": 0,
  "anchor": { "x": 812, "y": 534 },
  "region_rect": { "x": -10000, "y": -10000, "w": 20000, "h": 20000 },
  "frame_png_base64": "..."
}
```

Response
```json
{
  "request_id": "same-uuid-string",
  "intervene": true,
  "style": "highlight",
  "message": "Looks like you paused here a bit.",
  "target": { "region_id": "ALL" },
  "cooldown_seconds": 45
}
```

### POST `/coach`
Request
```json
{
  "region_id": "ALL",
  "stall_seconds": 15,
  "oscillation_count": 0,
  "anchor": { "x": 812, "y": 534 },
  "user_text": "I understood.",
  "previous_coach_line": "Try reading it out loud once."
}
```

Response
```json
{
  "summary": "",
  "question": "",
  "next_action": "Great. Does it make sense now?"
}
```

## Stability Hardening Applied
- `intervene=false` does not force-close user-opened UI.
- Analyze responses are applied only when request-id matches active state.
- Bubble/coach-open phases block retrigger and auto-close races.
- Watchdog/timer cancellation is state-aware.
- `localhost` was replaced with `127.0.0.1` to avoid `::1` connection refusal.
- Analyze timeout tuned:
  - Swift request timeout: 8s
  - Python Vision Agents sub-timeout: 1.8s
- Sticky true window in Python to reduce rapid decision flip.

## Project Structure
- iOS app: `PencilStuckMarker/PencilStuckMarker`
- Python backend: `python_service`
- Worksheet resource: `PencilStuckMarker/PencilStuckMarker/Resources/cube_worksheet.pdf`

## Requirements
- Xcode 15+ (tested with iOS Simulator runtime 26.2)
- Python 3.11 recommended
- macOS with iOS Simulator

## How to Run (Prototype)
1. Clone this repository.
2. Open `PencilStuckMarker/PencilStuckMarker.xcodeproj` in Xcode.
3. Run Python service:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r python_service/requirements.txt
set -a; source .env; set +a
uvicorn python_service.main:app --host 127.0.0.1 --port 8000 --reload --reload-dir python_service
```
4. Build and run on iPad Simulator or device.

## Setup

### 1) Python backend
```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
pip install -r python_service/requirements.txt
```

Create `.env` (project root):
```bash
OPENAI_API_KEY=YOUR_KEY
# Optional OpenAI-compatible endpoint (example: Gemini OpenAI-compatible)
OPENAI_BASE_URL="https://generativelanguage.googleapis.com/v1beta/openai"
OPENAI_MODEL="gemini-2.0-flash"
```

Install Vision Agents OpenAI plugin if missing:
```bash
pip install vision-agents
pip install vision-agents-plugins-openai
```

Run server:
```bash
set -a; source .env; set +a
uvicorn python_service.main:app --host 127.0.0.1 --port 8000 --reload --reload-dir python_service
```

### 2) iOS app
```bash
open PencilStuckMarker/PencilStuckMarker.xcodeproj
```
- Run `PencilStuckMarker` on iPad Simulator.
- Worksheet PDF is shown by default.

## Demo Script (Submission)
1. Start backend (`uvicorn ... --host 127.0.0.1 --port 8000`).
2. Launch app in Simulator.
3. Write on worksheet and pause for ~10s.
4. Confirm bubble appears near anchor.
5. Tap bubble -> `Talk with coach`.
6. Send short message (e.g., `I understood.`) and confirm short coaching response.

## Expected Limitations During Demo
Note: The current prototype may not handle edge-case inputs consistently.

## Troubleshooting

### `Connection refused` to `::1.8000`
- Cause: IPv6 localhost mismatch.
- Fix: app uses `127.0.0.1`; run backend on `--host 127.0.0.1`.

### `/analyze` timeout (`NSURLErrorDomain -1001`)
- Ensure backend is running.
- Verify API key/env loaded before `uvicorn`.
- Vision path is timeboxed; fallback should still return quickly.

### `Task was destroyed but it is pending!` from vision_agents
- Usually non-fatal cleanup warning from plugin internals.
- Service should still return response/fallback.

### Keyboard AutoLayout warnings (`UIViewAlertForUnsatisfiableConstraints`)
- Intermittent system keyboard warning in Simulator.
- Usually not the root cause of intervention pipeline issues.

## Safety / Product Constraints
- Coaching is intentionally short.
- The system should not output worksheet answers.
- Guidance remains behavior-based and optional.

## License
Prototype / hackathon project.
