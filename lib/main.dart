import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'screens/splash_screen.dart';
import 'services/mqtt_service.dart';
import 'services/app_settings.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Verrouiller l'orientation en mode portrait uniquement
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  
  // Configuration iOS-style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.light,
    ),
  );
  
  // Charger les préférences avant de lancer l'app
  final settings = AppSettings();
  await Future.delayed(const Duration(milliseconds: 100)); // Laisser le temps de charger
  
  runApp(const MyApp());

  // Connect MQTT and request device list at app launch
  MQTTService().connect(
    server: settings.mqttServer,
    port: settings.mqttPort,
    username: settings.mqttUsername,
    password: settings.mqttPassword,
  ).then((connected) {
    if (connected) {
      MQTTService().publishMessage('home/matter/request', 'test');
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AppSettings _settings = AppSettings();
  final MQTTService _mqtt = MQTTService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  String? _lastMoveNotificationId;
  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _mqtt.addListener(_onMqttChanged);
  }

  @override
  void dispose() {
    _hideToast();
    _mqtt.removeListener(_onMqttChanged);
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    setState(() {});
  }

  void _onMqttChanged() {
    final messages = _mqtt.recentMessages;
    if (messages.isEmpty) return;

    final moveMessage = messages.firstWhere(
      (m) =>
          m.isIncoming &&
          (m.topic == 'home/wristband/move' || m.topic == 'home/wrisband/move'),
      orElse: () => messages.first,
    );

    if (!(moveMessage.isIncoming &&
        (moveMessage.topic == 'home/wristband/move' ||
            moveMessage.topic == 'home/wrisband/move'))) {
      return;
    }

    if (moveMessage.isRetained) {
      return;
    }

    final messageId =
        '${moveMessage.topic}_${moveMessage.message}_${moveMessage.timestamp.toIso8601String()}';
    if (_lastMoveNotificationId == messageId) return;
    _lastMoveNotificationId = messageId;

    if (!_settings.enableSuccessNotifications) return;

    final movement = _extractMovement(moveMessage.message);
    _showToast(
      '${_settings.text('movement_detected')}: $movement',
      backgroundColor: AppTheme.successGreen,
      icon: Icons.check_circle_rounded,
    );
  }

  String _extractMovement(String payload) {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) return 'inconnu';

    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final movement = decoded['movement'] ?? decoded['mouvement'] ?? decoded['move'];
          if (movement != null) return movement.toString();
        }
      } catch (_) {}
    }

    return trimmed;
  }

  void _hideToast() {
    _toastEntry?.remove();
    _toastEntry = null;
  }

  void _showToast(
    String message, {
    Color? backgroundColor,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = _navigatorKey.currentState?.overlay;
    final context = _navigatorKey.currentContext;
    if (overlay == null || context == null) return;

    _hideToast();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = backgroundColor ?? (isDark ? AppTheme.darkElevated : Colors.grey[900]!);

    final entry = OverlayEntry(
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                builder: (context, value, child) => Transform.translate(
                  offset: Offset(0, -10 * (1 - value)),
                  child: Opacity(opacity: value, child: child),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppTheme.cardShadow(isDark),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    _toastEntry = entry;

    Future.delayed(duration, () {
      if (_toastEntry == entry) {
        _hideToast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WaveControl',
      navigatorKey: _navigatorKey,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _settings.themeMode,
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
