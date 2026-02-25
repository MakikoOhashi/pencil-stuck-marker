# Pencil Stuck Marker (WIP)

Experimental iPad app for detecting writing stalls with Apple Pencil
and visually marking "stuck" regions in real time.

Status: Early prototype (PencilKit input validation)

---

# Project: (TBD) — PDF Study Companion (Prototype)

> A PDF + Apple Pencil study companion that **detects when a learner is stuck** and gently **nudges attention** with spatial annotations.  
> It does **not** solve the problem or "understand" the content via OCR.

## Why this exists
On iPad, many learners study by writing directly on PDFs.  
This prototype focuses on the *process*, not the *answer*:
- Detect "stall / hesitation" from pen interaction patterns
- Surface a gentle, optional intervention near where the learner paused
- Keep the learner in control (no forced tutoring)

## Core principles
- **No OCR**: We do not parse the PDF text or solve problems.
- **No answers**: The AI does not provide solutions.
- **Spatial > Chat**: Guidance is anchored to a location (arrow/highlight + small bubble), not a fixed chat box.
- **Explain the *why*** (behavior-based): "You paused here / rewrote here", not "because the dice face is X".

## MVP (Hackathon Week Scope)
### Input
- PDF import (Files / Share → open in app)
- Apple Pencil handwriting on top of the PDF (PencilKit overlay)

### Setup mode (manual, fast)
- User marks 2–10 "answer regions" as rectangles (Regions)
  - Rationale: avoids OCR; still supports arbitrary PDFs

### Study mode
- Track per-region writing activity:
  - last stroke timestamp
  - stroke delta (progress)
  - erase count / write-erase oscillation
- Detect stuck candidates:
  - **Inactivity stall**: no progress for N seconds
  - **Oscillation**: write/erase 繰り返し in short window
- When a stuck candidate is detected:
  - Ask Vision Agent to **verify** (1-frame check)
  - If verified: show a small 💭 bubble near the last activity point
    - "困ってる？声で考えてみる？" / "ここで止まってるみたい"
  - User taps bubble to:
    - "ヒント（視覚強調）" (level up annotation)
    - "今は大丈夫" (dismiss)

### Intervention levels (keep it minimal)
- Level 1: highlight / arrow + short bubble (behavior-based)
- Level n: TBD

---

## What the app "recognizes" (explicitly)
We recognize:
- **Where** the learner is working (Region / last pen location)
- **How** the learner is working (stall / oscillation / low progress)

We do NOT recognize:
- Problem text meaning
- Correct answers
- Diagram semantics (dice faces, geometry labels, etc.)

---

## Architecture Overview

### iPad App (Swift / SwiftUI)
Responsibilities:
- PDF import & rendering (PDF background)
- Pencil writing capture (PencilKit)
- Region creation UI (rectangles)
- Event logging (strokes/eraser/time)
- Local, fast heuristics → **stuck candidate detection**
- Render spatial interventions (highlight/arrow/bubble UI)

### Python Service (the "Teacher Brain", not a solver)
Python is used for:
- Aggregating interaction events into features
- Scoring stuck likelihood + cooldown logic
- Selecting response templates (behavior-based)
- Producing **intervention commands**:
  - target region / anchor point
  - highlight shape, arrow geometry
  - bubble text (template-based)
  - optional follow-up prompts (confirmations / next action)

> Python does not need OCR.  
> It reasons on interaction features + optional visual verification results.

### Vision Agents SDK (visual verifier / "second opinion")
Use case (minimal + high leverage):
- **Not** continuous per-frame analysis
- Called only when local heuristics detect a stuck candidate

What it receives:
- 1 frame snapshot (current PDF + handwriting)
- candidate region rectangle / anchor point
- local features summary (stall seconds, oscillation count, etc.)

What it returns:
- `intervene: yes/no/uncertain`
- optional: confidence score or suggested anchor refinement

Why this placement:
- Satisfies the "must use Vision Agents SDK" requirement meaningfully
- Avoids OCR / heavy CV
- Prevents false positives ("don't interrupt when the learner is just thinking normally")

---

## Data Flow (Decision Pipeline)
1. Swift collects pen events + region states continuously
2. Swift computes lightweight features + detects **stuck candidate**
3. Swift requests Vision Agent verification (1 snapshot)
4. If verified:
   - Swift calls Python to generate an intervention command (or Python is called earlier; either is fine)
5. Swift renders the intervention near the anchor point
6. User taps bubble:
   - update level / dismiss
   - (optional) send a short "user intent" event back to Python

---

## Safety / UX Constraints
- No forced popups: only a small bubble; user opts in
- Cooldown to avoid nagging
- All copy is behavior-based:
  - "ここで止まってるみたい"
  - "書いて→消してを繰り返してるかも"
  - "声で考えてみる？"
- No claims of correctness; no answer-giving

---

## Out of scope (for hackathon week)
- OCR / PDF text parsing
- Auto-detecting answer boxes from the PDF
- Full chat tutor
- Domain-specific reasoning (dice / geometry semantics)
- Multi-page learning analytics

---

## Demo Script (for judges)
1. Import a PDF worksheet
2. Mark two Regions quickly (Setup)
3. Start writing with Apple Pencil
4. Pause at a hard problem (simulate being stuck)
5. App detects the stuck point
6. Tap bubble → stronger highlight/arrow appears
7. Learner resumes writing (intervention disappears or cools down)
