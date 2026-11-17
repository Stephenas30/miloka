import 'dart:async';
import 'package:flutter/gestures.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../game/belote_game_logic.dart';
import '../game/belote_rules.dart';
import '../game/call_system.dart';
import '../game/deck.dart';
import '../game/played_card.dart';
import '../models/card_model.dart';
import '../widgets/call_popup.dart';
import '../service/stats_service.dart';
import '../service/game_channel_service.dart';
import '../utils/image_cache.dart';
import '../utils/svg_cache.dart';
import '../utils/game_wake_lock.dart';
import '../widgets/game_result_animation.dart';

class HandHistoryEntry {
  final CallOption contractCall;
  final String contractWinner;
  final String winningTeam;
  final Map<String, int> delta;
  final bool dedans;

  HandHistoryEntry({
    required this.contractCall,
    required this.contractWinner,
    required this.winningTeam,
    required this.delta,
    required this.dedans,
  });
}

class GameScreen extends StatefulWidget {
  final Set<String> humanPlayers;
  final String? teamId;
  final bool isHost;
  final Map<String, String> playerNames;
  final Map<String, String> playerAvatars;
  const GameScreen({
    super.key,
    this.humanPlayers = const {'Sud'},
    this.teamId,
    this.isHost = true,
    this.playerNames = const {},
    this.playerAvatars = const {},
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
  with SingleTickerProviderStateMixin {
  late BeloteGameLogic gameLogic;

  bool get _isGuestNetworked => widget.teamId != null && !widget.isHost;
  StreamSubscription<Map<String, dynamic>>? _networkSubscription;

  bool showCallBubble = false;
  String callBubblePlayer = "";
  String callBubbleText = "";
  List<HandHistoryEntry> handHistory = [];
  String? overallWinner;

  CardModel? animatingDealCard;
  String? animatingDealPlayer;
  bool dealCardAtTarget = false;
  CardModel? animatingPlayCard;
  String? animatingPlayPlayer;
  Offset _playFrom = Offset.zero;
  Offset _playTo = Offset.zero;
  bool _playDropAndSettle = false;
  late final AnimationController _playController;
  final Duration dealAnimationDuration = const Duration(milliseconds: 200);
  final Duration playAnimationDuration = const Duration(milliseconds: 450);
  static const Duration dropAnimationDuration = Duration(milliseconds: 200);
  static const double _cardDropAboveTable = 180.0;

  final List<String> players = ["Nord", "Est", "Sud", "Ouest"];

  CardModel? _draggingCard;
  String? _draggingCardPlayer;
  bool _dropResolveInProgress = false;
  bool _dragHasMoved = false;
  Offset _dragStartPos = Offset.zero;
  final ValueNotifier<Offset> _dragPos = ValueNotifier<Offset>(Offset.zero);
  AnimationController? _returnController;
  Animation<Offset>? _returnAnimation;
  final GlobalKey _dragStackKey = GlobalKey();
  final Map<String, GlobalKey> _cardKeys = {};

  bool _hostReady = false;
  bool _guestReady = false;
  Timer? _autoCloseTimer;

  bool _isHuman(String player) => widget.humanPlayers.contains(player);

  bool _isLocalPlayer(String player) {
    if (widget.teamId == null) return _isHuman(player);
    return widget.isHost ? player == 'Sud' : player == 'Nord';
  }

  bool _initReceived = false;
  Timer? _requestInitTimer;
  bool _isPlayingCard = false;
  Completer<CallOption>? _pendingBidCompleter;
  Completer<String?>? _pendingCounterCompleter;
  Completer<String?>? _pendingSurCounterCompleter;

  bool _guestDealing = false;
  Timer? _guestDealTimer;
  Timer? _inactivityTimer;
  Timer? _inactivityWarningTimer;
  bool _isWarningShown = false;

  @override
  void initState() {
    super.initState();
    _playController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    GameWakeLock.acquire();
    gameLogic = BeloteGameLogic(players: players);

    if (widget.teamId != null) {
      _setupNetwork();
    } else {
      Future.delayed(Duration.zero, () => _dealCards());
    }
  }

  void _startAutoCloseTimer() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (overallWinner != null) return;
      if (widget.isHost) {
        _hostReady = true;
        if (_guestReady || widget.teamId == null) {
          _hostReady = false;
          _guestReady = false;
          _applyLastHandAndNext();
        } else {
          setState(() {});
        }
      } else {
        GameChannelService().send('player_ready', {});
        setState(() {
          gameLogic.waitingForNextHand = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _networkSubscription?.cancel();
    _requestInitTimer?.cancel();
    _guestDealTimer?.cancel();
    _autoCloseTimer?.cancel();
    _inactivityTimer?.cancel();
    _inactivityWarningTimer?.cancel();
    GameWakeLock.release();
    _playController.dispose();
    _returnController?.dispose();
    _dragPos.dispose();
    if (widget.teamId != null) {
      GameChannelService().disconnect();
    }
    super.dispose();
  }

  Future<void> _setupNetwork() async {
    final channel = GameChannelService();
    try {
      await channel.connect(widget.teamId!);
    } catch (e) {
      if (widget.isHost && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Connexion au serveur impossible. La partie continue en local.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
        _dealCards();
      }
      return;
    }
    _networkSubscription = channel.events.listen(_handleNetworkEvent);

    if (widget.isHost) {
      Future.delayed(Duration.zero, () => _dealCards());
    } else {
      _requestInitTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!_initReceived) {
          channel.send('request_init', {});
        }
      });
    }
  }

  void _handleNetworkEvent(Map<String, dynamic> event) {
    final action = event['action'] as String?;
    if (action == null) return;

    if (widget.isHost) {
      switch (action) {
        case 'request_init':
          _handleGuestRequestInit();
        case 'bid':
          _handleGuestBid(event);
        case 'play_card':
          _handleGuestPlay(event);
        case 'player_ready':
          setState(() => _guestReady = true);
          if (_hostReady) {
            _autoCloseTimer?.cancel();
            _hostReady = false;
            _guestReady = false;
            _applyLastHandAndNext();
          }
        case 'guest_bid':
          if (_pendingBidCompleter != null) {
            final callName = event['call'] as String? ?? 'pass';
            _pendingBidCompleter!.complete(CallOption.values.byName(callName));
          } else {
          }
        case 'counter_response':
          if (_pendingCounterCompleter != null) {
            _pendingCounterCompleter!.complete(event['choice'] as String?);
            _pendingCounterCompleter = null;
          }
        case 'sur_counter_response':
          if (_pendingSurCounterCompleter != null) {
            _pendingSurCounterCompleter!.complete(event['choice'] as String?);
            _pendingSurCounterCompleter = null;
          }
      }
    } else {
      switch (action) {
        case 'init_game':
          _handleGuestInit(event);
        case 'bid_made':
          _handleGuestBidMade(event);
        case 'card_played':
          _handleGuestCardPlayed(event);
        case 'trick_resolved':
          _handleGuestTrickResolved(event);
        case 'hand_finished':
          _handleGuestHandFinished(event);
        case 'game_over':
          _handleGuestGameOver(event);
        case 'bid_request':
          _handleBidRequest(event);
        case 'counter_request':
          _handleCounterRequest(event);
        case 'sur_counter_request':
          _handleSurCounterRequest(event);
        case 'dealing':
          _handleGuestDealing(event);
        case 'forfeit':
          _handleGuestForfeit(event);
      }
    }
  }

  Map<String, dynamic>? _lastInitGameData;

  void _handleGuestRequestInit() {
    if (_lastInitGameData != null) {
      GameChannelService().send('init_game', _lastInitGameData!);
    }
  }

  void _handleGuestInit(Map<String, dynamic> event) {
    _initReceived = true;
    _requestInitTimer?.cancel();
    final contractWinner = event['contract_winner'] as String? ?? 'Nord';
    final starterPlayer = event['starter'] as String? ?? contractWinner;
    final handData = event['hand'] as List? ?? [];
    gameLogic.aiHands[0] = handData.map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
    final estData = event['est_hand'] as List? ?? [];
    gameLogic.aiHands[1] = estData.map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
    final ouestData = event['ouest_hand'] as List? ?? [];
    gameLogic.aiHands[2] = ouestData.map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
    final sudData = event['sud_hand'] as List? ?? [];
    gameLogic.playerHand = sudData.map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
    gameLogic.starterIndex = gameLogic.players.indexOf(starterPlayer);
    gameLogic.gameStarted = true;
    gameLogic.biddingFinished = true;
    _autoCloseTimer?.cancel();
    gameLogic.waitingForNextHand = false;
    gameLogic.callSystem.contractCall = CallOption.values.byName(event['contract_call'] as String);
    gameLogic.callSystem.contractWinner = contractWinner;
    setState(() {});
    _animateGuestDeal();
    _startGame();
  }

  void _animateGuestDeal() {
    _guestDealTimer?.cancel();
    setState(() => _guestDealing = true);
    _guestDealTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _guestDealing = false);
    });
  }

  bool get _inactivityEnabled => widget.humanPlayers.length >= 2;

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityWarningTimer?.cancel();
    if (_isWarningShown) {
      _isWarningShown = false;
      Navigator.of(context).pop();
    }
    if (!gameLogic.gameStarted || gameLogic.gameOver) return;
    // L'inactivité (forfait) ne s'applique que lorsque 2 joueurs réels
    // jouent ensemble (partie en ligne / contre un adversaire réel).
    // En solo contre l'IA, aucun forfait d'inactivité n'est déclenché.
    if (!_inactivityEnabled) return;
    final current = gameLogic.callSystem.currentPlayer;
    if (!_isHuman(current)) return;
    _inactivityTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted || gameLogic.gameOver || !gameLogic.gameStarted) return;
      if (gameLogic.callSystem.currentPlayer != current) return;
      if (_isHuman(current)) {
        _inactivityTimer = null;
        if (widget.teamId != null) {
          GameChannelService().send('forfeit', {'player': current});
        }
        setState(() {
          gameLogic.gameOver = true;
          gameLogic.gameStarted = false;
          overallWinner = current == 'Sud' || current == 'Nord' ? 'EO' : 'NS';
        });
      }
    });
    _inactivityWarningTimer = Timer(const Duration(seconds: 50), () {
      _showForfeitWarning(current);
    });
  }

  void _showForfeitWarning(String current) {
    if (!mounted || gameLogic.gameOver || !gameLogic.gameStarted) return;
    if (!_inactivityEnabled) return;
    if (gameLogic.callSystem.currentPlayer != current) return;
    if (!_isHuman(current)) return;
    _isWarningShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (_) => const _ForfeitWarningDialog(),
    ).whenComplete(() {
      _isWarningShown = false;
    });
  }

  void _handleGuestForfeit(Map<String, dynamic> event) {
    final player = event['player'] as String? ?? '';
    if (player.isEmpty) return;
    _inactivityTimer?.cancel();
    setState(() {
      gameLogic.gameOver = true;
      gameLogic.gameStarted = false;
      overallWinner = player == 'Sud' || player == 'Nord' ? 'EO' : 'NS';
    });
  }

  void _handleGuestDealing(Map<String, dynamic> event) {
    final dealType = event['deal_type'] as String? ?? 'initial';
    final duration = dealType == 'initial' ? 10500 : 3000;
    final handData = event['hand'] as List? ?? [];
    if (handData.isNotEmpty) {
      gameLogic.aiHands[0] = handData.map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
      final estData = event['est_hand'] as List? ?? [];
      gameLogic.aiHands[1] = estData.map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
      final ouestData = event['ouest_hand'] as List? ?? [];
      gameLogic.aiHands[2] = ouestData.map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
      final sudData = event['sud_hand'] as List? ?? [];
      gameLogic.playerHand = sudData.map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
    }
    _guestDealTimer?.cancel();
    setState(() => _guestDealing = true);
    _guestDealTimer = Timer(Duration(milliseconds: duration), () {
      if (mounted) setState(() => _guestDealing = false);
    });
  }

  void _handleGuestBidMade(Map<String, dynamic> event) {
    final player = event['player'] as String? ?? '';
    final callName = event['call'] as String? ?? 'pass';
    final option = CallOption.values.byName(callName);
    gameLogic.callSystem.makeCall(option);
    _showCallBubble(player, option);
    setState(() {});
  }

  void _handleBidRequest(Map<String, dynamic> event) {
    if (!mounted) return;
    final current = event['player'] as String? ?? 'Nord';
    final callsStr = (event['available_calls'] as List?)?.cast<String>() ?? [];
    final availableCalls = callsStr.map((s) => CallOption.values.byName(s)).toList();

    _setHandsFromEvent(event);
    setState(() => gameLogic.waitingForNextHand = false);

    _animateGuestDeal();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => CallPopup(
          playerName: current,
          availableCalls: availableCalls,
          timeoutSeconds: 10,
          onCall: (option) {
            GameChannelService().send('guest_bid', {'call': option.name});
          },
        ),
      );
    });
  }

  void _handleGuestCardPlayed(Map<String, dynamic> event) {
    final player = event['player'] as String? ?? '';
    final cardData = event['card'] as Map<String, dynamic>?;
    if (cardData == null) return;
    final card = CardModel.fromMap(cardData);
    final posData = event['pos'] as Map<String, dynamic>?;
    final position = posData == null
        ? null
        : Offset(
            (posData['x'] as num?)?.toDouble() ?? 0.5,
            (posData['y'] as num?)?.toDouble() ?? 0.42,
          );
    final hand = _handFor(player);
    hand.removeWhere((c) => c.suit == card.suit && c.rank == card.rank);
    setState(() {
      gameLogic.currentTrick.add(
        PlayedCard(player, card, position: position),
      );
      gameLogic.callSystem.setCurrentPlayer(
        event['next_player'] as String? ?? _nextPlayer(player),
      );
    });
  }

  void _handleGuestTrickResolved(Map<String, dynamic> event) {
    final winner = event['winner'] as String? ?? 'Nord';
    final tricksPlayed = (event['tricks_played'] as num?)?.toInt() ?? gameLogic.tricksPlayed + 1;
    setState(() {
      gameLogic.currentTrick = [];
      gameLogic.tricksPlayed = tricksPlayed;
      final ns = (event['team_points_ns'] as num?)?.toInt() ?? 0;
      final eo = (event['team_points_eo'] as num?)?.toInt() ?? 0;
      gameLogic.teamPoints = {'NS': ns, 'EO': eo};
      gameLogic.callSystem.setCurrentPlayer(winner);
    });
    if (tricksPlayed >= 8) {
      gameLogic.lastHandDelta = {
        'NS': (event['delta_ns'] as num?)?.toInt() ?? 0,
        'EO': (event['delta_eo'] as num?)?.toInt() ?? 0,
      };
      gameLogic.gameOver = true;
      gameLogic.gameStarted = false;
      setState(() => gameLogic.waitingForNextHand = true);
      _startAutoCloseTimer();
    }
  }

  void _handleGuestHandFinished(Map<String, dynamic> event) {
    final starterIndex = (event['starter_index'] as num?)?.toInt() ?? 0;
    setState(() {
      gameLogic.gameOver = true;
      gameLogic.gameStarted = false;
      gameLogic.lastHandDelta = {
        'NS': (event['delta_ns'] as num?)?.toInt() ?? 0,
        'EO': (event['delta_eo'] as num?)?.toInt() ?? 0,
      };
      gameLogic.gameScore = {
        'NS': (event['score_ns'] as num?)?.toInt() ?? 0,
        'EO': (event['score_eo'] as num?)?.toInt() ?? 0,
      };
      gameLogic.playerHand.clear();
      gameLogic.aiHands = [[], [], []];
      gameLogic.deck = Deck();
      gameLogic.currentTrick = [];
      gameLogic.tricksPlayed = 0;
      gameLogic.teamPoints = {'NS': 0, 'EO': 0};
      gameLogic.starterIndex = starterIndex;
      gameLogic.order = [for (int i = 0; i < gameLogic.players.length; i++) gameLogic.players[(starterIndex + i) % gameLogic.players.length]];
      gameLogic.callSystem = CallSystem(gameLogic.players, initialIndex: starterIndex, playerTeams: {
        for (final p in gameLogic.players) p: BeloteRules.teamOf(p),
      });
      gameLogic.biddingFinished = false;
    });
  }

  void _handleGuestGameOver(Map<String, dynamic> event) {
    _autoCloseTimer?.cancel();
    setState(() {
      overallWinner = event['winner'] as String?;
    });
  }

  Future<void> _handleGuestBid(Map<String, dynamic> event) async {
    final optionStr = event['call'] as String?;
    if (optionStr == null) return;
    final option = CallOption.values.byName(optionStr);
    gameLogic.callSystem.makeCall(option);
    final player = event['player'] as String? ?? 'Nord';
    _showCallBubble(player, option);

    if (BeloteRules.isContractProposal(option)) {
      await _processCounterAfterBid();
    } else {
      gameLogic.callSystem.setCurrentPlayer(gameLogic.callSystem.contractWinner ?? player);
    }

    if (!gameLogic.callSystem.isFinished()) {
      _showCallPopup();
    } else {
      _finishBidding();
    }
  }

  void _handleGuestPlay(Map<String, dynamic> event) {
    final cardData = event['card'] as Map<String, dynamic>?;
    if (cardData == null) return;
    final card = CardModel.fromMap(cardData);
    final player = event['player'] as String? ?? 'Nord';
    final hand = _handFor(player);
    final contains = hand.contains(card);
    final posData = event['pos'] as Map<String, dynamic>?;
    final position = posData == null
        ? null
        : Offset(
            (posData['x'] as num?)?.toDouble() ?? 0.5,
            (posData['y'] as num?)?.toDouble() ?? 0.42,
          );
    if (contains) {
      _playCardFromNetwork(player, card, position: position);
    } else {
    }
  }

  Future<void> _playCardFromNetwork(String player, CardModel card,
      {Offset? position}) async {
    if (_isPlayingCard) return;
    _isPlayingCard = true;
    final hand = _handFor(player);
    final board = _boardSize();
    final relative =
        position ?? _randomDropPos();
    _playFrom = _cardStackOffset(card) ?? _edgeStart(player);
    _playTo = Offset(
      relative.dx * board.width - cardWidthValue / 2,
      relative.dy * board.height - cardHeightValue / 2,
    );
    _playDropAndSettle = false;
    setState(() {
      hand.remove(card);
      animatingPlayCard = card;
      animatingPlayPlayer = player;
    });
    _playController.duration = playAnimationDuration;
    await _playController.forward(from: 0);
    setState(() {
      gameLogic.currentTrick.add(
        PlayedCard(player, card, position: relative),
      );
      animatingPlayCard = null;
      animatingPlayPlayer = null;
    });

    if (widget.teamId != null && widget.isHost) {
      GameChannelService().send('card_played', {
        'player': player,
        'card': card.toMap(),
        'next_player': _nextPlayer(player),
      });
    }

    if (gameLogic.currentTrick.length >= 4) {
      await Future.delayed(const Duration(milliseconds: 400));
      _resolveTrick();
    } else {
      final next = _nextPlayer(player);
      gameLogic.callSystem.setCurrentPlayer(next);
      if (widget.teamId != null && !widget.isHost) {
        // guest waits for host broadcast
      } else if (!_isHuman(next)) {
        await Future.delayed(const Duration(milliseconds: 250));
        Future.delayed(Duration.zero, () => _playAITurn());
      }
    }
    _isPlayingCard = false;
    _resetInactivityTimer();
  }

  /// Distribution animée : 3 cartes chacun puis 2 cartes chacun
  Future<void> _dealCards() async {
    // Premier tour : 3 cartes chacun
    for (var player in gameLogic.order) {
      for (var i = 0; i < 3; i++) {
        await _dealCardToPlayer(player);
      }
    }

    // Deuxième tour : 2 cartes chacun
    for (var player in gameLogic.order) {
      for (var i = 0; i < 2; i++) {
        await _dealCardToPlayer(player);
      }
    }

    if (widget.teamId != null && widget.isHost) {
      GameChannelService().send('dealing', {
        'order': gameLogic.order,
        'deal_type': 'initial',
        'hand': gameLogic.aiHands[0].map((c) => c.toMap()).toList(),
        'est_hand': gameLogic.aiHands[1].map((c) => c.toMap()).toList(),
        'ouest_hand': gameLogic.aiHands[2].map((c) => c.toMap()).toList(),
        'sud_hand': gameLogic.playerHand.map((c) => c.toMap()).toList(),
      });
    }

    // Quand la distribution est terminée → lancer le popup d'appel
    await _showCallPopup();
  }

  Future<void> _dealCardToPlayer(String player) async {
    final card = gameLogic.deck.deal(1).first;
    setState(() {
      animatingDealCard = card;
      animatingDealPlayer = player;
      dealCardAtTarget = false;
    });

    await Future.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;
    setState(() {
      dealCardAtTarget = true;
    });
    await Future.delayed(dealAnimationDuration + const Duration(milliseconds: 30));
    if (!mounted) return;

    setState(() {
      if (player == "Nord") {
        gameLogic.aiHands[0].add(card);
      } else if (player == "Est") {
        gameLogic.aiHands[1].add(card);
      } else if (player == "Ouest") {
        gameLogic.aiHands[2].add(card);
      } else {
        gameLogic.playerHand.add(card);
      }
      animatingDealCard = null;
      animatingDealPlayer = null;
      dealCardAtTarget = false;
    });
  }

  void _giveCards(String player, int count) {
    gameLogic.giveCards(player, count);
  }

  String _callOptionLabel(CallOption option) {
    return BeloteRules.callOptionLabel(option);
  }

  void _registerLastHandHistory() {
    final contract = gameLogic.callSystem.contractCall;
    final preneur = gameLogic.callSystem.contractWinner;
    if (contract == null || preneur == null) return;
    final preneurTeam = BeloteRules.teamOf(preneur);
    final winnerTeam = gameLogic.handWinningTeam();
    final dedans = winnerTeam != preneurTeam;

    handHistory.add(HandHistoryEntry(
      contractCall: contract,
      contractWinner: preneur,
      winningTeam: winnerTeam,
      delta: Map<String, int>.from(gameLogic.lastHandDelta),
      dedans: dedans,
    ));
  }

  void _showStatistics() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Statistiques de la partie'),
        content: SizedBox(
          width: double.maxFinite,
          child: handHistory.isEmpty
              ? const Text('Aucune manche jouée pour cette partie.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: handHistory.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final entry = handHistory[index];
                    final contractLabel = _callOptionLabel(entry.contractCall);
                    final isDedans = entry.dedans ? 'Oui' : 'Non';
                    final winnerLabel = entry.winningTeam == 'NS' ? 'Nord-Sud' : 'Est-Ouest';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Manche ${index + 1}: $winnerLabel', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Contrat: $contractLabel'),
                        Text('Preneur: ${entry.contractWinner}'),
                        Text('Dedans: $isDedans'),
                        Text('Score: NS ${entry.delta['NS']} / EO ${entry.delta['EO']}'),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  List<CardModel> _handFor(String player) {
    return gameLogic.handFor(player);
  }

  List<CardModel> _legalCards(String player) {
    return gameLogic.legalCards(player);
  }

  PlayedCard _currentWinningCard() {
    return gameLogic.currentWinningCard();
  }

  bool _isPartnerWinning(String player) {
    return gameLogic.isPartnerWinning(player);
  }

  CardModel _lowestPointCard(List<CardModel> candidates) {
    return gameLogic.lowestPointCard(candidates);
  }

  CardModel _minimalWinningCard(List<CardModel> candidates, Suit leadSuit) {
    return gameLogic.minimalWinningCard(candidates, leadSuit);
  }

  CardModel _pickLeadCard(String player) {
    return gameLogic.pickLeadCard(player);
  }

  String _nextPlayer(String current) {
    return gameLogic.nextPlayer(current);
  }

  void _startGame() {
    if (gameLogic.callSystem.contractWinner != null) {
      gameLogic.callSystem.setCurrentPlayer(gameLogic.players[gameLogic.starterIndex]);
      setState(() {
        gameLogic.gameStarted = true;
        gameLogic.gameOver = false;
      });
      _resetInactivityTimer();
    }
  }

  void _resolveTrick() {
    gameLogic.resolveTrick();
    setState(() {
      gameLogic.currentTrick = [];
      if (gameLogic.tricksPlayed >= 8) {
        gameLogic.gameOver = true;
        gameLogic.gameStarted = false;
        gameLogic.lastHandDelta = gameLogic.computeHandScores();
        _registerLastHandHistory();
        gameLogic.waitingForNextHand = true;
        _startAutoCloseTimer();
      }
    });

    if (widget.teamId != null && widget.isHost) {
      final payload = <String, dynamic>{
        'winner': gameLogic.callSystem.currentPlayer,
        'tricks_played': gameLogic.tricksPlayed,
        'team_points_ns': gameLogic.teamPoints['NS'],
        'team_points_eo': gameLogic.teamPoints['EO'],
      };
      if (gameLogic.tricksPlayed >= 8) {
        payload['delta_ns'] = gameLogic.lastHandDelta['NS'];
        payload['delta_eo'] = gameLogic.lastHandDelta['EO'];
      }
      GameChannelService().send('trick_resolved', payload);
    }

    if (!gameLogic.gameOver && !_isHuman(gameLogic.callSystem.currentPlayer)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playAITurn();
      });
    }
  }

  void _applyLastHandAndNext() {
    bool shouldStartNextHand = true;
    final isGameOver = gameLogic.gameScore['NS']! + (gameLogic.lastHandDelta['NS'] ?? 0) >= 150 ||
                        gameLogic.gameScore['EO']! + (gameLogic.lastHandDelta['EO'] ?? 0) >= 150;

    _autoCloseTimer?.cancel();
    setState(() {
      gameLogic.gameScore['NS'] = gameLogic.gameScore['NS']! + (gameLogic.lastHandDelta['NS'] ?? 0);
      gameLogic.gameScore['EO'] = gameLogic.gameScore['EO']! + (gameLogic.lastHandDelta['EO'] ?? 0);

      if (isGameOver) {
        overallWinner = gameLogic.gameScore['NS']! >= 150 ? 'NS' : 'EO';
        gameLogic.waitingForNextHand = false;
        shouldStartNextHand = false;
      }

      if (overallWinner == null) {
        gameLogic.waitingForNextHand = false;
        gameLogic.lastHandDelta = {'NS': 0, 'EO': 0};
        gameLogic.teamPoints = {'NS': 0, 'EO': 0};
        gameLogic.tricksPlayed = 0;
        gameLogic.currentTrick = [];
        gameLogic.playerHand.clear();
        gameLogic.aiHands = [[], [], []];
        gameLogic.deck = Deck();
        gameLogic.deck.shuffle();
        gameLogic.starterIndex = (gameLogic.starterIndex + 1) % players.length;
        gameLogic.order = [for (int i = 0; i < players.length; i++) players[(gameLogic.starterIndex + i) % players.length]];
        gameLogic.callSystem = CallSystem(players, initialIndex: gameLogic.starterIndex, playerTeams: {
          for (final p in players) p: BeloteRules.teamOf(p),
        });
        gameLogic.biddingFinished = false;
        gameLogic.gameOver = false;
      }
    });

    if (widget.teamId != null && widget.isHost) {
      if (isGameOver) {
        GameChannelService().send('game_over', {
          'winner': overallWinner,
        });
      } else {
        GameChannelService().send('hand_finished', {
          'delta_ns': gameLogic.lastHandDelta['NS'],
          'delta_eo': gameLogic.lastHandDelta['EO'],
          'score_ns': gameLogic.gameScore['NS'],
          'score_eo': gameLogic.gameScore['EO'],
          'starter_index': gameLogic.starterIndex,
        });
      }
    }

    if (shouldStartNextHand) {
      Future.delayed(Duration.zero, () => _dealCards());
    }
  }

  Future<void> _playCard(String player, CardModel card,
      {Offset? dropPos}) async {
    if (_isPlayingCard) return;
    _isPlayingCard = true;
    _draggingCard = null;
    _returnAnimation = null;
    _dragPos.value = Offset.zero;
    final hand = _handFor(player);
    final board = _boardSize();
    // Position fractionnelle où la carte va atterrir (relâchement du doigt, ou emplacement aléatoire)
    final relative = dropPos != null
        ? Offset(
            dropPos.dx / board.width,
            dropPos.dy / board.height,
          )
        : _randomDropPos();
    _playFrom = dropPos ?? _cardStackOffset(card) ?? _edgeStart(player);
    _playTo = Offset(
      relative.dx * board.width - cardWidthValue / 2,
      relative.dy * board.height - cardHeightValue / 2,
    );
    _playDropAndSettle = dropPos != null;
    setState(() {
      hand.remove(card);
      animatingPlayCard = card;
      animatingPlayPlayer = player;
    });
    _playController.duration = dropPos != null
        ? dropAnimationDuration
        : playAnimationDuration;
    await _playController.forward(from: 0);

    if (widget.teamId != null && !widget.isHost) {
      // Guest : envoie au host, ne fait rien d'autre (host broadcast card_played)
      setState(() {
        animatingPlayCard = null;
        animatingPlayPlayer = null;
      });
      GameChannelService().send('play_card', {
        'player': player,
        'card': card.toMap(),
        'pos': {'x': relative.dx, 'y': relative.dy},
      });
      _isPlayingCard = false;
      return;
    }

    setState(() {
      gameLogic.currentTrick.add(
        PlayedCard(player, card, position: relative),
      );
      animatingPlayCard = null;
      animatingPlayPlayer = null;
    });

    if (widget.teamId != null && widget.isHost) {
      GameChannelService().send('card_played', {
        'player': player,
        'card': card.toMap(),
        'next_player': _nextPlayer(player),
        'pos': {'x': relative.dx, 'y': relative.dy},
      });
    }

    if (gameLogic.currentTrick.length >= 4) {
      await Future.delayed(const Duration(milliseconds: 400));
      _resolveTrick();
    } else {
      final next = _nextPlayer(player);
      gameLogic.callSystem.setCurrentPlayer(next);
      if (!_isHuman(next)) {
        await Future.delayed(const Duration(milliseconds: 250));
        _isPlayingCard = false;
        _playAITurn();
      }
    }
    _isPlayingCard = false;
    _resetInactivityTimer();
  }

  CardModel _chooseAICard(String player) {
    final legal = _legalCards(player);
    if (legal.isEmpty) return _handFor(player).first;
    if (gameLogic.currentTrick.isEmpty) {
      return _pickLeadCard(player);
    }

    final leadSuit = gameLogic.currentTrick.first.card.suit;
    final winner = _currentWinningCard();
    final partnerWinning = _isPartnerWinning(player);
    final followCards = legal.where((card) => card.suit == leadSuit).toList();
    if (followCards.isNotEmpty) {
      if (partnerWinning) return _lowestPointCard(followCards);
      final canBeat = followCards
          .where((card) => BeloteRules.trickCardStrength(card, leadSuit, gameLogic.callSystem) >
              BeloteRules.trickCardStrength(winner.card, leadSuit, gameLogic.callSystem))
          .toList();
      if (canBeat.isNotEmpty) return _minimalWinningCard(canBeat, leadSuit);
      return _lowestPointCard(followCards);
    }

    final trumps = legal.where((card) => BeloteRules.isTrump(card, gameLogic.callSystem)).toList();
    if (trumps.isNotEmpty) {
      if (partnerWinning) return _lowestPointCard(legal);
      final canBeat = trumps
          .where((card) => BeloteRules.trickCardStrength(card, leadSuit, gameLogic.callSystem) >
              BeloteRules.trickCardStrength(winner.card, leadSuit, gameLogic.callSystem))
          .toList();
      if (canBeat.isNotEmpty) return _minimalWinningCard(canBeat, leadSuit);
      return _lowestPointCard(trumps);
    }

    return _lowestPointCard(legal);
  }

  Future<void> _playAITurn() async {
    if (!gameLogic.gameStarted || gameLogic.gameOver) {
      return;
    }
    final current = gameLogic.callSystem.currentPlayer;
    if (_isHuman(current)) {
      return;
    }
    if (_handFor(current).isEmpty) {
      return;
    }
    final card = _chooseAICard(current);
    await _playCard(current, card);
  }

  bool _canPlayCard(CardModel card, {String player = 'Sud'}) {
    return gameLogic.canPlayCard(card, player: player);
  }

  GlobalKey _cardKeyFor(CardModel card) =>
      _cardKeys.putIfAbsent(card.assetPath, () => GlobalKey());

  Size _boardSize() {
    final renderBox =
        _dragStackKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.size ?? const Size(400, 700);
  }

  /// Position de la carte dans les coordonnées du Stack de la table.
  Offset? _cardStackOffset(CardModel card) {
    final cardKey = _cardKeys[card.assetPath];
    final stackBox =
        _dragStackKey.currentContext?.findRenderObject() as RenderBox?;
    final cardBox =
        cardKey?.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || cardBox == null) return null;
    final stackOrigin = stackBox.localToGlobal(Offset.zero);
    return cardBox.localToGlobal(Offset.zero) - stackOrigin;
  }

  /// Position fractionnelle aléatoire naturelle près du centre de la table.
  Offset _randomDropPos() {
    final random = math.Random();
    return Offset(
      0.36 + random.nextDouble() * 0.28,
      0.28 + random.nextDouble() * 0.22,
    );
  }

  /// Position de repos de la carte pour un joueur sans GlobalKey (IA/joueurs non humains).
  Offset _edgeStart(String player) {
    final origin = _playOrigin(player);
    final size = _boardSize();
    if (origin.y > 0.5) {
      return Offset(size.width / 2 - cardWidthValue / 2, size.height + 40);
    }
    if (origin.y < -0.5) {
      return Offset(size.width / 2 - cardWidthValue / 2, -120);
    }
    if (origin.x > 0.5) {
      return Offset(size.width + 40, size.height / 2 - cardHeightValue / 2);
    }
    return Offset(-100, size.height / 2 - cardHeightValue / 2);
  }

  static const double cardWidthValue = 80.0;
  static const double cardHeightValue = 100.0;
  /// Démarrage du drag au moment où le doigt touche la carte (events pointer bruts,
  /// aucun délai d'arène de gestes).
  void _onCardPointerDown(CardModel card, String playerName, PointerDownEvent details) {
    if (!_isHuman(playerName)) return;
    if (!_canPlayCard(card, player: playerName)) return;
    final box = _dragStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    setState(() {
      _draggingCard = card;
      _draggingCardPlayer = playerName;
      _dropResolveInProgress = false;
      _dragHasMoved = false;
      _dragStartPos = details.position;
      _dragPos.value = box.globalToLocal(details.position);
    });
  }

  /// Mise à jour du drag à chaque pointer (position 1:1 du doigt, sans décalage).
  void _onCardPointerMove(PointerMoveEvent event) {
    if (_draggingCard == null) return;
    final box = _dragStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _dragPos.value = box.globalToLocal(event.position);
    final dx = event.position.dx - _dragStartPos.dx;
    final dy = event.position.dy - _dragStartPos.dy;
    if (dx * dx + dy * dy > 36) {
      _dragHasMoved = true;
    }
  }

  bool _isOverDropZone(Offset pos) {
    final size = MediaQuery.sizeOf(context);
    return _dropZoneRectFor(size).contains(pos);
  }

  void _onReturnTick() {
    final animation = _returnAnimation;
    if (animation == null) return;
    _dragPos.value = animation.value;
  }

  void _onReturnDone(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    setState(() {
      _draggingCard = null;
      _dragPos.value = Offset.zero;
      _returnAnimation = null;
    });
  }

  /// Relâche du doigt : déclenché par le Listener global du Stack ; tap si pas de mouvement.
  void _tryResolveDragDrop() {
    final card = _draggingCard;
    final playerName = _draggingCardPlayer;
    if (card == null || playerName == null) return;
    if (!_dragHasMoved) {
      setState(() {
        _draggingCard = null;
        _draggingCardPlayer = null;
        _dragPos.value = Offset.zero;
      });
      _playCard(playerName, card);
      return;
    }
    _resolveDragDrop(card, playerName);
  }

  void _flyBackToHand(CardModel card) {
    final rest = _cardStackOffset(card);
    if (rest == null) {
      setState(() {
        _draggingCard = null;
        _dragPos.value = Offset.zero;
      });
      return;
    }
    _returnController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 230),
    )
      ..addListener(_onReturnTick)
      ..addStatusListener(_onReturnDone);
    _returnAnimation = Tween<Offset>(begin: _dragPos.value, end: rest).animate(
      CurvedAnimation(
        parent: _returnController!,
        curve: Curves.easeOutCubic,
      ),
    );
    _returnController!.forward(from: 0);
  }

  void _resolveDragDrop(CardModel card, String playerName) {
    if (_dropResolveInProgress) return;
    if (_draggingCard == null) return;
    if (!_dragHasMoved) {
      setState(() => _draggingCard = null);
      _draggingCardPlayer = null;
      return;
    }
    _dropResolveInProgress = true;

    if (!_canPlayCard(card, player: playerName)) {
      // Carte non jouable maintenant → retour en main + message
      _flyBackToHand(card);
      _draggingCardPlayer = null;
      _dropResolveInProgress = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Carte non jouable — suivez la couleur jouée'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (_isOverDropZone(_dragPos.value)) {
      final dropPos = _dragPos.value;
      setState(() => _draggingCard = null);
      _draggingCardPlayer = null;
      _dropResolveInProgress = false;
      _playCard(playerName, card, dropPos: dropPos);
      return;
    }
    // Ailleurs : retour animé de la carte vers sa place dans la main
    _flyBackToHand(card);
    _draggingCardPlayer = null;
    _dropResolveInProgress = false;
  }
  Widget _buildPlayerHand(List<CardModel> cards, {required String playerName}) {
    const cardWidth = 80.0;
    const cardHeight = 100.0;
    final playable = [
      for (final c in cards) _canPlayCard(c, player: playerName),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final overlap = cards.length <= 1
            ? 0.0
            : math.min(36.0, (available - cardWidth) / (cards.length - 1));
        final width = cards.isEmpty
            ? 0.0
            : math.min(available, cardWidth + (cards.length - 1) * overlap);
        final canPlay = _isHuman(playerName);
        return SizedBox(
          height: cardHeight,
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: width,
              child: Stack(
                alignment: Alignment.centerRight,
                children: [
                  for (var i = 0; i < cards.length; i++)
                    Positioned(
                      key: _cardKeyFor(cards[i]),
                      right: (cards.length - 1 - i) * overlap,
                      child: IgnorePointer(
                        ignoring: !(canPlay && playable[i]),
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: canPlay && playable[i]
                              ? (details) => _onCardPointerDown(
                                    cards[i],
                                    playerName,
                                    details,
                                  )
                              : null,
                           child: identical(_draggingCard, cards[i])
                               ? const SizedBox.shrink()
                               : cachedSvgAsset(
                                   cards[i].assetPath,
                                   width: cardWidth,
                                   height: cardHeight,
                                 ),
                       ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Rect _dropZoneRectFor(Size size) =>
      Rect.fromLTWH(0, 0, size.width, size.height - 150.0);

  Widget _buildDragMergedOverlay() {
    final card = _draggingCard;
    if (card == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _dragPos,
          builder: (context, _) {
            final size = MediaQuery.sizeOf(context);
            final pos = _dragPos.value;
            final over = _dropZoneRectFor(size).contains(pos);
            return Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: over
                        ? const Color(0x14FFC107)
                        : Colors.black.withValues(alpha: 0.12),
                  ),
                ),
                Positioned(
                  top: 70,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        over ? Icons.touch_app : Icons.touch_app_outlined,
                        color: over ? const Color(0xFFFFC107) : Colors.white54,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        over
                            ? 'Relâchez la carte !'
                            : 'Déposez la carte n\'importe où sur la table',
                        style: TextStyle(
                          color: over ? const Color(0xFFFFC107) : Colors.white70,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: pos.dx - 40,
                  top: pos.dy - 50,
                  child: Transform.scale(
                    scale: 1.07,
                    child: RepaintBoundary(
                      child: Container(
                        width: cardWidthValue,
                        height: cardHeightValue,
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(9)),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x59000000),
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: cachedSvgAsset(
                          card.assetPath,
                          width: cardWidthValue,
                          height: cardHeightValue,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _showTrickArea() {
    final size = MediaQuery.sizeOf(context);
    final played = gameLogic.currentTrick;
    return SizedBox.expand(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final playedCard in played) _buildPlacedCard(playedCard, size),
        ],
      ),
    );
  }

  Widget _buildPlacedCard(PlayedCard playedCard, Size size) {
    final position = playedCard.position;
    final left = position != null
        ? position.dx * size.width - 30
        : size.width / 2 - 30;
    final top = position != null
        ? position.dy * size.height - 38
        : size.height * 0.32;
    return Positioned(
      left: left,
      top: top,
      child: Transform.rotate(
        angle: playedCard.rotation * math.pi / 180,
        child: cachedSvgAsset(
          playedCard.card.assetPath,
          width: 60,
          height: 76,
        ),
      ),
    );
  }

  Future<void> _showCallBubble(String player, CallOption option) async {
    final label = '${_displayName(player)} : ${_callOptionLabel(option)}';
    setState(() {
      showCallBubble = true;
      callBubblePlayer = player;
      callBubbleText = label;
    });

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    setState(() {
      showCallBubble = false;
    });
  }

  Future<void> _dealRemainingCards() async {
    for (var player in gameLogic.order) {
      await Future.delayed(const Duration(milliseconds: 600), () {
        setState(() {
          _giveCards(player, 3);
        });
      });
    }

    if (widget.teamId != null && widget.isHost) {
      GameChannelService().send('dealing', {
        'order': gameLogic.order,
        'deal_type': 'final',
        'hand': gameLogic.aiHands[0].map((c) => c.toMap()).toList(),
        'est_hand': gameLogic.aiHands[1].map((c) => c.toMap()).toList(),
        'ouest_hand': gameLogic.aiHands[2].map((c) => c.toMap()).toList(),
        'sud_hand': gameLogic.playerHand.map((c) => c.toMap()).toList(),
      });
    }
  }

  Future<void> _finishBidding() async {
    gameLogic.biddingFinished = true;
    await _dealRemainingCards();
    final sorted = gameLogic.sortedSouthHand(gameLogic.callSystem.contractCall);
    setState(() {
      gameLogic.playerHand = sorted;
      if (_isHuman('Nord')) {
        gameLogic.aiHands[0] = BeloteRules.sortSouthHand(gameLogic.aiHands[0], gameLogic.callSystem.contractCall);
      }
      gameLogic.winningPlayer = gameLogic.callSystem.contractWinner;
    });

    if (widget.teamId != null && widget.isHost) {
      final initData = {
        'your_player': 'Nord',
        'host_player': 'Sud',
        'hand': gameLogic.aiHands[0].map((c) => c.toMap()).toList(),
        'est_hand': gameLogic.aiHands[1].map((c) => c.toMap()).toList(),
        'ouest_hand': gameLogic.aiHands[2].map((c) => c.toMap()).toList(),
        'sud_hand': gameLogic.playerHand.map((c) => c.toMap()).toList(),
        'contract_call': gameLogic.callSystem.contractCall?.name,
        'contract_winner': gameLogic.callSystem.contractWinner,
        'starter': gameLogic.players[gameLogic.starterIndex],
      };
      _lastInitGameData = initData;
      await GameChannelService().send('init_game', initData);
    }

    _startGame();
    if (!_isHuman(gameLogic.callSystem.currentPlayer)) {
      Future.delayed(Duration.zero, () => _playAITurn());
    } else {
    }
  }

  Future<void> _showCallPopup() async {
    final current = gameLogic.callSystem.currentPlayer;
    gameLogic.starterPlayer ??= current;

    if (widget.teamId != null && _isHuman(current) && !_isLocalPlayer(current)) {
      GameChannelService().send('bid_request', {
        'player': current,
        'available_calls': gameLogic.callSystem.availableCalls.map((c) => c.name).toList(),
        'hand': gameLogic.handFor(current).map((c) => c.toMap()).toList(),
        'est_hand': gameLogic.aiHands[1].map((c) => c.toMap()).toList(),
        'ouest_hand': gameLogic.aiHands[2].map((c) => c.toMap()).toList(),
        'sud_hand': gameLogic.playerHand.map((c) => c.toMap()).toList(),
      });
      _pendingBidCompleter = Completer<CallOption>();
      CallOption option;
      try {
        option = await _pendingBidCompleter!.future.timeout(const Duration(seconds: 15));
      } catch (_) {
        option = CallOption.pass;
      }
      _pendingBidCompleter = null;
      gameLogic.callSystem.makeCall(option);
      await _showCallBubble(current, option);

      if (_isContractProposal(option)) {
        await _processCounterAfterBid();
      }

      if (widget.isHost) {
        GameChannelService().send('bid_made', {
          'player': current,
          'call': option.name,
          'next_player': gameLogic.callSystem.currentPlayer,
        });
      }

      if (!gameLogic.callSystem.isFinished()) {
        await _showCallPopup();
      } else {
        await _finishBidding();
      }
    } else if (!_isHuman(current)) {
      final option = gameLogic.bestCallForPlayer(current);
      gameLogic.callSystem.makeCall(option);
      await _showCallBubble(current, option);

      if (_isContractProposal(option)) {
        await _processCounterAfterBid();
      }

      if (widget.teamId != null && widget.isHost) {
        GameChannelService().send('bid_made', {
          'player': current,
          'call': option.name,
          'next_player': gameLogic.callSystem.currentPlayer,
        });
      }

      if (!gameLogic.callSystem.isFinished()) {
        await _showCallPopup();
      } else {
        await _finishBidding();
      }
    } else {
      showDialog(
        context: context,
        builder: (_) => CallPopup(
          playerName: current,
          availableCalls: gameLogic.callSystem.availableCalls,
          timeoutSeconds: 10,
          onCall: (option) async {
            gameLogic.callSystem.makeCall(option);
            await _showCallBubble(current, option);

            if (_isContractProposal(option)) {
              await _processCounterAfterBid();
            }

            if (widget.teamId != null && widget.isHost) {
              GameChannelService().send('bid_made', {
                'player': current,
                'call': option.name,
                'next_player': gameLogic.callSystem.currentPlayer,
              });
            }

            if (!gameLogic.callSystem.isFinished()) {
              await _showCallPopup();
            } else {
              await _finishBidding();
            }
          },
        ),
      );
    }
  }

  bool _isContractProposal(CallOption option) {
    return BeloteRules.isContractProposal(option);
  }

  Future<void> _processCounterAfterBid() async {
    final counterCalled = await _handleCounterWindow();
    if (counterCalled) {
      await _handleSurCounterWindow();
    }
  }

  Future<bool> _handleCounterWindow() async {
    final currentPlayer = gameLogic.callSystem.currentPlayer;

    if (!_isHuman(currentPlayer)) return false;

    if (widget.teamId != null && !_isLocalPlayer(currentPlayer)) {
      return _handleTeamCounterWindow(currentPlayer, 'counter', 'Contrer ?', 5, CallOption.x2);
    }

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TimerChoiceDialog(
        title: '${_displayName(currentPlayer)} : Contrer ?',
        seconds: 5,
        options: const ['x2', 'Passer'],
      ),
    );

    if (result == 'x2') {
      gameLogic.callSystem.makeCall(CallOption.x2);
      if (widget.teamId != null && widget.isHost) {
        GameChannelService().send('bid_made', {
          'player': currentPlayer,
          'call': CallOption.x2.name,
          'next_player': gameLogic.callSystem.currentPlayer,
        });
      }
      await _showCallBubble(currentPlayer, CallOption.x2);
      return true;
    }
    return false;
  }

  Future<bool> _handleSurCounterWindow() async {
    final currentPlayer = gameLogic.callSystem.currentPlayer;

    if (!_isHuman(currentPlayer)) return false;

    if (widget.teamId != null && !_isLocalPlayer(currentPlayer)) {
      return _handleTeamCounterWindow(currentPlayer, 'sur_counter', 'Sur-contrer ?', 10, CallOption.x4);
    }

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TimerChoiceDialog(
        title: '${_displayName(currentPlayer)} : Sur-contrer ?',
        seconds: 10,
        options: const ['x4', 'Passer'],
      ),
    );

    if (result == 'x4') {
      gameLogic.callSystem.makeCall(CallOption.x4);
      if (widget.teamId != null && widget.isHost) {
        GameChannelService().send('bid_made', {
          'player': currentPlayer,
          'call': CallOption.x4.name,
          'next_player': gameLogic.callSystem.currentPlayer,
        });
      }
      await _showCallBubble(currentPlayer, CallOption.x4);
      return true;
    }
    return false;
  }

  Future<bool> _handleTeamCounterWindow(String player, String type, String title, int seconds, CallOption counterOption) async {
    final completer = Completer<String?>();
    final action = type == 'sur_counter' ? 'sur_counter_request' : 'counter_request';
    if (type == 'sur_counter') {
      _pendingSurCounterCompleter = completer;
    } else {
      _pendingCounterCompleter = completer;
    }
    GameChannelService().send(action, {
      'player': player,
      'seconds': seconds,
      'hand': gameLogic.handFor(player).map((c) => c.toMap()).toList(),
      'est_hand': gameLogic.aiHands[1].map((c) => c.toMap()).toList(),
      'ouest_hand': gameLogic.aiHands[2].map((c) => c.toMap()).toList(),
      'sud_hand': gameLogic.playerHand.map((c) => c.toMap()).toList(),
    });

    final localResult = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TimerChoiceDialog(
        title: '$title (${_displayName(player)})',
        seconds: seconds,
        options: type == 'sur_counter' ? const ['x4', 'Passer'] : const ['x2', 'Passer'],
      ),
    );

    if (localResult == counterOption.name) {
      _pendingCounterCompleter = null;
      _pendingSurCounterCompleter = null;
      gameLogic.callSystem.makeCall(counterOption);
      if (widget.isHost) {
        GameChannelService().send('bid_made', {
          'player': player,
          'call': counterOption.name,
          'next_player': gameLogic.callSystem.currentPlayer,
        });
      }
      await _showCallBubble(player, counterOption);
      return true;
    }

    String? guestResult;
    try {
      guestResult = await completer.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      guestResult = null;
    }
    if (type == 'sur_counter') {
      _pendingSurCounterCompleter = null;
    } else {
      _pendingCounterCompleter = null;
    }
    if (guestResult == counterOption.name) {
      gameLogic.callSystem.makeCall(counterOption);
      if (widget.isHost) {
        GameChannelService().send('bid_made', {
          'player': player,
          'call': counterOption.name,
          'next_player': gameLogic.callSystem.currentPlayer,
        });
      }
      await _showCallBubble(player, counterOption);
      return true;
    }
    return false;
  }

  Future<void> _handleCounterRequest(Map<String, dynamic> event) async {
    final player = event['player'] as String? ?? 'Nord';
    final seconds = (event['seconds'] as num?)?.toInt() ?? 5;
    _setHandsFromEvent(event);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TimerChoiceDialog(
        title: '${_displayName(player)} : Contrer ?',
        seconds: seconds,
        options: const ['x2', 'Passer'],
      ),
    );
    GameChannelService().send('counter_response', {
      'choice': result ?? 'pass',
    });
  }

  Future<void> _handleSurCounterRequest(Map<String, dynamic> event) async {
    final player = event['player'] as String? ?? 'Nord';
    final seconds = (event['seconds'] as num?)?.toInt() ?? 10;
    _setHandsFromEvent(event);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TimerChoiceDialog(
        title: '${_displayName(player)} : Sur-contrer ?',
        seconds: seconds,
        options: const ['x4', 'Passer'],
      ),
    );
    GameChannelService().send('sur_counter_response', {
      'choice': result ?? 'pass',
    });
  }

  void _setHandsFromEvent(Map<String, dynamic> event) {
    final handData = event['hand'] as List? ?? [];
    if (handData.isEmpty && !event.containsKey('hand')) return;
    setState(() {
      gameLogic.aiHands[0] = handData
          .map((c) => CardModel.fromMap(Map<String, dynamic>.from(c)))
          .toList();
      final estData = event['est_hand'] as List? ?? [];
      gameLogic.aiHands[1] = estData
          .map((c) => CardModel.fromMap(Map<String, dynamic>.from(c)))
          .toList();
      final ouestData = event['ouest_hand'] as List? ?? [];
      gameLogic.aiHands[2] = ouestData
          .map((c) => CardModel.fromMap(Map<String, dynamic>.from(c)))
          .toList();
      final sudData = event['sud_hand'] as List? ?? [];
      gameLogic.playerHand = sudData
          .map((c) => CardModel.fromMap(Map<String, dynamic>.from(c)))
          .toList();
    });
  }

  Widget _buildOverlapCardsRightToLeft(
    List<CardModel> cards, {
    bool showBack = false,
    void Function(CardModel)? onCardTap,
  }) {
    const cardWidth = 80.0;
    const cardHeight = 100.0;
    const overlap = 36.0;
    final width = cards.isEmpty
        ? 0.0
        : cardWidth + (cards.length - 1) * overlap;

    return SizedBox(
      height: cardHeight,
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: width,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              for (var i = 0; i < cards.length; i++)
                Positioned(
                  right: (cards.length - 1 - i) * overlap,
                  child: GestureDetector(
                    dragStartBehavior: DragStartBehavior.down,
                    onTap: onCardTap != null ? () => onCardTap(cards[i]) : null,
                    child: cachedSvgAsset(
                      (showBack && onCardTap == null)
                          ? "assets/images/card/dos.png"
                          : cards[i].assetPath,
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

  Widget _buildOverlapCardsTopToBottom(List<CardModel> cards) {
    const cardWidth = 100.0;
    const cardHeight = 60.0;
    const overlap = 24.0;
    final height = cards.isEmpty
        ? 0.0
        : cardHeight + (cards.length - 1) * overlap;

    return SizedBox(
      width: cardWidth,
      height: height,
      child: Align(
        alignment: Alignment.topCenter,
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
                    child: cachedSvgAsset(
                      "assets/images/card/dos.png",
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

  String _displayName(String player) {
    return widget.playerNames[player] ?? player;
  }

  Widget _playerAvatar(String player) {
    final isCurrentPlayer = gameLogic.callSystem.currentPlayer == player;
    final name = _displayName(player);
    final avatarUrl = widget.playerAvatars[player] ?? '';
    final showImage = _isHuman(player) && avatarUrl.isNotEmpty;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isCurrentPlayer ? Colors.yellow : Colors.transparent,
          width: 3,
        ),
      ),
      child: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey[300],
        backgroundImage: showImage ? cachedNetworkImage(avatarUrl) : null,
        child: showImage
            ? null
            : Text(
                name.isNotEmpty ? name[0].toUpperCase() : player[0],
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
      ),
    );
  }

  String _mappedPosition(String player) {
    if (widget.teamId == null) return player;
    if (widget.isHost) {
      // Host: Sud(me)→bottom, Nord(partner)→top, Ouest→left, Est→right
      return player;
    } else {
      // Guest: Nord(me)→bottom, Sud(partner)→top, Ouest→right, Est→left
      switch (player) {
        case "Nord": return "Sud";
        case "Sud": return "Nord";
        case "Est": return "Ouest";
        case "Ouest": return "Est";
        default: return player;
      }
    }
  }

  Widget _positionedMarker(String player, Color color) {
    final media = MediaQuery.sizeOf(context);
    final w = media.width;
    final h = media.height;
    final pos = _mappedPosition(player);
    switch (pos) {
      case "Nord":
        return Positioned(
          top: 80,
          left: w * 0.5 - 28,
          child: _playerAvatar(player),
        );
      case "Est":
        return Positioned(
          right: 12,
          top: h * 0.35,
          child: _playerAvatar(player),
        );
      case "Ouest":
        return Positioned(
          left: 12,
          top: h * 0.35,
          child: _playerAvatar(player),
        );
      case "Sud":
      default:
        return Positioned(
          bottom: 12,
          left: w * 0.5 - 28,
          child: _playerAvatar(player),
        );
    }
  }

  Widget _positionedCallBubble() {
    final media = MediaQuery.sizeOf(context);
    final w = media.width;
    final h = media.height;

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

    final pos = _mappedPosition(callBubblePlayer);
    switch (pos) {
      case "Nord":
        return Positioned(top: 12, left: w * 0.5 - 60, child: content);
      case "Est":
        return Positioned(right: 12, top: h * 0.4, child: content);
      case "Ouest":
        return Positioned(left: 12, top: h * 0.4, child: content);
      case "Sud":
      default:
        return Positioned(bottom: 160, left: w * 0.5 - 60, child: content);
    }
  }

  Widget _buildGameInfoBar() {
    final contractLabel = gameLogic.callSystem.contractCall != null
        ? _callOptionLabel(gameLogic.callSystem.contractCall!)
        : "En attente";
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
            onPressed: () {
              // Ici tu peux mettre une alerte de confirmation
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("Confirmation", textAlign: TextAlign.center),
                  content: const Text("Voulez-vous abandonner ?", textAlign: TextAlign.center),
                  actionsAlignment: MainAxisAlignment.center,
                  actions: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("Non", style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () {
                        Navigator.of(context).pop(); // ferme le dialogue
                        Navigator.pop(context); // quitte la page
                      },
                      child: const Text("Oui", style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
          ),
          Column(
            children: [
              const Text(
                "Score",
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                "${gameLogic.gameScore["NS"] ?? 0} - ${gameLogic.gameScore["EO"] ?? 0}",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Column(
            children: [
              const Text(
                "Contrat",
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                contractLabel,
                style: const TextStyle(
                  color: Colors.yellow,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (gameLogic.callSystem.contractWinner != null)
                Text(
                  _displayName(gameLogic.callSystem.contractWinner!),
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
            ],
          ),
          Column(
            children: [
              const Text(
                "Pli",
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                gameLogic.tricksPlayed.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Alignment _alignmentForPlayer(String player) {
    switch (player) {
      case "Nord":
        return const Alignment(0, -0.85);
      case "Est":
        return const Alignment(0.85, 0);
      case "Ouest":
        return const Alignment(-0.85, 0);
      case "Sud":
      default:
        return const Alignment(0, 0.85);
    }
  }

  Alignment _playOrigin(String player) {
    if (widget.teamId != null && !widget.isHost) {
      switch (player) {
        case "Nord": return const Alignment(0, 0.85);
        case "Sud": return const Alignment(0, -0.85);
        case "Est": return const Alignment(-0.85, 0);
        case "Ouest": return const Alignment(0.85, 0);
      }
    }
    return _alignmentForPlayer(player);
  }

  Alignment _dealAlignment(String player) {
    if (widget.teamId != null && !widget.isHost) {
      switch (player) {
        case "Nord": return const Alignment(0, 0.85);
        case "Sud": return const Alignment(0, -0.85);
        case "Est": return const Alignment(-0.85, 0);
        case "Ouest": return const Alignment(0.85, 0);
      }
    }
    return _alignmentForPlayer(player);
  }

  Widget _buildDealAnimation() {
    return AnimatedAlign(
      alignment: dealCardAtTarget
          ? _dealAlignment(animatingDealPlayer!)
          : Alignment.center,
      duration: dealAnimationDuration,
      curve: Curves.easeInOut,
      child: cachedSvgAsset(
        "assets/images/card/dos.png",
        width: 60,
        height: 80,
      ),
    );
  }

  double _handAngle(String player) {
    final origin = _playOrigin(player);
    return math.atan2(-origin.x, origin.y);
  }

  double _phase(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);

  Offset _handStart(String player) {
    final board = _boardSize();
    final o = _playOrigin(player);
    if (o.y > 0.5) return Offset(board.width / 2 - 44, board.height + 60);
    if (o.y < -0.5) return Offset(board.width / 2 - 44, -120);
    if (o.x > 0.5) return Offset(board.width + 60, board.height / 2);
    return Offset(-100, board.height / 2);
  }

  Widget _buildPlayAnimation() {
    final card = animatingPlayCard!;
    final player = animatingPlayPlayer!;
    return AnimatedBuilder(
      animation: _playController,
      builder: (context, _) {
        final t = _playController.value.clamp(0.0, 1.0);
        final rest = _playFrom;
        final target = _playTo;

        Offset cardPos;
        double cardScaleX = 1.0;
        double cardScaleY = 1.0;
        double cardRotation = 0;
        if (_playDropAndSettle) {
          // Chute gravitationnelle : la carte tombe d'au-dessus de la table
          // avec une accélération constante, pivote légèrement puis s'écrase
          // sur le tapis (squash) et rebondit une fois (bounceOut).
          final fromY = _playFrom.dy - _cardDropAboveTable;
          final fallEnd = 0.78; // fin de la chute libre
          if (t < fallEnd) {
            final fallP = Curves.easeInQuad.transform(t / fallEnd);
            cardPos = Offset(
              _playFrom.dx + (target.dx - _playFrom.dx) * Curves.easeOutCubic.transform(t),
              fromY + (target.dy - fromY) * fallP,
            );
            cardRotation = math.sin(t * math.pi) * 0.18 * (1 - t);
            // léger étirement vertical pendant la chute (stretch en Y)
            cardScaleX = 1.0 - 0.04 * fallP;
            cardScaleY = 1.0 + 0.04 * fallP;
          } else {
            // Impact + rebond (elastic out)
            final s = _phase(t, fallEnd, 1.0);
            cardPos = Offset(target.dx, target.dy);
            cardRotation = 0;
            // écraser à l'impact puis relâcher
            final bounce = Curves.elasticOut.transform(s);
            cardScaleX = 1.12 + (1 - bounce) * 0.14 * (1 - s);
            cardScaleY = 0.88 + (bounce - 1) * 0.14 * (1 - s);
          }
        } else if (t < 0.17) {
          cardPos = rest;
          cardScaleX = 1.0;
          cardScaleY = 1.0;
        } else if (t < 0.28) {
          cardPos = rest;
          final before = 1.0 + 0.09 * Curves.easeOut.transform(_phase(t, 0.17, 0.28));
          cardScaleX = before;
          cardScaleY = before;
        } else if (t < 0.80) {
          final p = _phase(t, 0.28, 0.80);
          final eased = Curves.easeInOutCubic.transform(p);
          cardPos = Offset(
            rest.dx + (target.dx - rest.dx) * eased,
            rest.dy + (target.dy - rest.dy) * eased -
                math.sin(p * math.pi) * 110,
          );
          cardScaleX = 1.09;
          cardScaleY = 1.09;
          cardRotation = math.sin(p * math.pi) * 0.15 *
              (target.dx >= rest.dx ? 1 : -1);
        } else {
          cardPos = target;
          final after = 1.09 - 0.09 * Curves.easeOutBack.transform(_phase(t, 0.80, 1.0));
          cardScaleX = after;
          cardScaleY = after;
        }

        final liftFactor = _playDropAndSettle
            ? 0.0
            : (t < 0.17
                ? 0.0
                : t < 0.80
                    ? _phase(t, 0.17, 0.45)
                    : 1.0 - _phase(t, 0.80, 1.0));

        Offset handPos;
        double handOpacity = 1.0;
        final gripOffset = const Offset(-4, 46);
        if (_playDropAndSettle) {
          handPos = const Offset(0, -300);
          handOpacity = 0.0;
        } else if (t < 0.17) {
          final p = Curves.easeOutCubic.transform(_phase(t, 0.0, 0.17));
          handPos = Offset.lerp(_handStart(player), rest + gripOffset, p)!;
        } else if (t < 0.80) {
          handPos = cardPos + gripOffset;
        } else {
          final p = _phase(t, 0.80, 1.0);
          handPos = Offset.lerp(
            target + gripOffset,
            _handStart(player),
            Curves.easeInCubic.transform(p),
          )!;
          handOpacity = 1.0 - p;
        }

        return Stack(
          children: [
            Positioned(
              left: cardPos.dx,
              top: cardPos.dy,
              child: Transform.rotate(
                angle: cardRotation,
                child: Transform.scale(
                  scaleX: cardScaleX,
                  scaleY: cardScaleY,
                  child: Container(
                    width: cardWidthValue,
                    height: cardHeightValue,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: 0.3 + 0.25 * liftFactor),
                          blurRadius: 6 + 12 * liftFactor,
                          offset: Offset(0, 2 + 8 * liftFactor),
                        ),
                      ],
                    ),
                    child: cachedSvgAsset(
                      card.assetPath,
                      width: cardWidthValue,
                      height: cardHeightValue,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: handPos.dx,
              top: handPos.dy,
              child: Opacity(
                opacity: handOpacity,
                child: Transform.rotate(
                  angle: _handAngle(player),
                  child: CustomPaint(
                    size: const Size(88, 116),
                    painter: const _PlayHandPainter(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final localPlayer = widget.teamId == null
        ? (widget.humanPlayers.isEmpty ? 'Sud' : widget.humanPlayers.first)
        : (widget.isHost ? 'Sud' : 'Nord');
    final localTeam = BeloteRules.teamOf(localPlayer);
    final localWon = overallWinner != null && overallWinner == localTeam;

    return Scaffold(
      body: Stack(
        key: _dragStackKey,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: Image.asset(
                "assets/images/background.jpg",
                fit: BoxFit.cover,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  // Barre d'infos (Score, Contrat, Pli)
                  RepaintBoundary(child: _buildGameInfoBar()),
                  
                  const SizedBox(height: 12),

                  // Nord (invité : affiche Sud face cachée)
                  if (_isGuestNetworked)
                    SizedBox(
                      height: 120,
                      child: RepaintBoundary(
                        child: _buildOverlapCardsRightToLeft(
                          gameLogic.playerHand,
                          showBack: true,
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 120,
                      child: RepaintBoundary(
                        child: _buildOverlapCardsRightToLeft(
                          gameLogic.aiHands[0],
                          showBack: !_isLocalPlayer('Nord'),
                          onCardTap: _isLocalPlayer('Nord')
                              ? (card) {
                                  if (gameLogic.canPlayCard(card, player: 'Nord')) {
                                    _playCard('Nord', card);
                                  }
                                }
                              : null,
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  // Centre avec Ouest et Est
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          child: RepaintBoundary(
                            child: _buildOverlapCardsTopToBottom(
                              _isGuestNetworked ? gameLogic.aiHands[1] : gameLogic.aiHands[2],
                            ),
                          ),
                        ),
                        const Expanded(child: SizedBox.shrink()),
                        SizedBox(
                          width: 80,
                          child: RepaintBoundary(
                            child: _buildOverlapCardsTopToBottom(
                              _isGuestNetworked ? gameLogic.aiHands[2] : gameLogic.aiHands[1],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Sud (joueur humain) — pour l'invité : main de Nord en bas
                  SizedBox(
                    height: 140,
                    child: RepaintBoundary(
                      child: _isGuestNetworked
                          ? _buildPlayerHand(gameLogic.aiHands[0], playerName: "Nord")
                          : _buildPlayerHand(gameLogic.playerHand, playerName: "Sud"),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Zone de pli en overlay plein écran — chaque carte reste où elle est jouée
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: RepaintBoundary(child: _showTrickArea()),
            ),
          ),
          if (animatingDealCard != null)
            RepaintBoundary(child: _buildDealAnimation()),
          if (animatingPlayCard != null)
            RepaintBoundary(child: _buildPlayAnimation()),
          if (_draggingCard != null)
            RepaintBoundary(child: _buildDragMergedOverlay()),

          if (_guestDealing)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      cachedSvgAsset("assets/images/card/dos.png", height: 80),
                      const SizedBox(height: 12),
                      const Text("Distribution...", style: TextStyle(color: Colors.white, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ),

          if (showCallBubble) _positionedCallBubble(),
          
          // Afficher les avatars des joueurs avec contour pour le joueur actif
          _positionedMarker("Nord", Colors.black),
          _positionedMarker("Est", Colors.white),
          _positionedMarker("Ouest", Colors.white),
          _positionedMarker("Sud", Colors.black),

          // Overlay : résultat de la manche + bouton Suivant
          if (gameLogic.waitingForNextHand)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: Center(
                  child: Card(
                    color: Colors.blueGrey[900],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Résultat de la manche', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          if (handHistory.isNotEmpty && handHistory.last.dedans)
                            const Text('Dedans !', style: TextStyle(color: Colors.orangeAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('NS : +${gameLogic.lastHandDelta["NS"] ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                          Text('EO : +${gameLogic.lastHandDelta["EO"] ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 16)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: overallWinner == null
                                ? (widget.isHost
                                    ? () {
                                        _autoCloseTimer?.cancel();
                                        _hostReady = true;
                                        if (_guestReady || widget.teamId == null) {
                                          _hostReady = false;
                                          _guestReady = false;
                                          _applyLastHandAndNext();
                                        } else {
                                          setState(() {});
                                        }
                                      }
                                    : () {
                                        _autoCloseTimer?.cancel();
                                        GameChannelService().send('player_ready', {});
                                        setState(() {
                                          gameLogic.waitingForNextHand = false;
                                        });
                                      })
                                : null,
                            child: Text(_hostReady && widget.isHost && widget.teamId != null
                                ? 'Attente...'
                                : 'Continuer'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Overlay : résultat de la partie
          if (overallWinner != null)
            Positioned.fill(
              child: GameResultAnimation(
                won: localWon,
                title: localWon ? 'VICTOIRE !' : 'DÉFAITE',
                subtitle:
                    'Victoire : ${overallWinner == 'NS' ? 'Nord-Sud' : 'Est-Ouest'}',
                details: [
                  Text(
                    'NS : ${gameLogic.gameScore['NS'] ?? 0}  •  EO : ${gameLogic.gameScore['EO'] ?? 0}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 17,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                actions: [
                  GameResultAction(
                    label: 'Recommencer',
                    onPressed: () async {
                      await StatsService().recordGameResult(
                        gameName: 'belote',
                        won: localWon,
                        context: context,
                      );
                      setState(() {
                        gameLogic.resetGame();
                        overallWinner = null;
                        handHistory.clear();
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _dealCards();
                      });
                    },
                  ),
                  GameResultAction(
                    label: 'Statistiques',
                    color: const Color(0xFF9A5424),
                    onPressed: _showStatistics,
                  ),
                ],
              ),
            ),
          
          if (!gameLogic.biddingFinished)
            Positioned(
              top: MediaQuery.sizeOf(context).height / 2 - 40,
              left: MediaQuery.sizeOf(context).width / 2 - 30,
              child: cachedSvgAsset("assets/images/card/dos.png", height: 60),
            ),

          // Listener global (top) — reçoit tous les pointer events, passe-through translucent
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {},
            onPointerMove: _onCardPointerMove,
            onPointerUp: (_) => _tryResolveDragDrop(),
            onPointerCancel: (_) {
              _tryResolveDragDrop();
            },
            child: const SizedBox.expand(),
          ),
        ],
      ),
    );
  }
}

class _TimerChoiceDialog extends StatefulWidget {
  final String title;
  final int seconds;
  final List<String> options;

  const _TimerChoiceDialog({
    required this.title,
    required this.seconds,
    required this.options,
  });

  @override
  State<_TimerChoiceDialog> createState() => _TimerChoiceDialogState();
}

class _TimerChoiceDialogState extends State<_TimerChoiceDialog> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining > 1) {
        setState(() => _remaining--);
      } else {
        _timer?.cancel();
        if (mounted) Navigator.pop(context);
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
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_remaining}s',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: widget.options.map((opt) {
              final isAction = opt == 'x2' || opt == 'x4';
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isAction ? Colors.orange : Colors.grey,
                ),
                onPressed: () {
                  _timer?.cancel();
                  Navigator.pop(context, opt);
                },
                child: Text(opt,
                    style: const TextStyle(color: Colors.white)),
              );
                }).toList(),
          ),
        ],
      ),
    );
  }
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

class _PlayHandPainter extends CustomPainter {
  const _PlayHandPainter();

  static Paint? _skinFill;
  static Paint? _skinHeatLarge;
  static Paint? _skinHeatSmall;
  static Paint? _skinOutlineMedField;
  static Paint? _skinOutlineThumb1Field;
  static Paint? _skinOutlineThumb2Field;
  static Paint? _creaseLarge;
  static Paint? _creaseSmall;
  static Paint? _nailFill;
  static Paint? _shadowFill;
  static Path? _crease1Path;
  static Path? _crease2Path;
  static const _gradTop = Color(0xFFF3C6A3);
  static const _gradBase = Color(0xFFDEA174);
  static const _outline = Color(0xFF9A6444);
  static const _crease = Color(0xFFA96F46);
  static const _nail = Color(0xFFF6DCC9);

  static Paint _skin() => _skinFill ??= Paint()
    ..shader = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_gradTop, _gradBase],
    ).createShader(const Rect.fromLTWH(-40, -110, 80, 120));

  static Paint _skinLarge() =>
      _skinHeatLarge ??= Paint()..color = _outline..style = PaintingStyle.stroke..strokeWidth = 1.7;

  static Paint _skinOutlineMed() =>
      _skinOutlineMedField ??= Paint()..color = _outline..style = PaintingStyle.stroke..strokeWidth = 1.3;

  static Paint _skinOutlineSmall() =>
      _skinHeatSmall ??= Paint()..color = _outline..style = PaintingStyle.stroke..strokeWidth = 1.1;

  static Paint _skinOutlineThumb1() =>
      _skinOutlineThumb1Field ??= Paint()..color = _outline..style = PaintingStyle.stroke..strokeWidth = 1.2;

  static Paint _skinOutlineThumb2() =>
      _skinOutlineThumb2Field ??= Paint()..color = _outline..style = PaintingStyle.stroke..strokeWidth = 1.0;

  static Paint _crease13() =>
      _creaseLarge ??= Paint()..color = _crease..style = PaintingStyle.stroke..strokeWidth = 1.3;

  static Paint _crease10() =>
      _creaseSmall ??= Paint()..color = _crease..style = PaintingStyle.stroke..strokeWidth = 1.0;

  static Paint _nailPaint() => _nailFill ??= Paint()..color = _nail;

  static Paint _shadowPaint() =>
      _shadowFill ??= Paint()..color = Colors.black.withValues(alpha: 0.25);

  static Path _crease1() =>
      _crease1Path ??= Path()
        ..moveTo(-21, -42)
        ..quadraticBezierTo(-6, -34, 12, -46)
        ..quadraticBezierTo(18, -49, 24, -44);

  static Path _crease2() =>
      _crease2Path ??= Path()
        ..moveTo(-17, -27)
        ..quadraticBezierTo(2, -21, 20, -31);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height);

    final skinPaint = _skin();
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(1, -8), width: 84, height: 22),
      _shadowPaint(),
    );

    RRect rounded(double x, double y, double w, double h, double r) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));

    final palm = rounded(-27, -68, 54, 48, 15);
    canvas.drawRRect(palm, skinPaint);
    canvas.drawRRect(palm, _skinLarge());

    canvas.drawPath(_crease1(), _crease13());
    canvas.drawPath(_crease2(), _crease10());

    const fingers = [
      (-19.0, 9.2, 24.0),
      (-6.3, 10.4, 29.0),
      (6.3, 10.8, 32.0),
      (19.0, 9.8, 26.5),
    ];
    for (final (fx, fw, total) in fingers) {
      final seg1 = total * 0.55;
      final seg2 = total - seg1;
      final r1 = rounded(fx - fw / 2, -68 - seg1, fw, seg1 + 1.5, fw / 2);
      canvas.drawRRect(r1, skinPaint);
      final r2 = rounded(
        fx - fw / 2,
        -68 - seg1 - seg2,
        fw,
        seg2 + 1.0,
        fw / 2,
      );
      canvas.drawRRect(r2, skinPaint);
      canvas.drawRRect(r1, _skinOutlineMed());
      canvas.drawRRect(r2, _skinOutlineSmall());
      canvas.drawLine(
        Offset(fx - fw / 2 + 1.5, -68 - seg1),
        Offset(fx + fw / 2 - 1.5, -68 - seg1),
        _crease10(),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(fx, -68 - total + fw * 0.32),
          width: fw * 0.5,
          height: fw * 0.33,
        ),
        _nailPaint(),
      );
    }

    canvas.save();
    canvas.translate(-26, -24);
    canvas.rotate(-0.55);
    final thumb1 = rounded(-6.2, -15, 12.4, 17, 6.2);
    canvas.drawRRect(thumb1, skinPaint);
    canvas.drawRRect(thumb1, _skinOutlineThumb1());
    final thumb2 = rounded(-5, -25, 10, 12, 5);
    canvas.drawRRect(thumb2, skinPaint);
    canvas.drawRRect(thumb2, _skinOutlineThumb2());
    canvas.drawLine(
      const Offset(-6.2, -15),
      const Offset(6.2, -15),
      _crease10(),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlayHandPainter oldDelegate) => false;
}
