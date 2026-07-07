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
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
  with SingleTickerProviderStateMixin {
  late BeloteGameLogic gameLogic;

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

  @override
  void initState() {
    super.initState();
    gameLogic = BeloteGameLogic(players: players);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dealCards();
    });
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
      print("🎬 Début de la manche. Preneur : ${gameLogic.callSystem.contractWinner}");
      gameLogic.callSystem.setCurrentPlayer(gameLogic.callSystem.contractWinner!);
      setState(() {
        gameLogic.gameStarted = true;
        gameLogic.gameOver = false;
      });
      print("👉 Premier joueur de la manche : ${gameLogic.callSystem.currentPlayer}");
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
      }
    });
    if (!gameLogic.gameOver && gameLogic.callSystem.currentPlayer != 'Sud') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playAITurn();
      });
    }
  }

  void _applyLastHandAndNext() {
    bool shouldStartNextHand = true;

    setState(() {
      gameLogic.gameScore['NS'] = gameLogic.gameScore['NS']! + (gameLogic.lastHandDelta['NS'] ?? 0);
      gameLogic.gameScore['EO'] = gameLogic.gameScore['EO']! + (gameLogic.lastHandDelta['EO'] ?? 0);

      if (gameLogic.gameScore['NS']! >= 150 || gameLogic.gameScore['EO']! >= 150) {
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

    setState(() {
      gameLogic.currentTrick.add(PlayedCard(player, card));
      animatingPlayCard = null;
      animatingPlayPlayer = null;
      playCardAtCenter = false;
    });

    if (gameLogic.currentTrick.length >= 4) {
      await Future.delayed(const Duration(milliseconds: 400));
      _resolveTrick();
    } else {
      final next = _nextPlayer(player);
      print('➡️ Prochain joueur : $next');
      gameLogic.callSystem.setCurrentPlayer(next);
      if (next != 'Sud') {
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
    print('🤖 Tour IA : $current');
    if (current == 'Sud') {
      print("⛔ C'est le tour de Sud, l'IA s'arrête.");
      return;
    }
    if (_handFor(current).isEmpty) {
      print('⛔ $current n\'a plus de cartes.');
      return;
    }
    final card = _chooseAICard(current);
    await _playCard(current, card);
  }

  bool _canPlayCard(CardModel card) {
    return gameLogic.canPlayCard(card);
  }

  Widget _buildPlayerHand(List<CardModel> cards, {required String playerName}) {
    final legal = playerName == "Sud" ? _legalCards("Sud") : [];
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
                    onTap: playerName == "Sud" && _canPlayCard(cards[i])
                        ? () => _playCard("Sud", cards[i])
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

    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: const Alignment(0, -0.58),
            child: _buildTrickCard(playedMap['Nord']),
          ),
          // Est et Ouest rapprochés du centre
          Align(
            alignment: const Alignment(0.38, -0.05),
            child: _buildTrickCard(playedMap['Est']),
          ),
          Align(
            alignment: const Alignment(-0.38, -0.05),
            child: _buildTrickCard(playedMap['Ouest']),
          ),
          Align(
            alignment: const Alignment(0, 0.6),
            child: _buildTrickCard(playedMap['Sud']),
          ),
        ],
      ),
    );
  }

  Widget _buildTrickCard(PlayedCard? playedCard) {
    if (playedCard == null) {
      return Container(
        width: 50,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }
    return SvgPicture.asset(
      playedCard.card.assetPath,
      width: 42,
      height: 54,
    );
  }

  Future<void> _showCallBubble(String player, CallOption option) async {
    setState(() {
      showCallBubble = true;
      callBubblePlayer = player;
      callBubbleText = _callOptionLabel(option);
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
      gameLogic.winningPlayer = gameLogic.callSystem.contractWinner;
    });

    _startGame();
    if (gameLogic.callSystem.currentPlayer != 'Sud') {
      print('⏳ IA doit commencer la manche.');
      Future.delayed(Duration.zero, () => _playAITurn());
    } else {
      print('🎮 Sud commence la manche.');
    }
  }

  Future<void> _showCallPopup() async {
    final current = gameLogic.callSystem.currentPlayer;
    gameLogic.starterPlayer ??= current;

    if (current != 'Sud') {
      final option = gameLogic.bestCallForPlayer(current);
      await gameLogic.callSystem.makeCall(option);
      await _showCallBubble(current, option);

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
                  child: SvgPicture.asset(
                    showBack
                        ? "assets/images/card/dos.svg"
                        : cards[i].assetPath,
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

  Widget _playerAvatar(String player) {
    final isCurrentPlayer = gameLogic.callSystem.currentPlayer == player;
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
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[300],
        ),
        child: Center(
          child: Text(
            player[0],
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _positionedMarker(String player, Color color) {
    final media = MediaQuery.of(context);
    final w = media.size.width;
    final h = media.size.height;
    switch (player) {
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

    switch (callBubblePlayer) {
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
                  gameLogic.callSystem.contractWinner!,
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

  Widget _buildDealAnimation() {
    return AnimatedAlign(
      alignment: dealCardAtTarget
          ? _alignmentForPlayer(animatingDealPlayer!)
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
          : _alignmentForPlayer(animatingPlayPlayer!),
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
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/images/background.png",
              fit: BoxFit.cover,
            ),
          ),
          if (animatingDealCard != null) _buildDealAnimation(),
          if (animatingPlayCard != null) _buildPlayAnimation(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  // Barre d'infos (Score, Contrat, Pli)
                  _buildGameInfoBar(),
                  
                  const SizedBox(height: 12),

                  // Nord (IA 0)
                  SizedBox(
                    height: 120,
                    child: _buildOverlapCardsRightToLeft(
                      gameLogic.aiHands[0],
                      showBack: true,
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
                          child: _buildOverlapCardsTopToBottom(gameLogic.aiHands[2]),
                        ),
                        const Expanded(child: SizedBox.shrink()),
                        SizedBox(
                          width: 80,
                          child: _buildOverlapCardsTopToBottom(gameLogic.aiHands[1]),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Sud (joueur humain)
                  SizedBox(
                    height: 140,
                    child: _buildPlayerHand(gameLogic.playerHand, playerName: "Sud"),
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
                            onPressed: overallWinner == null ? _applyLastHandAndNext : null,
                            child: const Text('Suivant'),
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
