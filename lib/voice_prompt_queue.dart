class VoicePromptQueue {
  final List<String> _queue = [];

  void produce(String item) {
    _queue.add(item);
  }

  String consumeItems() {
    if (_queue.isEmpty) {
      throw StateError('No items in queue');
    }
    return _queue.removeAt(0);
  }

  void clear() {
    _queue.clear();
  }
}

