import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../game/pool_game.dart';
import '../providers/auth_provider.dart';
import '../utils/image_cache.dart';
import '../utils/game_wake_lock.dart';
import '../widgets/friends_dialog.dart';
import 'pool_online_lobby_screen.dart';
import 'home_screen.dart';

const _poolInk = Color(0xFF17110C);
const _poolHudCard = Color(0xFF261A10);
const _poolHudLine = Color(0xFF4A3220);
const _poolHudText = Color(0xFFF1E6D3);
const _poolAccent = Color(0xFF1F9A3A);
const _poolTitleFont = 'BillardTitre';
const _poolTextFont = 'BillardLora';
const _poolBoldFont = 'BillardBold';

class PoolScreen extends StatefulWidget {
  const PoolScreen({super.key});

  @override
  State<PoolScreen> createState() => _PoolScreenState();
}

class _PoolScreenState extends State<PoolScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _poolInk,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/background.jpg', fit: BoxFit.cover),
          Padding(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isLandscape =
                    constraints.maxWidth > constraints.maxHeight;
                final compact = constraints.maxHeight < 380 ||
                    constraints.maxWidth < 340;
                final modes = [
                  _PoolModeCard(
                    emoji: '🔮',
                    title: 'Solo',
                    subtitle: 'Affrontez l’IA',
                    colors: const [Color(0xCCE53935), Color(0x66E53935)],
                    onTap: () => _chooseDifficulty(context),
                    compact: compact,
                  ),
                  _PoolModeCard(
                    emoji: '⚔️',
                    title: 'Multiplayer',
                    subtitle: 'À tour de rôle sur le même téléphone',
                    colors: const [Color(0xCCFDD835), Color(0x66FDD835)],
                    onTap: () => _openGame(context, PoolMode.local),
                    compact: compact,
                  ),
                  _PoolModeCard(
                    emoji: '🌐',
                    title: 'En ligne',
                    subtitle: 'Jouez contre un ami en réseau',
                    colors: const [Color(0xCC43A047), Color(0x6643A047)],
                    compact: compact,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PoolOnlineLobbyScreen(),
                      ),
                    ),
                  ),
                ];
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Billard 🎱',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: _poolTitleFont,
                        fontSize: compact ? 30 : 42,
                        fontWeight: FontWeight.bold,
                        shadows: const [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 12,
                            offset: Offset(2, 3),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: compact ? 3 : 5),
                    Text(
                      'Choisissez un mode de jeu',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: _poolTextFont,
                        fontSize: compact ? 13 : 16,
                      ),
                    ),
                    SizedBox(height: compact ? 12 : 24),
                    if (isLandscape)
                      Row(
                        children: [
                          for (
                            var index = 0;
                            index < modes.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(width: 10),
                            Expanded(child: modes[index]),
                          ],
                        ],
                      )
                    else
                      Column(
                        children: [
                          for (
                            var index = 0;
                            index < modes.length;
                            index++
                          ) ...[
                            if (index > 0) const SizedBox(height: 7),
                            SizedBox(
                              width: compact ? 210 : 240,
                              child: modes[index],
                            ),
                          ],
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
          const Positioned(top: 12, right: 12, child: _PoolAccountHeader()),
          Positioned(
            top: 12,
            left: 12,
            child: GestureDetector(
              onTap: () => showFriendsDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
          ),
          Positioned(
            bottom: 20,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x99000000),
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseDifficulty(BuildContext context) async {
    final level = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _poolHudCard,
        title: const Text(
          'Choisissez la difficulté',
          style: TextStyle(color: _poolHudText, fontFamily: _poolBoldFont),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in const [
              (0, 'Facile'),
              (1, 'Moyen'),
              (2, 'Difficile'),
            ])
              ListTile(
                title: Text(
                  entry.$2,
                  style: const TextStyle(
                    color: _poolHudText,
                    fontFamily: _poolTextFont,
                  ),
                ),
                onTap: () => Navigator.pop(dialogContext, entry.$1),
              ),
          ],
        ),
      ),
    );
    if (level != null && context.mounted) {
      await _openGame(context, PoolMode.solo, level: level);
    }
  }

  Future<void> _openGame(
    BuildContext context,
    PoolMode mode, {
    int level = 1,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PoolGameScreen(mode: mode, level: level),
      ),
    );
  }
}

class _PoolModeCard extends StatelessWidget {
  const _PoolModeCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.onTap,
    this.compact = false,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
         child: Container(
          height: compact ? 64 : 90,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 1 : 2,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0x4DFFFFFF), width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(
                emoji,
                style: TextStyle(fontSize: compact ? 22 : 30),
              ),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: _poolBoldFont,
                        fontSize: compact ? 13 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: _poolTextFont,
                        fontSize: compact ? 9 : 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contexte d’une partie en ligne Kadri (Supabase Realtime).
class KadriPoolSession {
  const KadriPoolSession({
    required this.seed,
    required this.playerIndex,
    required this.hostBet,
    required this.guestBet,
    required this.onSendLine,
    required this.remoteLines,
    required this.onGameFinished,
    required this.onClosed,
  });

  final int seed;
  final int playerIndex;
  final int hostBet;
  final int guestBet;
  final void Function(String line) onSendLine;
  final Stream<String> remoteLines;
  final void Function(int winnerIndex) onGameFinished;
  final VoidCallback onClosed;
}

class PoolGameScreen extends StatefulWidget {
  const PoolGameScreen({
    super.key,
    required this.mode,
    this.level = 1,
    this.kadri,
  });

  final PoolMode mode;
  final int level;
  final KadriPoolSession? kadri;

  @override
  State<PoolGameScreen> createState() => _PoolGameScreenState();
}

class _PoolGameScreenState extends State<PoolGameScreen>
    with SingleTickerProviderStateMixin {
  late final PoolGame _game;
  late final Ticker _ticker;
  StreamSubscription<String>? _remoteSubscription;
  bool _gameOverReported = false;
  int _lastTickSeconds = -1;
  String _lastTickMessage = '';
  PoolGameState _lastState = PoolGameState.aiming;
  int _lastCurrentPlayer = 0;
  late final ValueNotifier<int> _tableTick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    final kadri = widget.kadri;
    _game = PoolGame(
      mode: widget.mode,
      level: widget.level,
      myPlayerIndex: kadri?.playerIndex ?? 0,
      onSend: kadri?.onSendLine,
    );
    if (kadri != null) {
      _game
        ..start(seed: kadri.seed)
        ..ready = true;
      _remoteSubscription = kadri.remoteLines.listen(_onRemoteLine);
    }
    GameWakeLock.acquire();
    _ticker = createTicker((_) {
      _game.tick();
      final session = widget.kadri;
      if (session != null && _game.isGameOver && !_gameOverReported) {
        _gameOverReported = true;
        session.onGameFinished(_game.winner);
        _lastTickMessage = _game.message;
        _lastTickSeconds = _game.turnSecondsLeft;
        if (mounted) setState(() {});
        return;
      }
      if (!mounted) return;
      final fastState = _game.state == PoolGameState.moving ||
          _game.state == PoolGameState.striking;
      final aiCharging = widget.mode == PoolMode.solo &&
          _game.currentPlayer == 1 &&
          (_game.state == PoolGameState.aiming ||
              _game.state == PoolGameState.placingCue);
      if (fastState || aiCharging) _tableTick.value++;
      final secondsChanged = _game.turnSecondsLeft != _lastTickSeconds;
      final messageChanged = _game.message != _lastTickMessage;
      final stateChanged = _game.state != _lastState;
      final turnChanged = _game.currentPlayer != _lastCurrentPlayer;
      _lastTickSeconds = _game.turnSecondsLeft;
      _lastTickMessage = _game.message;
      _lastState = _game.state;
      _lastCurrentPlayer = _game.currentPlayer;
      if (secondsChanged || messageChanged || stateChanged || turnChanged) {
        setState(() {});
      }
    })..start();
  }

  void _onRemoteLine(String line) {
    if (!mounted) return;
    final fields = line.split(' ');
    setState(() {
      if (fields.first == 'START' && fields.length == 2) {
        final seed = int.tryParse(fields[1]);
        if (seed != null) {
          _game
            ..start(seed: seed)
            ..ready = true;
          _gameOverReported = false;
        }
        return;
      }
      if (fields.first == 'SHOT' && fields.length == 3) {
        final angle = double.tryParse(fields[1]);
        final power = double.tryParse(fields[2]);
        if (angle != null && power != null) _game.remoteShot(angle, power);
        return;
      }
      if (fields.first == 'PLACE' && fields.length == 3) {
        final x = double.tryParse(fields[1]);
        final y = double.tryParse(fields[2]);
        if (x != null && y != null) _game.remotePlace(x, y);
        return;
      }
      if (fields.first == 'STATE' && !_game.applySnapshot(line)) {
        _game.message = 'État de partie reçu invalide';
      }
    });
  }

  void _closeGame() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  Future<void> _confirmCloseGame() async {
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
    if (confirmed == true && mounted) _closeGame();
  }

  @override
  void dispose() {
    GameWakeLock.release();
    _ticker.dispose();
    _tableTick.dispose();
    _remoteSubscription?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _restart() {
    final kadri = widget.kadri;
    if (kadri != null) {
      if (kadri.playerIndex != 0) {
        setState(() => _game.message = 'Seul l’hôte peut relancer la partie.');
        return;
      }
      final seed = DateTime.now().microsecondsSinceEpoch;
      setState(() {
        _game
          ..start(seed: seed)
          ..ready = true;
        _gameOverReported = false;
      });
      kadri.onSendLine('START $seed');
      return;
    }
    setState(() => _game.start());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.kadri == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.kadri != null) widget.kadri!.onClosed();
      },
      child: Scaffold(
        backgroundColor: _poolInk,
        body: SafeArea(
          top: false,
          bottom: true,
          left: true,
          right: true,
          child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 5),
                _buildHud(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scale = math
                          .min(
                            (constraints.maxWidth - 12).clamp(
                                  0,
                                  double.infinity,
                                ) /
                                PoolGame.tableWidth,
                            (constraints.maxHeight - 12).clamp(
                                  0,
                                  double.infinity,
                                ) /
                                PoolGame.tableHeight,
                          )
                          .toDouble();
                      final boardSize = Size(
                        PoolGame.tableWidth * scale,
                        PoolGame.tableHeight * scale,
                      );
                      return Center(
                        child: SizedBox(
                          width: boardSize.width,
                          height: boardSize.height,
                          child: Listener(
                            onPointerDown: (event) {
                              final point = _toBoard(
                                event.localPosition,
                                scale,
                              );
                              _game.pointerDown(point.dx, point.dy);
                              if (_game.state == PoolGameState.aiming ||
                                  _game.state == PoolGameState.placingCue) {
                                _tableTick.value++;
                                setState(() {});
                              }
                            },
                            onPointerMove: (event) {
                              final point = _toBoard(
                                event.localPosition,
                                scale,
                              );
                              _game.pointerMove(point.dx, point.dy);
                              if (_game.state == PoolGameState.aiming ||
                                  _game.state == PoolGameState.placingCue) {
                                _tableTick.value++;
                                setState(() {});
                              }
                            },
                            onPointerUp: (_) {
                              _game.pointerUp();
                              _tableTick.value++;
                              setState(() {});
                            },
                            child: ValueListenableBuilder<int>(
                              valueListenable: _tableTick,
                              builder: (context, _, _) => RepaintBoundary(
                                child: CustomPaint(
                                  painter: _PoolTablePainter(_game),
                                  size: boardSize,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  ),
                ),
              ],
            ),
            if (_game.isGameOver) Positioned.fill(child: _buildGameOver()),
          ],
        ),
        ),
      ),
    );
  }

  Offset _toBoard(Offset point, double scale) =>
      Offset(point.dx / scale, point.dy / scale);

  Widget _buildHud() {
    final narrow = MediaQuery.sizeOf(context).width < 560;
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: _poolInk,
        border: Border(bottom: BorderSide(color: _poolHudLine)),
      ),
      child: Row(
        children: [
          _HudButton(
            icon: Icons.home,
            onPressed: _confirmCloseGame,
            tooltip: 'Accueil',
          ),
          if (_game.state == PoolGameState.aiming ||
              _game.state == PoolGameState.placingCue) ...[
            const SizedBox(width: 8),
            _TimerPill(seconds: _game.turnSecondsLeft),
          ],
          const SizedBox(width: 8),
          _PlayerBadge(
            title: _game.playerName(0),
            subtitle: _game.groupLabel(0),
            active: _game.currentPlayer == 0 && !_game.isGameOver,
            compact: narrow,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _game.message,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              strutStyle: const StrutStyle(fontSize: 13, height: 1.15),
              style: const TextStyle(
                color: _poolHudText,
                fontSize: 13,
                fontFamily: _poolBoldFont,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (widget.kadri != null &&
              (widget.kadri!.hostBet > 0 || widget.kadri!.guestBet > 0)) ...[
            _StakeBadge(
              hostBet: widget.kadri!.hostBet,
              guestBet: widget.kadri!.guestBet,
            ),
            const SizedBox(width: 8),
          ],
          _PlayerBadge(
            title: _game.playerName(1),
            subtitle: _game.groupLabel(1),
            active: _game.currentPlayer == 1 && !_game.isGameOver,
            compact: narrow,
          ),
          const SizedBox(width: 8),
          if (!narrow) const _PoolAccountHeader(compact: true),
        ],
      ),
    );
  }

  Widget _buildGameOver() {
    final playerIndex = widget.kadri?.playerIndex ?? 0;
    final won = _game.winner == playerIndex;
    final accent = won ? const Color(0xFFFFC107) : const Color(0xFFE53935);
    final title = won ? 'VICTOIRE !' : 'DÉFAITE';
    final subtitle = widget.mode == PoolMode.local
        ? '${_game.playerName(_game.winner)} gagne la partie !'
        : won
        ? 'Bravo, vous avez gagné la partie !'
        : 'Courage, retentez votre chance !';
    return ColoredBox(
      color: Colors.black.withValues(alpha: .72),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [accent.withValues(alpha: .28), Colors.transparent],
                radius: .9,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(won ? '🏆' : '😔', style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 4),
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: won
                        ? const [Color(0xFFFFF176), Color(0xFFFF9800)]
                        : const [Color(0xFFFF8A80), Color(0xFFC62828)],
                  ).createShader(bounds),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: _poolTitleFont,
                      fontSize: MediaQuery.sizeOf(context).width < 400 ? 40 : 54,
                      shadows: const [
                        Shadow(color: Color(0xFF3A1F00), blurRadius: 12),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: _poolTextFont,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    _GameOverButton(
                      label: 'Rejouer',
                      color: _poolAccent,
                      onPressed: _restart,
                    ),
                    _GameOverButton(
                      label: '🏠 Accueil',
                      color: const Color(0xFF9A5424),
                      onPressed: _confirmCloseGame,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StakeBadge extends StatelessWidget {
  const _StakeBadge({required this.hostBet, required this.guestBet});

  final int hostBet;
  final int guestBet;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 560;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: _poolHudCard,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _poolAccent, width: 2),
      ),
      child: Text(
        'Mise $hostBet / $guestBet 🪙',
        style: TextStyle(
          color: _poolHudText,
          fontSize: compact ? 10 : 12,
          fontFamily: _poolBoldFont,
        ),
      ),
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: _poolAccent,
        minimumSize: const Size(40, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Tooltip(
        message: tooltip ?? '',
        child: Icon(icon, size: 19),
      ),
    );
  }
}

class _TimerPill extends StatelessWidget {
  const _TimerPill({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final critical = seconds <= 3;
    final color = critical ? const Color(0xFFFF3B30) : _poolHudText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _poolHudCard,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: critical ? const Color(0xFFFF3B30) : _poolHudLine,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 18, color: color),
          const SizedBox(width: 5),
          Text(
            '${seconds}s',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              fontFamily: _poolBoldFont,
            ),
          ),
        ],
      ),
    );
  }
}

class _GameOverButton extends StatelessWidget {
  const _GameOverButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 54,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontFamily: _poolTextFont,
          ),
        ),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}

class _PlayerBadge extends StatelessWidget {
  const _PlayerBadge({
    required this.title,
    required this.subtitle,
    required this.active,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final bool active;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minWidth: compact ? 56 : 92,
        maxWidth: compact ? 96 : 155,
        minHeight: compact ? 44 : 48,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 6 : 7,
      ),
      decoration: BoxDecoration(
        color: _poolHudCard,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: active ? _poolAccent : _poolHudLine,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _poolHudText,
              fontSize: compact ? 9 : 11,
              fontFamily: _poolTextFont,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _poolHudText.withValues(alpha: .75),
              fontSize: compact ? 8 : 9,
              fontFamily: _poolTextFont,
            ),
          ),
        ],
      ),
    );
  }
}

class _PoolTablePainter extends CustomPainter {
  _PoolTablePainter(this.game) : _signature = _computeSignature(game);

  final PoolGame game;
  final int _signature;

  static int _computeSignature(PoolGame g) {
    final parts = <num>[
      g.aim,
      g.power,
      g.state.index.toDouble(),
      g.currentPlayer.toDouble(),
      g.winner.toDouble(),
      if (g.cuePlacementValid) 1 else 0,
    ];
    for (final ball in g.balls) {
      parts
        ..add(ball.x)
        ..add(ball.y)
        ..add(ball.pocketed ? 1 : 0);
    }
    return Object.hashAll(parts);
  }
  static const _felt = Color(0xFF0D7D25);
  static const _railLight = Color(0xFF9A5424);
  static const _railDark = Color(0xFF4A2410);

  static Paint? _framePaint;
  static Paint? _feltPaint;
  static Paint? _diamondPaint;
  static Paint? _pocketGoldPaint;
  static Paint? _pocketBlackPaint;
  static Paint? _cushionPaint;
  static Paint? _zonePaint;
  static Paint? _shadowPaint;
  static final Map<Color, Paint> _fillPaints = {};
  static TextPainter? _lineLabelPainter;
  static final Map<int, TextPainter> _numberPainters = {};

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / PoolGame.tableWidth,
      size.height / PoolGame.tableHeight,
    );
    canvas.save();
    canvas.scale(scale);
    _drawTable(canvas);
    if (game.state == PoolGameState.placingCue) {
      _drawPlacementZone(canvas);
    }
    for (final ball in game.balls.where((ball) => ball.id != 0)) {
      _drawBall(canvas, ball);
    }
    _drawBall(
      canvas,
      game.cueBall,
      alpha: game.state == PoolGameState.placingCue && !game.cuePlacementValid
          ? 105
          : 255,
    );
    if (game.state == PoolGameState.aiming) {
      _drawAim(canvas);
      _drawPower(canvas);
    }
    canvas.restore();
  }

  void _drawPlacementZone(Canvas canvas) {
    const edge = PoolGame.rail;
    const height = PoolGame.tableHeight;
    const line = PoolGame.headStringX;
    _zonePaint ??= Paint()
      ..shader = const LinearGradient(
        colors: [Color(0x662ECC71), Color(0x332ECC71)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(
        const Rect.fromLTRB(edge, edge, line, height - edge),
      );
    canvas.drawRect(
      const Rect.fromLTRB(edge, edge, line, height - edge),
      _zonePaint!,
    );
    final linePaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    _drawDashedLine(
      canvas,
      const Offset(line, edge),
      const Offset(line, height - edge),
      linePaint,
    );
    final lineLabel = _lineLabelPainter ??= (TextPainter(
          text: const TextSpan(
            text: 'LIGNE DE DÉPART',
            style: TextStyle(
              color: Color(0xCCFFFFFF),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout());
    lineLabel.paint(
      canvas,
      Offset(line - 8 - lineLabel.width, edge + 6),
    );
  }

  void _drawTable(Canvas canvas) {
    const width = PoolGame.tableWidth;
    const height = PoolGame.tableHeight;
    const edge = PoolGame.rail;
    _framePaint ??= Paint()
      ..shader = const LinearGradient(
        colors: [_railLight, _railDark, _railLight],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(const Rect.fromLTWH(0, 0, width, height));
    _feltPaint ??= Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        colors: [Color(0xFF22B43F), _felt],
        radius: 1.94,
      ).createShader(
        const Rect.fromLTWH(
          edge,
          edge,
          width - 2 * edge,
          height - 2 * edge,
        ),
      );
    _diamondPaint ??= Paint()..color = const Color(0xFFECDCAA);
    _pocketGoldPaint ??= Paint()..color = const Color(0xFFC9A24A);
    _pocketBlackPaint ??= Paint()..color = const Color(0xFF080808);
    _cushionPaint ??= Paint()..color = const Color(0xFF0B6A1F);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, width, height),
        const Radius.circular(22),
      ),
      _framePaint!,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(2, 2, width - 4, height - 4),
        const Radius.circular(22),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFF2A1307),
    );
    canvas.drawRect(
      const Rect.fromLTRB(
        edge - 10,
        edge - 10,
        width - edge + 10,
        height - edge + 10,
      ),
      _cushionPaint!,
    );
    canvas.drawRect(
      const Rect.fromLTRB(edge, edge, width - edge, height - edge),
      _feltPaint!,
    );
    final diamond = _diamondPaint!;
    for (var i = 1; i <= 7; i++) {
      if (i == 4) continue;
      final x = edge + (width - 2 * edge) * i / 8;
      canvas
        ..drawCircle(Offset(x, edge / 2 - 5), 3.5, diamond)
        ..drawCircle(Offset(x, height - edge / 2 + 5), 3.5, diamond);
    }
    for (var i = 1; i <= 3; i++) {
      final y = edge + (height - 2 * edge) * i / 4;
      canvas
        ..drawCircle(Offset(edge / 2 - 5, y), 3.5, diamond)
        ..drawCircle(Offset(width - edge / 2 + 5, y), 3.5, diamond);
    }
    for (final pocket in PoolGame.pocketsForDrawing) {
      canvas
        ..drawCircle(
          Offset(pocket[0], pocket[1]),
          PoolGame.pocketRadius + 3,
          _pocketGoldPaint!,
        )
        ..drawCircle(
          Offset(pocket[0], pocket[1]),
          PoolGame.pocketRadius,
          _pocketBlackPaint!,
        );
    }
  }

  static TextPainter _numberPainter(int id) {
    return _numberPainters.putIfAbsent(
      id,
      () => TextPainter(
        text: TextSpan(
          text: '$id',
          style: TextStyle(
            color: const Color(0xFF111111),
            fontSize: PoolGame.ballRadius * .7,
            fontFamily: _poolBoldFont,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  void _drawBall(Canvas canvas, PoolBall ball, {int alpha = 255}) {
    if (ball.pocketed) return;
    final radius = PoolGame.ballRadius;
    final center = Offset(ball.x, ball.y);
    _shadowPaint ??= Paint()..color = const Color(0x4D000000);
    if (alpha == 255) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center + const Offset(3, 4),
          width: radius * 2,
          height: radius * 1.6,
        ),
        _shadowPaint!,
      );
    } else {
      canvas.drawOval(
        Rect.fromCenter(
          center: center + const Offset(3, 4),
          width: radius * 2,
          height: radius * 1.6,
        ),
        Paint()..color = Colors.black.withAlpha(76 * alpha ~/ 255),
      );
    }
    final color = switch (ball.id) {
      0 => const Color(0xFFF7F7EF),
      8 => const Color(0xFF111111),
      _ when game.groupOf(ball.id) == 1 => const Color(0xFFD9302A),
      _ => const Color(0xFFF2A61C),
    };
    // Paint cache: full opacity à l'identique pour 60 fps ; couleur de repli allouée seulement pour les cas translucides (bille blanche invalide).
    if (alpha == 255) {
      _fillPaints.putIfAbsent(color, () => Paint()..color = color);
      canvas.drawCircle(center, radius, _fillPaints[color]!);
    } else {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = color.withAlpha(alpha),
      );
    }
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
    final rotation = ball.orientation;
    if (ball.id != 0) {
      for (final side in const [1, -1]) {
        if (side * rotation[8] <= 0) continue;
        canvas.save();
        canvas.transform(
          Float64List.fromList([
            rotation[0],
            rotation[3],
            0,
            0,
            side * rotation[1],
            side * rotation[4],
            0,
            0,
            0,
            0,
            1,
            0,
            center.dx + side * radius * rotation[2],
            center.dy + side * radius * rotation[5],
            0,
            1,
          ]),
        );
        canvas.drawCircle(
          Offset.zero,
          radius * .5,
          alpha == 255
              ? _fillPaints.putIfAbsent(
                    Colors.white,
                    () => Paint()..color = Colors.white,
                  )
              : Paint()..color = Colors.white.withAlpha(alpha),
        );
        final textPainter = _numberPainter(ball.id);
        textPainter.paint(
          canvas,
          Offset(-textPainter.width / 2, radius * .25 - textPainter.height),
        );
        canvas.restore();
      }
    }
    canvas.restore();
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(-1 / 3, -1 / 3),
          radius: 1.5,
          colors: [
            const Color(0xBFFFFFFF).withAlpha(191 * alpha ~/ 255),
            Colors.transparent,
            const Color(0x73000000).withAlpha(115 * alpha ~/ 255),
          ],
          stops: const [0, .45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 1.5)),
    );
    canvas.drawOval(
      Rect.fromLTRB(
        center.dx - radius * .55,
        center.dy - radius * .62,
        center.dx - radius * .2,
        center.dy - radius * .3,
      ),
      Paint()..color = Colors.white.withAlpha(150 * alpha ~/ 255),
    );
  }

  void _drawAim(Canvas canvas) {
    if (!game.canControl) return;
    final dx = math.cos(game.aim);
    final dy = math.sin(game.aim);
    var closest = double.infinity;
    PoolBall? target;
    for (final ball in game.balls) {
      if (ball.id == 0 || ball.pocketed) continue;
      final ox = ball.x - game.cueBall.x;
      final oy = ball.y - game.cueBall.y;
      final projection = ox * dx + oy * dy;
      if (projection <= 0) continue;
      final perpendicular = (ox * dy - oy * dx).abs();
      if (perpendicular < 2 * PoolGame.ballRadius) {
        final distance =
            projection -
            math.sqrt(
              4 * PoolGame.ballRadius * PoolGame.ballRadius -
                  perpendicular * perpendicular,
            );
        if (distance < closest) {
          closest = distance;
          target = ball;
        }
      }
    }
    final edgeDistance = _distanceToRail(dx, dy);
    if (target == null || edgeDistance < closest) closest = edgeDistance;
    final end = Offset(
      game.cueBall.x + dx * closest,
      game.cueBall.y + dy * closest,
    );
    final guidePaint = Paint()
      ..color = Colors.white.withAlpha(150)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    _drawDashedLine(
      canvas,
      Offset(game.cueBall.x, game.cueBall.y),
      end,
      guidePaint,
    );
    canvas.drawCircle(end, PoolGame.ballRadius, guidePaint);
    if (target != null && edgeDistance >= closest) {
      final normal = Offset(target.x - end.dx, target.y - end.dy);
      final length = normal.distance;
      if (length > 0) {
        canvas.drawLine(
          Offset(target.x, target.y),
          Offset(
            target.x + normal.dx / length * 45,
            target.y + normal.dy / length * 45,
          ),
          guidePaint,
        );
      }
    }
    final stickStart = Offset(game.cueBall.x, game.cueBall.y);
    final stickEnd =
        stickStart -
        Offset(dx, dy) * (PoolGame.ballRadius + 5 + game.power * 90 + 250);
    canvas.drawLine(
      stickStart - Offset(dx, dy) * (PoolGame.ballRadius + 5 + game.power * 90),
      stickEnd,
      Paint()
        ..color = const Color(0xFF8A552D)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      stickStart - Offset(dx, dy) * (PoolGame.ballRadius + 5 + game.power * 90),
      stickStart -
          Offset(dx, dy) * (PoolGame.ballRadius + 12 + game.power * 90),
      Paint()
        ..color = const Color(0xFF4AA3DF)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  double _distanceToRail(double dx, double dy) {
    final left = PoolGame.rail + PoolGame.ballRadius;
    final right = PoolGame.tableWidth - PoolGame.rail - PoolGame.ballRadius;
    final top = PoolGame.rail + PoolGame.ballRadius;
    final bottom = PoolGame.tableHeight - PoolGame.rail - PoolGame.ballRadius;
    var distance = double.infinity;
    if (dx > 0) distance = math.min(distance, (right - game.cueBall.x) / dx);
    if (dx < 0) distance = math.min(distance, (left - game.cueBall.x) / dx);
    if (dy > 0) distance = math.min(distance, (bottom - game.cueBall.y) / dy);
    if (dy < 0) distance = math.min(distance, (top - game.cueBall.y) / dy);
    return distance;
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final distance = (end - start).distance;
    const dash = 6.0;
    const gap = 6.0;
    final direction = (end - start) / distance;
    for (var offset = 0.0; offset < distance; offset += dash + gap) {
      final stop = math.min(offset + dash, distance);
      canvas.drawLine(
        start + direction * offset,
        start + direction * stop,
        paint,
      );
    }
  }

  void _drawPower(Canvas canvas) {
    const left = PoolGame.rail;
    const right = PoolGame.tableWidth - PoolGame.rail;
    canvas
      ..drawRect(
        const Rect.fromLTRB(left, 5, right, 11),
        Paint()..color = const Color(0xFF2A1307),
      )
      ..drawRect(
        Rect.fromLTRB(left, 5, left + (right - left) * game.power, 11),
        Paint()..color = const Color(0xFF1F9A3A),
      );
  }

  @override
  bool shouldRepaint(covariant _PoolTablePainter oldDelegate) =>
      oldDelegate._signature != _signature;
}

class _PoolAccountHeader extends StatelessWidget {
  const _PoolAccountHeader({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final coins =
            int.tryParse((auth.userProfile?['coins'] ?? '0').toString()) ?? 0;
        final username =
            auth.userProfile?['username']?.toString() ??
            auth.userProfile?['full_name']?.toString() ??
            'Profil';
        final avatarUrl = auth.userProfile?['avatar_url']?.toString();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: compact ? 12 : 14,
                    backgroundColor: Colors.white24,
                    backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                        ? cachedNetworkImage(avatarUrl)
                        : null,
                    child: avatarUrl == null || avatarUrl.isEmpty
                        ? Icon(
                            Icons.person,
                            color: Colors.white,
                            size: compact ? 12 : 14,
                          )
                        : null,
                  ),
                  SizedBox(width: compact ? 6 : 8),
                  SizedBox(
                    child: Text(
                      username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 13 : 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 6 : 8),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 12,
                vertical: compact ? 6 : 6,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.monetization_on,
                    color: Colors.amber,
                    size: compact ? 18 : 20,
                  ),
                  SizedBox(width: compact ? 4 : 6),
                  Text(
                    '$coins',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
