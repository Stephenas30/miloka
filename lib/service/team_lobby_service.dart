import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/retry_util.dart';
import 'supabase_service.dart';

class TeamLobbyService {
  static final TeamLobbyService _instance = TeamLobbyService._internal();

  factory TeamLobbyService() => _instance;

  TeamLobbyService._internal();

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
        .from('teams')
        .select('team_id')
        .eq('team_id', teamId)
        .maybeSingle();
    return response != null;
  }

  Future<String?> createTeam(String hostId, Map<String, dynamic> hostProfile) async {
    final teamId = _generateTeamId();

    final payload = {
      'team_id': teamId,
      'host_id': hostId,
      'host_profile': hostProfile,
      'guest_id': null,
      'guest_profile': null,
      'guest_ready': false,
      'status': 'waiting',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await NetworkRetry.retry(() => _client.from('teams').insert(payload));
    } catch (e) {
      print('createTeam failed after retries: $e');
      return null;
    }

    _teams[teamId] = payload;
    return teamId;
  }

  Future<Map<String, dynamic>?> getTeam(String teamId) async {
    try {
      final response = await _client
          .from('teams')
          .select('team_id, host_id, host_profile, guest_id, guest_profile, guest_ready, status')
          .eq('team_id', teamId)
          .maybeSingle();
      if (response == null) {
        return _teams[teamId];
      }
      return Map<String, dynamic>.from(response);
    } catch (_) {
      return _teams[teamId];
    }
  }

  Future<bool> joinTeam(
    String teamId,
    String guestId,
    Map<String, dynamic> guestProfile,
  ) async {
    final team = await getTeam(teamId);
    if (team == null) return false;
    if (team['guest_id'] != null) return false;

    final payload = {
      'guest_id': guestId,
      'guest_profile': guestProfile,
      'guest_ready': false,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await NetworkRetry.retry(() => _client.from('teams').update(payload).eq('team_id', teamId));
    } catch (e) {
      print('joinTeam failed after retries: $e');
      return false;
    }

    _teams[teamId] = {
      ...team,
      ...payload,
    };
    return true;
  }

  Future<bool> updateGuestReady(String teamId, bool ready) async {
    final team = await getTeam(teamId);
    if (team == null) return false;
    if (team['guest_id'] == null) return false;

    final payload = {
      'guest_ready': ready,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      await _client.from('teams').update(payload).eq('team_id', teamId);
    } catch (_) {
      return false;
    }

    _teams[teamId] = {
      ...team,
      ...payload,
    };
    return true;
  }

  Future<void> updateHostProfile(String teamId, Map<String, dynamic> profile) async {
    final payload = {
      'host_profile': profile,
      'updated_at': DateTime.now().toIso8601String(),
    };
    try {
      await _client.from('teams').update(payload).eq('team_id', teamId);
    } catch (_) {}
    final team = _teams[teamId];
    if (team != null) {
      team['host_profile'] = profile;
    }
  }

  Future<void> startGame(String teamId) async {
    try {
      await NetworkRetry.retry(() => _client.from('teams').update({
        'status': 'playing',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId));
    } catch (e) {
      print('startGame failed after retries: $e');
    }
  }

  Future<void> resetGame(String teamId) async {
    try {
      await NetworkRetry.retry(() => _client.from('teams').update({
        'status': 'waiting',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId));
    } catch (e) {
      print('resetGame failed after retries: $e');
    }
  }

  Future<void> removeGuest(String teamId) async {
    try {
      await NetworkRetry.retry(() => _client.from('teams').update({
        'guest_id': null,
        'guest_profile': null,
        'guest_ready': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId));
    } catch (e) {
      print('removeGuest failed after retries: $e');
    }
    final team = _teams[teamId];
    if (team != null) {
      team['guest_id'] = null;
      team['guest_profile'] = null;
      team['guest_ready'] = false;
    }
  }

  Future<void> setPublicWaiting(String teamId) async {
    try {
      await _client.from('teams').update({
        'status': 'public_waiting',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId);
    } catch (_) {}
    final team = _teams[teamId];
    if (team != null) team['status'] = 'public_waiting';
  }

  Future<void> cancelPublicWaiting(String teamId) async {
    try {
      await _client.from('teams').update({
        'status': 'waiting',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('team_id', teamId);
    } catch (_) {}
    final team = _teams[teamId];
    if (team != null) team['status'] = 'waiting';
  }

  Future<Map<String, dynamic>?> findPublicMatch(String myTeamId) async {
    try {
      final response = await _client
          .from('teams')
          .select()
          .eq('status', 'public_waiting')
          .neq('team_id', myTeamId)
          .limit(1)
          .maybeSingle();
      if (response != null) {
        return Map<String, dynamic>.from(response);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> claimForMatch(String teamId) async {
    try {
      final response = await _client
          .from('teams')
          .update({
            'status': 'public_matched',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('team_id', teamId)
          .eq('status', 'public_waiting');
      if (response != null && response is List && response.isEmpty) return false;
      final team = _teams[teamId];
      if (team != null) team['status'] = 'public_matched';
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteTeam(String teamId) async {
    try {
      await NetworkRetry.retry(() => _client.from('teams').delete().eq('team_id', teamId));
    } catch (e) {
      print('deleteTeam failed after retries: $e');
    }
    _teams.remove(teamId);
  }
}

