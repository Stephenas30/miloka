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
  bool _subscribed = false;
  bool _intentionalDisconnect = false;
  Timer? _resubscribeTimer;

  Future<void> connect(String teamId) async {
    _teamId = teamId;
    _intentionalDisconnect = false;
    _eventController = StreamController<Map<String, dynamic>>.broadcast();
    await _join(teamId);
  }

  Future<void> _join(String teamId) async {
    final completer = Completer<void>();
    final channel = SupabaseService().client.channel('game:$teamId');
    _channel = channel;
    channel.onBroadcast(
      event: 'game_event',
      callback: (payload) {
        _eventController.add(Map<String, dynamic>.from(payload));
      },
    );
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _subscribed = true;
        _resubscribeTimer?.cancel();
        if (!completer.isCompleted) completer.complete();
      } else if (status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.channelError) {
        _subscribed = false;
        if (!completer.isCompleted) {
          completer.completeError(Exception('Subscribe failed: $status ${error ?? ''}'));
        } else if (!_intentionalDisconnect && identical(channel, _channel)) {
          // Perte de connexion en cours de partie (app en arrière-plan,
          // bascule réseau...) : on réabonne le canal automatiquement.
          _scheduleResubscribe(channel);
        }
      }
    });
    await completer.future.timeout(const Duration(seconds: 10));
  }

  void _scheduleResubscribe(RealtimeChannel deadChannel) {
    _resubscribeTimer?.cancel();
    _resubscribeTimer = Timer(const Duration(seconds: 2), () async {
      if (_intentionalDisconnect || _teamId == null || _subscribed) return;
      if (!identical(deadChannel, _channel)) return;
      try {
        await deadChannel.unsubscribe();
      } catch (_) {}
      try {
        await _join(_teamId!);
      } catch (_) {
        _scheduleResubscribe(deadChannel);
      }
    });
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
    _intentionalDisconnect = true;
    _resubscribeTimer?.cancel();
    try {
      await _channel?.unsubscribe();
    } catch (_) {}
    _channel = null;
    _subscribed = false;
  }

  Future<void> reconnect() async {
    final id = _teamId;
    if (id == null) return;
    await disconnect();
    await connect(id);
  }
}
