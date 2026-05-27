from fastapi import FastAPI, UploadFile, File, HTTPException, Depends, Header
import os
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from database import (
    init_db,
    save_user_input_image,
    save_analysis_output,
    get_output_by_id,
    get_all_outputs,
)

import base64
import traceback
import numpy as np
import io
from PIL import Image

from model.function import analyze_uploaded_file

# API KEY AUTHENTICATION
# This key is used to protect the backend endpoints.
# Any request to /analyze or /analyses must include this key in the request header.
# Header name: x-api-key
# For prototype testing, the default key is "dev-secret-key".
# In production, this key should be stored as an environment variable, not hardcoded.
API_KEY = os.getenv("API_KEY", "dev-secret-key")


# FILE UPLOAD VALIDATION
# The backend must not trust the uploaded filename or extension only.
# This validation checks the file size and confirms that image files are real images
# before saving them or passing them to the AI model.
# This helps prevent memory exhaustion, fake file uploads, and unsafe parsing.
MAX_IMAGE_SIZE = 20 * 1024 * 1024
MAX_VIDEO_SIZE = 100 * 1024 * 1024

ALLOWED_IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png"}
ALLOWED_VIDEO_EXTENSIONS = {".mp4", ".mov"}


MAX_DISPLAY_PX = 1024


def validate_image_bytes(file_bytes):
    try:
        image = Image.open(io.BytesIO(file_bytes))
        image.verify()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid image file.")


def _resize_for_display(image_bytes, max_px=MAX_DISPLAY_PX, save_format="JPEG", quality=85):
    """Return resized image bytes; only downscales if either dimension exceeds max_px."""
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    if img.width <= max_px and img.height <= max_px:
        if save_format.upper() == "JPEG":
            buf = io.BytesIO()
            img.save(buf, format="JPEG", quality=quality)
            return buf.getvalue()
        return image_bytes
    img.thumbnail((max_px, max_px), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format=save_format, quality=quality)
    return buf.getvalue()


def validate_uploaded_file(file_bytes, filename):
    ext = os.path.splitext(filename)[1].lower()

    if ext in ALLOWED_IMAGE_EXTENSIONS:
        if len(file_bytes) > MAX_IMAGE_SIZE:
            raise HTTPException(status_code=413, detail="Image file is too large.")

        validate_image_bytes(file_bytes)
        return

    if ext in ALLOWED_VIDEO_EXTENSIONS:
        if len(file_bytes) > MAX_VIDEO_SIZE:
            raise HTTPException(status_code=413, detail="Video file is too large.")

        return

    raise HTTPException(status_code=400, detail="Unsupported file type.")


def safe(v):
    if isinstance(v, bytes):
        return None  # never expose raw blobs in list responses
    if isinstance(v, (np.float32, np.float64)):
        return float(v)
    if isinstance(v, (np.int32, np.int64)):
        return int(v)
    return v

def verify_api_key(x_api_key: str = Header(None)):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")
    return x_api_key



app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_methods=["*"],
    allow_headers=["*"],
)

init_db()


@app.get("/")
def home():
    return {"message": "Backend is running"}


async def _read_with_limit(upload_file: UploadFile, max_bytes: int) -> bytes:
    chunks = []
    total = 0
    while True:
        chunk = await upload_file.read(65536)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise HTTPException(status_code=413, detail="File exceeds maximum allowed upload size.")
        chunks.append(chunk)
    return b"".join(chunks)


@app.post("/analyze")
async def analyze(
    file: UploadFile = File(...),
    api_key: str = Depends(verify_api_key)):

    print("FILE RECEIVED:", file.filename)

    image_bytes = await _read_with_limit(file, MAX_VIDEO_SIZE)

    validate_uploaded_file(image_bytes, file.filename)

    input_id = save_user_input_image(file.filename, image_bytes)

    try:
        result = analyze_uploaded_file(image_bytes, file.filename)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except FileNotFoundError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Analysis failed: {str(e)}")

    output_id = save_analysis_output(
        input_image_id=input_id,
        output_image_data=result["output_image_data"],
        has_tactile_flooring=result["has_tactile_flooring"],
        compatibility_percentage=result["compatibility_percentage"],
        contrast_percentage=result["contrast_percentage"],
        compatibility_label=result["compatibility_label"],
        notes=result["notes"],
        report_pdf=result["report_pdf"],
    )

    # Both input_image_data and output_image_data are always JPEG/PNG bytes at this point —
    # for videos, input_image_data is the best analyzed frame, not the raw video bytes.
    input_display_bytes = _resize_for_display(result["input_image_data"], save_format="JPEG")
    input_image_base64 = base64.b64encode(input_display_bytes).decode("utf-8")

    output_display_bytes = _resize_for_display(result["output_image_data"], save_format="PNG")
    output_image_base64 = base64.b64encode(output_display_bytes).decode("utf-8")
    pdf_base64 = base64.b64encode(result["report_pdf"]).decode("utf-8")

    return JSONResponse(content={
        "input_image_id": safe(input_id),
        "output_id": safe(output_id),
        "has_tactile_flooring": bool(result["has_tactile_flooring"]),
        "compatibility_percentage": safe(result["compatibility_percentage"]),
        "compatibility_label": str(result["compatibility_label"]),
        "contrast_percentage": safe(result["contrast_percentage"]),
        "notes": str(result["notes"]),
        "input_image": input_image_base64,
        "output_image": output_image_base64,
        "report_pdf": pdf_base64,
    })


@app.get("/analyses")
def list_analyses(api_key: str = Depends(verify_api_key)):
    rows = get_all_outputs()
    return JSONResponse(content=[
        {
            "id":                       safe(row["id"]),
            "input_image_id":           safe(row["input_image_id"]),
            "filename":                 str(row["filename"]) if row["filename"] is not None else None,
            "has_tactile_flooring":     bool(row["has_tactile_flooring"]) if row["has_tactile_flooring"] is not None else None,
            "compatibility_percentage": safe(row["compatibility_percentage"]),
            "contrast_percentage":      safe(row["contrast_percentage"]),
            "compatibility_label":      str(row["compatibility_label"]) if row["compatibility_label"] is not None else None,
            "analyzed_at":              str(row["analyzed_at"]) if row["analyzed_at"] is not None else None,
        }
        for row in rows
    ])


@app.get("/analyses/{output_id}")
def get_analysis(output_id: int, api_key: str = Depends(verify_api_key)):
    row = get_output_by_id(output_id)
    if not row:
        raise HTTPException(status_code=404, detail="Analysis not found")

    return JSONResponse(content={
        "input_image_id":           safe(row["input_image_id"]),
        "output_id":                safe(row["id"]),
        "filename":                 str(row["filename"]),
        "has_tactile_flooring":     bool(row["has_tactile_flooring"]),
        "compatibility_percentage": safe(row["compatibility_percentage"]),
        "compatibility_label":      str(row["compatibility_label"] or ""),
        "contrast_percentage":      safe(row["contrast_percentage"] or 0.0),
        "notes":                    str(row["notes"] or ""),
        "analyzed_at":              str(row["analyzed_at"]),
        "input_image":  base64.b64encode(row["input_image_data"]).decode("utf-8"),
        "output_image": base64.b64encode(row["output_image_data"]).decode("utf-8"),
        "report_pdf":   base64.b64encode(row["report_pdf"]).decode("utf-8"),
    })

