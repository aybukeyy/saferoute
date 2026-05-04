import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import 'locale_notifier.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final locale = ref.watch(localeNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(text: strings.settingsLanguage),
          RadioListTile<String>(
            value: 'tr',
            groupValue: locale.languageCode,
            onChanged: (v) {
              if (v != null) {
                ref
                    .read(localeNotifierProvider.notifier)
                    .setLocale(Locale(v));
              }
            },
            title: Text(strings.settingsLanguageTurkish),
            secondary: const Text('🇹🇷', style: TextStyle(fontSize: 22)),
          ),
          RadioListTile<String>(
            value: 'en',
            groupValue: locale.languageCode,
            onChanged: (v) {
              if (v != null) {
                ref
                    .read(localeNotifierProvider.notifier)
                    .setLocale(Locale(v));
              }
            },
            title: Text(strings.settingsLanguageEnglish),
            secondary: const Text('🇬🇧', style: TextStyle(fontSize: 22)),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
