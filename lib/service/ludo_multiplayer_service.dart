import 'dart:async';
import 'package:realtime_client/src/types.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ColorSelectionState {
  final String userId;
  final String? pendingColor;
  final String? fixedColor;

  const ColorSelectionState({
    required this.userId,
    this.pendingColor,
    this.fixedColor,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'pendingColor': pendingColor,
        'fixedColor': fixedColor,
      };

  factory ColorSelectionState.fromJson(Map<String, dynamic> json) => ColorSelectionState(
        userId: json['userId']?.toString() ?? '',
        pendingColor: json['pendingColor']?.toString(),
        fixedColor: json['fixedColor']?.toString(),
      );
}

class LudoMultiplayerSession {
  final String roomCode;
  final bool isHost;
  final String playerName;

  const LudoMultiplayerSession({
    required this.roomCode,
    required this.isHost,
    required this.playerName,
  });
}

class LudoMultiplayerService {
  LudoMultiplayerService._internal();

  static final LudoMultiplayerService _instance =
      LudoMultiplayerService._internal();

  factory LudoMultiplayerService() => _instance;

  final SupabaseClient _client = Supabase.instance.client;
  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, StreamController<Map<String, dynamic>>> _streams = {};
  final Map<String, List<Map<String, dynamic>>> _participants = {};
  static const String _globalChannel = 'ludo_global';

  Future<LudoMultiplayerSession> createRoom({
    required String playerName,
    required String playerColor,
  }) async {
    final roomCode = _globalChannel;
    final channel = _client.channel(roomCode);

    _streams[roomCode] = StreamController<Map<String, dynamic>>.broadcast();

    _participants[roomCode] = [
      {'name': playerName, 'color': playerColor},
    ];

    await channel.subscribe();

    _registerChannelListeners(channel, roomCode);

    _channels[roomCode] = channel;

    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'ludo_presence',
      type: RealtimeListenTypes.broadcast,
      payload: {
        'type': 'presence',
        'action': 'join',
        'player': {'name': playerName, 'color': playerColor},
      },
    );

    return LudoMultiplayerSession(
      roomCode: roomCode,
      isHost: true,
      playerName: playerName,
    );
  }

  Future<LudoMultiplayerSession?> joinRoom({
    String roomCode = '',
    required String playerName,
    required String playerColor,
  }) async {
    final channelName = roomCode.isEmpty ? _globalChannel : roomCode;
    final channel = _client.channel(channelName);
    _streams[channelName] = StreamController<Map<String, dynamic>>.broadcast();
    _participants.putIfAbsent(channelName, () => []);
    await channel.subscribe();

    _registerChannelListeners(channel, channelName);

    _channels[channelName] = channel;

    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'ludo_presence',
      type: RealtimeListenTypes.broadcast,
      payload: {
        'type': 'presence',
        'action': 'join',
        'player': {'name': playerName, 'color': playerColor},
      },
    );

    return LudoMultiplayerSession(
      roomCode: channelName,
      isHost: false,
      playerName: playerName,
    );
  }

  void _registerChannelListeners(RealtimeChannel channel, String channelName) {
    channel.onBroadcast(
      event: 'ludo_state',
      callback: (payload, [ref]) {
        final data = Map<String, dynamic>.from(payload as Map);
        _streams[channelName]?.add(data);
      },
    );

    channel.onBroadcast(
      event: 'ludo_state_response',
      callback: (payload, [ref]) {
        final data = Map<String, dynamic>.from(payload as Map);
        _streams[channelName]?.add(data);
      },
    );

    channel.onBroadcast(
      event: 'ludo_presence',
      callback: (payload, [ref]) {
        final data = Map<String, dynamic>.from(payload as Map);
        try {
          final type = data['type']?.toString();
          final action = data['action']?.toString();
          final playerData = data['player'] as Map<String, dynamic>?;
          if (type == 'presence' && action == 'join' && playerData != null) {
            final existing = _participants.putIfAbsent(channelName, () => []);
            final name = playerData['name']?.toString() ?? '';
            final color = playerData['color']?.toString() ?? '';
            if (name.isNotEmpty && color.isNotEmpty) {
              if (!existing.any(
                (e) => e['name'] == name && e['color'] == color,
              )) {
                existing.add({'name': name, 'color': color});
              }
            }
          }
        } catch (_) {}
        _streams[channelName]?.add(data);
      },
    );

    channel.onBroadcast(
      event: 'ludo_participants',
      callback: (payload, [ref]) {
        final data = Map<String, dynamic>.from(payload as Map);
        try {
          final type = data['type']?.toString();
          if (type == 'participants') {
            final participantList = data['participants'] as List<dynamic>?;
            if (participantList != null) {
              final existing = _participants.putIfAbsent(channelName, () => []);
              existing.clear();
              for (final item in participantList) {
                if (item is Map<String, dynamic>) {
                  final name = item['name']?.toString() ?? '';
                  final color = item['color']?.toString() ?? '';
                  if (name.isNotEmpty && color.isNotEmpty) {
                    existing.add({'name': name, 'color': color});
                  }
                }
              }
            }
          }
        } catch (_) {}
        _streams[channelName]?.add(data);
      },
    );

    channel.onBroadcast(
      event: 'ludo_start',
      callback: (payload, [ref]) {
        final data = Map<String, dynamic>.from(payload as Map);
        _streams[channelName]?.add(data);
      },
    );

    channel.onBroadcast(
      event: 'ludo_game_ended',
      callback: (payload, [ref]) {
        final data = Map<String, dynamic>.from(payload as Map);
        _streams[channelName]?.add(data);
      },
    );

    channel.onBroadcast(
      event: 'ludo_player_left',
      callback: (payload, [ref]) {
        final data = Map<String, dynamic>.from(payload as Map);
        _streams[channelName]?.add(data);
      },
    );
  }

  Stream<Map<String, dynamic>> watchRoom(String roomCode) {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    return _streams
        .putIfAbsent(
          name,
          () => StreamController<Map<String, dynamic>>.broadcast(),
        )
        .stream;
  }

  /// Écoute le canal Supabase et redirige vers le flux interne
  Future<void> subscribeToChannel(String roomCode) async {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    final channel = _client.channel(name);

    channel.onBroadcast(
      event: 'ludo_response',
      callback: (payload, [ref]) {
        final data = Map<String, dynamic>.from(payload as Map);
        final controller = _streams.putIfAbsent(
          name,
          () => StreamController<Map<String, dynamic>>.broadcast(),
        );
        controller.add(data);
      },
    );

    channel.subscribe();
  }

  Future<void> sendState(
    String roomCode,
    Map<String, dynamic> payload, [
    bool response = false,
  ]) async {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    final channel = _channels[name];

    //print(payload);

    if (channel == null) return;
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: response ? 'ludo_state_response' : 'ludo_state',
      type: RealtimeListenTypes.broadcast,
      payload: payload,
    );
  }

  void sendJoin(
    String roomCode,
    String playerName,
    String playerColor,
  ) {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    final channel = _channels[name];
    if (channel == null) return;
    final existing = _participants.putIfAbsent(name, () => []);
    if (!existing.any(
      (e) => e['name'] == playerName && e['color'] == playerColor,
    )) {
      existing.add({'name': playerName, 'color': playerColor});
    }
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'ludo_presence',
      type: RealtimeListenTypes.broadcast,
      payload: {
        'type': 'presence',
        'action': 'join',
        'player': {'name': playerName, 'color': playerColor},
      },
    );
  }

  void sendParticipants(
    String roomCode,
    List<Map<String, dynamic>> participants,
  ) {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    final channel = _channels[name];
    if (channel == null) return;
    final existing = _participants.putIfAbsent(name, () => []);
    existing
      ..clear()
      ..addAll(
        participants.map(
          (entry) => {
            'name': entry['name']?.toString() ?? '',
            'color': entry['color']?.toString() ?? '',
            'id': entry['id']?.toString() ?? '',
            'avatar': entry['avatar']?.toString() ?? '',
          },
        ),
      );
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'ludo_participants',
      type: RealtimeListenTypes.broadcast,
      payload: {'type': 'participants', 'participants': existing},
    );
  }

  void sendGameStart(String roomCode) {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    final channel = _channels[name];
    if (channel == null) return;
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'ludo_start',
      type: RealtimeListenTypes.broadcast,
      payload: {'type': 'start'},
    );
  }

  void sendGameEnded(String roomCode) {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    final channel = _channels[name];
    if (channel == null) return;
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'ludo_game_ended',
      type: RealtimeListenTypes.broadcast,
      payload: {'type': 'game_ended'},
    );
  }

  void sendPlayerLeft(String roomCode, String playerName, String color) {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    final channel = _channels[name];
    if (channel == null) return;
    // ignore: invalid_use_of_internal_member
    channel.send(
      event: 'ludo_player_left',
      type: RealtimeListenTypes.broadcast,
      payload: {'type': 'player_left', 'player': playerName, 'color': color},
    );
  }

  List<Map<String, dynamic>> getParticipants(String roomCode) {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    return _participants.putIfAbsent(name, () => []);
  }

  Future<RealtimeChannel> createColorChannel(String teamId) async {
    final channelName = 'ludo_color_$teamId';
    final channel = _client.channel(channelName);
    _streams[channelName] = StreamController<Map<String, dynamic>>.broadcast();
    await channel.subscribe();
    _registerColorListeners(channel, channelName);
    _channels[channelName] = channel;
    return channel;
  }

  Stream<Map<String, dynamic>> watchColorChannel(String teamId) {
    final name = 'ludo_color_$teamId';
    return _streams
        .putIfAbsent(name, () => StreamController<Map<String, dynamic>>.broadcast())
        .stream;
  }

  void _registerColorListeners(RealtimeChannel channel, String channelName) {
    for (final event in [
      'ludo_color_select', 'ludo_color_fix', 'ludo_color_unfix',
      'ludo_color_done', 'ludo_color_start',
      'ludo_bet_enable', 'ludo_bet_amount',
      'ludo_bet_request_agreement', 'ludo_bet_agree', 'ludo_bet_disagree', 'ludo_bet_reset',
      'ludo_color_sync_request', 'ludo_color_sync_state',
    ]) {
      channel.onBroadcast(event: event, callback: (payload, [ref]) {
        final data = Map<String, dynamic>.from(payload as Map);
        _streams[channelName]?.add(data);
      });
    }
  }

  void sendColorStart(String teamId, String userId) {
    _sendColorEvent(teamId, 'ludo_color_start', {'type': 'ludo_color_start', 'userId': userId});
  }

  void sendColorSelect(String teamId, String userId, String color) {
    _sendColorEvent(teamId, 'ludo_color_select', {
      'type': 'ludo_color_select',
      'userId': userId,
      'color': color,
    });
  }

  void sendColorFix(String teamId, String userId, String color) {
    _sendColorEvent(teamId, 'ludo_color_fix', {
      'type': 'ludo_color_fix',
      'userId': userId,
      'color': color,
    });
  }

  void sendColorUnfix(String teamId, String userId) {
    _sendColorEvent(teamId, 'ludo_color_unfix', {
      'type': 'ludo_color_unfix',
      'userId': userId,
    });
  }

  void sendColorDone(String teamId) {
    _sendColorEvent(teamId, 'ludo_color_done', {'type': 'ludo_color_done'});
  }

  void sendColorSyncRequest(String teamId, String userId) {
    _sendColorEvent(teamId, 'ludo_color_sync_request', {
      'type': 'ludo_color_sync_request',
      'userId': userId,
    });
  }

  void sendColorSyncState(String teamId, List<Map<String, dynamic>> states, {bool bettingEnabled = false}) {
    _sendColorEvent(teamId, 'ludo_color_sync_state', {
      'type': 'ludo_color_sync_state',
      'states': states,
      'bettingEnabled': bettingEnabled,
    });
  }

  void _sendColorEvent(String teamId, String event, Map<String, dynamic> payload) {
    final channelName = 'ludo_color_$teamId';
    final channel = _channels[channelName];
    if (channel == null) return;
    // ignore: invalid_use_of_internal_member
    channel.send(event: event, type: RealtimeListenTypes.broadcast, payload: payload);
  }

  void sendBetEnable(String teamId, bool enabled) {
    _sendColorEvent(teamId, 'ludo_bet_enable', {'type': 'ludo_bet_enable', 'enabled': enabled});
  }

  void sendBetAmount(String teamId, String userId, int amount) {
    _sendColorEvent(teamId, 'ludo_bet_amount', {'type': 'ludo_bet_amount', 'userId': userId, 'amount': amount});
  }

  void sendBetRequestAgreement(String teamId) {
    _sendColorEvent(teamId, 'ludo_bet_request_agreement', {'type': 'ludo_bet_request_agreement'});
  }

  void sendBetAgree(String teamId, String userId) {
    _sendColorEvent(teamId, 'ludo_bet_agree', {'type': 'ludo_bet_agree', 'userId': userId});
  }

  void sendBetDisagree(String teamId, String userId) {
    _sendColorEvent(teamId, 'ludo_bet_disagree', {'type': 'ludo_bet_disagree', 'userId': userId});
  }

  void sendBetReset(String teamId) {
    _sendColorEvent(teamId, 'ludo_bet_reset', {'type': 'ludo_bet_reset'});
  }

  void disposeColorChannel(String teamId) {
    final channelName = 'ludo_color_$teamId';
    final channel = _channels.remove(channelName);
    channel?.unsubscribe();
    _streams[channelName]?.close();
    _streams.remove(channelName);
  }

  void disposeRoom(String roomCode) {
    final channel = _channels.remove(roomCode);
    channel?.unsubscribe();
    _streams[roomCode]?.close();
    _streams.remove(roomCode);
  }

}
