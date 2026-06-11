import sys

with open('lib/main.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
conflict_index = 0
state = 0 # 0=normal, 1=HEAD, 2=THEIRS
head_lines = []
theirs_lines = []

for line in lines:
    if line.startswith('<<<<<<< HEAD'):
        state = 1
        conflict_index += 1
        head_lines = []
        theirs_lines = []
    elif line.startswith('======='):
        state = 2
    elif line.startswith('>>>>>>>'):
        state = 0
        if conflict_index == 1:
            # Block 1: Imports & Background Service
            new_lines.append("import 'screens/ai_chatbot_screen.dart';\n")
            new_lines.append("import 'services/fall_detection_service.dart';\n")
            new_lines.extend(head_lines)
        elif conflict_index == 2:
            # Block 2: HomeScreen UI
            # head_lines has 165 lines. We want to skip the last 40 lines which draw the Police/Medical tools so we can insert the Chatbot button above it.
            # Actually, let's just find the text "APP-ONLY TOOLS" in head_lines and insert the chatbot button above it.
            tools_idx = 0
            for i, hl in enumerate(head_lines):
                if "APP-ONLY TOOLS" in hl:
                    tools_idx = i - 7
                    break
            
            new_lines.extend(head_lines[:tools_idx])
            new_lines.append('''                // ── AI Chatbot Button ──
                _NeonButton(
                  label: "SAFETY CHATBOT  ·  AI ASSISTANT",
                  icon: Icons.smart_toy,
                  glowColor: _Neon.lime,
                  fillColor: _Neon.lime.withOpacity(0.08),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SafetyChatbotScreen())),
                ),
                const SizedBox(height: 16),
''')
            new_lines.extend(head_lines[tools_idx:])
        elif conflict_index == 3:
            # Block 3: Methods
            # Drop the last line of HEAD (Future<void> _triggerSos() async {)
            hl = head_lines[:-1]
            new_lines.extend(hl)
            
            # For THEIRS, drop the last line (Future<void> _triggerRecording() async {)
            tl = theirs_lines[:-1]
            # Replace _triggerRecording with _triggerSos
            tl_str = "".join(tl).replace('_triggerRecording()', '_triggerSos()')
            new_lines.append(tl_str)
            
            # Put back the unified function declaration
            new_lines.append("  Future<void> _triggerSos() async {\n")
            
        elif conflict_index == 4:
            # Block 4: SenderScreen UI Bottom
            new_lines.append('''                  // Fall Detection Toggle
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _Neon.lime.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _fallDetectionEnabled ? Icons.shield : Icons.shield_outlined,
                              color: _fallDetectionEnabled ? _Neon.lime : Colors.white70,
                            ),
                            const SizedBox(width: 8),
                            const Text("Fall Detection", style: TextStyle(color: Colors.white, fontSize: 16)),
                          ],
                        ),
                        Switch(
                          value: _fallDetectionEnabled,
                          onChanged: _toggleFallDetection,
                          activeColor: _Neon.lime,
                        ),
                      ],
                    ),
                  ),

                  // Fall Detected Banner
                  if (_fallDetected)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _Neon.hotRed.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _Neon.hotRed, width: 2),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: _Neon.hotRed, size: 28),
                          const SizedBox(width: 12),
                          const Expanded(child: Text("FALL DETECTED — SOS AUTO-ACTIVATED", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                        ],
                      ),
                    ),
''')
            new_lines.extend(head_lines)
            
    elif state == 1:
        head_lines.append(line)
    elif state == 2:
        theirs_lines.append(line)
    else:
        new_lines.append(line)

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print("All remaining conflicts resolved!")
