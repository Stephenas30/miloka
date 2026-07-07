import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import '../providers/auth_provider.dart';
import 'supabase_service.dart';

class StatsService {
  static final StatsService _instance = StatsService._internal();
  factory StatsService() => _instance;
  StatsService._internal();

  int _calculateLevel(int xp) {
    if (xp < 250) return 1;
    if (xp < 500) return 2;
    if (xp < 750) return 3;
    if (xp < 1000) return 4;
    return 5;
  }

  int _calculateXpProgress(int xp) {
    if (xp < 250) return xp;
    if (xp < 500) return xp - 250;
    if (xp < 750) return xp - 500;
    if (xp < 1000) return xp - 750;
    return 1000;
  }

  Future<void> recordGameResult({
    required String gameName,
    required bool won,
    required BuildContext? context,
  }) async {
    final authProvider = context != null ? context.read<AuthProvider?>() : null;
    final currentUserId = authProvider?.currentUser?.id;

    if (currentUserId == null) return;

    final supabase = SupabaseService();
    final profile = await supabase.getUserProfile(currentUserId);

    if (profile == null) return;

    final gameKey = gameName.toLowerCase();
    final playedKey = '${gameKey}_played';
    final winsKey = '${gameKey}_wins';
    final lossesKey = '${gameKey}_losses';

    final played = int.tryParse((profile[playedKey] ?? '0').toString()) ?? 0;
    final wins = int.tryParse((profile[winsKey] ?? '0').toString()) ?? 0;
    final losses = int.tryParse((profile[lossesKey] ?? '0').toString()) ?? 0;

    final updatedData = {
      playedKey: played + 1,
      winsKey: won ? wins + 1 : wins,
      lossesKey: won ? losses : losses + 1,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await supabase.client.from('users').update(updatedData).eq('id', currentUserId);

    final updatedProfile = await supabase.getUserProfile(currentUserId);
    final totalGames = (int.tryParse((updatedProfile?['belote_played'] ?? '0').toString()) ?? 0) +
        (int.tryParse((updatedProfile?['ludo_played'] ?? '0').toString()) ?? 0);
    final totalWins = (int.tryParse((updatedProfile?['belote_wins'] ?? '0').toString()) ?? 0) +
        (int.tryParse((updatedProfile?['ludo_wins'] ?? '0').toString()) ?? 0);

    final currentXp = int.tryParse((updatedProfile?['${gameKey}_xp'] ?? '0').toString()) ?? 0;
    final xpDelta = won ? 50 : -10;
    final newXp = (currentXp + xpDelta).clamp(0, 1000);
    final level = _calculateLevel(newXp);
    final xpProgress = _calculateXpProgress(newXp);

    final badgeList = <String>[];
    if (totalWins >= 1) badgeList.add('FirstWin');
    if (totalGames >= 5) badgeList.add('Starter');
    if (level >= 2) badgeList.add('RisingStar');
    if (level >= 5) badgeList.add('Legend');

    await supabase.client.from('users').update({
      '${gameKey}_level': level,
      '${gameKey}_xp': newXp,
      '${gameKey}_xp_progress': xpProgress,
      'badges': badgeList.join(','),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', currentUserId);
  }
}
