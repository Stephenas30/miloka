import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../game/belote_game_logic.dart';
import '../game/belote_rules.dart';
import '../game/call_system.dart';
import '../game/deck.dart';
import '../game/played_card.dart';
import '../models/card_model.dart';
import '../widgets/call_popup.dart';
import '../service/stats_service.dart';
import '../service/game_channel_service.dart';

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
  bool playCardAtCenter = false;
  final Duration dealAnimationDuration = const Duration(milliseconds: 500);
  final Duration playAnimationDuration = const Duration(milliseconds: 450);

  final List<String> players = ["Nord", "Est", "Sud", "Ouest"];

  CardModel? _draggingCard;
  double _dragX = 0;
  double _dragY = 0;
  final GlobalKey _dragStackKey = GlobalKey();

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
  int _channelGen = -1;
  Completer<CallOption>? _pendingBidCompleter;

  bool _guestDealing = false;
  Timer? _guestDealTimer;

  @override
  void initState() {
    super.initState();
    gameLogic = BeloteGameLogic(players: players);

    if (widget.teamId != null) {
      _setupNetwork();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dealCards();
      });
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
    if (widget.teamId != null) {
      GameChannelService().disconnect();
    }
    super.dispose();
  }

  Future<void> _setupNetwork() async {
    final channel = GameChannelService();
    await channel.connect(widget.teamId!);
    _channelGen = channel.connectionGen;
    _networkSubscription = channel.events.listen(_handleNetworkEvent);
    print('[${widget.teamId}] _setupNetwork role=${widget.isHost ? "HOTE" : "INVITÉ"} gen=$_channelGen');

    if (widget.isHost) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dealCards();
      });
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
    if (action == null) { print('[${widget.teamId}] ⚠️ event with no action'); return; }

    if (GameChannelService().connectionGen != _channelGen) {
      print('[${widget.teamId}] ⚠️ stale event action=$action gen=${GameChannelService().connectionGen} != $_channelGen');
      return;
    }

    if (widget.isHost) {
      print('[${widget.teamId}] 📥 HOST event action=$action');
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
            print('[${widget.teamId}] ✅ guest_bid received call=$callName, completing completer');
            _pendingBidCompleter!.complete(CallOption.values.byName(callName));
          } else {
            print('[${widget.teamId}] ⚠️ guest_bid but no pending completer');
          }
      }
    } else {
      print('[${widget.teamId}] 📥 GUEST event action=$action');
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
      }
    }
  }

  Map<String, dynamic>? _lastInitGameData;

  void _handleGuestRequestInit() {
    print('[${widget.teamId}] _handleGuestRequestInit lastInit=${_lastInitGameData != null}');
    if (_lastInitGameData != null) {
      GameChannelService().send('init_game', _lastInitGameData!);
    }
  }

  void _handleGuestInit(Map<String, dynamic> event) {
    _initReceived = true;
    _requestInitTimer?.cancel();
    final contractWinner = event['contract_winner'] as String? ?? 'Nord';
    print('[${widget.teamId}] _handleGuestInit winner=$contractWinner gen=$_channelGen');
    final handData = event['hand'] as List? ?? [];
    gameLogic.aiHands[0] = handData.map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
    final estData = event['est_hand'] as List? ?? [];
    gameLogic.aiHands[1] = estData.map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
    final ouestData = event['ouest_hand'] as List? ?? [];
    gameLogic.aiHands[2] = ouestData.map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
    final sudData = event['sud_hand'] as List? ?? [];
    gameLogic.playerHand = sudData.map((c) => CardModel.fromMap(Map<String, dynamic>.from(c))).toList();
    gameLogic.gameStarted = true;
    gameLogic.biddingFinished = true;
    _autoCloseTimer?.cancel();
    gameLogic.waitingForNextHand = false;
    gameLogic.callSystem.contractCall = CallOption.values.byName(event['contract_call'] as String);
    gameLogic.callSystem.contractWinner = contractWinner;
    gameLogic.callSystem.setCurrentPlayer(contractWinner);
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

  void _handleGuestBidMade(Map<String, dynamic> event) {
    final player = event['player'] as String? ?? '';
    final callName = event['call'] as String? ?? 'pass';
    final option = CallOption.values.byName(callName);
    gameLogic.callSystem.makeCall(option);
    _showCallBubble(player, option);
    setState(() {});
  }

  void _handleBidRequest(Map<String, dynamic> event) {
    if (!mounted) { print('[${widget.teamId}] ⚠️ _handleBidRequest not mounted'); return; }
    final current = event['player'] as String? ?? 'Nord';
    final callsStr = (event['available_calls'] as List?)?.cast<String>() ?? [];
    final availableCalls = callsStr.map((s) => CallOption.values.byName(s)).toList();
    print('[${widget.teamId}] _handleBidRequest player=$current calls=${availableCalls.map((c) => c.name).join(",")}');

    final handData = event['hand'] as List? ?? [];

    setState(() {
      gameLogic.waitingForNextHand = false;
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

    _animateGuestDeal();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) { print('[${widget.teamId}] ⚠️ _handleBidRequest postFrame not mounted'); return; }
      print('[${widget.teamId}] _handleBidRequest showing CallPopup');
      showDialog(
        context: context,
        builder: (_) => CallPopup(
          playerName: current,
          availableCalls: availableCalls,
          onCall: (option) {
            print('[${widget.teamId}] guest_bid selected=${option.name}');
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
    final hand = _handFor(player);
    hand.removeWhere((c) => c.suit == card.suit && c.rank == card.rank);
    setState(() {
      gameLogic.currentTrick.add(PlayedCard(player, card));
      gameLogic.callSystem.setCurrentPlayer(event['next_player'] as String? ?? _nextPlayer(player));
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
    if (!gameLogic.gameOver) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) setState(() {});
      });
    }
  }

  void _handleGuestHandFinished(Map<String, dynamic> event) {
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
    });
  }

  void _handleGuestGameOver(Map<String, dynamic> event) {
    _autoCloseTimer?.cancel();
    setState(() {
      overallWinner = event['winner'] as String?;
    });
  }

  void _handleGuestBid(Map<String, dynamic> event) {
    final optionStr = event['call'] as String?;
    if (optionStr == null) return;
    final option = CallOption.values.byName(optionStr);
    gameLogic.callSystem.makeCall(option);
    final player = event['player'] as String? ?? 'Nord';
    _showCallBubble(player, option);

    gameLogic.callSystem.setCurrentPlayer(gameLogic.callSystem.contractWinner ?? player);
    if (!gameLogic.callSystem.isFinished()) {
      _showCallPopup();
    } else {
      _finishBidding();
    }
  }

  void _handleGuestPlay(Map<String, dynamic> event) {
    final cardData = event['card'] as Map<String, dynamic>?;
    if (cardData == null) { print('[${widget.teamId}] ⚠️ _handleGuestPlay cardData null'); return; }
    final card = CardModel.fromMap(cardData);
    final player = event['player'] as String? ?? 'Nord';
    final hand = _handFor(player);
    final contains = hand.contains(card);
    print('[${widget.teamId}] _handleGuestPlay player=$player card=${card.suit.name}-${card.rank.name} handSize=${hand.length} contains=$contains');
    if (contains) {
      _playCardFromNetwork(player, card);
    } else {
      print('[${widget.teamId}] ⚠️ _handleGuestPlay: card not in hand. Hand: ${hand.map((c) => "${c.suit.name}-${c.rank.name}").join(", ")}');
    }
  }

  Future<void> _playCardFromNetwork(String player, CardModel card) async {
    final hand = _handFor(player);
    setState(() {
      hand.remove(card);
      animatingPlayCard = card;
      animatingPlayPlayer = player;
      playCardAtCenter = false;
    });
    await Future.delayed(const Duration(milliseconds: 20));
    setState(() => playCardAtCenter = true);
    await Future.delayed(playAnimationDuration + const Duration(milliseconds: 50));
    setState(() {
      gameLogic.currentTrick.add(PlayedCard(player, card));
      animatingPlayCard = null;
      animatingPlayPlayer = null;
      playCardAtCenter = false;
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
        await Future.delayed(const Duration(milliseconds: 700));
        await _playAITurn();
      }
    }
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

    // Quand la distribution est terminée → lancer le popup d’appel
    await _showCallPopup();
  }

  Future<void> _dealCardToPlayer(String player) async {
    final card = gameLogic.deck.deal(1).first;
    setState(() {
      animatingDealCard = card;
      animatingDealPlayer = player;
      dealCardAtTarget = false;
    });

    await Future.delayed(const Duration(milliseconds: 20));
    setState(() {
      dealCardAtTarget = true;
    });
    await Future.delayed(dealAnimationDuration + const Duration(milliseconds: 50));

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
      print('[${widget.teamId}] 🎬 Début. Preneur : ${gameLogic.callSystem.contractWinner}');
      gameLogic.callSystem.setCurrentPlayer(gameLogic.callSystem.contractWinner!);
      setState(() {
        gameLogic.gameStarted = true;
        gameLogic.gameOver = false;
      });
      print('[${widget.teamId}] 👉 Premier joueur : ${gameLogic.callSystem.currentPlayer}');
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
        gameLogic.callSystem = CallSystem(players, initialIndex: gameLogic.starterIndex);
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
        });
      }
    }

    if (shouldStartNextHand) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dealCards();
      });
    }
  }

  Future<void> _playCard(String player, CardModel card) async {
    print('🃏 $player joue ${card.assetPath}');
    final hand = _handFor(player);
    setState(() {
      hand.remove(card);
      animatingPlayCard = card;
      animatingPlayPlayer = player;
      playCardAtCenter = false;
    });

    await Future.delayed(const Duration(milliseconds: 20));
    setState(() {
      playCardAtCenter = true;
    });
    await Future.delayed(playAnimationDuration + const Duration(milliseconds: 50));

    if (widget.teamId != null && !widget.isHost) {
      // Guest : envoie au host, ne fait rien d'autre (host broadcast card_played)
      setState(() {
        animatingPlayCard = null;
        animatingPlayPlayer = null;
        playCardAtCenter = false;
      });
      GameChannelService().send('play_card', {
        'player': player,
        'card': card.toMap(),
      });
      return;
    }

    setState(() {
      gameLogic.currentTrick.add(PlayedCard(player, card));
      animatingPlayCard = null;
      animatingPlayPlayer = null;
      playCardAtCenter = false;
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
      print('➡️ Prochain joueur : $next');
      gameLogic.callSystem.setCurrentPlayer(next);
      if (!_isHuman(next)) {
        await Future.delayed(const Duration(milliseconds: 700));
        await _playAITurn();
      }
    }
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
      print('⛔ IA ne joue pas : gameStarted=${gameLogic.gameStarted}, gameOver=${gameLogic.gameOver}');
      return;
    }
    final current = gameLogic.callSystem.currentPlayer;
    if (_isHuman(current)) {
      print("⛔ $current est humain, l'IA s'arrête.");
      return;
    }
    if (_handFor(current).isEmpty) {
      print('⛔ $current n\'a plus de cartes.');
      return;
    }
    final card = _chooseAICard(current);
    await _playCard(current, card);
  }

  bool _canPlayCard(CardModel card, {String player = 'Sud'}) {
    return gameLogic.canPlayCard(card, player: player);
  }

  void _onDragStart(CardModel card, String playerName, LongPressStartDetails details) {
    final RenderBox? box = _dragStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    setState(() {
      _draggingCard = card;
      _dragX = local.dx;
      _dragY = local.dy;
    });
  }

  void _onDragUpdate(LongPressMoveUpdateDetails details) {
    final RenderBox? box = _dragStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    setState(() {
      _dragX = local.dx;
      _dragY = local.dy;
    });
  }

  void _onDragEnd(CardModel card, String playerName) {
    if (!_canPlayCard(card, player: playerName)) {
      setState(() => _draggingCard = null);
      return;
    }
    final screenHeight = MediaQuery.of(context).size.height;
    if (_dragY < screenHeight * 0.5) {
      final playCard = card;
      setState(() => _draggingCard = null);
      _playCard(playerName, playCard);
    } else {
      setState(() => _draggingCard = null);
    }
  }

  Widget _buildPlayerHand(List<CardModel> cards, {required String playerName}) {
    const cardWidth = 80.0;
    const cardHeight = 100.0;
    const overlap = 36.0;
    final width = cards.isEmpty
        ? 0.0
        : cardWidth + (cards.length - 1) * overlap;

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
                    onTap: _isHuman(playerName) && _canPlayCard(cards[i], player: playerName)
                        ? () => _playCard(playerName, cards[i])
                        : null,
                    onLongPressStart: _isHuman(playerName) && _canPlayCard(cards[i], player: playerName)
                        ? (d) => _onDragStart(cards[i], playerName, d)
                        : null,
                    onLongPressMoveUpdate: _isHuman(playerName)
                        ? _onDragUpdate
                        : null,
                    onLongPressEnd: _isHuman(playerName) && _draggingCard != null
                        ? (_) => _onDragEnd(cards[i], playerName)
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

  PlayedCard? _playedCardFor(String player) {
    for (final played in gameLogic.currentTrick) {
      if (played.player == player) return played;
    }
    return null;
  }

  Widget _showTrickArea() {
    final playedMap = {
      for (final player in ['Nord', 'Est', 'Sud', 'Ouest'])
        player: _playedCardFor(player),
    };

    if (widget.teamId != null && !widget.isHost) {
      return SizedBox(
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: const Alignment(0, -0.45),
              child: _buildTrickCard(playedMap['Sud']),
            ),
            Align(
              alignment: const Alignment(0.33, -0.05),
              child: _buildTrickCard(playedMap['Ouest']),
            ),
            Align(
              alignment: const Alignment(-0.33, -0.05),
              child: _buildTrickCard(playedMap['Est']),
            ),
            Align(
              alignment: const Alignment(0, 0.45),
              child: _buildTrickCard(playedMap['Nord']),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: const Alignment(0, -0.45),
            child: _buildTrickCard(playedMap['Nord']),
          ),
          Align(
            alignment: const Alignment(0.33, -0.05),
            child: _buildTrickCard(playedMap['Est']),
          ),
          Align(
            alignment: const Alignment(-0.33, -0.05),
            child: _buildTrickCard(playedMap['Ouest']),
          ),
          Align(
            alignment: const Alignment(0, 0.45),
            child: _buildTrickCard(playedMap['Sud']),
          ),
        ],
      ),
    );
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

  Future<void> _showCallBubble(String player, CallOption option) async {
    final label = '${_displayName(player)} : ${_callOptionLabel(option)}';
    print('[${widget.teamId}] 📢 $label');
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
  }

  Future<void> _finishBidding() async {
    gameLogic.biddingFinished = true;
    print('Appels terminés, on commence la partie !');
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
      };
      _lastInitGameData = initData;
      print('[${widget.teamId}] envoi init_game winner=${gameLogic.callSystem.contractWinner}');
      await GameChannelService().send('init_game', initData);
    }

    _startGame();
    if (!_isHuman(gameLogic.callSystem.currentPlayer)) {
      print('⏳ IA doit commencer la manche.');
      Future.delayed(Duration.zero, () => _playAITurn());
    } else {
      print('🎮 ${gameLogic.callSystem.currentPlayer} commence la manche.');
    }
  }

  Future<void> _showCallPopup() async {
    final current = gameLogic.callSystem.currentPlayer;
    gameLogic.starterPlayer ??= current;
    print('[${widget.teamId}] _showCallPopup current=$current local=${_isLocalPlayer(current)} human=${_isHuman(current)}');

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
      final option = await _pendingBidCompleter!.future;
      _pendingBidCompleter = null;
      await gameLogic.callSystem.makeCall(option);
      await _showCallBubble(current, option);

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
      await gameLogic.callSystem.makeCall(option);
      await _showCallBubble(current, option);

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
          onCall: (option) async {
            await gameLogic.callSystem.makeCall(option);
            await _showCallBubble(current, option);

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
                    onTap: onCardTap != null ? () => onCardTap(cards[i]) : null,
                    child: SvgPicture.asset(
                      (showBack && onCardTap == null)
                          ? "assets/images/card/dos.svg"
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
                      "assets/images/card/dos.svg",
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
        backgroundImage: showImage ? NetworkImage(avatarUrl) : null,
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
    final media = MediaQuery.of(context);
    final w = media.size.width;
    final h = media.size.height;
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

  Widget _buildDragOverlay() {
    return Positioned(
      left: _dragX - 40,
      top: _dragY - 50,
      child: Transform.rotate(
        angle: 0.05,
        child: SvgPicture.asset(
          _draggingCard!.assetPath,
          width: 80,
          height: 100,
        ),
      ),
    );
  }

  Widget _buildDealAnimation() {
    return AnimatedAlign(
      alignment: dealCardAtTarget
          ? _dealAlignment(animatingDealPlayer!)
          : Alignment.center,
      duration: dealAnimationDuration,
      curve: Curves.easeInOut,
      child: SvgPicture.asset(
        "assets/images/card/dos.svg",
        width: 60,
        height: 80,
      ),
    );
  }

  Widget _buildPlayAnimation() {
    return AnimatedAlign(
      alignment: playCardAtCenter
          ? Alignment.center
          : _playOrigin(animatingPlayPlayer!),
      duration: playAnimationDuration,
      curve: Curves.easeInOut,
      child: SvgPicture.asset(
        animatingPlayCard!.assetPath,
        width: 80,
        height: 100,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        key: _dragStackKey,
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/images/background.png",
              fit: BoxFit.cover,
            ),
          ),
          if (animatingDealCard != null) _buildDealAnimation(),
          if (animatingPlayCard != null) _buildPlayAnimation(),
          if (_draggingCard != null) _buildDragOverlay(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  // Barre d'infos (Score, Contrat, Pli)
                  _buildGameInfoBar(),
                  
                  const SizedBox(height: 12),

                  // Nord (invité : affiche Sud face cachée)
                  if (_isGuestNetworked)
                    SizedBox(
                      height: 120,
                      child: _buildOverlapCardsRightToLeft(
                        gameLogic.playerHand,
                        showBack: true,
                      ),
                    )
                  else
                    SizedBox(
                      height: 120,
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

                  const SizedBox(height: 12),

                  // Centre avec Ouest et Est
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          child: _buildOverlapCardsTopToBottom(
                            _isGuestNetworked ? gameLogic.aiHands[1] : gameLogic.aiHands[2],
                          ),
                        ),
                        const Expanded(child: SizedBox.shrink()),
                        SizedBox(
                          width: 80,
                          child: _buildOverlapCardsTopToBottom(
                            _isGuestNetworked ? gameLogic.aiHands[2] : gameLogic.aiHands[1],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Sud (joueur humain) — pour l'invité : main de Nord en bas
                  SizedBox(
                    height: 140,
                    child: _isGuestNetworked
                        ? _buildPlayerHand(gameLogic.aiHands[0], playerName: "Nord")
                        : _buildPlayerHand(gameLogic.playerHand, playerName: "Sud"),
                  ),
                ],
              ),
            ),
          ),

          // Afficher la zone de pli en overlay pour ne pas impacter le layout des mains
          Positioned(
            top: MediaQuery.of(context).size.height * 0.33,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: true,
              child: _showTrickArea(),
            ),
          ),

          if (_guestDealing)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset("assets/images/card/dos.svg", height: 80),
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

          // Overlay : victoire de la partie
          if (overallWinner != null)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    color: Colors.green[800],
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Victoire : ${overallWinner == 'NS' ? 'Nord-Sud' : 'Est-Ouest'}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () async {
                              await StatsService().recordGameResult(
                                gameName: 'belote',
                                won: overallWinner == 'NS',
                                context: context,
                              );
                              // reset complet pour recommencer une nouvelle partie
                              setState(() {
                                gameLogic.resetGame();
                                overallWinner = null;
                                handHistory.clear();
                              });
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _dealCards();
                              });
                            },
                            child: const Text('Recommencer'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _showStatistics,
                            child: const Text('Statistiques'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          
          if (!gameLogic.biddingFinished)
            Positioned(
              top: MediaQuery.of(context).size.height / 2 - 40,
              left: MediaQuery.of(context).size.width / 2 - 30,
              child: SvgPicture.asset("assets/images/card/dos.svg", height: 60),
            ),
        ],
      ),
    );
  }
}
