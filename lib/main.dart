import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:camera/camera.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/ai_orchestrator_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Camera (Non-blocking)
  try {
    await availableCameras();
  } catch (_) {}
  
  // Load env
  await dotenv.load(fileName: ".env");

  // 2. Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: dotenv.env['FIREBASE_API_KEY'] ?? '',
        authDomain: dotenv.env['FIREBASE_AUTH_DOMAIN'] ?? '',
        databaseURL: dotenv.env['FIREBASE_DATABASE_URL'] ?? '',
        projectId: dotenv.env['FIREBASE_PROJECT_ID'] ?? '',
        storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? '',
        messagingSenderId: dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '',
        appId: dotenv.env['FIREBASE_APP_ID'] ?? '',
      ),
    );
  } catch (e) {
    debugPrint("Firebase Init Error: $e");
  }
  
  // 3. Initialize Notifications
  const AndroidInitializationSettings initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings = InitializationSettings(android: initSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // 4. Start background service
  try {
    await initializeService();
  } catch (e) {
    debugPrint("Background Service Init Error: $e");
  }

  // 5. Request Location and Bluetooth Permissions
  // (Moved to HomeScreen.dart so it runs inside a valid UI context)
  
  runApp(const SentinelSafeApp());
}

class SentinelSafeApp extends StatelessWidget {
  const SentinelSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'SentinelSafe',
      theme: AppTheme.darkTheme,
      routerConfig: AppRouter.router,
    );
  }
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'sentinelsafe_bg',
    'SentinelSafe Background Service',
    description: 'Autonomous safety monitoring.',
    importance: Importance.low,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'sentinelsafe_bg',
      initialNotificationTitle: 'SentinelSafe Active',
      initialNotificationContent: 'Monitoring for Sentinel hardware...',
      foregroundServiceNotificationId: 889,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
    ),
  );
  await service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  bool isConnecting = false;
  bool autoScanEnabled = false;
  BluetoothDevice? connectedDevice;

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('force_connect').listen((event) async {
    autoScanEnabled = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_scan_enabled', true);
    _triggerScan(service, connectedDevice, isConnecting);
  });

  service.on('cancel_scan').listen((event) async {
    autoScanEnabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_scan_enabled', false);
    isConnecting = false;
    connectedDevice?.disconnect();
    connectedDevice = null;
    try { FlutterBluePlus.stopScan(); } catch (_) {}
    service.invoke('ble_state', {'state': 'disconnected'});
  });

  final prefs = await SharedPreferences.getInstance();
  autoScanEnabled = prefs.getBool('auto_scan_enabled') ?? false;

  // Initialize the AI Core Orchestrator
  AIOrchestrator().start(service);

  // Background BLE logic
  FlutterBluePlus.scanResults.listen((results) async {
    if (isConnecting || connectedDevice != null) return;
    for (ScanResult r in results) {
      final String name = r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.localName;
      if (name == 'Sentinel') {
        isConnecting = true;
        try { await FlutterBluePlus.stopScan(); } catch (_) {}
        service.invoke('ble_state', {'state': 'connecting'});

        try {
           // Clear any stale GATT connections from previous app crashes
           try { await r.device.disconnect(); } catch (_) {}
           await Future.delayed(const Duration(milliseconds: 500));

           await r.device.connect(autoConnect: false, timeout: const Duration(seconds: 15));
           connectedDevice = r.device;
           await _setupBleListeners(connectedDevice!, service);
           service.invoke('ble_state', {'state': 'connected'});

           // Connection Success Notification
           flutterLocalNotificationsPlugin.show(
              88,
              'Sentinel Hardware Connected',
              'The app is now synced with your physical SOS button.',
              const NotificationDetails(
                android: AndroidNotificationDetails('sentinelsafe_bg', 'Safety Status', importance: Importance.low),
              ),
           );

           r.device.connectionState.listen((state) {
             if (state == BluetoothConnectionState.disconnected) {
               connectedDevice = null;
               isConnecting = false;
               service.invoke('ble_state', {'state': 'disconnected'});
             }
           });
        } catch (e) {
          debugPrint("BLE CONNECT ERROR: $e");
          isConnecting = false;
          connectedDevice = null;
          service.invoke('ble_state', {'state': 'disconnected'});
        }
      }
    }
  });

  Timer.periodic(const Duration(seconds: 15), (timer) async {
    if (!autoScanEnabled || connectedDevice != null || isConnecting) return;
    if (FlutterBluePlus.isScanningNow == false) {
      try {
        service.invoke('ble_state', {'state': 'scanning'});
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      } catch (e) {
        debugPrint("BLE SCAN ERROR: $e");
      }
    }
  });
}

Future<void> _triggerScan(ServiceInstance service, BluetoothDevice? connectedDevice, bool isConnecting) async {
  if (connectedDevice != null || isConnecting || FlutterBluePlus.isScanningNow) return;
  try {
    service.invoke('ble_state', {'state': 'scanning'});
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
  } catch (e) {
    debugPrint("MANUAL BLE SCAN ERROR: $e");
    service.invoke('ble_state', {'state': 'disconnected'});
  }
}

Future<void> _updateFirebaseActive() async {
  String firebaseURL = "https://esp32iotproject-e9fe1-default-rtdb.asia-southeast1.firebasedatabase.app";
  
  String lat = "0.000000";
  String lng = "0.000000";
  String gpsStatus = "NO_SIGNAL";

  try {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 5),
    );
    lat = position.latitude.toStringAsFixed(6);
    lng = position.longitude.toStringAsFixed(6);
    gpsStatus = "OK";
    debugPrint("📱 Phone GPS Acquired: $lat, $lng");
  } catch (e) {
    debugPrint("⚠️ Failed to get Phone GPS: $e");
  }

  try {
    final fbUrl = Uri.parse("$firebaseURL/devices/device001.json");
    await http.put(fbUrl, 
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "status": "ACTIVE",
        "deviceID": 1,
        "lat": double.tryParse(lat) ?? 0.0,
        "lng": double.tryParse(lng) ?? 0.0,
        "gps": gpsStatus,
        "gps_live": gpsStatus == "OK"
      })
    );
    debugPrint("Firebase updated successfully via Flutter");
  } catch (e) {
    debugPrint("Failed to update Firebase: $e");
  }
}

Future<void> _sendIdleStatus() async {
  String firebaseURL = "https://esp32iotproject-e9fe1-default-rtdb.asia-southeast1.firebasedatabase.app";
  try {
    final fbUrl = Uri.parse("$firebaseURL/devices/device001.json");
    await http.put(fbUrl, headers: {"Content-Type": "application/json"}, body: jsonEncode({"status": "IDLE", "deviceID": 1}));
    debugPrint("Firebase set to IDLE via Flutter");
  } catch (e) {
    debugPrint("Failed to set IDLE: $e");
  }
}

Future<void> _setupBleListeners(BluetoothDevice device, ServiceInstance service) async {
  try {
    List<BluetoothService> services = await device.discoverServices();
    for (var svc in services) {
      final svcUuid = svc.uuid.toString().toLowerCase();
      if (svcUuid.contains("ffe0")) {
        for (var charc in svc.characteristics) {
          final charUuid = charc.uuid.toString().toLowerCase();
          if (charUuid.contains("ffe1")) {
            debugPrint("✅ Found SOS Characteristic! Subscribing to notifications...");
            try {
              await charc.setNotifyValue(true);
              // Use onValueReceived for real-time notifications
              charc.onValueReceived.listen((value) async {
              if (value.isNotEmpty) {
                String msg = utf8.decode(value);
                debugPrint("BLE RECEIVE: $msg");
                if (msg.trim() == '1' || msg.trim() == '2') {
                  // UPDATE FIREBASE VIA PHONE INTERNET
                  _updateFirebaseActive();

                  // BROADCAST TO SERVICE CHANNEL
                  service.invoke('sos_triggered');

                  // High-priority Alert Notification
                  flutterLocalNotificationsPlugin.show(
                    99,
                    '🚨 HARDWARE SOS TRIGGERED',
                    'Sentinel hardware button pressed. Activating recording.',
                    const NotificationDetails(
                      android: AndroidNotificationDetails(
                        'sentinelsafe_bg',
                        'Emergency Alerts',
                        importance: Importance.max,
                        priority: Priority.high,
                        fullScreenIntent: true,
                      ),
                    ),
                  );

                  if (Platform.isAndroid) {
                    const intent = AndroidIntent(
                      action: 'android.intent.action.MAIN',
                      package: 'com.example.sentinel_mesh',
                      componentName: 'com.example.sentinel_mesh.MainActivity',
                      arguments: <String, dynamic>{'AUTO_RECORD': true},
                      flags: <int>[268435456],
                    );
                    await intent.launch();
                  }
                } else if (msg.trim() == '3') {
                  // STOP RECORDING COMMAND & FIREBASE IDLE
                  _sendIdleStatus();
                  service.invoke('sos_stopped');
                }
              }
            });
            } catch (e) {
              debugPrint("❌ Failed to subscribe to BLE notifications: $e");
            }
          }
        }
      }
    }
  } catch (_) {}
}
