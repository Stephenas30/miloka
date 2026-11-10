import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class PoolTeamLobbyService {
  PoolTeamLobbyService._();

  static final PoolTeamLobbyService instance = PoolTeamLobbyService._();

  SupabaseClient get _client => SupabaseService().client;

  Future<String> createRoom({required bool publicMatch}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Connectez-vous pour jouer en ligne.');
    final profile = await _client
        .from('users')
        .select('username, avatar_url')
        .eq('id', user.id)
        .single();
    final roomId = await _client.rpc(
      'create_pool_team',
      params: {
        'p_host_profile': profile,
        'p_access_type': publicMatch ? 'public' : 'friend',
      },
    );
    if (roomId is! String || roomId.isEmpty) {
      throw StateError('Le salon de billard n’a pas pu être créé.');
    }
    return roomId;
  }

  Future<Map<String, dynamic>?> getRoom(String roomId) async {
    final row = await _client
        .from('pool_teams')
        .select()
        .eq('team_id', roomId)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<String?> tryMatchPublicRoom(String roomId) async {
    final result = await _client.rpc(
      'try_match_pool_team',
      params: {'p_team_id': roomId},
    );
    return result?.toString();
  }

  Future<bool> joinRoom(
    String roomId, {
    required int? invitationId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Connectez-vous pour jouer en ligne.');
    final profile = await _client
        .from('users')
        .select('username, avatar_url')
        .eq('id', user.id)
        .single();
    final result = await _client.rpc(
      'join_pool_team',
      params: {
        'p_team_id': roomId,
        'p_guest_profile': profile,
        'p_invitation_id': invitationId,
      },
    );
    return result == true;
  }

  Future<String?> joinRoomByCode(String code) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Connectez-vous pour rejoindre.');
    final profile = await _client
        .from('users')
        .select('username, avatar_url')
        .eq('id', user.id)
        .single();
    final result = await _client.rpc(
      'join_pool_team_by_code',
      params: {
        'p_join_code': code,
        'p_guest_profile': profile,
      },
    );
    return result is String && result.isNotEmpty ? result : null;
  }

  Future<bool> startRoom(String roomId, int seed) async {
    final result = await _client.rpc(
      'start_pool_team',
      params: {'p_team_id': roomId, 'p_game_seed': seed},
    );
    return result == true;
  }

  Future<int> getCurrentUserCoins() async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Connectez-vous pour miser.');
    final row = await _client
        .from('users')
        .select('coins')
        .eq('id', user.id)
        .single();
    return (row['coins'] as num?)?.toInt() ?? 0;
  }

  Future<bool> setRoomBet(String roomId, int amount) async {
    final result = await _client.rpc(
      'set_pool_team_bet',
      params: {'p_team_id': roomId, 'p_bet': amount},
    );
    return result == true;
  }

  Future<bool> setBetAgreement(String roomId, bool agreed) async {
    final result = await _client.rpc(
      'set_pool_team_bet_agreement',
      params: {'p_team_id': roomId, 'p_agreed': agreed},
    );
    return result == true;
  }

  Future<bool> settleRoom(String roomId, int winnerIndex) async {
    final result = await _client.rpc(
      'settle_pool_team',
      params: {'p_team_id': roomId, 'p_winner_index': winnerIndex},
    );
    return result == true;
  }

  Future<bool> cancelRoom(String roomId) async {
    final result = await _client.rpc(
      'cancel_pool_team',
      params: {'p_team_id': roomId},
    );
    return result == true;
  }
}
