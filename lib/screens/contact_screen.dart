import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../services/contact_service.dart';

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final _nameCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final s = context.read<LocaleProvider>().s;
    final message = _messageCtrl.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.contactEmpty)));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ContactService().submitMessage(
        name: _nameCtrl.text,
        message: message,
        userId: context.read<AuthProvider>().uid,
      );
      _messageCtrl.clear();
      messenger.showSnackBar(SnackBar(content: Text(s.contactSent)));
    } catch (e) {
      debugPrint('[CONTACT] send error: $e');
      messenger.showSnackBar(SnackBar(content: Text(s.contactFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      appBar: AppBar(title: Text(s.titleContact)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: s.contactNameLabel),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _messageCtrl,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: s.contactMessageLabel,
                hintText: s.contactMessageHint,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _send,
              icon: const Icon(Icons.send, size: 18),
              label: Text(s.contactSend, style: AppText.bodyStrong),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
