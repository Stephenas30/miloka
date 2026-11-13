import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/card_model.dart';

class PlayedCard {
  final String player;
  final CardModel card;
  final Offset? position;
  final double rotation;

  PlayedCard(this.player, this.card, {Offset? position})
      : position = position,
        rotation = position == null
            ? 0
            : (math.sin(position.dx * 71.3 +
                        position.dy * 129.7) *
                14.0);
}
