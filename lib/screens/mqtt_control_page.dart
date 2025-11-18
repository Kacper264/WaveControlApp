import 'package:flutter/material.dart';
import '../services/mqtt_service.dart';
import 'dart:async';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class MqttControlPage extends StatefulWidget {
  const MqttControlPage({super.key});

  @override
  State<MqttControlPage> createState() => _MqttControlPageState();
}

class _MqttControlPageState extends State<MqttControlPage> {
  final MQTTService _mqtt = MQTTService();

  @override
  void initState() {
    super.initState();
    _mqtt.addListener(_onMqttChanged);
    _mqtt.connect();
  }

  @override
  void dispose() {
    _mqtt.removeListener(_onMqttChanged);
    super.dispose();
  }

  void _onMqttChanged() {
    if (!mounted) return;
    setState(() {});
  }

  // Affiche le dialog de sélection de couleur
  Future<void> _showColorPicker(String topic, Color currentColor) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Choisir une couleur'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: currentColor,
              onColorChanged: (Color color) {
                // Envoie la couleur immédiatement quand elle change
                _mqtt.setRgbColor(topic, color.red, color.green, color.blue);
              },
              enableAlpha: false,
              displayThumbColor: true,
              paletteType: PaletteType.hsvWithHue,
              labelTypes: const [],  // Cache les labels RGB/HSV
              pickerAreaBorderRadius: const BorderRadius.all(Radius.circular(10)),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Fermer'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  // Affiche le dialog de réglage de la luminosité
  Future<void> _showBrightnessSlider(String topic, int currentBrightness) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Régler la luminosité'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${currentBrightness}%'),
                  Slider(
                    value: currentBrightness.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '${currentBrightness}%',
                    onChanged: (double value) {
                      setState(() {
                        currentBrightness = value.round();
                      });
                      _mqtt.setBrightness(topic, currentBrightness);
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Fermer'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _send(String topic, String msg) async {
    final success = await _mqtt.publishMessage(topic, msg);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Commande $msg envoyée' : 'Échec $msg'),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Requests'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              children: [
                Icon(_mqtt.isConnected ? Icons.wifi : Icons.wifi_off, color: _mqtt.isConnected ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Text(_mqtt.isConnected ? 'Connecté' : 'Déconnecté', style: const TextStyle(color: Colors.black54)),
              ],
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              itemCount: _mqtt.deviceStates.values.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final device = _mqtt.deviceStates.values.toList()[index];
                final topic = device.topic;
                final name = device.friendlyName ?? topic;
                final state = device.state;
                final isLamp = !topic.contains('prise');
                final displayColor = isLamp ? device.displayColor : null;
                final brightness = isLamp ? device.brightness : 0;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Row(
                    children: [
                      Expanded(child: Text(name)),
                      const SizedBox(width: 8),
                      Builder(builder: (ctx) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isLamp) ...[
                              GestureDetector(
                                onTap: () {
                                  if (state == 'ON') {
                                    _showColorPicker(
                                      topic,
                                      Color(int.parse(displayColor!.replaceFirst('#', '0xFF'))),
                                    );
                                  }
                                },
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Color(int.parse(displayColor!.replaceFirst('#', '0xFF'))),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.black12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (isLamp && brightness > 0) ...[
                              GestureDetector(
                                onTap: () {
                                  if (state == 'ON') {
                                    _showBrightnessSlider(topic, brightness);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$brightness%',
                                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              state,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: state == 'ON' ? Colors.green : (state == 'OFF' ? Colors.grey[700] : Colors.black54),
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                  subtitle: Text(topic, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () => _send(topic, 'ON'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        child: const Text('ON'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _send(topic, 'OFF'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                        child: const Text('OFF'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.all(12),
            alignment: Alignment.centerLeft,
            child: const Text('Historique', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            height: 160,
            child: _mqtt.history.isEmpty
                ? const Center(child: Text('Pas d\'historique'))
                : ListView.builder(
                    itemCount: _mqtt.history.length,
                    itemBuilder: (context, index) {
                      final h = _mqtt.history[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(h.success ? Icons.check_circle : Icons.error, color: h.success ? Colors.green : Colors.red, size: 18),
                        title: Text(h.toString(), style: const TextStyle(fontSize: 12)),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => _mqtt.clearHistory(),
                  child: const Text('Effacer l\'historique'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fermer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
