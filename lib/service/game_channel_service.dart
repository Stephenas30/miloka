import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class GameChannelService {
  static final GameChannelService _instance = GameChannelService._internal();
  factory GameChannelService() => _instance;
  GameChannelService._internal();

  RealtimeChannel? _channel;
  StreamController<Map<String, dynamic>> _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  int _connectionGen = 0;
  int get connectionGen => _connectionGen;

  Future<void> connect(String teamId) async {
    _connectionGen++;
    _eventController = StreamController<Map<String, dynamic>>.broadcast();
    _channel = SupabaseService().client.channel('game:$teamId');
    _channel!.onBroadcast(
      event: 'game_event',
      callback: (payload) {
        _eventController.add(Map<String, dynamic>.from(payload));
      },
    );
    _channel!.subscribe((status, error) {
      print('GameChannel subscribed: $status ${error ?? ''}');
    });
  }

  Future<void> send(String action, Map<String, dynamic> data) async {
    if (_channel == null) return;
    try {
      await _channel!.sendBroadcastMessage(
        event: 'game_event',
        payload: {'action': action, ...data},
      );
    } catch (e) {
      print('GameChannel send error: $e');
    }
  }

  Future<void> disconnect() async {
    await _channel?.unsubscribe();
    _channel = null;
  }

  Future<void> reconnect(String teamId) async {
    await disconnect();
    await connect(teamId);
  }
}
