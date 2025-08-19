import 'package:test/test.dart';
import '../lib/config.dart';

void main() {
  test('voice_prompt_source accepts boolean without crashing', () {
    AppConfig.loadFromMap({
      'accusticWarner': {'voice_prompt_source': false},
    });

    final aiVoice =
        (AppConfig.get<dynamic>('accusticWarner.voice_prompt_source') ??
                'dialogflow') ==
            'dialogflow';

    expect(aiVoice, isFalse);
  });
}
