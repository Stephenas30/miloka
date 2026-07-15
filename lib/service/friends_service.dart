import 'package:miloka/service/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FriendsService {
  final SupabaseClient client = SupabaseService().client;

  Future<List<dynamic>> getSuggestedFriends() async {
    List<dynamic> suggestedFriends = [];
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      // Exclude users who are already friends
      final friendsResponse = await client
          .from('amis')
          .select('id_ami')
          .eq('id_user', userId);
      List<String> friendIds = [];
      for (var f in friendsResponse) {
        if (f['id_ami'] != null) friendIds.add(f['id_ami']);
      }

      late final dynamic response;
      if (friendIds.isEmpty) {
        response = await client
            .from('users')
            .select()
            .neq('id', userId)
            .limit(10);
      } else {
        // use 'not in' filter to exclude friend ids
        final inList = friendIds.map((id) => '"$id"').join(',');
        response = await client
            .from('users')
            .select()
            .not('id', 'in', '($inList)')
            .neq('id', userId)
            .limit(10);
      }
      for (var friend in response) {
        suggestedFriends.add({
          'id': friend['id'],
          'username': friend['username'],
          'avatar_url': friend['avatar_url'],
          'is_connected': friend['is_connected'],
        });
      }
      return suggestedFriends;
    } catch (e) {
      throw Exception('Erreur lors de la récupération des amis suggérés: $e');
    }
  }

  Future<void> addFriend(String friendId) async {
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Vérifier si une demande existe déjà de sa part (pending)
      final existingRequest = await client
          .from('amis')
          .select()
          .eq('id_user', friendId)
          .eq('id_ami', userId)
          .eq('status', 'pending')
          .maybeSingle();

      if (existingRequest != null) {
        // Auto-accept: la personne nous avait déjà envoyé une demande
        await acceptFriendRequest(friendId);
        return;
      }

      // Vérifier si déjà ami ou déjà envoyé
      final existing = await client
          .from('amis')
          .select()
          .eq('id_user', userId)
          .eq('id_ami', friendId)
          .maybeSingle();

      if (existing != null) {
        throw Exception('Demande déjà envoyée');
      }

      await client.from('amis').insert({
        'id_user': userId,
        'id_ami': friendId,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Erreur lors de l\'envoi de la demande d\'ami: $e');
    }
  }

  Future<List<dynamic>> getFriendsList() async {
    List<dynamic> friendsList = [];
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      final response = await client
          .from('amis')
          .select('id_ami')
          .eq('id_user', userId)
          .eq('status', 'accepted');
      for (var friend in response) {
        final friendDetails = await client
            .from('users')
            .select()
            .eq('id', friend['id_ami'])
            .single();
        friendsList.add({
          'id': friendDetails['id'],
          'username': friendDetails['username'],
          'avatar_url': friendDetails['avatar_url'],
          'is_connected': friendDetails['is_connected'],
        });
      }
      return friendsList;
    } catch (e) {
      throw Exception('Erreur lors de la récupération de la liste d\'amis: $e');
    }
  }

  Future<List<dynamic>> getFriendsSubscribeToGam() async {
    List<dynamic> friendsList = [];
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      final response = await client
          .from('amis')
          .select('id_ami')
          .eq('send_partie', 'accepted')
          .eq('id_user', userId);
      for (var friend in response) {
        final friendDetails = await client
            .from('users')
            .select()
            .eq('id', friend['id_ami'])
            .single();
        friendsList.add({
          'id': friendDetails['id'],
          'username': friendDetails['username'],
          'avatar_url': friendDetails['avatar_url'],
          //'is_connected': friendDetails['is_connected'],
        });
      }

      print('serveur => $friendsList');
      return friendsList;
    } catch (e) {
      throw Exception('Erreur lors de la récupération de la liste d\'amis: $e');
    }
  }

  Future<List<dynamic>> getHoteSubscribeToGam() async {
    List<dynamic> friendsList = [];
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      final response = await client
          .from('amis')
          .select('id_user')
          .eq('send_partie', 'accepted')
          .eq('id_ami', userId);
      for (var friend in response) {
        final friendDetails = await client
            .from('users')
            .select()
            .eq('id', friend['id_user'])
            .single();
        friendsList.add({
          'id': friendDetails['id'],
          'username': friendDetails['username'],
          'avatar_url': friendDetails['avatar_url'],
          //'is_connected': friendDetails['is_connected'],
        });
      }
      return friendsList;
    } catch (e) {
      throw Exception('Erreur lors de la récupération de la liste d\'amis: $e');
    }
  }

  Future<void> removeFriendSubscribeToGam(String friendId) async {
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      await client
          .from('amis')
          .update({'send_partie': 'none'})
          .or('id_user.eq.$userId, id_user.eq.$friendId, id_user.eq.$friendId, id_user.eq.$userId');
    } catch (e) {
      throw Exception('Erreur lors de la suppression d\'un ami: $e');
    }
  }

   Future<void> playingGame(String friendId) async {
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      await client
          .from('amis')
          .update({'send_partie': 'playing'})
          .eq('id_user', userId)
          .eq('id_ami', friendId);
    } catch (e) {
      throw Exception('Erreur lors de la suppression d\'un ami: $e');
    }
  }

  Future<void> removeFriend(String friendId) async {
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      // Supprimer les deux lignes pour rompre l'amitié mutuelle
      await client
          .from('amis')
          .delete()
          .eq('id_user', userId)
          .eq('id_ami', friendId);
      await client
          .from('amis')
          .delete()
          .eq('id_user', friendId)
          .eq('id_ami', userId);
    } catch (e) {
      throw Exception('Erreur lors de la suppression d\'un ami: $e');
    }
  }

  Future<Set<String>> getPendingSentFriendIds() async {
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await client
          .from('amis')
          .select('id_ami')
          .eq('id_user', userId)
          .eq('status', 'pending');
      return response.map<String>((r) => r['id_ami'].toString()).toSet();
    } catch (e) {
      throw Exception('Erreur lors de la récupération des demandes envoyées: $e');
    }
  }

  Future<List<dynamic>> getFriendRequests() async {
    List<dynamic> requests = [];
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await client
          .from('amis')
          .select('id_user')
          .eq('id_ami', userId)
          .eq('status', 'pending');
      for (var req in response) {
        final userDetails = await client
            .from('users')
            .select()
            .eq('id', req['id_user'])
            .single();
        requests.add({
          'id': userDetails['id'],
          'username': userDetails['username'],
          'avatar_url': userDetails['avatar_url'],
        });
      }
      return requests;
    } catch (e) {
      throw Exception('Erreur lors de la récupération des demandes d\'ami: $e');
    }
  }

  Future<void> acceptFriendRequest(String requesterId) async {
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Marquer la demande comme acceptée
      await client
          .from('amis')
          .update({'status': 'accepted'})
          .eq('id_user', requesterId)
          .eq('id_ami', userId);

      // Créer la ligne inverse pour une amitié mutuelle
      await client.from('amis').insert({
        'id_user': userId,
        'id_ami': requesterId,
        'status': 'accepted',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Erreur lors de l\'acceptation de la demande d\'ami: $e');
    }
  }

  Future<void> declineFriendRequest(String requesterId) async {
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await client
          .from('amis')
          .delete()
          .eq('id_user', requesterId)
          .eq('id_ami', userId);
    } catch (e) {
      throw Exception('Erreur lors du refus de la demande d\'ami: $e');
    }
  }

  Future<List<dynamic>> searchUsers(String query) async {
    List<dynamic> results = [];
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await client
          .from('users')
          .select()
          .ilike('username', '%$query%')
          .neq('id', userId)
          .limit(20);
      for (var user in response) {
        results.add({
          'id': user['id'],
          'username': user['username'],
          'avatar_url': user['avatar_url'],
          'is_connected': user['is_connected'],
        });
      }
      return results;
    } catch (e) {
      throw Exception('Erreur lors de la recherche d\'utilisateurs: $e');
    }
  }

  Future<void> sendGameRequest(String receiverId) async {
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      await client
          .from('amis')
          .update({'send_partie': 'pending'})
          .eq('id_ami', receiverId)
          .eq('id_user', userId);
    } catch (e) {
      throw Exception('Erreur lors de l\'envoie de requête vers l\' ami: $e');
    }
  }
}
