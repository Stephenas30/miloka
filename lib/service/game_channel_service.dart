import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/retry_util.dart';
import 'supabase_service.dart';

class GameChannelService {
  static final GameChannelService _instance = GameChannelService._internal();
  factory GameChannelService() => _instance;
  GameChannelService._internal();

  RealtimeChannel? _channel;
  StreamController<Map<String, dynamic>> _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  String? _teamId;

  Future<void> connect(String teamId) async {
    _teamId = teamId;
    _eventController = StreamController<Map<String, dynamic>>.broadcast();
    _channel = SupabaseService().client.channel('game:$teamId');
    _channel!.onBroadcast(
      event: 'game_event',
      callback: (payload) {
        _eventController.add(Map<String, dynamic>.from(payload));
      },
    );
    final completer = Completer<void>();
    _channel!.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (!completer.isCompleted) completer.complete();
      } else if (status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.channelError) {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Subscribe failed: $status ${error ?? ''}'));
        }
      }
    });
    await completer.future.timeout(const Duration(seconds: 10));
  }

  Future<void> send(String action, Map<String, dynamic> data, {String? from}) async {
    if (_channel == null) return;
    final payload = <String, dynamic>{'action': action, ...data};
    if (from != null) payload['_from'] = from;
    try {
      await NetworkRetry.retry(() => _channel!.sendBroadcastMessage(
        event: 'game_event',
        payload: payload,
      ));
    } catch (e) {
      print('GameChannel send failed after retries: $e');
    }
  }

  Future<void> disconnect() async {
    await _channel?.unsubscribe();
    _channel = null;
  }

  Future<void> reconnect() async {
    final id = _teamId;
    if (id == null) return;
    await disconnect();
    await connect(id);
  }
}
