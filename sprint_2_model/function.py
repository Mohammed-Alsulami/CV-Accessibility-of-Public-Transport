import cv2
import joblib
import numpy as np
import matplotlib.pyplot as plt
from skimage.feature import hog

PATCH_SIZE = 64


def extract_hog_features(image):
    image = cv2.resize(image, (PATCH_SIZE, PATCH_SIZE))
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    features = hog(
        gray,
        orientations=9,
        pixels_per_cell=(8, 8),
        cells_per_block=(2, 2),
        block_norm='L2-Hys'
    )
    return features


def detect_tactile_with_trained_model(image_path, model_path="/content/tactile_svm.pkl", show_result=True):
    model = joblib.load(model_path)

    image = cv2.imread(image_path)
    if image is None:
        raise ValueError(f"Could not read image: {image_path}")

    h, w = image.shape[:2]
    y_start = int(h * 0.45)
    ground = image[y_start:, :]
    draw_img = ground.copy()

    window_size = PATCH_SIZE
    step = PATCH_SIZE // 2

    detections = []

    for yy in range(0, ground.shape[0] - window_size + 1, step):
        for xx in range(0, ground.shape[1] - window_size + 1, step):
            patch = ground[yy:yy + window_size, xx:xx + window_size]

            features = extract_hog_features(patch).reshape(1, -1)
            pred = model.predict(features)[0]

            if pred == 1:
                detections.append((xx, yy, window_size, window_size))

    tactile_detected = len(detections) >= 3

    for (x, y, ww, hh) in detections:
        cv2.rectangle(draw_img, (x, y), (x + ww, y + hh), (0, 255, 0), 2)

    label = f"{'TACTILE_DETECTED' if tactile_detected else 'NO_TACTILE_DETECTED'} | patches={len(detections)}"
    color = (0, 255, 0) if tactile_detected else (0, 0, 255)

    cv2.putText(
        draw_img,
        label,
        (20, 30),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.8,
        color,
        2
    )

    if show_result:
        draw_rgb = cv2.cvtColor(draw_img, cv2.COLOR_BGR2RGB)
        plt.figure(figsize=(10, 8))
        plt.imshow(draw_rgb)
        plt.axis("off")
        plt.title("Tactile Detection")
        plt.show()

    return {
        "tactile_paving": tactile_detected,
        "num_detected_patches": len(detections),
        "detections": detections
    }


if __name__ == "__main__":
    result = detect_tactile_with_trained_model(
        image_path="test1.jpg",
        model_path="tactile_svm.pkl", 
        show_result=True
    )

    print(result)
