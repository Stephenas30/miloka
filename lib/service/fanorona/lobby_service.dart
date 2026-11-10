import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_service.dart';
import '../../utils/retry_util.dart';

/// Gestion des équipes Fanorona (2 joueurs max).
class FanoronaTeamLobbyService {
  static final FanoronaTeamLobbyService _instance =
      FanoronaTeamLobbyService._internal();
  factory FanoronaTeamLobbyService() => _instance;
  FanoronaTeamLobbyService._internal();

  final SupabaseService _supabaseService = SupabaseService();
  SupabaseClient get _client => _supabaseService.client;
  final Map<String, Map<String, dynamic>> _teams = {};

  String _generateTeamId() {
    const min = 100000;
    const max = 999999;
    var id = (min + Random().nextInt(max - min)).toString();
    while (_teams.containsKey(id)) {
      id = (min + Random().nextInt(max - min)).toString();
    }
    return id;
  }

  Future<bool> teamExists(String teamId) async {
    final response = await _client
        .from('fanorona_teams')
        .select('team_id')
        .eq('team_id', teamId)
        .maybeSingle();
    return response != null;
  }

  Future<String?> createTeam(
    String hostId,
    Map<String, dynamic> hostProfile,
  ) async {
    final teamId = _generateTeamId();
    final member = {'id': hostId, 'profile': hostProfile};
    final payload = {
      'team_id': teamId,
      'host_id': hostId,
      'host_profile': hostProfile,
      'members': [member],
      'status': 'waiting',
      'channel_id': teamId,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await NetworkRetry.retry(
        () => _client.from('fanorona_teams').insert(payload),
      );
    } catch (e) {
      return null;
    }
    _teams[teamId] = payload;
    return teamId;
  }

  Future<Map<String, dynamic>?> getTeam(String teamId) async {
    try {
      final response = await _client
          .from('fanorona_teams')
          .select(
            'team_id, host_id, host_profile, members, status, channel_id, merged_source_id',
          )
          .eq('team_id', teamId)
          .maybeSingle();
      if (response == null) return _teams[teamId];
      return Map<String, dynamic>.from(response);
    } catch (_) {
      return _teams[teamId];
    }
  }

  List<Map<String, dynamic>> getMembersList(Map<String, dynamic> team) {
    final members = team['members'];
    if (members is List) {
      return members.map((m) => Map<String, dynamic>.from(m)).toList();
    }
    return [];
  }

  int getMemberCount(Map<String, dynamic> team) {
    return getMembersList(team).length;
  }

  bool isMemberInTeam(Map<String, dynamic> team, String userId) {
    return getMembersList(team).any((m) => m['id']?.toString() == userId);
  }

  /// Rejoint une équipe existante par code (max 2 membres).
  Future<Map<String, dynamic>?> joinTeam(String teamId) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return null;
    final team = await getTeam(teamId);
    if (team == null) return null;
    final status = team['status']?.toString();
    if (status != 'waiting' && status != 'public_waiting') return null;
    final profile = await _client
        .from('users')
        .select()
        .eq('id', currentUser.id)
        .single();
    final joined = await addMember(teamId, currentUser.id, profile);
    if (!joined) return null;
    return getTeam(teamId);
  }

  Future<bool> addMember(
    String teamId,
    String userId,
    Map<String, dynamic> userProfile,
  ) async {
    final team = await getTeam(teamId);
    if (team == null) return false;

    final members = getMembersList(team);
    if (members.length >= 2) return false;
    if (members.any((m) => m['id']?.toString() == userId)) return false;

    members.add({'id': userId, 'profile': userProfile});

    try {
      await NetworkRetry.retry(
        () => _client
            .from('fanorona_teams')
            .update({
              'members': members,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('team_id', teamId),
      );
    } catch (e) {
      return false;
    }

    _teams[teamId] = {...team, 'members': members};
    return true;
  }

  /// Enregistre la mise d'un membre dans son profil (JSONB members),
  /// sans migration de schéma. Toute modification de mise réinitialise
  /// les accords des deux joueurs.
  Future<bool> setMemberBet(String teamId, String userId, int bet) async {
    final team = await getTeam(teamId);
    if (team == null) return false;

    final members = getMembersList(team);
    var changed = false;
    for (final m in members) {
      final profile = Map<String, dynamic>.from(m['profile'] as Map? ?? {});
      if (m['id']?.toString() == userId) {
        if ((profile['bet'] as int? ?? 0) == bet) return true;
        profile['bet'] = bet;
        changed = true;
      }
      // Les conditions changent : les accords précédents sont annulés.
      if (profile.remove('bet_agreed') != null) changed = true;
      m['profile'] = profile;
    }
    if (!changed) return false;

    try {
      await NetworkRetry.retry(
        () => _client
            .from('fanorona_teams')
            .update({
              'members': members,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('team_id', teamId),
      );
    } catch (e) {
      return false;
    }

    _teams[teamId] = {...team, 'members': members};
    return true;
  }

  /// Acceptation (ou retrait) de la mise par un membre.
  Future<bool> setMemberBetAgreement(
    String teamId,
    String userId,
    bool agreed,
  ) async {
    final team = await getTeam(teamId);
    if (team == null) return false;

    final members = getMembersList(team);
    var changed = false;
    for (final m in members) {
      if (m['id']?.toString() != userId) continue;
      final profile = Map<String, dynamic>.from(m['profile'] as Map? ?? {});
      if ((profile['bet_agreed'] as bool? ?? false) == agreed) return true;
      profile['bet_agreed'] = agreed;
      m['profile'] = profile;
      changed = true;
    }
    if (!changed) return false;

    try {
      await NetworkRetry.retry(
        () => _client
            .from('fanorona_teams')
            .update({
              'members': members,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('team_id', teamId),
      );
    } catch (e) {
      return false;
    }

    _teams[teamId] = {...team, 'members': members};
    return true;
  }

  Future<bool> removeMember(String teamId, String userId) async {
    final team = await getTeam(teamId);
    if (team == null) return false;
    if (team['host_id']?.toString() == userId) return false;

    final members = getMembersList(team);
    members.removeWhere((m) => m['id']?.toString() == userId);

    try {
      await NetworkRetry.retry(
        () => _client
            .from('fanorona_teams')
            .update({
              'members': members,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('team_id', teamId),
      );
    } catch (e) {
      return false;
    }

    _teams[teamId] = {...team, 'members': members};
    return true;
  }

  Future<void> startGame(String teamId) async {
    try {
      await NetworkRetry.retry(
        () => _client
            .from('fanorona_teams')
            .update({
              'status': 'playing',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('team_id', teamId),
      );
    } catch (_) {}
  }

  Future<void> updateStatus(String teamId, String status) async {
    try {
      await _client
          .from('fanorona_teams')
          .update({
            'status': status,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('team_id', teamId);
    } catch (_) {}
    final team = _teams[teamId];
    if (team != null) team['status'] = status;
  }

  Future<void> setPublicWaiting(String teamId) async {
    try {
      await _client
          .from('fanorona_teams')
          .update({
            'status': 'public_waiting',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('team_id', teamId);
    } catch (_) {}
    final team = _teams[teamId];
    if (team != null) team['status'] = 'public_waiting';
  }

  Future<void> cancelPublicWaiting(String teamId) async {
    try {
      await _client
          .from('fanorona_teams')
          .update({
            'status': 'waiting',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('team_id', teamId);
    } catch (_) {}
    final team = _teams[teamId];
    if (team != null) team['status'] = 'waiting';
  }

  Future<Map<String, dynamic>?> findPublicMatch(String myTeamId) async {
    try {
      final response = await _client
          .from('fanorona_teams')
          .select()
          .eq('status', 'public_waiting')
          .neq('team_id', myTeamId)
          .limit(10);
      for (final row in response) {
        final team = Map<String, dynamic>.from(row);
        final members = team['members'];
        final otherSize = (members is List) ? members.length : 0;
        if (otherSize <= 1) return team;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> claimForMatch(String teamId) async {
    try {
      await _client
          .from('fanorona_teams')
          .update({
            'status': 'public_matched',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('team_id', teamId)
          .eq('status', 'public_waiting');
      final team = _teams[teamId];
      if (team != null) team['status'] = 'public_matched';
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Fusionne la team source dans la team cible (matchmaking public).
  /// La team source pointe vers le canal de la team cible pour rejoindre
  /// la même partie en ligne. Le statut reste public_matched : les deux
  /// joueurs doivent d'abord passer par la mise avant de lancer.
  Future<bool> mergeTeams(String targetTeamId, String sourceTeamId) async {
    final target = await getTeam(targetTeamId);
    final source = await getTeam(sourceTeamId);
    if (target == null || source == null) return false;

    final targetMembers = getMembersList(target);
    final sourceMembers = getMembersList(source);
    if (targetMembers.length + sourceMembers.length > 2) return false;

    for (final m in sourceMembers) {
      targetMembers.add(m);
    }

    try {
      await NetworkRetry.retry(
        () => _client
            .from('fanorona_teams')
            .update({
              'members': targetMembers,
              'status': 'public_matched',
              'merged_source_id': sourceTeamId,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('team_id', targetTeamId),
      );

      await NetworkRetry.retry(
        () => _client
            .from('fanorona_teams')
            .update({
              'status': 'public_matched',
              'channel_id': targetTeamId,
              'host_id': target['host_id'],
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('team_id', sourceTeamId),
      );
    } catch (e) {
      return false;
    }

    _teams[targetTeamId] = {
      ...target,
      'members': targetMembers,
      'status': 'public_matched',
      'merged_source_id': sourceTeamId,
    };
    _teams[sourceTeamId] = {
      ...source,
      'status': 'public_matched',
      'channel_id': targetTeamId,
      'host_id': target['host_id'],
    };
    return true;
  }

  Future<void> deleteTeam(String teamId) async {
    try {
      await NetworkRetry.retry(
        () => _client.from('fanorona_teams').delete().eq('team_id', teamId),
      );
    } catch (_) {}
    _teams.remove(teamId);
  }
}
