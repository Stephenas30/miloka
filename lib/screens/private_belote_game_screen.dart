import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../game/belote_game_logic.dart';
import '../game/belote_rules.dart';
import '../game/call_system.dart';
import '../models/card_model.dart';
import '../game/played_card.dart';
import '../service/game_channel_service.dart';
import '../service/private_match_service.dart';
import '../service/supabase_service.dart';
import '../providers/auth_provider.dart';
import '../utils/image_cache.dart';
import '../widgets/call_popup.dart';
import 'classic_team_lobby_screen.dart';
import 'private_game_lobby_screen.dart';

class PrivateBeloteGameScreen extends StatefulWidget {
  final String matchCode;
  final String localPosition;
  final Map<String, String> playerNames;
  final Map<String, String> playerAvatars;
  final Map<String, String> playerIds;
  final int bet;

  const PrivateBeloteGameScreen({
    super.key,
    required this.matchCode,
    required this.localPosition,
    required this.playerNames,
    required this.playerAvatars,
    this.playerIds = const {},
    this.bet = 0,
  });

  @override
  State<PrivateBeloteGameScreen> createState() => _PrivateBeloteGameScreenState();
}

class _PrivateBeloteGameScreenState extends State<PrivateBeloteGameScreen> {
  final GameChannelService _gameChannel = GameChannelService();
  late BeloteGameLogic gameLogic;

  static const List<String> allPlayers = ['Sud', 'Est', 'Nord', 'Ouest'];

  bool _gameInitialized = false;
  bool _gameStarted = false;
  bool _gameOver = false;
  bool _guestDealing = false;
  bool _isPlayingCard = false;
  String? _winningTeam;
  String _statusText = 'Initialisation...';
  bool showCallBubble = false;
  String callBubblePlayer = '';
  String callBubbleText = '';

  StreamSubscription<Map<String, dynamic>>? _subscription;
  StreamSubscription<Map<String, dynamic>>? _matchSubscription;

  // Hand result flow
  bool _handResultActive = false;
  Map<String, int>? _handResultDeltas;
  Set<String> _confirmedPlayers = {};
  int _handResultCountdown = 10;
  Timer? _handResultTimer;

  // Bidding timer
  int _bidTimerSeconds = 0;
  Timer? _bidTimer;
  bool _callMade = false;

  bool get _isDealer => widget.localPosition == 'Sud';

  Timer? _syncTimer;
  Timer? _inactivityTimer;
  Timer? _inactivityWarningTimer;
  bool _isWarningShown = false;

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityWarningTimer?.cancel();
    if (_isWarningShown) {
      _isWarningShown = false;
      Navigator.of(context).pop();
    }
    if (!_gameStarted || _gameOver) return;
    if (gameLogic.callSystem.currentPlayer != widget.localPosition) return;
    _inactivityTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted || _gameOver || !_gameStarted) return;
      _gameChannel.send('forfeit', {
        'player': widget.localPosition,
      });
      setState(() {
        _gameOver = true;
        _winningTeam = _teamOf(widget.localPosition) == 'NS' ? 'EO' : 'NS';
        _localWon = false;
        _winningShare = 0;
      });
      context.read<AuthProvider>().refreshProfile();
    });
    _inactivityWarningTimer = Timer(const Duration(seconds: 50), _showForfeitWarning);
  }

  void _showForfeitWarning() {
    if (!mounted || _gameOver || !_gameStarted) return;
    if (gameLogic.callSystem.currentPlayer != widget.localPosition) return;
    _isWarningShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (_) => _ForfeitWarningDialog(),
    ).whenComplete(() {
      _isWarningShown = false;
    });
  }

  void _handleForfeit(Map<String, dynamic> event) {
    final forfeitingPlayer = event['player'] as String? ?? '';
    if (forfeitingPlayer.isEmpty) return;
    final forfeitingTeam = _teamOf(forfeitingPlayer);
    final winningTeam = forfeitingTeam == 'NS' ? 'EO' : 'NS';
    _inactivityTimer?.cancel();
    _syncTimer?.cancel();
    setState(() {
      _gameOver = true;
      _winningTeam = winningTeam;
      _localWon = (winningTeam == 'NS' && (widget.localPosition == 'Sud' || widget.localPosition == 'Nord'))
          || (winningTeam == 'EO' && (widget.localPosition == 'Est' || widget.localPosition == 'Ouest'));
      _winningShare = 0;
    });
    context.read<AuthProvider>().refreshProfile();
  }

  // Counter / sur-counter phase
  String _counterPhase = 'none'; // 'none' | 'counter' | 'surcounter'
  int _counterSeconds = 0;
  Timer? _counterTimer;
  int _counterMultiplier = 1;
  String? _counterBidder;
  CallOption? _lastCall;
  String? _counterPlayer;
  bool _counterDialogShowing = false;

  bool _localWon = false;
  int _winningShare = 0;

  // ── Position helpers ──

  String _bottomPlayer() => widget.localPosition;
  String _topPlayer() => _oppositeOf(widget.localPosition);
  String _leftPlayer() => _leftOf(widget.localPosition);
  String _rightPlayer() => _rightOf(widget.localPosition);

  String _oppositeOf(String pos) {
    switch (pos) {
      case 'Sud': return 'Nord';
      case 'Nord': return 'Sud';
      case 'Est': return 'Ouest';
      case 'Ouest': return 'Est';
      default: return 'Nord';
    }
  }

  String _leftOf(String pos) {
    switch (pos) {
      case 'Sud': return 'Ouest';
      case 'Ouest': return 'Nord';
      case 'Nord': return 'Est';
      case 'Est': return 'Sud';
      default: return 'Ouest';
    }
  }

  String _rightOf(String pos) {
    switch (pos) {
      case 'Sud': return 'Est';
      case 'Est': return 'Nord';
      case 'Nord': return 'Ouest';
      case 'Ouest': return 'Sud';
      default: return 'Est';
    }
  }

  String _teamOf(String player) {
    if (player == 'Sud' || player == 'Nord') return 'NS';
    return 'EO';
  }

  bool _isOnTeam(String team) {
    return _teamOf(widget.localPosition) == team;
  }

  Alignment _trickAlignment(String player) {
    if (player == _topPlayer()) return const Alignment(0, -0.45);
    if (player == _rightPlayer()) return const Alignment(0.33, -0.05);
    if (player == _leftPlayer()) return const Alignment(-0.33, -0.05);
    return const Alignment(0, 0.45);
  }

  // ── Lifecycle ──

  @override
  void initState() {
    super.initState();
    gameLogic = BeloteGameLogic(players: List.from(allPlayers));
    _subscription = _gameChannel.events.listen(_handleEvent);
    if (_isDealer) {
      _dealInitialCards();
    } else {
      setState(() { _statusText = 'Attente des cartes...'; _guestDealing = true; });
    }
    _initMatchSubscription();
  }

  void _initMatchSubscription() {
    _matchSubscription = PrivateMatchService().subscribeToMatch(widget.matchCode).listen((match) {
      if (match['status'] == 'cancelled' && mounted) {
        _returnToTeamLobby();
      }
    });
  }

  Future<void> _returnToTeamLobby() async {
    final match = await PrivateMatchService().getMatch(widget.matchCode, forceRefresh: true);
    if (match == null) return;
    final isTeamA = widget.localPosition == 'Sud' || widget.localPosition == 'Nord';
    final teamId = isTeamA ? match['team_a_id'] as String? : match['team_b_id'] as String?;
    if (teamId == null || !mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ClassicTeamLobbyScreen(
          teamId: teamId,
          isHost: widget.localPosition == 'Sud' || widget.localPosition == 'Ouest',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _matchSubscription?.cancel();
    _handResultTimeout?.cancel();
    _counterTimer?.cancel();
    _syncTimer?.cancel();
    _inactivityTimer?.cancel();
    _inactivityWarningTimer?.cancel();
    super.dispose();
  }

  // ── Cancel match ──

  Future<bool> _confirmLeave() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmation', textAlign: TextAlign.center),
        content: const Text('Voulez-vous abandonner ?', textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oui', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _cancelMatch() {
    _gameChannel.send('cancel', {});
    _gameChannel.disconnect();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ── Serialisation ──

  Map<String, dynamic> _serializeHands() {
    return {
      'Sud': gameLogic.playerHand.map((c) => c.toMap()).toList(),
      'Nord': gameLogic.handFor('Nord').map((c) => c.toMap()).toList(),
      'Est': gameLogic.handFor('Est').map((c) => c.toMap()).toList(),
      'Ouest': gameLogic.handFor('Ouest').map((c) => c.toMap()).toList(),
    };
  }

  Map<String, List<CardModel>> _deserializeHands(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(
      key,
      (value as List).map((c) => CardModel.fromMap(c as Map<String, dynamic>)).toList(),
    ));
  }

  // ── Dealing ──

  void _dealInitialCards() {
    for (int i = 0; i < 3; i++) {
      for (final player in gameLogic.order) {
        gameLogic.giveCards(player, 1);
      }
    }
    for (int i = 0; i < 2; i++) {
      for (final player in gameLogic.order) {
        gameLogic.giveCards(player, 1);
      }
    }
    gameLogic.playerHand = BeloteRules.sortSouthHand(gameLogic.playerHand, null);
    final starterIdx = gameLogic.starterIndex;
    _gameChannel.send('init_game', {
      'hands': _serializeHands(),
      'starterIndex': starterIdx,
    });
    setState(() { _gameInitialized = true; });
    _startBidding();
  }

  void _handleInitGame(Map<String, dynamic> event) {
    final hands = _deserializeHands(event['hands'] as Map<String, dynamic>);
    final starterIdx = event['starterIndex'] as int;
    gameLogic.initializeFromHands(hands, starterIdx);
    gameLogic.playerHand = BeloteRules.sortSouthHand(gameLogic.playerHand, null);
    setState(() { _gameInitialized = true; _guestDealing = false; });
    _startBidding();
  }

  // ── Bidding ──

  void _startBidding() {
    setState(() { _statusText = 'Enchères - tour de ${_displayName(gameLogic.callSystem.currentPlayer)}'; });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && gameLogic.callSystem.currentPlayer == widget.localPosition) {
        _showCallPopup();
      }
    });
  }

  void _showCallPopup() {
    _callMade = false;
    _startBidTimer();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CallPopup(
        playerName: widget.localPosition,
        availableCalls: gameLogic.callSystem.availableCalls,
        onCall: (option) async {
          if (_callMade) return;
          _callMade = true;
          _stopBidTimer();
          gameLogic.callSystem.makeCall(option);
          _showCallBubble(widget.localPosition, option);
          _gameChannel.send('bid', {
            'player': widget.localPosition,
            'call': option.name,
          });
          if (option != CallOption.pass) {
            setState(() { _statusText = '${widget.localPosition}: ${option.name}'; });
          }
          if (gameLogic.callSystem.isFinished()) {
            await _finishBidding();
          } else if (option != CallOption.pass && option != CallOption.x2 && option != CallOption.x4) {
            _startCounterPhase(widget.localPosition, option);
          } else {
            setState(() { _statusText = 'Enchères - tour de ${_displayName(gameLogic.callSystem.currentPlayer)}'; });
            if (gameLogic.callSystem.currentPlayer == widget.localPosition) {
              _showCallPopup();
            }
          }
        },
      ),
    );
  }

  void _startBidTimer() {
    _bidTimer?.cancel();
    _bidTimerSeconds = 10;
    _bidTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _bidTimerSeconds--);
      if (_bidTimerSeconds <= 0) {
        timer.cancel();
        _onBidTimeout();
      }
    });
  }

  void _stopBidTimer() {
    _bidTimer?.cancel();
    _bidTimerSeconds = 0;
  }

  void _onBidTimeout() {
    if (_callMade) return;
    if (gameLogic.callSystem.currentPlayer != widget.localPosition) return;
    _callMade = true;
    Navigator.of(context, rootNavigator: true).pop();
    gameLogic.callSystem.makeCall(CallOption.pass);
    _showCallBubble(widget.localPosition, CallOption.pass);
    _gameChannel.send('bid', {
      'player': widget.localPosition,
      'call': 'pass',
    });
    setState(() { _statusText = '${widget.localPosition}: pass (timeout)'; });
    if (gameLogic.callSystem.isFinished()) {
      _finishBidding();
    } else {
      setState(() { _statusText = 'Enchères - tour de ${_displayName(gameLogic.callSystem.currentPlayer)}'; });
      if (gameLogic.callSystem.currentPlayer == widget.localPosition) {
        _showCallPopup();
      }
    }
  }

  void _handleBid(Map<String, dynamic> event) {
    final player = event['player'] as String;
    final callName = event['call'] as String;
    final option = CallOption.values.firstWhere((o) => o.name == callName);
    gameLogic.callSystem.makeCall(option);
    _showCallBubble(player, option);
    if (option != CallOption.pass) {
      setState(() { _statusText = '$player: ${option.name}'; });
    }
    if (gameLogic.callSystem.isFinished()) {
      _finishBidding();
    } else if (option != CallOption.pass && option != CallOption.x2 && option != CallOption.x4) {
      _startCounterPhase(player, option);
    } else {
      setState(() { _statusText = 'Enchères - tour de ${_displayName(gameLogic.callSystem.currentPlayer)}'; });
      if (gameLogic.callSystem.currentPlayer == widget.localPosition) {
        _showCallPopup();
      }
    }
  }

  // ── Counter / Sur-counter phase ──

  void _startCounterPhase(String player, CallOption option) {
    _counterPhase = 'counter';
    _counterBidder = player;
    _lastCall = option;
    _counterMultiplier = 1;
    _counterSeconds = 5;
    _counterPlayer = null;

    final opposingTeam = _teamOf(player) == 'NS' ? 'EO' : 'NS';

    setState(() {
      _statusText = '${_displayName(player)} propose ${BeloteRules.callOptionLabel(option)}';
    });

    if (_isOnTeam(opposingTeam)) {
      _showCounterPopup();
    }

    _counterTimer?.cancel();
    _counterTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_counterPhase != 'counter') { t.cancel(); return; }
      _counterSeconds--;
      if (_counterSeconds <= 0) {
        t.cancel();
        _onCounterPhaseTimeout();
      }
    });
  }

  void _onCounterPhaseTimeout() {
    if (_counterPhase != 'counter') return;
    _counterPhase = 'none';
    _counterTimer?.cancel();
    _dismissCounterDialog();

    if (_isOnTeam(_teamOf(_counterBidder!) == 'NS' ? 'EO' : 'NS')) {
      _gameChannel.send('counter_action', {
        'action': 'timeout',
        'phase': 'counter',
      });
    }
    _resolveCounterPhase();
  }

  void _onCounterMade(int multiplier) {
    _counterTimer?.cancel();
    _counterMultiplier = multiplier;
    _counterPhase = 'surcounter';
    _counterSeconds = 10;
    _counterPlayer = widget.localPosition;

    _gameChannel.send('counter_action', {
      'action': 'counter',
      'player': widget.localPosition,
      'multiplier': multiplier,
    });

    setState(() {
      _statusText = 'Contre x$multiplier par ${widget.localPosition}';
    });

    _startSurCounterPhase();
  }

  void _startSurCounterPhase() {
    if (_counterBidder == null) return;
    final bidderTeam = _teamOf(_counterBidder!);

    if (_isOnTeam(bidderTeam)) {
      _showSurCounterPopup();
    }

    _counterTimer?.cancel();
    _counterTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_counterPhase != 'surcounter') { t.cancel(); return; }
      _counterSeconds--;
      if (_counterSeconds <= 0) {
        t.cancel();
        _onSurCounterPhaseTimeout();
      }
    });
  }

  void _onSurCounterPhaseTimeout() {
    if (_counterPhase != 'surcounter') return;
    _counterPhase = 'none';
    _counterTimer?.cancel();
    _dismissCounterDialog();

    if (_isOnTeam(_teamOf(_counterBidder!))) {
      _gameChannel.send('counter_action', {
        'action': 'timeout',
        'phase': 'surcounter',
      });
    }
    _resolveCounterPhase();
  }

  void _onSurCounterMade() {
    _counterTimer?.cancel();
    _counterMultiplier *= 2;
    _counterPhase = 'none';

    _gameChannel.send('counter_action', {
      'action': 'surcounter',
      'player': widget.localPosition,
      'multiplier': _counterMultiplier,
    });

    setState(() {
      _statusText = 'Surcontré x$_counterMultiplier par ${widget.localPosition}';
    });

    _dismissCounterDialog();
    _resolveCounterPhase();
  }

  void _resolveCounterPhase() {
    _counterPhase = 'none';
    _counterTimer?.cancel();
    _dismissCounterDialog();

    if (_counterMultiplier > 1) {
      gameLogic.counterMultiplier = _counterMultiplier;
    }

    if (gameLogic.callSystem.isFinished()) {
      _finishBidding();
    } else {
      setState(() {
        _statusText = 'Enchères - tour de ${_displayName(gameLogic.callSystem.currentPlayer)}';
      });
      if (gameLogic.callSystem.currentPlayer == widget.localPosition) {
        _showCallPopup();
      }
    }
  }

  void _dismissCounterDialog() {
    if (_counterDialogShowing && mounted) {
      _counterDialogShowing = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _handleCounterAction(Map<String, dynamic> event) {
    final action = event['action'] as String?;

    if (action == 'counter' && _counterPhase != 'counter') return;
    if (action == 'surcounter' && _counterPhase != 'surcounter') return;

    _counterTimer?.cancel();
    _dismissCounterDialog();

    switch (action) {
      case 'counter':
        _counterMultiplier = event['multiplier'] as int? ?? 2;
        _counterPhase = 'surcounter';
        _counterSeconds = 10;
        _counterPlayer = event['player'] as String?;
        setState(() {
          _statusText = 'Contre x${_counterMultiplier} par ${_counterPlayer}';
        });
        if (_counterBidder != null) {
          final bidderTeam = _teamOf(_counterBidder!);
          if (_isOnTeam(bidderTeam)) {
            _startSurCounterPhase();
            _showSurCounterPopup();
          }
        }
        break;
      case 'surcounter':
        _counterMultiplier = event['multiplier'] as int? ?? 4;
        _counterPhase = 'none';
        setState(() {
          _statusText = 'Surcontré x${_counterMultiplier} par ${event['player']}';
        });
        _resolveCounterPhase();
        break;
      case 'timeout':
        _counterPhase = 'none';
        _resolveCounterPhase();
        break;
    }
  }

  void _showCounterPopup() {
    if (!mounted) return;
    _counterDialogShowing = true;

    final notifier = ValueNotifier<int>(_counterSeconds);
    final timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      notifier.value--;
      if (notifier.value <= 0) {
        t.cancel();
        if (_counterDialogShowing) {
          _counterDialogShowing = false;
          Navigator.of(context, rootNavigator: true).pop();
          _onCounterPhaseTimeout();
        }
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: ValueListenableBuilder<int>(
          valueListenable: notifier,
          builder: (context, seconds, _) => AlertDialog(
            title: Row(
              children: [
                const Text('Contre', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${seconds}s', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: seconds <= 3 ? Colors.red : Colors.black)),
              ],
            ),
            content: Text('${_displayName(_counterBidder!)} propose ${BeloteRules.callOptionLabel(_lastCall!)}'),
            actions: [
              TextButton(
                onPressed: seconds > 0
                    ? () {
                        timer.cancel();
                        _counterDialogShowing = false;
                        Navigator.pop(ctx);
                        _onCounterMade(2);
                      }
                    : null,
                child: const Text('x2', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: seconds > 0
                    ? () {
                        timer.cancel();
                        _counterDialogShowing = false;
                        Navigator.pop(ctx);
                        _onCounterMade(4);
                      }
                    : null,
                child: const Text('x4', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: seconds > 0
                    ? () {
                        timer.cancel();
                        _counterDialogShowing = false;
                        Navigator.pop(ctx);
                        _onCounterPhaseTimeout();
                      }
                    : null,
                child: const Text('Passer'),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _counterDialogShowing = false);
  }

  void _showSurCounterPopup() {
    if (!mounted) return;
    _counterDialogShowing = true;

    final notifier = ValueNotifier<int>(_counterSeconds);
    final timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      notifier.value--;
      if (notifier.value <= 0) {
        t.cancel();
        if (_counterDialogShowing) {
          _counterDialogShowing = false;
          Navigator.of(context, rootNavigator: true).pop();
          _onSurCounterPhaseTimeout();
        }
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: ValueListenableBuilder<int>(
          valueListenable: notifier,
          builder: (context, seconds, _) => AlertDialog(
            title: Row(
              children: [
                const Text('Surcontrer ?', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${seconds}s', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: seconds <= 3 ? Colors.red : Colors.black)),
              ],
            ),
            content: Text('Contre x$_counterMultiplier par ${_counterPlayer ?? "?"}'),
            actions: [
              TextButton(
                onPressed: seconds > 0
                    ? () {
                        timer.cancel();
                        _counterDialogShowing = false;
                        Navigator.pop(ctx);
                        _onSurCounterMade();
                      }
                    : null,
                child: const Text('Surcontrer', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: seconds > 0
                    ? () {
                        timer.cancel();
                        _counterDialogShowing = false;
                        Navigator.pop(ctx);
                        _onSurCounterPhaseTimeout();
                      }
                    : null,
                child: const Text('Passer'),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => _counterDialogShowing = false);
  }

  void _sortAllHands() {
    final contract = gameLogic.callSystem.contractCall;
    gameLogic.playerHand = BeloteRules.sortSouthHand(gameLogic.playerHand, contract);
    gameLogic.aiHands[0] = BeloteRules.sortSouthHand(gameLogic.aiHands[0], contract);
    gameLogic.aiHands[1] = BeloteRules.sortSouthHand(gameLogic.aiHands[1], contract);
    gameLogic.aiHands[2] = BeloteRules.sortSouthHand(gameLogic.aiHands[2], contract);
  }

  Future<void> _finishBidding() async {
    final contract = gameLogic.callSystem.contractCall;
    if (contract == null) return;

    if (_isDealer) {
      setState(() => _guestDealing = true);
      for (int i = 0; i < 3; i++) {
        for (final player in gameLogic.order) {
          gameLogic.giveCards(player, 1);
        }
      }
      _sortAllHands();
      _gameChannel.send('final_deal', {'hands': _serializeHands()});
    }

    setState(() {
      _guestDealing = false;
      _statusText = 'Contrat: ${BeloteRules.callOptionLabel(contract)} par ${gameLogic.callSystem.contractWinner}';
    });

    if (_isDealer) {
      gameLogic.callSystem.setCurrentPlayer(gameLogic.players[gameLogic.starterIndex]);
      _startGame();
    }
  }

  void _handleFinalDeal(Map<String, dynamic> event) {
    final hands = _deserializeHands(event['hands'] as Map<String, dynamic>);

    gameLogic.playerHand = List.from(hands['Sud'] ?? []);
    gameLogic.aiHands[0] = List.from(hands['Nord'] ?? []);
    gameLogic.aiHands[1] = List.from(hands['Est'] ?? []);
    gameLogic.aiHands[2] = List.from(hands['Ouest'] ?? []);

    _sortAllHands();

    final contract = gameLogic.callSystem.contractCall;
    setState(() {
      _guestDealing = false;
      _statusText = 'Contrat: ${contract != null ? BeloteRules.callOptionLabel(contract) : '?'} par ${gameLogic.callSystem.contractWinner}';
    });

    gameLogic.callSystem.setCurrentPlayer(gameLogic.players[gameLogic.starterIndex]);
    _startGame();
  }

  // ── Gameplay ──

  void _startGame() {
    setState(() {
      _gameStarted = true;
      _statusText = 'Au tour de ${_displayName(gameLogic.callSystem.currentPlayer)}';
    });
    _resetInactivityTimer();
  }

  void _restartSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted || _gameOver || !_gameStarted) return;
      if (gameLogic.currentTrick.length == 4) return;
      _requestSync();
    });
  }

  void _requestSync() {
    _gameChannel.send('request_sync', {
      'player': widget.localPosition,
    });
  }

  void _sendStateSync() {
    _gameChannel.send('state_sync', {
      'current_trick': gameLogic.currentTrick.map((pc) => {
        'player': pc.player,
        'card': pc.card.toMap(),
      }).toList(),
      'current_player': gameLogic.callSystem.currentPlayer,
      'tricks_played': gameLogic.tricksPlayed,
      'team_points_ns': gameLogic.teamPoints['NS'],
      'team_points_eo': gameLogic.teamPoints['EO'],
      'game_score_ns': gameLogic.gameScore['NS'],
      'game_score_eo': gameLogic.gameScore['EO'],
      'ai_hands_est': gameLogic.aiHands[1].map((c) => c.toMap()).toList(),
      'ai_hands_ouest': gameLogic.aiHands[2].map((c) => c.toMap()).toList(),
      'player_hand_sud': gameLogic.playerHand.map((c) => c.toMap()).toList(),
      'ai_hands_nord': gameLogic.aiHands[0].map((c) => c.toMap()).toList(),
    });
  }

  void _applyStateSync(Map<String, dynamic> data) {
    final trickList = (data['current_trick'] as List?) ?? [];
    final newTrick = trickList.map((e) {
      final eMap = Map<String, dynamic>.from(e);
      return PlayedCard(
        eMap['player'] as String,
        CardModel.fromMap(Map<String, dynamic>.from(eMap['card'])),
      );
    }).toList();

    final currentPlayer = data['current_player'] as String? ?? gameLogic.callSystem.currentPlayer;

    setState(() {
      gameLogic.currentTrick = newTrick;
      gameLogic.callSystem.setCurrentPlayer(currentPlayer);
      gameLogic.tricksPlayed = (data['tricks_played'] as num?)?.toInt() ?? gameLogic.tricksPlayed;
      gameLogic.teamPoints = {
        'NS': (data['team_points_ns'] as num?)?.toInt() ?? 0,
        'EO': (data['team_points_eo'] as num?)?.toInt() ?? 0,
      };
      gameLogic.gameScore = {
        'NS': (data['game_score_ns'] as num?)?.toInt() ?? 0,
        'EO': (data['game_score_eo'] as num?)?.toInt() ?? 0,
      };
      if (data['ai_hands_est'] != null) {
        gameLogic.aiHands[1] = (data['ai_hands_est'] as List).map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
      }
      if (data['ai_hands_ouest'] != null) {
        gameLogic.aiHands[2] = (data['ai_hands_ouest'] as List).map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
      }
      if (data['player_hand_sud'] != null) {
        gameLogic.playerHand = (data['player_hand_sud'] as List).map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
      }
      if (data['ai_hands_nord'] != null) {
        gameLogic.aiHands[0] = (data['ai_hands_nord'] as List).map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
      }
    });
  }

  void _playCard(CardModel card) {
    if (_isPlayingCard) return;
    if (!_gameStarted || _gameOver) return;
    if (gameLogic.currentTrick.length == 4) return;
    if (gameLogic.callSystem.currentPlayer != widget.localPosition) return;
    if (!gameLogic.canPlayCard(card, player: widget.localPosition)) return;

    _isPlayingCard = true;
    final hand = gameLogic.handFor(widget.localPosition);
    hand.remove(card);
    gameLogic.currentTrick.add(PlayedCard(widget.localPosition, card));
    gameLogic.callSystem.nextTurn();

    _gameChannel.send('play_card', {
      'player': widget.localPosition,
      'card': card.toMap(),
    });

    setState(() {
      _isPlayingCard = false;
      if (gameLogic.currentTrick.length == 4) {
        _resolveTrick();
      } else {
        _statusText = 'Au tour de ${_displayName(gameLogic.callSystem.currentPlayer)}';
      }
    });
    _restartSyncTimer();
    _resetInactivityTimer();
  }

  void _handleCardPlayed(Map<String, dynamic> event) {
    if (gameLogic.currentTrick.length == 4) return;
    final player = event['player'] as String;
    final card = CardModel.fromMap(event['card'] as Map<String, dynamic>);

    final hand = gameLogic.handFor(player);
    hand.remove(card);
    gameLogic.currentTrick.add(PlayedCard(player, card));
    gameLogic.callSystem.nextTurn();

    setState(() {
      if (gameLogic.currentTrick.length == 4) {
        _resolveTrick();
      } else {
        _statusText = 'Au tour de ${_displayName(gameLogic.callSystem.currentPlayer)}';
      }
    });
    _restartSyncTimer();
    _resetInactivityTimer();
    if (_isDealer) _sendStateSync();
  }

  Timer? _handResultTimeout;

  void _resolveTrick() {
    setState(() { _statusText = 'Plie en cours...'; });
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      gameLogic.resolveTrick();
      final totalTricks = gameLogic.tricksPlayed;
    setState(() {
      if (totalTricks >= 8) {
        if (_isDealer) {
          _finishHand();
        } else {
          _statusText = 'Fin de la manche...';
          _handResultTimeout = Timer(const Duration(seconds: 10), () {
            if (!mounted || _handResultActive) return;
            _finishHand();
          });
        }
      } else {
        _statusText = 'Plie remportée par ${_displayName(gameLogic.callSystem.currentPlayer)}';
      }
    });
    });
  }

  void _finishHand() {
    final deltas = gameLogic.computeHandScores();
    gameLogic.gameScore['NS'] = (gameLogic.gameScore['NS'] ?? 0) + (deltas['NS'] ?? 0);
    gameLogic.gameScore['EO'] = (gameLogic.gameScore['EO'] ?? 0) + (deltas['EO'] ?? 0);
    gameLogic.lastHandDelta = deltas;

    final nsTotal = gameLogic.gameScore['NS'] ?? 0;
    final eoTotal = gameLogic.gameScore['EO'] ?? 0;

    if (nsTotal >= 150 || eoTotal >= 150) {
      final winningTeam = nsTotal >= 150 ? 'NS' : 'EO';
      final losingTeam = winningTeam == 'NS' ? 'EO' : 'NS';
      final totalBet = widget.bet * 2;
      final appShare = (totalBet / 3).round();
      final winningShare = totalBet - appShare;
      final perWinner = winningShare ~/ 2;
      final remainder = winningShare - perWinner * 2;

      if (_isDealer) {
        _processTokenTransfer(winningTeam, losingTeam, widget.bet, perWinner, remainder, appShare).then((_) {
          if (mounted) context.read<AuthProvider>().refreshProfile();
        });
      }

      setState(() {
        _gameOver = true;
        _winningTeam = winningTeam;
        _localWon = (winningTeam == 'NS' && (widget.localPosition == 'Sud' || widget.localPosition == 'Nord'))
            || (winningTeam == 'EO' && (widget.localPosition == 'Est' || widget.localPosition == 'Ouest'));
        _winningShare = winningShare;
      });
      _gameChannel.send('game_over', {
        'winner': winningTeam,
        'scores': {'NS': nsTotal, 'EO': eoTotal},
        'app_share': appShare,
        'winning_share': winningShare,
      });
      return;
    }

    _gameChannel.send('hand_result', {
      'deltas': {'NS': deltas['NS'], 'EO': deltas['EO']},
      'scores': {'NS': nsTotal, 'EO': eoTotal},
    });
    _startHandResult(deltas);
  }

  void _handleHandOver(Map<String, dynamic> event) {
    final deltas = Map<String, int>.from(event['deltas'] as Map);
    gameLogic.gameScore['NS'] = gameLogic.gameScore['NS']! + (deltas['NS'] ?? 0);
    gameLogic.gameScore['EO'] = gameLogic.gameScore['EO']! + (deltas['EO'] ?? 0);
    gameLogic.lastHandDelta = deltas;

    final nsTotal = gameLogic.gameScore['NS'] ?? 0;
    final eoTotal = gameLogic.gameScore['EO'] ?? 0;

    if (nsTotal >= 150 || eoTotal >= 150) {
      setState(() { _gameOver = true; _winningTeam = nsTotal >= 150 ? 'NS' : 'EO'; });
      return;
    }

    _startHandResult(deltas);
  }

  void _handleHandResult(Map<String, dynamic> event) {
    _handResultTimeout?.cancel();
    final deltas = Map<String, int>.from(event['deltas'] as Map);
    final scores = Map<String, int>.from(event['scores'] as Map);
    gameLogic.gameScore['NS'] = scores['NS'] ?? 0;
    gameLogic.gameScore['EO'] = scores['EO'] ?? 0;
    gameLogic.lastHandDelta = deltas;
    if (!_handResultActive) {
      _startHandResult(deltas);
    }
  }

  void _startHandResult(Map<String, int> deltas) {
    setState(() {
      _handResultActive = true;
      _handResultDeltas = deltas;
      _confirmedPlayers = {};
      _handResultCountdown = 10;
    });
    _startHandResultTimer();
  }

  void _startHandResultTimer() {
    _handResultTimer?.cancel();
    _handResultTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _handResultCountdown--;
      });
      if (_handResultCountdown <= 0) {
        timer.cancel();
        _onHandResultContinue();
      }
    });
  }

  void _onHandResultContinue() {
    if (_confirmedPlayers.contains(widget.localPosition)) return;
    setState(() => _confirmedPlayers.add(widget.localPosition));
    _gameChannel.send('hand_continue', {'player': widget.localPosition});
    if (_isDealer && _confirmedPlayers.length >= 4) {
      _handResultTimer?.cancel();
      _gameChannel.send('next_hand', {});
      _dismissHandResult();
      _nextHand();
    }
  }

  void _handleHandContinue(Map<String, dynamic> event) {
    final player = event['player'] as String;
    if (_confirmedPlayers.contains(player)) return;
    setState(() => _confirmedPlayers.add(player));
    if (_isDealer && _confirmedPlayers.length >= 4) {
      _handResultTimer?.cancel();
      _gameChannel.send('next_hand', {});
      _dismissHandResult();
      _nextHand();
    }
  }

  void _dismissHandResult() {
    _handResultTimeout?.cancel();
    _handResultTimer?.cancel();
    _handResultActive = false;
    _confirmedPlayers = {};
  }

  void _handleGameOver(Map<String, dynamic> event) {
    final winningTeam = event['winner'] as String;
    setState(() {
      _gameOver = true;
      _winningTeam = winningTeam;
      _localWon = (winningTeam == 'NS' && (widget.localPosition == 'Sud' || widget.localPosition == 'Nord'))
          || (winningTeam == 'EO' && (widget.localPosition == 'Est' || widget.localPosition == 'Ouest'));
      _winningShare = event['winning_share'] as int? ?? 0;
    });
    context.read<AuthProvider>().refreshProfile();
  }

  Future<void> _processTokenTransfer(String winningTeam, String losingTeam, int bet, int perWinner, int remainder, int appShare) async {
    final supabase = SupabaseService();
    final List<String> winners = winningTeam == 'NS' ? ['Sud', 'Nord'] : ['Est', 'Ouest'];
    final List<String> losers = losingTeam == 'NS' ? ['Sud', 'Nord'] : ['Est', 'Ouest'];

    for (int i = 0; i < winners.length; i++) {
      final pid = widget.playerIds[winners[i]];
      if (pid == null || pid.isEmpty) continue;
      final amount = perWinner + (i == 0 ? remainder : 0);
      final current = await supabase.getUserProfile(pid);
      final coins = int.tryParse((current?['coins'] ?? '0').toString()) ?? 0;
      await supabase.client.from('users').update({'coins': coins + amount}).eq('id', pid);
    }

    for (final loser in losers) {
      final pid = widget.playerIds[loser];
      if (pid == null || pid.isEmpty) continue;
      final current = await supabase.getUserProfile(pid);
      final coins = int.tryParse((current?['coins'] ?? '0').toString()) ?? 0;
      final deducted = coins - bet;
      await supabase.client.from('users').update({'coins': deducted >= 0 ? deducted : 0}).eq('id', pid);
    }

    if (appShare > 0) {
      await supabase.client.from('app_gains').insert({
        'match_code': widget.matchCode,
        'amount': appShare,
        'bet': bet,
        'winner_team': winningTeam,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  void _nextHand() {
    final savedNs = gameLogic.gameScore['NS'] ?? 0;
    final savedEo = gameLogic.gameScore['EO'] ?? 0;
    final previousStarter = gameLogic.starterIndex;
    gameLogic.resetGame();
    gameLogic.starterIndex = (previousStarter - 1 + 4) % 4;
    gameLogic.order = [for (int i = 0; i < 4; i++) gameLogic.players[(gameLogic.starterIndex + i) % 4]];
    gameLogic.callSystem = CallSystem(gameLogic.players, initialIndex: gameLogic.starterIndex, playerTeams: {
      for (final p in gameLogic.players) p: BeloteRules.teamOf(p),
    });
    gameLogic.gameScore['NS'] = savedNs;
    gameLogic.gameScore['EO'] = savedEo;
    setState(() {
      _gameStarted = false;
    });
    if (_isDealer) {
      _dealInitialCards();
    } else {
      setState(() { _statusText = 'Attente des cartes...'; _guestDealing = true; });
    }
  }

  // ── Event handler ──

  void _handleEvent(Map<String, dynamic> event) {
    final action = event['action'] as String?;
    switch (action) {
      case 'init_game':
        if (_isDealer) break;
        _handleInitGame(event);
        break;
      case 'bid': {
        final player = event['player'] as String?;
        if (player == null || player == widget.localPosition) break;
        _handleBid(event);
        break;
      }
      case 'final_deal':
        if (_isDealer) break;
        _handleFinalDeal(event);
        break;
      case 'play_card': {
        final player = event['player'] as String?;
        if (player == null || player == widget.localPosition) break;
        _handleCardPlayed(event);
        break;
      }
      case 'hand_over':
        if (_isDealer) break;
        _handleHandOver(event);
        break;
      case 'hand_result':
        _handleHandResult(event);
        break;
      case 'counter_action':
        _handleCounterAction(event);
        break;
      case 'hand_continue':
        _handleHandContinue(event);
        break;
      case 'next_hand':
        if (_isDealer) break;
        _dismissHandResult();
        _nextHand();
        break;
      case 'request_sync':
        if (_isDealer) _sendStateSync();
        break;
      case 'state_sync':
        if (!_isDealer) _applyStateSync(event);
        break;
      case 'forfeit':
        _handleForfeit(event);
        break;
      case 'game_over':
        if (_isDealer) break;
        _handleGameOver(event);
        break;
      case 'cancel':
        if (mounted) {
          _gameChannel.disconnect();
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        break;
    }
  }

  // ── Call bubble ──

  Future<void> _showCallBubble(String player, CallOption option) async {
    final label = '${_displayName(player)} : ${BeloteRules.callOptionLabel(option)}';
    setState(() {
      showCallBubble = true;
      callBubblePlayer = player;
      callBubbleText = label;
    });
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() { showCallBubble = false; });
  }

  // ── Display helpers ──

  String _displayName(String player) {
    return widget.playerNames[player] ?? player;
  }

  // ═══════════════════════════════════════════
  //  BUILD / UI
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final bool showGameOver = _gameOver && _winningTeam != null;

    if (!_gameInitialized && !showGameOver) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _confirmLeave()) _cancelMatch();
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Partie privée'), backgroundColor: const Color(0xFF006400)),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave()) _cancelMatch();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: Image.asset('assets/images/background.png', fit: BoxFit.cover),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  children: [
                    _buildGameInfoBar(),
                    const SizedBox(height: 4),
                    Text(_statusText, style: const TextStyle(color: Colors.white70, fontSize: 13, shadows: [Shadow(blurRadius: 2, color: Colors.black)])),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: _buildOverlapCardsRightToLeft(
                        gameLogic.handFor(_topPlayer()),
                        showBack: true,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 80,
                            child: _buildOverlapCardsTopToBottom(gameLogic.handFor(_leftPlayer())),
                          ),
                          const Expanded(child: SizedBox.shrink()),
                          SizedBox(
                            width: 80,
                            child: _buildOverlapCardsTopToBottom(gameLogic.handFor(_rightPlayer())),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 140,
                      child: _buildPlayerHand(gameLogic.handFor(_bottomPlayer()), playerName: _bottomPlayer()),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.35,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: true,
                child: _buildTrickArea(),
              ),
            ),
            _positionedMarker(_bottomPlayer()),
            _positionedMarker(_topPlayer()),
            _positionedMarker(_leftPlayer()),
            _positionedMarker(_rightPlayer()),
            if (showCallBubble) _positionedCallBubble(),
            if (_handResultActive && !showGameOver) _buildHandResultOverlay(),
            if (_bidTimerSeconds > 0) _buildBidTimer(),
            if (_guestDealing && !showGameOver) _buildDealingOverlay(),
            if (showGameOver) _buildGameOverOverlay(),
          ],
        ),
      ),
    );
  }

  // ── Game info bar ──

  Widget _buildGameInfoBar() {
    final nsScore = gameLogic.gameScore['NS'] ?? 0;
    final eoScore = gameLogic.gameScore['EO'] ?? 0;
    final contract = gameLogic.callSystem.contractCall;
    final contractLabel = contract != null ? BeloteRules.callOptionLabel(contract) : 'En attente';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () async {
              if (await _confirmLeave()) _cancelMatch();
            },
          ),
          Column(
            children: [
              const Text('Score', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 4),
              Text('$nsScore - $eoScore', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          Column(
            children: [
              const Text('Contrat', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 4),
              Text(contractLabel, style: const TextStyle(color: Colors.yellow, fontSize: 14, fontWeight: FontWeight.bold)),
              if (gameLogic.callSystem.contractWinner != null)
                Text(_displayName(gameLogic.callSystem.contractWinner!), style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ],
          ),
          Column(
            children: [
              const Text('Pli', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 4),
              Text(gameLogic.tricksPlayed.toString(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Player hand (bottom) ──

  Widget _buildPlayerHand(List<CardModel> cards, {required String playerName}) {
    const cardWidth = 80.0;
    const cardHeight = 100.0;
    const overlap = 36.0;
    final width = cards.isEmpty ? 0.0 : cardWidth + (cards.length - 1) * overlap;

    return SizedBox(
      height: cardHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              for (var i = 0; i < cards.length; i++)
                Positioned(
                  right: (cards.length - 1 - i) * overlap,
                  child: GestureDetector(
                    onTap: _gameStarted && gameLogic.callSystem.currentPlayer == playerName && gameLogic.canPlayCard(cards[i], player: playerName)
                        ? () => _playCard(cards[i])
                        : null,
                    child: SvgPicture.asset(
                      cards[i].assetPath,
                      width: cardWidth,
                      height: cardHeight,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Opponent hand (top, face-down) ──

  Widget _buildOverlapCardsRightToLeft(
    List<CardModel> cards, {
    bool showBack = false,
  }) {
    const cardWidth = 80.0;
    const cardHeight = 100.0;
    const overlap = 36.0;
    final width = cards.isEmpty ? 0.0 : cardWidth + (cards.length - 1) * overlap;

    return SizedBox(
      height: cardHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              for (var i = 0; i < cards.length; i++)
                Positioned(
                  right: (cards.length - 1 - i) * overlap,
                  child: SvgPicture.asset(
                    showBack ? 'assets/images/card/dos.svg' : cards[i].assetPath,
                    width: cardWidth,
                    height: cardHeight,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Opponent hand (sides, face-down, rotated) ──

  Widget _buildOverlapCardsTopToBottom(List<CardModel> cards) {
    const cardWidth = 100.0;
    const cardHeight = 60.0;
    const overlap = 24.0;
    final height = cards.isEmpty ? 0.0 : cardHeight + (cards.length - 1) * overlap;

    return SizedBox(
      width: cardWidth,
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SizedBox(
          height: height,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              for (var i = 0; i < cards.length; i++)
                Positioned(
                  top: i * overlap,
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: SvgPicture.asset(
                      'assets/images/card/dos.svg',
                      width: cardHeight,
                      height: cardWidth,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Trick area ──

  Widget _buildTrickArea() {
    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: _trickAlignment(_topPlayer()),
            child: _buildTrickCard(_playedCardFor(_topPlayer())),
          ),
          Align(
            alignment: _trickAlignment(_rightPlayer()),
            child: _buildTrickCard(_playedCardFor(_rightPlayer())),
          ),
          Align(
            alignment: _trickAlignment(_leftPlayer()),
            child: _buildTrickCard(_playedCardFor(_leftPlayer())),
          ),
          Align(
            alignment: _trickAlignment(_bottomPlayer()),
            child: _buildTrickCard(_playedCardFor(_bottomPlayer())),
          ),
        ],
      ),
    );
  }

  PlayedCard? _playedCardFor(String player) {
    for (final played in gameLogic.currentTrick) {
      if (played.player == player) return played;
    }
    return null;
  }

  Widget _buildTrickCard(PlayedCard? playedCard) {
    if (playedCard == null) {
      return Container(
        width: 60,
        height: 76,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }
    return SvgPicture.asset(
      playedCard.card.assetPath,
      width: 60,
      height: 76,
    );
  }

  // ── Avatars ──

  Widget _positionedMarker(String player) {
    final media = MediaQuery.of(context);
    final w = media.size.width;
    final h = media.size.height;
    if (player == _bottomPlayer()) {
      return Positioned(bottom: 12, left: w * 0.5 - 28, child: _playerAvatar(player));
    }
    if (player == _topPlayer()) {
      return Positioned(top: 80, left: w * 0.5 - 28, child: _playerAvatar(player));
    }
    if (player == _leftPlayer()) {
      return Positioned(left: 12, top: h * 0.35, child: _playerAvatar(player));
    }
    return Positioned(right: 12, top: h * 0.35, child: _playerAvatar(player));
  }

  Widget _playerAvatar(String player) {
    final isCurrentPlayer = gameLogic.callSystem.currentPlayer == player;
    final name = _displayName(player);
    final avatarUrl = widget.playerAvatars[player] ?? '';
    final showImage = avatarUrl.isNotEmpty;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isCurrentPlayer ? Colors.yellow : Colors.transparent,
          width: 3,
        ),
      ),
      child: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.grey[300],
        backgroundImage: showImage ? cachedNetworkImage(avatarUrl) : null,
        child: showImage
            ? null
            : Text(
                name.isNotEmpty ? name[0].toUpperCase() : player[0],
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
              ),
      ),
    );
  }

  // ── Call bubble ──

  Widget _positionedCallBubble() {
    final media = MediaQuery.of(context);
    final w = media.size.width;
    final h = media.size.height;

    Widget content = Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        callBubbleText,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );

    if (callBubblePlayer == _topPlayer()) {
      return Positioned(top: 12, left: w * 0.5 - 60, child: content);
    }
    if (callBubblePlayer == _rightPlayer()) {
      return Positioned(right: 12, top: h * 0.4, child: content);
    }
    if (callBubblePlayer == _leftPlayer()) {
      return Positioned(left: 12, top: h * 0.4, child: content);
    }
    return Positioned(bottom: 160, left: w * 0.5 - 60, child: content);
  }

  // ── Overlays ──

  Widget _buildHandResultOverlay() {
    final deltas = _handResultDeltas ?? {'NS': 0, 'EO': 0};
    final nsTotal = gameLogic.gameScore['NS'] ?? 0;
    final eoTotal = gameLogic.gameScore['EO'] ?? 0;
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Card(
            color: Colors.black54,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Résultat de la manche', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text('NS : ${deltas['NS']}  (total $nsTotal)', style: const TextStyle(color: Colors.white, fontSize: 16)),
                  Text('EO : ${deltas['EO']}  (total $eoTotal)', style: const TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 16),
                  Text('${_confirmedPlayers.length}/4 confirmé', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('$_handResultCountdown s', style: const TextStyle(color: Colors.orange, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: _confirmedPlayers.contains(widget.localPosition) ? null : _onHandResultContinue,
                      child: Text(
                        _confirmedPlayers.contains(widget.localPosition) ? 'En attente des autres…' : 'Continuer (${_handResultCountdown}s)',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBidTimer() {
    return Positioned(
      right: 20,
      bottom: 180,
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          color: Colors.black87,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '$_bidTimerSeconds',
            style: TextStyle(
              color: _bidTimerSeconds <= 3 ? Colors.red : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDealingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black26,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset('assets/images/card/dos.svg', height: 80),
              const SizedBox(height: 12),
              const Text('Distribution...', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    final nsTotal = gameLogic.gameScore['NS'] ?? 0;
    final eoTotal = gameLogic.gameScore['EO'] ?? 0;
    return Positioned.fill(
      child: Stack(
        children: [
          Container(color: Colors.black54),
          const _ConfettiWidget(),
          Center(
            child: Card(
              color: Colors.black54,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _localWon ? '🎉 Victoire !' : '💔 Défaite',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Text('NS : $nsTotal', style: const TextStyle(color: Colors.white, fontSize: 16)),
                    Text('EO : $eoTotal', style: const TextStyle(color: Colors.white, fontSize: 16)),
                    if (widget.bet > 0) ...[
                      const SizedBox(height: 16),
                      if (_localWon) ...[
                        Text('+${_winningShare ~/ 2} 🪙', style: const TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                        Text('Gain de l\'équipe', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ] else ...[
                        Text('-${widget.bet} 🪙', style: const TextStyle(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                        Text('Mise perdue', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () async {
                        final isTeamA = widget.localPosition == 'Sud' || widget.localPosition == 'Nord';
                        final isHost = widget.localPosition == 'Sud' || widget.localPosition == 'Ouest';
                        final match = await PrivateMatchService().getMatch(widget.matchCode, forceRefresh: true);
                        if (match == null) return;
                        await PrivateMatchService().rejectBets(widget.matchCode);
                        _gameChannel.disconnect();
                        if (!mounted) return;
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PrivateGameLobbyScreen(
                              matchCode: widget.matchCode,
                              isTeamA: isTeamA,
                              isHost: isHost,
                              match: match,
                              localPosition: widget.localPosition,
                            ),
                          ),
                        );
                      },
                      child: const Text('Quitter', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  CONFETTI
  // ═══════════════════════════════════════════

}

class _ConfettiParticle {
  final double startOffset;
  final double x;
  final double speed;
  final double size;
  final Color color;
  final double rotation;
  final double rotationSpeed;

  _ConfettiParticle()
      : startOffset = Random().nextDouble(),
        x = Random().nextDouble(),
        speed = 0.12 + Random().nextDouble() * 0.28,
        size = 3 + Random().nextDouble() * 5,
        color = Colors.primaries[
            Random().nextInt(Colors.primaries.length)],
        rotation = Random().nextDouble() * 6.28,
        rotationSpeed = (Random().nextDouble() - 0.5) * 8;
}

class _ConfettiWidget extends StatefulWidget {
  const _ConfettiWidget();

  @override
  State<_ConfettiWidget> createState() => _ConfettiWidgetState();
}

class _ConfettiWidgetState extends State<_ConfettiWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _particles = List<_ConfettiParticle>.generate(
    24,
    (_) => _ConfettiParticle(),
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_particles, _controller.value),
        );
      },
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter(this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width.isInfinite || size.height.isInfinite) return;

    final paint = Paint();
    for (final p in particles) {
      final t = (progress + p.startOffset) % 1.0;
      final y = -0.15 + t * 1.3;
      if (y < -0.1 || y > 1.1) continue;
      final x = p.x + sin(t * 8 + p.x * 10) * 0.025;

      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(p.rotation + t * p.rotationSpeed);

      final alpha = (1 - y.clamp(0, 1)) * 0.85;
      paint.color = p.color.withValues(alpha: alpha);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.6,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.progress != progress || old.particles != particles;
}

class _ForfeitWarningDialog extends StatefulWidget {
  const _ForfeitWarningDialog();

  @override
  State<_ForfeitWarningDialog> createState() => _ForfeitWarningDialogState();
}

class _ForfeitWarningDialogState extends State<_ForfeitWarningDialog> {
  int _seconds = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _timer?.cancel(); return; }
      setState(() {
        _seconds--;
      });
      if (_seconds <= 0) {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.orange.shade900,
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
          SizedBox(width: 8),
          Text('Inactivité', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Vous n\'avez pas joué depuis 50s.\nJouez une carte dans les',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 12),
          Text(
            '$_seconds',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'secondes',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            'sinon votre équipe sera forfait.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
