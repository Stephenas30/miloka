import 'package:supabase_flutter/supabase_flutter.dart';

import 'pool_team_lobby_service.dart';
import 'supabase_service.dart';

class PoolTeamInvitationService {
  SupabaseClient get _client => SupabaseService().client;

  Future<void> sendInvitation({
    required String inviteeId,
    required String teamId,
    required String inviterName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Connectez-vous pour inviter un ami.');
    await _client.from('team_invitations').insert({
      'inviter_id': user.id,
      'invitee_id': inviteeId,
      'team_id': teamId,
      'inviter_name': inviterName,
      'game_type': 'billard',
      'status': 'pending',
    });
  }

  Future<Map<String, dynamic>?> acceptInvitation(int invitationId) async {
    final invitation = await _client
        .from('team_invitations')
        .select()
        .eq('id', invitationId)
        .eq('game_type', 'billard')
        .maybeSingle();
    if (invitation == null) return null;

    final joined = await PoolTeamLobbyService.instance.joinRoom(
      invitation['team_id'].toString(),
      invitationId: invitationId,
    );
    if (!joined) return null;
    return Map<String, dynamic>.from(invitation);
  }

  Future<void> declineInvitation(int invitationId) async {
    await _client
        .from('team_invitations')
        .update({'status': 'declined'})
        .eq('id', invitationId)
        .eq('game_type', 'billard');
  }

  Future<List<Map<String, dynamic>>> getPendingInvitations() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final rows = await _client
        .from('team_invitations')
        .select()
        .eq('invitee_id', user.id)
        .eq('status', 'pending')
        .eq('game_type', 'billard')
        .order('created_at', ascending: false);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }
}
