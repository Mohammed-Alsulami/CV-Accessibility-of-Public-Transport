from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from database import (
    init_db,
    save_user_input_image,
    save_analysis_output,
    get_all_outputs,
)

import base64
import traceback
import numpy as np

from model.function import analyze_uploaded_file


def safe(v):
    if isinstance(v, (np.float32, np.float64)):
        return float(v)
    if isinstance(v, (np.int32, np.int64)):
        return int(v)
    return v


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


@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):

    print("✅ FILE RECEIVED:", file.filename)

    image_bytes = await file.read()

    input_id = save_user_input_image(file.filename, image_bytes)

    # Also encode the original image so the frontend can display it
    input_image_base64 = base64.b64encode(image_bytes).decode("utf-8")

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
        report_pdf=result["report_pdf"],
    )

    output_image_base64 = base64.b64encode(result["output_image_data"]).decode("utf-8")
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
def list_analyses():
    return get_all_outputs()
