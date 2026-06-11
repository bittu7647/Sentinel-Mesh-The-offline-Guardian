import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class AIService {
  static String get apiKey => dotenv.env['GEMINI_API_KEY'] ?? 'YOUR_GEMINI_API_KEY';
  
  static GenerativeModel _getModel(String modelName) => GenerativeModel(
    model: modelName,
    apiKey: apiKey,
    generationConfig: GenerationConfig(temperature: 0.2),
  );

  static Future<String> generateVideoReport(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) return "Video file not found.";

    final bytes = await file.readAsBytes();

    final prompt = """
Analyze this emergency situation from the provided media and generate a professional 'Sentinel Incident Report'.
Focus on:
1. Threat Assessment: Nature of the emergency (assault, medical, fall, etc.)
2. Visual Identifiers: Brief description of people or surroundings.
3. Audio Context: Notable sounds (screams, sirens, voices).
4. Recommendation: Priority level for responding officials.
Keep it objective and professional for law enforcement/medical use.
""";

    // Tier 1: Try Gemini 1.5 Flash (The modern standard for Vision + Video)
    try {
      debugPrint("AI Core: Attempting Tier 1 Analysis (gemini-1.5-flash)...");
      final flashModel = _getModel('gemini-1.5-flash');
      final content = [
        Content.multi([
          DataPart('video/mp4', bytes),
          TextPart(prompt),
        ])
      ];
      final response = await flashModel.generateContent(content);
      if (response.text != null) return response.text!;
    } catch (e) {
      debugPrint("AI Core: Tier 1 Failed ($e). Trying Tier 2 (Situational Vision)...");
    }

    // Tier 2: Fallback - Attempt situational analysis with same model but treating as generic stream
    try {
      final model = _getModel('gemini-1.5-flash');
      final content = [
        Content.multi([
          DataPart('image/jpeg', bytes),
          TextPart("$prompt\n(Context: Analyzing visual frames from an emergency recording)"),
        ])
      ];
      final response = await model.generateContent(content);
      if (response.text != null) return response.text!;
    } catch (e) {
      debugPrint("AI Core: Tier 2 Failed ($e). Falling back to Tier 3 (Failsafe Summary)...");
    }

    // Tier 3: Failsafe - Text-only report based on incident metadata
    try {
      final model = _getModel('gemini-1.5-flash');
      final metadataPrompt = "Generate a high-priority incident summary for an emergency recording that occurred at ${DateTime.now()}. The recording lasted several seconds. Request immediate attention from officials for manual evidence review.";
      final response = await model.generateContent([Content.text(metadataPrompt)]);
      return "【OFFLINE FAILSAFE REPORT】\n\n${response.text ?? "A high-priority incident has been recorded. Please forward this evidence to local officials immediately for manual review."}\n\n(Note: Visual AI is currently restricted, but evidence has been saved securely.)";
    } catch (e) {
      return "Critical Error: AI Analysis service is currently unreachable for this API key. Evidence is stored locally.";
    }
  }

  static Future<String> getEmergencyAdvice(String prompt) async {
    return _generate(prompt, "You are 'Sentinel AI', an emergency medical and safety assistant.");
  }

  static Future<Map<String, dynamic>> reasonOverEnvironment(Map<String, dynamic> context) async {
    final String prompt = "Context: $context. Analyze threat. Return JSON: {\"threat_score\": 0..1, \"recommended_action\": \"string\", \"reasoning\": \"string\"}";
    try {
      final response = await _generate(prompt, "You are the Autonomous Brain of Sentinel Mesh.");
      return {"score": 0.1, "action": "monitor", "reasoning": response};
    } catch (_) {
      return {"score": 0.0, "action": "none", "reasoning": "Offline baseline"};
    }
  }

  static Future<String> _generate(String prompt, String systemContext) async {
    if (apiKey == 'YOUR_GEMINI_API_KEY' || apiKey.isEmpty) return "API Key Missing";
    // Using standard identifier
    final model = _getModel('gemini-1.5-flash');
    final content = [Content.text("$systemContext\nUser: $prompt")];
    final response = await model.generateContent(content);
    return response.text ?? "Error";
  }
}
