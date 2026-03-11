class CommandHistory {
  final String topic;
  final String message;
  final DateTime timestamp;
  final bool success;
  final String? error;
  final bool isIncoming;
  final bool isRetained;

  CommandHistory({
    required this.topic,
    required this.message,
    required this.timestamp,
    required this.success,
    this.error,
    this.isIncoming = false,
    this.isRetained = false,
  });

  @override
  String toString() {
    final direction = isIncoming ? 'IN' : 'OUT';
    final retained = isRetained ? ' [R]' : '';
    return '${timestamp.toLocal().toString().split('.')[0]} - [$direction$retained] $topic: $message ${success ? '✓' : '✗'}';
  }
}