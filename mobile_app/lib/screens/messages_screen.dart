import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../models/message.dart';
import '../services/message_service.dart';
import '../state/auth_provider.dart';

/// Direct-messaging chat thread between a patient (or their attendant) and
/// their assigned doctor. Shared by both roles — a patient opens this from
/// Home (title = their doctor's name), a doctor opens it from a patient's
/// detail screen (title = the patient's name). One implementation since
/// the chat UI itself doesn't differ by role; which bubbles render
/// right-aligned is derived purely from `sender_user_id == the signed-in
/// user's own id`, which works identically for either caller. Lives at the
/// top level of screens/ (not under patient/ or doctor/) since it's
/// genuinely shared, not adapted per role. Added 2026-09-07 — see
/// context/decisions-log.md.
///
/// Polling, not websockets: this backend is REST-only with no existing
/// websocket infrastructure (see context/conventions.md) — this screen
/// re-fetches GET /patients/{id}/messages on a timer while it's open and
/// cancels the timer in dispose(), so nothing polls once the screen is
/// left (it's reached by pushing on top of a shell, same as Profile/Quick
/// Check-in, not a persistent IndexedStack tab, specifically so leaving it
/// really disposes the widget and stops the timer). Real-time push
/// (websockets/SSE) is a possible future upgrade, not built this pass.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.patientId, required this.title});

  final int patientId;
  final String title;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  static const _pollInterval = Duration(seconds: 12);

  final _service = MessageService();
  final _scrollController = ScrollController();
  final _composerController = TextEditingController();

  Timer? _pollTimer;
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load(showSpinner: true);
    _pollTimer = Timer.periodic(_pollInterval, (_) => _load(showSpinner: false));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scrollController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  Future<void> _load({required bool showSpinner}) async {
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final messages = await _service.getMessages(widget.patientId);
      if (!mounted) return;
      final wasAtBottom = _isScrolledToBottom();
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      if (wasAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        // A background poll failure stays silent (same convention as
        // PatientDataProvider.refreshTimeline) — only a first-load failure
        // (showSpinner) surfaces an error state, so a dropped poll never
        // clobbers an already-loaded thread.
        if (showSpinner) _loadError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (showSpinner) _loadError = 'Could not load messages right now.';
      });
    }
  }

  bool _isScrolledToBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - 40;
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  Future<void> _send() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      final sent = await _service.sendMessage(widget.patientId, text);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, sent];
        _composerController.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send this message. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownUserId = context.read<AuthProvider>().session?.userId;

    Widget body;
    if (_isLoading && _messages.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_loadError != null && _messages.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => _load(showSpinner: true), child: const Text('Try again')),
            ],
          ),
        ),
      );
    } else if (_messages.isEmpty) {
      body = Center(
        child: Text('No messages yet. Say hello!', style: TextStyle(color: context.rnMuted(0.6))),
      );
    } else {
      body = ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        itemCount: _messages.length,
        itemBuilder: (context, i) => _MessageBubble(
          message: _messages[i],
          isOwn: _messages[i].senderUserId == ownUserId,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: body),
            const Divider(height: 1),
            _Composer(controller: _composerController, sending: _isSending, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isOwn});
  final Message message;
  final bool isOwn;

  @override
  Widget build(BuildContext context) {
    final bg = isOwn ? RnColors.accent : RnColors.accent100;
    final fg = isOwn ? RnColors.surface : RnColors.text;
    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isOwn ? 14 : 2),
            bottomRight: Radius.circular(isOwn ? 2 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isOwn)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  message.senderName ?? _roleLabel(message.senderRole),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.75)),
                ),
              ),
            Text(message.content, style: TextStyle(fontSize: 14.5, color: fg)),
            const SizedBox(height: 3),
            Text(
              DateFormat('MMM d, h:mm a').format(message.createdAt),
              style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.65)),
            ),
          ],
        ),
      ),
    );
  }

  static String _roleLabel(String role) {
    switch (role) {
      case 'doctor':
        return 'Doctor';
      case 'attendant':
        return 'Attendant';
      default:
        return 'Patient';
    }
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.sending, required this.onSend});
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(hintText: 'Type a message…'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
