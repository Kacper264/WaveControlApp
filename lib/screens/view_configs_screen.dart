import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/mqtt_service.dart';
import '../services/app_settings.dart';
import '../models/wristband_config.dart';
import '../widgets/ios_widgets.dart';
import '../theme/app_theme.dart';
import 'dart:convert';

class ViewConfigsScreen extends StatefulWidget {
  const ViewConfigsScreen({super.key});

  @override
  State<ViewConfigsScreen> createState() => _ViewConfigsScreenState();
}

class _ViewConfigsScreenState extends State<ViewConfigsScreen> {
  final MQTTService _mqtt = MQTTService();
  final AppSettings _settings = AppSettings();
  
  List<WristbandConfig> _wristbandConfigs = [];
  bool _isLoading = false;
  String? _statusMessage;
  String? _statusType; // success | error | info
  bool _hasLoadedConfigs = false;
  String? _lastProcessedMessageId;

  @override
  void initState() {
    super.initState();
    _mqtt.addListener(_onMqttChanged);
    _settings.addListener(_onSettingsChanged);
    _wristbandConfigs = [];
    _hasLoadedConfigs = false;
    _statusMessage = null;
    _statusType = null;
    _getConfiguration();
  }

  @override
  void dispose() {
    _mqtt.removeListener(_onMqttChanged);
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onMqttChanged() {
    final messages = _mqtt.recentMessages;
    if (messages.isNotEmpty) {
      final lastMessage = messages.first;
      final messageId = '${lastMessage.topic}_${lastMessage.message}_${lastMessage.timestamp}';
      if (_lastProcessedMessageId != messageId) {
        _lastProcessedMessageId = messageId;
        _handleMqttMessage(lastMessage.topic, lastMessage.message);
      }
    }
  }

  void _onSettingsChanged() {
    setState(() {});
  }

  void _handleMqttMessage(String topic, String payload) {
    print('Message MQTT reçu - Topic: $topic, Payload: $payload');
    try {
      if (topic == 'home/wristband/get_config_response') {
        // Nettoyer les clés non quotées dans le payload
        final cleanedPayload = payload.replaceAllMapped(
          RegExp(r'(\w+):([^,}\]]+)'),
          (match) => '"${match.group(1)}":"${match.group(2)}"',
        );
        final jsonData = json.decode(cleanedPayload);
        
        print('Réception de la configuration récupérée');
        if (jsonData['config'] != null) {
          // jsonData['config'] est déjà un List après le décodage
          final configListRaw = jsonData['config'] as List;
          final configList = configListRaw.map((item) => WristbandConfig.fromJson(item)).toList();
          
          setState(() {
            _wristbandConfigs = configList;
            _isLoading = false;
            _hasLoadedConfigs = true;
            _statusMessage = _settings.text('config_loaded');
            _statusType = 'success';
          });
          
          print('${configList.length} configurations chargées');
        } else {
          setState(() {
            _wristbandConfigs = [];
            _isLoading = false;
            _hasLoadedConfigs = true;
            _statusMessage = _settings.text('no_saved_config');
            _statusType = 'info';
          });
        }
        return;
      }
    } catch (e) {
      print('Erreur de traitement du message MQTT: $e');
      setState(() {
        _isLoading = false;
        _hasLoadedConfigs = true;
        _statusMessage = '${_settings.text('parsing_error')}: $e';
        _statusType = 'error';
      });
    }
  }

  void _getConfiguration() {
    if (!_mqtt.isConnected) {
      setState(() {
        _statusMessage = '${_settings.text('not_connected_mqtt')} - ${_settings.text('check_connection')}';
        _statusType = 'error';
      });
      print('MQTT non connecté');
      return;
    }

    print('Demande de récupération de configuration');
    setState(() => _isLoading = true);
    _mqtt.publishMessage('home/wristband/get_config', 'request');

    // Timeout de sécurité
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _statusMessage = _settings.text('timeout_station');
          _statusType = 'error';
        });
        print('Timeout: pas de réponse de la base station');
      }
    });
  }

  IconData _getIconForMovement(String movement) {
    final normalized = movement.toLowerCase();
    if (normalized.contains('cercle') && (normalized.contains('gauche') || normalized.contains('droit') || normalized.contains('droite'))) {
      return normalized.contains('gauche')
          ? FontAwesomeIcons.arrowRotateLeft
          : FontAwesomeIcons.arrowRotateRight;
    }
    if (normalized.contains('point')) return Icons.circle;
    if (normalized.contains('haut')) return Icons.arrow_upward_rounded;
    if (normalized.contains('bas')) return Icons.arrow_downward_rounded;
    if (normalized.contains('gauche')) return Icons.arrow_back_rounded;
    if (normalized.contains('droite') || normalized.contains('droit')) return Icons.arrow_forward_rounded;
    if (normalized.contains('tap') || normalized.contains('touche')) return Icons.touch_app_rounded;
    if (normalized.contains('double')) return Icons.repeat_rounded;
    if (normalized.contains('long')) return Icons.pan_tool_rounded;
    return Icons.gesture_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        title: Text(
          _settings.text('view_configs'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        centerTitle: true,
        actions: [
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(AppTheme.primaryPurple),
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(
                Icons.refresh_rounded,
                color: AppTheme.primaryPurple,
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                _getConfiguration();
              },
            ),
        ],
      ),
      body: _isLoading && !_hasLoadedConfigs
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation(AppTheme.primaryPurple),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _settings.text('loading_configs'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          : ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              children: [
                // Afficher les messages de statut
                if (_statusMessage != null)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _statusType == 'success'
                            ? AppTheme.successGreen.withOpacity(0.15)
                            : _statusType == 'error'
                                ? AppTheme.errorRed.withOpacity(0.15)
                                : AppTheme.secondaryBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _statusType == 'success'
                              ? AppTheme.successGreen.withOpacity(0.3)
                              : _statusType == 'error'
                                  ? AppTheme.errorRed.withOpacity(0.3)
                                  : AppTheme.secondaryBlue.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _statusType == 'success'
                                ? Icons.check_circle_rounded
                                : _statusType == 'error'
                                    ? Icons.error_rounded
                                    : Icons.info_rounded,
                            color: _statusType == 'success'
                                ? AppTheme.successGreen
                                : _statusType == 'error'
                                    ? AppTheme.errorRed
                                    : AppTheme.secondaryBlue,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              style: TextStyle(
                                color: _statusType == 'success'
                                    ? AppTheme.successGreen
                                    : _statusType == 'error'
                                        ? AppTheme.errorRed
                                        : AppTheme.secondaryBlue,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                setState(() => _statusMessage = null);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Badge info lecture seule
                if (_hasLoadedConfigs)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: Opacity(opacity: value, child: child),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.secondaryBlue.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.visibility_rounded,
                            color: AppTheme.secondaryBlue,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _settings.text('read_only_mode'),
                              style: TextStyle(
                                color: AppTheme.secondaryBlue,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Section des configurations existantes
                if (_wristbandConfigs.isNotEmpty)
                  ...[
                    Text(
                      _settings.text('current_configs'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_wristbandConfigs.length} ${_settings.text('configs_count')}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                    ),
                    const SizedBox(height: 16),
                    ..._wristbandConfigs.map((config) => TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          builder: (context, value, child) {
                            return Transform.scale(
                              scale: 0.8 + (0.2 * value),
                              alignment: Alignment.topCenter,
                              child: Opacity(opacity: value, child: child),
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: AppTheme.cardShadow(isDark),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [AppTheme.primaryPurple, AppTheme.secondaryBlue],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        _getIconForMovement(config.mouvement),
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            config.mouvement.toUpperCase(),
                                            style: TextStyle(
                                              color: isDark ? Colors.white : Colors.black87,
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${config.entityId} → ${config.actionType}',
                                            style: TextStyle(
                                              color: isDark ? Colors.white60 : Colors.black54,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w400,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )),
                  ],

                // Message quand aucune config
                if (_hasLoadedConfigs && _wristbandConfigs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.secondaryBlue.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryBlue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.info_rounded,
                            color: AppTheme.secondaryBlue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _settings.text('no_config'),
                            style: TextStyle(
                              color: AppTheme.secondaryBlue,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
