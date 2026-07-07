import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<String> createTeam(String hostId, Map<String, dynamic> hostProfile) async {
    final teamId = _generateTeamId();

    final payload = {
      'team_id': teamId,
      'host_id': hostId,
      'host_profile': hostProfile,
      'guest_id': null,
      'guest_profile': null,
      'guest_ready': false,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    await _client.from('teams').insert(payload);
    _teams[teamId] = payload;
    return teamId;
  }

  Future<Map<String, dynamic>?> getTeam(String teamId) async {
    try {
      final response = await _client
          .from('teams')
          .select('team_id, host_id, host_profile, guest_id, guest_profile, guest_ready')
          .eq('team_id', teamId)
          .maybeSingle();
      if (response == null) {
        return _teams[teamId];
      }
      return Map<String, dynamic>.from(response as Map<String, dynamic>);
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
}

