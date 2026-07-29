import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/retry_util.dart';
import 'supabase_service.dart';

class LudoTeamLobbyService {
  static final LudoTeamLobbyService _instance = LudoTeamLobbyService._internal();
  factory LudoTeamLobbyService() => _instance;
  LudoTeamLobbyService._internal();

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
        .from('ludo_teams')
        .select('team_id')
        .eq('team_id', teamId)
        .maybeSingle();
    return response != null;
  }

  Future<String?> createTeam(String hostId, Map<String, dynamic> hostProfile) async {
    final teamId = _generateTeamId();
    final member = {
      'id': hostId,
      'profile': hostProfile,
      'color': 'red',
    };

    final payload = {
      'team_id': teamId,
      'host_id': hostId,
      'host_profile': hostProfile,
      'members': [member],
      'status': 'waiting',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await NetworkRetry.retry(() => _client.from('ludo_teams').insert(payload));
    } catch (e) {
      return null;
    }

    _teams[teamId] = payload;
    return teamId;
  }

  Future<Map<String, dynamic>?> getTeam(String teamId) async {
    try {
      final response = await _client
          .from('ludo_teams')
          .select('team_id, host_id, host_profile, members, status')
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

  Future<bool> addMember(String teamId, String userId, Map<String, dynamic> userProfile) async {
    final team = await getTeam(teamId);
    if (team == null) return false;

    final members = getMembersList(team);
    if (members.length >= 4) return false;
    if (members.any((m) => m['id']?.toString() == userId)) return false;

    final availableColors = ['red', 'green', 'yellow', 'blue'];
    for (final m in members) {
      availableColors.remove(m['color']?.toString());
    }
    final color = availableColors.isNotEmpty ? availableColors.first : 'yellow';

    final newMember = {
      'id': userId,
      'profile': userProfile,
      'color': color,
    };
    members.add(newMember);

    try {
      await NetworkRetry.retry(() => _client.from('ludo_teams').update({
        'members': members,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId));
    } catch (e) {
      return false;
    }

    _teams[teamId] = {...team, 'members': members};
    return true;
  }

  Future<bool> removeMember(String teamId, String userId) async {
    final team = await getTeam(teamId);
    if (team == null) return false;

    final members = getMembersList(team);
    if (team['host_id']?.toString() == userId) {
      return false;
    }

    members.removeWhere((m) => m['id']?.toString() == userId);

    try {
      await NetworkRetry.retry(() => _client.from('ludo_teams').update({
        'members': members,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId));
    } catch (e) {
      return false;
    }

    _teams[teamId] = {...team, 'members': members};
    return true;
  }

  Future<bool> updateMemberColor(String teamId, String userId, String color) async {
    final team = await getTeam(teamId);
    if (team == null) return false;

    final members = getMembersList(team);
    final idx = members.indexWhere((m) => m['id']?.toString() == userId);
    if (idx == -1) return false;

    members[idx]['color'] = color;

    try {
      await _client.from('ludo_teams').update({
        'members': members,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId);
    } catch (_) {
      return false;
    }

    _teams[teamId] = {...team, 'members': members};
    return true;
  }

  Future<bool> updateMemberBet(String teamId, String userId, int amount) async {
    final team = await getTeam(teamId);
    if (team == null) return false;

    final members = getMembersList(team);
    final idx = members.indexWhere((m) => m['id']?.toString() == userId);
    if (idx == -1) return false;

    members[idx]['bet'] = amount;

    try {
      await _client.from('ludo_teams').update({
        'members': members,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId);
    } catch (_) {
      return false;
    }

    _teams[teamId] = {...team, 'members': members};
    return true;
  }

  Future<void> resetMemberBets(String teamId) async {
    try {
      final team = await getTeam(teamId);
      if (team == null) return;
      final members = getMembersList(team);
      for (final member in members) {
        member['bet'] = 0;
      }
      await _client.from('ludo_teams').update({
        'members': members,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId);
      _teams[teamId] = {...team, 'members': members};
    } catch (_) {}
  }

  Future<void> startGame(String teamId) async {
    try {
      await NetworkRetry.retry(() => _client.from('ludo_teams').update({
        'status': 'playing',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId));
    } catch (_) {}
  }

  Future<void> updateStatus(String teamId, String status) async {
    try {
      await _client.from('ludo_teams').update({
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId);
    } catch (_) {}
    final team = _teams[teamId];
    if (team != null) team['status'] = status;
  }

  Future<void> updateBettingEnabled(String teamId, bool enabled, {bool? hostAiEnabled}) async {
    try {
      final team = await getTeam(teamId);
      if (team == null) return;
      final hostProfile = Map<String, dynamic>.from(team['host_profile'] as Map? ?? {});
      hostProfile['betting_enabled'] = enabled;
      hostProfile['host_ai_enabled'] = hostAiEnabled ?? !enabled;
      await _client.from('ludo_teams').update({
        'host_profile': hostProfile,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId);
      final cached = _teams[teamId];
      if (cached != null) cached['host_profile'] = hostProfile;
    } catch (_) {}
  }

  Future<void> updateMembers(String teamId, List<Map<String, dynamic>> members) async {
    try {
      await _client.from('ludo_teams').update({
        'members': members,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId);
    } catch (_) {}
    final team = _teams[teamId];
    if (team != null) team['members'] = members;
  }

  Future<void> setPublicWaiting(String teamId) async {
    try {
      await _client.from('ludo_teams').update({
        'status': 'public_waiting',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId);
    } catch (_) {}
    final team = _teams[teamId];
    if (team != null) team['status'] = 'public_waiting';
  }

  Future<void> cancelPublicWaiting(String teamId) async {
    try {
      await _client.from('ludo_teams').update({
        'status': 'waiting',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId);
    } catch (_) {}
    final team = _teams[teamId];
    if (team != null) team['status'] = 'waiting';
  }

  Future<Map<String, dynamic>?> findPublicMatch(String myTeamId, int mySize) async {
    try {
      final response = await _client
          .from('ludo_teams')
          .select()
          .eq('status', 'public_waiting')
          .neq('team_id', myTeamId)
          .limit(10);

      for (final row in response) {
        final team = Map<String, dynamic>.from(row);
        final members = team['members'];
        final otherSize = (members is List) ? members.length : 0;
        if (mySize + otherSize <= 4) {
          return team;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> claimForMatch(String teamId) async {
    try {
      await _client
          .from('ludo_teams')
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

  Future<bool> mergeTeams(String targetTeamId, String sourceTeamId) async {
    final target = await getTeam(targetTeamId);
    final source = await getTeam(sourceTeamId);
    if (target == null || source == null) return false;

    final targetMembers = getMembersList(target);
    final sourceMembers = getMembersList(source);

    if (targetMembers.length + sourceMembers.length > 4) return false;

    final availableColors = ['red', 'green', 'yellow', 'blue'];
    for (final m in targetMembers) {
      availableColors.remove(m['color']?.toString());
    }

    for (final m in sourceMembers) {
      if (availableColors.isNotEmpty) {
        m['color'] = availableColors.removeAt(0);
      }
      targetMembers.add(m);
    }

    try {
      await NetworkRetry.retry(() => _client.from('ludo_teams').update({
        'members': targetMembers,
        'status': 'playing',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', targetTeamId));

      await NetworkRetry.retry(() => _client.from('ludo_teams').update({
        'status': 'playing',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', sourceTeamId));
    } catch (e) {
      return false;
    }

    _teams[targetTeamId] = {...target, 'members': targetMembers, 'status': 'playing'};
    _teams[sourceTeamId] = {...source, 'status': 'playing'};
    return true;
  }

  Future<void> deleteTeam(String teamId) async {
    try {
      await NetworkRetry.retry(() => _client.from('ludo_teams').delete().eq('team_id', teamId));
    } catch (_) {}
    _teams.remove(teamId);
  }
}