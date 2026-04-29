// Locked system prompts for the Cactus-style Gemma 4 router.
//
// Source of truth for the prompt text and JSON schema is
// `docs/planning/IMPLEMENTATION.md §3 (Gemma 4 Usage)`. Do not edit these
// strings without updating that doc — they are part of the hackathon
// submission's "locked prompt" claim and are reviewed against the schema in
// `lib/models/classification.dart` / `lib/models/report.dart`.

import 'package:flutter_gemma/core/message.dart';

import '../models/report.dart';

/// Container for both the system prompts and the user-message templates that
/// feed the two Gemma 4 entry points (E2B classifier, E4B summariser).
///
/// All prompts are intentionally `static const String`s so the analyser can
/// catch drift if anyone tries to mutate them at runtime, and so the exact
/// bytes shipped on-device match what the writeup quotes.
class GemmaPrompts {
  GemmaPrompts._(); // pure namespace, no instances

  /// Mode 1 — Per-report classification, served by Gemma 4 E2B.
  ///
  /// Mirrors IMPLEMENTATION.md §3 verbatim. Output schema is also encoded in
  /// `models/classification.dart` (Classification + ReportCategory + RiskLevel).
  static const String classifySystem = '''
You are a public-safety report classifier. Classify the user's report
AND produce a one-sentence neutral explanation of what likely happened.
Return ONLY valid JSON matching this schema, no prose:

{
  "category": "violence" | "theft" | "harassment" | "suspicious_activity" | "vandalism" | "other",
  "risk_level": "low" | "medium" | "high",
  "time_sensitive": true | false,
  "confidence": 0.0 - 1.0,
  "explanation": "<one neutral sentence, max 25 words, describing what likely happened>"
}

Rules:
- "violence" requires physical harm or weapons.
- "theft" includes pickpocketing and snatching.
- "harassment" includes following, catcalling, intimidation.
- "high" only for active or recent (<1h) physical danger.
- The explanation must be neutral, factual, no alarming words, no advice, no second-person.
''';

  /// Mode 2 — Per-area summary, served by Gemma 4 E4B (cached 5 min/cell).
  static const String summarizeSystem = '''
You are a public-safety briefer. Given recent reports for a small neighborhood,
write ONE sentence (max 20 words) describing the current risk picture in
plain, neutral language.

Rules:
- No alarming words ("dangerous", "scary", "avoid").
- No advice ("be careful", "stay away").
- No second-person ("you").
- Just describe what the reports collectively indicate, with the time context.
- If reports are mixed or sparse, say so honestly.
''';

  /// User-message template for Mode 1 classification calls.
  ///
  /// `occurredAt` is rendered as ISO-8601 to keep the prompt deterministic
  /// across locales — Gemma should not see "Apr 26, 2026, 12:30 PM".
  static String classifyUser({
    required String text,
    required double lat,
    required double lng,
    required DateTime occurredAt,
  }) {
    return 'Report: "$text"\n'
        'Location: ($lat, $lng)\n'
        'Reported at: ${occurredAt.toUtc().toIso8601String()}';
  }

  /// User-message template for Mode 2 summarisation calls.
  ///
  /// `reports` is a list of compact `(category, level, text)` tuples — keeping
  /// this typed (instead of passing full Report objects) makes the prompt-build
  /// path easy to test and avoids leaking unrelated fields like uid/createdAt
  /// into the model context.
  static String summarizeUser({
    required String geohash,
    required int hours,
    required bool night,
    required List<({String category, String level, String text})> reports,
  }) {
    final body = reports.isEmpty
        ? '(no reports)'
        : reports
            .map((r) => '- ${r.category} (${r.level}): "${r.text}"')
            .join('\n');

    return 'Cell: "$geohash"\n'
        'Period: last $hours hours\n'
        'Time of day: ${night ? "night" : "day"}\n'
        'Reports:\n$body';
  }

  /// Convenience: turn the schema enum back into the wire string Gemma is
  /// taught to emit (e.g. `ReportCategory.suspiciousActivity` → `suspicious_activity`).
  /// Used by the parser as a sanity-check during development; not on the hot
  /// path.
  static String wireCategory(ReportCategory c) => switch (c) {
        ReportCategory.violence => 'violence',
        ReportCategory.theft => 'theft',
        ReportCategory.harassment => 'harassment',
        ReportCategory.suspiciousActivity => 'suspicious_activity',
        ReportCategory.vandalism => 'vandalism',
        ReportCategory.other => 'other',
      };

  /// Same as [wireCategory] but for risk levels.
  static String wireRiskLevel(RiskLevel l) => switch (l) {
        RiskLevel.low => 'low',
        RiskLevel.medium => 'medium',
        RiskLevel.high => 'high',
      };

  /// Wraps a user prompt as a `flutter_gemma` user `Message`.
  ///
  /// Centralised so the rest of the codebase never has to import
  /// `flutter_gemma/core/message.dart` directly.
  static Message asUserMessage(String text) =>
      Message.text(text: text, isUser: true);
}
