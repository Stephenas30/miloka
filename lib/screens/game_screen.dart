import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math';
import '../game/deck.dart';
import '../models/card_model.dart';
import '../game/call_system.dart';
import '../widgets/call_popup.dart';

class PlayedCard {
  final String player;
  final CardModel card;
  PlayedCard(this.player, this.card);
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late Deck deck;
  late CallSystem callSystem;

  List<CardModel> playerHand = [];
  List<List<CardModel>> aiHands = [[], [], []]; // Nord, Est, Ouest

  bool showCallBubble = false;
  String callBubblePlayer = "";
  String callBubbleText = "";
  bool biddingFinished = false;
  bool gameStarted = false;
  bool gameOver = false;
  String? starterPlayer;
  String? winningPlayer;
  int tricksPlayed = 0;
  List<PlayedCard> currentTrick = [];
  Map<String, int> teamPoints = {"NS": 0, "EO": 0};

  CardModel? animatingDealCard;
  String? animatingDealPlayer;
  bool dealCardAtTarget = false;
  CardModel? animatingPlayCard;
  String? animatingPlayPlayer;
  bool playCardAtCenter = false;
  final Duration dealAnimationDuration = const Duration(milliseconds: 500);
  final Duration playAnimationDuration = const Duration(milliseconds: 450);

  late List<String> order; // ordre de distribution
  final List<String> players = ["Nord", "Est", "Sud", "Ouest"];

  @override
  void initState() {
    super.initState();
    deck = Deck();
    deck.shuffle();

    callSystem = CallSystem(players);

    // Choisir aléatoirement le joueur qui commence
    final startIndex = Random().nextInt(players.length);
    order = [
      for (int i = 0; i < players.length; i++)
        players[(startIndex + i) % players.length],
    ];

    // Lancer la distribution animée
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dealCards();
    });
  }

  /// Distribution animée : 3 cartes chacun puis 2 cartes chacun
  Future<void> _dealCards() async {
    // Premier tour : 3 cartes chacun
    for (var player in order) {
      for (var i = 0; i < 3; i++) {
        await _dealCardToPlayer(player);
      }
    }

    // Deuxième tour : 2 cartes chacun
    for (var player in order) {
      for (var i = 0; i < 2; i++) {
        await _dealCardToPlayer(player);
      }
    }

    // Quand la distribution est terminée → lancer le popup d’appel
    await _showCallPopup();
  }

  Future<void> _dealCardToPlayer(String player) async {
    final card = deck.deal(1).first;
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
        aiHands[0].add(card);
      } else if (player == "Est") {
        aiHands[1].add(card);
      } else if (player == "Ouest") {
        aiHands[2].add(card);
      } else {
        playerHand.add(card);
      }
      animatingDealCard = null;
      animatingDealPlayer = null;
      dealCardAtTarget = false;
    });
  }

  void _giveCards(String player, int count) {
    if (player == "Nord") {
      aiHands[0].addAll(deck.deal(count));
    } else if (player == "Est") {
      aiHands[1].addAll(deck.deal(count));
    } else if (player == "Ouest") {
      aiHands[2].addAll(deck.deal(count));
    } else if (player == "Sud") {
      playerHand.addAll(deck.deal(count));
    }
  }

  List<CardModel> _handForPlayer(String player) {
    switch (player) {
      case "Nord":
        return aiHands[0];
      case "Est":
        return aiHands[1];
      case "Ouest":
        return aiHands[2];
      default:
        return playerHand;
    }
  }

  CallOption _bestCallForPlayer(String player) {
    final hand = _handForPlayer(player);
    final counts = <Suit, int>{
      Suit.trefle: 0,
      Suit.carreau: 0,
      Suit.coeur: 0,
      Suit.pique: 0,
    };

    for (final card in hand) {
      counts[card.suit] = counts[card.suit]! + 1;
    }

    final sortedSuits = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sortedSuits) {
      final option = _suitToCallOption(entry.key);
      if (callSystem.availableCalls.contains(option)) {
        return option;
      }
    }

    return CallOption.pass;
  }

  CallOption _suitToCallOption(Suit suit) {
    switch (suit) {
      case Suit.trefle:
        return CallOption.treble;
      case Suit.carreau:
        return CallOption.diamond;
      case Suit.coeur:
        return CallOption.heart;
      case Suit.pique:
        return CallOption.spade;
    }
  }

  String _callOptionLabel(CallOption option) {
    switch (option) {
      case CallOption.treble:
        return "Trèfle";
      case CallOption.diamond:
        return "Carreau";
      case CallOption.heart:
        return "Cœur";
      case CallOption.spade:
        return "Pique";
      case CallOption.sansAs:
        return "Sans As";
      case CallOption.toutAs:
        return "Tout As";
      case CallOption.x2:
        return "x2";
      case CallOption.x4:
        return "x4";
      case CallOption.pass:
        return "Passer";
    }
  }

  int _rankValue(Rank rank, CallOption mode) {
    switch (mode) {
      case CallOption.sansAs:
        switch (rank) {
          case Rank.as:
            return 800;
          case Rank.dix:
            return 700;
          case Rank.roi:
            return 600;
          case Rank.dame:
            return 500;
          case Rank.valet:
            return 400;
          case Rank.neuf:
            return 300;
          case Rank.huit:
            return 200;
          case Rank.sept:
            return 100;
        }
      case CallOption.toutAs:
      default:
        switch (rank) {
          case Rank.valet:
            return 800;
          case Rank.neuf:
            return 700;
          case Rank.as:
            return 600;
          case Rank.dix:
            return 500;
          case Rank.roi:
            return 400;
          case Rank.dame:
            return 300;
          case Rank.huit:
            return 200;
          case Rank.sept:
            return 100;
        }
    }
  }

  List<CardModel> _sortedSouthHand(CallOption? contractCall) {
    final cards = List<CardModel>.from(playerHand);
    Suit? calledSuit;
    if (contractCall == CallOption.treble) calledSuit = Suit.trefle;
    if (contractCall == CallOption.diamond) calledSuit = Suit.carreau;
    if (contractCall == CallOption.heart) calledSuit = Suit.coeur;
    if (contractCall == CallOption.spade) calledSuit = Suit.pique;

    final defaultMode = contractCall == CallOption.sansAs
        ? CallOption.sansAs
        : contractCall == CallOption.toutAs
        ? CallOption.toutAs
        : CallOption.sansAs;

    final suitOrder = <Suit>[];
    if (calledSuit != null) {
      suitOrder.add(calledSuit);
      for (var suit in Suit.values) {
        if (suit != calledSuit) suitOrder.add(suit);
      }
    } else {
      suitOrder.addAll(Suit.values);
    }

    cards.sort((a, b) {
      final aGroup = suitOrder.indexOf(a.suit);
      final bGroup = suitOrder.indexOf(b.suit);
      if (aGroup != bGroup) return aGroup.compareTo(bGroup);

      final aMode = calledSuit != null && a.suit == calledSuit
          ? CallOption.toutAs
          : defaultMode;
      final bMode = calledSuit != null && b.suit == calledSuit
          ? CallOption.toutAs
          : defaultMode;
      return _rankValue(b.rank, bMode).compareTo(_rankValue(a.rank, aMode));
    });

    return cards;
  }

  Suit? _contractTrumpSuit() {
    final contract = callSystem.contractCall;
    switch (contract) {
      case CallOption.treble:
        return Suit.trefle;
      case CallOption.diamond:
        return Suit.carreau;
      case CallOption.heart:
        return Suit.coeur;
      case CallOption.spade:
        return Suit.pique;
      default:
        return null;
    }
  }

  bool _isTrump(CardModel card) {
    if (callSystem.contractCall == CallOption.toutAs) return true;
    if (callSystem.contractCall == CallOption.sansAs) return false;
    final trumpSuit = _contractTrumpSuit();
    return card.suit == trumpSuit;
  }

  int _trickCardStrength(CardModel card, Suit? leadSuit) {
    final isTrump = _isTrump(card);
    if (isTrump) {
      return 1000 + _rankValue(card.rank, CallOption.toutAs);
    }
    if (leadSuit != null && card.suit == leadSuit) {
      return 200 + _rankValue(card.rank, CallOption.sansAs);
    }
    return 0;
  }

  int _cardPointValue(CardModel card) {
    final isTrump = _isTrump(card);
    final rank = card.rank;
    if (isTrump) {
      switch (rank) {
        case Rank.as:
          return 11;
        case Rank.dix:
          return 10;
        case Rank.roi:
          return 4;
        case Rank.dame:
          return 3;
        case Rank.valet:
          return 20;
        case Rank.neuf:
          return 14;
        case Rank.huit:
        case Rank.sept:
          return 0;
      }
    }
    switch (rank) {
      case Rank.as:
        return 11;
      case Rank.dix:
        return 10;
      case Rank.roi:
        return 4;
      case Rank.dame:
        return 3;
      case Rank.valet:
        return 2;
      case Rank.neuf:
      case Rank.huit:
      case Rank.sept:
        return 0;
    }
  }

  String _teamOf(String player) {
    return player == "Nord" || player == "Sud" ? "NS" : "EO";
  }

  List<CardModel> _handFor(String player) {
    if (player == "Nord") return aiHands[0];
    if (player == "Est") return aiHands[1];
    if (player == "Ouest") return aiHands[2];
    return playerHand;
  }

  List<CardModel> _legalCards(String player) {
    final hand = _handFor(player);
    if (currentTrick.isEmpty) return hand;
    final leadSuit = currentTrick.first.card.suit;
    final hasLead = hand.any((card) => card.suit == leadSuit);
    if (hasLead) {
      return hand.where((card) => card.suit == leadSuit).toList();
    }
    final trumps = hand.where(_isTrump).toList();
    if (trumps.isNotEmpty) return trumps;
    return hand;
  }

  String _nextPlayer(String current) {
    final index = players.indexOf(current);
    return players[(index + 1) % players.length];
  }

  void _startGame() {
    if (callSystem.contractWinner != null) {
      print("🎬 Début de la manche. Preneur : ${callSystem.contractWinner}");
      callSystem.setCurrentPlayer(callSystem.contractWinner!);
      setState(() {
        gameStarted = true;
        gameOver = false;
      });
      print("👉 Premier joueur de la manche : ${callSystem.currentPlayer}");
    }
  }

  void _resolveTrick() {
    final leadSuit = currentTrick.first.card.suit;
    PlayedCard winner = currentTrick.first;
    for (final played in currentTrick) {
      final currentStrength = _trickCardStrength(played.card, leadSuit);
      final winnerStrength = _trickCardStrength(winner.card, leadSuit);
      if (currentStrength > winnerStrength) {
        winner = played;
      }
    }
    final trickPoints = currentTrick.fold(
      0,
      (sum, played) => sum + _cardPointValue(played.card),
    );
    final team = _teamOf(winner.player);
    teamPoints[team] = teamPoints[team]! + trickPoints;
    tricksPlayed += 1;
    final nextLeader = winner.player;
    setState(() {
      currentTrick = [];
      callSystem.setCurrentPlayer(nextLeader);
      if (tricksPlayed >= 8) {
        gameOver = true;
        gameStarted = false;
      }
    });
    print("🏆 Gagnant du pli : $nextLeader (+$trickPoints pts pour $team)");
    if (!gameOver && nextLeader != "Sud") {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _playAITurn();
      });
    }
  }

  Future<void> _playCard(String player, CardModel card) async {
    print("🃏 $player joue ${card.assetPath}");
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
      currentTrick.add(PlayedCard(player, card));
      animatingPlayCard = null;
      animatingPlayPlayer = null;
      playCardAtCenter = false;
    });

    if (currentTrick.length >= 4) {
      await Future.delayed(const Duration(milliseconds: 400));
      _resolveTrick();
    } else {
      final next = _nextPlayer(player);
      print("➡️ Prochain joueur : $next");
      callSystem.setCurrentPlayer(next);
      if (next != "Sud") {
        await Future.delayed(const Duration(milliseconds: 700));
        await _playAITurn();
      }
    }
  }

  CardModel _chooseAICard(String player) {
    final legal = _legalCards(player);
    if (legal.isEmpty) return _handFor(player).first;
    if (currentTrick.isEmpty) {
      legal.sort(
        (a, b) =>
            _trickCardStrength(b, null).compareTo(_trickCardStrength(a, null)),
      );
      return legal.first;
    }
    final leadSuit = currentTrick.first.card.suit;
    legal.sort((a, b) {
      final aScore = _trickCardStrength(a, leadSuit);
      final bScore = _trickCardStrength(b, leadSuit);
      return bScore.compareTo(aScore);
    });
    return legal.first;
  }

  Future<void> _playAITurn() async {
    if (!gameStarted || gameOver) {
      print("⛔ IA ne joue pas : gameStarted=$gameStarted, gameOver=$gameOver");
      return;
    }
    final current = callSystem.currentPlayer;
    print("🤖 Tour IA : $current");
    if (current == "Sud") {
      print("⛔ C'est le tour de Sud, l'IA s'arrête.");
      return;
    }
    if (_handFor(current).isEmpty) {
      print("⛔ $current n'a plus de cartes.");
      return;
    }
    final card = _chooseAICard(current);
    await _playCard(current, card);
  }

  bool _canPlayCard(CardModel card) {
    if (callSystem.currentPlayer != "Sud") return false;
    if (!playerHand.contains(card)) return false;
    return _legalCards("Sud").contains(card);
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
                    child: Container(
                      decoration: BoxDecoration(
                        border: playerName == "Sud" && legal.contains(cards[i])
                            ? Border.all(color: Colors.yellowAccent, width: 2)
                            : null,
                      ),
                      child: SvgPicture.asset(
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
  }

  PlayedCard? _playedCardFor(String player) {
    for (final played in currentTrick) {
      if (played.player == player) return played;
    }
    return null;
  }

  Widget _showTrickArea() {
    final playedMap = {
      for (final player in ['Nord', 'Est', 'Sud', 'Ouest'])
        player: _playedCardFor(player),
    };

    return Column(
      children: [
        Text(
          gameOver
              ? 'Manche terminée : NS ${teamPoints['NS']} / EO ${teamPoints['EO']}'
              : 'Tour de : ${callSystem.currentPlayer}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Center(
                    child: Text(
                      'Pli',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: const Alignment(0, -0.9),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Nord', style: TextStyle(color: Colors.white, fontSize: 12)),
                    const SizedBox(height: 6),
                    _buildTrickCard(playedMap['Nord']),
                  ],
                ),
              ),
              Align(
                alignment: const Alignment(0.9, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Est', style: TextStyle(color: Colors.white, fontSize: 12)),
                    const SizedBox(height: 6),
                    _buildTrickCard(playedMap['Est']),
                  ],
                ),
              ),
              Align(
                alignment: const Alignment(-0.9, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Ouest', style: TextStyle(color: Colors.white, fontSize: 12)),
                    const SizedBox(height: 6),
                    _buildTrickCard(playedMap['Ouest']),
                  ],
                ),
              ),
              Align(
                alignment: const Alignment(0, 0.9),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Sud', style: TextStyle(color: Colors.white, fontSize: 12)),
                    const SizedBox(height: 6),
                    _buildTrickCard(playedMap['Sud']),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrickCard(PlayedCard? playedCard) {
    if (playedCard == null) {
      return Container(
        width: 42,
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white24,
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
    for (var player in order) {
      await Future.delayed(const Duration(milliseconds: 600), () {
        setState(() {
          _giveCards(player, 3);
        });
      });
    }
  }

  Future<void> _finishBidding() async {
    biddingFinished = true;
    print("Appels terminés, on commence la partie !");
    await _dealRemainingCards();
    final sorted = _sortedSouthHand(callSystem.contractCall);
    setState(() {
      playerHand = sorted;
      winningPlayer = callSystem.contractWinner;
    });

    _startGame();
    if (callSystem.currentPlayer != "Sud") {
      print("⏳ IA doit commencer la manche.");
      Future.delayed(Duration.zero, () => _playAITurn());
    } else {
      print("🎮 Sud commence la manche.");
    }
  }

  Future<void> _showCallPopup() async {
    final current = callSystem.currentPlayer;
    starterPlayer ??= current;

    if (current != "Sud") {
      // IA joue automatiquement en choisissant la couleur la plus présente
      final option = _bestCallForPlayer(current);
      await callSystem.makeCall(option);
      await _showCallBubble(current, option);

      if (!callSystem.isFinished()) {
        await _showCallPopup();
      } else {
        await _finishBidding();
      }
    } else {
      // Joueur humain → popup
      showDialog(
        context: context,
        builder: (_) => CallPopup(
          playerName: current,
          onCall: (option) async {
            await callSystem.makeCall(option);
            await _showCallBubble(current, option);
            if (!callSystem.isFinished()) {
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

  Widget _marker({required Color color}) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
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
          top: 4,
          left: w * 0.5 + 50,
          child: _marker(color: color),
        );
      case "Est":
        return Positioned(
          right: 4,
          top: h * 0.4 - 10,
          child: _marker(color: color),
        );
      case "Ouest":
        return Positioned(
          left: 4,
          top: h * 0.4 - 10,
          child: _marker(color: color),
        );
      case "Sud":
      default:
        return Positioned(
          bottom: 140,
          left: w * 0.5 + 50,
          child: _marker(color: color),
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
      appBar: AppBar(title: const Text("Partie contre IA")),
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
                  // Nord (IA 0)
                  SizedBox(
                    height: 120,
                    child: _buildOverlapCardsRightToLeft(
                      aiHands[0],
                      showBack: true,
                    ),
                  ),

                  const SizedBox(height: 12),

                  _showTrickArea(),

                  const SizedBox(height: 12),

                  // Centre avec Ouest et Est
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          child: _buildOverlapCardsTopToBottom(aiHands[2]),
                        ),
                        const Expanded(child: SizedBox.shrink()),
                        SizedBox(
                          width: 80,
                          child: _buildOverlapCardsTopToBottom(aiHands[1]),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Sud (joueur humain)
                  SizedBox(
                    height: 140,
                    child: _buildPlayerHand(playerHand, playerName: "Sud"),
                  ),
                ],
              ),
            ),
          ),

          if (showCallBubble) _positionedCallBubble(),
          if (starterPlayer != null)
            _positionedMarker(starterPlayer!, Colors.black),
          if (winningPlayer != null)
            _positionedMarker(winningPlayer!, Colors.white),
          if (!biddingFinished)
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
