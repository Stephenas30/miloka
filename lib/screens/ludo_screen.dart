import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../game/ludo/ludo_board_layout.dart';
import '../game/ludo/ludo_engine.dart';
import '../providers/auth_provider.dart';
import '../service/stats_service.dart';
import 'profile_screen.dart';
import 'purchase_screen.dart';

class LudoScreen extends StatefulWidget {
  const LudoScreen({super.key});

  @override
  State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen>
    with SingleTickerProviderStateMixin {

  late final LudoEngine _engine;
  Timer? _aiTimer;
  late AnimationController _diceController;
  int _displayDice = 1;
  LudoPawn? _selectedPawn;
  bool _winnerDialogShown = false;
  bool _beginGame = false;
  bool _aiPlaying = false;
  bool _diceRolledThisTurn = false;
  bool _isDraggingDice = false;
  bool _isSlidingDice = false;

  Offset _diceDragOffset = Offset.zero;
  Offset _slideVelocity = Offset.zero;
  double _diceSlideAngle = 0;
  Timer? _slideTimer;
  final GlobalKey _stackKey = GlobalKey();
  double _cellSize = 0;
  Timer? _moveTimer;
  int? _movingPawnId;
  LudoColor? _movingPawnColor;
  List<Offset> _movePath = [];
  int _moveIndex = 0;

  @override
  void initState() {
    super.initState();
    _diceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    _moveTimer?.cancel();
    _slideTimer?.cancel();
    _diceController.dispose();
    super.dispose();
  }

  void _scheduleAiTurn() {
    if (_engine.winner != null || _engine.currentPlayer.isHuman) return;
    if (_aiTimer != null && _aiTimer!.isActive) return;
    if (_aiPlaying) return;

    _aiTimer = Timer(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      _aiPlaying = true;
      _aiTimer = null;
      final value = _engine.rollDice();
      setState(() {});
      _animateDiceRoll(value).then((_) {
        if (!mounted) return;
        _engine.aiPlay();
        final move = _engine.lastMove;

        if (move != null) {
          _startPawnMove(move.pawn.color, move.pawn.id, move.fromSteps, move.toSteps, () {
            if (!mounted) return;
            setState(() {
              if (_engine.winner == null) {
                if (_engine.extraTurn) {
                  _engine.scheduleTurnEnd(extraTurn: true);
                } else {
                  _engine.scheduleTurnEnd(extraTurn: false);
                }
              }
              _aiPlaying = false;
              _scheduleAiTurn();
            });
          });
        } else {
          setState(() {
            if (_engine.winner == null) {
              if (_engine.extraTurn) {
                _engine.scheduleTurnEnd(extraTurn: true);
              } else {
                _engine.scheduleTurnEnd(extraTurn: false);
              }
            }
            _aiPlaying = false;
            _scheduleAiTurn();
          });
        }
      });
    });
  }

  Future<void> _animateDiceRoll(int value) async {
    _diceController.forward(from: 0).then((_) {
      if (mounted) setState(() => _displayDice = value);
    });
    for (var i = 0; i < 6; i++) {
      Future.delayed(Duration(milliseconds: i * 70), () {
        if (mounted) {
          setState(() => _displayDice = math.Random().nextInt(6) + 1);
        }
      });
    }
    await Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _displayDice = value);
    });
  }

  void _onRollDice() {
    if (_engine.winner != null ||
        !_engine.currentPlayer.isHuman ||
        _diceRolledThisTurn) {
      return;
    }
    _diceRolledThisTurn = true;
    final value = _engine.rollDice();
    setState(() => _selectedPawn = null);
    _animateDiceRoll(value).then((_) {
      if (!mounted) return;
      setState(() {
        if (_engine.getValidMoves().isEmpty) {
          _diceRolledThisTurn = false;
          _engine.scheduleTurnEnd(extraTurn: false);
          _scheduleAiTurn();
        }
      });
    });
  }

  void _onPawnTap(LudoPawn pawn) {
    if (_engine.winner != null ||
        !_engine.currentPlayer.isHuman) {
      return;
    }
    if (!_engine.canMovePawn(pawn)) return;

    final fromSteps = pawn.stepsFromStart;
    final move = _engine.getValidMoves().firstWhere((m) => m.pawn.id == pawn.id);
    final toSteps = move.toSteps;

    final moved = _engine.applyMove(pawn);
    if (!moved) return;

    _startPawnMove(pawn.color, pawn.id, fromSteps, toSteps, () {
      if (!mounted) return;
      setState(() { _selectedPawn = null; _diceRolledThisTurn = false; });
      if (_engine.winner != null) return;
      if (_engine.extraTurn) {
        _engine.scheduleTurnEnd(extraTurn: true);
      } else {
        _engine.scheduleTurnEnd(extraTurn: false);
        _scheduleAiTurn();
      }
    });
  }

  void _startPawnMove(LudoColor color, int pawnId, int fromSteps, int toSteps, VoidCallback onComplete) {
    _movePath = LudoBoardLayout.movePath(color, fromSteps, toSteps, pawnId, _cellSize);
    if (_movePath.isEmpty) {
      onComplete();
      return;
    }
    _movingPawnId = pawnId;
    _movingPawnColor = color;
    _moveIndex = 0;

    _moveTimer?.cancel();
    _moveTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _moveIndex++;
      });
      if (_moveIndex >= _movePath.length) {
        timer.cancel();
        _movingPawnId = null;
        _movingPawnColor = null;
        _movePath = [];
        onComplete();
      }
    });
  }

  void _startDiceSlide() {
    _slideTimer?.cancel();
    const friction = 0.96;
    const minVelocity = 20.0;

    final renderBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final stackSize = renderBox.size;
    final diceSize = 60.0;
    const bottomPadding = 24.0;
    final topBound = -stackSize.height + bottomPadding + diceSize;
    final leftBound = -stackSize.width / 2 + diceSize / 2;
    final rightBound = stackSize.width / 2 - diceSize / 2;

    _slideTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _slideVelocity *= friction;

      if (_slideVelocity.distance < minVelocity) {
        timer.cancel();
        _animateDiceBack();
        return;
      }

      setState(() {
        _diceDragOffset += _slideVelocity * 0.016;
        _diceSlideAngle += _slideVelocity.distance * 0.0003;

        if (_diceDragOffset.dx < leftBound) {
          _diceDragOffset = Offset(leftBound, _diceDragOffset.dy);
          _slideVelocity = Offset(-_slideVelocity.dx, _slideVelocity.dy);
        } else if (_diceDragOffset.dx > rightBound) {
          _diceDragOffset = Offset(rightBound, _diceDragOffset.dy);
          _slideVelocity = Offset(-_slideVelocity.dx, _slideVelocity.dy);
        }
        if (_diceDragOffset.dy < topBound) {
          _diceDragOffset = Offset(_diceDragOffset.dx, topBound);
          _slideVelocity = Offset(_slideVelocity.dx, -_slideVelocity.dy);
        }
      });
    });
  }

  void _animateDiceBack() {
    const duration = Duration(milliseconds: 300);
    final startOffset = _diceDragOffset;
    final startAngle = _diceSlideAngle;
    final startTime = DateTime.now();

    _slideTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds / duration.inMilliseconds;
      final t = elapsed.clamp(0.0, 1.0);
      final easeOut = 1 - (1 - t) * (1 - t);

      setState(() {
        _diceDragOffset = Offset.lerp(startOffset, Offset.zero, easeOut)!;
        _diceSlideAngle = startAngle * (1 - easeOut);
      });

      if (t >= 1) {
        timer.cancel();
        setState(() {
          _isSlidingDice = false;
          _diceDragOffset = Offset.zero;
          _diceSlideAngle = 0;
          _slideVelocity = Offset.zero;
        });
        _onRollDice();
      }
    });
  }

  void _startGame(LudoColor color) {
    setState(() {
      _engine = LudoEngine(humanColor: color);
      _beginGame = true;
    });
    if (!_engine.currentPlayer.isHuman) {
      _scheduleAiTurn();
    }
  }

  Future<void> _showColorPicker() async {
    LudoColor? selectedColor;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Center(
            child: Text(
              'Choisis ta couleur',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          content: SizedBox(
            width: 220,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Quelle couleur veux-tu jouer ?',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: LudoColor.values.map((color) {
                    final isSelected = selectedColor == color;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = color),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: LudoBoardLayout.colorValues[color],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.black26,
                            width: isSelected ? 4 : 2,
                          ),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: LudoBoardLayout.colorValues[color]!.withValues(alpha: 0.6),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            color.label,
                            style: TextStyle(
                              color: color == LudoColor.yellow ? Colors.black87 : Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            Center(
              child: SizedBox(
                width: 180,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedColor != null
                        ? LudoBoardLayout.colorValues[selectedColor]
                        : Colors.grey.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: selectedColor != null
                      ? () {
                          Navigator.pop(ctx);
                          _startGame(selectedColor!);
                        }
                      : null,
                  child: const Text(
                    'Valider',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _restartGame() {
    _aiTimer?.cancel();
    _moveTimer?.cancel();
    _slideTimer?.cancel();
    setState(() {
      _winnerDialogShown = false;
      _engine.reset();
      _displayDice = 1;
      _selectedPawn = null;
      _movingPawnId = null;
      _movingPawnColor = null;
      _movePath = [];
      _aiPlaying = false;
      _diceRolledThisTurn = false;
      _isSlidingDice = false;
      _diceDragOffset = Offset.zero;
      _slideVelocity = Offset.zero;
      _diceSlideAngle = 0;
    });
  }

  Future<void> _finishGameWithStats() async {
    await StatsService().recordGameResult(
      gameName: 'ludo',
      won: _engine.winner == _engine.humanColor,
      context: context,
    );
  }

  void _showWinnerDialog() {
    if (_winnerDialogShown) return;
    _winnerDialogShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Partie terminée'),
        content: Text('${_engine.winner!.label} remporte la victoire !'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _restartGame();
            },
            child: const Text('Rejouer'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_beginGame) {
      if (_engine.winner != null && !_winnerDialogShown) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _finishGameWithStats();
            _showWinnerDialog();
          }
        });
      }
    }

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
      floatingActionButton: _beginGame
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF006400),
              onPressed: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back, color: Colors.white),
            )
          : null,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: _beginGame
              ? Stack(
                  key: _stackKey,
                  children: [
                    Column(
                      children: [
                        _buildHeader(),
                        Expanded(child: Center(child: _buildBoard())),
                      ],
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 24),
        child: GestureDetector(
          onTap: !_isDraggingDice && !_isSlidingDice &&
                  _engine.currentPlayer.isHuman &&
                  _engine.winner == null &&
                  !_diceRolledThisTurn
              ? _onRollDice
              : null,
          onPanStart: (_) {
            _slideTimer?.cancel();
            setState(() {
              _isDraggingDice = true;
              _isSlidingDice = false;
              _slideVelocity = Offset.zero;
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _diceDragOffset += details.delta;
            });
          },
          onPanEnd: (details) {
            final canRoll = _isDraggingDice &&
                _engine.currentPlayer.isHuman &&
                _engine.winner == null &&
                !_diceRolledThisTurn;

            _slideVelocity = details.velocity.pixelsPerSecond;

            if (_slideVelocity.distance > 50 && canRoll) {
              _isSlidingDice = true;
              _isDraggingDice = false;
              _startDiceSlide();
            } else {
              setState(() {
                _isDraggingDice = false;
                _diceDragOffset = Offset.zero;
              });
              if (canRoll) {
                _onRollDice();
              }
            }
          },
          child: Transform.translate(
            offset: _diceDragOffset,
            child: Transform.rotate(
              angle: _diceSlideAngle,
              child: _buildDice(
              _engine.currentPlayer.isHuman &&
              _engine.winner == null &&
              !_diceRolledThisTurn,
            ),
          ),
        ),
                      ),
                      ),
                    ),
                  ],
                )
              : _buildMain(),
        ),
      ),
    );
  }

  Widget _buildMain() {
    final authProvider = context.read<AuthProvider?>();
    final coins = int.tryParse((authProvider?.userProfile?['coins'] ?? '0').toString()) ?? 0;
    final avatarUrl = authProvider?.userProfile?['avatar_url']?.toString();
    final username = authProvider?.userProfile?['username']?.toString() ?? 'Profil';

    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Ludo',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
              const SizedBox(height: 40),
              _buildPawnChoice('Solo', LudoColor.red, () {
                _showColorPicker();
              }),
              const SizedBox(height: 20),
              _buildPawnChoice('En ligne', LudoColor.green, () {}),
              const SizedBox(height: 20),
              _buildPawnChoice('Multi', LudoColor.blue, () {}),
            ],
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl == null || avatarUrl.isEmpty
                            ? const Icon(Icons.person, color: Colors.white, size: 16)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(username,
                          style: const TextStyle(color: Colors.white, fontSize: 14)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
                      const SizedBox(width: 6),
                      Text('$coins',
                          style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 20,
          left: 16,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: const Color(0xFF006400),
            onPressed: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildPawnChoice(String label, LudoColor color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        height: 68,
        decoration: BoxDecoration(
          color: LudoBoardLayout.colorValues[color]!.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 140,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: LudoBoardLayout.colorValues[color],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 100),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFF8B0000)],
                ).createShader(bounds),
                child: const Text(
                  'Ludo',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 50),
              IconButton(
                onPressed: () {
                  _restartGame();
                },
                icon: Icon(Icons.refresh, color: Colors.amber),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _engine.message,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight) - 24;
        _cellSize = size / LudoBoardLayout.gridSize;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _LudoBoardPainter(cellSize: _cellSize),
              ),
              ..._buildPlayerInfo(),
              ..._buildPawns(_cellSize),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildPawns(double cellSize) {
    final widgets = <Widget>[];
    for (final player in _engine.players) {
      for (final pawn in player.pawns) {
        final isAnimating = _movingPawnId == pawn.id && _movingPawnColor == pawn.color;
        Offset pos;
        if (isAnimating && _moveIndex < _movePath.length) {
          pos = _movePath[_moveIndex];
        } else {
          pos = LudoBoardLayout.pawnPosition(pawn, cellSize);
        }

        final isSelectable =
            _engine.currentPlayer.isHuman &&
            _engine.canMovePawn(pawn) &&
            !isAnimating;

        final isSelected =
            _selectedPawn?.id == pawn.id && _selectedPawn?.color == pawn.color;

        widgets.add(
          Positioned(
            left: pos.dx - cellSize * 0.32,
            top: pos.dy - cellSize * 0.32,
            child: GestureDetector(
              onTap: isSelectable ? () => _onPawnTap(pawn) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: cellSize * 0.64,
                height: cellSize * 0.64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LudoBoardLayout.colorValues[pawn.color],
                  border: Border.all(
                    color: isSelected
                        ? Colors.white
                        : isSelectable
                        ? Colors.amber
                        : Colors.black87,
                    width: isSelected || isSelectable ? 3 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(1, 2),
                    ),
                  ],
                ),
                child: pawn.finished
                    ? const Icon(Icons.star, color: Colors.white, size: 14)
                    : null,
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  List<Widget> _buildPlayerInfo() {
    final authProvider = context.read<AuthProvider?>();
    final avatarUrl = authProvider?.userProfile?['avatar_url']?.toString();
    final username = authProvider?.userProfile?['username']?.toString() ?? 'Profil';

    return LudoColor.values.map((color) {
      final isHuman = color == _engine.humanColor;
      final displayName = isHuman ? username : 'IA ${color.label}';
      final icon = isHuman
          ? (avatarUrl != null && avatarUrl.isNotEmpty
              ? null as Widget?
              : const Icon(Icons.person, color: Colors.white, size: 14))
          : const Icon(Icons.smart_toy, color: Colors.white, size: 14);

      Widget avatar;
      if (isHuman && avatarUrl != null && avatarUrl.isNotEmpty) {
        avatar = CircleAvatar(
          radius: 8,
          backgroundImage: NetworkImage(avatarUrl),
        );
      } else {
        avatar = icon!;
      }

      return Positioned(
        left: color == LudoColor.green || color == LudoColor.red ? 4 : null,
        right: color == LudoColor.yellow || color == LudoColor.blue ? 4 : null,
        top: color == LudoColor.green || color == LudoColor.yellow ? 4 : null,
        bottom: color == LudoColor.red || color == LudoColor.blue ? 4 : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: LudoBoardLayout.colorValues[color]!.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              avatar,
              if (displayName.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  displayName,
                  style: TextStyle(
                    color: color == LudoColor.yellow ? Colors.black87 : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildDice(bool canRoll) {
    return AnimatedBuilder(
      animation: _diceController,
        builder: (context, child) {
          return Transform.rotate(
            angle: _diceController.value * math.pi * 2,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: canRoll ? Colors.white : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: canRoll ? Colors.amber : Colors.grey,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(2, 3),
                  ),
                ],
              ),
              child: Center(
                child: _displayDice > 0
                    ? _DiceFace(value: _displayDice)
                    : const SizedBox.shrink(),
              ),
            ),
          );
        },
      );
  }
}

class _DiceFace extends StatelessWidget {
  final int value;

  const _DiceFace({required this.value});

  @override
  Widget build(BuildContext context) {
    const dotPositions = {
      1: [Offset(0.5, 0.5)],
      2: [Offset(0.25, 0.25), Offset(0.75, 0.75)],
      3: [Offset(0.25, 0.25), Offset(0.5, 0.5), Offset(0.75, 0.75)],
      4: [
        Offset(0.25, 0.25),
        Offset(0.75, 0.25),
        Offset(0.25, 0.75),
        Offset(0.75, 0.75),
      ],
      5: [
        Offset(0.25, 0.25),
        Offset(0.75, 0.25),
        Offset(0.5, 0.5),
        Offset(0.25, 0.75),
        Offset(0.75, 0.75),
      ],
      6: [
        Offset(0.25, 0.2),
        Offset(0.75, 0.2),
        Offset(0.25, 0.5),
        Offset(0.75, 0.5),
        Offset(0.25, 0.8),
        Offset(0.75, 0.8),
      ],
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: dotPositions[value]!.map((p) {
            return Positioned(
              left: p.dx * w - 5,
              top: p.dy * h - 5,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.black87,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _LudoBoardPainter extends CustomPainter {
  final double cellSize;

  _LudoBoardPainter({required this.cellSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Fond blanc central
    paint.color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(6 * cellSize, 6 * cellSize, 3 * cellSize, 3 * cellSize),
      paint,
    );

    // Bases colorées
    _drawBase(canvas, LudoColor.red, 9, 0);
    _drawBase(canvas, LudoColor.green, 0, 0);
    _drawBase(canvas, LudoColor.yellow, 0, 9);
    _drawBase(canvas, LudoColor.blue, 9, 9);

    // Couloirs maison
    _drawHomeStretch(canvas, LudoColor.green);
    _drawHomeStretch(canvas, LudoColor.red);
    _drawHomeStretch(canvas, LudoColor.yellow);
    _drawHomeStretch(canvas, LudoColor.blue);

    // Chemin principal
    for (var i = 0; i < LudoBoardLayout.pathCoords.length; i++) {
      final c = LudoBoardLayout.pathCoords[i];
      final isSafe = LudoEngine.safeTrackIndices.contains(i);
      paint.color = isSafe ? Colors.grey.shade300 : Colors.white;
      canvas.drawRect(
        Rect.fromLTWH(c[0] * cellSize, c[1] * cellSize, cellSize, cellSize),
        paint,
      );
      paint.color = Colors.black26;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 0.5;
      canvas.drawRect(
        Rect.fromLTWH(c[0] * cellSize, c[1] * cellSize, cellSize, cellSize),
        paint,
      );
      paint.style = PaintingStyle.fill;

      if (isSafe) {
        paint.color = Colors.black38;
        canvas.drawCircle(
          Offset((c[0] + 0.5) * cellSize, (c[1] + 0.5) * cellSize),
          cellSize * 0.12,
          paint,
        );
      }
    }

    // Centre triangulaire
    _drawCenter(canvas);
  }

  void _drawBase(Canvas canvas, LudoColor color, int row, int col) {
    final paint = Paint()
      ..color = LudoBoardLayout.colorValues[color]!.withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          col * cellSize,
          row * cellSize,
          6 * cellSize,
          6 * cellSize,
        ),
        Radius.circular(cellSize * 0.3),
      ),
      paint,
    );

    paint.color = Colors.white.withValues(alpha: 0.9);
    for (final coords in LudoBoardLayout.baseCoords[color]!) {
      canvas.drawCircle(
        Offset((coords[0] + 0.5) * cellSize, (coords[1] + 0.5) * cellSize),
        cellSize * 0.35,
        paint,
      );
    }
  }

  void _drawHomeStretch(Canvas canvas, LudoColor color) {
    final paint = Paint()
      ..color = LudoBoardLayout.colorValues[color]!.withValues(alpha: 0.75);
    for (final c in LudoBoardLayout.homeStretchCoords[color]!) {
      canvas.drawRect(
        Rect.fromLTWH(c[0] * cellSize, c[1] * cellSize, cellSize, cellSize),
        paint,
      );
    }
  }

  void _drawCenter(Canvas canvas) {
    final center = Offset(7.5 * cellSize, 7.5 * cellSize);
    final r = cellSize * 1.5;
    final colors = [
      LudoBoardLayout.colorValues[LudoColor.blue]!,
      LudoBoardLayout.colorValues[LudoColor.red]!,
      LudoBoardLayout.colorValues[LudoColor.green]!,
      LudoBoardLayout.colorValues[LudoColor.yellow]!,
    ];

    for (var i = 0; i < 4; i++) {
      final paint = Paint()..color = colors[i];
      final path = Path();
      final angle = -math.pi / 4 + i * math.pi / 2;
      path.moveTo(center.dx, center.dy);
      path.arcTo(
        Rect.fromCircle(center: center, radius: r),
        angle,
        math.pi / 2,
        false,
      );
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
