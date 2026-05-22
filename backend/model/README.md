# Model Architecture

This document explains the model package structure and how to add a new accessibility feature detector in the future.

---

## Directory Structure

```
backend/model/
├── README.md                        # This file
├── function.py                      # Orchestration layer — shared logic, API entry point
├── utils.py                         # Shared image utilities (overlay, frame quality, file type checks)
├── features/
│   ├── __init__.py                  # Feature registry (REGISTERED_FEATURES list)
│   ├── base.py                      # Abstract FeatureDetector base class
│   └── tactile_flooring.py         # Tactile flooring detector (current feature)
├── src/
│   ├── __init__.py
│   ├── GRFBUNet.py                  # GRFBUNet architecture
│   └── unet.py                      # UNet architecture
└── weights/
    └── model.pth                    # Tactile flooring model weights
```

---

## How the Feature System Works

Every accessibility feature (e.g. tactile flooring, handrails) is a **`FeatureDetector`** subclass defined in `features/`.

Each detector is responsible for exactly four things:

| Responsibility | Method |
|---|---|
| Loading its model weights | `load(device)` |
| Running inference on a single PIL image | `run_on_image(original_img, device, threshold)` |
| Calculating luminance contrast | `calculate_contrast(original_img, mask_img)` |
| Returning a DSAPT compatibility result | `get_compatibility(detected, contrast_percentage)` |

The orchestration in `function.py` (video frame extraction, PDF generation, API response) is **shared** and does not need to change when a new feature is added.

---

## How to Add a New Feature

The following example uses handrails/grabrails, as described in `Add another DSAPT feature.md`.

### Step 1 — Collect and prepare a dataset

Collect labelled images showing the new feature (e.g. handrails at train stations, bus stops, ramps). Images need pixel-level segmentation masks.

### Step 2 — Train a model

Either train a dedicated single-class model or retrain the existing model as multi-class:

- **Separate model (simpler):** train a new GRFBUNet (or other architecture) for the new feature only.
- **Multi-class model (better long term):** update the existing model to detect multiple classes simultaneously, e.g.:
  - class 0: background
  - class 1: tactile flooring
  - class 2: handrail/grabrail

Save the trained weights to `weights/` (e.g. `weights/handrail_model.pth`).

### Step 3 — Create the detector file

Create `features/handrail.py` by subclassing `FeatureDetector`:

```python
import os
import time
import argparse

import numpy as np
import torch
from PIL import Image
from torchvision import transforms

from ..src import GRFBUNet        # or whichever architecture you used
from ..utils import create_overlay
from .base import FeatureDetector

_BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

_DSAPT_MIN = 30
_DSAPT_MEDIUM = 45
_DSAPT_HIGH = 60


class HanrailDetector(FeatureDetector):

    _MODEL_PATH = os.path.join(_BASE_DIR, "weights", "handrail_model.pth")

    def __init__(self):
        self._model = None

    @property
    def feature_name(self):
        return "Handrail/grabrail"

    @property
    def result_key(self):
        return "has_handrail"

    @property
    def model_path(self):
        return self._MODEL_PATH

    def load(self, device):
        classes = 1
        model = GRFBUNet(in_channels=3, num_classes=classes + 1, base_c=32)
        torch.serialization.add_safe_globals([argparse.Namespace])
        checkpoint = torch.load(self._MODEL_PATH, map_location="cpu", weights_only=True)
        model.load_state_dict(checkpoint["model"])
        model.to(device)
        model.eval()
        self._model = model

    def _preprocess(self, image):
        # Adjust mean/std to match your training normalisation
        mean = (0.485, 0.456, 0.406)
        std  = (0.229, 0.224, 0.225)
        transform = transforms.Compose([
            transforms.Resize(565),
            transforms.ToTensor(),
            transforms.Normalize(mean=mean, std=std),
        ])
        return transform(image)

    def run_on_image(self, original_img, device, threshold=500):
        original_w, original_h = original_img.size
        img = self._preprocess(original_img)
        img = torch.unsqueeze(img, dim=0)

        with torch.no_grad():
            start_time = time.time()
            output = self._model(img.to(device))
            end_time = time.time()
            prediction = output["out"].argmax(1).squeeze(0).cpu().numpy().astype(np.uint8)

        prediction = Image.fromarray(prediction).resize(
            (original_w, original_h), resample=Image.NEAREST
        )
        prediction = np.array(prediction)
        prediction[prediction == 1] = 255
        prediction[prediction == 0] = 0

        mask_img   = Image.fromarray(prediction).convert("L")
        overlay_img = create_overlay(original_img, mask_img)

        detected_pixels = int(np.sum(np.array(mask_img) > 0))
        result = "Yes" if detected_pixels > threshold else "No"

        inference_time = end_time - start_time
        fps = 1.0 / inference_time if inference_time > 0 else 0.0

        return result, detected_pixels, inference_time, fps, overlay_img, mask_img

    def calculate_contrast(self, original_img, mask_img):
        # Same luminance contrast calculation as TactileFlooringDetector.
        # Adjust if the handrail geometry requires a different approach.
        img_np   = np.array(original_img).astype(np.float32)
        mask_np  = np.array(mask_img)
        feature_mask    = mask_np > 0
        surrounding_mask = mask_np == 0

        if np.sum(feature_mask) == 0 or np.sum(surrounding_mask) == 0:
            return 0.0, 0.0, 0.0

        r, g, b   = img_np[:,:,0], img_np[:,:,1], img_np[:,:,2]
        luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

        surrounding_lum = np.mean(luminance[surrounding_mask])
        feature_lum     = np.mean(luminance[feature_mask])

        lighter = max(feature_lum, surrounding_lum)
        darker  = min(feature_lum, surrounding_lum)
        contrast = ((lighter - darker) / lighter * 100) if lighter > 0 else 0.0

        return contrast, feature_lum, surrounding_lum

    def get_compatibility(self, detected, contrast_percentage):
        if not detected:
            return 0, "Not assessed", "Handrail was not detected in the input image."

        if contrast_percentage < _DSAPT_MIN:
            return 0, "Not compatible", (
                f"Handrail detected, but contrast ({contrast_percentage:.1f}%) is below "
                f"the minimum DSAPT level of {_DSAPT_MIN}%."
            )
        if contrast_percentage < _DSAPT_MEDIUM:
            return 50, "Minimum compatibility", (
                f"Handrail detected with {contrast_percentage:.1f}% contrast. "
                f"Meets the {_DSAPT_MIN}% minimum but not the {_DSAPT_MEDIUM}% level."
            )
        if contrast_percentage < _DSAPT_HIGH:
            return 75, "Moderate compatibility", (
                f"Handrail detected with {contrast_percentage:.1f}% contrast. "
                f"Exceeds {_DSAPT_MEDIUM}% but not the {_DSAPT_HIGH}% high-contrast level."
            )
        return 100, "High compatibility", (
            f"Handrail detected with {contrast_percentage:.1f}% contrast. "
            f"Exceeds the {_DSAPT_HIGH}% DSAPT high-contrast level."
        )
```

### Step 4 — Register the detector

Open `features/__init__.py` and add two lines:

```python
from .base import FeatureDetector
from .tactile_flooring import TactileFlooringDetector
from .handrail import HanrailDetector          # <-- add import

REGISTERED_FEATURES = [
    TactileFlooringDetector,
    HanrailDetector,                           # <-- add to list
]
```

### Step 5 — Update function.py

`function.py` currently instantiates `TactileFlooringDetector` directly. For a single active feature, simply swap the import:

```python
from .features import HanrailDetector          # or whichever detector you want
```

If you want to run **multiple detectors in one request**, loop over `REGISTERED_FEATURES`:

```python
from .features import REGISTERED_FEATURES

detectors = [cls() for cls in REGISTERED_FEATURES]
for detector in detectors:
    detector.load(device)
# then call detector.run_on_image / calculate_contrast / get_compatibility for each
```

### Step 6 — Update the API response

In `function.py` → `analyze_uploaded_file`, add the new detector's results to the returned dict:

```python
return {
    # existing tactile flooring fields
    "has_tactile_flooring": ...,
    "compatibility_percentage": ...,
    ...
    # new handrail fields
    "has_handrail": handrail_result == "Yes",
    "handrail_contrast_percentage": handrail_contrast,
    "handrail_compatibility_label": handrail_label,
}
```

In `main.py`, add the new fields to the `JSONResponse`:

```python
return JSONResponse(content={
    ...
    "has_handrail": bool(result["has_handrail"]),
    "handrail_contrast_percentage": safe(result["handrail_contrast_percentage"]),
    "handrail_compatibility_label": str(result["handrail_compatibility_label"]),
})
```

### Step 7 — Update the PDF report

`pdf_report` in `function.py` currently writes a single-feature layout. To include a second feature, adjust the Y coordinates and add extra `c.drawString` calls for the new fields.

Alternatively, update the `Report_Template.pdf` in a PDF editor to add a second section, then update the coordinates accordingly.

### Step 8 — Update the frontend

In `frontend/src/HomePage.js`, display the new result fields returned by the API:

```jsx
{response.has_handrail !== undefined && (
  <p>Handrail detected: {response.has_handrail ? "Yes" : "No"}</p>
)}
{response.handrail_contrast_percentage !== undefined && (
  <p>Estimated contrast: {response.handrail_contrast_percentage.toFixed(1)}%</p>
)}
{response.handrail_compatibility_label && (
  <p>DSAPT compatibility: {response.handrail_compatibility_label}</p>
)}
```

---

## Summary Checklist

| Step | What to do |
|---|---|
| 1 | Collect and label a dataset for the new feature |
| 2 | Train a model; save weights to `weights/` |
| 3 | Create `features/<feature_name>.py` subclassing `FeatureDetector` |
| 4 | Register it in `features/__init__.py` |
| 5 | Update `function.py` to call the new detector |
| 6 | Add new fields to the API response in `function.py` and `main.py` |
| 7 | Update `Report_Template.pdf` and the `pdf_report` call in `function.py` |
| 8 | Display the new fields in the frontend |
