class DeviceState {
  final String topic;
  String state; // e.g. 'ON' / 'OFF' / others
  String? color; // hex string like '#RRGGBB'
  int _brightness = 0; // stocké en 0-255
  List<int>? rgbColor; // [R,G,B] values
  DateTime lastUpdated;

  // Getter/Setter pour brightness en pourcentage
  int get brightness => (_brightness * 100 / 255).round();
  set brightness(int percent) {
    _brightness = ((percent * 255) / 100).round();
  }

  // Getter pour la valeur brute de brightness
  int get rawBrightness => _brightness;

  DeviceState({
    required this.topic,
    required this.state,
    this.color,
    int brightness = 0,
    this.rgbColor,
    DateTime? lastUpdated,
  }) : _brightness = brightness,
       lastUpdated = lastUpdated ?? DateTime.now();

  void update({String? state, String? color, int? brightness, List<int>? rgbColor}) {
    if (state != null) this.state = state;
    if (brightness != null) _brightness = brightness; // Stocke la valeur brute
    if (rgbColor != null) {
      this.rgbColor = rgbColor;
      // Met à jour la couleur en format hex
      this.color = '#${rgbColor[0].toRadixString(16).padLeft(2, '0')}'
          '${rgbColor[1].toRadixString(16).padLeft(2, '0')}'
          '${rgbColor[2].toRadixString(16).padLeft(2, '0')}';
    }
    if (color != null) this.color = color;
    lastUpdated = DateTime.now();
  }

  String get displayColor {
    if (state != 'ON') return '#808080'; // Gris si éteint
    return color ?? '#FFFFFF'; // Blanc par défaut si pas de couleur
  }

  @override
  String toString() => '${lastUpdated.toLocal().toIso8601String()} • $topic: $state'
      '${brightness > 0 ? ' (${brightness}%)' : ''}'
      '${color != null ? ' ($color)' : ''}';
}