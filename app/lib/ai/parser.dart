// JSON output parser for Gemma 4 E2B classification responses.
//
// Source of truth for the schema this code parses: docs/planning/IMPLEMENTATION.md
// §3 ("Mode 1 — Per-report classification + micro-explanation"). This file is
// intentionally pure Dart — no flutter_gemma imports — so it can be unit
// tested without spinning up an inference engine.

import 'dart:convert';

import '../models/classification.dart';
import '../models/report.dart';

/// Result of a single parse attempt. The service uses this to decide whether
/// to issue a retry call against the model.
sealed class ParseOutcome {
  const ParseOutcome();
}

/// Parser succeeded, [classification] is ready to ship.
class ParseSuccess extends ParseOutcome {
  final Classification classification;
  const ParseSuccess(this.classification);
}

/// Parser failed (no JSON found, malformed JSON, schema mismatch, etc.).
/// [reason] is human-readable, used only for logs.
class ParseFailure extends ParseOutcome {
  final String reason;
  const ParseFailure(this.reason);
}

/// Stateless parser for Gemma 4 E2B classification output.
///
/// Lives in its own class so unit tests don't have to reach for static
/// functions — and so the safe-default policy is in one obvious place.
class GemmaClassificationParser {
  const GemmaClassificationParser();

  /// Hard-coded fallback used when both the first attempt and the retry fail
  /// to produce parseable JSON. Mirrors the IMPLEMENTATION.md contract:
  /// `category=other`, `risk_level=low`, `confidence=0.0`, `needs_review=true`.
  static const Classification safeDefault = Classification(
    category: ReportCategory.other,
    riskLevel: RiskLevel.low,
    timeSensitive: false,
    confidence: 0.0,
    explanation: '',
    needsReview: true,
  );

  /// Single-pass parse of [raw] model output.
  ///
  /// The model may wrap the JSON in a fenced code block, prepend prose, or
  /// trail a stop token — [tryExtractJson] handles those cases. Returns a
  /// [ParseOutcome] so the caller can branch on retry vs. fallback without
  /// catching exceptions.
  ParseOutcome parse(String raw) {
    final extracted = tryExtractJson(raw);
    if (extracted == null) {
      return const ParseFailure('no JSON object found in model output');
    }

    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(extracted);
      if (decoded is! Map<String, dynamic>) {
        return ParseFailure('decoded JSON is ${decoded.runtimeType}, not Map');
      }
      json = decoded;
    } on FormatException catch (e) {
      return ParseFailure('jsonDecode failed: ${e.message}');
    }

    return _fromMap(json);
  }

  /// Convert a decoded JSON map into a [Classification], applying defensive
  /// validation. Anything we cannot map confidently → [ParseFailure].
  ParseOutcome _fromMap(Map<String, dynamic> json) {
    // category
    final categoryRaw = json['category'];
    if (categoryRaw is! String) {
      return const ParseFailure('"category" missing or not a String');
    }
    final category = _categoryFromWire(categoryRaw);
    if (category == null) {
      return ParseFailure('"category" has unknown value "$categoryRaw"');
    }

    // risk_level
    final riskLevelRaw = json['risk_level'];
    if (riskLevelRaw is! String) {
      return const ParseFailure('"risk_level" missing or not a String');
    }
    final riskLevel = _riskLevelFromWire(riskLevelRaw);
    if (riskLevel == null) {
      return ParseFailure('"risk_level" has unknown value "$riskLevelRaw"');
    }

    // time_sensitive
    final timeSensitiveRaw = json['time_sensitive'];
    if (timeSensitiveRaw is! bool) {
      return const ParseFailure('"time_sensitive" missing or not a bool');
    }

    // confidence (clamped to [0, 1])
    final confidenceRaw = json['confidence'];
    if (confidenceRaw is! num) {
      return const ParseFailure('"confidence" missing or not a number');
    }
    final confidence = confidenceRaw.toDouble().clamp(0.0, 1.0);

    // explanation (allow empty string per schema, but require String type)
    final explanationRaw = json['explanation'];
    if (explanationRaw is! String) {
      return const ParseFailure('"explanation" missing or not a String');
    }

    return ParseSuccess(
      Classification(
        category: category,
        riskLevel: riskLevel,
        timeSensitive: timeSensitiveRaw,
        confidence: confidence,
        explanation: explanationRaw.trim(),
      ),
    );
  }

  /// Extract a JSON object string from [raw] model output.
  ///
  /// Handles three observed shapes from `flutter_gemma`:
  ///   1. Fenced markdown: ```json { ... } ```
  ///   2. Prose then object: "Here you go: { ... }"
  ///   3. Pure JSON: "{ ... }"
  ///
  /// Returns `null` if no balanced `{ ... }` can be located. Brace counting is
  /// string-aware (skips braces inside double-quoted strings, respects
  /// backslash escapes) so a `}` inside an explanation does not truncate the
  /// payload.
  static String? tryExtractJson(String raw) {
    if (raw.isEmpty) return null;

    // Strip a fenced code block first if present — common with chat-tuned
    // models that ignore the "no prose" instruction.
    final fence = RegExp(
      r'```(?:json)?\s*(\{[\s\S]*?\})\s*```',
      caseSensitive: false,
    );
    final fenceMatch = fence.firstMatch(raw);
    final source = fenceMatch?.group(1) ?? raw;

    final start = source.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = start; i < source.length; i++) {
      final ch = source[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (ch == r'\') {
        escape = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          return source.substring(start, i + 1);
        }
      }
    }
    return null; // unbalanced
  }

  static ReportCategory? _categoryFromWire(String wire) {
    switch (wire.trim().toLowerCase()) {
      case 'violence':
        return ReportCategory.violence;
      case 'theft':
        return ReportCategory.theft;
      case 'harassment':
        return ReportCategory.harassment;
      case 'suspicious_activity':
        return ReportCategory.suspiciousActivity;
      case 'vandalism':
        return ReportCategory.vandalism;
      case 'other':
        return ReportCategory.other;
      default:
        return null;
    }
  }

  static RiskLevel? _riskLevelFromWire(String wire) {
    switch (wire.trim().toLowerCase()) {
      case 'low':
        return RiskLevel.low;
      case 'medium':
        return RiskLevel.medium;
      case 'high':
        return RiskLevel.high;
      default:
        return null;
    }
  }
}
