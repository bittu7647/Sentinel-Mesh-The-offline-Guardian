import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../services/ai_service.dart';
import '../../services/fall_detection_service.dart';
import '../../core/animations/staggered_list_animation.dart';
import 'widgets/sos_pulse_button.dart';
import 'widgets/fall_detection_toggle.dart';

class SenderModeScreen extends StatefulWidget {
  const SenderModeScreen({super.key});

  @override
  State<SenderModeScreen> createState() => _SenderModeScreenState();
}

class _SenderModeScreenState extends State<SenderModeScreen> {
  CameraController? _cameraController;
  bool _isRecording = false;
  bool _fallDetectionEnabled = false;
  bool _fallDetected = false;
  FallDetectionService? _fallDetectionService;
  StreamSubscription? _sosSub;

  @override
  void initState() {
    super.initState();
    _initCamera();

    // Hardware Trigger Listener
    _sosSub = FlutterBackgroundService().on('sos_triggered').listen((_) {
      if (mounted && !_isRecording) {
        debugPrint("🚨 Hardware SOS detected on Sender screen! Triggering camera...");
        _triggerSOS();
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _cameraController = CameraController(cameras[0], ResolutionPreset.medium, enableAudio: true);
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  @override
  void dispose() {
    _sosSub?.cancel();
    _stopFallDetection();
    _cameraController?.dispose();
    super.dispose();
  }

  void _toggleFallDetection(bool enabled) {
    setState(() => _fallDetectionEnabled = enabled);
    if (enabled) {
      _startFallDetection();
    } else {
      _stopFallDetection();
    }
  }

  void _startFallDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    _fallDetectionService = FallDetectionService(onFallDetected: _onFallDetected);
    _cameraController!.startImageStream((image) {
       _fallDetectionService?.processCameraImage(image, _cameraController!.description);
    });
  }

  void _stopFallDetection() {
    _cameraController?.stopImageStream();
    _fallDetectionService?.dispose();
    _fallDetectionService = null;
  }

  void _onFallDetected() {
    if (mounted) setState(() => _fallDetected = true);
    _triggerSOS();
  }

  String? _aiReport;
  bool _isAnalyzing = false;

  void _generateAIReport(String path) async {
    setState(() => _isAnalyzing = true);
    final report = await AIService.generateVideoReport(path);
    if (mounted) {
      setState(() {
        _aiReport = report;
        _isAnalyzing = false;
      });
    }
  }

  Future<void> _triggerSOS() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    HapticFeedback.heavyImpact();

    if (!_isRecording) {
      // CRITICAL FIX: Stop image stream (Fall Detection) before starting video recording
      // Android camera cannot handle both simultaneously.
      if (_fallDetectionEnabled) {
        await _cameraController?.stopImageStream();
      }

      _aiReport = null; // Clear old report
      await _cameraController!.startVideoRecording();
      setState(() => _isRecording = true);

      try {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high).timeout(const Duration(seconds: 5));
        await FirebaseDatabase.instance.ref('devices/device001').update({
          'status': 'ACTIVE',
          'lat': pos.latitude,
          'lng': pos.longitude,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {
        await FirebaseDatabase.instance.ref('devices/device001').update({
          'status': 'ACTIVE',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
    } else {
      final file = await _cameraController!.stopVideoRecording();
      setState(() => _isRecording = false);

      // Resume Fall Detection if it was enabled
      if (_fallDetectionEnabled) {
        _startFallDetection();
      }

      await FirebaseDatabase.instance.ref('devices/device001').update({'status': 'IDLE'});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Recording ended. AI Analysis starting...")),
        );
        _generateAIReport(file.path);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera Preview Background
          if (_cameraController != null && _cameraController!.value.isInitialized)
            Positioned.fill(
              child: AspectRatio(
                aspectRatio: _cameraController!.value.aspectRatio,
                child: CameraPreview(_cameraController!),
              ),
            )
          else
            Container(color: AppColors.colorDeepGreen),

          // Dark Overlay for UI readability
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.4),
            ),
          ),

          // AI Report Overlay
          if (_aiReport != null || _isAnalyzing)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("INCIDENT REPORT", style: AppTextStyles.displayMedium.copyWith(color: AppColors.colorAquaMint)),
                        IconButton(
                          onPressed: () => setState(() => _aiReport = null),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        )
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        child: _isAnalyzing
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(height: 100),
                                  const CircularProgressIndicator(color: AppColors.colorAquaMint),
                                  const SizedBox(height: 24),
                                  Text("AI EXAMINING EVIDENCE...", style: AppTextStyles.labelLarge),
                                ],
                              ),
                            )
                          : Text(
                              _aiReport!,
                              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.colorMintWhite, height: 1.5),
                            ),
                      ),
                    ),
                    if (!_isAnalyzing)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: ElevatedButton.icon(
                          onPressed: () {}, // Future: Share report functionality
                          icon: const Icon(Icons.share_rounded),
                          label: const Text("FORWARD TO OFFICIALS"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.colorAquaMint,
                            foregroundColor: AppColors.colorDeepGreen,
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Bottom Controls
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_fallDetected)
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.colorDanger.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.colorDanger),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_rounded, color: AppColors.colorDanger),
                        const SizedBox(width: 12),
                        Text("FALL DETECTED — SOS ACTIVE", style: AppTextStyles.labelMedium.copyWith(color: Colors.white)),
                      ],
                    ),
                  ),
                FallDetectionToggle(
                  initialValue: _fallDetectionEnabled,
                  onChanged: _toggleFallDetection,
                ),
                const SizedBox(height: 60),
                SOSPulseButton(
                  onTrigger: _triggerSOS,
                  isRecording: _isRecording,
                ),
                const SizedBox(height: 40),
                Text(
                  "ESP32 AUTO-MONITORING ACTIVE",
                  style: AppTextStyles.captionTech,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
