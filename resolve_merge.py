import re

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Block 3: SENDER SCREEN comment
content = re.sub(
    r'<<<<<<< HEAD\n// SENDER SCREEN \(CAMERA RECORDING — NO AGORA\)\n=======\n// SENDER SCREEN \(CAMERA, AUTO-RECORD & FALL DETECTION LOGIC\)\n>>>>>>> [a-f0-9]+\n',
    r'// SENDER SCREEN (CAMERA, AUTO-RECORD & FALL DETECTION LOGIC)\n',
    content
)

# Block 4: SenderScreenState variables
content = re.sub(
    r'<<<<<<< HEAD\n\s*bool _pendingSosTrigger = false;\n\s*late AnimationController _sosPulse;\n\s*late Animation<double> _sosAnim;\n\s*StreamSubscription\? _sosSub;\n\s*StreamSubscription\? _firebaseSosSub;\n\s*StreamSubscription\? _directBleSub;\n=======\n\s*// Fall Detection\n\s*FallDetectionService\? _fallDetectionService;\n\s*bool _fallDetectionEnabled = false;\n\s*bool _fallDetected = false;\n>>>>>>> [a-f0-9]+\n',
    r'''  bool _pendingSosTrigger = false;
  late AnimationController _sosPulse;
  late Animation<double> _sosAnim;
  StreamSubscription? _sosSub;
  StreamSubscription? _firebaseSosSub;
  StreamSubscription? _directBleSub;
  
  // Fall Detection
  FallDetectionService? _fallDetectionService;
  bool _fallDetectionEnabled = false;
  bool _fallDetected = false;
''',
    content
)

# Block 6: SnackBar resolution
content = re.sub(
    r'<<<<<<< HEAD\n\s*ScaffoldMessenger.of\(context\).showSnackBar\(SnackBar\(\n\s*content: Text\(\'Evidence saved: \$\{video.path\}\', style: const TextStyle\(color: _Neon.textMain\)\),\n\s*backgroundColor: _Neon.lime.withOpacity\(0.25\),\n\s*\)\);\n=======\n\s*ScaffoldMessenger.of\(context\).showSnackBar\(SnackBar\(content: Text\(\'Evidence Saved: \$\{video.path\}\'\), backgroundColor: Colors.green\)\);\n\n\s*// Restart image stream for fall detection if still enabled\n\s*if \(_fallDetectionEnabled && _cameras.isNotEmpty\) {\n\s*_cameraController!\.startImageStream\(\(CameraImage image\) {\n\s*_fallDetectionService\?\.processCameraImage\(image, _cameras\[0\]\);\n\s*}\);\n\s*}\n>>>>>>> [a-f0-9]+\n',
    r'''      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Evidence saved: ${video.path}', style: const TextStyle(color: _Neon.textMain)),
        backgroundColor: _Neon.lime.withOpacity(0.25),
      ));

      // Restart image stream for fall detection if still enabled
      if (_fallDetectionEnabled && _cameras.isNotEmpty) {
        _cameraController!.startImageStream((CameraImage image) {
          _fallDetectionService?.processCameraImage(image, _cameras[0]);
        });
      }
''',
    content
)

# Block 7: Dispose block
content = re.sub(
    r'<<<<<<< HEAD\n\s*_sosPulse.dispose\(\);\n\s*_sosSub\?\.cancel\(\);\n\s*_firebaseSosSub\?\.cancel\(\);\n\s*_directBleSub\?\.cancel\(\);\n=======\n\s*_fallDetectionService\?\.dispose\(\);\n>>>>>>> [a-f0-9]+\n',
    r'''    _sosPulse.dispose();
    _sosSub?.cancel();
    _firebaseSosSub?.cancel();
    _directBleSub?.cancel();
    _fallDetectionService?.dispose();
''',
    content
)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("Simple replacements done!")
