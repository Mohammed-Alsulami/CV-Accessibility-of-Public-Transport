import os

import cv2
import numpy as np


def create_overlay(original_img, prediction_mask):
    orig_np = np.array(original_img).copy()
    mask_np = np.array(prediction_mask)

    binary_mask = mask_np > 0

    overlay = orig_np.copy()
    overlay[binary_mask] = [0, 255, 0]

    blended = (0.6 * orig_np + 0.4 * overlay).astype(np.uint8)

    return blended


def get_frame_quality_score(frame):
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

    brightness = np.mean(gray)
    blur_score = cv2.Laplacian(gray, cv2.CV_64F).var()

    if brightness < 50:
        return 0

    if blur_score < 100:
        return 0

    return brightness + blur_score


def is_image_file(file_path):
    image_extensions = [".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff"]
    return os.path.splitext(file_path)[1].lower() in image_extensions


def is_video_file(file_path):
    video_extensions = [".mp4", ".mov", ".avi", ".mkv"]
    return os.path.splitext(file_path)[1].lower() in video_extensions
