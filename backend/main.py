from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from database import init_db, save_analysis, get_all_analyses

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

    # dummy response (your AI will go here later)
    status = "Partially Accessible"
    features = {
        "ramp": "Yes",
        "stairs": "Yes",
        "pathway": "Narrow",
        "signage": "Missing",
    }

    save_analysis(file.filename, status, features)

    return {"status": status, "features": features}


@app.get("/analyses")
def list_analyses():
    return get_all_analyses()
