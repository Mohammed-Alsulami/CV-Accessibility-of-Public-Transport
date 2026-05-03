from datetime import datetime
import os
import time
import numpy as np
import torch
from PIL import Image
from torchvision import transforms
import matplotlib.pyplot as plt

from src import GRFBUNet


def load_model(model_path, device):
    classes = 1
    model = GRFBUNet(in_channels=3, num_classes=classes + 1, base_c=32)

    checkpoint = torch.load(model_path, map_location="cpu", weights_only=False)
    model.load_state_dict(checkpoint["model"])
    model.to(device)
    model.eval()

    return model


def preprocess_image(image):
    mean = (0.709, 0.381, 0.224)
    std = (0.127, 0.079, 0.043)

    transform = transforms.Compose([
        transforms.Resize(565),
        transforms.ToTensor(),
        transforms.Normalize(mean=mean, std=std)
    ])

    return transform(image)


def create_overlay(original_img, prediction_mask):
    orig_np = np.array(original_img).copy()
    mask_np = np.array(prediction_mask)

    binary_mask = mask_np > 0

    overlay = orig_np.copy()
    overlay[binary_mask] = [255, 0, 0]

    blended = (0.6 * orig_np + 0.4 * overlay).astype(np.uint8)
    return blended


def main():
    image_path = "/Users/mohammed-alsulami/Desktop/Sprint-3 Model/test1.jpg" # <----- Image path
    threshold = 500
    model_path = "/Users/mohammed-alsulami/Desktop/Sprint-3 Model/model/model_best.pth" # <---- Model path

    device = torch.device("cuda:0" if torch.cuda.is_available() else "cpu")
    print(f"using {device} device.")

    if not os.path.exists(image_path):
        raise FileNotFoundError(f"Image not found: {image_path}")

    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model not found: {model_path}")

    original_img = Image.open(image_path).convert("RGB")
    original_w, original_h = original_img.size

    img = preprocess_image(original_img)
    img = torch.unsqueeze(img, dim=0)

    model = load_model(model_path, device)

    with torch.no_grad():
        img_height, img_width = img.shape[-2:]
        init_img = torch.zeros((1, 3, img_height, img_width), device=device)
        model(init_img)

        start_time = time.time()
        output = model(img.to(device))
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

    print(f"inference time: {inference_time:.4f} s")
    print(f"FPS: {fps:.4f}")
    print(f"Detected pixels: {detected_pixels}")
    print(f"Tactile flooring detected: {result}")

    plt.figure(figsize=(10, 10))
    plt.imshow(overlay_img)
    plt.title(f"Tactile flooring detected: {result}")
    plt.axis("off")
    plt.show()

def pdf_report(input_image, processed_image, dsapt_compliance_score, notes,
               output_path="output_report.pdf", template_path="Report_Template.pdf"):
    import io
    from reportlab.pdfgen import canvas
    from reportlab.lib.utils import ImageReader
    from pdfrw import PdfReader, PdfWriter, PageMerge

    PAGE_W, PAGE_H = 612, 792

    # Convert input to PIL Image (accepts file path, PIL Image, or numpy array)
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
        draw_w, draw_h = iw * scale, ih * scale
        draw_x = cell_x + (cell_w - draw_w) / 2
        draw_y = cell_y_bottom + (cell_h - draw_h) / 2
        c.drawImage(ImageReader(pil_img), draw_x, draw_y, draw_w, draw_h)

    def draw_wrapped_text(c, text, x, y, max_width, font_name, font_size, line_height):
        words = str(text).split()
        lines, current = [], ""
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

    # Date
    c.setFont("Helvetica", 11)
    c.drawString(205.33, 465.15, datetime.now().strftime("%d/%m/%Y"))

    # Input image (cell: x=205–540, y=355–455)
    pil_in = to_pil(input_image)
    if pil_in:
        draw_image_in_cell(c, pil_in, 205.33, 355, 540 - 205.33, 100)

    # Processed/output image (cell: x=205–540, y=218–340)
    pil_out = to_pil(processed_image)
    if pil_out:
        draw_image_in_cell(c, pil_out, 205.33, 218, 540 - 205.33, 122)

    # DSAPT Compliance Score
    c.setFont("Helvetica", 11)
    c.drawString(205.33, 210.58, f"{dsapt_compliance_score}%")

    # Notes (wrapped)
    draw_wrapped_text(c, notes, 205.33, 185.55, 335, "Helvetica", 10, 12)

    c.save()
    packet.seek(0)

    template = PdfReader(template_path)
    overlay_pdf = PdfReader(packet)
    PageMerge(template.pages[0]).add(overlay_pdf.pages[0]).render()
    PdfWriter(output_path, trailer=template).write()

    return output_path




if __name__ == "__main__":
    main()
