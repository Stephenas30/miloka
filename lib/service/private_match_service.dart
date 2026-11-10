import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/retry_util.dart';
import 'supabase_service.dart';

class PrivateMatchService {
  static final PrivateMatchService _instance = PrivateMatchService._internal();
  factory PrivateMatchService() => _instance;
  PrivateMatchService._internal();

  final SupabaseService _supabaseService = SupabaseService();
  SupabaseClient get _client => _supabaseService.client;
  final Map<String, Map<String, dynamic>> _matches = {};

  String _generateCode() {
    const min = 100000;
    const max = 999999;
    var code = (min + Random().nextInt(max - min)).toString();
    while (_matches.containsKey(code)) {
      code = (min + Random().nextInt(max - min)).toString();
    }
    return code;
  }

  Future<String?> createMatch({
    required String teamAId,
    required String hostId,
    required Map<String, dynamic> hostProfile,
    required String guestId,
    required Map<String, dynamic> guestProfile,
  }) async {
    final code = _generateCode();
    final match = {
      'match_code': code,
      'team_a_id': teamAId,
      'team_a_host_id': hostId,
      'team_a_host_profile': hostProfile,
      'team_a_guest_id': guestId,
      'team_a_guest_profile': guestProfile,
      'team_b_id': null,
      'team_b_host_id': null,
      'team_b_host_profile': null,
      'team_b_guest_id': null,
      'team_b_guest_profile': null,
      'status': 'waiting',
    };
    _matches[code] = match;

    try {
      await NetworkRetry.retry(() => _client.from('private_matches').insert(match));
    } catch (e) {
      print('createMatch failed after retries: $e');
      _matches.remove(code);
      return null;
    }

    return code;
  }

  Future<bool> joinMatch({
    required String matchCode,
    required String teamBId,
    required String hostId,
    required Map<String, dynamic> hostProfile,
    required String guestId,
    required Map<String, dynamic> guestProfile,
  }) async {
    final match = await getMatch(matchCode);
    if (match == null || match['status'] != 'waiting') return false;

    match['team_b_id'] = teamBId;
    match['team_b_host_id'] = hostId;
    match['team_b_host_profile'] = hostProfile;
    match['team_b_guest_id'] = guestId;
    match['team_b_guest_profile'] = guestProfile;
    match['status'] = 'ready';
    _matches[matchCode] = match;

    try {
      await NetworkRetry.retry(() => _client.from('private_matches').update({
        'team_b_id': teamBId,
        'team_b_host_id': hostId,
        'team_b_host_profile': hostProfile,
        'team_b_guest_id': guestId,
        'team_b_guest_profile': guestProfile,
        'status': 'ready',
      }).eq('match_code', matchCode));
      return true;
    } catch (e) {
      print('joinMatch failed after retries: $e');
      if (_matches.containsKey(matchCode)) {
        _matches.remove(matchCode);
      }
      return false;
    }
  }

  Future<void> cancelMatch(String code) async {
    final match = _matches[code];
    if (match != null) {
      match['status'] = 'cancelled';
    }
    try {
      await NetworkRetry.retry(() => _client.from('private_matches').update({
        'status': 'cancelled',
      }).eq('match_code', code));
    } catch (e) {
      print('cancelMatch failed after retries: $e');
    }
  }

  Future<String?> createPublicMatch({
    required String teamAId,
    required String teamAHostId,
    required Map<String, dynamic> teamAHostProfile,
    required String teamAGuestId,
    required Map<String, dynamic> teamAGuestProfile,
    required String teamBId,
    required String teamBHostId,
    required Map<String, dynamic> teamBHostProfile,
    required String teamBGuestId,
    required Map<String, dynamic> teamBGuestProfile,
  }) async {
    final code = _generateCode();
    final match = {
      'match_code': code,
      'team_a_id': teamAId,
      'team_a_host_id': teamAHostId,
      'team_a_host_profile': teamAHostProfile,
      'team_a_guest_id': teamAGuestId,
      'team_a_guest_profile': teamAGuestProfile,
      'team_b_id': teamBId,
      'team_b_host_id': teamBHostId,
      'team_b_host_profile': teamBHostProfile,
      'team_b_guest_id': teamBGuestId,
      'team_b_guest_profile': teamBGuestProfile,
      'status': 'ready',
    };
    _matches[code] = match;
    try {
      await NetworkRetry.retry(() => _client.from('private_matches').insert(match));
    } catch (e) {
      print('createPublicMatch failed after retries: $e');
      _matches.remove(code);
      return null;
    }
    return code;
  }

  Future<Map<String, dynamic>?> getMatch(String code, {bool forceRefresh = false}) async {
    if (!forceRefresh && _matches.containsKey(code) && _matches[code]!['status'] != 'cancelled') {
      return _matches[code];
    }
    try {
      final response = await _client
          .from('private_matches')
          .select()
          .eq('match_code', code)
          .maybeSingle();
      if (response != null) {
        final match = Map<String, dynamic>.from(response);
        _matches[code] = match;
        return match;
      }
    } catch (_) {
      if (_matches.containsKey(code) && _matches[code]!['status'] != 'cancelled') {
        return _matches[code];
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> findMatchByTeamId(String teamId) async {
    try {
      final response = await _client
          .from('private_matches')
          .select()
          .or('team_a_id.eq.$teamId,team_b_id.eq.$teamId')
          .eq('status', 'ready')
          .limit(1)
          .maybeSingle();
      if (response != null) {
        final match = Map<String, dynamic>.from(response);
        final code = match['match_code'] as String;
        _matches[code] = match;
        return match;
      }
    } catch (_) {}
    return null;
  }

  Future<void> placeBet(String matchCode, String position, int amount) async {
    try {
      final current = await getMatch(matchCode, forceRefresh: true);
      final bets = Map<String, dynamic>.from(current?['bets'] as Map? ?? {});
      bets[position] = amount;
      await _client.from('private_matches').update({'bets': bets}).eq('match_code', matchCode);
      if (_matches.containsKey(matchCode)) {
        _matches[matchCode]!['bets'] = bets;
      }
    } catch (e) {
      print('placeBet failed: $e');
    }
  }

  Future<void> acceptBet(String matchCode, String position) async {
    try {
      final current = await getMatch(matchCode, forceRefresh: true);
      final accepted = List<String>.from(current?['accepted_by'] as List? ?? []);
      if (!accepted.contains(position)) {
        accepted.add(position);
      }
      await _client.from('private_matches').update({'accepted_by': accepted}).eq('match_code', matchCode);
      if (_matches.containsKey(matchCode)) {
        _matches[matchCode]!['accepted_by'] = accepted;
      }
    } catch (e) {
      print('acceptBet failed: $e');
    }
  }

  Future<void> rejectBets(String matchCode) async {
    try {
      await _client.from('private_matches').update({
        'bets': {},
        'accepted_by': [],
      }).eq('match_code', matchCode);
      if (_matches.containsKey(matchCode)) {
        _matches[matchCode]!['bets'] = <String, dynamic>{};
        _matches[matchCode]!['accepted_by'] = <dynamic>[];
      }
    } catch (e) {
      print('rejectBets failed: $e');
    }
  }

  Stream<Map<String, dynamic>> subscribeToMatch(String matchCode) {
    return _client
        .from('private_matches')
        .stream(primaryKey: ['match_code'])
        .eq('match_code', matchCode)
        .map((rows) => rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : <String, dynamic>{});
  }
}
