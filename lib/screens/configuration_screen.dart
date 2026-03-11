import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/mqtt_service.dart';
import '../services/app_settings.dart';
import '../models/wristband_config.dart';
import '../widgets/ios_widgets.dart';
import '../theme/app_theme.dart';
import 'ir_device_detail_screen.dart';
import 'dart:convert';

class ConfigurationScreen extends StatefulWidget {
  const ConfigurationScreen({super.key});

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  final MQTTService _mqtt = MQTTService();
  final AppSettings _settings = AppSettings();
  List<Map<String, dynamic>> _irDevices = [];

  WristbandPossibility? _wristbandPossibility;
  List<WristbandConfig> _wristbandConfigs = [];
  bool _isLoading = false;
  String? _statusMessage;
  String? _statusType; // success | error | info
  bool _hasLoadedConfigs = false; // Active le formulaire après chargement
  String? _lastProcessedMessageId; // Pour éviter de traiter le même message deux fois
  bool _hasShownAutoWizard = false; // Pour éviter d'ouvrir le wizard plusieurs fois automatiquement

  @override
  void initState() {
    super.initState();
    _mqtt.addListener(_onMqttChanged);
    _settings.addListener(_onSettingsChanged);
    // Réinitialiser les états pour avoir un chargement frais
    _wristbandPossibility = null;
    _wristbandConfigs = [];
    _hasLoadedConfigs = false;
    _statusMessage = null;
    _statusType = null;
    _requestIrDevices();
    _loadWristbandPossibility();
  }

  @override
  void dispose() {
    _mqtt.removeListener(_onMqttChanged);
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onMqttChanged() {
    // Écouter les messaes MQTT pour les topics du bracelet
    final messages = _mqtt.recentMessages;
    if (messages.isNotEmpty) {
      final lastMessage = messages.first; // Prendre le message le plus récent
      // Déduplication par ID (topic + contenu + timestamp)
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
      // Gestion des télécommandes IR (liste des périphériques)
      if (topic == 'home/IR/feedback') {
        final jsonData = json.decode(payload);
        final status = jsonData['status'];

        if (status == 'saved_list') {
          final telecommandes = jsonData['telecommandes'] as Map<String, dynamic>;
          final devices = <Map<String, dynamic>>[];

          telecommandes.forEach((name, data) {
            devices.add({
              'name': name,
              'touches': List<String>.from(data['touches'] ?? []),
            });
          });

          setState(() {
            _irDevices = devices;
          });
        } else if (status == 'created' || status == null) {
          // Une nouvelle télécommande vient d'être créée, redemander la liste
          _requestIrDevices();
        }
        return;
      }

      // Nettoyer les clés non quotées dans tout le payload pour gérer les JSON non standards
      final cleanedPayload = payload.replaceAllMapped(
        RegExp(r'(\w+):([^,}\]]+)'),
        (match) => '"${match.group(1)}":"${match.group(2)}"',
      );
      final jsonData = json.decode(cleanedPayload);

      switch (topic) {
        case 'home/wristband/posibility':
          print('Réception des possibilités du bracelet');
          setState(() {
            _wristbandPossibility = WristbandPossibility.fromJson(jsonData);
            _isLoading = false;
            _statusMessage = null;
            _statusType = null;
          });
          _loadExistingConfigs();
          break;

        case 'home/wristband/config_status':
          print('Réception du statut de configuration');
          final status = WristbandConfigStatus.fromJson(jsonData);
          setState(() {
            if (status.status != 'success') {
              _statusMessage = '${_settings.text('send_error')}: ${status.message}';
              _statusType = 'error';
            }
            _isLoading = false;
          });
          if (status.status == 'success') {
            _saveConfigsLocally();
            // Recharger automatiquement les configurations après un envoi réussi
            _getConfiguration();
          }
          break;

        case 'home/wristband/get_config_response':
          print('Réception de la configuration récupérée');
          if (jsonData['config'] != null) {
            final configList = _parseConfigList(jsonData['config'].toString());
            final deduped = _dedupeConfigs(configList);
            setState(() {
              _wristbandConfigs = deduped;
              _hasLoadedConfigs = true;
              _isLoading = false;
              if (deduped.isEmpty) {
                _statusMessage = _settings.text('no_saved_config');
                _statusType = 'info';
                // Ouvrir automatiquement le wizard si aucune config n'existe
                if (!_hasShownAutoWizard && _wristbandPossibility != null) {
                  _hasShownAutoWizard = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _showConfigWizard();
                  });
                }
              } else {
                _statusMessage = _settings.text('loaded_configs');
                _statusType = 'success';
              }
            });
            _saveConfigsLocally();
          } else {
            setState(() {
              _hasLoadedConfigs = true;
              _isLoading = false;
              _statusMessage = _settings.text('no_saved_config');
              _statusType = 'info';
              // Ouvrir automatiquement le wizard si aucune config n'existe
              if (!_hasShownAutoWizard && _wristbandPossibility != null) {
                _hasShownAutoWizard = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _showConfigWizard();
                });
              }
            });
          }
          break;

        case 'home/wristband/execution_status':
          final execution = WristbandExecutionStatus.fromJson(jsonData);
          print('Execution status: ${execution.status} for ${execution.movement}');
          break;
      }
    } catch (e) {
      print('Erreur parsing MQTT message: $e');
      setState(() {
        _statusMessage = '${_settings.text('parsing_error')}: $e';
        _isLoading = false;
      });
    }
  }

  void _loadWristbandPossibility() {
    setState(() => _isLoading = true);
    _mqtt.publishMessage('home/wristband/request', '/getposibility');
  }

  void _requestIrDevices() {
    // Demander la liste des télécommandes IR enregistrées
    _mqtt.publishMessage('home/remote/saved', 'saved');
  }

  void _loadExistingConfigs() {
    // Après avoir reçu les possibilités, demander les configurations existantes
    if (!_mqtt.isConnected) {
      print('MQTT non connecté, impossible de charger les configs');
      return;
    }
    print('Demande de chargement des configurations existantes');
    setState(() {
      _isLoading = true;
      _hasLoadedConfigs = false;
    });
    _mqtt.publishMessage('home/wristband/get_config', 'request');
  }

  void _saveConfigsLocally() {
    // Sauvegarder les configurations localement (shared preferences, etc.)
    // Pour l'instant, on garde en mémoire
  }

  void _sendConfiguration() {
    if (!_mqtt.isConnected) {
      setState(() {
        _statusMessage = '${_settings.text('not_connected_mqtt')} - ${_settings.text('check_connection')}';
        _statusType = 'error';
      });
      print('MQTT non connecté');
      return;
    }

    print('Envoi de ${_wristbandConfigs.length} configurations');
    setState(() => _isLoading = true);
    final configJson = '[${_wristbandConfigs.map((c) => '{mouvement:${c.mouvement},entity_id:${c.entityId},action_type:${c.actionType}}').join(',')}]';
    print('JSON envoyé: $configJson');
    _mqtt.publishMessage('home/wristband/config', configJson);

    // Timeout de sécurité au cas où la réponse ne viendrait pas
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _statusMessage = _settings.text('timeout_bracelet');
        });
        print('Timeout: pas de réponse du bracelet');
      }
    });
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
        });
        print('Timeout: pas de réponse de la base station');
      }
    });
  }

  List<WristbandConfig> _parseConfigList(String configStr) {
    // Convertir le format spécial en JSON valide
    // Ex: [{mouvement:haut,entity_id:switch.prise_2,action_type:on}]
    // -> [{"mouvement":"haut","entity_id":"switch.prise_2","action_type":"on"}]
    final cleaned = configStr.replaceAllMapped(
      RegExp(r'(\w+):([^,}]+)'),
      (match) => '"${match.group(1)}":"${match.group(2)}"',
    );
    final jsonList = json.decode(cleaned);
    return (jsonList as List).map((item) => WristbandConfig.fromJson(item)).toList();
  }

  String _normalizeMovement(String m) {
    return m.trim().toUpperCase();
  }

  String _normalizeAction(String a) {
    return a.trim().toLowerCase();
  }

  String _normalizeEntityId(String id) {
    return id.trim().toLowerCase();
  }

  List<WristbandConfig> _dedupeConfigs(List<WristbandConfig> configs) {
    final usedMovements = <String>{};
    final usedActionsPerDevice = <String, Set<String>>{};
    final result = <WristbandConfig>[];

    for (final config in configs) {
      final movementKey = _normalizeMovement(config.mouvement);
      final entityKey = _normalizeEntityId(config.entityId);
      final actionKey = _normalizeAction(config.actionType);
      final actionsForDevice = usedActionsPerDevice.putIfAbsent(entityKey, () => <String>{});

      if (usedMovements.contains(movementKey)) continue; // ignore doublon de mouvement
      if (actionsForDevice.contains(actionKey)) continue; // ignore doublon action par périphérique

      usedMovements.add(movementKey);
      actionsForDevice.add(actionKey);
      result.add(config);
    }

    return result;
  }

  void _addConfig(String mouvement, String entityId, String actionType) {
    // Vérifier si cette combinaison existe déjà
    final normalizedNew = _normalizeMovement(mouvement);
    final existingIndex = _wristbandConfigs.indexWhere(
      (config) => _normalizeMovement(config.mouvement) == normalizedNew
    );

    final normalizedAction = _normalizeAction(actionType);
    final entityKey = _normalizeEntityId(entityId);
    final duplicateActionIndex = _wristbandConfigs.indexWhere(
      (config) => _normalizeEntityId(config.entityId) == entityKey && _normalizeAction(config.actionType) == normalizedAction,
    );

    if (existingIndex >= 0) {
      setState(() {
        _statusMessage = _settings.text('movement_configured');
        _statusType = 'error';
      });
      return; // Ne pas permettre la re-sélection
    }

    if (duplicateActionIndex >= 0) {
      setState(() {
        _statusMessage = _settings.text('action_used');
        _statusType = 'error';
      });
      return; // Ne pas réutiliser la même action sur un même périphérique
    }

    final newConfig = WristbandConfig(
      mouvement: mouvement,
      entityId: entityId,
      actionType: actionType,
    );

    setState(() {
      _wristbandConfigs.add(newConfig);
    });
    // Envoyer automatiquement la configuration mise à jour
    _sendConfiguration();
  }

  void _removeConfig(String mouvement) {
    setState(() {
      _wristbandConfigs.removeWhere(
        (config) => _normalizeMovement(config.mouvement) == _normalizeMovement(mouvement),
      );
    });
    // Envoyer automatiquement la configuration mise à jour
    _sendConfiguration();
  }

  List<String> _getAvailableMovements() {
    if (_wristbandPossibility == null) return [];
    final usedMovements = _wristbandConfigs
      .map((c) => _normalizeMovement(c.mouvement))
      .toSet();
    return _wristbandPossibility!.movements
      .where((m) => !usedMovements.contains(_normalizeMovement(m)))
      .toList();
  }

  IconData _getIconForMovement(String movement) {
    final normalized = movement.toLowerCase();
    final compact = normalized.replaceAll(RegExp(r'[^a-z]'), '');

    if (compact.contains('cercleleft') || compact.contains('circleleft') || compact.contains('circlegauche')) {
      return FontAwesomeIcons.arrowRotateRight;
    }
    if (compact.contains('cercleright') || compact.contains('circleright') || compact.contains('circledroite') || compact.contains('circledroit')) {
      return FontAwesomeIcons.arrowRotateLeft;
    }
    if (normalized.contains('cercle') && (normalized.contains('gauche') || normalized.contains('droit') || normalized.contains('droite'))) {
      return normalized.contains('gauche')
          ? FontAwesomeIcons.arrowRotateLeft
          : FontAwesomeIcons.arrowRotateRight;
    }
    if (compact.contains('point')) return Icons.circle;
    if (compact == 'up' || compact.contains('haut')) return Icons.arrow_upward_rounded;
    if (compact == 'down' || compact.contains('bas')) return Icons.arrow_downward_rounded;
    if (compact == 'left' || compact.contains('gauche')) return Icons.arrow_back_rounded;
    if (compact == 'right' || compact.contains('droite') || compact.contains('droit')) return Icons.arrow_forward_rounded;
    if (compact.contains('tap') || compact.contains('touche')) return Icons.touch_app_rounded;
    if (compact.contains('double')) return Icons.repeat_rounded;
    if (compact.contains('long')) return Icons.pan_tool_rounded;
    return Icons.gesture_rounded;
  }

  List<String> _getAvailableActions(WristbandDevice device) {
    List<String> actions = [];

    if (device.type == 'light') {
      actions.addAll(['on', 'off', 'toggle']);
    } else if (device.type == 'switch') {
      actions.addAll(['on', 'off', 'toggle']);
    }

    return actions;
  }

  bool _deviceHasFreeAction(WristbandDevice device) {
    final allActions = _getAvailableActions(device);
    final usedActions = _wristbandConfigs
        .where((c) => _normalizeEntityId(c.entityId) == _normalizeEntityId(device.entityId))
        .map((c) => _normalizeAction(c.actionType))
        .toSet();
    return allActions.any((a) => !usedActions.contains(_normalizeAction(a)));
  }

  List<String> _getRemainingActions(WristbandDevice device) {
    final allActions = _getAvailableActions(device);
    final usedActions = _wristbandConfigs
        .where((c) => _normalizeEntityId(c.entityId) == _normalizeEntityId(device.entityId))
        .map((c) => _normalizeAction(c.actionType))
        .toSet();
    return allActions
        .where((a) => !usedActions.contains(_normalizeAction(a)))
        .toList();
  }

  List<String> _getRemainingIrActions(String deviceName) {
    final device = _irDevices.firstWhere(
      (d) => d['name'] == deviceName,
      orElse: () => {},
    );

    if (device.isEmpty) return [];

    final touches = List<String>.from(device['touches'] ?? []);
    final usedActions = _wristbandConfigs
        .where((c) => _normalizeEntityId(c.entityId) == _normalizeEntityId('ir:$deviceName'))
        .map((c) => _normalizeAction(c.actionType))
        .toSet();

    return touches.where((t) => !usedActions.contains(_normalizeAction(t))).toList();
  }

  bool _irHasFreeAction(String deviceName) {
    return _getRemainingIrActions(deviceName).isNotEmpty;
  }

  List<Map<String, String>> _getDeviceOptions() {
    final options = <Map<String, String>>[];

    // Appareils classiques (light / switch)
    if (_wristbandPossibility != null) {
      options.addAll(_wristbandPossibility!.devices
          .where((device) => _deviceHasFreeAction(device))
          .map((device) => {
                'id': device.entityId,
                'label': '${device.friendlyName} (${device.type})',
                'type': 'ha',
                'deviceType': device.type,
              }));
    }

    // Télécommandes IR
    options.addAll(_irDevices
        .where((d) => _irHasFreeAction(d['name']))
        .map((d) => {
              'id': 'ir:${d['name']}',
              'label': '${d['name']} (IR)',
              'type': 'ir',
            }));

    return options;
  }

  void _showConfigWizard() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ConfigWizard(
        wristbandPossibility: _wristbandPossibility!,
        irDevices: _irDevices,
        onAddConfig: (mouvement, deviceId, action) {
          Navigator.pop(context);
          _addConfig(mouvement, deviceId, action);
        },
        getAvailableMovements: _getAvailableMovements,
        getDeviceOptions: _getDeviceOptions,
        getRemainingActions: _getRemainingActions,
        getRemainingIrActions: _getRemainingIrActions,
      ),
    );
  }

  void _showAvailableDevices() {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _AvailableDevicesScreen(
          devices: _wristbandPossibility!.devices,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        title: Text(
          _settings.text('configuration'),
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
            const SizedBox(width: 50),
        ],
      ),
      body: _isLoading && _wristbandPossibility == null
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
                    _settings.text('connecting_bracelet'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          : _wristbandPossibility == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.watch_off_rounded,
                        size: 64,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _settings.text('no_possibility'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                )
              : ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(20, 20, 20, _hasLoadedConfigs && _wristbandPossibility != null ? 200 : 20),
                  children: [
                    // Afficher les messages de statut seulement avant le chargement
                    if (!_hasLoadedConfigs && _statusMessage != null)
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
                            ],
                          ),
                        ),
                      ),

                    // Afficher les erreurs de parsing meme apres chargement
                    if (_hasLoadedConfigs && _statusType == 'error' && _statusMessage != null)
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
                            color: AppTheme.errorRed.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.errorRed.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_rounded,
                                color: AppTheme.errorRed,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _statusMessage!,
                                  style: TextStyle(
                                    color: AppTheme.errorRed,
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

                    // Message quand config chargee
                    if (_hasLoadedConfigs && _wristbandConfigs.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.successGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.successGreen.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.successGreen.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.check_circle_rounded,
                                color: AppTheme.successGreen,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _settings.text('config_loaded'),
                                style: TextStyle(
                                  color: AppTheme.successGreen,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_hasLoadedConfigs) const SizedBox(height: 32),

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
                                        Container(
                                          decoration: BoxDecoration(
                                            color: AppTheme.errorRed.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(10),
                                              onTap: () {
                                                HapticFeedback.mediumImpact();
                                                _removeConfig(config.mouvement);
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(10),
                                                child: Icon(
                                                  Icons.delete_rounded,
                                                  color: AppTheme.errorRed,
                                                  size: 20,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )),
                        const SizedBox(height: 32),
                      ],
                  ],
                ),
      floatingActionButton: _hasLoadedConfigs && _wristbandPossibility != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: FloatingActionButton.extended(
                        onPressed: _showAvailableDevices,
                        backgroundColor: AppTheme.secondaryBlue,
                        icon: const Icon(Icons.devices_rounded, color: Colors.white),
                        label: Text(
                          _settings.text('devices'),
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FloatingActionButton.extended(
                        onPressed: _showConfigWizard,
                        backgroundColor: AppTheme.primaryPurple,
                        icon: const Icon(Icons.add_rounded, color: Colors.white),
                        label: Text(
                          _settings.text('add_config'),
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PAGE PÉRIPHÉRIQUES DISPONIBLES
// ═══════════════════════════════════════════════════════════════════════════

class _AvailableDevicesScreen extends StatefulWidget {
  final List<WristbandDevice> devices;

  const _AvailableDevicesScreen({
    required this.devices,
  });

  @override
  State<_AvailableDevicesScreen> createState() => _AvailableDevicesScreenState();
}

class _AvailableDevicesScreenState extends State<_AvailableDevicesScreen> {
  final MQTTService _mqtt = MQTTService();
  final AppSettings _settings = AppSettings();
  bool _isLoadingIR = true;
  List<Map<String, dynamic>> _savedDevices = [];
  String? _lastProcessedMessageId;
  String? _awaitingButtonForDevice;
  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    _mqtt.addListener(_onMqttChanged);
    _loadSavedDevices();
  }

  @override
  void dispose() {
    _mqtt.removeListener(_onMqttChanged);
    _hideToast();
    super.dispose();
  }

  void _hideToast() {
    _toastEntry?.remove();
    _toastEntry = null;
  }

  void _showToast(
    String message, {
    Color? backgroundColor,
    IconData? icon,
    Duration duration = const Duration(seconds: 2),
  }) {
    // Déterminer le type de notification
    bool shouldShow = true;
    if (backgroundColor == AppTheme.successGreen) {
      shouldShow = _settings.enableSuccessNotifications;
    } else if (backgroundColor == AppTheme.errorRed) {
      shouldShow = _settings.enableErrorNotifications;
    }

    if (!shouldShow) return;

    _hideToast();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ?? (isDark ? AppTheme.darkCard : Colors.white);
    final textColor = backgroundColor != null ? Colors.white : (isDark ? Colors.white : Colors.black87);

    final entry = OverlayEntry(
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Align(
            alignment: Alignment.topCenter,
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, -10 * (1 - value)),
                    child: Opacity(opacity: value, child: child),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppTheme.cardShadow(isDark),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: textColor, size: 18),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          message,
                          style: TextStyle(
                            color: textColor,
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

    Overlay.of(context).insert(entry);
    _toastEntry = entry;

    Future.delayed(duration, () {
      if (_toastEntry == entry) {
        _hideToast();
      }
    });
  }

  void _onMqttChanged() {
    final messages = _mqtt.recentMessages;
    
    if (messages.isNotEmpty) {
      // Déclencher une mise à jour de l'interface pour afficher les changements des objets intelligents
      if (!mounted) return;
      setState(() {});

      final lastMessage = messages.first;
      
      final messageId = '${lastMessage.topic}_${lastMessage.message}_${lastMessage.timestamp}';
      if (_lastProcessedMessageId != messageId) {
        _lastProcessedMessageId = messageId;
        _handleMqttMessage(lastMessage.topic, lastMessage.message);
      }
    }
  }

  void _handleMqttMessage(String topic, String payload) {
    if (topic == 'home/IR/feedback' || topic == 'home/remote/new') {
      try {
        final jsonData = jsonDecode(payload);
        final status = jsonData['status'];
        
        if (status == 'saved_list') {
          final telecommandes = jsonData['telecommandes'] as Map<String, dynamic>;
          final devices = <Map<String, dynamic>>[];
          
          telecommandes.forEach((name, data) {
            devices.add({
              'name': name,
              'touches': List<String>.from(data['touches'] ?? []),
              'count': data['count'] ?? 0,
            });
          });
          
          if (mounted) {
            setState(() {
              _savedDevices = devices;
              _isLoadingIR = false;
            });
          }
          
          if (_awaitingButtonForDevice != null) {
            final device = telecommandes[_awaitingButtonForDevice];
            if (device != null) {
              final touches = device['touches'] as List?;
              if (touches != null && touches.isNotEmpty) {
                _awaitingButtonForDevice = null;
                
                _showToast(
                  _settings.text('button_saved'),
                  backgroundColor: AppTheme.successGreen,
                  icon: Icons.check_circle,
                );
              }
            }
          }
        } else if (status == 'created' || (topic == 'home/remote/new' && (status == null || status.toString() == 'null'))) {
          final deviceName = jsonData['telecommande'] as String?;
          
          if (deviceName != null && !_savedDevices.any((d) => d['name'] == deviceName)) {
            if (mounted) {
              setState(() {
                _savedDevices.add({
                  'name': deviceName,
                  'touches': <String>[],
                  'count': 0,
                });
                _awaitingButtonForDevice = deviceName;
              });
              
              _showToast(
                '${_settings.text('remote_created')} "$deviceName"',
                backgroundColor: AppTheme.successGreen,
                icon: Icons.check_circle_rounded,
              );
            }
          }
        } else if (status == 'learned' || status == 'deleted' || status == 'removed' || 
                   status == 'removed_button' || status == 'removed_remote') {
          _loadSavedDevices();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoadingIR = false;
          });
        }
      }
    }
  }

  void _loadSavedDevices() {
    setState(() {
      _isLoadingIR = true;
    });
    _mqtt.publishMessage('home/remote/saved', 'saved');
  }

  void _deleteDevice(String deviceName) {
    _mqtt.publishMessage('home/IR/remove/remote', deviceName);
    
    setState(() {
      _savedDevices.removeWhere((d) => d['name'] == deviceName);
    });
    
    _showToast(
      '${_settings.text('remote_deleted_with_name')} "$deviceName"',
      backgroundColor: AppTheme.successGreen,
      icon: Icons.check_circle_rounded,
    );
  }

  void _showAddRemoteDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: AppTheme.cardShadow(isDark),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.warningOrange.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.settings_remote_rounded,
                            color: AppTheme.warningOrange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _settings.text('new_remote'),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _settings.text('short_name_no_spaces'),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: isDark ? Colors.white54 : Colors.black54,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        hintText: _settings.text('remote_name'),
                        filled: true,
                        fillColor: isDark ? AppTheme.darkBackground : Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.white70 : Colors.black87,
                              side: BorderSide(
                                color: (isDark ? Colors.white : Colors.black).withOpacity(0.15),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(_settings.text('cancel')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final name = controller.text.trim();
                              if (name.isEmpty) {
                                _showToast(
                                  _settings.text('enter_name'),
                                  backgroundColor: AppTheme.errorRed,
                                  icon: Icons.error_rounded,
                                );
                                return;
                              }
                              if (_savedDevices.any((d) => d['name'] == name)) {
                                _showToast(
                                  _settings.text('remote_exists'),
                                  backgroundColor: AppTheme.errorRed,
                                  icon: Icons.error_rounded,
                                );
                                return;
                              }
                              Navigator.pop(context);
                              final message = json.encode({
                                'telecommande': name,
                              });
                              _mqtt.publishMessage('home/remote/new', message);

                              _showToast(
                                '${_settings.text('remote_created')} "$name"',
                                backgroundColor: AppTheme.successGreen,
                                icon: Icons.check_circle_rounded,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.warningOrange,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(_settings.text('add')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _settings.text('available_devices_title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: isDark ? Colors.white : Colors.black87,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            onPressed: _loadSavedDevices,
            icon: Icon(
              Icons.refresh_rounded,
              color: isDark ? Colors.white : Colors.black87,
            ),
            tooltip: _settings.text('refresh'),
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          // Section Objets intelligents
          if (_mqtt.isConnected && _mqtt.deviceStates.isNotEmpty) ...[
            Text(
              _settings.text('smart_objects'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${_mqtt.deviceStates.length} ${_settings.text('devices_count')}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            ..._mqtt.deviceStates.values.toList().map((device) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.cardShadow(isDark),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.secondaryBlue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      (device.friendlyName?.toLowerCase().contains('lum') ?? false) || (device.topic.toLowerCase().contains('light') || device.topic.toLowerCase().contains('lum'))
                          ? Icons.lightbulb_rounded
                          : Icons.power_rounded,
                      color: AppTheme.secondaryBlue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.friendlyName ?? device.topic,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          device.topic,
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontSize: 13,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IOSStatusBadge(
                    text: device.state.toLowerCase(),
                    color: device.state.toUpperCase() == 'ON' ? AppTheme.successGreen : Colors.grey,
                    icon: device.state.toUpperCase() == 'ON' ? Icons.check_circle_rounded : Icons.circle_outlined,
                  ),
                ],
              ),
            )),
            const SizedBox(height: 32),
          ],

          // Section Infrarouges
          Text(
            _settings.text('ir_devices'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          if (_isLoadingIR)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(
                  color: AppTheme.warningOrange,
                ),
              ),
            )
          else if (_savedDevices.isNotEmpty) ...[
            Text(
              '${_savedDevices.length} ${_settings.text('ir_count')}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            ..._savedDevices.map((device) => Dismissible(
              key: Key(device['name']),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.errorRed,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (direction) async {
                return await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
                    title: Text('${_settings.text('delete')} "${device['name']}" ?'),
                    content: Text(_settings.text('delete_remote_message')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(_settings.text('cancel')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(_settings.text('delete'), style: const TextStyle(color: AppTheme.errorRed)),
                      ),
                    ],
                  ),
                ) ?? false;
              },
              onDismissed: (direction) {
                _deleteDevice(device['name']);
              },
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => IRDeviceDetailScreen(
                        deviceName: device['name'],
                        deviceData: device,
                      ),
                    ),
                  ).then((_) => _loadSavedDevices()); // Refresh après retour
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppTheme.cardShadow(isDark),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.warningOrange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.settings_remote,
                              color: AppTheme.warningOrange,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  device['name'],
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${device['touches']?.length ?? 0} ${_settings.text('button_s')}',
                                  style: TextStyle(
                                    color: isDark ? Colors.white54 : Colors.black54,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: isDark ? Colors.white54 : Colors.black38,
                          ),
                        ],
                      ),
                      if ((device['touches'] as List?)?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: (device['touches'] as List<dynamic>)
                              .map((touch) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.warningOrange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  touch.toString(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.warningOrange,
                                  ),
                                ),
                              ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                _settings.text('no_remote_saved'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddRemoteDialog,
        backgroundColor: AppTheme.warningOrange,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(
          _settings.text('add_ir'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// WIDGET WIZARD - Configuration en 3 étapes
// ═══════════════════════════════════════════════════════════════════════════

class _ConfigWizard extends StatefulWidget {
  final WristbandPossibility wristbandPossibility;
  final List<Map<String, dynamic>> irDevices;
  final Function(String mouvement, String deviceId, String action) onAddConfig;
  final List<String> Function() getAvailableMovements;
  final List<Map<String, String>> Function() getDeviceOptions;
  final List<String> Function(WristbandDevice) getRemainingActions;
  final List<String> Function(String) getRemainingIrActions;

  const _ConfigWizard({
    required this.wristbandPossibility,
    required this.irDevices,
    required this.onAddConfig,
    required this.getAvailableMovements,
    required this.getDeviceOptions,
    required this.getRemainingActions,
    required this.getRemainingIrActions,
  });

  @override
  State<_ConfigWizard> createState() => _ConfigWizardState();
}

class _ConfigWizardState extends State<_ConfigWizard> {
  final AppSettings _settings = AppSettings();
  int _step = 0; // 0: mouvement, 1: appareil, 2: action
  String? _selectedMovement;
  String? _selectedDeviceId;
  String? _selectedAction;

  IconData _stepIcon() {
    switch (_step) {
      case 0:
        return Icons.gesture_rounded;
      case 1:
        return Icons.devices_rounded;
      default:
        return Icons.flash_on_rounded;
    }
  }

  IconData _iconForMovement(String movement) {
    final normalized = movement.toLowerCase();
    final compact = normalized.replaceAll(RegExp(r'[^a-z]'), '');

    if (compact.contains('cercleleft') || compact.contains('circleleft') || compact.contains('circlegauche')) {
      return FontAwesomeIcons.arrowRotateRight;
    }
    if (compact.contains('cercleright') || compact.contains('circleright') || compact.contains('circledroite') || compact.contains('circledroit')) {
      return FontAwesomeIcons.arrowRotateLeft;
    }
    if (compact.contains('point')) return Icons.circle;
    if (compact == 'up' || compact.contains('haut')) return Icons.arrow_upward_rounded;
    if (compact == 'down' || compact.contains('bas')) return Icons.arrow_downward_rounded;
    if (compact == 'left' || compact.contains('gauche')) return Icons.arrow_back_rounded;
    if (compact == 'right' || compact.contains('droite') || compact.contains('droit')) return Icons.arrow_forward_rounded;
    if (compact.contains('tap') || compact.contains('touche')) return Icons.touch_app_rounded;
    if (compact.contains('double')) return Icons.repeat_rounded;
    if (compact.contains('long')) return Icons.pan_tool_rounded;
    return Icons.gesture_rounded;
  }

  IconData _iconForDeviceOption(Map<String, String> device) {
    if (device['type'] == 'ir') return Icons.settings_remote_rounded;
    final deviceType = device['deviceType'];
    if (deviceType == 'light') return Icons.lightbulb_rounded;
    if (deviceType == 'switch') return Icons.power_rounded;
    return Icons.devices_other_rounded;
  }

  IconData _iconForAction(String action) {
    final normalized = action.toLowerCase();
    if (normalized == 'on') return Icons.power_rounded;
    if (normalized == 'off') return Icons.power_off_rounded;
    if (normalized == 'toggle') return Icons.power_settings_new_rounded;
    return Icons.touch_app_rounded;
  }

  void _nextStep() {
    if (_step < 2) {
      setState(() => _step++);
    } else {
      // Valider et fermer
      widget.onAddConfig(_selectedMovement!, _selectedDeviceId!, _selectedAction!);
    }
  }

  void _previousStep() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.pop(context);
    }
  }

  List<String> _getRemainingActionsForDevice() {
    if (_selectedDeviceId == null) return [];
    
    final isIr = _selectedDeviceId!.startsWith('ir:');
    if (isIr) {
      final irName = _selectedDeviceId!.substring(3);
      return widget.getRemainingIrActions(irName);
    } else {
      WristbandDevice? device;
      try {
        device = widget.wristbandPossibility.devices
            .firstWhere((d) => d.entityId == _selectedDeviceId);
      } catch (_) {}
      if (device != null) {
        return widget.getRemainingActions(device);
      }
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Titre + étape
          Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _stepIcon(),
                    color: AppTheme.primaryPurple,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _step == 0
                        ? _settings.text('which_movement')
                        : _step == 1
                            ? _settings.text('which_device')
                            : _settings.text('which_action'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${_settings.text('step_of')} ${_step + 1} ${_settings.text('of')} 3',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Contenu selon l'étape
          if (_step == 0)
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget
                    .getAvailableMovements()
                    .map((movement) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: IOSButton(
                            text: movement.toUpperCase(),
                            icon: _iconForMovement(movement),
                            iconSize: 26,
                            color: _selectedMovement == movement
                                ? AppTheme.primaryPurple
                                : Colors.grey,
                            onPressed: () {
                              setState(() => _selectedMovement = movement);
                              Future.delayed(const Duration(milliseconds: 300), _nextStep);
                            },
                          ),
                        ))
                    .toList(),
              ),
            )
          else if (_step == 1)
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget
                    .getDeviceOptions()
                    .map((device) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: IOSButton(
                            text: device['label']!,
                            icon: _iconForDeviceOption(device),
                            iconSize: 26,
                            color: _selectedDeviceId == device['id']
                                ? AppTheme.primaryPurple
                                : Colors.grey,
                            onPressed: () {
                              setState(() => _selectedDeviceId = device['id']);
                              Future.delayed(const Duration(milliseconds: 300), _nextStep);
                            },
                          ),
                        ))
                    .toList(),
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _getRemainingActionsForDevice()
                    .map((action) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: IOSButton(
                            text: action.toUpperCase(),
                      icon: _iconForAction(action),
                            iconSize: 26,
                            color: _selectedAction == action
                                ? AppTheme.primaryPurple
                                : Colors.grey,
                            onPressed: () {
                              setState(() => _selectedAction = action);
                              HapticFeedback.mediumImpact();
                            },
                          ),
                        ))
                    .toList(),
              ),
            ),

          const SizedBox(height: 24),

          // Boutons navigation
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _previousStep,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppTheme.primaryPurple,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _step == 0 ? _settings.text('close') : _settings.text('back'),
                      style: const TextStyle(
                        color: AppTheme.primaryPurple,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: IOSButton(
                  text: _step == 2 ? _settings.text('validate') : _settings.text('next'),
                  color: ((_step == 0 && _selectedMovement != null) ||
                          (_step == 1 && _selectedDeviceId != null) ||
                          (_step == 2 && _selectedAction != null))
                      ? AppTheme.primaryPurple
                      : Colors.grey[400]!,
                  onPressed: ((_step == 0 && _selectedMovement != null) ||
                          (_step == 1 && _selectedDeviceId != null) ||
                          (_step == 2 && _selectedAction != null))
                      ? _nextStep
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}