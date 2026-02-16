import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'configuration_screen.dart';
import 'mqtt_control_page.dart';
import 'monitoring_screen.dart';
import 'settings_screen.dart';
import 'view_configs_screen.dart';
// import 'package:battery_plus/battery_plus.dart'; // plus utilisé
import '../services/mqtt_service.dart';
import '../services/app_settings.dart';
import '../widgets/ios_widgets.dart';
import '../theme/app_theme.dart';
import '../models/device_state.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final MQTTService _mqtt = MQTTService();
  // final Battery _battery = Battery(); // plus utilisé
  final AppSettings _settings = AppSettings();
  // int _batteryLevel = 100; // plus utilisé
  late AnimationController _headerAnimation;
  late Animation<double> _headerFade;

  @override
  void initState() {
    super.initState();
    _mqtt.addListener(_onMqttChanged);
    _settings.addListener(_onSettingsChanged);
    // _readBatteryLevel(); // plus utilisé
    
    _headerAnimation = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _headerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _headerAnimation, curve: Curves.easeOut),
    );
    _headerAnimation.forward();
  }

  @override
  void dispose() {
    _mqtt.removeListener(_onMqttChanged);
    _settings.removeListener(_onSettingsChanged);
    _headerAnimation.dispose();
    super.dispose();
  }

  void _onMqttChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }



  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header moderne style iOS
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _headerFade,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top bar avec statut
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Logo et titre
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [AppTheme.primaryPurple, AppTheme.secondaryBlue],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.primaryPurple.withOpacity(0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.watch, color: Colors.white, size: 24),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'WaveControl',
                                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            // Icône paramètres
                            Container(
                              decoration: BoxDecoration(
                                color: isDark ? AppTheme.darkCard : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: AppTheme.cardShadow(isDark),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        pageBuilder: (_, __, ___) => const SettingsScreen(),
                                        transitionsBuilder: (_, anim, __, child) {
                                          return FadeTransition(opacity: anim, child: child);
                                        },
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Icon(
                                      Icons.settings_rounded,
                                      color: isDark ? Colors.white : Colors.black87,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Statut avec badges
                        AnimatedBuilder(
                          animation: _mqtt,
                          builder: (context, _) {
                            return Row(
                              children: [
                                IOSStatusBadge(
                                  text: _mqtt.isConnected ? _settings.text('connected_label') : _settings.text('disconnected_label'),
                                  color: _mqtt.isConnected ? AppTheme.successGreen : AppTheme.errorRed,
                                  icon: _mqtt.isConnected ? Icons.check_circle_rounded : Icons.error_rounded,
                                ),
                                const SizedBox(width: 8),
                                ValueListenableBuilder<BatteryStatus?>(
                                  valueListenable: _mqtt.batteryStatusNotifier,
                                  builder: (context, batteryStatus, _) {
                                    if (batteryStatus == null) {
                                      return IOSStatusBadge(
                                        text: '--%',
                                        color: AppTheme.secondaryBlue,
                                        icon: Icons.battery_unknown_rounded,
                                      );
                                    }
                                    return IOSStatusBadge(
                                      text: '${batteryStatus.batteryLevel}%',
                                      color: batteryStatus.batteryLevel > 20 ? AppTheme.secondaryBlue : AppTheme.warningOrange,
                                      icon: batteryStatus.isCharging
                                          ? Icons.bolt_rounded
                                          : Icons.battery_full_rounded,
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Grille de fonctionnalités ou Monitoring selon le mode
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: _settings.userMode == UserMode.user
                    ? _buildMonitoringSliverGrid(context)
                    : SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.0,
                        ),
                        delegate: SliverChildListDelegate(_buildFeatureCards(context)),
                      ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
      floatingActionButton: _settings.userMode == UserMode.user
          ? FloatingActionButton.extended(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.push(context, _createRoute(const ViewConfigsScreen()));
              },
              backgroundColor: AppTheme.primaryPurple,
              icon: const Icon(Icons.visibility_rounded, color: Colors.white),
              label: Text(
                _settings.text('view_configs'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildMonitoringSliverGrid(BuildContext context) {
    final devices = _mqtt.isConnected ? _mqtt.deviceStates.values.toList() : <DeviceState>[];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    
    if (devices.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _settings.text('no_device'),
              style: theme.textTheme.headlineMedium,
            ),
          ),
        ),
      );
    }
    
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.60,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final ds = devices[index];
          final name = ds.friendlyName ?? ds.topic;
          final isOn = ds.state.toUpperCase() == 'ON';
          final typeLabel = _deviceTypeLabel(ds);
          final timeText = '${ds.lastUpdated.hour.toString().padLeft(2, '0')}:${ds.lastUpdated.minute.toString().padLeft(2, '0')}';
          Color iconBg;
          try {
            iconBg = Color(int.parse(ds.displayColor.replaceFirst('#', '0xFF')));
          } catch (_) {
            iconBg = isDark ? AppTheme.darkElevated : AppTheme.primaryPurple;
          }

          // Sélectionner l'icône en fonction du type et de l'état
          IconData displayIcon;
          if (_isLamp(ds)) {
            displayIcon = isOn ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded;
          } else {
            displayIcon = Icons.electrical_services_rounded;
          }

          // Couleur de l'icône : selon l'état
          Color iconColor;
          if (_isLamp(ds)) {
            iconColor = isOn ? iconBg : (isDark ? Colors.grey[600]! : Colors.grey[400]!);
          } else {
            // Pour les prises : vert si allumée, gris si éteinte
            iconColor = isOn ? AppTheme.successGreen : (isDark ? Colors.grey[600]! : Colors.grey[400]!);
          }

          return IOSCard(
            padding: const EdgeInsets.all(12),
            child: GestureDetector(
              onTap: _isLamp(ds) ? () => _showLightControlDialog(context, ds) : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Grand icône en haut
                  Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: isOn 
                          ? iconBg.withOpacity(0.15)
                          : (isDark ? Colors.grey[800] : Colors.grey[200]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        displayIcon,
                        size: 32,
                        color: iconColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Nom et type
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        typeLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Badge statut
                  IOSStatusBadge(
                    text: isOn ? _settings.text('on') : _settings.text('off'),
                    color: isOn ? AppTheme.successGreen : AppTheme.errorRed,
                    icon: isOn ? Icons.power_rounded : Icons.power_off_rounded,
                  ),
                  const SizedBox(height: 6),
                  // Infos additionnelles
                  if (_isLamp(ds))
                    Text(
                      '${_settings.text('brightness')} : ${ds.brightness}%',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    timeText,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 10, color: isDark ? Colors.white54 : Colors.black45),
                  ),
                ],
              ),
            ),
          );
        },
        childCount: devices.length,
      ),
    );
  }

  bool _isLamp(DeviceState ds) {
    final topic = ds.topic.toLowerCase();
    final name = (ds.friendlyName ?? '').toLowerCase();
    return topic.contains('lum') || name.contains('lum') || name.contains('light');
  }

  String _deviceTypeLabel(DeviceState ds) {
    if (_isLamp(ds)) return _settings.text('light');
    final topic = ds.topic.toLowerCase();
    final name = (ds.friendlyName ?? '').toLowerCase();
    if (topic.contains('prise') || name.contains('prise') || name.contains('plug') || name.contains('switch')) {
      return _settings.text('socket');
    }
    return _settings.text('device');
  }

  void _showLightControlDialog(BuildContext context, DeviceState device) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    int currentBrightness = device.brightness;
    Color currentColor = Color(int.parse(device.displayColor.replaceFirst('#', '0xFF')));
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
              title: Text(device.friendlyName ?? device.topic),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Titre Couleur
                    Text(
                      _settings.text('choose_color'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    // Color Picker
                    ColorPicker(
                      pickerColor: currentColor,
                      onColorChanged: (Color color) {
                        setState(() {
                          currentColor = color;
                        });
                        _mqtt.setRgbColor(device.topic, color.red, color.green, color.blue);
                      },
                      enableAlpha: false,
                      displayThumbColor: true,
                      paletteType: PaletteType.hsvWithHue,
                      labelTypes: const [],
                      pickerAreaBorderRadius: const BorderRadius.all(Radius.circular(10)),
                    ),
                    const SizedBox(height: 24),
                    // Titre Luminosité
                    Text(
                      _settings.text('adjust_brightness'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    // Pourcentage
                    Text(
                      '${currentBrightness}%',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    // Slider Luminosité
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
                        _mqtt.setBrightness(device.topic, currentBrightness);
                      },
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text(_settings.text('close')),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<Widget> _buildFeatureCards(BuildContext context) {
    final cards = <Widget>[];
    final userMode = _settings.userMode;

    // Configuration - Développeur et Technicien uniquement
    if (userMode == UserMode.developer || userMode == UserMode.technician) {
      cards.add(_buildFeatureCard(
        context,
        icon: Icons.tune_rounded,
        title: _settings.text('configuration'),
        subtitle: _settings.text('movements'),
        gradient: const [AppTheme.primaryPurple, Color(0xFF9D8BFF)],
        onTap: () => _showConfigDialog(context),
      ));
    }

    // Monitoring - Tous les modes
    cards.add(_buildFeatureCard(
      context,
      icon: Icons.monitor_heart_rounded,
      title: _settings.text('monitoring'),
      subtitle: _settings.text('surveillance'),
      gradient: const [AppTheme.secondaryBlue, Color(0xFF4DA8FF)],
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          _createRoute(const MonitoringScreen()),
        );
      },
    ));

    // TEST.MQTT - Développeur uniquement
    if (userMode == UserMode.developer) {
      cards.add(_buildFeatureCard(
        context,
        icon: Icons.wifi_rounded,
        title: _settings.text('test_mqtt'),
        subtitle: _settings.text('control'),
        gradient: const [AppTheme.successGreen, Color(0xFF52D77F)],
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            _createRoute(const MqttControlPage()),
          );
        },
      ));
    }

    return cards;
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () {
              HapticFeedback.mediumImpact();
              onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: Colors.white, size: 32),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showConfigDialog(BuildContext context) {
    HapticFeedback.lightImpact();
    Navigator.push(context, _createRoute(const ConfigurationScreen()));
  }

  Route _createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;
        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(position: animation.drive(tween), child: child);
      },
      transitionDuration: const Duration(milliseconds: 350),
    );
  }
}
