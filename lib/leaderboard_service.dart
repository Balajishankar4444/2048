import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> submitScore(String username, int score) async {
    await _db.collection('leaderboard').add({
      'name': username,
      'score': score,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}