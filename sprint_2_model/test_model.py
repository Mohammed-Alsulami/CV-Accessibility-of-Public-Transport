from function import detect_tactile_with_trained_model
import os

IMAGE_PATH = "test8.jpg"
MODEL_PATH = "tactile_svm.pkl"

# ✅ Safety checks
if not os.path.exists(IMAGE_PATH):
    print("❌ Image not found:", IMAGE_PATH)
    exit()

if not os.path.exists(MODEL_PATH):
    print("❌ Model not found:", MODEL_PATH)
    exit()

print("🚀 Running tactile detection...\n")

try:
    result = detect_tactile_with_trained_model(
        image_path=IMAGE_PATH,
        model_path=MODEL_PATH,   # 🔥 override default
        show_result=True
    )

    print("\n✅ RESULT:")
    print(result)

except Exception as e:
    print("❌ ERROR:", e)
