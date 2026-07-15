import 'dart:async';
import 'dart:math' as math;

import 'package:realtime_client/src/types.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  static final LudoMultiplayerService _instance = LudoMultiplayerService._internal();

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

    channel.onBroadcast(
      event: 'ludo_state',
      callback: (payload, [ref]) {
        final data = payload is Map<String, dynamic>
            ? payload
            : Map<String, dynamic>.from(payload as Map);
        _streams[roomCode]?.add(data);
      },
    );

    channel.onBroadcast(
      event: 'ludo_presence',
      callback: (payload, [ref]) {
        final data = payload is Map<String, dynamic>
            ? payload
            : Map<String, dynamic>.from(payload as Map);
        try {
          final type = data['type']?.toString();
          final action = data['action']?.toString();
          final playerData = data['player'] as Map<String, dynamic>?;
          if (type == 'presence' && action == 'join' && playerData != null) {
            final existing = _participants.putIfAbsent(roomCode, () => []);
            final name = playerData['name']?.toString() ?? '';
            final color = playerData['color']?.toString() ?? '';
            if (name.isNotEmpty && color.isNotEmpty) {
              if (!existing.any((e) => e['name'] == name && e['color'] == color)) {
                existing.add({'name': name, 'color': color});
              }
            }
          }
        } catch (_) {}
        _streams[roomCode]?.add(data);
      },
    );

    channel.onBroadcast(
      event: 'ludo_participants',
      callback: (payload, [ref]) {
        final data = payload is Map<String, dynamic>
            ? payload
            : Map<String, dynamic>.from(payload as Map);
        try {
          final type = data['type']?.toString();
          if (type == 'participants') {
            final participantList = data['participants'] as List<dynamic>?;
            if (participantList != null) {
              final existing = _participants.putIfAbsent(roomCode, () => []);
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
        _streams[roomCode]?.add(data);
      },
    );

    channel.onBroadcast(
      event: 'ludo_start',
      callback: (payload, [ref]) {
        final data = payload is Map<String, dynamic>
            ? payload
            : Map<String, dynamic>.from(payload as Map);
        _streams[roomCode]?.add(data);
      },
    );

    _channels[roomCode] = channel;

    await channel.send(
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
    channel.onBroadcast(
      event: 'ludo_state',
      callback: (payload, [ref]) {
        final data = payload is Map<String, dynamic>
            ? payload
            : Map<String, dynamic>.from(payload as Map);
        _streams[channelName]?.add(data);
      },
    );
    channel.onBroadcast(
      event: 'ludo_presence',
      callback: (payload, [ref]) {
        final data = payload is Map<String, dynamic>
            ? payload
            : Map<String, dynamic>.from(payload as Map);
        try {
          final type = data['type']?.toString();
          final action = data['action']?.toString();
          final playerData = data['player'] as Map<String, dynamic>?;
          if (type == 'presence' && action == 'join' && playerData != null) {
            final existing = _participants.putIfAbsent(channelName, () => []);
            final name = playerData['name']?.toString() ?? '';
            final color = playerData['color']?.toString() ?? '';
            if (name.isNotEmpty && color.isNotEmpty) {
              if (!existing.any((e) => e['name'] == name && e['color'] == color)) {
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
        final data = payload is Map<String, dynamic>
            ? payload
            : Map<String, dynamic>.from(payload as Map);
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
        final data = payload is Map<String, dynamic>
            ? payload
            : Map<String, dynamic>.from(payload as Map);
        _streams[channelName]?.add(data);
      },
    );

    _channels[channelName] = channel;

    await channel.send(
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

  Stream<Map<String, dynamic>> watchRoom(String roomCode) {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    return _streams.putIfAbsent(name, () => StreamController<Map<String, dynamic>>.broadcast()).stream;
  }

  Future<void> sendState(String roomCode, Map<String, dynamic> payload) async {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    final channel = _channels[name];

    if (channel == null) return;
    await channel.send(
      event: 'ludo_state',
      type: RealtimeListenTypes.broadcast,
      payload: payload,
    );
  }

  Future<void> sendJoin(
    String roomCode,
    String playerName,
    String playerColor,
  ) async {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    final channel = _channels[name];
    if (channel == null) return;
    final existing = _participants.putIfAbsent(name, () => []);
    if (!existing.any((e) => e['name'] == playerName && e['color'] == playerColor)) {
      existing.add({'name': playerName, 'color': playerColor});
    }
    await channel.send(
      event: 'ludo_presence',
      type: RealtimeListenTypes.broadcast,
      payload: {
        'type': 'presence',
        'action': 'join',
        'player': {'name': playerName, 'color': playerColor},
      },
    );
  }

  Future<void> sendParticipants(
    String roomCode,
    List<Map<String, dynamic>> participants,
  ) async {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    final channel = _channels[name];
    if (channel == null) return;
    final existing = _participants.putIfAbsent(name, () => []);
    existing
      ..clear()
      ..addAll(participants.map((entry) => {
            'name': entry['name']?.toString() ?? '',
            'color': entry['color']?.toString() ?? '',
            'id': entry['id']?.toString() ?? '',
            'avatar': entry['avatar']?.toString() ?? '',
          }));
    await channel.send(
      event: 'ludo_participants',
      type: RealtimeListenTypes.broadcast,
      payload: {
        'type': 'participants',
        'participants': existing,
      },
    );
  }

  Future<void> sendGameStart(String roomCode) async {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    final channel = _channels[name];
    if (channel == null) return;
    await channel.send(
      event: 'ludo_start',
      type: RealtimeListenTypes.broadcast,
      payload: {
        'type': 'start',
      },
    );
  }

  List<Map<String, dynamic>> getParticipants(String roomCode) {
    final name = roomCode.isEmpty ? _globalChannel : roomCode;
    return _participants.putIfAbsent(name, () => []);
  }

  void disposeRoom(String roomCode) {
    final channel = _channels.remove(roomCode);
    channel?.unsubscribe();
    _streams[roomCode]?.close();
    _streams.remove(roomCode);
  }

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = math.Random();
    return List.generate(5, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
