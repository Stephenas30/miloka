import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../game/fanorona/fanorona_board_layout.dart';
import '../../game/fanorona/fanorona_engine.dart';
import '../../providers/auth_provider.dart';
import '../../service/fanorona/lobby_service.dart';
import '../../service/game_channel_service.dart';
import '../../service/stats_service.dart';
import '../../utils/image_cache.dart';
import '../profile_screen.dart';
import '../home_screen.dart';
import '../purchase_screen.dart';
import '../../widgets/friends_dialog.dart';
import '../../widgets/game_result_animation.dart';
import 'fanorona_lobby_screen.dart';

class FanoronaScreen extends StatefulWidget {
  final bool isOnline;
  final bool isHost;
  final String teamId;
  final String channelId;

  const FanoronaScreen({
    super.key,
    this.isOnline = false,
    this.isHost = false,
    this.teamId = '',
    this.channelId = '',
  });

  @override
  State<FanoronaScreen> createState() => _FanoronaScreenState();
}

class _FanoronaScreenState extends State<FanoronaScreen>
    with WidgetsBindingObserver {
  late FanoronaEngine _engine;
  bool _beginGame = false;
  bool _isOnline = false;
  bool _aiPlaying = false;
  Timer? _aiTimer;
  Timer? _requestTimer;
  StreamSubscription<Map<String, dynamic>>? _gameSubscription;

  int _myPlayerIndex = 0;
  int get _aiPlayerIndex => 1;

  int? _selectedPiece;
  Map<int, Set<FanoronaMoveType>> _targets = {};
  int? _pendingDualChoice;
  List<int> _capturedAnimating = [];
  int? _highlightFrom;
  int? _highlightTo;

  bool _stateReceived = false;
  bool _gameOverHandled = false;
  double _cellSize = 40;

  /// Numéro de séquence du dernier état reçu (anti-échos périmés).
  int _stateSeq = -1;

  // Chrono de réflexion par coup.
  static const int _turnSeconds = 60;
  static const int _warnSecondsLeft = 10;
  Timer? _clockTimer;
  int _secondsLeft = _turnSeconds;
  bool _timeWarnOpen = false;
  bool _timeoutHandled = false;

  bool get _isMyTurn {
    if (_engine.isGameOver) return false;
    if (_aiPlaying) return false;
    if (_isOnline && !_stateReceived) return false;
    return _engine.turn == _myPlayerIndex;
  }

  @override
  void initState() {
    super.initState();
    // Lobby/menu en portrait, plateau (9x5) en paysage pour être entièrement
    // visible.
    _applyOrientation(landscape: widget.isOnline);
    _engine = FanoronaEngine();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _onClockTick(),
    );
    if (widget.isOnline) {
      _isOnline = true;
      _beginGame = true;
      _myPlayerIndex = widget.isHost ? 0 : 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _connectChannel();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Au retour au premier plan, le socket Realtime peut être mort
    // (Android suspend les WebSockets en arrière-plan) : on resynchronise.
    if (state == AppLifecycleState.resumed && _isOnline && _beginGame) {
      _resyncConnection();
    }
  }

  void _applyOrientation({required bool landscape}) {
    SystemChrome.setPreferredOrientations(
      landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Restaurer le portrait par défaut de l'app en quittant le jeu.
    _applyOrientation(landscape: false);
    _aiTimer?.cancel();
    _requestTimer?.cancel();
    _clockTimer?.cancel();
    _gameSubscription?.cancel();
    if (_isOnline) {
      GameChannelService().disconnect();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Online
  // ---------------------------------------------------------------

  Future<void> _connectChannel() async {
    try {
      await GameChannelService().connect(widget.channelId);
      _gameSubscription = GameChannelService().events.listen(_handleGameEvent);
      setState(() {
        if (widget.isHost) _stateReceived = true;
      });
      if (widget.isHost) {
        _broadcastState();
      } else {
        _requestState();
        _requestTimer = Timer.periodic(const Duration(seconds: 2), (_) {
          if (!_stateReceived) _requestState();
        });
      }
    } catch (e) {
      debugPrint('Fanorona connect failed: $e');
    }
  }

  Future<void> _resyncConnection() async {
    debugPrint('Fanorona app resumed: resync channel');
    _gameSubscription?.cancel();
    try {
      await GameChannelService().reconnect();
    } catch (e) {
      debugPrint('Fanorona reconnect failed: $e');
    }
    if (!mounted) return;
    _gameSubscription = GameChannelService().events.listen(_handleGameEvent);
    _resetTurnClock();
    if (widget.isHost) {
      _broadcastState();
    } else {
      setState(() => _stateReceived = false);
      _requestState();
    }
  }

  void _requestState() {
    GameChannelService().send('request_state', {});
  }

  void _broadcastState() {
    if (!_isOnline || !widget.isHost) return;
    GameChannelService().send('game_state', {
      'seq': ++_stateSeq,
      'state': _engine.snapshot(),
    });
  }

  /// Les payloads Supabase Realtime peuvent livrer les nombres sous forme
  /// de String ("1", voire "1.0") après passage par le serveur.
  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      final parsed = int.tryParse(trimmed);
      if (parsed != null) return parsed;
      return double.tryParse(trimmed)?.toInt();
    }
    return null;
  }

  void _handleGameEvent(Map<String, dynamic> payload) {
    if (!mounted) return;
    final action = payload['action']?.toString();
    debugPrint('Fanorona event [$action] payload=$payload');

    if (action == 'game_state') {
      final raw = payload['state'];
      final seq = _parseInt(payload['seq']) ?? -1;
      if (raw is Map) {
        if (seq >= 0 && seq <= _stateSeq) {
          debugPrint('Fanorona stale state seq=$seq (last=$_stateSeq) ignored');
          return;
        }
        _stateSeq = seq;
        // Pendant notre propre séquence de capture, l'écho de l'hôte est
        // redondant : l'appliquer effacerait la sélection en cours (et un
        // écho retardé ferait régresser le plateau local).
        if (_engine.inCaptureSequence && _engine.turn == _myPlayerIndex) {
          debugPrint('Fanorona state seq=$seq skipped (own capture sequence)');
          return;
        }
        setState(() {
          _engine.applySnapshot(Map<String, dynamic>.from(raw));
          _selectedPiece = null;
          _targets = {};
          _pendingDualChoice = null;
          _stateReceived = true;
          _resetTurnClock();
        });
        _checkGameOver();
      }
    } else if (action == 'move') {
      if (!widget.isHost) return;
      final from = _parseInt(payload['from']);
      final dir = _parseInt(payload['dir']);
      // Clé "move_type" et non "type" : Supabase Realtime écrase la clé
      // "type" du payload avec son enveloppe ("type": "broadcast").
      final type = _parseInt(payload['move_type']);
      debugPrint('Fanorona remote move parsed from=$from dir=$dir type=$type');
      if (from == null ||
          dir == null ||
          type == null ||
          type < 0 ||
          type >= FanoronaMoveType.values.length) {
        return;
      }
      _applyRemoteMove(FanoronaMove(from, dir, FanoronaMoveType.values[type]));
    } else if (action == 'end_capture') {
      if (!widget.isHost) return;
      if (!_engine.inCaptureSequence) return;
      _engine.endTurn();
      _selectedPiece = null;
      _targets = {};
      _pendingDualChoice = null;
      _highlightFrom = null;
      _highlightTo = null;
      _resetTurnClock();
      _broadcastState();
      setState(() {});
      _checkGameOver();
    } else if (action == 'timeout') {
      // L'adversaire a dépassé les 60 s : victoire du joueur local.
      if (!widget.isHost) return;
      if (_engine.isGameOver) return;
      _engine.winner = _myPlayerIndex;
      _engine.drawReason = null;
      _resetTurnClock();
      _broadcastState();
      setState(() {});
      _checkGameOver();
    } else if (action == 'request_state') {
      if (widget.isHost) _broadcastState();
    }
  }

  void _applyRemoteMove(FanoronaMove move) {
    _highlightFrom = move.from;
    _highlightTo = _destinationOf(move);
    final captured = _engine.applyMove(move);
    _selectedPiece = null;
    _targets = {};
    _pendingDualChoice = null;
    _resetTurnClock();
    setState(() {});
    if (captured.isNotEmpty) {
      _capturedAnimating = captured;
      setState(() {});
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) setState(() => _capturedAnimating = []);
      });
    }
    _afterMoveApplied();
  }

  int _destinationOf(FanoronaMove move) {
    switch (move.dir) {
      case 0:
        return move.from - FanoronaEngine.cols;
      case 1:
        return move.from - FanoronaEngine.cols + 1;
      case 2:
        return move.from + 1;
      case 3:
        return move.from + FanoronaEngine.cols + 1;
      case 4:
        return move.from + FanoronaEngine.cols;
      case 5:
        return move.from + FanoronaEngine.cols - 1;
      case 6:
        return move.from - 1;
      case 7:
        return move.from - FanoronaEngine.cols - 1;
    }
    return move.from;
  }

  // ---------------------------------------------------------------
  // Game flow
  // ---------------------------------------------------------------

  void _startSolo() {
    _applyOrientation(landscape: true);
    _resetTurnClock();
    setState(() {
      _engine = FanoronaEngine();
      _beginGame = true;
      _isOnline = false;
      _myPlayerIndex = 0;
      _selectedPiece = null;
      _targets = {};
      _pendingDualChoice = null;
      _gameOverHandled = false;
    });
  }

  Future<void> _startOnlineGame() async {
    final userProfile = context.read<AuthProvider?>()?.userProfile;
    if (userProfile == null) return;
    final userId = userProfile['id']?.toString();
    if (userId == null) return;
    final teamId = await FanoronaTeamLobbyService().createTeam(
      userId,
      userProfile,
    );
    if (teamId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la création du lobby')),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FanoronaLobbyScreen(teamId: teamId, isHost: true),
      ),
    );
  }

  Future<void> _showJoinDialog() async {
    final controller = TextEditingController();
    if (!mounted) return;
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Rejoindre une partie',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Code d\'équipe',
            labelStyle: TextStyle(color: Colors.white54),
            hintText: 'ex: 123456',
            hintStyle: TextStyle(color: Colors.white24),
            counterText: '',
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Annuler',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Rejoindre',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !mounted) return;
    final team = await FanoronaTeamLobbyService().joinTeam(code);
    if (team == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code invalide ou équipe pleine.')),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FanoronaLobbyScreen(teamId: team['team_id'], isHost: false),
      ),
    );
  }

  void _onBoardTap(TapUpDetails details) {
    if (!_beginGame || !_isMyTurn) return;
    final pos = FanoronaBoardLayout.nearestPoint(
      details.localPosition,
      _cellSize,
    );
    if (pos == -1) return;

    if (_pendingDualChoice != null) {
      _handleDualChoiceTap(details.localPosition, pos);
      return;
    }

    final boardValue = _engine.board[pos];

    if (_selectedPiece == null) {
      if (boardValue == _engine.activePiece) {
        final targets = _engine.targetsForPiece(pos);
        if (targets.isNotEmpty) {
          setState(() {
            _selectedPiece = pos;
            _targets = targets;
          });
        }
      }
      return;
    }

    if (pos == _selectedPiece) {
      setState(() {
        _selectedPiece = null;
        _targets = {};
      });
      return;
    }

    final targetTypes = _targets[pos];
    if (targetTypes != null) {
      if (targetTypes.length > 1) {
        setState(() => _pendingDualChoice = pos);
        return;
      }
      final dir = FanoronaEngine.directionBetween(_selectedPiece!, pos);
      if (dir == -1) return;
      _executeMove(FanoronaMove(_selectedPiece!, dir, targetTypes.first));
      return;
    }

    if (boardValue == _engine.activePiece) {
      final targets = _engine.targetsForPiece(pos);
      if (targets.isNotEmpty) {
        setState(() {
          _selectedPiece = pos;
          _targets = targets;
        });
        return;
      }
    }

    setState(() {
      _selectedPiece = null;
      _targets = {};
    });
  }

  void _handleDualChoiceTap(Offset localPos, int tappedPos) {
    final to = _pendingDualChoice!;
    final targetPos = FanoronaBoardLayout.pointAtIndex(to, _cellSize);
    final dx = localPos.dx - targetPos.dx;
    final type = dx < 0
        ? FanoronaMoveType.approach
        : FanoronaMoveType.withdrawal;
    final types = _targets[to];
    if (types == null || !types.contains(type)) return;
    final dir = FanoronaEngine.directionBetween(_selectedPiece!, to);
    if (dir == -1) return;
    _executeMove(FanoronaMove(_selectedPiece!, dir, type));
  }

  void _executeMove(FanoronaMove move) {
    _highlightFrom = move.from;
    _highlightTo = _destinationOf(move);
    _selectedPiece = null;
    _targets = {};
    _pendingDualChoice = null;

    if (_isOnline && !widget.isHost) {
      // Encodé en String : insensible aux transformations de types du
      // transport. "move_type" car Supabase réserve la clé "type".
      GameChannelService().send('move', {
        'from': move.from.toString(),
        'dir': move.dir.toString(),
        'move_type': move.type.index.toString(),
      });
    }

    final captured = _engine.applyMove(move);
    _resetTurnClock();
    setState(() {});
    if (captured.isNotEmpty) {
      _capturedAnimating = captured;
      setState(() {});
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) setState(() => _capturedAnimating = []);
      });
    }
    _afterMoveApplied();
  }

  void _afterMoveApplied() {
    if (!_engine.inCaptureSequence) {
      _broadcastState();
      setState(() {});
      _checkGameOver();
      if (!_isOnline) _scheduleAiTurn();
      return;
    }
    final continuations = _engine.legalMoves();
    if (continuations.isEmpty) {
      _engine.endTurn();
      _broadcastState();
      setState(() {});
      _checkGameOver();
      if (!_isOnline) _scheduleAiTurn();
      return;
    }
    // En ligne, la suite de la capture appartient au joueur dont c'est le
    // tour ; l'adversaire regarde seulement (highlights déjà posés).
    if (_isOnline && _engine.turn != _myPlayerIndex) {
      _selectedPiece = null;
      _targets = {};
      _pendingDualChoice = null;
      _broadcastState();
      setState(() {});
      return;
    }
    _selectedPiece = _engine.movingPiecePos;
    _targets = _engine.targetsForPiece(_selectedPiece!);
    _broadcastState();
    setState(() {});
  }

  void _stopCapture() {
    if (!_isMyTurn || !_engine.inCaptureSequence) return;
    if (_isOnline && !widget.isHost) {
      // L'hôte est autoritaire : il doit être informé de la fin de la
      // séquence de capture, sinon il reste bloqué au tour de l'invité.
      GameChannelService().send('end_capture', {});
    }
    _engine.endTurn();
    _resetTurnClock();
    _selectedPiece = null;
    _targets = {};
    _pendingDualChoice = null;
    _broadcastState();
    setState(() {});
    _checkGameOver();
    if (!_isOnline) _scheduleAiTurn();
  }

  void _scheduleAiTurn() {
    if (_engine.isGameOver) return;
    if (_aiTimer?.isActive ?? false) return;
    if (_aiPlaying) return;
    _aiTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _runAiTurn();
    });
  }

  Future<void> _runAiTurn() async {
    if (!mounted || _engine.isGameOver) return;
    setState(() => _aiPlaying = true);
    await Future.delayed(const Duration(milliseconds: 500));
    while (mounted && !_engine.isGameOver && _engine.turn == _aiPlayerIndex) {
      final move = _engine.aiChooseNextMove();
      if (move == null) {
        if (_engine.inCaptureSequence) _engine.endTurn();
        break;
      }
      _highlightFrom = move.from;
      _highlightTo = _destinationOf(move);
      final captured = _engine.applyMove(move);
      setState(() {});
      if (captured.isNotEmpty) {
        _capturedAnimating = captured;
        setState(() {});
        await Future.delayed(const Duration(milliseconds: 320));
        if (mounted) setState(() => _capturedAnimating = []);
      } else {
        await Future.delayed(const Duration(milliseconds: 250));
      }
      if (_engine.isGameOver) break;
      if (!_engine.inCaptureSequence) break;
    }
    if (!mounted) return;
    setState(() => _aiPlaying = false);
    _checkGameOver();
  }

  // ---------------------------------------------------------------
  // Chrono de réflexion (60 s par coup)
  // ---------------------------------------------------------------

  void _resetTurnClock() {
    _secondsLeft = _turnSeconds;
    _timeoutHandled = false;
  }

  void _onClockTick() {
    if (!mounted || !_beginGame || _engine.isGameOver) return;
    if (!_isMyTurn) {
      // Tour adverse : le chrono reste armé à 60 s.
      if (_secondsLeft != _turnSeconds || _timeoutHandled) {
        _resetTurnClock();
        setState(() {});
      }
      return;
    }
    if (_timeoutHandled) return;
    if (_secondsLeft > 0) _secondsLeft--;
    if (_secondsLeft == _warnSecondsLeft) _showTimeWarning();
    if (_secondsLeft <= 0) {
      _timeoutHandled = true;
      setState(() {});
      _handleSelfTimeout();
    } else {
      setState(() {});
    }
  }

  /// Alerte affichée à 50 s écoulées (10 s restantes), fermée auto après 3 s.
  void _showTimeWarning() {
    if (_timeWarnOpen || !mounted) return;
    _timeWarnOpen = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.timer, color: Colors.redAccent),
            const SizedBox(width: 8),
            const Text(
              'Plus que $_warnSecondsLeft secondes !',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'Dépêche-toi de jouer : si le temps s\'écoule, tu perds la partie.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    ).whenComplete(() => _timeWarnOpen = false);
    Timer(const Duration(seconds: 3), () {
      if (mounted && _timeWarnOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    });
  }

  /// Délai dépassé : le joueur courant perd et retourne au choix du mode.
  Future<void> _handleSelfTimeout() async {
    if (_engine.isGameOver || !_isMyTurn) return;
    _engine.winner = 1 - _myPlayerIndex;
    _engine.drawReason = null;
    if (_isOnline) {
      if (widget.isHost) {
        // Diffuser d'abord la victoire de l'adversaire, puis quitter.
        await GameChannelService().send('game_state', {
          'seq': ++_stateSeq,
          'state': _engine.snapshot(),
        });
        _settleBets();
      } else {
        await GameChannelService().send('timeout', {});
      }
    }
    _recordStats();
    await _returnToModeSelection();
  }

  // ---------------------------------------------------------------
  // Game over / stats / cleanup
  // ---------------------------------------------------------------

  void _checkGameOver() {
    if (!_engine.isGameOver || _gameOverHandled) return;
    _gameOverHandled = true;
    _broadcastState();
    _recordStats();
    // Règlement des mises : l'hôte est autoritaire, une seule fois,
    // et seulement s'il y a un vainqueur (pas de nulle).
    if (_isOnline &&
        widget.isHost &&
        widget.teamId.isNotEmpty &&
        _engine.winner != null) {
      _settleBets();
    }
    _refreshProfileAfterMatch();
    _showGameOverDialog();
  }

  /// Le perdant perd sa mise ; le gagnant reçoit 2/3 de la mise du perdant,
  /// l'application conserve 1/3 (table app_gains).
  Future<void> _settleBets() async {
    try {
      final team = await FanoronaTeamLobbyService().getTeam(widget.teamId);
      if (team == null) return;
      final members = FanoronaTeamLobbyService().getMembersList(team);
      if (members.length < 2) return;

      final winnerIndex = _engine.winner!.clamp(0, members.length - 1);
      final loserIndex = 1 - winnerIndex;
      final winnerId = members[winnerIndex]['id']?.toString();
      final loserId = members[loserIndex]['id']?.toString();
      if (winnerId == null || loserId == null) return;

      final winnerProfile = members[winnerIndex]['profile'] as Map?;
      final winnerName =
          (winnerProfile?['username'] ??
                  winnerProfile?['full_name'] ??
                  winnerId)
              .toString();

      final mise =
          ((members[loserIndex]['profile'] as Map?)?['bet'] as int?) ?? 0;
      if (mise <= 0) return;

      final winnerExtra = (2 * mise) ~/ 3;
      final appShare = mise - winnerExtra;
      final supabase = Supabase.instance.client;

      final loserRow = await supabase
          .from('users')
          .select('coins')
          .eq('id', loserId)
          .maybeSingle();
      final loserCoins = (loserRow?['coins'] as int?) ?? 0;
      await supabase
          .from('users')
          .update({'coins': loserCoins - mise})
          .eq('id', loserId);

      final winnerRow = await supabase
          .from('users')
          .select('coins')
          .eq('id', winnerId)
          .maybeSingle();
      final winnerCoins = (winnerRow?['coins'] as int?) ?? 0;
      await supabase
          .from('users')
          .update({'coins': winnerCoins + winnerExtra})
          .eq('id', winnerId);

      if (appShare > 0) {
        await supabase.from('app_gains').insert({
          'match_code': 'fanorona_${widget.teamId}',
          'amount': appShare,
          'bet': mise,
          'winner_team': winnerName,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      debugPrint(
        'Fanorona bets settled: mise=$mise winner=+$winnerExtra app=+$appShare',
      );
      if (mounted) context.read<AuthProvider?>()?.refreshProfile();
    } catch (e) {
      debugPrint('Fanorona bet settlement failed: $e');
    }
  }

  void _recordStats() {
    final won =
        _engine.winner != null &&
        _engine.winner == (_isOnline ? _myPlayerIndex : 0);
    StatsService().recordGameResult(
      gameName: 'fanorona',
      won: won,
      context: context,
    );
  }

  /// Actualise le profil (jetons) après un match : immédiat, puis une seconde
  /// fois après un délai pour rattraper le règlement des mises par l'hôte.
  void _refreshProfileAfterMatch() {
    context.read<AuthProvider?>()?.refreshProfile();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) context.read<AuthProvider?>()?.refreshProfile();
    });
  }

  Future<void> _cleanupTeams() async {
    final team = await FanoronaTeamLobbyService().getTeam(widget.teamId);
    final mergedSource = team?['merged_source_id']?.toString();
    await FanoronaTeamLobbyService().deleteTeam(widget.teamId);
    if (mergedSource != null && mergedSource.isNotEmpty) {
      await FanoronaTeamLobbyService().deleteTeam(mergedSource);
    }
  }

  void _showGameOverDialog() {
    if (!mounted) return;
    final draw = _engine.winner == null;
    final won =
        _engine.winner != null &&
        _engine.winner == (_isOnline ? _myPlayerIndex : 0);
    final message = draw
        ? (_engine.drawReason == 'paika'
              ? '50 coups sans capture : partie nulle.'
              : 'Position répétée 3 fois : partie nulle.')
        : (won
              ? 'Félicitations, tu as gagné !'
              : 'L\'adversaire a gagné. Retente ta chance !');

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (ctx) => GameResultAnimation(
        won: draw ? null : won,
        title: draw ? 'ÉGALITÉ' : (won ? 'VICTOIRE !' : 'DÉFAITE'),
        subtitle: message,
        icon: draw ? '🤝' : null,
        actions: [
          GameResultAction(
            label: 'Choix du mode de jeu',
            color: const Color(0xFF9A5424),
            onPressed: () {
              Navigator.pop(ctx);
              _returnToModeSelection();
            },
          ),
        ],
        ),
    );
  }

  /// Retourne au choix du mode de jeu (menu de FanoronaScreen).
  Future<void> _returnToModeSelection() async {
    _refreshProfileAfterMatch();
    _applyOrientation(landscape: false);
    if (_isOnline) {
      GameChannelService().disconnect();
      if (widget.isHost && widget.teamId.isNotEmpty) {
        await _cleanupTeams();
      }
    }
    _aiTimer?.cancel();
    _requestTimer?.cancel();
    _gameSubscription?.cancel();
    _gameSubscription = null;
    if (!mounted) return;
    setState(() {
      _engine = FanoronaEngine();
      _beginGame = false;
      _isOnline = false;
      _aiPlaying = false;
      _stateReceived = false;
      _gameOverHandled = false;
      _stateSeq = -1;
      _selectedPiece = null;
      _targets = {};
      _pendingDualChoice = null;
      _capturedAnimating = [];
      _highlightFrom = null;
      _highlightTo = null;
      _myPlayerIndex = 0;
    });
  }

  Future<void> _confirmLeaveGame() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Text(
          'Quitter la partie ?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Êtes-vous sûr de vouloir quitter la partie ?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Annuler',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Quitter',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_isOnline) {
      await GameChannelService().disconnect();
      if (widget.isHost && widget.teamId.isNotEmpty) {
        await _cleanupTeams();
      }
    }
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => route.isFirst,
      );
    }
  }

  void _showRules() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Règles du Fanorona',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: const Text(
            '• Déplace une pièce d\'un point vers un point voisin libre, le long des lignes.\n\n'
            '• Approche : avance vers une pièce adverse pour la capturer (avec ses alignées).\n\n'
            '• Retrait : recule pour capturer la (les) pièce(s) derrière la position de départ.\n\n'
            '• Si une capture est possible, elle est obligatoire (la capture « paika » n\'est alors pas autorisée).\n\n'
            '• Si les deux types de capture sont possibles sur la même case, choisis-en un.\n\n'
            '• Après une capture, la même pièce peut continuer à capturer (aucun retour en arrière, ni 2 fois de suite dans la même direction). Tu peux t\'arrêter quand tu veux.\n\n'
            '• Si tu ne peux pas capturer, tu fais un simple déplacement « paika ».\n\n'
            '• Gagne en éliminant toutes les pièces adverses ou en le laissant sans coup possible.\n\n'
            '• Nulle : 50 coups consécutifs sans capture, ou position répétée 3 fois.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_beginGame && _engine.isGameOver && !_gameOverHandled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkGameOver();
      });
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(child: _beginGame ? _buildGame() : _buildMain()),
      ),
    );
  }

  Widget _buildGame() {
    return Stack(
      children: [
        Column(
          children: [
            _buildHeader(),
            Expanded(child: Center(child: _buildBoard())),
            _buildBottomBar(),
          ],
        ),
        Positioned(
          top: 8,
          left: 8,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: Colors.black.withValues(alpha: 0.6),
            shape: const CircleBorder(),
            onPressed: _confirmLeaveGame,
            child: const Icon(Icons.arrow_back, color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final authProvider = context.read<AuthProvider?>();
    final coins =
        int.tryParse((authProvider?.userProfile?['coins'] ?? '0').toString()) ??
        0;
    final avatarUrl = authProvider?.userProfile?['avatar_url']?.toString();
    final username =
        authProvider?.userProfile?['username']?.toString() ?? 'Profil';

    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFFF8C00).withValues(alpha: 0.4),
              ),
            ),
            child: const Text(
              'Fanorona',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Row(
            children: [
              IconButton(
                onPressed: _showRules,
                icon: const Icon(
                  Icons.help_outline,
                  color: Colors.white70,
                  size: 20,
                ),
                tooltip: 'Règles',
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.white24,
                        backgroundImage:
                            avatarUrl != null && avatarUrl.isNotEmpty
                            ? cachedNetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl == null || avatarUrl.isEmpty
                            ? const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 14,
                              )
                            : null,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      color: Colors.amber,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$coins',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _statusText {
    if (_engine.isGameOver) {
      if (_engine.winner == null) return 'Partie nulle';
      final won = _engine.winner == (_isOnline ? _myPlayerIndex : 0);
      return won ? 'Victoire !' : 'Défaite';
    }
    if (_isOnline && !_stateReceived) return 'Synchronisation...';
    if (!_isMyTurn) {
      return _isOnline ? 'Tour de l\'adversaire' : 'Tour de l\'IA...';
    }
    if (_engine.inCaptureSequence) {
      return 'Continue la capture, ou arrête.';
    }
    final moves = _engine.legalMoves();
    if (moves.isEmpty) return 'Plus de coup possible';
    if (moves.first.type != FanoronaMoveType.paika) {
      return 'Capture obligatoire ! Choisis une pièce';
    }
    return 'Déplace une pièce';
  }

  Widget _buildBottomBar() {
    final inSequence = _engine.inCaptureSequence && _isMyTurn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pieceCount(FanoronaPlayer.human),
                if (_isMyTurn) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (_secondsLeft <= _warnSecondsLeft
                                  ? Colors.redAccent
                                  : Colors.white)
                              .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: _secondsLeft <= _warnSecondsLeft
                              ? Colors.redAccent
                              : Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_secondsLeft s',
                          style: TextStyle(
                            color: _secondsLeft <= _warnSecondsLeft
                                ? Colors.redAccent
                                : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    _statusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _pieceCount(FanoronaPlayer.ai),
              ],
            ),
          ),
          if (inSequence) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _stopCapture,
                icon: const Icon(Icons.stop, size: 18),
                label: const Text('Arrêter la capture'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pieceCount(FanoronaPlayer player) {
    final isHuman = player == FanoronaPlayer.human;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:
            (isHuman
                    ? FanoronaBoardLayout.humanColor
                    : FanoronaBoardLayout.aiColor)
                .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${_engine.countPieces(player)}',
        style: TextStyle(
          color: isHuman ? const Color(0xFFFFB74D) : Colors.grey.shade300,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _buildBoard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = math.min(
          constraints.maxWidth / (FanoronaEngine.cols - 1),
          constraints.maxHeight / (FanoronaEngine.rows - 1),
        );
        _cellSize = cell;
        final size = FanoronaBoardLayout.boardSize(cell);
        return Center(
          child: GestureDetector(
            onTapUp: _onBoardTap,
            child: CustomPaint(
              size: size,
              painter: FanoronaBoardPainter(
                cellSize: cell,
                board: _engine.board,
                selectedPiece: _selectedPiece,
                targets: _targets,
                movingPiece: _engine.inCaptureSequence
                    ? _engine.movingPiecePos
                    : null,
                capturedAnimating: _capturedAnimating,
                pendingDualChoice: _pendingDualChoice,
                highlightFrom: _highlightFrom,
                highlightTo: _highlightTo,
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------
  // Main menu (mode selection)
  // ---------------------------------------------------------------

  Future<void> _onPrivateGame() async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Partie en ligne',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Crée une partie et invite un ami ou lance une recherche publique, ou rejoins avec le code d\'équipe.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'create'),
            child: const Text('Créer', style: TextStyle(color: Colors.amber)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'join'),
            child: const Text(
              'Rejoindre',
              style: TextStyle(color: Colors.greenAccent),
            ),
          ),
        ],
      ),
    );
    if (action == 'create') {
      await _startOnlineGame();
    } else if (action == 'join') {
      await _showJoinDialog();
    }
  }

  Widget _buildMain() {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Fanorona',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 12)],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFFF8C00).withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  'Jeu de stratégie malgache',
                  style: TextStyle(
                    color: Color(0xFFFF8C00),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              _buildGameChip('Contre IA', Icons.smart_toy, () => _startSolo()),
              const SizedBox(height: 16),
              _buildGameChip('En ligne', Icons.wifi, _onPrivateGame),
            ],
          ),
        ),
        Positioned(top: 12, left: 12, right: 12, child: _buildMenuTopBar()),
        Positioned(
          bottom: 20,
          left: 16,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: Colors.black.withValues(alpha: 0.6),
            shape: const CircleBorder(),
            onPressed: () => Navigator.of(context).pop(),
            child: const Icon(Icons.arrow_back, color: Colors.white70),
          ),
        ),
      ],
    );
  }

  /// Barre du haut du menu : amis, profil, jetons (identique à Ludo).
  Widget _buildMenuTopBar() {
    final authProvider = context.read<AuthProvider?>();
    final coins =
        int.tryParse((authProvider?.userProfile?['coins'] ?? '0').toString()) ??
        0;
    final avatarUrl = authProvider?.userProfile?['avatar_url']?.toString();
    final username =
        authProvider?.userProfile?['username']?.toString() ?? 'Profil';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => showFriendsDialog(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const CircleAvatar(
              radius: 14,
              backgroundColor: Colors.black54,
              child: Icon(Icons.people_alt, color: Colors.white, size: 20),
            ),
          ),
        ),
        Row(
          spacing: 8,
          children: [
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white24,
                      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                          ? cachedNetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl == null || avatarUrl.isEmpty
                          ? const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      username,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PurchaseScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$coins',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGameChip(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        height: 60,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF8C00), Color(0xFFFF8C00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF8C00).withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            const BoxShadow(
              color: Colors.black38,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FanoronaBoardPainter extends CustomPainter {
  final double cellSize;
  final List<int> board;
  final int? selectedPiece;
  final Map<int, Set<FanoronaMoveType>> targets;
  final int? movingPiece;
  final List<int> capturedAnimating;
  final int? pendingDualChoice;
  final int? highlightFrom;
  final int? highlightTo;

  const FanoronaBoardPainter({
    required this.cellSize,
    required this.board,
    this.selectedPiece,
    this.targets = const {},
    this.movingPiece,
    this.capturedAnimating = const [],
    this.pendingDualChoice,
    this.highlightFrom,
    this.highlightTo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // plateau
    final bg = Paint()
      ..color = const Color(0xFF5D3A1A).withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(cellSize * 0.4),
      ),
      bg,
    );

    final linePaint = Paint()
      ..color = FanoronaBoardLayout.lineColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cellSize * 0.03
      ..strokeCap = StrokeCap.round;

    // lignes
    for (final seg in FanoronaBoardLayout.lineSegments) {
      final start = FanoronaBoardLayout.pointAt(seg[0], seg[1], cellSize);
      final end = FanoronaBoardLayout.pointAt(seg[2], seg[3], cellSize);
      canvas.drawLine(start, end, linePaint);
    }

    // points forts
    final strongPaint = Paint()
      ..color = FanoronaBoardLayout.strongPointColor.withValues(alpha: 0.35);
    for (var pos = 0; pos < FanoronaEngine.size; pos++) {
      if (FanoronaEngine.isStrongPoint(pos)) {
        canvas.drawCircle(
          FanoronaBoardLayout.pointAtIndex(pos, cellSize),
          cellSize * 0.06,
          strongPaint,
        );
      }
    }

    // highlight du dernier coup
    if (highlightFrom != null) {
      final hl = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        FanoronaBoardLayout.pointAtIndex(highlightFrom!, cellSize),
        cellSize * 0.32,
        hl,
      );
    }
    if (highlightTo != null) {
      final hl = Paint()
        ..color = const Color(0xFFFFF176).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        FanoronaBoardLayout.pointAtIndex(highlightTo!, cellSize),
        cellSize * 0.32,
        hl,
      );
    }

    // pièces
    for (var pos = 0; pos < FanoronaEngine.size; pos++) {
      final value = board[pos];
      if (value == FanoronaEngine.empty) continue;
      final center = FanoronaBoardLayout.pointAtIndex(pos, cellSize);
      final isSelected = pos == selectedPiece;
      final isMoving = pos == movingPiece;

      if (isSelected || isMoving) {
        final ring = Paint()
          ..color = isSelected ? Colors.white : const Color(0xFFFFF176)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, cellSize * 0.37, ring);
      }

      final color = value == FanoronaEngine.humanPiece
          ? FanoronaBoardLayout.humanColor
          : FanoronaBoardLayout.aiColor;
      final piece = Paint()..color = color;
      canvas.drawCircle(center, cellSize * 0.30, piece);

      final edge = Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.03;
      canvas.drawCircle(center, cellSize * 0.30, edge);

      if (value == FanoronaEngine.humanPiece) {
        final shine = Paint()..color = Colors.white.withValues(alpha: 0.15);
        canvas.drawCircle(
          center.translate(-cellSize * 0.08, -cellSize * 0.08),
          cellSize * 0.10,
          shine,
        );
      }
    }

    // captures en cours d'animation (pièces supprimées)
    if (capturedAnimating.isNotEmpty) {
      final fade = Paint()..color = Colors.red.withValues(alpha: 0.55);
      for (final pos in capturedAnimating) {
        canvas.drawCircle(
          FanoronaBoardLayout.pointAtIndex(pos, cellSize),
          cellSize * 0.30,
          fade,
        );
      }
    }

    // cibles de capture (cercles verts)
    for (final entry in targets.entries) {
      final center = FanoronaBoardLayout.pointAtIndex(entry.key, cellSize);
      if (entry.value.length > 1) {
        // double capture -> un cercle vert unique pour ouvrir le choix
        final dot = Paint()..color = Colors.greenAccent;
        canvas.drawCircle(center, cellSize * 0.20, dot);
        final ring = Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cellSize * 0.03;
        canvas.drawCircle(center, cellSize * 0.20, ring);
      } else {
        final dot = Paint()..color = Colors.greenAccent;
        canvas.drawCircle(center, cellSize * 0.18, dot);
        final ring = Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cellSize * 0.03;
        canvas.drawCircle(center, cellSize * 0.18, ring);
      }
    }

    // choix de double capture : deux cercles verts (approche à gauche, retrait à droite)
    if (pendingDualChoice != null) {
      final center = FanoronaBoardLayout.pointAtIndex(
        pendingDualChoice!,
        cellSize,
      );
      final offset = Offset(cellSize * 0.55, 0);
      _drawChoiceCircle(canvas, center - offset, 'A', false);
      _drawChoiceCircle(canvas, center + offset, 'R', true);
    }
  }

  void _drawChoiceCircle(
    Canvas canvas,
    Offset center,
    String label,
    bool isRight,
  ) {
    final dot = Paint()
      ..color = isRight ? const Color(0xFF26C6DA) : Colors.greenAccent;
    canvas.drawCircle(center, cellSize * 0.20, dot);
    final ring = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = cellSize * 0.03;
    canvas.drawCircle(center, cellSize * 0.20, ring);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: cellSize * 0.22,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant FanoronaBoardPainter oldDelegate) {
    return oldDelegate.cellSize != cellSize ||
        oldDelegate.board != board ||
        oldDelegate.selectedPiece != selectedPiece ||
        oldDelegate.targets != targets ||
        oldDelegate.movingPiece != movingPiece ||
        oldDelegate.capturedAnimating != capturedAnimating ||
        oldDelegate.pendingDualChoice != pendingDualChoice ||
        oldDelegate.highlightFrom != highlightFrom ||
        oldDelegate.highlightTo != highlightTo;
  }
}
