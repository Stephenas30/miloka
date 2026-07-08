import 'package:miloka/service/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FriendsService {

  final SupabaseClient client = SupabaseService().client;

  Future<List<dynamic>> getSuggestedFriends() async {
    List<dynamic> suggestedFriends = [];
    try{
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      // Exclude users who are already friends
      final friendsResponse = await client.from('amis').select('id_ami').eq('id_user', userId);
      List<String> friendIds = [];
      for (var f in friendsResponse) {
        if (f['id_ami'] != null) friendIds.add(f['id_ami']);
      }

      late final dynamic response;
      if (friendIds.isEmpty) {
        response = await client.from('users').select().neq('id', userId).limit(10);
      } else {
        // use 'not in' filter to exclude friend ids
        final inList = friendIds.map((id) => '"$id"').join(',');
        response = await client.from('users').select().not('id', 'in', '($inList)').neq('id', userId).limit(10);
      }
      for(var friend in response) {
        suggestedFriends.add({
          'id': friend['id'],
          'username': friend['username'],
          'avatar_url': friend['avatar_url'],
          'is_connected': friend['is_connected'],
        });
      }
      return suggestedFriends;
    }catch (e) {
      throw Exception('Erreur lors de la récupération des amis suggérés: $e');
    }
  }

  Future<void> addFriend(String friendId) async {
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      await client.from('amis').insert({
        'id_user': userId,
        'id_ami': friendId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      throw Exception('Erreur lors de l\'ajout d\'un ami: $e');
    }
  }

  Future<List<dynamic>> getFriendsList() async {
    List<dynamic> friendsList = [];
    try{
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      final response = await client.from('amis').select('id_ami').eq('id_user', userId);
      for(var friend in response) {
        final friendDetails = await client.from('users').select().eq('id', friend['id_ami']).single();
        friendsList.add({
          'id': friendDetails['id'],
          'username': friendDetails['username'],
          'avatar_url': friendDetails['avatar_url'],
          'is_connected': friendDetails['is_connected'],
        });
      }
      return friendsList;
    }catch (e) {
      throw Exception('Erreur lors de la récupération de la liste d\'amis: $e');
    }
  }

  Future<void> removeFriend(String friendId) async {
    try {
      final userId = SupabaseService().client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }
      await client.from('amis').delete().eq('id_user', userId).eq('id_ami', friendId);
    } catch (e) {
      throw Exception('Erreur lors de la suppression d\'un ami: $e');
    }
  }

}