import 'package:flutter/material.dart';
import '../services/mqtt_service.dart';
import '../models/device_state.dart';

class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({Key? key}) : super(key: key);

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  final MQTTService _mqtt = MQTTService();

  @override
  void initState() {
    super.initState();
    // Listen for MQTT updates; request is sent at app startup
    _mqtt.connect();
    _mqtt.addListener(_onMqttChanged);
  }

  void _onMqttChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _mqtt.removeListener(_onMqttChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show all devices received, regardless of their state
    final devices = _mqtt.deviceStates.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: devices.isEmpty
            ? const Center(child: Text('Aucun périphérique détecté — en attente de réponse...'))
            : ListView.separated(
                itemCount: devices.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final DeviceState ds = devices[index];
                  final name = ds.friendlyName ?? ds.topic;
                  return ListTile(
                    leading: Builder(builder: (ctx) {
                      // Decide icon by device type inferred from topic or friendlyName
                      final nameLower = (ds.friendlyName ?? ds.topic).toLowerCase();
                      IconData iconData = Icons.device_unknown;
                      if (ds.topic.toLowerCase().contains('lum') || nameLower.contains('lum') || nameLower.contains('light')) {
                        iconData = Icons.lightbulb;
                      } else if (ds.topic.toLowerCase().contains('prise') || nameLower.contains('prise') || nameLower.contains('switch') || nameLower.contains('plug')) {
                        iconData = Icons.power;
                      }

                      Color bgColor;
                      try {
                        bgColor = Color(int.parse(ds.displayColor.replaceFirst('#', '0xFF')));
                      } catch (_) {
                        bgColor = Colors.grey;
                      }

                      return CircleAvatar(
                        radius: 20,
                        backgroundColor: bgColor,
                        child: Icon(iconData, color: Colors.white, size: 20),
                      );
                    }),
                    title: Text(name),
                    subtitle: Text('${ds.state} • ${ds.brightness}% • ${ds.rgbColor != null ? ds.rgbColor.toString() : ''}'),
                    trailing: Text('${ds.lastUpdated.hour.toString().padLeft(2,'0')}:${ds.lastUpdated.minute.toString().padLeft(2,'0')}'),
                  );
                },
              ),
      ),
    );
  }
}
