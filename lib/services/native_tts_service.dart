import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';

class NativeTtsService {
  static const MethodChannel _channel = MethodChannel('pharm_parrot/tts');
  
  Future<void> speak(String text) async {
    if (kIsWeb) {
      // Web implementation using browser's speech synthesis
      // Could be implemented later if needed
      debugPrint('[TTS Web] $text');
      return;
    }
    
    try {
      await _channel.invokeMethod('speak', {'text': text});
      debugPrint('[TTS Native] Speaking: $text');
    } on PlatformException catch (e) {
      debugPrint('[TTS Error] ${e.message}');
    } catch (e) {
      debugPrint('[TTS Error] $e');
    }
  }
  
  Future<void> beep(int frequency, int duration) async {
    if (kIsWeb) return;
    
    try {
      await _channel.invokeMethod('beep', {
        'frequency': frequency,
        'duration': duration,
      });
    } on PlatformException catch (e) {
      debugPrint('[Beep Error] ${e.message}');
    }
  }
  
  Future<void> stop() async {
    if (kIsWeb) return;
    
    try {
      await _channel.invokeMethod('stop');
    } on PlatformException catch (e) {
      debugPrint('[TTS Error] ${e.message}');
    }
  }
}
