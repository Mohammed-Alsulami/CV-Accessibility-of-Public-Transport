from abc import ABC, abstractmethod


class FeatureDetector(ABC):
    """
    Abstract base class for accessibility feature detectors.

    Each subclass wraps one trained model and is responsible for:
    - Declaring where its weights live (model_path)
    - Loading those weights onto the target device
    - Running inference on a single PIL image
    - Calculating luminance contrast between the detected region and its surroundings
    - Returning a DSAPT compatibility assessment

    To add a new feature (e.g. handrails), create a new subclass in this package,
    implement every abstract member, then register it in features/__init__.py.
    See backend/model/README.md for a full step-by-step guide.
    """

    @property
    @abstractmethod
    def feature_name(self) -> str:
        """Human-readable name used in PDF reports, e.g. 'Tactile flooring'."""

    @property
    @abstractmethod
    def result_key(self) -> str:
        """Key used in the API response dict, e.g. 'has_tactile_flooring'."""

    @property
    @abstractmethod
    def model_path(self) -> str:
        """Absolute path to the .pth weights file for this feature's model."""

    @abstractmethod
    def load(self, device) -> None:
        """
        Load model weights onto device.
        Must be called once before run_on_image.
        """

    @abstractmethod
    def run_on_image(self, original_img, device, threshold: int = 500):
        """
        Run inference on a single PIL Image.

        Args:
            original_img: PIL.Image in RGB mode
            device: torch.device
            threshold: minimum pixel count to consider the feature detected

        Returns:
            result (str): "Yes" or "No"
            detected_pixels (int): number of detected pixels
            inference_time (float): seconds taken for the forward pass
            fps (float): inferred frames per second
            overlay_img (np.ndarray): original image with the detected region highlighted
            mask_img (PIL.Image): binary mask of the detected region
        """

    @abstractmethod
    def calculate_contrast(self, original_img, mask_img):
        """
        Calculate luminance contrast between the detected region and its surroundings.

        Args:
            original_img: PIL.Image in RGB mode
            mask_img: PIL.Image binary mask (L mode) from run_on_image

        Returns:
            contrast_percentage (float): 0–100
            region_luminance (float): mean luminance inside the detected region
            surrounding_luminance (float): mean luminance outside the detected region
        """

    @abstractmethod
    def get_compatibility(self, detected: bool, contrast_percentage: float):
        """
        Convert a contrast reading into a DSAPT compatibility result.

        Args:
            detected: True if the feature was detected
            contrast_percentage: value from calculate_contrast

        Returns:
            score (int): 0, 50, 75, or 100
            label (str): short human-readable label, e.g. 'High compatibility'
            notes (str): full explanation suitable for the PDF report
        """
