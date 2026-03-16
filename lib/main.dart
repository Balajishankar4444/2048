import 'dart:math';
import 'dart:convert'; // Required for JSON
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart'; 
import 'sound_manager.dart';

import 'package:firebase_auth/firebase_auth.dart'; // Ensure this import is at the top

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Sign in anonymously to satisfy your new Production Rules
  try {
    final userCredential = await FirebaseAuth.instance.signInAnonymously();
    debugPrint("Signed in with UID: ${userCredential.user?.uid}");
  } catch (e) {
    debugPrint("Auth Error: $e");
  }

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => GameEngine(),
      child: const InfinityMergeApp(),
    ),
  );
}

class LeaderboardService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Get saved player name
  Future<String> getPlayerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('player_name') ?? "Player";
  }
  Future<List<Map<String, dynamic>>> getGlobalScoresFuture() async {
  final snapshot = await _db
      .collection('leaderboard')
      .orderBy('score', descending: true)
      .limit(5) // Just get the top 5 for the preview
      .get();

  return snapshot.docs.map((doc) => {
    'name': doc['name'],
    'score': doc['score'],
  }).toList();
}

  // Save player name locally
  Future<void> savePlayerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player_name', name);
  }

  // Check if name already exists
  Future<bool> isNameTaken(String name) async {
    final query = await _db
        .collection('leaderboard')
        .where('name', isEqualTo: name)
        .limit(1)
        .get();

    return query.docs.isNotEmpty;
  }

  // Update name on server
  Future<void> updateNameOnServer(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final oldName = prefs.getString('player_name');

    if (oldName == null) return;

    final query = await _db
        .collection('leaderboard')
        .where('name', isEqualTo: oldName)
        .get();

    for (var doc in query.docs) {
      await doc.reference.update({'name': newName});
    }

    await prefs.setString('player_name', newName);
  }

  // Submit score
  Future<void> submitScore(String username, int score) async {
    if (score <= 0) return;

    final query = await _db
        .collection('leaderboard')
        .where('name', isEqualTo: username)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      await _db.collection('leaderboard').add({
        'name': username,
        'score': score,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } else {
      final doc = query.docs.first;

      if (score > doc['score']) {
        await doc.reference.update({
          'score': score,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  // Get global leaderboard
  Stream<List<Map<String, dynamic>>> getGlobalScores() {
    return _db
        .collection('leaderboard')
        .orderBy('score', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {
                  'name': doc['name'],
                  'score': doc['score'],
                })
            .toList());
  }

  // Get player rank
  Future<int> getPlayerRank(int score) async {
    if (score <= 0) return 0;

    final query = await _db
        .collection('leaderboard')
        .where('score', isGreaterThan: score)
        .get();

    return query.docs.length + 1;
  }
}

class InfinityMergeApp extends StatelessWidget {
  const InfinityMergeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infinity 2048',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      ),
      home: const MainMenu(),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final LeaderboardService _service = LeaderboardService();
  
  bool _isLocked = false; 

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  void _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    String name = await _service.getPlayerName();
    setState(() {
      _nameController.text = name;
      // This checks the flag set by your initial setup popup
      _isLocked = prefs.getBool('has_set_name') ?? false;
    });
  }

  String _formatTime(int totalSeconds) {
    int hours = totalSeconds ~/ 3600;
    int minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) return "${hours}h ${minutes}m";
    return "${minutes}m ${totalSeconds % 60}s";
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<GameEngine>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Player Profile"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("DISPLAY NAME", style: TextStyle(color: Colors.white38, fontSize: 12)),
const SizedBox(height: 8),
TextField(
  controller: _nameController,
  enabled: false, // LOCKS THE FIELD
  style: const TextStyle(color: Colors.white70),
  decoration: InputDecoration(
    filled: true,
    fillColor: Colors.white.withOpacity(0.05),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    suffixIcon: const Icon(Icons.lock_outline, color: Colors.white24, size: 18),
  ),
),
const Padding(
  padding: EdgeInsets.only(top: 8.0, left: 4.0),
  child: Text(
    "Username cannot be changed.",
    style: TextStyle(color: Colors.white24, fontSize: 11, fontStyle: FontStyle.italic),
  ),
),
            const SizedBox(height: 40),
            // Find this section inside your build method:
const Text("PERSONAL STATS", style: TextStyle(color: Colors.white38, fontSize: 12)),
const SizedBox(height: 16),

// REPLACE/UPDATE THESE ROWS:
// Inside _ProfileScreenState in main.dart

_statsRow("All-Time Best", "${engine.bestScore}"),
_statsRow("Highest Tile", "${engine.highestTileReached}"),
_statsRow("Time Played", _formatTime(engine.totalSecondsPlayed)),
// This will now show the highest level saved in the engine
_statsRow("All-Time Level", "${engine.level}"),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white10, // Neutral color
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("CLOSE", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),    
          ],
        ),
      ),
    );
  }

  Widget _statsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(value, style: TextStyle(color: Provider.of<GameEngine>(context).themeColor, fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
    );
  }
}

// --- MODELS ---

class Tile {
  final String id;
  final int x;
  final int y;
  final int value;
  final bool isNew;
  final bool isMerged;
  final bool isDeleting;

  Tile({
    required this.id,
    required this.x,
    required this.y,
    required this.value,
    this.isNew = true,
    this.isMerged = false,
    this.isDeleting = false,
  });

  // --- ADDED FOR RESUME FUNCTIONALITY ---
  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'value': value,
      };

  factory Tile.fromJson(Map<String, dynamic> json) => Tile(
        id: json['id'],
        x: json['x'],
        y: json['y'],
        value: json['value'],
        isNew: false, // Don't animate old tiles on load
      );
  // ---------------------------------------

  Tile copyWith({int? x, int? y, int? value, bool? isNew, bool? isMerged, bool? isDeleting, String? id}) {
    return Tile(
      id: id ?? this.id,
      x: x ?? this.x,
      y: y ?? this.y,
      value: value ?? this.value,
      isNew: isNew ?? this.isNew,
      isMerged: isMerged ?? this.isMerged,
      isDeleting: isDeleting ?? this.isDeleting,
    );
  }
}

enum Direction { up, down, left, right }
enum GameMode {
  classic,
  timeAttack,
  survival,
  grid6x6,
}

// --- GAME ENGINE ---

class GameEngine extends ChangeNotifier {
  List<Tile> tiles = [];
  List<List<Tile>> history = [];
  int score = 0;
  final Map<GameMode, int> _bestScores = {
    GameMode.classic: 0,
    GameMode.timeAttack: 0,
    GameMode.survival: 0,
    GameMode.grid6x6: 0,
  };

  int get bestScore => _bestScores[mode] ?? 0;
  int level = 1;
  int combo = 0;
  bool gameOver = false;
  bool hasWon = false;
  int gridSize = 4;
  final _uuid = const Uuid();
  int survivalMoves = 0;
  int undosAvailable = 1;
  int shufflesAvailable = 1;
  int blastsAvailable = 1;
  bool _hasSavedGame = false;
  bool get hasSavedGame => _hasSavedGame;
  GameMode mode = GameMode.classic;
  int timeRemaining = 60;
  int survivalSeconds = 0;
  Timer? modeTimer;
  int totalSecondsPlayed = 0;
  int highestTileReached = 0;
  Timer? _playtimeTimer;

  Color _themeColor = const Color(0xFFBB86FC);
  Color get themeColor => _themeColor;

  List<List<int>> grid = List.generate(4, (_) => List.filled(4, 0));
  bool isGameOver = false;
  bool isGameWon = false;

  GameEngine() {
    _loadData();
    _loadTheme();
    initGame();
  }

  void initGame() {
    grid = List.generate(4, (_) => List.filled(4, 0));
    score = 0;
    isGameOver = false;
    isGameWon = false;
    addNewTile();
    addNewTile();
    notifyListeners();
  }

  void addNewTile() {
    List<int> emptyCells = [];
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        if (grid[i][j] == 0) emptyCells.add(i * 4 + j);
      }
    }
    if (emptyCells.isNotEmpty) {
      int randomCell = emptyCells[Random().nextInt(emptyCells.length)];
      grid[randomCell ~/ 4][randomCell % 4] = Random().nextInt(10) == 0 ? 4 : 2;
    }
  }

  void moveTiles(Direction direction) {
  if (isGameOver || isGameWon) return;

  List<List<int>> newGrid = List.generate(4, (i) => List.from(grid[i]));
  bool moved = false;
  int mergesInThisMove = 0;

  void move(int r1, int c1, int r2, int c2) {
    if (newGrid[r1][c1] != 0 && newGrid[r1][c1] == newGrid[r2][c2]) {
      newGrid[r2][c2] *= 2;
      newGrid[r1][c1] = 0;
      score += newGrid[r2][c2];
      moved = true;
      mergesInThisMove++;
    } 
    else if (newGrid[r1][c1] != 0 && newGrid[r2][c2] == 0) {
      newGrid[r2][c2] = newGrid[r1][c1];
      newGrid[r1][c1] = 0;
      moved = true;
    }
  }

  switch (direction) {
    case Direction.up:
      for (int j = 0; j < 4; j++) {
        for (int i = 1; i < 4; i++) {
          for (int k = i; k > 0; k--) move(k, j, k - 1, j);
        }
      }
      break;

    case Direction.down:
      for (int j = 0; j < 4; j++) {
        for (int i = 2; i >= 0; i--) {
          for (int k = i; k < 3; k++) move(k, j, k + 1, j);
        }
      }
      break;

    case Direction.left:
      for (int i = 0; i < 4; i++) {
        for (int j = 1; j < 4; j++) {
          for (int k = j; k > 0; k--) move(i, k, i, k - 1);
        }
      }
      break;

    case Direction.right:
      for (int i = 0; i < 4; i++) {
        for (int j = 2; j >= 0; j--) {
          for (int k = j; k < 3; k++) move(i, k, i, k + 1);
        }
      }
      break;
  }

  if (moved) {
    print("Move detected");
    if (mergesInThisMove >= 3) {
      SoundManager.playBigCollision();
    } 
    else if (mergesInThisMove > 0) {
      SoundManager.playCollision();
    } 
    else {
      SoundManager.playSwipe();
    }

    grid = newGrid;
    addNewTile();
    checkGameState();

    if (score > bestScore) {
      _bestScores[mode] = score;
    }

    notifyListeners();
  }
}

  void checkGameState() {
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        if (grid[i][j] == 2048) {
          isGameWon = true;
          return;
        }
      }
    }

    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        if (grid[i][j] == 0) return;
        if (i < 3 && grid[i][j] == grid[i + 1][j]) return;
        if (j < 3 && grid[i][j] == grid[i][j + 1]) return;
      }
    }
    isGameOver = true;
  }

  Future<void> _loadTheme() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    int? colorValue = prefs.getInt('theme_color');
    if (colorValue != null) {
      _themeColor = Color(colorValue);
      notifyListeners();
    }
  }

  Future<void> updateTheme(Color newColor) async {
    _themeColor = newColor;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color', newColor.value);
    notifyListeners();
  }

// Start tracking when the game screen opens
void startPlaytimeTracking() {
  _playtimeTimer?.cancel();
  _playtimeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    totalSecondsPlayed++;
    if (totalSecondsPlayed % 10 == 0) _saveData(); // Save every 10 seconds
    notifyListeners();
  });
}

void stopPlaytimeTracking() {
  _playtimeTimer?.cancel();
}

// Add this logic inside your move() function after tiles are merged:
void _updateHighestTile() {
  bool changed = false;
  for (var tile in tiles) {
    if (tile.value > highestTileReached) {
      highestTileReached = tile.value;
      changed = true; // Track if a new record was actually hit
    }
  }
  if (changed) notifyListeners(); // <--- ADD THIS to update the Profile UI
}

  void newGame() {
  tiles = [];
  history = [];
  score = 0;
  combo = 0;
  gameOver = false;
  hasWon = false;

  survivalMoves = 0;
  survivalSeconds = 0;

  undosAvailable = 1;
  shufflesAvailable = 1;
  blastsAvailable = 1;

  modeTimer?.cancel();

  if (mode == GameMode.timeAttack) {
    timeRemaining = 300;

    modeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (gameOver) {
        _handleGameEnd();
        timer.cancel();
        return;
      }

      timeRemaining--;

      if (timeRemaining <= 0) {
        gameOver = true;
        timer.cancel();
      }

      notifyListeners();
    });
  }

  addRandomTile();
  addRandomTile();

  _saveData();
  notifyListeners();
}

  void addRandomTile() {
    List<Point<int>> emptySpots = [];
    for (int x = 0; x < gridSize; x++) {
      for (int y = 0; y < gridSize; y++) {
        if (!tiles.any((t) => t.x == x && t.y == y)) emptySpots.add(Point(x, y));
      }
    }
    if (emptySpots.isNotEmpty) {
      final spot = emptySpots[Random().nextInt(emptySpots.length)];
      int val = Random().nextInt(10) == 0 ? 4 : 2;
      tiles.add(Tile(id: _uuid.v4(), x: spot.x, y: spot.y, value: val));
    }
  }

void undoMove() {
  // If we are in Time Attack and the game is already over (time hit 0), stop.
  if (mode == GameMode.timeAttack && gameOver) return;

  if (history.isNotEmpty && undosAvailable > 0) {
    tiles = List.from(history.removeLast());
    undosAvailable--;
    combo = 0;
    gameOver = false; 
    _saveData();
    notifyListeners();
    HapticFeedback.lightImpact();
  }
}

void shuffleBoard() {
  if (mode == GameMode.timeAttack && gameOver) return;
  if (shufflesAvailable <= 0 || tiles.isEmpty) return;

  List<Point<int>> emptySpots = [];

  for (int x = 0; x < gridSize; x++) {
    for (int y = 0; y < gridSize; y++) {
      emptySpots.add(Point(x, y));
    }
  }

  emptySpots.shuffle();

  List<Tile> shuffledTiles = [];

  for (int i = 0; i < tiles.length; i++) {
    shuffledTiles.add(Tile(
      id: _uuid.v4(),
      x: emptySpots[i].x,
      y: emptySpots[i].y,
      value: tiles[i].value,
      isNew: false,
    ));
  }

  tiles = shuffledTiles;

  shufflesAvailable--;
  gameOver = false;

  _saveData();
  HapticFeedback.mediumImpact();
  notifyListeners();
}

void blastTile(String id) {
  if (mode == GameMode.timeAttack && gameOver) return;

  if (blastsAvailable <= 0) return;
  tiles.removeWhere((t) => t.id == id);
  blastsAvailable--;
  gameOver = false; 
  _saveData();
  HapticFeedback.heavyImpact();
  notifyListeners();
}
  void startMode(GameMode selectedMode) {
  mode = selectedMode;

  if (mode == GameMode.grid6x6) {
    gridSize = 6;
  } else {
    gridSize = 4;
  }

  if (mode == GameMode.timeAttack) {
    timeRemaining = 300;

    modeTimer?.cancel();
    modeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (gameOver) {
        _handleGameEnd();
        timer.cancel();
        return;
      }

      timeRemaining--;

      if (timeRemaining <= 0) {
        gameOver = true;
        timer.cancel();
      }

      notifyListeners();
    });
  }

  if (mode == GameMode.survival) {
    survivalMoves = 0;
  }

  newGame();
}
bool isSoundEnabled = true; // Default to true

  // --- Add a toggle method ---
  void toggleSound() async {
    isSoundEnabled = !isSoundEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_sound_enabled', isSoundEnabled);
    notifyListeners();
  }

  Future<void> move(Direction dir) async {
    if (gameOver) return;

    List<Tile> currentSnapshot = tiles.map((t) => t.copyWith()).toList();
    bool moved = false;
    bool anyMerged = false;
    List<Tile> nextTiles = [];
    List<String> mergedIds = [];
    int actualMergeCount = 0;

    List<Tile> sorted = List.from(tiles.where((t) => !t.isDeleting));
    if (dir == Direction.right) sorted.sort((a, b) => b.x.compareTo(a.x));
    if (dir == Direction.left) sorted.sort((a, b) => a.x.compareTo(b.x));
    if (dir == Direction.down) sorted.sort((a, b) => b.y.compareTo(a.y));
    if (dir == Direction.up) sorted.sort((a, b) => a.y.compareTo(b.y));

    for (var tile in sorted) {
      int curX = tile.x;
      int curY = tile.y;
      Tile? collisionTarget;

      while (true) {
        int nextX = curX + (dir == Direction.right ? 1 : dir == Direction.left ? -1 : 0);
        int nextY = curY + (dir == Direction.down ? 1 : dir == Direction.up ? -1 : 0);

        if (nextX < 0 || nextX >= gridSize || nextY < 0 || nextY >= gridSize) break;

        var target = nextTiles.firstWhere(
          (t) => t.x == nextX && t.y == nextY && !t.isDeleting,
          orElse: () => Tile(id: 'none', x: -1, y: -1, value: -1),
        );

        if (target.id == 'none') {
          curX = nextX;
          curY = nextY;
          moved = true;
        } else if (target.value == tile.value && !mergedIds.contains(target.id)) {
          collisionTarget = target;
          curX = nextX;
          curY = nextY;
          moved = true;
          break;
        } else {
          break;
        }
      }

      if (collisionTarget != null) {
        int idx = nextTiles.indexWhere((t) => t.id == collisionTarget!.id);
        nextTiles[idx] = nextTiles[idx].copyWith(isMerged: true);
        mergedIds.add(collisionTarget.id);

        anyMerged = true;
        actualMergeCount++; // <--- INCREMENT whenever a merge occurs
        
        int points = collisionTarget.value * 2;
        score += points + (combo * 15);

        nextTiles.add(tile.copyWith(x: curX, y: curY, isDeleting: true, isNew: false));
      } else {
        nextTiles.add(tile.copyWith(x: curX, y: curY, isNew: false));
      }
    }

    if (moved) {
      if (isSoundEnabled) {
    if (actualMergeCount >= 2) {
      SoundManager.playBigCollision();
    } else if (anyMerged) {
      SoundManager.playCollision();
    } else {
      SoundManager.playSwipe();
    }
  }

  if (mode == GameMode.survival) {
    survivalMoves++;
  }
      if (anyMerged) {
        combo++;
      } else {
        combo = 0;
      }

      history.add(currentSnapshot);
      if (history.length > 5) history.removeAt(0);

      tiles = nextTiles;
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 150));

      tiles = tiles.map((t) {
        if (t.isMerged) {
          int newVal = t.value * 2;
          if (newVal == 2048 && !hasWon) hasWon = true;
          return t.copyWith(value: newVal, isMerged: false);
        }
        return t;
      }).where((t) => !t.isDeleting).toList();
      _updateHighestTile();
      addRandomTile();
      _updateLevel();
      _checkGameOver();
      _saveData();

      if (anyMerged) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.selectionClick();
      }

      notifyListeners();
    }
  }

  // Inside GameEngine class
void _updateLevel() {
  // 1. Calculate the potential level based on score
  int calculatedLevel = (score / 2000).floor() + 1; 
  
  // 2. Only update if the calculated level is HIGHER than the current saved level
  if (calculatedLevel > level) {
    level = calculatedLevel;
    _saveData(); 
    notifyListeners(); 
  }
}
  

  void _checkGameOver() async {
    if (tiles.length < gridSize * gridSize) return;
    for (var tile in tiles) {
      for (var dir in Direction.values) {
        int nx = tile.x + (dir == Direction.right ? 1 : dir == Direction.left ? -1 : 0);
        int ny = tile.y + (dir == Direction.down ? 1 : dir == Direction.up ? -1 : 0);
        if (nx >= 0 && nx < gridSize && ny >= 0 && ny < gridSize) {
          if (tiles.any((t) => t.x == nx && t.y == ny && t.value == tile.value)) return;
        }
      }
    }
    
    // Once game is officially over:
    gameOver = true;
  if (mode == GameMode.classic) {
    final service = LeaderboardService();
    String playerName = await service.getPlayerName(); 
    service.submitScore(playerName, score); 
    if (score > (_bestScores[GameMode.classic] ?? 0)) {
      _bestScores[GameMode.classic] = score;
    }
  }
    
    _saveData();
    notifyListeners();
  }

  void _handleGameEnd() {
  final service = LeaderboardService();
  // In a real app, you'd get the username from a profile setting
  service.submitScore("Anonymous Player", score); 
}

  // --- UPDATED LOAD/SAVE FOR RESUME LOGIC ---
  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    score = prefs.getInt('current_score') ?? 0;
  level = prefs.getInt('current_level') ?? 1;
  totalSecondsPlayed = prefs.getInt('total_playtime') ?? 0;
  highestTileReached = prefs.getInt('highest_tile') ?? 0;
  
  // Load best scores for every mode individually
  for (var m in GameMode.values) {
    _bestScores[m] = prefs.getInt('best_score_${m.name}') ?? 0;
  }

    String? savedTiles = prefs.getString('saved_tiles');
    if (savedTiles != null) {
      List<dynamic> decoded = jsonDecode(savedTiles);
      tiles = decoded.map((json) => Tile.fromJson(json)).toList();
      score = prefs.getInt('current_score') ?? 0;
      level = prefs.getInt('current_level') ?? 1;
      undosAvailable = prefs.getInt('undos') ?? 1;
      shufflesAvailable = prefs.getInt('shuffles') ?? 1;
      blastsAvailable = prefs.getInt('blasts') ?? 1;
      _hasSavedGame = tiles.isNotEmpty;
    } else {
      newGame();
    }
    notifyListeners();
  }
Future<void> _saveData() async {
  
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('current_level', level);
  await prefs.setInt('total_playtime', totalSecondsPlayed);
await prefs.setInt('highest_tile', highestTileReached);

  // 1. Update mode-specific high score
  if (mode == GameMode.classic && score > bestScore) {
    _bestScores[GameMode.classic] = score;
    await prefs.setInt('best_score_classic', score);
  }
  
  // 2. Save current game state
  await prefs.setInt('current_score', score);
  await prefs.setInt('current_level', level);
  await prefs.setInt('undos', undosAvailable);
  await prefs.setInt('shuffles', shufflesAvailable);
  await prefs.setInt('blasts', blastsAvailable);

  String encoded = jsonEncode(tiles.map((t) => t.toJson()).toList());
  await prefs.setString('saved_tiles', encoded);
  _hasSavedGame = true;
}
}

class UsernameSetupDialog extends StatefulWidget {
  const UsernameSetupDialog({super.key});

  @override
  State<UsernameSetupDialog> createState() => _UsernameSetupDialogState();
}

class _UsernameSetupDialogState extends State<UsernameSetupDialog> {
  final TextEditingController _controller = TextEditingController();
  final LeaderboardService _service = LeaderboardService();
  String? _error;
  bool _loading = false;

  void _submit() async {
    String name = _controller.text.trim();
    if (name.length < 3) {
      setState(() => _error = "Name too short");
      return;
    }

    setState(() => _loading = true);
    bool taken = await _service.isNameTaken(name);

    if (taken) {
      setState(() {
        _error = "Name already taken!";
        _loading = false;
      });
    } else {
      // Save locally and on server
      // 1. Save name
await _service.savePlayerName(name);
await _service.updateNameOnServer(name);

// 2. Set the flag so popup never shows again
final prefs = await SharedPreferences.getInstance();
await prefs.setBool('has_set_name', true);

// 3. REFRESH THE APP
if (mounted) {
  // This tells the Consumer in Step 3 to rebuild with the new name
  Provider.of<GameEngine>(context, listen: false).notifyListeners();
  Navigator.pop(context);
}
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Prevent back button
      child: AlertDialog(
        title: const Text("Welcome! Enter your name"),
        content: TextField(
          controller: _controller,
          decoration: InputDecoration(errorText: _error, hintText: "Username"),
        ),
        actions: [
          _loading 
            ? const CircularProgressIndicator() 
            : ElevatedButton(onPressed: _submit, child: const Text("START PLAYING")),
        ],
      ),
    );
  }
}
// --- HOME SCREEN (MAIN MENU) ---

class MainMenu extends StatefulWidget {
  const MainMenu({super.key});

  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  // Correctly declared variables at class level
  Future<int>? _rankFuture;
  Future<List<Map<String, dynamic>>>? _leaderboardFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshLeaderboardData(force: true); 
      _checkFirstTimeUser();
    });
  }

  // Proper function definition (not inside another function)
  // Inside _MainMenuState in main.dart
void _refreshLeaderboardData({bool force = false}) {
  final engine = Provider.of<GameEngine>(context, listen: false);
  final service = LeaderboardService();
  
  // Explicitly pull the Classic mode score
  int classicBest = engine._bestScores[GameMode.classic] ?? 0;

  if (force || _rankFuture == null) {
    setState(() {
      // Always calculate rank based on Classic Best
      if (classicBest > 0) {
        _rankFuture = service.getPlayerRank(classicBest); 
      }
      _leaderboardFuture = service.getGlobalScoresFuture();
    });
  }
}

  Future<void> _checkFirstTimeUser() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    bool hasSetName = prefs.getBool('has_set_name') ?? false;

    if (!hasSetName && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const UsernameSetupDialog(),
      ).then((_) => _refreshLeaderboardData(force: true));
    }
  }

  void _showSettingsDialog() {
  showDialog(
    context: context,
    builder: (context) {
      // Using Consumer ensures the dialog UI updates immediately when settings change
      return Consumer<GameEngine>(
        builder: (context, engine, child) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text("Settings", style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min, // Fixes height issue
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Select Theme Color", style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _colorCircle(engine, const Color(0xFFBB86FC)),
                    _colorCircle(engine, const Color(0xFF03DAC6)),
                    _colorCircle(engine, const Color(0xFFFFB300)),
                  ],
                ),
                
                const SizedBox(height: 25),
                const Divider(color: Colors.white10),
                const SizedBox(height: 10),
                
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: ListTile(
                    leading: Icon(
                      engine.isSoundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      color: engine.isSoundEnabled ? engine.themeColor : Colors.grey,
                    ),
                    title: const Text(
                      "Sound Effects",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    trailing: Switch(
                      value: engine.isSoundEnabled,
                      activeColor: engine.themeColor, // Matches your selected theme!
                      onChanged: (bool value) {
                        engine.toggleSound();
                      },
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Close", style: TextStyle(color: engine.themeColor)),
              ),
            ],
          );
        },
      );
    },
  );
}

  Widget _colorCircle(GameEngine engine, Color color) {
    bool isSelected = engine.themeColor.value == color.value;
    return GestureDetector(
      onTap: () => engine.updateTheme(color),
      child: Container(
        width: 45, height: 45,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
        ),
        child: isSelected ? const Icon(Icons.check, color: Colors.black) : null,
      ),
    );
  }

// Update your refresh function to include the leaderboard
void _performSingleRefresh() {
  final engine = Provider.of<GameEngine>(context, listen: false);
  final service = LeaderboardService();
  
  setState(() {
    // Refresh Rank
    if (engine.bestScore > 0) {
      _rankFuture = service.getPlayerRank(engine.bestScore);
    }
    // Refresh Leaderboard Preview
    _leaderboardFuture = service.getGlobalScoresFuture();
  });
}

  void _manualRefresh(int score) {
  setState(() {
    _rankFuture = LeaderboardService().getPlayerRank(score);
  });
}

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<GameEngine>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.transparent,
            expandedHeight: 100,
            floating: true,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Infinity Merge 2048",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: Colors.white,
                  ),
                ),
                Text(
                  "Merge tiles. Beat the world.",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.white38,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor: engine.themeColor,
                  child: Icon(Icons.person, size: 18, color: Colors.black),
                ),
              ),
              IconButton(
                onPressed: (){ _showSettingsDialog(); },
                icon: Icon(Icons.settings_outlined, color: engine.themeColor),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  _buildStatsCard(engine),
                  const SizedBox(height: 40),
                  _buildMainPlayButton(context, engine),
                  const SizedBox(height: 40),
                  _buildSectionHeader("Game Modes"),
                  _buildGameModes(context),
                  const SizedBox(height: 30),
                  _buildSectionHeader("Leaderboard Preview"),
                  _buildLeaderboardPreview(context),
                  const SizedBox(height: 30),
                  _buildSectionHeader("Daily Rewards"),
                  _buildRewardsSection(),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- AFTER ---
Widget _buildStatsCard(GameEngine engine) {
  int classicBest = engine._bestScores[GameMode.classic] ?? 0;

  return Container(
    // ... your existing decoration ...
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _statItem("Best (Classic)", "$classicBest", engine.themeColor),
        
        GestureDetector(
          // SCENARIO C: Manual Reload Button
          onTap: () => _performSingleRefresh(), 
          child: FutureBuilder<int>(
            future: _rankFuture,
            builder: (context, snapshot) {
              final bool isLoading = snapshot.connectionState == ConnectionState.waiting;
              
              String rankText = "---";
              if (snapshot.hasData && snapshot.data! > 0) {
                rankText = "#${snapshot.data}";
              } else if (isLoading) {
                rankText = "...";
              }

              return Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Rank ", style: TextStyle(color: Colors.white38, fontSize: 12)),
                      Icon(
                        Icons.refresh, 
                        size: 12, 
                        color: isLoading ? engine.themeColor : Colors.white38
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rankText,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: engine.themeColor,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        _statItem("Level", "${engine.level}", engine.themeColor),
      ],
    ),
  );
}

// Helper to make the mode name look nice (e.g., "timeAttack" -> "Time Attack")
String _getModeName(GameMode mode) {
  switch (mode) {
    case GameMode.classic: return "Classic";
    case GameMode.timeAttack: return "Time Attack";
    case GameMode.survival: return "Survival";
    case GameMode.grid6x6: return "6x6";
  }
}

  // Inside _MainMenuState
Widget _statItem(String label, String value, Color themeColor) { // Add themeColor parameter
  return Column(
    children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      const SizedBox(height: 5),
      Text(
        value, 
        style: TextStyle( // Removed 'const'
          fontWeight: FontWeight.bold, 
          fontSize: 16, 
          color: themeColor // Use the passed parameter
        )
      ),
    ],
  );
}

  // --- UPDATED PLAY BUTTONS (RESUME & NEW GAME) ---
  Widget _buildMainPlayButton(BuildContext context, GameEngine engine) {
  return Column(
    children: [
      if (engine.hasSavedGame) ...[
        _customMenuButton(
          context,
          "RESUME GAME",
          engine.themeColor,
          Colors.black,
          () async {
            // 1. Wait for user to finish playing
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const GameScreen()));
            
            // 2. This runs AFTER the GameScreen is popped
            if (mounted) {
              _performSingleRefresh(); // Forces rank and leaderboard reload
              Provider.of<GameEngine>(context, listen: false)._loadData();
            }
          },
        ),
        const SizedBox(height: 16),
      ],
      _customMenuButton(
        context,
        "NEW GAME",
        engine.hasSavedGame ? Colors.white.withOpacity(0.05) : engine.themeColor,
        engine.hasSavedGame ? Colors.white : Colors.black,
        () async {
          engine.newGame();
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const GameScreen()));
          
          // Refresh after returning from a New Game too
          if (mounted) {
            _performSingleRefresh();
          }
        },
      ),
    ],
  );
}

  Widget _customMenuButton(BuildContext context, String text, Color bg, Color textColor, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 70,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: bg == Provider.of<GameEngine>(context).themeColor? 8 : 0,
        ),
        onPressed: onPressed,
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1.5),
        ),
      ),
    );
  }

  Widget _buildGameModes(BuildContext context) {
  return SizedBox(
    height: 110,
    child: Row(
      children: [
        Expanded(child: _modeCard("Classic", Icons.grid_4x4, Colors.blueAccent, GameMode.classic, context)),
        Expanded(child: _modeCard("Time Attack", Icons.timer_outlined, Colors.orangeAccent, GameMode.timeAttack, context)),
        Expanded(child: _modeCard("Survival", Icons.favorite_border, Colors.redAccent, GameMode.survival, context)),
        Expanded(child: _modeCard("6x6 Grid", Icons.grid_on_outlined, Colors.greenAccent, GameMode.grid6x6, context)),
      ],
    ),
  );
}

  Widget _modeCard(
  String title,
  IconData icon,
  Color color,
  GameMode mode,
  BuildContext context,
) {
  return GestureDetector(
    onTap: () {
      final engine = context.read<GameEngine>();

      engine.startMode(mode);

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GameScreen()),
      );
    },
    child: Container(
      width: 110,
      margin: const EdgeInsets.only(right: 15),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildLeaderboardPreview(BuildContext context) {
  return FutureBuilder<List<Map<String, dynamic>>>(
    future: _leaderboardFuture, // Uses the stable future we created
    builder: (context, snapshot) {
      // Change this part of _buildLeaderboardPreview:
if (snapshot.connectionState == ConnectionState.waiting && _leaderboardFuture != null) {
  final engine = Provider.of<GameEngine>(context); // Define engine
  return Center( // Removed 'const'
    child: Padding(
      padding: const EdgeInsets.all(20.0),
      child: CircularProgressIndicator(color: engine.themeColor), // Use engine.themeColor
    ),
  );
}

      if (snapshot.hasError || !snapshot.hasData) {
        return const Center(child: Text("Unable to load scores", style: TextStyle(color: Colors.white24)));
      }

      final worldScores = snapshot.data!;

      return Consumer<GameEngine>(
        builder: (context, engine, child) {
          return FutureBuilder<String>(
            future: LeaderboardService().getPlayerName(),
            builder: (context, nameSnapshot) {
              final currentPlayerName = nameSnapshot.data ?? "Player";

              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    // Top 5 Scores
                    for (int i = 0; i < worldScores.length; i++)
                      _leaderRow(
                        (i + 1).toString(),
                        worldScores[i]['name'],
                        worldScores[i]['score'].toString(),
                        isCurrentPlayer: worldScores[i]['name'] == currentPlayerName,
                      ),
                    
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Divider(color: Colors.white10, thickness: 1),
                    ),

                    // Your Score
                    _leaderRow(
                      "YOU",
                      currentPlayerName,
                      // Force it to show Classic Best, not engine.bestScore (which follows the current mode)
                      (engine._bestScores[GameMode.classic] ?? 0).toString(),
                      isCurrentPlayer: true,
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );
}

  Widget _leaderRow(String rank, String name, String score, {bool isCurrentPlayer = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Container(
          width: 30,
          child: Text(
            rank, 
            style: TextStyle(
              color: isCurrentPlayer ? Provider.of<GameEngine>(context).themeColor : Colors.white38, 
              fontWeight: FontWeight.bold,
              fontSize: 12,
            )
          ),
        ),
        Expanded(
          child: Text(
            name, 
            style: TextStyle(
              color: isCurrentPlayer ? Colors.white : Colors.white70,
              fontWeight: isCurrentPlayer ? FontWeight.bold : FontWeight.normal,
            )
          )
        ),
        Text(
          score, 
          style: TextStyle(
            color: isCurrentPlayer ? Provider.of<GameEngine>(context).themeColor : Colors.white,
            fontWeight: FontWeight.bold
          )
        ),
      ],
    ),
  );
}

  Widget _buildRewardsSection() {
  // Add this line to define engine in this scope
  final engine = Provider.of<GameEngine>(context); 

  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      // Use engine.themeColor instead of the hardcoded purple
      gradient: LinearGradient(
        colors: [engine.themeColor.withOpacity(0.2), Colors.transparent]
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white10),
    ),
    child: Row( // REMOVED 'const' from here
      children: [
        // Use engine.themeColor here
        Icon(Icons.play_circle_fill, color: engine.themeColor, size: 40), 
        const SizedBox(width: 15),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Unlock Power-ups", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("Watch a short ad to get a free UNDO", style: TextStyle(fontSize: 11, color: Colors.white38)),
            ],
          ),
        ),
        const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white24),
      ],
    ),
  );
}

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }
}

// --- GAME SCREEN UI ---

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  Offset? _dragStart;
  bool isBlastActive = false;

  void _handleSwipe(DragUpdateDetails d, GameEngine engine) {
    if (_dragStart == null || isBlastActive) return;
    final dx = d.localPosition.dx - _dragStart!.dx;
    final dy = d.localPosition.dy - _dragStart!.dy;
    if (dx.abs() > 30 || dy.abs() > 30) {
      if (dx.abs() > dy.abs()) {
        engine.move(dx > 0 ? Direction.right : Direction.left);
      } else {
        engine.move(dy > 0 ? Direction.down : Direction.up);
      }
      _dragStart = null;
    }
  }

  @override
  @override
  void initState() {
    super.initState();
    // This is the correct home for these triggers!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameEngine>().startPlaytimeTracking();
    });
  }

@override
void dispose() {
  // We use Provider.of with listen: false because it is more stable in dispose
  try {
    Provider.of<GameEngine>(context, listen: false).stopPlaytimeTracking();
  } catch (e) {
    // If the context is already deactivated, we catch the error to prevent a crash
    debugPrint("Safe dispose: GameEngine tracking stopped or context was lost.");
  }
  super.dispose();
}
  @override
  Widget build(BuildContext context) {
    final engine = context.watch<GameEngine>();
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _dragStart = d.localPosition,
        onPanUpdate: (d) => _handleSwipe(d, engine),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(engine),
              _buildProgressBar(engine),
              _buildComboDisplay(engine),
              Expanded(child: _buildBoardArea(engine)),
              if (engine.mode != GameMode.survival)
  _buildPowerUps(engine),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildHeader(GameEngine engine) => Padding(
  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
  child: Column(
    children: [

      if (engine.mode == GameMode.timeAttack)
        Text(
          "⏱ ${engine.timeRemaining}s",
          style: const TextStyle(color: Colors.orange),
        ),

      if (engine.mode == GameMode.survival)
  Text(
    "👣 ${engine.survivalMoves} moves",
    style: const TextStyle(color: Colors.red),
  ),

      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _statBox("SCORE", engine.score),
          IconButton(
            icon: const Icon(Icons.home_rounded, color: Colors.white38),
            onPressed: () => Navigator.pop(context),
          ),
          _statBox("BEST", engine.bestScore,
              color: engine.themeColor),
        ],
      ),
    ],
  ),
);

  Widget _statBox(String label, int val, {Color color = Colors.white}) => Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
          Text("$val", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        ],
      );

  Widget _buildProgressBar(GameEngine engine) {
    double progress = (engine.score % 2000) / 2000;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("LEVEL ${engine.level}", style: TextStyle(color: engine.themeColor, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: progress, backgroundColor: Colors.white12, color: engine.themeColor, minHeight: 6),
        ],
      ),
    );
  }

  Widget _buildComboDisplay(GameEngine engine) {
    return Container(
      height: 50,
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => ScaleTransition(scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut), child: FadeTransition(opacity: animation, child: child)),
        child: engine.combo > 1
            ? Text("COMBO X${engine.combo}", key: ValueKey('combo_${engine.combo}'), style: GoogleFonts.poppins(color: Colors.orangeAccent, fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: 2, shadows: [Shadow(color: Colors.orange.withOpacity(0.5), blurRadius: 10)]))
            : const SizedBox.shrink(key: ValueKey('no_combo')),
      ),
    );
  }

  Widget _buildBoardArea(GameEngine engine) => LayoutBuilder(builder: (context, constraints) {
      double size = min(constraints.maxWidth, constraints.maxHeight) * 0.92;
      return Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            GameBoard(
                size: size,
                isBlastMode: isBlastActive,
                onTileTap: (id) {
                  engine.blastTile(id);
                  setState(() => isBlastActive = false);
                }),
            // The overlay only appears if gameOver is true
            if (engine.gameOver) 
              _overlay(size, "GAME OVER", engine.newGame, "RETRY"),
            
            // ... rest of your stack (2048 win, Blast text, etc)
          ],
        ),
      );
    });

  Widget _overlay(double size, String text, VoidCallback onBtn, String btnText, {Color color = Colors.black87}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(text, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black), onPressed: onBtn, child: Text(btnText)),
        ]),
      );

  Widget _buildPowerUps(GameEngine engine) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _powerBtn(Icons.undo, "UNDO", engine.undosAvailable, engine.undoMove),
          _powerBtn(Icons.shuffle, "SHUFFLE", engine.shufflesAvailable, engine.shuffleBoard),
          _powerBtn(Icons.auto_fix_high, "BLAST", engine.blastsAvailable, () => setState(() => isBlastActive = !isBlastActive), active: isBlastActive),
        ],
      ),
    );

  Widget _powerBtn(IconData icon, String label, int count, VoidCallback onTap, {bool active = false}) {
    bool canUse = count > 0;
    return GestureDetector(
      onTap: canUse ? onTap : null,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(shape: BoxShape.circle, color: active ? Colors.red : (canUse ? Colors.white10 : Colors.black26), border: Border.all(color: active ? Colors.white : Colors.transparent, width: 2)),
          child: Icon(icon, color: canUse ? Colors.white : Colors.white10, size: 28),
        ),
        const SizedBox(height: 4),
        Text("$label ($count)", style: TextStyle(fontSize: 10, color: canUse ? Colors.white70 : Colors.white12)),
      ]),
    );
  }
}

// --- BOARD & TILES ---

class GameBoard extends StatelessWidget {
  final double size;
  final bool isBlastMode;
  final Function(String) onTileTap;
  const GameBoard({super.key, required this.size, required this.isBlastMode, required this.onTileTap});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<GameEngine>();
    double spacing = 10.0;
    double tileSize = (size - (spacing * (engine.gridSize + 1))) / engine.gridSize;
    final renderList = List<Tile>.from(engine.tiles)..sort((a, b) => a.isDeleting ? 1 : -1);

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(spacing),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20, offset: Offset(0, 10))]),
      child: Stack(
        children: [
          for (int i = 0; i < engine.gridSize * engine.gridSize; i++)
            Positioned(
              left: (i % engine.gridSize) * (tileSize + spacing),
top: (i ~/ engine.gridSize) * (tileSize + spacing),
              child: Container(width: tileSize, height: tileSize, decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(8))),
            ),
          ...renderList.map((t) => AnimatedTile(key: ValueKey(t.id), tile: t, size: tileSize, spacing: spacing, isBlastCandidate: isBlastMode, onTap: () => onTileTap(t.id))),
        ],
      ),
    );
  }
}

class AnimatedTile extends StatefulWidget {
  final Tile tile;
  final double size;
  final double spacing;
  final bool isBlastCandidate;
  final VoidCallback onTap;
  const AnimatedTile({super.key, required this.tile, required this.size, required this.spacing, required this.isBlastCandidate, required this.onTap});

  @override
  State<AnimatedTile> createState() => _AnimatedTileState();
}

class _AnimatedTileState extends State<AnimatedTile> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 50),
    ]).animate(_controller);
    if (widget.tile.isNew) _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedTile old) {
    super.didUpdateWidget(old);
    if (old.tile.value != widget.tile.value) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tileColor = _getColor(widget.tile.value);
    final hasGlow = widget.tile.value >= 128;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      left: widget.tile.x * (widget.size + widget.spacing),
      top: widget.tile.y * (widget.size + widget.spacing),
      child: GestureDetector(
        onTap: widget.isBlastCandidate ? widget.onTap : null,
        child: ScaleTransition(
          scale: widget.tile.isDeleting ? const AlwaysStoppedAnimation(1.0) : _scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: tileColor,
              borderRadius: BorderRadius.circular(10),
              border: widget.isBlastCandidate ? Border.all(color: Colors.red, width: 3) : null,
              boxShadow: [if (hasGlow && !widget.tile.isDeleting) BoxShadow(color: tileColor.withOpacity(0.4), blurRadius: 15, spreadRadius: 1)],
            ),
            child: Center(
              child: Text("${widget.tile.value}", style: TextStyle(fontSize: widget.tile.value > 100 ? (widget.tile.value > 1000 ? 18 : 22) : 28, fontWeight: FontWeight.bold, color: widget.tile.value <= 4 ? Colors.black54 : Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  Color _getColor(int v) {
    switch (v) {
      case 2: return const Color(0xFFEEE4DA);
      case 4: return const Color(0xFFEDE0C8);
      case 8: return const Color(0xFFF2B179);
      case 16: return const Color(0xFFF59563);
      case 32: return const Color(0xFFF67C5F);
      case 64: return const Color(0xFFF65E3B);
      case 128: return const Color(0xFFEDCF72);
      case 256: return const Color(0xFFEDCC61);
      case 512: return const Color(0xFFEDC850);
      case 1024: return const Color(0xFFEDC53F);
      case 2048: return const Color(0xFFEDC22E);
      default: return const Color(0xFF3C3A32);
    }
  }}
