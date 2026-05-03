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

def pdf_report(pdf_content, output_path="report_output.pdf", template_path="pdf_template.pdf"):
    """Fill pdf_template.pdf with pdf_content values and save to output_path.

    pdf_content keys: date, image_file, detection_result, detected_pixels,
                      inference_time, fps, notes (optional)
    """
    import io
    from reportlab.pdfgen import canvas
    from reportlab.lib.pagesizes import letter
    from reportlab.lib.colors import HexColor, black
    from pdfrw import PdfReader, PdfWriter, PageMerge

    return "PDF generation not implemented yet."




if __name__ == "__main__":
    main()
