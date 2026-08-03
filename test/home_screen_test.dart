import 'package:flutter_test/flutter_test.dart';
import 'package:miloka/screens/home_screen.dart';

void main() {
  group('parseLudoParticipantsPayload', () {
    test('returns null for a missing or empty payload', () {
      expect(parseLudoParticipantsPayload(null), isNull);
      expect(parseLudoParticipantsPayload(<String, dynamic>{}), isNull);
      expect(
        parseLudoParticipantsPayload({'event': 'other_event'}),
        isNull,
      );
      expect(
        parseLudoParticipantsPayload({'event': 'ludo_participants'}),
        isNull,
      );
    });

    test('parses participant payload when available', () {
      final payload = <String, dynamic>{
        'event': 'ludo_participants',
        'participants': [
          {'name': 'Alice', 'color': 'yellow'},
        ],
      };

      final parsed = parseLudoParticipantsPayload(payload);

      expect(parsed, isNotNull);
      expect(parsed, hasLength(1));
      expect(parsed![0]['name'], 'Alice');
      expect(parsed[0]['color'], 'yellow');
    });

    test('parses multiple participants', () {
      final payload = <String, dynamic>{
        'event': 'ludo_participants',
        'participants': [
          {'name': 'Alice', 'color': 'yellow'},
          {'name': 'Bob', 'color': 'blue'},
          {'name': 'Charlie', 'color': 'green'},
        ],
      };

      final parsed = parseLudoParticipantsPayload(payload);

      expect(parsed, hasLength(3));
      expect(parsed![1]['name'], 'Bob');
      expect(parsed[2]['color'], 'green');
    });
  });
}