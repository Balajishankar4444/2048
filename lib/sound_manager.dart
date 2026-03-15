import 'package:audioplayers/audioplayers.dart';

class SoundManager {
  // Use ONE static player. 
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> play(String file) async {
    try {
      
      await _player.stop(); 
      await _player.play(AssetSource(file));
    } catch (e) {
      print("!!! SOUND ERROR: $e");
    }
  }

  // Update these to use the new 'play' method
  static void playSwipe() => play('swipe.mp3');
  static void playCollision() => play('collision.mp3');
  static void playBigCollision() => play('bigcollision.mp3');
}