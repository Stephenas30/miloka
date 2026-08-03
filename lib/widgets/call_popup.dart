import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../game/call_system.dart';

class CallPopup extends StatefulWidget {
  final String playerName;
  final Function(CallOption) onCall;
  final List<CallOption> availableCalls;
  final int? timeoutSeconds;

  const CallPopup({
    super.key,
    required this.playerName,
    required this.onCall,
    required this.availableCalls,
    this.timeoutSeconds,
  });

  @override
  State<CallPopup> createState() => _CallPopupState();
}

class _CallPopupState extends State<CallPopup> {
  int? _remaining;
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.timeoutSeconds != null && widget.timeoutSeconds! > 0) {
      _remaining = widget.timeoutSeconds;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _remaining = _remaining! - 1;
        });
        if (_remaining! <= 0) {
          _timer?.cancel();
          if (!_done) {
            _done = true;
            widget.onCall(CallOption.pass);
            Navigator.of(context).pop();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _select(CallOption option) {
    if (_done) return;
    _done = true;
    _timer?.cancel();
    widget.onCall(option);
    Navigator.of(context).pop();
  }

  String _callOptionLabel(CallOption option) {
    switch (option) {
      case CallOption.treble: return "Trèfle";
      case CallOption.diamond: return "Carreau";
      case CallOption.heart: return "Cœur";
      case CallOption.spade: return "Pique";
      case CallOption.sansAs: return "Sans As";
      case CallOption.toutAs: return "Tout As";
      case CallOption.x2: return "x2";
      case CallOption.x4: return "x4";
      case CallOption.pass: return "Passer";
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isSmall = size.width < 380 || size.height < 600;

    final dialogWidth = isSmall ? size.width * 0.95 : size.width * 0.8;
    final dialogHeight = isSmall ? size.height * 0.6 : size.height * 0.55;

    final radius = (dialogWidth * 0.35).clamp(70.0, 130.0);
    final btnSize = isSmall ? 42.0 : 56.0;
    final passBtnSize = isSmall ? 52.0 : 70.0;
    final fontSize = isSmall ? 9.0 : 12.0;
    final passFontSize = isSmall ? 11.0 : 14.0;

    final options = [
      CallOption.treble,
      CallOption.diamond,
      CallOption.heart,
      CallOption.spade,
      CallOption.sansAs,
      CallOption.toutAs,
      CallOption.x2,
      CallOption.x4,
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cx = constraints.maxWidth / 2;
            final cy = constraints.maxHeight / 2;

            return Stack(
              children: [
                for (int i = 0; i < options.length; i++)
                  Positioned(
                    left: cx + radius * math.cos((2 * math.pi / options.length) * i - math.pi / 2) - btnSize / 2,
                    top: cy + radius * math.sin((2 * math.pi / options.length) * i - math.pi / 2) - btnSize / 2,
                    child: SizedBox(
                      width: btnSize,
                      height: btnSize,
                      child: ElevatedButton(
                        onPressed: widget.availableCalls.contains(options[i])
                            ? () => _select(options[i])
                            : null,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          backgroundColor: widget.availableCalls.contains(options[i]) ? null : Colors.grey[400],
                          foregroundColor: widget.availableCalls.contains(options[i]) ? null : Colors.grey[600],
                        ),
                        child: Text(
                          _callOptionLabel(options[i]),
                          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),

                Positioned(
                  left: cx - passBtnSize / 2,
                  top: cy - passBtnSize / 2,
                  child: SizedBox(
                    width: passBtnSize,
                    height: passBtnSize,
                    child: ElevatedButton(
                      onPressed: widget.availableCalls.contains(CallOption.pass)
                          ? () => _select(CallOption.pass)
                          : null,
                      style: ElevatedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                        backgroundColor: widget.availableCalls.contains(CallOption.pass) ? null : Colors.grey[400],
                        foregroundColor: widget.availableCalls.contains(CallOption.pass) ? null : Colors.grey[600],
                      ),
                      child: Text(
                        "Passer",
                        style: TextStyle(fontSize: passFontSize, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),

                if (_remaining != null)
                  Positioned(
                    top: 8,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _remaining! <= 3 ? Colors.red : Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_remaining s',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
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
}
