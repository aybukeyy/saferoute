// Pure-Dart rubric checks shared by Mode 1 and Mode 2 evals.
//
// These mirror the locked prompt rules in IMPLEMENTATION.md §3 and PLAN.md §6.
// No flutter_gemma / Flutter imports — safe to call from any isolate, from
// `flutter test`, and from a standalone Dart entry point.

/// Outcome of a single rubric check. `details` is human-readable, used for CSV
/// output and console logs.
class RubricResult {
  final bool pass;
  final List<String> failures;
  final int wordCount;

  const RubricResult({
    required this.pass,
    required this.failures,
    required this.wordCount,
  });

  Map<String, dynamic> toJson() => {
        'pass': pass,
        'failures': failures,
        'wordCount': wordCount,
      };
}

/// Mirror of `Mode 1` explanation rubric: ≤25 words, neutral, no advice, no
/// second-person. Both English and Turkish trigger words covered.
RubricResult checkMode1Explanation(String text) {
  return _checkRubric(
    text: text,
    maxWords: 25,
    requireSingleSentence: false,
  );
}

/// Mirror of `Mode 2` summary rubric: ≤20 words, ONE sentence, neutral, no
/// advice, no second-person.
RubricResult checkMode2Summary(String text) {
  return _checkRubric(
    text: text,
    maxWords: 20,
    requireSingleSentence: true,
  );
}

/// Internal: shared rubric body. The caller decides whether single-sentence
/// is enforced and the word ceiling.
RubricResult _checkRubric({
  required String text,
  required int maxWords,
  required bool requireSingleSentence,
}) {
  final failures = <String>[];
  final trimmed = text.trim();

  if (trimmed.isEmpty) {
    return const RubricResult(
      pass: false,
      failures: ['empty output'],
      wordCount: 0,
    );
  }

  // Word count — split on any whitespace, drop empties.
  final words =
      trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final wordCount = words.length;
  if (wordCount > maxWords) {
    failures.add('wordCount=$wordCount > $maxWords');
  }

  // Single sentence — terminal punctuation count.
  if (requireSingleSentence) {
    // Strip a trailing terminal mark before counting so "Ok." → 1.
    final body = trimmed.endsWith('.') ||
            trimmed.endsWith('!') ||
            trimmed.endsWith('?')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final terminals =
        RegExp(r'[.!?]').allMatches(body).length; // any internal terminals
    if (terminals > 0) {
      failures.add('multipleSentences (interior terminals=$terminals)');
    }
  }

  final lower = trimmed.toLowerCase();

  // Second-person pronouns. Turkish forms are checked as whole words to avoid
  // false positives on substrings (e.g. "sensör"). English ones are
  // substring-safe because of word boundaries baked into the regex.
  for (final pronoun in _secondPersonPatterns) {
    if (pronoun.hasMatch(lower)) {
      failures.add('secondPerson(${pronoun.pattern})');
      break; // one is enough — don't spam
    }
  }

  // Alarming words / advice phrasing.
  for (final word in _alarmingWords) {
    if (lower.contains(word)) {
      failures.add('alarming("$word")');
    }
  }
  for (final phrase in _adviceMarkers) {
    if (lower.contains(phrase)) {
      failures.add('advice("$phrase")');
    }
  }

  return RubricResult(
    pass: failures.isEmpty,
    failures: failures,
    wordCount: wordCount,
  );
}

// Shared dictionaries — kept as `final` (not `const`) because `RegExp` is not
// const-constructible.
final List<RegExp> _secondPersonPatterns = [
  RegExp(r'\byou\b'),
  RegExp(r'\byour\b'),
  RegExp(r'\byours\b'),
  RegExp(r'\byourself\b'),
  RegExp(r'\bsen\b'),
  RegExp(r'\bseni\b'),
  RegExp(r'\bsana\b'),
  RegExp(r'\bsenin\b'),
  RegExp(r'\bsiz\b'),
  RegExp(r'\bsizi\b'),
  RegExp(r'\bsize\b'),
  RegExp(r'\bsizin\b'),
];

final List<String> _alarmingWords = [
  'dangerous',
  'danger',
  'scary',
  'avoid',
  'beware',
  'threat',
  'threatening',
  'horrifying',
  // Turkish
  'tehlikeli',
  'tehlike',
  'korkunç',
  'kaçın',
  'kaçının',
  'sakın',
  'dikkat',
];

final List<String> _adviceMarkers = [
  'be careful',
  'stay away',
  'do not go',
  "don't go",
  'recommend',
  'suggest',
  'should not',
  'must not',
  'dikkat et',
  'kaçınmalı',
  'önerilir',
  'tavsiye',
];
