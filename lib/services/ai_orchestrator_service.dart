import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'threat_evaluator.dart';
import '../models/threat_level.dart';
import 'ai_service.dart';
import 'places_service.dart';
import 'audio_ai_service.dart';
import 'route_anomaly_service.dart';
import 'vision_threat_service.dart';

class AIOrchestrator {
  static final AIOrchestrator _instance = AIOrchestrator._internal();
  factory AIOrchestrator() => _instance;
  AIOrchestrator._internal();

  AIState _currentState = AIState.initial();
  final _stateController = StreamController<AIState>.broadcast();
  Stream<AIState> get stateStream => _stateController.stream;

  final AudioAiService _audioAiService = AudioAiService();
  final RouteAnomalyService _routeAnomalyService = RouteAnomalyService();
  final VisionThreatService _visionThreatService = VisionThreatService();

  void start(ServiceInstance service) {
    // Initialize AI Services
    _audioAiService.initialize();
    _routeAnomalyService.initialize();
    // Vision service needs a camera, typically initialized in UI, but we prep it here
    
    // Event Loop: Polls sensor fusion state every 5 seconds
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _orchestrate(service);
    });
  }

  Future<void> _orchestrate(ServiceInstance service) async {
    // Determine context (simplified for background isolate)
    final score = ThreatEvaluator.calculateScore(
      bleSosTriggered: false,
      motionAnomaly: false,
      audioClassification: null,
      isUnsafeLocation: false,
    );

    final newLevel = ThreatEvaluator.mapScoreToLevel(score);

    if (newLevel != _currentState.level) {
      final reasoning = await AIService.reasonOverEnvironment({
        "threat_score": score,
        "current_level": newLevel.name,
      });

      _currentState = AIState(
        level: newLevel,
        confidence: score,
        reasoning: reasoning['reasoning'] ?? "Transitioning state.",
        activeSensors: _getSensorsForLevel(newLevel),
      );

      _stateController.add(_currentState);
      service.invoke('ai_state_change', {
        "level": newLevel.index,
        "reasoning": _currentState.reasoning,
      });

      _executeAgenticActions(newLevel, service);
    }
  }

  Map<String, dynamic> _getSensorsForLevel(ThreatLevel level) {
    switch (level) {
      case ThreatLevel.defcon5Baseline:
        return {"BLE": true, "Motion": true, "Mic": false, "Camera": false};
      case ThreatLevel.defcon4Suspicion:
        return {"BLE": true, "Motion": true, "Mic": true, "Camera": false};
      case ThreatLevel.defcon2Verification:
        return {"BLE": true, "Motion": true, "Mic": true, "Camera": true};
      case ThreatLevel.defcon1Action:
        return {"BLE": true, "Motion": true, "Mic": true, "Camera": true};
    }
  }

  void _executeAgenticActions(ThreatLevel level, ServiceInstance service) async {
    if (level == ThreatLevel.defcon4Suspicion || level == ThreatLevel.defcon2Verification) {
      // AI Pre-fetching: High risk detected. Cache nearby safety hubs.
      try {
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
        // Swarm fetch in background
        PlacesService.getNearbyPlaces(pos.latitude, pos.longitude, 'police');
        PlacesService.getNearbyPlaces(pos.latitude, pos.longitude, 'hospital');
        service.invoke('ai_log', {"msg": "AI Core cached nearby safety hubs."});
      } catch (_) {}
    }

    if (level == ThreatLevel.defcon2Verification) {
      service.invoke('sos_triggered');
    }
  }
}
