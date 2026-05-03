import 'package:flutter/material.dart';

import 'emergency_contact_storage.dart';

class EmergencySettingsScreen extends StatefulWidget {
  const EmergencySettingsScreen({super.key, EmergencyContactStorage? storage})
      : _storage = storage;

  final EmergencyContactStorage? _storage;

  @override
  State<EmergencySettingsScreen> createState() =>
      _EmergencySettingsScreenState();
}

class _EmergencySettingsScreenState extends State<EmergencySettingsScreen> {
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
    final raw = _controller.text.trim();
    if (!_phoneRegex.hasMatch(raw)) {
      setState(() => _error = 'Use international format, e.g. +905551234567');
      return;
    }
    setState(() => _error = null);
    await _storage.write(raw);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved / Kaydedildi')),
    );
  }

  Future<void> _clear() async {
    await _storage.clear();
    if (!mounted) return;
    setState(() {
      _controller.clear();
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cleared / Silindi')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acil durum kişisi / Emergency contact')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Acil durum butonuna basıldığında SMS gönderilecek numara.\n'
                    'Phone that receives an SMS when the emergency button is held.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone (E.164, e.g. +905551234567)',
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
                          label: const Text('Save / Kaydet'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _clear,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Clear / Sil'),
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
