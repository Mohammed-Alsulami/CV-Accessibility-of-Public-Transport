import argparse
import os
import time

import numpy as np
import torch
from PIL import Image
from torchvision import transforms

from ..src import GRFBUNet
from ..utils import create_overlay
from .base import FeatureDetector


_BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

_DSAPT_MIN = 30
_DSAPT_MEDIUM = 45
_DSAPT_HIGH = 60


class TactileFlooringDetector(FeatureDetector):
    """Detects tactile ground surface indicators and assesses DSAPT contrast compliance."""

    _MODEL_PATH = os.path.join(_BASE_DIR, "weights", "model.pth")

    def __init__(self):
        self._model = None

    @property
    def feature_name(self) -> str:
        return "Tactile flooring"

    @property
    def result_key(self) -> str:
        return "has_tactile_flooring"

    @property
    def model_path(self) -> str:
        return self._MODEL_PATH

    def load(self, device) -> None:
        classes = 1
        model = GRFBUNet(in_channels=3, num_classes=classes + 1, base_c=32)

        torch.serialization.add_safe_globals([argparse.Namespace])

        checkpoint = torch.load(self._MODEL_PATH, map_location="cpu", weights_only=True)
        model.load_state_dict(checkpoint["model"])
        model.to(device)
        model.eval()

        self._model = model

    def _preprocess(self, image):
        mean = (0.709, 0.381, 0.224)
        std = (0.127, 0.079, 0.043)

        transform = transforms.Compose([
            transforms.Resize(565),
            transforms.ToTensor(),
            transforms.Normalize(mean=mean, std=std),
        ])

        return transform(image)

    def run_on_image(self, original_img, device, threshold: int = 500):
        original_w, original_h = original_img.size

        img = self._preprocess(original_img)
        img = torch.unsqueeze(img, dim=0)

        with torch.no_grad():
            start_time = time.time()
            output = self._model(img.to(device))
            end_time = time.time()

            prediction = output["out"].argmax(1).squeeze(0).cpu().numpy().astype(np.uint8)

        prediction = Image.fromarray(prediction)
        prediction = prediction.resize((original_w, original_h), resample=Image.NEAREST)
        prediction = np.array(prediction)

        prediction[prediction == 1] = 255
        prediction[prediction == 0] = 0

        mask_img = Image.fromarray(prediction).convert("L")
        overlay_img = create_overlay(original_img, mask_img)

        detected_pixels = int(np.sum(np.array(mask_img) > 0))
        result = "Yes" if detected_pixels > threshold else "No"

        inference_time = end_time - start_time
        fps = 1.0 / inference_time if inference_time > 0 else 0.0

        return result, detected_pixels, inference_time, fps, overlay_img, mask_img

    def calculate_contrast(self, original_img, mask_img):
        img_np = np.array(original_img).astype(np.float32)
        mask_np = np.array(mask_img)

        tactile_mask = mask_np > 0
        surrounding_mask = mask_np == 0

        if np.sum(tactile_mask) == 0 or np.sum(surrounding_mask) == 0:
            return 0.0, 0.0, 0.0

        r = img_np[:, :, 0]
        g = img_np[:, :, 1]
        b = img_np[:, :, 2]

        luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

        tactile_luminance_values = luminance[tactile_mask]
        surrounding_luminance = np.mean(luminance[surrounding_mask])

        dark_threshold = np.percentile(tactile_luminance_values, 25)
        dark_tactile_mask = tactile_mask & (luminance <= dark_threshold)

        light_threshold = np.percentile(tactile_luminance_values, 75)
        light_tactile_mask = tactile_mask & (luminance >= light_threshold)

        dark_luminance = np.mean(luminance[dark_tactile_mask]) if np.sum(dark_tactile_mask) > 0 else 0.0
        light_luminance = np.mean(luminance[light_tactile_mask]) if np.sum(light_tactile_mask) > 0 else 0.0

        def _contrast(lum1, lum2):
            lighter = max(lum1, lum2)
            darker = min(lum1, lum2)
            if lighter == 0:
                return 0.0
            return ((lighter - darker) / lighter) * 100

        dark_contrast = _contrast(dark_luminance, surrounding_luminance)
        light_contrast = _contrast(light_luminance, surrounding_luminance)

        if dark_contrast >= light_contrast:
            return dark_contrast, dark_luminance, surrounding_luminance
        return light_contrast, light_luminance, surrounding_luminance

    def get_compatibility(self, detected: bool, contrast_percentage: float):
        if not detected:
            return (
                0,
                "Not assessed",
                (
                    "Tactile flooring was not detected in the input image, so DSAPT "
                    "luminance contrast compatibility could not be assessed."
                ),
            )

        if contrast_percentage < _DSAPT_MIN:
            return (
                0,
                "Not compatible",
                (
                    f"Tactile flooring was detected, but the estimated luminance contrast "
                    f"is {contrast_percentage:.2f}%. This is below the minimum selected "
                    f"DSAPT contrast level of {_DSAPT_MIN}%, so it is not considered "
                    f"compatible based on contrast."
                ),
            )

        if contrast_percentage < _DSAPT_MEDIUM:
            return (
                50,
                "Minimum compatibility",
                (
                    f"Tactile flooring was detected with an estimated luminance contrast "
                    f"of {contrast_percentage:.2f}%. This meets the minimum selected DSAPT "
                    f"contrast level of {_DSAPT_MIN}%, but does not reach the "
                    f"{_DSAPT_MEDIUM}% or {_DSAPT_HIGH}% levels. Therefore, "
                    f"it is considered partially compatible based on contrast."
                ),
            )

        if contrast_percentage < _DSAPT_HIGH:
            return (
                75,
                "Moderate compatibility",
                (
                    f"Tactile flooring was detected with an estimated luminance contrast "
                    f"of {contrast_percentage:.2f}%. This exceeds the {_DSAPT_MEDIUM}% "
                    f"contrast level but does not reach the {_DSAPT_HIGH}% high-contrast "
                    f"level. Therefore, it shows moderate DSAPT contrast compatibility."
                ),
            )

        return (
            100,
            "High compatibility",
            (
                f"Tactile flooring was detected with an estimated luminance contrast "
                f"of {contrast_percentage:.2f}%. This exceeds the {_DSAPT_HIGH}% "
                f"contrast level, so it is considered highly compatible based on the "
                f"selected DSAPT contrast criteria."
            ),
        )
