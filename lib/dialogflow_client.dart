class DialogflowClient {
  // ...existing code...

  // User phrases for voice commands
  final List<String> userPhrases = [
    // EXIT / STOP
    "Exit the app",
    "Close the application",
    "Stop running",
    "Shut down the speed camera app",
    "Quit",
    "Terminate",
    "End application",

    // ADD POLICE
    "I saw a police car",
    "Add a police warning",
    "There’s a police checkpoint",
    "Mark police location",
    "Report police",
    "Police ahead",
    "Police trap",
    "Add police marker",

    // POLICE ADD FAIL
    "Adding police didn't work",
    "Police marker failed",
    "Failed to add police marker",
  ];

  // Additional user phrases for various scenarios
  final List<String> additionalPhrases = [
    // GPS
    "GPS is off",
    "Turn on GPS",
    "I lost GPS signal",
    "GPS is weak",
    "GPS is back online",
    "No GPS",
    "GPS unavailable",
    "GPS signal lost",

    // INTERNET / OSM DATA
    "No internet connection",
    "The map isn’t loading",
    "Can't download data",
    "Why is there no data from the server?",
    "No map data",
    "Offline mode",
    "No connection",
    "Server not reachable",

    // HAZARD
    "There’s a hazard ahead",
    "Danger on the road",
    "I see something dangerous",
    "Hazard detected",
    "Road hazard",
    "Obstacle ahead",

    // SPEED CAMERA WARNINGS

    // Fixed camera distance prompts
    "Fixed camera 100 meters ahead",
    "Fixed camera ahead in 100 meters",
    "There is a fixed camera 100 meters away",
    "Fixed speed camera 100 meters ahead",
    "Fixed camera coming up in 100 meters",
    "Fixed camera 300 meters ahead",
    "Fixed camera ahead in 300 meters",
    "There is a fixed camera 300 meters away",
    "Fixed speed camera 300 meters ahead",
    "Fixed camera coming up in 300 meters",
    "Fixed camera 500 meters ahead",
    "Fixed camera ahead in 500 meters",
    "There is a fixed camera 500 meters away",
    "Fixed speed camera 500 meters ahead",
    "Fixed camera coming up in 500 meters",
    "Fixed camera 1000 meters ahead",
    "Fixed camera ahead in 1000 meters",
    "There is a fixed camera 1000 meters away",
    "Fixed speed camera 1000 meters ahead",
    "Fixed camera coming up in 1000 meters",

    // Traffic camera distance prompts
    "Traffic camera 100 meters ahead",
    "Traffic camera ahead in 100 meters",
    "There is a traffic camera 100 meters away",
  ];

  // Method to process user phrases
  void processUserPhrase(String phrase) {
    if (userPhrases.contains(phrase) || additionalPhrases.contains(phrase)) {
      print("Processing command: $phrase");
      // Add logic to handle specific commands
    } else {
      print("Unknown command: $phrase");
    }
  }
}
