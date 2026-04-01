from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def home():
    return {"message": "Backend is running"}

@app.post("/analyze")
def analyze():
    return {
        "status": "Partially Accessible",
        "features": {
            "ramp": "Yes",
            "stairs": "Yes",
            "pathway": "Narrow",
            "signage": "Missing"
        }
    }