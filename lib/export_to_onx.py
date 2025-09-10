# export_to_onnx.py
import json, os
import joblib
import onnx
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType
# 1) Load your trained model
model_path = os.path.join(os.path.abspath(os.path.dirname(__file__)), '../python/ai/speed_camera_model.pkl')


MODEL_PKL = model_path
ONNX_RAW  = "model_raw.onnx"
ONNX_OUT  = "model_fixed.onnx"
FEATURES  = "feature_names.json"

# 1) Load model (make sure sklearn version matches the one used for training!)
model = joblib.load(MODEL_PKL)

# 2) Feature order (from your training pipeline)
feature_names = list(model.feature_names_in_)
with open(FEATURES, "w") as f:
    json.dump(feature_names, f)

# 3) Export to ONNX (conservative opset for mobile)
onx = convert_sklearn(
    model,
    initial_types=[("input", FloatTensorType([None, len(feature_names)]))],
    target_opset=12,
)
with open(ONNX_RAW, "wb") as f:
    f.write(onx.SerializeToString())

# 4) Patch the output shape to [None, n_out]
#    If your model predicts [lat, lon], n_out = 2.
n_out = getattr(model, "n_outputs_", None) or 2  # fall back to 2 if missing

m = onnx.load(ONNX_RAW)

# There is typically a single model output
out = m.graph.output[0]
tt = out.type.tensor_type
# Ensure rank-2: [None, n_out]
if tt.shape is None or len(tt.shape.dim) == 0:
    tt.shape.dim.add()
    tt.shape.dim.add()
else:
    # Make sure there are at least 2 dims
    while len(tt.shape.dim) < 2:
        tt.shape.dim.add()

# Batch dim unknown / variable:
tt.shape.dim[0].dim_param = "N"  # symbolic (equivalent to -1)
# Output width:
tt.shape.dim[1].dim_value = int(n_out)

# 5) (Optional) Force IR=9 for older mobile runtimes
m.ir_version = 9

onnx.save(m, ONNX_OUT)
print(f"✅ Wrote {ONNX_OUT} with output shape [None,{n_out}] and IR=9")
print(f"   Feature names saved to {FEATURES}")
