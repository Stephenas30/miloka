import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../game/pool_game.dart';
import '../game/pool_network.dart';
import '../providers/auth_provider.dart';
import '../utils/image_cache.dart';
import '../widgets/friends_dialog.dart';

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
          Image.asset(
            'BillardAndroid/app/src/main/res/drawable/billardfond.png',
            fit: BoxFit.cover,
          ),
          const ColoredBox(color: Color(0xAA000000)),
          Padding(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isLandscape = constraints.maxWidth > constraints.maxHeight;
                final modes = [
                  _PoolModeCard(
                    emoji: '🤖',
                    title: 'Solo',
                    subtitle: 'Affrontez l’ordinateur',
                    accent: const Color(0xFF6FD602),
                    onTap: () => _chooseDifficulty(context),
                  ),
                  _PoolModeCard(
                    emoji: '👥',
                    title: 'Multiplayer',
                    subtitle: 'À tour de rôle sur le même téléphone',
                    accent: const Color(0xFF1267B5),
                    onTap: () => _openGame(context, PoolMode.local),
                  ),
                  _PoolModeCard(
                    emoji: '🌐',
                    title: 'En ligne',
                    subtitle: PoolNetwork.supportsLan
                        ? 'Jouez contre un ami en réseau'
                        : 'Disponible sur Android et iOS',
                    accent: const Color(0xFF6FD602),
                    onTap: PoolNetwork.supportsLan
                        ? () => _chooseNetwork(context)
                        : null,
                  ),
                ];
                return Column(
                  children: [
                    const SizedBox(height: 22),
                    Text(
                      'Billard 8',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFFFE6A0),
                        fontFamily: _poolTitleFont,
                        fontSize: 48,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 12,
                            offset: Offset(2, 3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Choisissez un mode de jeu',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: _poolTextFont,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: isLandscape
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var index = 0; index < modes.length; index++)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: modes[index],
                                    ),
                                  ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var index = 0; index < modes.length; index++)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: modes[index],
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          const Positioned(
            top: 12,
            right: 12,
            child: _PoolAccountHeader(),
          ),
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
                  child: Icon(
                    Icons.people_alt,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
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
          style: TextStyle(
            color: _poolHudText,
            fontFamily: _poolBoldFont,
          ),
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

  Future<void> _chooseNetwork(BuildContext context) async {
    final addressController = TextEditingController();
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _poolHudCard,
        title: const Text(
          'Jeu en ligne',
          style: TextStyle(
            color: _poolHudText,
            fontFamily: _poolBoldFont,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Les deux joueurs doivent être connectés au même Wi-Fi.',
              style: TextStyle(
                color: _poolHudText,
                fontFamily: _poolTextFont,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: addressController,
              keyboardType: TextInputType.url,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: _poolTextFont,
              ),
              decoration: const InputDecoration(
                labelText: 'Adresse IP de l’hôte',
                hintText: '192.168.1.20',
                labelStyle: TextStyle(color: _poolAccent),
                hintStyle: TextStyle(color: Colors.white38),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: _poolHudLine),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Annuler',
              style: TextStyle(color: _poolHudText, fontFamily: _poolTextFont),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'host'),
            style: FilledButton.styleFrom(backgroundColor: _poolAccent),
            child: const Text(
              'Créer une partie',
              style: TextStyle(fontFamily: _poolTextFont),
            ),
          ),
          FilledButton(
            onPressed: () {
              final address = addressController.text.trim();
              if (address.isNotEmpty) Navigator.pop(dialogContext, address);
            },
            style: FilledButton.styleFrom(backgroundColor: _poolAccent),
            child: const Text(
              'Rejoindre',
              style: TextStyle(fontFamily: _poolTextFont),
            ),
          ),
        ],
      ),
    );
    addressController.dispose();
    if (choice == null || !context.mounted) return;
    await _openGame(
      context,
      PoolMode.online,
      isHost: choice == 'host',
      address: choice == 'host' ? null : choice,
    );
  }

  Future<void> _openGame(
    BuildContext context,
    PoolMode mode, {
    int level = 1,
    bool isHost = false,
    String? address,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PoolGameScreen(
          mode: mode,
          level: level,
          isHost: isHost,
          address: address,
        ),
      ),
    );
  }
}

class _PoolModeCard extends StatelessWidget {
  const _PoolModeCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .27)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  emoji,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 55),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: _poolBoldFont,
                    fontSize: 19,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: constraints.maxHeight < 150 ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: _poolTextFont,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PoolGameScreen extends StatefulWidget {
  const PoolGameScreen({
    super.key,
    required this.mode,
    this.level = 1,
    this.isHost = false,
    this.address,
  });

  final PoolMode mode;
  final int level;
  final bool isHost;
  final String? address;

  @override
  State<PoolGameScreen> createState() => _PoolGameScreenState();
}

class _PoolGameScreenState extends State<PoolGameScreen>
    with SingleTickerProviderStateMixin {
  late final PoolGame _game;
  late final Ticker _ticker;
  PoolNetwork? _network;
  String _connectionMessage = '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (widget.mode == PoolMode.online) {
      _network = PoolNetwork(onLine: _onLine, onStatus: _onNetworkStatus);
    }
    _game = PoolGame(
      mode: widget.mode,
      level: widget.level,
      myPlayerIndex: widget.isHost ? 0 : 1,
      onSend: _network?.send,
    );
    if (widget.mode == PoolMode.online) {
      _game.ready = false;
      _connect();
    }
    _ticker = createTicker((_) {
      _game.tick();
      if (mounted) setState(() {});
    })..start();
  }

  Future<void> _connect() async {
    try {
      if (widget.isHost) {
        final address = await _network!.host();
        if (mounted) {
          setState(() {
            _connectionMessage = 'Adresse : $address';
            if (!_game.ready) {
              _game.message = 'En attente de l’adversaire… $address';
            }
          });
        }
      } else {
        await _network!.join(widget.address!);
        if (mounted) {
          setState(() {
            _connectionMessage = 'En attente de l’hôte…';
            if (!_game.ready) _game.message = _connectionMessage;
          });
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connectionMessage = 'Connexion impossible : $error';
        _game.message = _connectionMessage;
      });
    }
  }

  void _onNetworkStatus(String status) {
    if (!mounted) return;
    setState(() {
      switch (status) {
        case 'connected':
          _connectionMessage = 'Adversaire connecté';
          _game.message = _connectionMessage;
          if (widget.isHost) _startOnlineGame();
        case 'lost':
          _connectionMessage = 'Connexion perdue';
          _game.ready = false;
          _game.message = _connectionMessage;
        case 'error':
          _connectionMessage = 'Erreur de connexion';
          _game.message = _connectionMessage;
      }
    });
  }

  void _startOnlineGame() {
    final seed = DateTime.now().microsecondsSinceEpoch;
    _game
      ..start(seed: seed)
      ..ready = true;
    _network?.send('START $seed');
  }

  void _onLine(String line) {
    if (!mounted) return;
    final fields = line.split(' ');
    setState(() {
      if (fields.first == 'START' && fields.length == 2) {
        final seed = int.tryParse(fields[1]);
        if (seed != null) {
          _game
            ..start(seed: seed)
            ..ready = true;
          _connectionMessage = 'Partie lancée';
        }
      } else if (fields.first == 'SHOT' && fields.length == 3) {
        final angle = double.tryParse(fields[1]);
        final power = double.tryParse(fields[2]);
        if (angle != null && power != null) _game.remoteShot(angle, power);
      } else if (fields.first == 'PLACE' && fields.length == 3) {
        final x = double.tryParse(fields[1]);
        final y = double.tryParse(fields[2]);
        if (x != null && y != null) _game.remotePlace(x, y);
      } else if (fields.first == 'STATE' && !_game.applySnapshot(line)) {
        _connectionMessage = 'État de partie reçu invalide';
        _game.message = _connectionMessage;
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_network?.close() ?? Future<void>.value());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _restart() {
    if (widget.mode == PoolMode.online && !widget.isHost) {
      setState(() => _game.message = 'Seul l’hôte peut relancer la partie.');
      return;
    }
    if (widget.mode == PoolMode.online) {
      _startOnlineGame();
    } else {
      setState(() => _game.start());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _poolInk,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHud(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scale = math.min(
                      (constraints.maxWidth - 36).clamp(0, double.infinity) /
                          PoolGame.tableWidth,
                      (constraints.maxHeight - 36).clamp(0, double.infinity) /
                          PoolGame.tableHeight,
                    ).toDouble();
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
                            final point = _toBoard(event.localPosition, scale);
                            _game.pointerDown(point.dx, point.dy);
                            setState(() {});
                          },
                          onPointerMove: (event) {
                            final point = _toBoard(event.localPosition, scale);
                            _game.pointerMove(point.dx, point.dy);
                            setState(() {});
                          },
                          onPointerUp: (_) {
                            _game.pointerUp();
                            setState(() {});
                          },
                          child: CustomPaint(
                            painter: _PoolTablePainter(_game),
                            size: boardSize,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (_game.isGameOver) Positioned.fill(child: _buildGameOver()),
        ],
      ),
    );
  }

  Offset _toBoard(Offset point, double scale) =>
      Offset(point.dx / scale, point.dy / scale);

  Widget _buildHud() {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        color: _poolInk,
        border: Border(bottom: BorderSide(color: _poolHudLine)),
      ),
      child: Row(
        children: [
          _HudButton(
            icon: Icons.home,
            label: 'Accueil',
            onPressed: () => Navigator.pop(context),
          ),
          _PlayerBadge(
            title: _game.playerName(0),
            subtitle: _game.groupLabel(0),
            active: _game.currentPlayer == 0 && !_game.isGameOver,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _game.message.isEmpty ? _connectionMessage : _game.message,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _poolHudText,
                fontSize: 14,
                fontFamily: _poolBoldFont,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _PlayerBadge(
            title: _game.playerName(1),
            subtitle: _game.groupLabel(1),
            active: _game.currentPlayer == 1 && !_game.isGameOver,
          ),
          _HudButton(
            icon: Icons.refresh,
            label: 'Nouvelle partie',
            onPressed: _restart,
          ),
          const SizedBox(width: 8),
          const _PoolAccountHeader(compact: true),
        ],
      ),
    );
  }

  Widget _buildGameOver() {
    final playerIndex = widget.mode == PoolMode.online && !widget.isHost ? 1 : 0;
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: _poolTitleFont,
                      fontSize: 54,
                      shadows: [
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
                      onPressed: () => Navigator.pop(context),
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

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: _poolAccent,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontSize: 12,
          fontFamily: _poolBoldFont,
        ),
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
  });

  final String title;
  final String subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 92, maxWidth: 155),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _poolHudCard,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: active ? _poolAccent : _poolHudLine,
          width: active ? 3 : 2,
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
              fontSize: 11,
              fontFamily: _poolTextFont,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _poolHudText.withValues(alpha: .75),
              fontSize: 9,
              fontFamily: _poolTextFont,
            ),
          ),
        ],
      ),
    );
  }
}

class _PoolTablePainter extends CustomPainter {
  _PoolTablePainter(this.game);

  final PoolGame game;
  static const _felt = Color(0xFF0D7D25);
  static const _railLight = Color(0xFF9A5424);
  static const _railDark = Color(0xFF4A2410);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / PoolGame.tableWidth,
        size.height / PoolGame.tableHeight);
    canvas.save();
    canvas.scale(scale);
    _drawTable(canvas);
    for (final ball in game.balls.where((ball) => ball.id != 0)) {
      _drawBall(canvas, ball);
    }
    _drawBall(canvas, game.cueBall,
        alpha: game.state == PoolGameState.placingCue &&
                !game.cuePlacementValid
            ? 105
            : 255);
    if (game.state == PoolGameState.aiming) {
      _drawAim(canvas);
      _drawPower(canvas);
    }
    canvas.restore();
  }

  void _drawTable(Canvas canvas) {
    const width = PoolGame.tableWidth;
    const height = PoolGame.tableHeight;
    const edge = PoolGame.rail;
    final frame = Paint()
      ..shader = const LinearGradient(
        colors: [_railLight, _railDark, _railLight],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(const Rect.fromLTWH(0, 0, width, height));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, width, height),
        const Radius.circular(22),
      ),
      frame,
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
      const Rect.fromLTRB(edge - 10, edge - 10, width - edge + 10, height - edge + 10),
      Paint()..color = const Color(0xFF0B6A1F),
    );
    canvas.drawRect(
      const Rect.fromLTRB(edge, edge, width - edge, height - edge),
      Paint()
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
        ),
    );
    final diamond = Paint()..color = const Color(0xFFECDCAA);
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
          Paint()..color = const Color(0xFFC9A24A),
        )
        ..drawCircle(
          Offset(pocket[0], pocket[1]),
          PoolGame.pocketRadius,
          Paint()..color = const Color(0xFF080808),
        );
    }
  }

  void _drawBall(Canvas canvas, PoolBall ball, {int alpha = 255}) {
    if (ball.pocketed) return;
    final radius = PoolGame.ballRadius;
    final center = Offset(ball.x, ball.y);
    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(3, 4),
        width: radius * 2,
        height: radius * 1.6,
      ),
      Paint()..color = Colors.black.withAlpha(76 * alpha ~/ 255),
    );
    final color = switch (ball.id) {
      0 => const Color(0xFFF7F7EF),
      8 => const Color(0xFF111111),
      _ when game.groupOf(ball.id) == 1 => const Color(0xFFD9302A),
      _ => const Color(0xFFF2A61C),
    };
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withAlpha(alpha),
    );
    canvas.save();
    final clip = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.clipPath(clip);
    final rotation = ball.orientation;
    if (ball.id == 0) {
      final dotPaint = Paint()..color = const Color(0xFFCC2222).withAlpha(alpha);
      for (var axis = 0; axis < 3; axis++) {
        for (final side in const [1, -1]) {
          final depth = side * rotation[6 + axis];
          if (depth <= .05) continue;
          canvas.drawCircle(
            center +
                Offset(
                  side * rotation[axis] * radius,
                  side * rotation[3 + axis] * radius,
                ),
            radius * (.1 + .12 * depth),
            dotPaint,
          );
        }
      }
    } else {
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
          Paint()..color = Colors.white.withAlpha(alpha),
        );
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${ball.id}',
            style: TextStyle(
              color: const Color(0xFF111111).withAlpha(alpha),
              fontSize: radius * .7,
              fontFamily: _poolBoldFont,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
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
        final distance = projection -
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
    _drawDashedLine(canvas, Offset(game.cueBall.x, game.cueBall.y), end, guidePaint);
    canvas.drawCircle(end, PoolGame.ballRadius, guidePaint);
    if (target != null && edgeDistance >= closest) {
      final normal = Offset(target.x - end.dx, target.y - end.dy);
      final length = normal.distance;
      if (length > 0) {
        canvas.drawLine(
          Offset(target.x, target.y),
          Offset(target.x + normal.dx / length * 45, target.y + normal.dy / length * 45),
          guidePaint,
        );
      }
    }
    final stickStart = Offset(game.cueBall.x, game.cueBall.y);
    final stickEnd = stickStart -
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
      stickStart - Offset(dx, dy) * (PoolGame.ballRadius + 12 + game.power * 90),
      Paint()
        ..color = const Color(0xFF4AA3DF)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  double _distanceToRail(double dx, double dy) {
    final left = PoolGame.rail + PoolGame.ballRadius;
    final right =
        PoolGame.tableWidth - PoolGame.rail - PoolGame.ballRadius;
    final top = PoolGame.rail + PoolGame.ballRadius;
    final bottom =
        PoolGame.tableHeight - PoolGame.rail - PoolGame.ballRadius;
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
      canvas.drawLine(start + direction * offset, start + direction * stop, paint);
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
        Rect.fromLTRB(
          left,
          5,
          left + (right - left) * game.power,
          11,
        ),
        Paint()..color = const Color(0xFF1F9A3A),
      );
  }

  @override
  bool shouldRepaint(covariant _PoolTablePainter oldDelegate) => true;
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
        final username = auth.userProfile?['username']?.toString() ??
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
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
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
