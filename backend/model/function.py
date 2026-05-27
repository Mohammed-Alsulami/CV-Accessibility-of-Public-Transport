from datetime import datetime
import io
import os
import tempfile

import cv2
import numpy as np
from PIL import Image

from .utils import get_frame_quality_score, is_image_file, is_video_file

# Singleton: model is loaded once at first request and reused for all subsequent requests.
# Loading PyTorch weights from disk takes 5-30s — doing it per-request was the main bottleneck.
_cached_detector = None
_cached_device = None


def _get_detector():
    global _cached_detector, _cached_device
    if _cached_detector is None:
        import torch
        from .features import TactileFlooringDetector
        # Limit PyTorch threads to avoid overwhelming an already-loaded CPU.
        torch.set_num_threads(4)
        torch.set_num_interop_threads(2)
        _cached_device = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")
        det = TactileFlooringDetector()
        if not os.path.exists(det.model_path):
            raise FileNotFoundError(f"Model not found: {det.model_path}")
        det.load(_cached_device)
        _cached_detector = det
    return _cached_detector, _cached_device


# USER SETTINGS - CHANGE THESE ONLY

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

INPUT_PATH = ""

TEMPLATE_PATH = os.path.join(BASE_DIR, "Report_Template.pdf")

OUTPUT_PDF_PATH = os.path.join(BASE_DIR, "output_report.pdf")

THRESHOLD = 500

FRAME_INTERVAL_SECONDS = 1
MAX_VIDEO_SECONDS = 10

# PDF Report Generation
# output_path=None → returns PDF bytes in memory (no disk I/O).
# Pass a file path string to write to disk (CLI usage).
def pdf_report(input_image, processed_image, accessibility_feature,
               dsapt_compliance_score, notes,
               output_path=None, template_path="Report_Template.pdf"):

    from reportlab.pdfgen import canvas
    from reportlab.lib.utils import ImageReader
    from pdfrw import PdfReader, PdfWriter, PageMerge

    PAGE_W, PAGE_H = 612, 792

    # Value column geometry — read directly from the template PDF content stream.
    # These numbers are exact: do not adjust them.
    VAL_X = 198.58   # left edge of the value (right) column
    VAL_W = 323.65   # width of the value column
    TEXT_X = 205.33  # where text starts inside each value cell (left padding)

    def to_pil(img_input):
        if isinstance(img_input, np.ndarray):
            return Image.fromarray(img_input.astype(np.uint8)).convert("RGB")
        if isinstance(img_input, Image.Image):
            return img_input.convert("RGB")
        if isinstance(img_input, str) and os.path.exists(img_input):
            return Image.open(img_input).convert("RGB")
        return None

    def whiteout(c, y_bottom, h):
        """Cover a template placeholder with a white rectangle."""
        c.setFillColorRGB(1, 1, 1)
        c.setStrokeColorRGB(1, 1, 1)
        c.rect(VAL_X, y_bottom, VAL_W, h, fill=1, stroke=0)

    def draw_image_in_cell(c, pil_img, cell_x, cell_y_bottom, cell_w, cell_h, padding=4):
        # Downsample to 2× the cell's point dimensions before embedding.
        # Prevents full-resolution images (e.g. 4 MP) from bloating the PDF.
        max_embed_w = int(cell_w * 2)
        max_embed_h = int(cell_h * 2)
        if pil_img.width > max_embed_w or pil_img.height > max_embed_h:
            pil_img = pil_img.copy()
            pil_img.thumbnail((max_embed_w, max_embed_h), Image.LANCZOS)
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

    # 1. Date  — template cell: y=462.9, h=12.75
    whiteout(c, 462.9, 12.75)
    c.setFillColorRGB(0, 0, 0)
    c.setFont("Helvetica", 11)
    c.drawString(TEXT_X, 465.15, datetime.now().strftime("%d/%m/%Y"))

    # 2. Input image  — template cell: y=367.13, h=83.275
    whiteout(c, 367.13, 83.275)
    pil_in = to_pil(input_image)
    if pil_in:
        draw_image_in_cell(c, pil_in, VAL_X, 367.13, VAL_W, 83.275)

    # 3. Accessibility feature  — template cell: y=329.35, h=25.25
    whiteout(c, 329.35, 25.25)
    c.setFillColorRGB(0, 0, 0)
    c.setFont("Helvetica", 11)
    draw_wrapped_text(c, accessibility_feature, TEXT_X, 344.35, VAL_W - 10, "Helvetica", 11, 13)

    # 4. Output image  — template cell: y=233.58, h=83.275
    whiteout(c, 233.58, 83.275)
    pil_out = to_pil(processed_image)
    if pil_out:
        draw_image_in_cell(c, pil_out, VAL_X, 233.58, VAL_W, 83.275)

    # 5. DSAPT compatibility  — template cell: y=208.33, h=12.75
    whiteout(c, 208.33, 12.75)
    c.setFillColorRGB(0, 0, 0)
    c.setFont("Helvetica", 11)
    c.drawString(TEXT_X, 210.58, f"{dsapt_compliance_score}%")

    # 6. Notes  — template cell: y=170.55, h=25.25
    whiteout(c, 170.55, 25.25)
    c.setFillColorRGB(0, 0, 0)
    draw_wrapped_text(c, notes, TEXT_X, 185.55, VAL_W - 10, "Helvetica", 10, 12)

    c.save()
    packet.seek(0)

    template = PdfReader(template_path)
    overlay_pdf = PdfReader(packet)

    PageMerge(template.pages[0]).add(overlay_pdf.pages[0]).render()

    if output_path is None:
        buf = io.BytesIO()
        PdfWriter(buf, trailer=template).write()
        return buf.getvalue()

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
    import torch
    from .features import TactileFlooringDetector
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
        accessibility_feature = detector.feature_name
    else:
        accessibility_feature = "None"

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

    if not os.path.exists(TEMPLATE_PATH):
        raise FileNotFoundError(f"PDF template not found: {TEMPLATE_PATH}")

    detector, device = _get_detector()

    suffix = os.path.splitext(filename)[1].lower()

    temp_path = None
    try:
        if is_image_file(filename):
            # Open image directly from bytes — no temp file needed.
            original_img = Image.open(io.BytesIO(file_bytes)).convert("RGB")
            result, detected_pixels, inference_time, fps, overlay_img, mask_img = detector.run_on_image(
                original_img=original_img,
                device=device,
                threshold=THRESHOLD,
            )
            print("Input type: Image")
            print(f"Detected pixels: {detected_pixels}")
            print(f"{detector.feature_name} detected: {result}")

        elif is_video_file(filename):
            with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
                temp_file.write(file_bytes)
                temp_path = temp_file.name

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
            accessibility_feature = detector.feature_name
        else:
            accessibility_feature = "None"

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

        # Generate PDF entirely in memory — no disk I/O, no race condition.
        pdf_bytes = pdf_report(
            input_image=original_img,
            processed_image=overlay_img,
            accessibility_feature=accessibility_feature,
            dsapt_compliance_score=dsapt_compliance_score,
            notes=notes,
            template_path=TEMPLATE_PATH,
        )

        print("PDF report generated successfully (in memory).")

        overlay_pil = Image.fromarray(overlay_img)
        image_buffer = io.BytesIO()
        overlay_pil.save(image_buffer, format="PNG")
        output_image_bytes = image_buffer.getvalue()

        input_buf = io.BytesIO()
        original_img.save(input_buf, format="JPEG", quality=90)
        input_image_bytes = input_buf.getvalue()

        return {
            "has_tactile_flooring": result == "Yes",
            "compatibility_percentage": dsapt_compliance_score,
            "compatibility_label": dsapt_compatibility_label,
            "contrast_percentage": contrast_percentage,
            "notes": notes,
            "input_image_data": input_image_bytes,
            "output_image_data": output_image_bytes,
            "report_pdf": pdf_bytes,
        }

    finally:
        if temp_path and os.path.exists(temp_path):
            os.remove(temp_path)


if __name__ == "__main__":
    main()
