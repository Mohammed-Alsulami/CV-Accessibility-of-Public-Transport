# CV Accessibility of Public Transport

A proof-of-concept AI tool that analyses images and video of public transport infrastructure to detect accessibility features and assess their compliance with the **Disability Standards for Accessible Public Transport (DSAPT)**. It currently detects tactile ground surface indicators (tactile flooring) and measures their luminance contrast against the surrounding surface.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [System Architecture](#2-system-architecture)
3. [Prerequisites](#3-prerequisites)
4. [Quick Start](#4-quick-start)
5. [Project Structure](#5-project-structure)
6. [Running the Application](#6-running-the-application)
7. [Configuration](#7-configuration)
8. [API Reference](#8-api-reference)
9. [AI Model](#9-ai-model)
10. [Database](#10-database)
11. [Adding a New Accessibility Feature](#11-adding-a-new-accessibility-feature)
12. [Known Limitations](#12-known-limitations)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Project Overview

This system was developed as a university capstone project exploring how computer vision can assist with accessibility auditing of public transport environments.

**What it does:**

- Accepts an uploaded image (JPG, PNG) or short video clip (MP4, MOV) via a web interface.
- Runs a deep learning segmentation model (GRFBUNet) to identify tactile flooring in the image.
- Calculates the luminance contrast between the detected tactile area and the surrounding surface, following the DSAPT contrast requirements.
- Returns a structured JSON result and a downloadable PDF report that includes the original image, the model overlay, the DSAPT compatibility score, and assessment notes.
- Persists every upload and its analysis result in a local SQLite database.

**DSAPT Contrast Levels Checked:**

| Contrast | Compatibility Label |
|---|---|
| Below 30% | Not compatible |
| 30% – 44.99% | Minimum compatibility |
| 45% – 59.99% | Moderate compatibility |
| 60% or above | High compatibility |

> This tool is a prototype. It is not a substitute for a formal DSAPT compliance assessment.

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    User's Browser                       │
│              React SPA  (localhost:3000)                │
└────────────────────────┬────────────────────────────────┘
                         │  HTTP POST /analyze (multipart)
                         │  x-api-key: dev-secret-key
                         ▼
┌─────────────────────────────────────────────────────────┐
│              FastAPI Backend  (localhost:8000)           │
│                                                         │
│  main.py                                                │
│  ├── File validation (size + magic-byte check)          │
│  ├── API key authentication                             │
│  ├── Calls model/function.py → analyze_uploaded_file()  │
│  └── Saves input + output to SQLite                     │
│                                                         │
│  model/function.py                                      │
│  ├── Writes upload to a temp file                       │
│  ├── Image path  → process_image()                      │
│  │   └── detector.run_on_image()                        │
│  ├── Video path  → process_video()                      │
│  │   ├── Extracts frames every N seconds                │
│  │   ├── Picks highest-quality frame (brightness+blur)  │
│  │   └── detector.run_on_image()                        │
│  ├── detector.calculate_contrast()                      │
│  ├── detector.get_compatibility()                       │
│  └── pdf_report()  →  returns PDF bytes                 │
│                                                         │
│  model/features/tactile_flooring.py                     │
│  └── GRFBUNet inference → binary segmentation mask      │
│                                                         │
│  database.py  →  SQLite (accessibility.db)              │
└─────────────────────────────────────────────────────────┘
```

**Data flow summary:**

1. The frontend posts the file to `/analyze` with the API key header.
2. `main.py` validates the file (extension + PIL byte-verification for images).
3. `analyze_uploaded_file()` writes the bytes to a temp file, runs the model, calculates contrast, generates the PDF, then deletes the temp file.
4. The result (overlay image, PDF, scores) is base64-encoded and returned as JSON.
5. The frontend renders the overlay side-by-side with the original image, displays the scores, and offers a PDF download button.

---

## 3. Prerequisites

| Requirement | Minimum Version | Notes |
|---|---|---|
| Python | 3.10 | 3.12 recommended |
| Node.js | 18 LTS | includes npm |
| pip | any recent | bundled with Python |

**GPU (optional):** The model runs on CPU by default. If a CUDA-capable GPU is present, PyTorch will use it automatically. Install the CUDA build of PyTorch before running `pip install -r requirements.txt` — see [requirements.txt](requirements.txt) for instructions.

---

## 4. Quick Start

### macOS / Linux

```bash
# Clone the repository
git clone <repository-url>
cd CV-Accessibility-of-Public-Transport

# Run the one-shot launcher — installs everything and starts both servers
bash start.sh
```

The script will:
- Create a Python virtual environment at `.venv/`
- Install all Python dependencies from `requirements.txt`
- Install all Node.js dependencies via `npm install`
- Start the FastAPI backend on `http://localhost:8000`
- Start the React frontend on `http://localhost:3000`

Open `http://localhost:3000` in your browser.

### Windows

Open **PowerShell** in the project folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\start_windows.ps1
```

The script auto-installs Python 3.12 and Node.js LTS via `winget` if they are not already present, then starts both servers and opens the browser automatically.

---

## 5. Project Structure

```
CV-Accessibility-of-Public-Transport/
│
├── README.md                        ← This file
├── requirements.txt                 ← Python dependencies
├── start.sh                         ← macOS/Linux launcher
├── start_windows.ps1                ← Windows launcher
├── .gitignore
│
├── backend/
│   ├── main.py                      ← FastAPI app, endpoints, file validation
│   ├── database.py                  ← SQLite helper (init, read, write)
│   ├── accessibility.db             ← SQLite database (auto-created, git-ignored)
│   │
│   ├── images/
│   │   ├── analysis_output/         ← Reserved directory (currently unused)
│   │   ├── training_data/           ← Reserved directory (currently unused)
│   │   └── user_input/              ← Reserved directory (currently unused)
│   │
│   └── model/
│       ├── README.md                ← Model-specific docs (adding new features)
│       ├── function.py              ← Orchestration: image/video processing, PDF
│       ├── utils.py                 ← create_overlay, frame quality scoring, file-type helpers
│       │
│       ├── features/
│       │   ├── __init__.py          ← REGISTERED_FEATURES list
│       │   ├── base.py              ← FeatureDetector abstract base class
│       │   └── tactile_flooring.py  ← Active detector (GRFBUNet + DSAPT logic)
│       │
│       ├── src/
│       │   ├── __init__.py
│       │   ├── GRFBUNet.py          ← GRFBUNet architecture (encoder–decoder + GRFB modules)
│       │   └── unet.py              ← Standard UNet architecture (unused by default)
│       │
│       ├── weights/
│       │   ├── model.pth            ← Active tactile flooring model weights
│       │   └── Old_model.pth        ← Previous model version (kept for reference)
│       │
│       ├── Report_Template.pdf      ← Blank PDF template for report generation
│       └── output_report.pdf        ← Last generated report (git-ignored, overwritten each run)
│
└── frontend/
    ├── package.json
    ├── public/
    │   ├── index.html
    │   ├── white-logo.png           ← Header logo
    │   └── transport.png            ← Favicon / branding
    └── src/
        ├── index.js                 ← React entry point
        ├── App.js                   ← Root component (renders HomePage)
        ├── HomePage.js              ← Entire UI: upload, analysis display, results
        ├── App.css
        └── index.css
```

---

## 6. Running the Application

### Manual start (without the launcher scripts)

**Backend:**

```bash
# From the project root
source .venv/bin/activate          # Windows: .venv\Scripts\activate
cd backend
python -m uvicorn main:app --reload
# API available at http://localhost:8000
# Interactive docs at http://localhost:8000/docs
```

**Frontend:**

```bash
cd frontend
npm install        # only needed the first time
npm start
# UI available at http://localhost:3000
```

### CLI mode (without the web UI)

`function.py` has a `main()` function that can run directly for quick local testing:

1. Open `backend/model/function.py`.
2. Set `INPUT_PATH` to the path of your image or video file.
3. Run:

```bash
cd backend
python -m model.function
```

The PDF report is written to `backend/model/output_report.pdf`.

---

## 7. Configuration

All tuneable values live at the top of [backend/model/function.py](backend/model/function.py):

| Variable | Default | Description |
|---|---|---|
| `THRESHOLD` | `500` | Minimum detected pixel count to consider a feature present. Lower = more sensitive. |
| `FRAME_INTERVAL_SECONDS` | `1` | For video input: extract one candidate frame per this many seconds. |
| `MAX_VIDEO_SECONDS` | `10` | Warn (but still process) if the video exceeds this duration. |
| `ACCESSIBILITY_FEATURE_X` | `205.33` | PDF X coordinate for the feature-detected text. |
| `ACCESSIBILITY_FEATURE_Y` | `345` | PDF Y coordinate for the feature-detected text. Adjust if text overlaps the template. |

**API key:**

The backend reads the key from the `API_KEY` environment variable. If it is not set, the prototype default `"dev-secret-key"` is used. The frontend hardcodes this same key.

For any deployment beyond local development, set a strong secret:

```bash
export API_KEY="your-strong-secret-here"
```

**CORS:**

`main.py` allows requests from `http://localhost:3000` only. To allow a different origin, update the `allow_origins` list in the `CORSMiddleware` call.

**File size limits:**

| File type | Limit |
|---|---|
| Images (JPG, PNG) | 20 MB |
| Videos (MP4, MOV) | 100 MB |

These are defined as `MAX_IMAGE_SIZE` and `MAX_VIDEO_SIZE` in `main.py`.

---

## 8. API Reference

All endpoints require the header `x-api-key: <API_KEY>`.

---

### `GET /`

Health check.

**Response:**
```json
{ "message": "Backend is running" }
```

---

### `POST /analyze`

Upload an image or video for analysis.

**Request:**

- Content-Type: `multipart/form-data`
- Field: `file` — the image or video file

**Accepted formats:**

| Type | Extensions |
|---|---|
| Image | `.jpg`, `.jpeg`, `.png` |
| Video | `.mp4`, `.mov` |

**Successful response (200):**

```json
{
  "input_image_id": 1,
  "output_id": 1,
  "has_tactile_flooring": true,
  "compatibility_percentage": 75,
  "compatibility_label": "Moderate compatibility",
  "contrast_percentage": 52.3,
  "notes": "Tactile flooring was detected with an estimated luminance contrast of 52.30%...",
  "input_image": "<base64-encoded original image>",
  "output_image": "<base64-encoded overlay PNG>",
  "report_pdf": "<base64-encoded PDF>"
}
```

| Field | Type | Description |
|---|---|---|
| `input_image_id` | int | Database row ID of the uploaded image |
| `output_id` | int | Database row ID of this analysis result |
| `has_tactile_flooring` | bool | Whether the model detected tactile flooring |
| `compatibility_percentage` | int | DSAPT score: 0, 50, 75, or 100 |
| `compatibility_label` | string | Human-readable DSAPT label |
| `contrast_percentage` | float | Estimated luminance contrast (0–100%) |
| `notes` | string | Full assessment text for the PDF report |
| `input_image` | string | Base64 image — original upload |
| `output_image` | string | Base64 PNG — original image with detection overlay |
| `report_pdf` | string | Base64 PDF — downloadable DSAPT report |

**Error responses:**

| Status | Meaning |
|---|---|
| 400 | Unsupported file type or invalid image bytes |
| 401 | Missing or invalid API key |
| 413 | File exceeds the size limit |
| 422 | No valid video frames found |
| 500 | Model or PDF generation failure |

---

### `GET /analyses`

Returns all previous analysis records from the database (no binary data, metadata only).

**Response:**
```json
[
  {
    "id": 1,
    "input_image_id": 1,
    "filename": "platform.jpg",
    "has_tactile_flooring": 1,
    "compatibility_percentage": 75.0,
    "analyzed_at": "2025-05-01 10:23:45"
  }
]
```

---

## 9. AI Model

### Architecture

The model is a **GRFBUNet** — a UNet encoder–decoder augmented with **Gaussian Receptive Field Block (GRFB)** modules in the downsampling path.

```
Input (3-channel RGB, resized so shortest side = 565 px)
    │
    ├─ Encoder (4× Down blocks, each: MaxPool → DoubleConv1 → GRFB)
    │         GRFB uses three parallel dilated-convolution branches to
    │         capture multi-scale context without losing resolution.
    │
    └─ Decoder (4× Up blocks, each: bilinear upsample + skip-connection + DoubleConv)
                    │
                    ▼
          Output logits (2 classes: background / tactile flooring)
          argmax → binary mask → resize to original dimensions
```

Key files:

| File | Role |
|---|---|
| [backend/model/src/GRFBUNet.py](backend/model/src/GRFBUNet.py) | Full architecture definition |
| [backend/model/src/unet.py](backend/model/src/unet.py) | Standard UNet (available but not currently used) |
| [backend/model/weights/model.pth](backend/model/weights/model.pth) | Trained weights for tactile flooring |

### Inference pipeline

1. The input image is resized so its shortest side is 565 px, converted to a tensor, and normalised using the training-dataset mean `(0.709, 0.381, 0.224)` and std `(0.127, 0.079, 0.043)`.
2. The model outputs a `(1, 2, H, W)` logit tensor. `argmax` along the class dimension yields a binary mask.
3. The mask is resized back to the original image dimensions using nearest-neighbour interpolation.
4. If the number of positive-class pixels exceeds `THRESHOLD` (default 500), the feature is considered detected.

### Luminance contrast calculation

The `calculate_contrast` method in `TactileFlooringDetector` uses a **percentile approach** designed for tactile studs that have both dark and light elements:

1. Compute per-pixel ITU-R BT.709 luminance: `L = 0.2126R + 0.7152G + 0.0722B`
2. Split the detected region into a "dark quartile" (bottom 25%) and a "light quartile" (top 25%).
3. Compute contrast against the surrounding area for both quartiles using `(lighter − darker) / lighter × 100`.
4. Return the higher of the two contrasts, as it represents the most discriminable part of the tactile pattern.

### Device selection

The model uses CUDA automatically if available, otherwise CPU:

```python
device = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")
```

No code change is needed to switch between CPU and GPU.

### Video processing

For video input, `process_video()`:

1. Samples one frame every `FRAME_INTERVAL_SECONDS` seconds.
2. Filters out blurry frames (Laplacian variance < 100) and dark frames (mean brightness < 50).
3. Selects the single highest-quality frame (brightness + Laplacian variance score) for inference.

Only one frame is sent to the model. This is intentional for the prototype — the "best frame" heuristic avoids processing duplicate or poor-quality frames.

---

## 10. Database

The SQLite database is created automatically at `backend/accessibility.db` on first run. It contains three tables:

### `user_input_images`

Stores every file uploaded through the web interface.

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER PK | Auto-incremented row ID |
| `filename` | TEXT | Original filename from the upload |
| `image_data` | BLOB | Raw file bytes |
| `uploaded_at` | TIMESTAMP | UTC timestamp of the upload |

### `user_image_output`

Stores the analysis result for each uploaded file.

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER PK | Auto-incremented row ID |
| `input_image_id` | INTEGER FK | References `user_input_images.id` |
| `output_image_data` | BLOB | Overlay PNG bytes |
| `has_tactile_flooring` | INTEGER | 1 = detected, 0 = not detected |
| `compatibility_percentage` | REAL | DSAPT score (0, 50, 75, or 100) |
| `report_pdf` | BLOB | PDF bytes |
| `analyzed_at` | TIMESTAMP | UTC timestamp of the analysis |

### `training_data`

Internal table reserved for storing labelled training images. Not exposed through any API endpoint in the current prototype.

| Column | Type | Description |
|---|---|---|
| `id` | INTEGER PK | Auto-incremented row ID |
| `image_data` | BLOB | Raw image bytes |
| `has_tactile_flooring` | INTEGER | Ground-truth label (0 or 1) |
| `compatibility_percentage` | REAL | Optional contrast annotation |
| `created_at` | TIMESTAMP | UTC timestamp |

---

## 11. Adding a New Accessibility Feature

The detector system is designed to be extended. Each new feature (e.g. handrails, ramps, step-edge markings) is a self-contained class that subclasses `FeatureDetector`.

For a complete step-by-step guide including a full code example, see [backend/model/README.md](backend/model/README.md).

**Summary of steps:**

| Step | What to do |
|---|---|
| 1 | Collect and label a dataset for the new feature |
| 2 | Train a model; save weights to `backend/model/weights/` |
| 3 | Create `backend/model/features/<feature_name>.py` subclassing `FeatureDetector` |
| 4 | Register the new class in `backend/model/features/__init__.py` |
| 5 | Update `function.py` to instantiate and call the new detector |
| 6 | Add the new fields to the API response in `function.py` and `main.py` |
| 7 | Update the PDF template and the `pdf_report()` call in `function.py` |
| 8 | Display the new fields in `frontend/src/HomePage.js` |

The four methods every `FeatureDetector` subclass must implement:

| Method | Purpose |
|---|---|
| `load(device)` | Load model weights onto the target device |
| `run_on_image(original_img, device, threshold)` | Run inference; return result, mask, overlay |
| `calculate_contrast(original_img, mask_img)` | Compute luminance contrast |
| `get_compatibility(detected, contrast_percentage)` | Return DSAPT score, label, and notes text |

---

## 12. Known Limitations

- **Single feature:** Only tactile flooring is detected in the current release. Support for handrails, ramps, and other DSAPT elements requires additional trained models.
- **Single best frame for video:** Video analysis selects exactly one frame. Scenes where tactile flooring is only partially visible may produce inconsistent results depending on which frame is chosen.
- **Detection threshold is fixed:** The `THRESHOLD` of 500 pixels was chosen empirically. It may need tuning for images taken from unusual distances or angles.
- **Contrast calculation is an estimate:** The luminance contrast is computed on the detected pixel region, which depends on the accuracy of the segmentation mask. Inaccurate masks lead to inaccurate contrast readings.
- **No authentication beyond a shared key:** The API key is a prototype mechanism. It provides no per-user identity or audit trail. Do not expose the backend on a public network without replacing this with proper authentication.
- **CORS locked to localhost:** The backend accepts requests only from `http://localhost:3000`. Deployment to any other origin requires updating `allow_origins` in `main.py`.
- **Database stores raw bytes:** Images and PDFs are stored as BLOBs in SQLite. This does not scale; a production system should use a file store (e.g. S3) with only the URL in the database.
- **No test suite:** The repository does not currently include automated tests. Manual testing against known images is the only verification method.

---

## 13. Troubleshooting

**`Backend is not reachable` error in the browser**

The FastAPI server is not running. Start it manually:

```bash
source .venv/bin/activate
cd backend
python -m uvicorn main:app --reload
```

**`Model not found` error on startup**

The file `backend/model/weights/model.pth` is missing. This file is tracked by git — run `git pull` or re-clone the repository. If the file exceeds GitHub's file size limit in your fork, download it separately and place it at that path.

**Very slow first analysis (CPU)**

PyTorch loads and JIT-compiles on the first inference call. Subsequent calls are significantly faster. On CPU, expect 5–30 seconds for the first request.

**Port already in use**

The launcher scripts kill processes on ports 8000 and 3000 before starting. If you are on Windows without using the launcher script, run:

```powershell
# Kill whatever is on port 8000
Get-NetTCPConnection -LocalPort 8000 | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```

**`Invalid image file` (400) when uploading a valid image**

The backend verifies image bytes using Pillow (`Image.verify()`). Some files with non-standard encoding may fail this check even if they appear valid in a viewer. Convert the image to a standard JPEG or PNG and try again.

**PDF text appears in the wrong position**

The PDF coordinates (`ACCESSIBILITY_FEATURE_X`, `ACCESSIBILITY_FEATURE_Y` and others in `function.py`) are hard-coded to match `Report_Template.pdf`. If the template is updated, adjust these coordinates accordingly. The origin (0, 0) is the **bottom-left** of the page in ReportLab's coordinate system. Page dimensions are 612 × 792 points (US Letter).
