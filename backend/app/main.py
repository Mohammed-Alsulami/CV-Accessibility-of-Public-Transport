from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from database import (
    init_db,
    save_user_input_image,
    save_analysis_output,
    get_all_outputs,
)

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

    # Save the raw user upload
    input_id = save_user_input_image(file.filename, image_bytes)

    # ── AI model goes here ──────────────────────────────────────────────────
    # Replace the dummy values below once the model is integrated.
    has_tactile_flooring = 0          # 0 = No, 1 = Yes
    compatibility_percentage = None   # populated by model
    output_image_data = None          # annotated output image bytes from model
    report_pdf = None                 # PDF report bytes from model
    # ────────────────────────────────────────────────────────────────────────

    output_id = save_analysis_output(
        input_image_id=input_id,
        output_image_data=output_image_data,
        has_tactile_flooring=has_tactile_flooring,
        compatibility_percentage=compatibility_percentage,
        report_pdf=report_pdf,
    )

    return {
        "input_image_id": input_id,
        "output_id": output_id,
        "has_tactile_flooring": bool(has_tactile_flooring),
        "compatibility_percentage": compatibility_percentage,
    }


@app.get("/analyses")
def list_analyses():
    return get_all_outputs()
