# Pencil Stuck Marker

Experimental iPad app that detects Apple Pencil writing stalls and nudges learners with spatial annotations — without solving problems or parsing PDFs.

- Detects "stall / hesitation" from pen interaction patterns
- Shows a gentle optional nudge near where the learner paused
- Does **not** use OCR; learner stays in control at all times

**Status:** Early prototype (PencilKit input validation) — WIP

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

```
┌─────────────────────────────────────────────────────────┐
│  iPad (Swift)                                           │
│  ・pen events + region states (continuous)              │
│  ・lightweight heuristics                               │
│        stall N sec? / oscillation?                      │
└───────────────────┬─────────────────────────────────────┘
                    │ stuck candidate detected
                    ▼
┌─────────────────────────────────────────────────────────┐
│  Vision Agent SDK                                       │
│  ・1-frame snapshot (PDF + handwriting)                 │
│  ・returns: intervene yes / no / uncertain              │
└───────────────────┬─────────────────────────────────────┘
                    │ intervene: yes
                    ▼
┌─────────────────────────────────────────────────────────┐
│  Python Service ("Teacher Brain")                       │
│  ・score features + cooldown logic                      │
│  ・select behavior-based template                       │
│  ・returns: UI command (anchor, shape, bubble text)     │
└───────────────────┬─────────────────────────────────────┘
                    │ UI command
                    ▼
┌─────────────────────────────────────────────────────────┐
│  iPad (Swift) — render intervention                     │
│  ・highlight / arrow + 💭 bubble near anchor point      │
│  ・user taps → level up / dismiss / send intent event   │
└─────────────────────────────────────────────────────────┘
```

---

## API Contract (Swift ↔ Python)

### `POST /analyze` — Swift → Python

```json
{
  "region_id": "A",
  "stall_seconds": 12.4,
  "oscillation_count": 3,
  "anchor": { "x": 812, "y": 534 },
  "region_rect": { "x": 120, "y": 400, "w": 680, "h": 260 },
  "frame_png_base64": "..."
}
```

| field | type | description |
|---|---|---|
| `region_id` | string | どの答え欄か |
| `stall_seconds` | float | 最後のストロークからの経過秒 |
| `oscillation_count` | int | 書き→消しの繰り返し回数 |
| `anchor` | {x,y} | バブルを表示するスクリーン座標 |
| `region_rect` | {x,y,w,h} | 答え欄の矩形（Vision Agent に渡す） |
| `frame_png_base64` | string | 1-frame スナップショット（Vision Agent 用） |

### Response — Python → Swift

```json
{
  "intervene": true,
  "style": "highlight",
  "message": "ここで少し止まってるみたい",
  "target": { "region_id": "A" },
  "cooldown_seconds": 45
}
```

| field | type | description |
|---|---|---|
| `intervene` | bool | 介入するか否か |
| `style` | string | `highlight` のみ（Day 1）、将来 `arrow` / `pulse` を追加予定 |
| `message` | string | バブルに表示するテキスト |
| `target.region_id` | string | 描画先の答え欄 |
| `cooldown_seconds` | int | 次の介入までの待機秒 |

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

> **Why not OCR?** Knowing *what* is written doesn't tell us *how hard the learner is struggling* — pen hesitation does. OCR adds latency and complexity with no gain for our core signal.

- OCR / PDF text parsing
- Auto-detecting answer boxes from the PDF
- Full chat tutor
- Domain-specific reasoning (dice / geometry semantics)
- Multi-page learning analytics

---

## How to Run

### iOS App
```bash
open PencilStuckMarker/PencilStuckMarker.xcodeproj
# Target: iPad (recommended) or iPad Simulator
# Xcode 15+, iOS 17+
```

### Python Service
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r python_service/requirements.txt

# Optional but recommended for Vision Agents SDK decision path
export OPENAI_API_KEY=your_key_here
# export OPENAI_MODEL=gpt-4.1-mini
# export OPENAI_BASE_URL=https://api.openai.com/v1

uvicorn python_service.main:app --reload --port 8000
```

If `OPENAI_API_KEY` is unset, `/analyze` falls back to local heuristic verification.

---

## Demo Script (for judges)
1. Import a PDF worksheet
2. Mark two Regions quickly (Setup)
3. Start writing with Apple Pencil
4. Pause at a hard problem (simulate being stuck)
5. App detects the stuck point
6. Tap bubble → stronger highlight/arrow appears
7. Learner resumes writing (intervention disappears or cools down)

---
---

# プロジェクト：（TBD）― PDF 学習コンパニオン（プロトタイプ）

> PDF と Apple Pencil を組み合わせた学習支援アプリ。**学習者が詰まっている瞬間を検知**し、空間的なアノテーションで**そっと注意を促す**。  
> PDF の内容を OCR で解析したり、問題を解いたりは**しない**。

## なぜ作るのか
iPad で PDF に直接書き込みながら勉強する学習者は多い。  
このプロトタイプは「答え」ではなく「プロセス」に注目する：
- ペン操作のパターンから「止まり・迷い」を検知する
- 学習者が止まった場所の近くに、控えめな任意の介入を提示する
- 学習者主導を保つ（強制的なチュータリングはしない）

## 基本方針
- **OCR なし**：PDF テキストの解析や問題の解答は行わない。
- **答えなし**：AI は解答を提供しない。
- **空間 > チャット**：ガイダンスは固定チャット欄ではなく、場所（矢印・ハイライト＋小バブル）に紐づける。
- **「なぜ」を行動ベースで説明**：「このサイコロの目が X だから」ではなく「ここで止まっている／書き直している」と伝える。

## MVP（ハッカソン週間スコープ）
### 入力
- PDF インポート（ファイルアプリ / 共有 → アプリで開く）
- PDF の上に Apple Pencil で手書き（PencilKit オーバーレイ）

### セットアップモード（手動・素早く）
- ユーザーが 2〜10 個の「答え欄」を矩形で手動指定（Region）
  - 理由：OCR を避けつつ、任意の PDF に対応できる

### 学習モード
- 領域ごとの書き込み状況をトラッキング：
  - 最終ストロークのタイムスタンプ
  - ストローク増分（進捗）
  - 消去回数 / 書き消し繰り返し（オシレーション）
- 「詰まり候補」の検出：
  - **不活動ストール**：N 秒間進捗なし
  - **オシレーション**：短時間内の書き→消しの繰り返し
- 詰まり候補を検出したとき：
  - Vision Agent に**確認**を依頼（1 フレームのチェック）
  - 確認が取れたら：最後の活動地点の近くに小さな 💭 バブルを表示
    - 「困ってる？声で考えてみる？」 / 「ここで止まってるみたい」
  - バブルをタップすると：
    - 「ヒント（視覚強調）」（アノテーションのレベルアップ）
    - 「今は大丈夫」（非表示）

### 介入レベル（最小限に）
- Level 1：ハイライト / 矢印 ＋ 短いバブル（行動ベース）
- Level n：TBD

---

## アプリが「認識する」もの（明示）
認識するもの：
- **どこで**学習しているか（Region / 最後のペン位置）
- **どのように**学習しているか（ストール / オシレーション / 進捗低下）

認識しないもの：
- 問題文の意味
- 正解
- 図の意味論（サイコロの目・幾何学ラベルなど）

---

## アーキテクチャ概要

### iPad アプリ（Swift / SwiftUI）
担当：
- PDF インポートとレンダリング（PDF 背景）
- ペン書き込みのキャプチャ（PencilKit）
- 領域作成 UI（矩形）
- イベントログ（ストローク / 消しゴム / 時刻）
- ローカルの軽量ヒューリスティクス → **詰まり候補の検出**
- 空間的介入のレンダリング（ハイライト / 矢印 / バブル UI）

### Python サービス（「先生の脳」―解答者ではない）
Python の用途：
- インタラクションイベントを特徴量に集約
- 詰まりスコアの算出 ＋ クールダウン管理
- 行動ベースの応答テンプレート選択
- **介入コマンド**の生成：
  - 対象 Region / アンカーポイント
  - ハイライト形状・矢印ジオメトリ
  - バブルテキスト（テンプレートベース）
  - オプションのフォローアッププロンプト（確認 / 次のアクション）

> Python は OCR を必要としない。  
> インタラクション特徴量 ＋ オプションの視覚確認結果をもとに判断する。

### Vision Agents SDK（視覚的検証 / 「セカンドオピニオン」）
用途（最小限・高レバレッジ）：
- 毎フレームの連続分析は**しない**
- ローカルヒューリスティクスが詰まり候補を検出したときだけ呼び出す

受け取るもの：
- 1 フレームのスナップショット（現在の PDF ＋ 手書き）
- 候補 Region の矩形 / アンカーポイント
- ローカル特徴量のサマリー（ストール秒数・オシレーション回数など）

返すもの：
- `intervene: yes/no/uncertain`
- オプション：確信度スコアまたはアンカー修正の提案

この配置の理由：
- 「Vision Agents SDK を必ず使う」という要件を意味ある形で満たす
- OCR / 重い CV を避けられる
- 誤検知を防ぐ（「普通に考えているだけ」の学習者を邪魔しない）

---

## データフロー（判断パイプライン）
1. Swift がペンイベント ＋ 領域状態を継続的に収集
2. Swift が軽量特徴量を計算し、**詰まり候補**を検出
3. Swift が Vision Agent に確認を依頼（1 スナップショット）
4. 確認が取れたら：
   - Swift が Python に介入コマンドの生成を依頼（または Python を先に呼んでも可）
5. Swift がアンカーポイント近くに介入を表示
6. ユーザーがバブルをタップ：
   - レベルアップ / 非表示
   - （オプション）短い「ユーザー意図」イベントを Python に送信

---

## 安全性 / UX 制約
- 強制ポップアップなし：小さなバブルのみ、ユーザーがオプトイン
- ナグ防止のクールダウン
- すべてのコピーは行動ベース：
  - 「ここで止まってるみたい」
  - 「書いて→消してを繰り返してるかも」
  - 「声で考えてみる？」
- 正確性の主張なし・解答提供なし

---

## スコープ外（ハッカソン週間）
- OCR / PDF テキスト解析
- PDF から答え欄を自動検出
- フルチャットチューター
- ドメイン固有の推論（サイコロ / 幾何学の意味論）
- 複数ページにまたがる学習分析

---

## デモスクリプト（審査員向け）
1. PDF ワークシートをインポート
2. 2 つの Region を素早く指定（セットアップ）
3. Apple Pencil で書き始める
4. 難しい問題で手を止める（詰まりをシミュレート）
5. アプリが詰まりポイントを検出
6. バブルをタップ → より強調されたハイライト / 矢印が表示
7. 学習者が書き再開（介入が消えるかクールダウンへ）
