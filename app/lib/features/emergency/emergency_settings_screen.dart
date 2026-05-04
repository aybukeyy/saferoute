import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import 'emergency_contact_storage.dart';

class EmergencySettingsScreen extends ConsumerStatefulWidget {
  const EmergencySettingsScreen({super.key, EmergencyContactStorage? storage})
      : _storage = storage;

  final EmergencyContactStorage? _storage;

  @override
  ConsumerState<EmergencySettingsScreen> createState() =>
      _EmergencySettingsScreenState();
}

class _EmergencySettingsScreenState extends ConsumerState<EmergencySettingsScreen> {
  static final RegExp _phoneRegex = RegExp(r'^\+\d{10,15}$');

  late final EmergencyContactStorage _storage =
      widget._storage ?? EmergencyContactStorage();
  final _controller = TextEditingController();
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await _storage.read();
    if (!mounted) return;
    setState(() {
      _controller.text = v ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final strings = ref.read(stringsProvider);
    final raw = _controller.text.trim();
    if (!_phoneRegex.hasMatch(raw)) {
      setState(() => _error = strings.emergencyContactPhoneError);
      return;
    }
    setState(() => _error = null);
    await _storage.write(raw);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.saved)),
    );
  }

  Future<void> _clear() async {
    final strings = ref.read(stringsProvider);
    await _storage.clear();
    if (!mounted) return;
    setState(() {
      _controller.clear();
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.cleared)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.emergencyContactTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(strings.emergencyContactHint),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: strings.emergencyContactPhoneLabel,
                      border: const OutlineInputBorder(),
                      errorText: _error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save),
                          label: Text(strings.saveAction),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _clear,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(strings.clearAction),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
