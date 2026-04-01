from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# ✅ FIX: allow frontend to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def home():
    return {"message": "Backend is running"}

@app.post("/analyze")
async def analyze(file: UploadFile = File(...)):
    print("✅ FILE RECEIVED:", file.filename)

    # dummy response (your AI will go here later)
    return {
        "status": "Partially Accessible",
        "features": {
            "ramp": "Yes",
            "stairs": "Yes",
            "pathway": "Narrow",
            "signage": "Missing"
        }
    }
