import 'package:dialog_flowtter/dialog_flowtter.dart';
import 'package:uuid/uuid.dart';

/// A client for interacting with Dialogflow's detect intent API.
///
/// This is a Dart port of the Python implementation found in
/// `python/dialogflow_client.py`.
class DialogflowClient {
  /// The Dialogflow project identifier.
  final String projectId;

  /// Language code for requests, defaults to English.
  final String languageCode;

  /// Service account credentials used for authentication.
  final DialogAuthCredentials credentials;

  /// Creates a [DialogflowClient] instance.
  DialogflowClient({
    required this.projectId,
    required this.credentials,
    this.languageCode = 'en',
  });

  /// Detects the intent of the supplied [text] using Dialogflow.
  ///
  /// A new session is created for every request mirroring the behaviour
  /// of the original Python implementation. On success the fulfilment
  /// text returned by Dialogflow is provided. On failure a generic
  /// error message is returned and the error is printed to the console.
  Future<String> detectIntent(String text) async {
    final sessionId = const Uuid().v4();
    try {
      final dialog = DialogFlowtter(
        credentials: credentials,
        projectId: projectId,
        sessionId: sessionId,
      );

      final queryInput = QueryInput(
        text: TextInput(
          text: text,
          languageCode: languageCode,
        ),
      );

      final response = await dialog.detectIntent(queryInput: queryInput);
      dialog.dispose();

      return response.text ?? '';
    } catch (e) {
      // Mimic behaviour of the Python client by logging the error and
      // returning a default message.
      // ignore: avoid_print
      print('Error during Dialogflow request: $e');
      return "Sorry, I couldn't process your request.";
    }
  }
}
