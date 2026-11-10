import 'dart:math' as math;

import 'package:flutter/material.dart';

const _resultTitleFont = 'BillardTitre';
const _resultTextFont = 'BillardLora';
const _resultAccent = Color(0xFF1F9A3A);

class GameResultAction {
  const GameResultAction({
    required this.label,
    required this.onPressed,
    this.color = _resultAccent,
  });

  final String label;
  final VoidCallback onPressed;
  final Color color;
}

class GameResultAnimation extends StatefulWidget {
  const GameResultAnimation({
    super.key,
    required this.won,
    required this.title,
    required this.subtitle,
    this.icon,
    this.details = const [],
    required this.actions,
  });

  final bool? won;
  final String title;
  final String subtitle;
  final String? icon;
  final List<Widget> details;
  final List<GameResultAction> actions;

  @override
  State<GameResultAnimation> createState() => _GameResultAnimationState();
}

class _GameResultAnimationState extends State<GameResultAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _timeline;
  late final AnimationController _halo;
  late final AnimationController _confetti;
  final _particles = List<_ResultParticle>.generate(
    140,
    (_) => _ResultParticle(),
  );

  @override
  void initState() {
    super.initState();
    _timeline = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    _halo = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _confetti = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    if (widget.won == true) _confetti.repeat();
  }

  @override
  void didUpdateWidget(covariant GameResultAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.won == true && oldWidget.won != true) {
      _confetti.repeat();
    } else if (widget.won != true && oldWidget.won == true) {
      _confetti.stop();
    }
  }

  @override
  void dispose() {
    _timeline.dispose();
    _halo.dispose();
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final won = widget.won == true;
    final accent = won
        ? const Color(0xFFFFC107)
        : widget.won == false
        ? const Color(0xFFE53935)
        : const Color(0xFFFFC107);

    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([_timeline, _halo]),
            builder: (context, _) {
              final fade = (_timeline.value / .4).clamp(0, 1).toDouble();
              return ColoredBox(
                color: Colors.black.withValues(alpha: fade * .67),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -.12),
                      radius: .9 + _halo.value * .08,
                      colors: [
                        accent.withValues(alpha: .28),
                        accent.withValues(alpha: .03),
                        Colors.transparent,
                      ],
                      stops: const [0, .45, 1],
                    ),
                  ),
                ),
              );
            },
          ),
          if (won)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _confetti,
                builder: (context, _) => CustomPaint(
                  painter: _ResultConfettiPainter(
                    _particles,
                    (_confetti.lastElapsedDuration?.inMicroseconds ?? 0) /
                        Duration.microsecondsPerSecond,
                  ),
                ),
              ),
            ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final titleSize = constraints.maxWidth > constraints.maxHeight
                    ? 54.0
                    : 46.0;
                final centerY = constraints.maxHeight / 2;
                return AnimatedBuilder(
                  animation: _timeline,
                  builder: (context, _) {
                    final progress = _timeline.value;
                    final bounce = Curves.easeOutBack.transform(
                      (progress / .47).clamp(0, 1).toDouble(),
                    );
                    final shake = widget.won == false && progress < .5
                        ? math.sin(progress * 1.4 * 60) *
                              (30 - progress * 60).clamp(0, 30) *
                              .6
                        : 0.0;
                    final subtitleOpacity = ((progress - .42) / .2)
                        .clamp(0, 1)
                        .toDouble();
                    final actionsOpacity = ((progress - .67) / .2)
                        .clamp(0, 1)
                        .toDouble();
                    return Stack(
                      children: [
                        Positioned(
                          top: centerY - 150,
                          left: 12,
                          right: 12,
                          child: Text(
                            widget.icon ?? (won ? '🏆' : '😔'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 56),
                          ),
                        ),
                        Positioned(
                          top: centerY - 87,
                          left: 12,
                          right: 12,
                          child: Transform.translate(
                            offset: Offset(shake, 0),
                            child: Transform.scale(
                              scale: bounce,
                              child: ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: won
                                      ? const [
                                          Color(0xFFFFF176),
                                          Color(0xFFFF9800),
                                        ]
                                      : const [
                                          Color(0xFFFF8A80),
                                          Color(0xFFC62828),
                                        ],
                                ).createShader(bounds),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    widget.title,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontFamily: _resultTitleFont,
                                      fontSize: titleSize,
                                      shadows: const [
                                        Shadow(
                                          color: Color(0xFF3A1F00),
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: centerY + 1,
                          left: 16,
                          right: 16,
                          child: Opacity(
                            opacity: subtitleOpacity,
                            child: Text(
                              widget.subtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: _resultTextFont,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        if (widget.details.isNotEmpty)
                          Positioned(
                            top: centerY + 42,
                            left: 16,
                            right: 16,
                            bottom: 96,
                            child: Opacity(
                              opacity: subtitleOpacity,
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: widget.details,
                                ),
                              ),
                            ),
                          ),
                        if (widget.actions.isNotEmpty)
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 28,
                            child: Opacity(
                              opacity: actionsOpacity,
                              child: IgnorePointer(
                                ignoring: actionsOpacity < 1,
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 16,
                                  runSpacing: 12,
                                  children: [
                                    for (final action in widget.actions)
                                      _ResultButton(action: action),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultButton extends StatelessWidget {
  const _ResultButton({required this.action});

  final GameResultAction action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 54,
      child: FilledButton(
        onPressed: action.onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: action.color,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontFamily: _resultTextFont,
          ),
        ),
        child: Text(action.label, textAlign: TextAlign.center),
      ),
    );
  }
}

class _ResultParticle {
  _ResultParticle()
    : x = _random.nextDouble(),
      startY = _random.nextDouble(),
      velocityX = (_random.nextDouble() - .5) * 1.2,
      velocityY = 2 + _random.nextDouble() * 3,
      size = 5 + _random.nextDouble() * 7,
      phase = _random.nextDouble() * math.pi * 2,
      color = _colors[_random.nextInt(_colors.length)];

  static final _random = math.Random();
  static const _colors = [
    Color(0xFFFFD54A),
    Color(0xFFE53935),
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
    Colors.white,
    Color(0xFFAB47BC),
  ];

  final double x;
  final double startY;
  final double velocityX;
  final double velocityY;
  final double size;
  final double phase;
  final Color color;
}

class _ResultConfettiPainter extends CustomPainter {
  _ResultConfettiPainter(this.particles, this.elapsedSeconds);

  final List<_ResultParticle> particles;
  final double elapsedSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()..style = PaintingStyle.fill;
    final elapsedFrames = elapsedSeconds * 60;

    for (final particle in particles) {
      final fallDistance = particle.velocityY * elapsedFrames;
      final y = (particle.startY * size.height +
              fallDistance +
              size.height +
              10) %
          (size.height + 10) -
          10;
      final x = (particle.x * size.width +
              particle.velocityX * elapsedFrames +
              math.sin(elapsedFrames * .05 + particle.phase) * .8) %
          size.width;

      paint.color = particle.color;
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(
          (elapsedFrames * 4 + particle.phase * 57) * math.pi / 180,
        );
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: particle.size,
          height: particle.size / 2,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ResultConfettiPainter oldDelegate) =>
      oldDelegate.elapsedSeconds != elapsedSeconds;
}
