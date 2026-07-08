import 'package:flutter/material.dart';

class StatsService {
  static final StatsService _instance = StatsService._internal();
  factory StatsService() => _instance;
  StatsService._internal();

  Future<void> recordGameResult({
    required String gameName,
    required bool won,
    required BuildContext? context,
  }) async {
    // Les statistiques de jeu ont été retirées de la table `users`.
    // Ajoute ici la logique vers une table dédiée si besoin.
  }
}
