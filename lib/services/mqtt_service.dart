import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/command_history.dart';
import '../models/device_state.dart';

// Modèle pour la batterie et le secteur
class BatteryStatus {
  final int batteryLevel;
  final bool isCharging;
  BatteryStatus(this.batteryLevel, this.isCharging);
}

class MQTTService extends ChangeNotifier {
  // Batterie et secteur du bracelet
  final ValueNotifier<BatteryStatus?> batteryStatusNotifier = ValueNotifier<BatteryStatus?>(null);

  BatteryStatus? get lastBatteryStatus => batteryStatusNotifier.value;
  static final MQTTService _instance = MQTTService._internal();
  factory MQTTService() => _instance;
  MQTTService._internal() {
    _listenToConnectivityChanges();
    _startPowerPolling();
  }

  MqttServerClient? _client;
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  // Stocker les paramètres de connexion pour reconnexion automatique
  String? _savedServer;
  int? _savedPort;
  String? _savedUsername;
  String? _savedPassword;
  bool _isReconnecting = false;
  Timer? _reconnectTimer;
  Timer? _powerRequestTimer;
  
  // Connectivité
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _wasDisconnectedDueToNetwork = false;
  
  final List<CommandHistory> _history = [];
  List<CommandHistory> get history => List.unmodifiable(_history);
  
  final Map<String, DeviceState> _deviceStates = {};
  Map<String, DeviceState> get deviceStates => Map.unmodifiable(_deviceStates);

  final List<CommandHistory> _recentMessages = [];
  List<CommandHistory> get recentMessages => List.unmodifiable(_recentMessages);

  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSubscription;

  void _listenToConnectivityChanges() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final hasConnectivity = results.any((result) => 
        result == ConnectivityResult.wifi || 
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet
      );
      
      if (hasConnectivity && _wasDisconnectedDueToNetwork && !_isConnected && !_isReconnecting) {
        print('Connectivité réseau restaurée, tentative de reconnexion MQTT...');
        _attemptAutoReconnect();
      } else if (!hasConnectivity && _isConnected) {
        print('Perte de connectivité réseau détectée');
        _wasDisconnectedDueToNetwork = true;
      }
    });
  }

  void _attemptAutoReconnect() async {
    if (_isReconnecting || _savedServer == null) return;
    
    _isReconnecting = true;
    
    final success = await connect(
      server: _savedServer,
      port: _savedPort,
      username: _savedUsername,
      password: _savedPassword,
    );
    
    if (success) {
      print('Reconnexion automatique réussie');
      _wasDisconnectedDueToNetwork = false;
      notifyListeners(); // Notifier immédiatement pour mettre à jour l'UI
      // Récupérer les devices après reconnexion
      await Future.delayed(const Duration(milliseconds: 200));
      publishMessage('home/matter/request', 'test');
    } else {
      print('Échec de reconnexion automatique, nouvelle tentative dans 2 secondes...');
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 2), () {
        _isReconnecting = false;
        _attemptAutoReconnect();
      });
      return;
    }
    
    _isReconnecting = false;
  }

  Future<bool> connect({String? server, int? port, String? username, String? password}) async {
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      return true;
    }

    // Utiliser les paramètres fournis ou ceux sauvegardés
    final mqttServer = server ?? _savedServer ?? '192.168.50.27';
    final mqttPort = port ?? _savedPort ?? 1883;
    final mqttUsername = username ?? _savedUsername ?? 'fil_rouge';
    final mqttPassword = password ?? _savedPassword ?? '';
    
    // Sauvegarder pour reconnexion automatique
    _savedServer = mqttServer;
    _savedPort = mqttPort;
    _savedUsername = mqttUsername;
    _savedPassword = mqttPassword;

    _client = MqttServerClient(mqttServer, 'flutter_client_${DateTime.now().millisecondsSinceEpoch}');
    _client!.port = mqttPort;
    _client!.logging(on: true);
    _client!.keepAlivePeriod = 60;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onSubscribed = _onSubscribed;

    final connMessage = MqttConnectMessage()
        .authenticateAs(mqttUsername, mqttPassword)
        .withClientIdentifier('flutter_client_${DateTime.now().millisecondsSinceEpoch}')
        .withWillTopic('home/status')
        .withWillMessage('Offline')
        .withWillQos(MqttQos.atLeastOnce)
        .startClean();

    _client!.connectionMessage = connMessage;

    try {
      await _client!.connect();
      _isConnected = _client!.connectionStatus!.state == MqttConnectionState.connected;

      // subscribe to all device topics and their status topics
      try {
        _client!.subscribe('home/#', MqttQos.atMostOnce);
        // Also subscribe to specific state topics for each device
        for (final topic in ['home/+/state', 'home/+/status', 'home/+/color']) {
          _client!.subscribe(topic, MqttQos.atMostOnce);
        }
      } catch (e) {
        print('Error subscribing to topics: $e');
      }

      // listen for incoming messages once
      _updatesSubscription = _client!.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        for (final rec in c) {
          try {
            final topic = rec.topic;
            final mqttMessage = rec.payload as MqttPublishMessage;
            final payload = MqttPublishPayload.bytesToStringAsString(mqttMessage.payload.message);
            _handleIncomingMessage(topic, payload);
          } catch (e) {
            print('Error handling incoming message: $e');
          }
        }
      });
      notifyListeners();
      return _isConnected;
    } catch (e) {
      print('Exception: $e');
      _isConnected = false;
      notifyListeners();
      return false;
    }
  }

  void _onDisconnected() async {
    _isConnected = false;
    _deviceStates.clear();
    notifyListeners();
    print('Disconnected');
    
    // Marquer comme déconnecté pour tenter une reconnexion si le réseau revient
    _wasDisconnectedDueToNetwork = true;
    
    // cancel incoming subscription
    try {
      _updatesSubscription?.cancel();
      _updatesSubscription = null;
    } catch (_) {}
    
    // Vérifier si on a encore de la connectivité réseau
    // Si oui, c'est probablement un changement de WiFi, donc reconnecter automatiquement
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasConnectivity = connectivityResult.any((result) => 
        result == ConnectivityResult.wifi || 
        result == ConnectivityResult.mobile ||
        result == ConnectivityResult.ethernet
      );
      
      if (hasConnectivity && _savedServer != null && !_isReconnecting) {
        print('Déconnexion MQTT détectée avec réseau actif (changement de WiFi?), tentative de reconnexion...');
        _attemptAutoReconnect();
      }
    } catch (e) {
      print('Erreur lors de la vérification de connectivité: $e');
    }
  }

  void _onConnected() {
    _isConnected = true;
    notifyListeners();
    _startPowerPolling();
    _requestPowerStatus();
    try {
      final payload = MqttClientPayloadBuilder()..addString('Online');
      _client?.publishMessage('home/status', MqttQos.atLeastOnce, payload.payload!);
    } catch (e) {
      print('Warning: failed to publish online status: $e');
    }
    print('Connected');
  }

  void _startPowerPolling() {
    _powerRequestTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      _requestPowerStatus();
    });
  }

  Future<void> _requestPowerStatus() async {
    if (!_isConnected) return;
    await publishMessage('home/wristband/request/power', '');
  }

  void _onSubscribed(String topic) {
    print('Subscribed to: $topic');
  }

  void _handleIncomingMessage(String topic, String payload) {
    // Gestion du topic batterie/secteur du bracelet
    if (topic == 'home/wristband/feedback/power') {
      try {
        // Corriger le format JSON invalide (cles sans guillemets)
        // {bat_lvl:70,sect:true} -> {"bat_lvl":70,"sect":true}
        final fixedPayload = payload
            .replaceAll('bat_lvl:', '"bat_lvl":')
            .replaceAll('sect:', '"sect":');

        final data = json.decode(fixedPayload);
        final int? batLvl = data['bat_lvl'] is int ? data['bat_lvl'] : int.tryParse(data['bat_lvl'].toString());
        final bool? sect = data['sect'] is bool ? data['sect'] : (data['sect'].toString().toLowerCase() == 'true');
        if (batLvl != null && sect != null) {
          batteryStatusNotifier.value = BatteryStatus(batLvl, sect);
        }
      } catch (e) {
        print('Erreur parsing batterie/secteur: $e');
      }
      // On ne notifie pas ici, le ValueNotifier s'en charge
    }
    // Stocker les messages récents pour les écrans qui en ont besoin
    if (topic.startsWith('home/wristband/') || topic.startsWith('home/IR/') || topic.startsWith('home/remote/')) {
      _recentMessages.insert(0, CommandHistory(
        topic: topic,
        message: payload,
        timestamp: DateTime.now(),
        success: true,
        isIncoming: true,
      ));
      // Garder seulement les 50 derniers messages
      if (_recentMessages.length > 50) {
        _recentMessages.removeLast();
      }
      notifyListeners(); // Notifier les écouteurs quand un nouveau message est reçu
    }

    try {
      if (topic == 'home/matter/response') {
        try {
          String jsonStr = payload;
          final firstBracket = payload.indexOf('[');
          if (firstBracket != -1) jsonStr = payload.substring(firstBracket);
          final list = json.decode(jsonStr) as List<dynamic>;

          // Collect all device IDs from the response
          final Set<String> receivedDeviceIds = {};

          for (final item in list) {
            try {
              final map = item as Map<String, dynamic>;
              final id = (map['id'] as String?) ?? '';
              final idParts = id.split('.');
              if (idParts.length < 2) continue;
              final baseId = idParts[1]; // e.g. prise_1 or lum_2
              final baseTopic = 'home/$baseId/set';
              receivedDeviceIds.add(baseTopic);

              final state = ((map['state'] as String?) ?? '').toUpperCase();
              final friendly = map['friendly_name'] as String?;
              final attrs = (map['attributes'] as Map<String, dynamic>?) ?? {};

              final deviceState = _deviceStates.putIfAbsent(
                baseTopic,
                () => DeviceState(topic: baseTopic, state: state, friendlyName: friendly),
              );

              int? brightness;
              List<int>? rgb;
              if (attrs.containsKey('brightness')) {
                try {
                  brightness = int.parse(attrs['brightness'].toString());
                } catch (_) {}
              }
              if (attrs.containsKey('rgb_color')) {
                try {
                  var rgbStr = attrs['rgb_color'].toString();
                  rgbStr = rgbStr.replaceAll(RegExp(r'[()\[\]\s]'), '');
                  final parts = rgbStr.split(',');
                  if (parts.length == 3) {
                    rgb = parts.map((s) => int.parse(s)).toList();
                  }
                } catch (_) {}
              }

              deviceState.update(state: state, brightness: brightness, rgbColor: rgb);
              if (friendly != null) deviceState.friendlyName = friendly;
            } catch (e) {
              print('Error parsing item in matter response: $e');
            }
          }

          // Remove devices that are no longer in the response
          _deviceStates.removeWhere((key, value) => !receivedDeviceIds.contains(key));

          notifyListeners();
        } catch (e) {
          print('Error parsing matter response JSON: $e');
        }
        // add to history
        _history.insert(0, CommandHistory(
          topic: topic,
          message: payload,
          timestamp: DateTime.now(),
          success: true,
          isIncoming: true,
        ));
        notifyListeners();
        return;
      }

      // Extraire le device ID et le type de message du topic
      // Format: home/lum_1/type/state
      final parts = topic.split('/');
      if (parts.length < 3) return; // Ignore les topics trop courts
      
      final deviceId = parts[1]; // ex: lum_1
      final baseTopic = 'home/$deviceId/set';
      final messageType = parts[2]; // ex: state, brightness, rgb_color
      
      // Vérifier si le périphérique est explicitement mentionné dans les réponses MQTT
      if (!_deviceStates.containsKey(baseTopic)) {
        print('Ignoré: périphérique non mentionné dans les réponses MQTT ($baseTopic)');
        return;
      }

      // Récupérer ou créer l'état de l'appareil
      final deviceState = _deviceStates.putIfAbsent(
        baseTopic, 
        () => DeviceState(topic: baseTopic, state: 'unknown')
      );

      // Traiter selon le type de message
      switch (messageType) {
        case 'state':
          deviceState.update(state: payload.trim().toUpperCase());
          break;
          
        case 'brightness':
          if (parts.length > 3 && parts[3] == 'state') {
            try {
              final brightness = int.parse(payload.trim());
              deviceState.update(brightness: brightness);
            } catch (e) {
              print('Error parsing brightness: $e');
            }
          }
          break;
          
        case 'rgb_color':
          if (parts.length > 3 && parts[3] == 'state') {
            try {
              final rgbValues = payload.split(',')
                  .map((s) => int.parse(s.trim()))
                  .toList();
              if (rgbValues.length == 3) {
                deviceState.update(rgbColor: rgbValues);
              }
            } catch (e) {
              print('Error parsing RGB color: $e');
            }
          }
          break;
      }
    } catch (e) {
      print('Error handling message for $topic: $e');
    }
    // add to command history as received message (keep success=true)
    _history.insert(0, CommandHistory(
      topic: topic,
      message: payload,
      timestamp: DateTime.now(),
      success: true,
      isIncoming: true,
    ));
    notifyListeners();
  }

  // Envoie un message sur un topic spécifique avec le bon suffixe
  Future<bool> _publishToDevice(String baseTopic, String type, String value) async {
    final topic = baseTopic.endsWith('/set') 
        ? baseTopic.substring(0, baseTopic.length - 4) + '/$type/set'
        : '$baseTopic/$type/set';
    return publishMessage(topic, value);
  }

  // Définir la luminosité (0-100)
  Future<bool> setBrightness(String topic, int brightness) {
    // Conversion en 0-255
    final rawBrightness = ((brightness * 255) / 100).round();
    return _publishToDevice(topic, 'brightness', rawBrightness.toString());
  }

  // Définir la couleur RGB
  Future<bool> setRgbColor(String topic, int r, int g, int b) {
    return _publishToDevice(topic, 'color', '$r,$g,$b');
  }

  Future<bool> publishMessage(String topic, String message) async {
    if (!_isConnected) {
      final connected = await connect();
      if (!connected) return false;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    print('Publishing -> topic: $topic, message: $message');

    try {
      // Do not set retain by default (some devices react differently to retained messages)
      _client!.publishMessage(
        topic,
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: false,
      );
      
      // Ajouter à l'historique
      _history.insert(0, CommandHistory(
        topic: topic,
        message: message,
        timestamp: DateTime.now(),
        success: true,
        isIncoming: false,
      ));
      notifyListeners();
      
      return true;
    } catch (e) {
      print('Error publishing message: $e');
      
      // Ajouter l'erreur à l'historique
      _history.insert(0, CommandHistory(
        topic: topic,
        message: message,
        timestamp: DateTime.now(),
        success: false,
        error: e.toString(),
        isIncoming: false,
      ));
      notifyListeners();
      
      return false;
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _wasDisconnectedDueToNetwork = false;
    _deviceStates.clear();
    _client?.disconnect();
    _client = null;
    _isConnected = false;
    notifyListeners();
  }
  
  void dispose() {
    _reconnectTimer?.cancel();
    _connectivitySubscription?.cancel();
    _updatesSubscription?.cancel();
    _powerRequestTimer?.cancel();
    disconnect();
    super.dispose();
  }

  Future<bool> reconnect({required String server, required int port, required String username, required String password}) async {
    disconnect();
    await Future.delayed(const Duration(milliseconds: 2000));
    return await connect(server: server, port: port, username: username, password: password);
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }
}