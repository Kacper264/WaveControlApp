class CommandHistory {
  final String topic;
  final String message;
  final DateTime timestamp;
  final bool success;
  final String? error;

  CommandHistory({
    required this.topic,
    required this.message,
    required this.timestamp,
    required this.success,
    this.error,
  });

  @override
  String toString() {
    return '${timestamp.toLocal().toString().split('.')[0]} - $topic: $message ${success ? '✓' : '✗'}';
  }
}