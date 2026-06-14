import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/animations/staggered_list_animation.dart';
import 'widgets/atom_logo_widget.dart';
import 'widgets/connection_status_bar.dart';
import 'widgets/mode_grid.dart';
import 'widgets/emergency_support_row.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppConnectionState _connectionState = AppConnectionState.disconnected;
  String _aiReasoning = "System monitoring active. No threats detected.";
  int _aiDefcon = 5;
  StreamSubscription? _bleSub;
  StreamSubscription? _aiSub;
  StreamSubscription? _sosSub;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _initListeners();
  }

  Future<void> _requestPermissions() async {
    try {
      // Bluetooth permissions for Android 12+
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
      ].request();

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse) {
        // Request background location for continuous tracking
        await Permission.locationAlways.request();
      }
    } catch (e) {
      debugPrint("Permission Error: $e");
    }
  }

  bool _isNavigating = false;

  void _navigateToSenderIfNotThere() {
    if (!mounted || _isNavigating) return;
    
    // Check current route to prevent duplicate pushes
    final router = GoRouter.of(context);
    final currentPath = router.routerDelegate.currentConfiguration.uri.toString();
    
    if (!currentPath.startsWith('/sender')) {
      _isNavigating = true;
      context.push('/sender?auto_start=true').then((_) {
         if (mounted) _isNavigating = false;
      });
    }
  }

  void _initListeners() {
    _bleSub = FlutterBackgroundService().on('ble_state').listen((event) {
      if (mounted) {
        setState(() {
          final state = event?['state'] ?? 'disconnected';
          if (state == 'connected') {
            _connectionState = AppConnectionState.connected;
          } else if (state == 'scanning' || state == 'connecting') {
            _connectionState = AppConnectionState.scanning;
          } else {
            _connectionState = AppConnectionState.disconnected;
          }
        });
      }
    });

    _aiSub = FlutterBackgroundService().on('ai_state_change').listen((event) {
      if (mounted) {
        setState(() {
          _aiDefcon = event?['level'] ?? 5;
          _aiReasoning = event?['reasoning'] ?? "Analyzing environment...";
        });
      }
    });

    _sosSub = FlutterBackgroundService().on('sos_triggered').listen((_) {
      _navigateToSenderIfNotThere();
    });

    _initNativeIntentListener();
  }

  static const MethodChannel _channel = MethodChannel('sentinel_mesh/esp_watcher');

  Future<void> _initNativeIntentListener() async {
    // 1. Check if the app was just opened via an emergency intent
    try {
      final bool isAutoRecord = await _channel.invokeMethod('isAutoRecord') ?? false;
      if (isAutoRecord) {
        _navigateToSenderIfNotThere();
      }
    } catch (_) {}

    // 2. Listen for emergency intents while the app is already open
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'autoRecord') {
        _navigateToSenderIfNotThere();
      }
    });
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    _aiSub?.cancel();
    _sosSub?.cancel();
    super.dispose();
  }

  void _toggleConnection() {
    if (_connectionState == AppConnectionState.disconnected) {
      FlutterBackgroundService().invoke('force_connect');
    } else {
      FlutterBackgroundService().invoke('cancel_scan');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                const StaggeredListAnimation(
                  index: 0,
                  child: Center(child: AtomLogoWidget()),
                ),
                const SizedBox(height: 32),
                StaggeredListAnimation(
                  index: 1,
                  child: _buildStatusCard(),
                ),
                const SizedBox(height: 24),
                StaggeredListAnimation(
                  index: 2,
                  child: ConnectionStatusBar(
                    state: _connectionState,
                    onActionPressed: _toggleConnection,
                  ),
                ),
                const SizedBox(height: 32),
                ModeGrid(
                  onSenderTap: () => context.push('/sender'),
                  onResponderTap: () => context.push('/radar'),
                ),
                const SizedBox(height: 40),
                StaggeredListAnimation(
                  index: 5,
                  child: Text(
                    "EMERGENCY SUPPORT",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.captionTech,
                  ),
                ),
                const SizedBox(height: 16),
                StaggeredListAnimation(
                  index: 6,
                  child: EmergencySupportRow(
                    onPoliceTap: () => context.push('/police'),
                    onMedicalTap: () => context.push('/medical'),
                  ),
                ),
                const SizedBox(height: 16),
                StaggeredListAnimation(
                  index: 7,
                  child: _buildChatbotButton(context),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final bool isEscalated = _aiDefcon < 5;
    final Color cardBorderColor = isEscalated ? AppColors.colorDanger.withValues(alpha: 0.5) : AppColors.colorBorder;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.colorSurfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorderColor),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: (5 - _aiDefcon) / 4,
                strokeWidth: 2,
                color: isEscalated ? AppColors.colorDanger : AppColors.colorAquaMint,
              ),
              Icon(
                isEscalated ? Icons.security : Icons.radar_rounded,
                size: 16,
                color: isEscalated ? AppColors.colorDanger : AppColors.colorAquaMint,
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "AI CORE: DEFCON $_aiDefcon",
                  style: AppTextStyles.labelLarge.copyWith(
                    color: isEscalated ? AppColors.colorDanger : AppColors.colorAquaMint,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _aiReasoning,
                  style: AppTextStyles.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatbotButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => context.push('/chatbot'),
      icon: const Icon(Icons.forum_rounded, size: 20),
      label: const Text("SAFETY AI ASSISTANT"),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.colorSurfaceAlt,
        foregroundColor: AppColors.colorAquaMint,
        side: const BorderSide(color: AppColors.colorBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
