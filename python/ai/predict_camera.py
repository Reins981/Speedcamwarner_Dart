#!/usr/bin/env python3
import json
import os
import sys
import joblib
import pandas as pd

def predict_speed_camera(model, latitude, longitude, time_of_day, day_of_week):
    if ":" in time_of_day:
        time_of_day = "evening" if int(time_of_day.split(":")[0]) > 18 else "morning"
    input_data = {
        'latitude': [latitude],
        'longitude': [longitude],
        'time_of_day': [time_of_day],
        'day_of_week': [day_of_week]
    }
    input_df = pd.DataFrame(input_data)
    input_df = pd.get_dummies(input_df, columns=['time_of_day', 'day_of_week'])
    for col in model.feature_names_in_:
        if col not in input_df.columns:
            input_df[col] = 0
    input_df = input_df[model.feature_names_in_]
    prediction = model.predict(input_df)
    return prediction[0].tolist()

def main():
    if len(sys.argv) != 5:
        print("[]")
        return 1
    latitude = float(sys.argv[1])
    longitude = float(sys.argv[2])
    time_of_day = sys.argv[3]
    day_of_week = sys.argv[4]
    model_path = os.path.join(os.path.dirname(__file__), "speed_camera_model.pkl")
    model = joblib.load(model_path)
    prediction = predict_speed_camera(model, latitude, longitude, time_of_day, day_of_week)
    print(json.dumps(prediction))
    return 0

if __name__ == "__main__":
    sys.exit(main())
