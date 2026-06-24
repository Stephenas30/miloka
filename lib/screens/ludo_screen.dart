import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../game/ludo/ludo_board_layout.dart';
import '../game/ludo/ludo_engine.dart';

class LudoScreen extends StatefulWidget {
  const LudoScreen({super.key});

  @override
  State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen>
    with SingleTickerProviderStateMixin {

  final LudoEngine _engine = LudoEngine();
  Timer? _aiTimer;
  late AnimationController _diceController;
  int _displayDice = 1;
  LudoPawn? _selectedPawn;
  bool _winnerDialogShown = false;
  bool _beginGame = false;

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
    _diceController.dispose();
    super.dispose();
  }

  void _scheduleAiTurn() {
    final isHumanTurn = _engine.currentPlayer.isHuman && _engine.winner == null;
    if (isHumanTurn) return;
    _aiTimer?.cancel();
    if (_engine.winner != null || _engine.currentPlayer.isHuman) return;

    _aiTimer = Timer(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      setState(() {
        _animateDiceRoll(_engine.rollDice());
        _engine.aiPlay();
      });
    });
  }

  Future<void> _animateDiceRoll(int value) async {
    _diceController.forward(from: 0).then((_) {
      if (mounted) setState(() => _displayDice = value);
    });
    for (var i = 0; i < 6; i++) {
      Future.delayed(Duration(milliseconds: i * 70), () {
        if (mounted)
          setState(() => _displayDice = math.Random().nextInt(6) + 1);
      });
    }
    await Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _displayDice = value);
    });

    _engine.scheduleTurnEnd(extraTurn: value == 6); 

    return Future.value();
  }

  void _onRollDice() {
    if (_engine.winner != null ||
        !_engine.currentPlayer.isHuman) {
      return;
    }
    setState(() {
      _selectedPawn = null;
      _animateDiceRoll(_engine.rollDice());
    });
    if (_engine.getValidMoves().isEmpty /* && _engine.diceRolled == false */) {
      _scheduleAiTurn();
    }
  }

  void _onPawnTap(LudoPawn pawn) {
    if (_engine.winner != null ||
        !_engine.currentPlayer.isHuman /* ||
        !_engine.diceRolled */) {
      return;
    }
    if (!_engine.canMovePawn(pawn)) return;

    setState(() {
      _selectedPawn = pawn;
      _engine.applyMove(pawn);
      _selectedPawn = null;
    });
  _scheduleAiTurn();
  }

  void _restartGame() {
    _aiTimer?.cancel();
    setState(() {
      _winnerDialogShown = false;
      _engine.reset();
      _displayDice = 1;
      _selectedPawn = null;
    });
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
    print('Humain => ${_engine.currentPlayer.isHuman}');


    if (_engine.winner != null && !_winnerDialogShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showWinnerDialog();
      });
    } else if (_engine.winner == null && !_engine.currentPlayer.isHuman) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAiTurn());
       print('àààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààà');
    }

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF006400),
        onPressed: () => Navigator.pop(context),
        child: const Icon(Icons.arrow_back, color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: _beginGame
              ? Column(
                  children: [
                    _buildHeader(),
                    Expanded(child: Center(child: _buildBoard())),
                    _buildControls(),
                    const SizedBox(height: 16),
                  ],
                )
              : _buildMain(),
        ),
      ),
    );
  }

  Widget _buildMain() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: () {
              setState(() {
                _beginGame = true;
              });
            },
            child: Text('Jouer Solo'),
          ),
          ElevatedButton(onPressed: () {}, child: Text('Jouer En ligne')),
          ElevatedButton(onPressed: () {}, child: Text('Jouer Multiplayer')),
          ElevatedButton(onPressed: () {}, child: Text('Sortir')),
        ],
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
        final cellSize = size / LudoBoardLayout.gridSize;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _LudoBoardPainter(cellSize: cellSize),
              ),
              ..._buildPawns(cellSize),
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
        final pos = LudoBoardLayout.pawnPosition(pawn, cellSize);

        final isSelectable =
            _engine.currentPlayer.isHuman &&
            /* _engine.diceRolled && */
            _engine.canMovePawn(pawn);

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

  Widget _buildControls() {
    final isHumanTurn = _engine.currentPlayer.isHuman && _engine.winner == null;

    //t('==> ${_engine.currentPlayerIndex}');
    //print(isHumanTurn);
    //print(!_engine.diceRolled);
    //print('/n/n');

    final canRoll = isHumanTurn /* && !_engine.diceRolled */;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _playerIndicator(LudoColor.red, true),
          _playerIndicator(LudoColor.green, false),
          _buildDice(canRoll),
          _playerIndicator(LudoColor.yellow, false),
          _playerIndicator(LudoColor.blue, false),
        ],
      ),
    );
  }

  Widget _playerIndicator(LudoColor color, bool isHuman) {
    final active = _engine.currentPlayer.color == color;
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: LudoBoardLayout.colorValues[color],
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? Colors.white : Colors.transparent,
              width: 3,
            ),
          ),
          child: isHuman
              ? const Icon(Icons.person, size: 16, color: Colors.white)
              : null,
        ),
        if (active)
          const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
      ],
    );
  }

  Widget _buildDice(bool canRoll) {
    //print('canRoll = $canRoll');
    return GestureDetector(
      onTap: canRoll ? _onRollDice : null,
      child: AnimatedBuilder(
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
      ),
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
