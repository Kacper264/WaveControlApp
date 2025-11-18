import 'package:flutter/material.dart';
import '../services/mqtt_service.dart';
import '../models/device_state.dart';

class ConfigurationScreen extends StatefulWidget {
  const ConfigurationScreen({super.key});

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  final MQTTService _mqtt = MQTTService();
  final List<String> mouvements = ['Haut', 'Bas', 'Droite', 'Gauche'];
  final Map<String, String?> actionMouvements = {}; // actionKey -> mouvement

  List<DeviceState> get devices => _mqtt.deviceStates.values.toList();

  List<String> getAvailableMouvements(String excludeKey) {
    final used = actionMouvements.values.where((m) => m != null && m != '' && m != excludeKey).toSet();
    return mouvements.where((m) => !used.contains(m)).toList();
  }

  @override
  void initState() {
    super.initState();
    _mqtt.addListener(_onMqttChanged);
  }

  @override
  void dispose() {
    _mqtt.removeListener(_onMqttChanged);
    super.dispose();
  }

  void _onMqttChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Configuration',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all, color: Colors.red),
            tooltip: 'Reset tous les mouvements',
            onPressed: () {
              setState(() {
                actionMouvements.clear();
              });
            },
          ),
        ],
      ),
      body: devices.isEmpty
          ? const Center(child: Text('Aucun périphérique détecté'))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: devices.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final device = devices[index];
                final isLamp = device.topic.contains('lum');
                final actions = isLamp
                    ? ['ON', 'OFF', '+LUM', '-LUM']
                    : ['ON', 'OFF'];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(isLamp ? Icons.lightbulb : Icons.power, color: isLamp ? Colors.amber : Colors.blueGrey, size: 28),
                                const SizedBox(width: 12),
                                Text(
                                  device.friendlyName ?? device.topic,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...actions.map((action) {
                              final actionKey = '${device.topic}::$action';
                              final availableMouvs = getAvailableMouvements(actionKey);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(action, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                                    ),
                                    const SizedBox(width: 16),
                                    DropdownButton<String>(
                                      value: actionMouvements[actionKey],
                                      hint: const Text('Associer un Mov'),
                                      items: mouvements.map((mouv) {
                                        return DropdownMenuItem<String>(
                                          value: mouv,
                                          enabled: availableMouvs.contains(mouv),
                                          child: Text(mouv, style: TextStyle(color: availableMouvs.contains(mouv) ? Colors.black : Colors.grey)),
                                        );
                                      }).toList(),
                                      onChanged: (selected) {
                                        setState(() {
                                          actionMouvements[actionKey] = selected;
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    if (actionMouvements[actionKey] != null)
                                      IconButton(
                                        icon: const Icon(Icons.clear, color: Colors.redAccent, size: 20),
                                        tooltip: 'Reset mouvement',
                                        onPressed: () {
                                          setState(() {
                                            actionMouvements[actionKey] = null;
                                          });
                                        },
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}