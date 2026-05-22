from .base import FeatureDetector
from .tactile_flooring import TactileFlooringDetector

# Registry of all active feature detectors.
#
# To add a new feature:
#   1. Create a new file in this directory (e.g. handrail.py) that subclasses FeatureDetector.
#   2. Import it below.
#   3. Append its class to REGISTERED_FEATURES.
#
# See backend/model/README.md for the full step-by-step guide.
REGISTERED_FEATURES = [
    TactileFlooringDetector,
]
