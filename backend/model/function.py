from datetime import datetime
import io
import os
import tempfile

import cv2
import numpy as np
import torch
from PIL import Image

from .features import TactileFlooringDetector
from .utils import get_frame_quality_score, is_image_file, is_video_file


# USER SETTINGS - CHANGE THESE ONLY

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

INPUT_PATH = ""

TEMPLATE_PATH = os.path.join(BASE_DIR, "Report_Template.pdf")

OUTPUT_PDF_PATH = os.path.join(BASE_DIR, "output_report.pdf")

THRESHOLD = 500

FRAME_INTERVAL_SECONDS = 1
MAX_VIDEO_SECONDS = 10

# PDF text position for accessibility feature
# If the text appears in the wrong place, only adjust this Y value.
ACCESSIBILITY_FEATURE_X = 205.33
ACCESSIBILITY_FEATURE_Y = 345


# PDF Report Generation
def pdf_report(input_image, processed_image, accessibility_feature,
               dsapt_compliance_score, notes,
               output_path="output_report.pdf", template_path="Report_Template.pdf"):

    from reportlab.pdfgen import canvas
    from reportlab.lib.utils import ImageReader
    from pdfrw import PdfReader, PdfWriter, PageMerge

    PAGE_W, PAGE_H = 612, 792

    def to_pil(img_input):
        if isinstance(img_input, np.ndarray):
            return Image.fromarray(img_input.astype(np.uint8)).convert("RGB")

        if isinstance(img_input, Image.Image):
            return img_input.convert("RGB")

        if isinstance(img_input, str) and os.path.exists(img_input):
            return Image.open(img_input).convert("RGB")

        return None

    def draw_image_in_cell(c, pil_img, cell_x, cell_y_bottom, cell_w, cell_h, padding=4):
        iw, ih = pil_img.size

        max_w = cell_w - 2 * padding
        max_h = cell_h - 2 * padding

        scale = min(max_w / iw, max_h / ih)

        draw_w = iw * scale
        draw_h = ih * scale

        draw_x = cell_x + (cell_w - draw_w) / 2
        draw_y = cell_y_bottom + (cell_h - draw_h) / 2

        c.drawImage(ImageReader(pil_img), draw_x, draw_y, draw_w, draw_h)

    def draw_wrapped_text(c, text, x, y, max_width, font_name, font_size, line_height):
        words = str(text).split()
        lines = []
        current = ""

        for word in words:
            test = (current + " " + word).strip()

            if c.stringWidth(test, font_name, font_size) <= max_width:
                current = test
            else:
                if current:
                    lines.append(current)
                current = word

        if current:
            lines.append(current)

        for line in lines:
            c.drawString(x, y, line)
            y -= line_height

    packet = io.BytesIO()
    c = canvas.Canvas(packet, pagesize=(PAGE_W, PAGE_H))

    # 1. Date
    c.setFont("Helvetica", 11)
    c.drawString(205.33, 465.15, datetime.now().strftime("%d/%m/%Y"))

    # 2. Input image
    pil_in = to_pil(input_image)
    if pil_in:
        draw_image_in_cell(c, pil_in, 205.33, 360, 540 - 205.33, 100)

    # 3. Accessibility feature detected
    c.setFont("Helvetica", 11)
    c.drawString(ACCESSIBILITY_FEATURE_X, ACCESSIBILITY_FEATURE_Y, accessibility_feature)

    # 4. Processed/output image
    pil_out = to_pil(processed_image)
    if pil_out:
        draw_image_in_cell(c, pil_out, 205.33, 226, 540 - 205.33, 100)

    # 5. DSAPT compatibility score
    c.setFont("Helvetica", 11)
    c.drawString(205.33, 210.58, f"{dsapt_compliance_score}%")

    # 6. Notes
    draw_wrapped_text(c, notes, 205.33, 185.55, 290, "Helvetica", 10, 12)

    c.save()
    packet.seek(0)

    template = PdfReader(template_path)
    overlay_pdf = PdfReader(packet)

    PageMerge(template.pages[0]).add(overlay_pdf.pages[0]).render()
    PdfWriter(output_path, trailer=template).write()

    return output_path


# Process Image Input
def process_image(image_path, detector, device, threshold=500):
    if not os.path.exists(image_path):
        raise FileNotFoundError(f"Image not found: {image_path}")

    original_img = Image.open(image_path).convert("RGB")

    result, detected_pixels, inference_time, fps, overlay_img, mask_img = detector.run_on_image(
        original_img=original_img,
        device=device,
        threshold=threshold,
    )

    print("Input type: Image")
    print(f"Detected pixels: {detected_pixels}")
    print(f"{detector.feature_name} detected: {result}")

    return original_img, overlay_img, mask_img, result, detected_pixels, inference_time, fps


# Process Video Input
def process_video(video_path, detector, device, threshold=500,
                  frame_interval_seconds=1, max_video_seconds=10):

    if not os.path.exists(video_path):
        raise FileNotFoundError(f"Video not found: {video_path}")

    cap = cv2.VideoCapture(video_path)

    if not cap.isOpened():
        raise ValueError("Could not open video file.")

    video_fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    video_duration = total_frames / video_fps if video_fps > 0 else 0

    print("Input type: Video")
    print(f"Video duration: {video_duration:.2f} seconds")

    if video_duration > max_video_seconds:
        print(f"Warning: The video is longer than {max_video_seconds} seconds.")
        print("Only selected frames from the video will be checked.")

    frame_step = int(video_fps * frame_interval_seconds)

    if frame_step <= 0:
        frame_step = 1

    selected_frames = []
    frame_number = 0

    while cap.isOpened():
        ret, frame = cap.read()

        if not ret:
            break

        if frame_number % frame_step == 0:
            quality_score = get_frame_quality_score(frame)

            if quality_score > 0:
                selected_frames.append({
                    "frame_number": frame_number,
                    "frame": frame.copy(),
                    "quality_score": quality_score,
                })

        frame_number += 1

    cap.release()

    if len(selected_frames) == 0:
        print("No good-quality frames were found.")
        return None, None, None, None, None, None, None

    best_frame_info = max(selected_frames, key=lambda x: x["quality_score"])
    best_frame = best_frame_info["frame"]
    best_frame_number = best_frame_info["frame_number"]

    best_frame_rgb = cv2.cvtColor(best_frame, cv2.COLOR_BGR2RGB)
    best_pil_img = Image.fromarray(best_frame_rgb)

    result, detected_pixels, inference_time, fps, overlay_img, mask_img = detector.run_on_image(
        original_img=best_pil_img,
        device=device,
        threshold=threshold,
    )

    print(f"Checked frames: {len(selected_frames)}")
    print(f"Best frame number: {best_frame_number}")
    print(f"Best frame quality score: {best_frame_info['quality_score']:.2f}")
    print(f"Detected pixels: {detected_pixels}")
    print(f"{detector.feature_name} detected: {result}")

    return best_pil_img, overlay_img, mask_img, result, detected_pixels, inference_time, fps


# Main Function (CLI entry point)
def main():
    device = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")

    if not os.path.exists(INPUT_PATH):
        raise FileNotFoundError(f"Input file not found: {INPUT_PATH}")

    if not os.path.exists(TEMPLATE_PATH):
        raise FileNotFoundError(f"PDF template not found: {TEMPLATE_PATH}")

    detector = TactileFlooringDetector()

    if not os.path.exists(detector.model_path):
        raise FileNotFoundError(f"Model not found: {detector.model_path}")

    detector.load(device)

    if is_image_file(INPUT_PATH):
        original_img, overlay_img, mask_img, result, detected_pixels, inference_time, fps = process_image(
            image_path=INPUT_PATH,
            detector=detector,
            device=device,
            threshold=THRESHOLD,
        )

    elif is_video_file(INPUT_PATH):
        original_img, overlay_img, mask_img, result, detected_pixels, inference_time, fps = process_video(
            video_path=INPUT_PATH,
            detector=detector,
            device=device,
            threshold=THRESHOLD,
            frame_interval_seconds=FRAME_INTERVAL_SECONDS,
            max_video_seconds=MAX_VIDEO_SECONDS,
        )

        if original_img is None:
            print("PDF report was not generated because no good-quality frame was found.")
            return

    else:
        raise ValueError("Unsupported file type. Please use an image or video file.")

    if result == "Yes":
        accessibility_feature = f"Accessibility Feature Detected: {detector.feature_name}"
    else:
        accessibility_feature = "No Accessibility Feature Detected"

    contrast_percentage, region_luminance, surrounding_luminance = detector.calculate_contrast(
        original_img, mask_img
    )

    dsapt_compliance_score, dsapt_compatibility_label, notes = detector.get_compatibility(
        detected=result == "Yes",
        contrast_percentage=contrast_percentage,
    )

    print(f"Tactile area luminance: {region_luminance:.2f}")
    print(f"Surrounding area luminance: {surrounding_luminance:.2f}")
    print(f"Estimated luminance contrast: {contrast_percentage:.2f}%")
    print(f"DSAPT compatibility score: {dsapt_compliance_score}%")
    print(f"DSAPT compatibility label: {dsapt_compatibility_label}")

    report_path = pdf_report(
        input_image=original_img,
        processed_image=overlay_img,
        accessibility_feature=accessibility_feature,
        dsapt_compliance_score=dsapt_compliance_score,
        notes=notes,
        output_path=OUTPUT_PDF_PATH,
        template_path=TEMPLATE_PATH,
    )

    print(f"PDF report generated successfully: {report_path}")


# FastAPI Analysis Function
def analyze_uploaded_file(file_bytes, filename):
    """
    Runs the AI model on an uploaded image or video file.
    Returns analysis results, processed image bytes, and PDF bytes.
    """

    device = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")

    detector = TactileFlooringDetector()

    if not os.path.exists(detector.model_path):
        raise FileNotFoundError(f"Model not found: {detector.model_path}")

    if not os.path.exists(TEMPLATE_PATH):
        raise FileNotFoundError(f"PDF template not found: {TEMPLATE_PATH}")

    detector.load(device)

    suffix = os.path.splitext(filename)[1]

    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
        temp_file.write(file_bytes)
        temp_path = temp_file.name

    try:
        if is_image_file(temp_path):
            original_img, overlay_img, mask_img, result, detected_pixels, inference_time, fps = process_image(
                image_path=temp_path,
                detector=detector,
                device=device,
                threshold=THRESHOLD,
            )

        elif is_video_file(temp_path):
            original_img, overlay_img, mask_img, result, detected_pixels, inference_time, fps = process_video(
                video_path=temp_path,
                detector=detector,
                device=device,
                threshold=THRESHOLD,
                frame_interval_seconds=FRAME_INTERVAL_SECONDS,
                max_video_seconds=MAX_VIDEO_SECONDS,
            )

            if original_img is None:
                raise ValueError("No valid video frames found.")

        else:
            raise ValueError("Unsupported file type.")

        if result == "Yes":
            accessibility_feature = f"Accessibility Feature Detected: {detector.feature_name}"
        else:
            accessibility_feature = "No Accessibility Feature Detected"

        contrast_percentage, region_luminance, surrounding_luminance = detector.calculate_contrast(
            original_img, mask_img
        )

        dsapt_compliance_score, dsapt_compatibility_label, notes = detector.get_compatibility(
            detected=result == "Yes",
            contrast_percentage=contrast_percentage,
        )

        print(f"Tactile area luminance: {region_luminance:.2f}")
        print(f"Surrounding area luminance: {surrounding_luminance:.2f}")
        print(f"Estimated luminance contrast: {contrast_percentage:.2f}%")
        print(f"DSAPT compatibility score: {dsapt_compliance_score}%")
        print(f"DSAPT compatibility label: {dsapt_compatibility_label}")

        report_path = pdf_report(
            input_image=original_img,
            processed_image=overlay_img,
            accessibility_feature=accessibility_feature,
            dsapt_compliance_score=dsapt_compliance_score,
            notes=notes,
            output_path=OUTPUT_PDF_PATH,
            template_path=TEMPLATE_PATH,
        )

        print(f"PDF report generated successfully: {report_path}")

        overlay_pil = Image.fromarray(overlay_img)
        image_buffer = io.BytesIO()
        overlay_pil.save(image_buffer, format="PNG")
        output_image_bytes = image_buffer.getvalue()

        with open(report_path, "rb") as pdf_file:
            pdf_bytes = pdf_file.read()

        return {
            "has_tactile_flooring": result == "Yes",
            "compatibility_percentage": dsapt_compliance_score,
            "compatibility_label": dsapt_compatibility_label,
            "contrast_percentage": contrast_percentage,
            "notes": notes,
            "output_image_data": output_image_bytes,
            "report_pdf": pdf_bytes,
        }

    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)


if __name__ == "__main__":
    main()
