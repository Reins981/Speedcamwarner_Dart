# export_to_onnx.py
import json, joblib, os
import numpy as np
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType

# 1) Load your trained model
model_path = os.path.join(os.path.abspath(os.path.dirname(__file__)), '../python/ai/speed_camera_model.pkl')
model = joblib.load(model_path)

# 2) Persist the exact feature order the model expects
#    This is critical because you used pandas.get_dummies when training.
feature_names = list(model.feature_names_in_)
with open("feature_names.json", "w") as f:
    json.dump(feature_names, f)

# 3) Export to ONNX
onx = convert_sklearn(
    model,
    initial_types=[("input", FloatTensorType([None, len(feature_names)]))],
)
with open("model.onnx", "wb") as f:
    f.write(onx.SerializeToString())

print("Wrote model.onnx and feature_names.json")
