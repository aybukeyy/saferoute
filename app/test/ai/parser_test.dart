// Unit tests for the Gemma 4 E2B classification parser.
//
// These cover the three contracts the rest of the AI module relies on:
//   1. Pure JSON ⇒ ParseSuccess with the expected enum values.
//   2. Markdown-fenced JSON ⇒ ParseSuccess (chat-tuned models often ignore
//      the "no prose" instruction and wrap output in ```json … ```).
//   3. Garbage / partial / wrong-typed JSON ⇒ ParseFailure (so the service
//      knows to retry, then fall through to `safeDefault`).

import 'package:app/ai/parser.dart';
import 'package:app/models/report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = GemmaClassificationParser();

  group('GemmaClassificationParser.parse', () {
    test('happy path: pure JSON output is parsed into Classification', () {
      const raw = '''
{
  "category": "harassment",
  "risk_level": "medium",
  "time_sensitive": true,
  "confidence": 0.82,
  "explanation": "Two men reportedly followed a person near the park entrance after dark."
}''';

      final outcome = parser.parse(raw);

      expect(outcome, isA<ParseSuccess>());
      final c = (outcome as ParseSuccess).classification;
      expect(c.category, ReportCategory.harassment);
      expect(c.riskLevel, RiskLevel.medium);
      expect(c.timeSensitive, isTrue);
      expect(c.confidence, closeTo(0.82, 1e-9));
      expect(c.explanation, contains('park entrance'));
      expect(c.needsReview, isFalse);
    });

    test('handles markdown-fenced JSON ("```json ... ```")', () {
      const raw = '''
Sure, here you go:
```json
{
  "category": "suspicious_activity",
  "risk_level": "low",
  "time_sensitive": false,
  "confidence": 0.4,
  "explanation": "Someone loitering near the bus stop."
}
```
Hope that helps!''';

      final outcome = parser.parse(raw);

      expect(outcome, isA<ParseSuccess>());
      final c = (outcome as ParseSuccess).classification;
      expect(c.category, ReportCategory.suspiciousActivity);
      expect(c.riskLevel, RiskLevel.low);
      expect(c.timeSensitive, isFalse);
    });

    test('clamps out-of-range confidence to [0, 1]', () {
      const raw = '''
{ "category": "theft", "risk_level": "high", "time_sensitive": true,
  "confidence": 4.2, "explanation": "Snatched bag." }''';

      final outcome = parser.parse(raw);

      expect(outcome, isA<ParseSuccess>());
      expect((outcome as ParseSuccess).classification.confidence, 1.0);
    });

    test('returns ParseFailure for non-JSON output', () {
      final outcome = parser.parse('I am sorry, I cannot help with that.');
      expect(outcome, isA<ParseFailure>());
    });

    test('returns ParseFailure when "category" is unknown', () {
      const raw = '''
{ "category": "alien_attack", "risk_level": "high", "time_sensitive": true,
  "confidence": 0.9, "explanation": "x" }''';
      expect(parser.parse(raw), isA<ParseFailure>());
    });

    test('returns ParseFailure when a required field is missing', () {
      // missing time_sensitive
      const raw = '''
{ "category": "vandalism", "risk_level": "low",
  "confidence": 0.1, "explanation": "Graffiti on a wall." }''';
      expect(parser.parse(raw), isA<ParseFailure>());
    });

    test('survives a closing brace inside the explanation string', () {
      const raw = '''
{
  "category": "other",
  "risk_level": "low",
  "time_sensitive": false,
  "confidence": 0.2,
  "explanation": "Looks like JSON-ish text: {not actual data}."
}''';
      final outcome = parser.parse(raw);
      expect(outcome, isA<ParseSuccess>());
      expect((outcome as ParseSuccess).classification.explanation,
          contains('{not actual data}'));
    });
  });

  group('GemmaClassificationParser.tryExtractJson', () {
    test('returns null on empty input', () {
      expect(GemmaClassificationParser.tryExtractJson(''), isNull);
    });

    test('returns null on unbalanced braces', () {
      expect(
        GemmaClassificationParser.tryExtractJson('{ "category": "theft" '),
        isNull,
      );
    });
  });

  group('GemmaClassificationParser.safeDefault', () {
    test('matches the contract from IMPLEMENTATION.md §3', () {
      const d = GemmaClassificationParser.safeDefault;
      expect(d.category, ReportCategory.other);
      expect(d.riskLevel, RiskLevel.low);
      expect(d.timeSensitive, isFalse);
      expect(d.confidence, 0.0);
      expect(d.explanation, '');
      expect(d.needsReview, isTrue);
    });
  });
}
