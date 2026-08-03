import 'package:supabase_flutter/supabase_flutter.dart';
import 'ludo_team_lobby_service.dart';
import 'supabase_service.dart';

class LudoTeamInvitationService {
  static final LudoTeamInvitationService _instance = LudoTeamInvitationService._internal();
  factory LudoTeamInvitationService() => _instance;
  LudoTeamInvitationService._internal();

  final SupabaseService _supabase = SupabaseService();
  SupabaseClient get _client => _supabase.client;

  Future<void> sendInvitation({
    required String inviteeId,
    required String teamId,
    required String inviterName,
  }) async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) throw Exception('Not authenticated');

    await _client.from('team_invitations').insert({
      'inviter_id': currentUser.id,
      'invitee_id': inviteeId,
      'team_id': teamId,
      'inviter_name': inviterName,
      'game_type': 'ludo',
      'status': 'pending',
    });
  }

  Future<Map<String, dynamic>?> acceptInvitation(int invitationId) async {
    final inv = await _client.from('team_invitations').select().eq('id', invitationId).maybeSingle();
    if (inv == null) return null;

    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return null;

    final profile = await _client.from('users').select().eq('id', currentUser.id).single();

    final joined = await LudoTeamLobbyService().addMember(inv['team_id'], currentUser.id, profile);
    if (!joined) return null;

    await _client.from('team_invitations').update({'status': 'accepted'}).eq('id', invitationId);
    return inv;
  }

  Future<void> declineInvitation(int invitationId) async {
    await _client.from('team_invitations').update({'status': 'declined'}).eq('id', invitationId);
  }

  Stream<List<Map<String, dynamic>>> subscribeToInvitations() {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return const Stream.empty();

    return _client
        .from('team_invitations')
        .stream(primaryKey: ['id'])
        .map((rows) => rows
            .where((r) =>
                r['invitee_id'] == currentUser.id &&
                r['status'] == 'pending' &&
                r['game_type'] == 'ludo')
            .map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r))
            .toList());
  }

  Future<List<Map<String, dynamic>>> getPendingInvitations() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return [];

    final response = await _client
        .from('team_invitations')
        .select()
        .eq('invitee_id', currentUser.id)
        .eq('status', 'pending')
        .eq('game_type', 'ludo')
        .order('created_at', ascending: false);

    return response.map<Map<String, dynamic>>((r) => Map<String, dynamic>.from(r)).toList();
  }
}