import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/command_history.dart';
import '../models/device_state.dart';

class MQTTService extends ChangeNotifier {
  static final MQTTService _instance = MQTTService._internal();
  factory MQTTService() => _instance;
  MQTTService._internal();

  MqttServerClient? _client;
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  final List<CommandHistory> _history = [];
  List<CommandHistory> get history => List.unmodifiable(_history);
  
  final Map<String, DeviceState> _deviceStates = {};
  Map<String, DeviceState> get deviceStates => Map.unmodifiable(_deviceStates);

  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSubscription;

  Future<bool> connect() async {
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      return true;
    }

    _client = MqttServerClient('192.168.50.27', 'flutter_client_${DateTime.now().millisecondsSinceEpoch}');
    _client!.port = 1883;
    _client!.logging(on: true);
    _client!.keepAlivePeriod = 60;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onSubscribed = _onSubscribed;

    final connMessage = MqttConnectMessage()
        .authenticateAs('fil_rouge', 'lolipop')
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

  void _onDisconnected() {
    _isConnected = false;
    notifyListeners();
    print('Disconnected');
    // cancel incoming subscription
    try {
      _updatesSubscription?.cancel();
      _updatesSubscription = null;
    } catch (_) {}
  }

  void _onConnected() {
    _isConnected = true;
    notifyListeners();
    try {
      final payload = MqttClientPayloadBuilder()..addString('Online');
      _client?.publishMessage('home/status', MqttQos.atLeastOnce, payload.payload!);
    } catch (e) {
      print('Warning: failed to publish online status: $e');
    }
    print('Connected');
  }

  void _onSubscribed(String topic) {
    print('Subscribed to: $topic');
  }

  void _handleIncomingMessage(String topic, String payload) {
    try {
      // Extraire le device ID et le type de message du topic
      // Format: home/lum_1/type/state
      final parts = topic.split('/');
      if (parts.length < 3) return; // Ignore les topics trop courts
      
      final deviceId = parts[1]; // ex: lum_1
      final baseTopic = 'home/$deviceId/set';
      final messageType = parts[2]; // ex: state, brightness, rgb_color
      
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
    _history.insert(0, CommandHistory(topic: topic, message: payload, timestamp: DateTime.now(), success: true));
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
        success: true
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
        error: e.toString()
      ));
      notifyListeners();
      
      return false;
    }
  }

  void disconnect() {
    _client?.disconnect();
    _isConnected = false;
    notifyListeners();
  }

  void clearHistory() {
    _history.clear();
    notifyListeners();
  }
}