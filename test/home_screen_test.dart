import 'package:flutter_test/flutter_test.dart';
import 'package:miloka/screens/home_screen.dart';

void main() {
  group('parseLudoParticipantsPayload', () {
    test('returns null for a missing or empty payload', () {
      expect(parseLudoParticipantsPayload(null), isNull);
      expect(parseLudoParticipantsPayload({'event': 'ludo_participants'}), isNull);
    });

    test('parses participant payload when available', () {
      final payload = {
        'event': 'ludo_participants',
        'participants': [
          {'name': 'Alice', 'color': 'yellow'},
        ],
      };

      final parsed = parseLudoParticipantsPayload(payload);

      expect(parsed, isNotNull);
      expect(parsed, hasLength(1));
      expect(parsed!.first['name'], 'Alice');
      expect(parsed.first['color'], 'yellow');
    });
  });
}
