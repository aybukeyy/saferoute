// AboutScreen — credits + licenses + GitHub link.
// Reached from the MapScreen overflow menu.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Icon(Icons.shield,
                  size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strings.appTitle,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(strings.aboutVersionTagline),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.psychology),
            title: Text(strings.aboutGemmaTitle),
            subtitle: Text(strings.aboutGemmaSubtitle),
          ),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: Text(strings.aboutOSMTitle),
            subtitle: Text(strings.aboutOSMSubtitle),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync),
            title: Text(strings.aboutFirebaseTitle),
            subtitle: Text(strings.aboutFirebaseSubtitle),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(strings.aboutSourceTitle),
            subtitle: const Text('github.com/aybukeyy/saferoute'),
          ),
        ],
      ),
    );
  }
}
