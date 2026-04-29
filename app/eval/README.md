# Safe Route — Eval Harness

Week-3 (10–11 May) evaluation scripts for the on-device Gemma 4 router. The
**code is committed now**; the **numbers are produced later**, on a real
Pixel-7-class device once Gemma weights are in place.

This directory holds:

```
eval/
├── data/
│   ├── mode1_dataset.json      # 30 labeled reports (TR + EN)
│   └── mode2_cases.json        # 10 labeled cell summaries
├── src/                        # named `src/` (not `lib/`) so the analyzer
│   ├── dataset.dart            #   doesn't trip on package-lib import rules
│   ├── harness.dart
│   ├── rubric.dart
│   ├── mode1_runner.dart
│   └── mode2_runner.dart
├── bin/
│   └── run_eval.dart           # standalone host stub for syntax / smoke
└── output/                     # CSV results written here (gitignored)
```

The integration tests live under `app/integration_test/` and import the
runners above, so the same harness powers both the device runs and the
host-side stub run.

---

## 1. Prerequisites

1. Gemma weights downloaded into `app/assets/`:
   - `gemma-4-e2b.task` (~1 GB)
   - `gemma-4-e4b.task` (~2 GB)
   See `docs/planning/MANUAL_SETUP.md §2`.
2. A connected Android device or emulator with **≥ 8 GB RAM**.
   - Recommended: Pixel 7 (API 34) or equivalent.
   - Run `flutter devices` to get the device id.
3. The `integration_test` package is **not yet** in `pubspec.yaml` (the eval
   agent is forbidden from touching dependencies). Add it before the first
   run:
   ```bash
   cd app
   flutter pub add --dev integration_test
   ```
   See `docs/planning/MANUAL_SETUP.md §8` (Eval).
4. `path_provider` is already a dependency of the app.

---

## 2. Run the integration tests on a device

From `app/`:

```bash
# Mode 1 — accuracy + rubric, 30 calls
flutter test integration_test/mode1_accuracy_test.dart -d <device-id>

# Mode 2 — area-summary rubric, 10 calls
flutter test integration_test/mode2_summary_test.dart -d <device-id>

# Latency bench — 100 E2B calls + 30 E4B calls + hot-swap cycles
flutter test integration_test/latency_bench_test.dart -d <device-id>

# Memory profile — RSS sampling around 100 E2B calls
flutter test integration_test/memory_profile_test.dart -d <device-id>
```

CSVs are written to the device's app-documents directory (returned by
`path_provider`). Pull them with `adb`:

```bash
# Find the documents dir under the package
adb shell run-as com.example.app ls files/
adb exec-out run-as com.example.app cat files/mode1_results_<stamp>.csv \
  > eval/output/mode1_results_<stamp>.csv
```

Replace `com.example.app` with the actual application id from
`android/app/build.gradle`.

If `run-as` doesn't work (release build / non-debuggable APK), use a debug
build and rerun.

---

## 3. Smoke-test the harness on the host (no device, no weights)

The standalone runner uses a stub classifier (always returns the parser's
safeDefault). Useful to confirm the JSON loaders and CSV writers are intact:

```bash
cd app
dart run eval/bin/run_eval.dart           # both modes
dart run eval/bin/run_eval.dart mode1     # only mode 1
dart run eval/bin/run_eval.dart mode2     # only mode 2
```

CSVs land in `app/eval/output/`. Accuracy will be near-zero (stub model);
that's expected — this run only validates the wiring.

---

## 4. Pass / fail thresholds

Thresholds are read from the dataset JSON, not hard-coded in the test files,
so re-baselining means editing one file:

| Test | Threshold | Source |
|---|---|---|
| Mode 1 category accuracy | ≥ 85% | `mode1_dataset.json :: targetAccuracy` |
| Mode 1 risk-level accuracy | ≥ 85% | `mode1_dataset.json :: targetAccuracy` |
| Mode 1 explanation rubric | ≥ 90% | `mode1_dataset.json :: targetRubric` |
| Mode 1 median latency | < 5000 ms | `mode1_dataset.json :: targetLatencyMs` |
| Mode 2 summary rubric | ≥ 90% | `mode2_cases.json :: targetRubric` |
| Mode 2 latency | logged only | (not asserted; cached in production) |

Source: `docs/planning/PLAN.md §6 (Success Criteria)`.

---

## 5. CSV output schemas

### `mode1_results_<stamp>.csv`
`id, lang, expected_category, actual_category, category_match,
expected_risk_level, actual_risk_level, risk_level_match, both_match,
expected_time_sensitive, actual_time_sensitive, confidence, needs_review,
rubric_pass, rubric_failures, explanation_word_count, explanation, latency_ms`

### `mode2_results_<stamp>.csv`
`id, geohash7, hours, night, report_count, rubric_pass, rubric_failures,
summary_word_count, summary, latency_ms`

### `latency_<stamp>.csv`
`phase, iteration, latency_ms` — `phase` is one of `cold_start_e2b`,
`per_call_e2b`, `cold_start_e4b_with_swap`, `per_call_e4b`,
`hotswap_classify`, `hotswap_summarize`, `hotswap_classify_back`,
`hotswap_swap_e2b_to_e4b`, `hotswap_swap_e4b_to_e2b`.

### `memory_<stamp>.csv`
`phase, call_index, rss_mb` — `phase` is `pre_warmup`, `post_warmup`,
`classify`, `post_run`. **Note**: `ProcessInfo.currentRss` may be 0 on some
platforms (logged as a warning); see test file header.

Aggregating into a single dashboard / Markdown table is left as a placeholder
(`tools/eval_report.py` — not implemented in this scaffold).

---

## 6. Battery profiling (Android Battery Historian)

Battery measurement is a native concern (kernel + framework counters). The
Dart side cannot read it directly. Procedure:

```bash
# 1. Reset battery stats on the device (must be unplugged from USB power
#    for accurate accounting; use a wireless ADB or a charge-only cable).
adb shell dumpsys batterystats --reset

# 2. Run the eval (any of the integration tests above will do; latency is
#    most representative because it's the longest sustained workload).
flutter test integration_test/latency_bench_test.dart -d <device-id>

# 3. Capture a bug report with embedded batterystats.
adb bugreport bugreport.zip

# 4. Upload bugreport.zip to https://bathist.ef.lc/  (Battery Historian).
#    Look at the "AppStats" tab for the Safe Route package id.
```

Record the `mAh` consumed during the test run and the `% battery` delta
straight into `WRITEUP.md §6`.

---

## 7. WRITEUP.md §6 paste-ready output

Each integration test logs a `-- WRITEUP §6 row --` block to stdout that maps
directly to the `Per-call latency` / `Memory footprint` / `Classification
accuracy` / `Battery impact` columns of the table in
`docs/planning/WRITEUP.md`. Look for lines prefixed `[mode1_eval]`,
`[mode2_eval]`, `[latency_bench]`, `[memory_profile]` in the test output and
copy the `| ... |` line that follows.

---

## 8. Known limitations

- **`integration_test` package is optional.** Until the user runs
  `flutter pub add --dev integration_test`, `flutter analyze
  integration_test/` will report unresolved imports for `package:integration_test/...`.
  The `eval/src/` and `eval/bin/` code analyses cleanly without it.
- **No CI.** All eval is local-device. The host stub run is intentionally a
  smoke test, not a substitute.
- **Dataset is small** (30 + 10) — that is by design: the hackathon judges
  read 1500 words and watch a 3-minute video, not a leaderboard. The dataset
  is balanced and curated, not statistically powerful.
- **Rubric is rule-based**, not LLM-judge — keeps the eval reproducible and
  free of additional model cost. Watch for false positives in non-English
  languages once we expand beyond TR/EN.
