from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.encoders import jsonable_encoder

from database import (
    init_db,
    save_user_input_image,
    save_analysis_output,
    get_all_outputs,
)

import base64
import os
import sys
import numpy as np

def safe(v):
    if isinstance(v, (np.float32, np.float64)):
        return float(v)
    if isinstance(v, (np.int32, np.int64)):
        return int(v)
    return v

# ADD SPRINT-4 MODEL FOLDER TO PYTHON PATH
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))

MODEL_DIR = os.path.abspath(
    os.path.join(CURRENT_DIR, "../../Sprint-4 Model")
)

sys.path.append(MODEL_DIR)


# IMPORT AI FUNCTION
from Function import analyze_uploaded_file


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

    # Read uploaded file
    image_bytes = await file.read()

    # Save original uploaded image
    input_id = save_user_input_image(
        file.filename,
        image_bytes
    )

    # RUN AI MODEL
    result = analyze_uploaded_file(
        image_bytes,
        file.filename
    )

    # Save analysis result to database
    output_id = save_analysis_output(
        input_image_id=input_id,
        output_image_data=result["output_image_data"],
        has_tactile_flooring=result["has_tactile_flooring"],
        compatibility_percentage=result["compatibility_percentage"],
        report_pdf=result["report_pdf"],
    )

    # Convert image bytes to base64
    output_image_base64 = base64.b64encode(
        result["output_image_data"]
    ).decode("utf-8")

    # Convert PDF bytes to base64
    pdf_base64 = base64.b64encode(
        result["report_pdf"]
    ).decode("utf-8")

    # Return results to frontend
    clean_response = {
        "input_image_id": safe(input_id),
        "output_id": safe(output_id),
        "has_tactile_flooring": bool(result["has_tactile_flooring"]),
        "compatibility_percentage": safe(result["compatibility_percentage"]),
        "compatibility_label": str(result["compatibility_label"]),
        "contrast_percentage": safe(result["contrast_percentage"]),
        "notes": str(result["notes"]),
        "output_image": output_image_base64,
        "report_pdf": pdf_base64,
    }

    return JSONResponse(content=clean_response)


@app.get("/analyses")
def list_analyses():
    return get_all_outputs()