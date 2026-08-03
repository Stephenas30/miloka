import 'dart:async';
import 'package:realtime_client/src/types.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DominoMultiplayerSession {
  final String roomCode;
  final bool isHost;
  final String playerName;

  const DominoMultiplayerSession({
    required this.roomCode,
    required this.isHost,
    required this.playerName,
  });
}

class DominoMultiplayerService {
  DominoMultiplayerService._internal();

  static final DominoMultiplayerService _instance =
      DominoMultiplayerService._internal();

  factory DominoMultiplayerService() => _instance;

  final SupabaseClient _client = Supabase.instance.client;
  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, StreamController<Map<String, dynamic>>> _streams = {};
  final Map<String, List<Map<String, dynamic>>> _participants = {};

  String _channelName(String roomCode) => 'domino_room_$roomCode';

  Future<DominoMultiplayerSession> createRoom({
    required String roomCode,
    required String playerId,
    required String playerName,
  }) async {
    final channelName = _channelName(roomCode);
    final channel = _client.channel(channelName);

    _streams[channelName] = StreamController<Map<String, dynamic>>.broadcast();
    _participants[channelName] = [
      {'id': playerId, 'name': playerName},
    ];

    await channel.subscribe();
    _registerChannelListeners(channel, channelName);
    _channels[channelName] = channel;

    _sendPresence(channel, channelName, playerId, playerName);

    return DominoMultiplayerSession(
      roomCode: roomCode,
      isHost: true,
      playerName: playerName,
    );
  }

  Future<DominoMultiplayerSession> joinRoom({
    required String roomCode,
    required String playerId,
    required String playerName,
  }) async {
    final channelName = _channelName(roomCode);
    final channel = _client.channel(channelName);

    _streams[channelName] = StreamController<Map<String, dynamic>>.broadcast();
    _participants.putIfAbsent(channelName, () => []);

    await channel.subscribe();
    _registerChannelListeners(channel, channelName);
    _channels[channelName] = channel;

    _sendPresence(channel, channelName, playerId, playerName);

    return DominoMultiplayerSession(
      roomCode: roomCode,
      isHost: false,
      playerName: playerName,
    );
  }

  void _sendPresence(
    RealtimeChannel channel,
    String channelName,
    String playerId,
    String playerName,
  ) {
    final existing = _participants.putIfAbsent(channelName, () => []);
    if (!existing.any((e) => e['id'] == playerId)) {
      existing.add({'id': playerId, 'name': playerName});
    }
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'domino_presence',
      type: RealtimeListenTypes.broadcast,
      payload: {
        'type': 'presence',
        'action': 'join',
        'player': {'id': playerId, 'name': playerName},
      },
    );
  }

  void _registerChannelListeners(RealtimeChannel channel, String channelName) {
    for (final event in [
      'domino_state',
      'domino_state_response',
      'domino_start',
      'domino_game_ended',
      'domino_player_left',
      'domino_player_ready',
    ]) {
      channel.onBroadcast(event: event, callback: (payload, [ref]) {
        _streams[channelName]
            ?.add(Map<String, dynamic>.from(payload as Map));
      });
    }

    channel.onBroadcast(
      event: 'domino_presence',
      callback: (payload, [ref]) {
        final data = Map<String, dynamic>.from(payload as Map);
        try {
          final type = data['type']?.toString();
          final action = data['action']?.toString();
          final player = data['player'] as Map<String, dynamic>?;
          if (type == 'presence' && action == 'join' && player != null) {
            final existing = _participants.putIfAbsent(channelName, () => []);
            final id = player['id']?.toString() ?? '';
            final name = player['name']?.toString() ?? '';
            if (id.isNotEmpty && name.isNotEmpty) {
              if (!existing.any((e) => e['id'] == id)) {
                existing.add({'id': id, 'name': name});
              }
            }
          }
        } catch (_) {}
        _streams[channelName]?.add(data);
      },
    );

    channel.onBroadcast(
      event: 'domino_participants',
      callback: (payload, [ref]) {
        final data = Map<String, dynamic>.from(payload as Map);
        try {
          final type = data['type']?.toString();
          if (type == 'participants') {
            final list = data['participants'] as List<dynamic>?;
            if (list != null) {
              final existing =
                  _participants.putIfAbsent(channelName, () => [])..clear();
              for (final item in list) {
                if (item is Map<String, dynamic>) {
                  final id = item['id']?.toString() ?? '';
                  final name = item['name']?.toString() ?? '';
                  if (id.isNotEmpty && name.isNotEmpty) {
                    existing.add({'id': id, 'name': name});
                  }
                }
              }
            }
          }
        } catch (_) {}
        _streams[channelName]?.add(data);
      },
    );
  }

  Stream<Map<String, dynamic>> watchRoom(String roomCode) {
    final channelName = _channelName(roomCode);
    return _streams
        .putIfAbsent(
          channelName,
          () => StreamController<Map<String, dynamic>>.broadcast(),
        )
        .stream;
  }

  bool hasChannel(String roomCode) => _channels.containsKey(_channelName(roomCode));

  void sendState(String roomCode, Map<String, dynamic> payload,
      [bool response = false]) {
    final channel = _channels[_channelName(roomCode)];
    if (channel == null) return;
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: response ? 'domino_state_response' : 'domino_state',
      type: RealtimeListenTypes.broadcast,
      payload: payload,
    );
  }

  void sendParticipants(String roomCode, List<Map<String, dynamic>> participants) {
    final channel = _channels[_channelName(roomCode)];
    if (channel == null) return;
    final existing = _participants.putIfAbsent(
      _channelName(roomCode),
      () => [],
    )
      ..clear()
      ..addAll(
        participants.map((e) => {
          'id': e['id']?.toString() ?? '',
          'name': e['name']?.toString() ?? '',
        }),
      );
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'domino_participants',
      type: RealtimeListenTypes.broadcast,
      payload: {'type': 'participants', 'participants': existing},
    );
  }

  void sendGameStart(String roomCode) {
    final channel = _channels[_channelName(roomCode)];
    if (channel == null) return;
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'domino_start',
      type: RealtimeListenTypes.broadcast,
      payload: {'type': 'start'},
    );
  }

  void sendGameEnded(String roomCode) {
    final channel = _channels[_channelName(roomCode)];
    if (channel == null) return;
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'domino_game_ended',
      type: RealtimeListenTypes.broadcast,
      payload: {'type': 'game_ended'},
    );
  }

  void sendPlayerLeft(String roomCode, String playerId, String playerName) {
    final channel = _channels[_channelName(roomCode)];
    if (channel == null) return;
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'domino_player_left',
      type: RealtimeListenTypes.broadcast,
      payload: {'type': 'player_left', 'player': playerName, 'id': playerId},
    );
  }

  void sendPlayerReady(String roomCode, String playerId, bool isReady) {
    final channel = _channels[_channelName(roomCode)];
    if (channel == null) return;
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'domino_player_ready',
      type: RealtimeListenTypes.broadcast,
      payload: {
        'type': 'player_ready',
        'player': playerId,
        'ready': isReady,
      },
    );
  }

  List<Map<String, dynamic>> getParticipants(String roomCode) {
    return _participants.putIfAbsent(_channelName(roomCode), () => []);
  }

  void disposeRoom(String roomCode) {
    final channelName = _channelName(roomCode);
    final channel = _channels.remove(channelName);
    channel?.unsubscribe();
    _streams[channelName]?.close();
    _streams.remove(channelName);
    _participants.remove(channelName);
  }
}