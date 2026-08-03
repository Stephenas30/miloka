import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:miloka/game/domino/domino_block_engine.dart';
import 'package:miloka/game/domino/domino_engine.dart';
import 'package:miloka/providers/auth_provider.dart';
import 'package:miloka/service/domino_multiplayer_service.dart';
import 'package:provider/provider.dart';

import 'home_screen.dart';

class DominoScreen extends StatefulWidget {
  final bool beginGame;
  final List<Map<String, dynamic>> playerSubscribe;
  final bool isHost;
  final String roomCode;

  const DominoScreen({
    super.key,
    this.beginGame = false,
    this.playerSubscribe = const [],
    this.isHost = false,
    this.roomCode = '',
  });

  @override
  State<DominoScreen> createState() => _DominoScreenState();
}

enum _OnlinePhase { none, host, guest }

enum _DominoVariant { draw, block }

class _DominoScreenState extends State<DominoScreen> {
  DominoEngine? _engine;
  Timer? _aiTimer;
  bool _aiPlaying = false;
  bool _winnerDialogShown = false;

  bool _isMultiplayer = false;
  bool isHost = true;
  String _roomCode = '';
  String _playerName = '';
  _DominoVariant _variant = _DominoVariant.block;

  StreamSubscription<Map<String, dynamic>>? _multiplayerSubscription;
  final DominoMultiplayerService _multiplayerService =
      DominoMultiplayerService();

  _OnlinePhase _onlinePhase = _OnlinePhase.none;
  String _myUserId = '';

  dynamic _userProfile;

  @override
  void initState() {
    super.initState();
    _userProfile = context.read<AuthProvider?>()?.userProfile;
    _myUserId = _userProfile?['id']?.toString() ?? '';
    _playerName =
        _userProfile?['username']?.toString() ?? 'Joueur';
    if (widget.beginGame) {
      _isMultiplayer = true;
      isHost = widget.isHost;
      _roomCode = widget.roomCode.isEmpty
          ? DominoEngine.randomRoomCode()
          : widget.roomCode;
      _setupOnlineEngine(
        playerId: _myUserId,
        playerName: _playerName,
      );
      _startWatching();
    }
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    _multiplayerSubscription?.cancel();
    if (_isMultiplayer && _roomCode.isNotEmpty) {
      if (isHost) {
        _multiplayerService.sendGameEnded(_roomCode);
      } else {
        _multiplayerService.sendPlayerLeft(
          _roomCode,
          _myUserId,
          _playerName,
        );
      }
      _multiplayerService.disposeRoom(_roomCode);
    }
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Gestion du mode En ligne (onBroadcast Supabase, comme Ludo)
  // ---------------------------------------------------------------

  Future<void> _createOnlineRoom() async {
    final code = DominoEngine.randomRoomCode();
    await _multiplayerService.createRoom(
      roomCode: code,
      playerId: _myUserId,
      playerName: _playerName,
    );
    if (!mounted) return;
    setState(() {
      _roomCode = code;
      _onlinePhase = _OnlinePhase.host;
      _isMultiplayer = true;
      isHost = true;
    });
    _startWatching();
  }

  Future<void> _joinOnlineRoom(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) return;
    await _multiplayerService.joinRoom(
      roomCode: trimmed,
      playerId: _myUserId,
      playerName: _playerName,
    );
    if (!mounted) return;
    setState(() {
      _roomCode = trimmed;
      _onlinePhase = _OnlinePhase.guest;
      _isMultiplayer = true;
      isHost = false;
    });
    _startWatching();
  }

  void _startWatching() {
    _multiplayerSubscription?.cancel();
    _multiplayerSubscription =
        _multiplayerService.watchRoom(_roomCode).listen((payload) {
      if (!mounted) return;
      final type = payload['type']?.toString();
      if (type == 'presence' || type == 'participants') {
        if (_onlinePhase != _OnlinePhase.none) setState(() {});
        return;
      }
      if (type == 'start') return;
      if (type == 'game_ended') {
        _handleGameEnded();
        return;
      }
      if (type == 'player_left') {
        _handlePlayerLeft(payload);
        return;
      }
      _handleStatePayload(payload);
    });
  }

  void _handleStatePayload(Map<String, dynamic> payload) {
    if (_engine == null) {
      final snapshot = DominoSnapshot.fromJson(payload);
      _setupOnlineEngineFromSnapshot(snapshot);
      if (!mounted) return;
      setState(() {
        _onlinePhase = _OnlinePhase.none;
        _beginGame = true;
      });
      return;
    }
    final snapshot = DominoSnapshot.fromJson(payload);
    if (_engine!.variant != snapshot.variant) {
      _ensureEngineVariant(snapshot);
      if (!mounted) return;
    }
    setState(() {
      _engine!.applySnapshot(DominoSnapshot.fromJson(payload));
    });
    if (isHost) _scheduleAiTurn();
  }

  void _setupOnlineEngine({
    required String playerId,
    required String playerName,
  }) {
    _engine = _newEngine(
      players: [
        DominoHuman(id: playerId, name: playerName),
      ],
      isMultiplayer: true,
      roomCode: _roomCode,
    );
  }

  /// Construit le moteur adapté à la variante (Draw ou Bloc).
  DominoEngine _newEngine({
    required List<DominoHuman> players,
    bool isMultiplayer = false,
    String roomCode = '',
    String? variant,
    void Function(DominoSnapshot snapshot)? onStateChange,
  }) {
    final isBlock =
        (variant ?? (_variant == _DominoVariant.block ? 'block' : 'draw')) ==
            'block';
    if (isBlock) {
      return DominoBlockEngine(
        human: players,
        isMultiplayer: isMultiplayer,
        roomCode: roomCode,
        onStateChange: onStateChange,
      );
    }
    return DominoEngine(
      human: players,
      isMultiplayer: isMultiplayer,
      roomCode: roomCode,
      onStateChange: onStateChange,
    );
  }

  /// Recrée le moteur dans la bonne variante si elle diffère de celle reçue.
  void _ensureEngineVariant(DominoSnapshot snapshot) {
    final engine = _engine;
    if (engine != null && engine.variant != snapshot.variant) {
      _engine = null;
      _setupOnlineEngineFromSnapshot(snapshot);
    }
  }

  void _sendStateChange(DominoSnapshot snapshot) {
    _multiplayerService.sendState(_roomCode, snapshot.toJson(), true);
  }

  void _setupOnlineEngineFromSnapshot(DominoSnapshot snapshot) {
    final humans = <DominoHuman>[
      for (var i = 0; i < snapshot.playerNames.length; i++)
        DominoHuman(
          id: i < snapshot.playerIds.length ? snapshot.playerIds[i] : null,
          name: snapshot.playerNames[i],
        ),
    ];
    _engine = _newEngine(
      players: humans,
      isMultiplayer: true,
      roomCode: _roomCode,
      variant: snapshot.variant,
      onStateChange: _sendStateChange,
    );
    _engine!.applySnapshot(snapshot);
    _playerName = snapshot.playerIds.contains(_myUserId)
        ? snapshot.playerNames[snapshot.playerIds.indexOf(_myUserId)]
        : _playerName;
  }

  Future<void> _hostStartGame() async {
    final participants = _multiplayerService.getParticipants(_roomCode);
    if (participants.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attends au moins un adversaire !')),
      );
      return;
    }
    _multiplayerService.sendParticipants(_roomCode, participants);
    final humans = <DominoHuman>[
      for (final p in participants)
        DominoHuman(
          id: p['id']?.toString() ?? '',
          name: p['name']?.toString() ?? 'Joueur',
        ),
    ];
    _engine = _newEngine(
      players: humans,
      isMultiplayer: true,
      roomCode: _roomCode,
      onStateChange: _sendStateChange,
    );
    _engine!.start();
    _multiplayerService.sendGameStart(_roomCode);
    // Diffuse l'état initial
    _multiplayerService.sendState(
      _roomCode,
      _engine!.snapshot().toJson(),
      true,
    );
    if (!mounted) return;
    setState(() {
      _onlinePhase = _OnlinePhase.none;
      _beginGame = true;
    });
    _scheduleAiTurn();
  }

  // ---------------------------------------------------------------
  // Modes locaux
  // ---------------------------------------------------------------

  void _startLocalGame({required int players, int aiPlayers = 0}) {
    final humans = <DominoHuman>[
      for (var i = 0; i < players; i++)
        DominoHuman(
          id: i == 0 ? null : 'local_$i',
          name: i == 0 ? 'Joueur' : 'Joueur ${i + 1}',
        ),
      for (var i = 0; i < aiPlayers; i++)
        DominoHuman(id: 'ai_$i', name: 'Robot ${i + 1}'),
    ];
    setState(() {
      _engine = _newEngine(players: humans);
      _engine!.start();
      _beginGame = true;
    });
    _scheduleAiTurn();
  }

  // ---------------------------------------------------------------
  // Boucle de tour
  // ---------------------------------------------------------------

  bool _beginGame = false;

  bool get _isMyTurn {
    final engine = _engine;
    if (engine == null || engine.gameOver) return false;
    if (!engine.currentPlayer.isHuman) return false;
    if (!engine.isMultiplayer) return true;
    return engine.currentPlayer.id == _myUserId;
  }

  void _afterLocalAction() {
    if (!mounted) return;
    setState(() {});
    if (_engine == null || _engine!.gameOver) return;
    if (isHost || !_engine!.isMultiplayer) _scheduleAiTurn();
  }

  void _scheduleAiTurn() {
    final engine = _engine;
    if (!mounted || engine == null) return;
    if (engine.gameOver) return;
    if (engine.currentPlayer.isHuman) return;
    if (_aiTimer != null && _aiTimer!.isActive) return;
    if (_aiPlaying) return;
    _aiTimer = Timer(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      _aiPlaying = true;
      _aiTimer = null;
      engine.aiTurn();
      _aiPlaying = false;
      _afterLocalAction();
      _scheduleAiTurn();
    });
  }

  void _onTileTap(DominoTile tile) {
    final engine = _engine;
    if (engine == null) return;
    if (!_isMyTurn || engine.waitingForRemote) return;
    if (!engine.currentPlayableTiles.contains(tile)) return;

    final sides = engine.validSidesFor(tile);
    if (sides.length == 1) {
      engine.playTile(tile, sides.first);
      _afterLocalAction();
    } else {
      _showSidePicker(tile);
    }
  }

  void _showSidePicker(DominoTile tile) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C2E),
        title: const Text(
          'Choisis un côté',
          style: TextStyle(color: Colors.white),
        ),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _playOnSide(tile, DominoSide.left);
              },
              child: const Text('À gauche', style: TextStyle(color: Colors.amber)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _playOnSide(tile, DominoSide.right);
              },
              child: const Text('À droite', style: TextStyle(color: Colors.amber)),
            ),
          ],
        ),
      ),
    );
  }

  void _playOnSide(DominoTile tile, DominoSide side) {
    final engine = _engine;
    if (engine == null) return;
    engine.playTile(tile, side);
    _afterLocalAction();
  }

  void _onDraw() {
    final engine = _engine;
    if (engine == null) return;
    if (!_isMyTurn || engine.waitingForRemote) return;
    if (engine.currentPlayableTiles.isNotEmpty || !engine.canDraw) return;
    engine.drawFromBoneyard();
    _afterLocalAction();
  }

  void _onPass() {
    final engine = _engine;
    if (engine == null) return;
    if (!_isMyTurn || engine.waitingForRemote) return;
    if (!engine.canPass) return;
    engine.passTurn();
    _afterLocalAction();
  }

  // ---------------------------------------------------------------
  // Événements réseau
  // ---------------------------------------------------------------

  void _handlePlayerLeft(Map<String, dynamic> payload) {
    if (!mounted) return;
    final name = payload['player']?.toString() ?? 'Un joueur';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name a quitté la partie.')),
    );
  }

  void _handleGameEnded() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Partie terminée', style: TextStyle(color: Colors.white)),
        content: const Text(
          'La partie a été interrompue.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _quitToHome();
            },
            child: const Text('OK', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  void _quitToHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => route.isFirst,
    );
  }

  // ---------------------------------------------------------------
  // Fin de partie
  // ---------------------------------------------------------------

  void _maybeShowWinner() {
    final engine = _engine;
    if (engine == null || !engine.gameOver || _winnerDialogShown) return;
    _winnerDialogShown = true;
    final winner = engine.winnerIndex == null
        ? null
        : engine.players[engine.winnerIndex!];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          title: const Text('Fin de partie', style: TextStyle(color: Colors.white)),
          content: Text(
            winner == null
                ? 'Personne ne gagne...'
                : '${winner.name} a gagné !',
            style: const TextStyle(color: Colors.white70, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _quitToHome();
              },
              child: const Text('Quitter', style: TextStyle(color: Colors.amber)),
            ),
          ],
        ),
      );
    });
  }

  // ---------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_beginGame && _engine != null) {
      _maybeShowWinner();
      return Scaffold(
        backgroundColor: const Color(0xFF16213E),
        body: SafeArea(child: _buildGame()),
      );
    }

    if (_onlinePhase != _OnlinePhase.none) {
      return Scaffold(
        backgroundColor: const Color(0xFF16213E),
        body: SafeArea(child: _buildOnlineLobby()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF16213E),
      body: SafeArea(child: _buildMenu()),
    );
  }

  Widget _buildMenu() {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '🁫 Dominos',
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(color: Colors.black87, blurRadius: 12),
                    Shadow(color: Color(0xFFD4A017), blurRadius: 20),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFD4A017).withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  '🎲 Draw Dominoes',
                  style: TextStyle(
                    color: Color(0xFFD4A017),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildVariantSelector(),
              const SizedBox(height: 24),
              _buildGameChip('Solo', Icons.person, _showSoloDialog),
              const SizedBox(height: 16),
              _buildGameChip('Local', Icons.people, _showLocalDialog),
              const SizedBox(height: 16),
              _buildGameChip('En ligne', Icons.wifi, _showOnlineDialog),
            ],
          ),
        ),
        Positioned(
          bottom: 20,
          left: 16,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: Colors.black.withValues(alpha: 0.6),
            shape: const CircleBorder(),
            onPressed: _quitToHome,
            child: const Icon(Icons.arrow_back, color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Widget _buildVariantSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final variant in _DominoVariant.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(
                  variant == _DominoVariant.draw ? 'Draw' : 'Bloc',
                ),
                selected: _variant == variant,
                onSelected: (_) =>
                    setState(() => _variant = variant),
                backgroundColor: Colors.white10,
                selectedColor: const Color(0xFFD4A017),
                labelStyle: TextStyle(
                  color: _variant == variant
                      ? Colors.black
                      : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGameChip(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        height: 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFD4A017).withValues(alpha: 0.8),
              const Color(0xFFD4A017).withValues(alpha: 0.4),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4A017).withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
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
                fontSize: 20,
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

  void _showSoloDialog() {
    var robots = 2;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C2E),
          title: const Text('Solo', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Nombre d\'adversaires robots',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var n = 1; n <= 3; n++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: ChoiceChip(
                        label: Text('$n'),
                        selected: robots == n,
                        onSelected: (_) => setDialogState(() => robots = n),
                        backgroundColor: Colors.white10,
                        selectedColor: const Color(0xFFD4A017),
                        labelStyle: const TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _startLocalGame(players: 1, aiPlayers: robots);
              },
              child: const Text('C\'est parti !', style: TextStyle(color: Colors.amber)),
            ),
          ],
        ),
      ),
    );
  }

  void _showLocalDialog() {
    var players = 2;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C2E),
          title: const Text('Local', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Nombre de joueurs',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var n = 2; n <= 4; n++)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: ChoiceChip(
                        label: Text('$n'),
                        selected: players == n,
                        onSelected: (_) => setDialogState(() => players = n),
                        backgroundColor: Colors.white10,
                        selectedColor: const Color(0xFFD4A017),
                        labelStyle: const TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _startLocalGame(players: players);
              },
              child: const Text('C\'est parti !', style: TextStyle(color: Colors.amber)),
            ),
          ],
        ),
      ),
    );
  }

  void _showOnlineDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C2E),
        title: const Text('En ligne', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _createOnlineRoom();
              },
              icon: const Icon(Icons.add),
              label: const Text('Créer une partie'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showJoinDialog();
              },
              icon: const Icon(Icons.login),
              label: const Text('Rejoindre avec un code'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
            ),
          ],
        ),
      ),
    );
  }

  void _showJoinDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C2E),
        title: const Text('Rejoindre une partie', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white, letterSpacing: 4),
          decoration: const InputDecoration(
            hintText: 'CODE',
            hintStyle: TextStyle(color: Colors.white38, letterSpacing: 4),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final code = controller.text.trim().toUpperCase();
              Navigator.pop(ctx);
              if (code.isNotEmpty) _joinOnlineRoom(code);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('Rejoindre'),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineLobby() {
    final isHost = _onlinePhase == _OnlinePhase.host;
    final participants = _roomCode.isEmpty
        ? <Map<String, dynamic>>[]
        : _multiplayerService.getParticipants(_roomCode);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            isHost ? 'Salle : $_roomCode' : 'Rejoins la salle $_roomCode',
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Mode : ${_variant == _DominoVariant.draw ? 'Draw' : 'Bloc'}',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          if (isHost) ...[
            const SizedBox(height: 8),
            Text(
              'Partage ce code avec tes amis',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _roomCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copié !')),
                );
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copier le code'),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Participants',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${participants.length}',
                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: participants.length,
              itemBuilder: (ctx, i) {
                final p = participants[i];
                final name = p['name']?.toString() ?? 'Joueur';
                final isMe = p['id']?.toString() == _myUserId;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFD4A017).withValues(alpha: 0.3),
                    child: Icon(
                      isMe ? Icons.person : Icons.person_outline,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    isMe ? '$name (toi)' : name,
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          if (isHost)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: participants.length >= 2 ? _hostStartGame : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Démarrer la partie'),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'En attente que l\'hôte démarre la partie...',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _quitToHome,
            child: const Text('Quitter', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  Widget _buildGame() {
    final engine = _engine!;
    return Column(
      children: [
        _buildHeader(engine),
        _buildOpponents(engine),
        Expanded(child: _buildBoard(engine)),
        _buildActions(engine),
        _buildMyHand(engine),
      ],
    );
  }

  Widget _buildHeader(DominoEngine engine) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Icon(
              engine.currentPlayer.isHuman ? Icons.person : Icons.smart_toy,
              color: Colors.amber,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                engine.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpponents(DominoEngine engine) {
    final others = [
      for (var i = 0; i < engine.players.length; i++)
        if (engine.players[i].id != _myUserId) engine.players[i],
    ];
    if (others.isEmpty) {
      return const SizedBox(height: 8);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          for (final p in others) ...[
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.tileCount} tuile(s)',
                      style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            if (p != others.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildBoard(DominoEngine engine) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            if (engine.played.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'La partie commence...',
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              )
            else
              for (final tile in engine.played)
                _DominoTileWidget(tile: tile, width: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(DominoEngine engine) {
    final isBlock = engine.variant == 'block';
    final canDraw =
        !isBlock && _isMyTurn && engine.canDraw && engine.currentPlayableTiles.isEmpty;
    final canPass = _isMyTurn && engine.canPass;
    if (!_isMyTurn) {
      return const SizedBox(height: 8);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          if (!isBlock) ...[
            Expanded(
              child: ElevatedButton.icon(
                onPressed: canDraw ? _onDraw : null,
                icon: const Icon(Icons.swap_vert, size: 18),
                label: Text('Pioche (${engine.boneyardCount})'),
                style:
                    ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: ElevatedButton.icon(
              onPressed: canPass ? _onPass : null,
              icon: const Icon(Icons.skip_next, size: 18),
              label: Text(isBlock ? 'Passer (bloqué)' : 'Passer'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyHand(DominoEngine engine) {
    final current = engine.currentPlayer;
    final isMyTurn = _isMyTurn;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                isMyTurn ? 'À toi de jouer !' : 'Tour de ${current.name}',
                style: TextStyle(
                  color: isMyTurn ? const Color(0xFFD4A017) : Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (engine.variant != 'block')
                Text(
                  'Bac : ${engine.boneyardCount}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tile in engine.currentPlayer.hand) ...[
                  GestureDetector(
                    onTap: isMyTurn && engine.currentPlayableTiles.contains(tile)
                        ? () => _onTileTap(tile)
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      transform: Matrix4.identity()
                        ..translateByDouble(0.0, isMyTurn && engine.currentPlayableTiles.contains(tile) ? -4.0 : 0.0, 0.0, 1.0),
                      child: _DominoTileWidget(tile: tile, width: 36),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DominoTileWidget extends StatelessWidget {
  final DominoTile tile;
  final double width;

  const _DominoTileWidget({required this.tile, required this.width});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, width * 2),
      painter: _DominoTilePainter(left: tile.left, right: tile.right),
    );
  }
}

class _DominoTilePainter extends CustomPainter {
  final int left;
  final int right;

  _DominoTilePainter({required this.left, required this.right});

  static const Map<int, List<(int, int)>> _pipLayouts = {
    0: [],
    1: [(1, 1)],
    2: [(0, 0), (2, 2)],
    3: [(0, 0), (1, 1), (2, 2)],
    4: [(0, 0), (0, 2), (2, 0), (2, 2)],
    5: [(0, 0), (0, 2), (1, 1), (2, 0), (2, 2)],
    6: [(0, 0), (0, 2), (1, 0), (1, 2), (2, 0), (2, 2)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    final bg = Paint()..color = const Color(0xFFF5F1E8);
    canvas.drawRRect(rrect, bg);

    final border = Paint()
      ..color = const Color(0xFF3A3A3A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRRect(rrect, border);

    final divider = Paint()
      ..color = const Color(0xFF3A3A3A)
      ..strokeWidth = 1.2;
    final midY = size.height / 2;
    canvas.drawLine(
      Offset(2, midY),
      Offset(size.width - 2, midY),
      divider,
    );

    final pipPaint = Paint()..color = const Color(0xFF2B2B2B);
    final halfHeight = size.height / 2;
    final pipRadius = size.width * 0.09;

    void drawPips(int value, double yOffset) {
      for (final (row, col) in _pipLayouts[value] ?? const <(int, int)>[]) {
        final x = size.width * (0.25 + col * 0.25);
        final y = yOffset + halfHeight * (0.25 + row * 0.25);
        canvas.drawCircle(Offset(x, y), pipRadius, pipPaint);
      }
    }

    drawPips(left, 0);
    drawPips(right, halfHeight);
  }

  @override
  bool shouldRepaint(covariant _DominoTilePainter oldDelegate) {
    return oldDelegate.left != left || oldDelegate.right != right;
  }
}