// AboutScreen — credits + licenses + GitHub link.
// Reached from the MapScreen overflow menu.

import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
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
                  Text('Safe Route',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  const Text('v1.0.0 · explainable safety navigation'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          const ListTile(
            leading: Icon(Icons.psychology),
            title: Text('Built with Gemma 4'),
            subtitle: Text('On-device classification & summarization · Apache 2.0'),
          ),
          const ListTile(
            leading: Icon(Icons.map_outlined),
            title: Text('Maps © OpenStreetMap contributors'),
            subtitle: Text('Tile usage per OSMF policy'),
          ),
          const ListTile(
            leading: Icon(Icons.cloud_sync),
            title: Text('Sync via Firebase'),
            subtitle: Text('Anonymous Auth · Firestore offline persistence'),
          ),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('Source code'),
            subtitle: Text('github.com/your-org/safe-route (placeholder)'),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Submitted to the Kaggle × DeepMind\nGemma 4 Good Hackathon',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
