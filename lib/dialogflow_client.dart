import 'dart:convert';
import 'dart:io';

import 'package:dialog_flowtter/dialog_flowtter.dart';
import 'package:uuid/uuid.dart';

/// A client for interacting with Dialogflow's detect intent API.
///
/// This is a Dart port of the Python implementation found in
/// `python/dialogflow_client.py`.
abstract class DialogflowService {
  Future<String> detectIntent(String text);
}

/// Exception thrown when an error occurs while communicating with Dialogflow.
class DialogflowException implements Exception {
  final String message;
  DialogflowException(this.message);

  @override
  String toString() => 'DialogflowException: $message';
}

/// Real implementation backed by the Google Dialogflow service.
class DialogflowClient implements DialogflowService {
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

  /// Construct a [DialogflowClient] using credentials stored in [jsonPath].
  factory DialogflowClient.fromServiceAccountFile({
    required String projectId,
    required String jsonPath,
    String languageCode = 'en',
  }) {
    try {
      final content = File(jsonPath).readAsStringSync();
      final jsonMap = jsonDecode(content) as Map<String, dynamic>;
      final creds = DialogAuthCredentials.fromJson(jsonMap);
      return DialogflowClient(
        projectId: projectId,
        credentials: creds,
        languageCode: languageCode,
      );
    } catch (e) {
      throw DialogflowException('Failed to load credentials: $e');
    }
  }

  /// Detects the intent of the supplied [text] using Dialogflow.
  ///
  /// A new session is created for every request mirroring the behaviour
  /// of the original Python implementation. On success the fulfilment
  /// text returned by Dialogflow is provided. On failure an exception is
  /// thrown so callers can react appropriately.
  @override
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
      throw DialogflowException('Error during Dialogflow request: $e');
    }
  }
}

/// Fallback implementation used when Dialogflow cannot be initialised.
class FallbackDialogflowClient implements DialogflowService {
  @override
  Future<String> detectIntent(String text) async =>
      "Sorry, I couldn't process your request.";
}
