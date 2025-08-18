# Speed Camera Warning App

This is a Flutter-based Android application that predicts the nearest speed camera based on GPS data. The app is a conversion of an existing Python project into Dart for better compatibility with Android development.

## Features
- Predicts the nearest speed camera coordinates.
- Uses machine learning models for accurate predictions.
- User-friendly interface built with Flutter.
- Real-time dashboard displays current direction and average bearing.

## Getting Started
1. Install Flutter: [Flutter Installation Guide](https://docs.flutter.dev/get-started/install).
2. Clone this repository.
3. Run `flutter pub get` to install dependencies.
4. Use `flutter run` to launch the app on an emulator or device.

## GPX Simulation
For development and testing without relying on a real GPS receiver, the app can
replay coordinates from a GPX track. On the **Actions** page press **Start (GPX)**
to launch the app using the sample track located at `gpx/nordspange_tr2.gpx`.

## Cloud data and rate limiting

The application downloads speed camera and construction zone information from a
cloud service. Access to this data requires a valid Google service account JSON
file placed at `python/service_account/<your-service-account>.json`. Without this
file the log will show messages like `Service account file not found` and the
app will fall back to the limited data bundled with the repository.

To avoid excessive network traffic the lookahead requests are rate limited. The
interval for speed‑camera downloads is controlled by the
`dosAttackPreventionIntervalDownloads` variable in
`lib/rectangle_calculator.dart` (default `30` seconds). Construction area
queries use a separate `constructionAreaLookupInterval` (default `120`
seconds) to further reduce server load. Adjust these values if you need more
frequent updates during development.

## Project Structure
- `lib/`: Contains the main application code.
- `assets/`: Stores static assets like images and JSON files.
- `test/`: Includes unit and widget tests.

## Contributing
Feel free to submit issues or pull requests to improve the app.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
