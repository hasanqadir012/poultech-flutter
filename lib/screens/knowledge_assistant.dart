import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message_model.dart';
import '../models/chat_session_model.dart';
import '../services/agent_service.dart';
import '../services/database_service.dart';

class KnowledgeAssistantScreen extends StatefulWidget {
  const KnowledgeAssistantScreen({super.key});

  @override
  State<KnowledgeAssistantScreen> createState() => _KnowledgeAssistantScreenState();
}

class _KnowledgeAssistantScreenState extends State<KnowledgeAssistantScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final DatabaseService _db = DatabaseService();
  final AgentService _agentService = AgentService();

  final List<ChatMessageModel> _messages = [];
  bool _loading = false;
  bool _historyLoading = true;
  String? _currentSessionId;

  @override
  void initState() {
    super.initState();
    _loadLatestSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Only restores existing session — never creates an empty one
  Future<void> _loadLatestSession() async {
    debugPrint('[CHAT] Loading latest session...');
    final session = await _db.getLatestChatSession();
    if (!mounted) return;

    setState(() {
      if (session != null && session.messages.isNotEmpty) {
        _currentSessionId = session.id;
        _messages.addAll(session.messages);
        debugPrint('[CHAT] Restored session ${session.id} — ${session.messages.length} messages');
      } else {
        debugPrint('[CHAT] No prior session — will create lazily on first message');
      }
      _historyLoading = false;
    });

    if (_messages.isNotEmpty) _scrollToBottom();
  }

  // Load a specific session from history
  void _loadSession(ChatSessionModel session) {
    setState(() {
      _currentSessionId = session.id;
      _messages
        ..clear()
        ..addAll(session.messages);
    });
    _scrollToBottom();
    debugPrint('[CHAT] Loaded session ${session.id} — ${session.messages.length} messages');
  }

  // Start new conversation — no API call, session created lazily on first message
  void _startNewConversation() {
    if (_messages.isEmpty) return; // already empty
    setState(() {
      _currentSessionId = null;
      _messages.clear();
    });
    debugPrint('[CHAT] New conversation — session will be created on first message');
  }

  Future<void> _askAssistant([String? preset]) async {
    final query = (preset ?? _controller.text).trim();
    if (query.isEmpty) return;

    // Lazy session creation — only on first message
    if (_currentSessionId == null) {
      final sessionId = await _db.createChatSession();
      debugPrint('[CHAT] Created session lazily — id: $sessionId');
      if (!mounted) return;
      setState(() => _currentSessionId = sessionId);
    }

    final userMessage = ChatMessageModel(
      role: ChatRole.user,
      content: query,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _loading = true;
      _controller.clear();
    });
    _scrollToBottom();

    if (_currentSessionId != null) {
      await _db.appendChatMessage(_currentSessionId!, userMessage);
    }

    try {
      // Fetch report history for farm-specific context (silent failure → empty list)
      final reports = await _db.getReports();

      // History = all messages before the user message just added
      final history = _messages.length > 1
          ? _messages.sublist(0, _messages.length - 1)
          : <ChatMessageModel>[];

      debugPrint('[CHAT] Sending to agent — reports: ${reports.length}, '
          'history msgs: ${history.length}');

      final answer = await _agentService.chatWithContext(
        userMessage: query,
        recentReports: reports,
        chatHistory: history,
      );
      final assistantMessage = ChatMessageModel(
        role: ChatRole.assistant,
        content: answer,
        timestamp: DateTime.now(),
      );

      if (mounted) setState(() => _messages.add(assistantMessage));

      if (_currentSessionId != null) {
        await _db.appendChatMessage(_currentSessionId!, assistantMessage);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.add(ChatMessageModel(
              role: ChatRole.assistant,
              content: 'Sorry, something went wrong. Please try again.',
              timestamp: DateTime.now(),
            )));
      }
      debugPrint('[CHAT] LLM error: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openHistory() async {
    final sessions = await _db.getChatSessions();
    if (!mounted) return;

    if (sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No saved conversations yet.'),
          backgroundColor: const Color(0xFF1E293B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => _SessionHistorySheet(
          sessions: sessions,
          currentSessionId: _currentSessionId,
          scrollController: scrollCtrl,
          onSessionSelected: (session) {
            Navigator.pop(ctx);
            _loadSession(session);
          },
          onDeleteSession: (session) async {
            if (session.id != null) {
              await _db.deleteChatSession(session.id!);
            }
            if (mounted) Navigator.pop(ctx);
            if (session.id == _currentSessionId) {
              setState(() {
                _currentSessionId = null;
                _messages.clear();
              });
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const chips = [
      'Optimal incubation temperature?',
      'How to improve fertility rate?',
      'Best practices for egg storage',
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          children: [
            const Text(
              'Knowledge Assistant',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (_messages.isNotEmpty)
              Text(
                '${_messages.length ~/ 2} exchanges',
                style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 11),
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          // History button
          IconButton(
            icon: Icon(Icons.history_rounded, color: Colors.white.withOpacity(0.7)),
            tooltip: 'Past conversations',
            onPressed: _historyLoading ? null : _openHistory,
          ),
          // New conversation button
          if (_messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: _loading ? null : _startNewConversation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'New',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _historyLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6)))
          : Column(
              children: [
                // Quick question chips (only when no messages)
                if (_messages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Questions',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: chips.map((text) {
                            return GestureDetector(
                              onTap: _loading ? null : () => _askAssistant(text),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 9),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.07),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: Colors.white.withOpacity(0.15)),
                                ),
                                child: Text(
                                  text,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                // Messages list
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFA855F7).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.psychology_outlined,
                                  size: 56,
                                  color:
                                      const Color(0xFFA855F7).withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Ask me anything about eggs,\nfertility, and incubation',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 16,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) =>
                              _buildMessageBubble(_messages[index]),
                        ),
                ),

                // Thinking indicator
                if (_loading)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFA855F7),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Thinking...',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Input bar
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.1)),
                            ),
                            child: TextField(
                              controller: _controller,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Type your question...',
                                hintStyle: TextStyle(color: Colors.white54),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                              ),
                              maxLines: null,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _askAssistant(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: _loading ? null : _askAssistant,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF3B82F6).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.send_rounded,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMessageBubble(ChatMessageModel message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.psychology,
                  color: Color(0xFFA855F7), size: 20),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: message.isUser
                    ? const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                      )
                    : LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.1),
                          Colors.white.withOpacity(0.05),
                        ],
                      ),
                borderRadius: BorderRadius.circular(16),
                border: message.isUser
                    ? null
                    : Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: MarkdownBody(
                data: message.content,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(
                      color: Colors.white, fontSize: 15, height: 1.4),
                  strong: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                  listBullet:
                      const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  const Icon(Icons.person, color: Colors.white, size: 20),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Sessions history bottom sheet ─────────────────────────────────────────────

class _SessionHistorySheet extends StatelessWidget {
  final List<ChatSessionModel> sessions;
  final String? currentSessionId;
  final ScrollController scrollController;
  final ValueChanged<ChatSessionModel> onSessionSelected;
  final ValueChanged<ChatSessionModel> onDeleteSession;

  const _SessionHistorySheet({
    required this.sessions,
    required this.currentSessionId,
    required this.scrollController,
    required this.onSessionSelected,
    required this.onDeleteSession,
  });

  String _preview(ChatSessionModel session) {
    final first = session.messages.firstWhere(
      (m) => m.isUser,
      orElse: () => session.messages.first,
    );
    final text = first.content.replaceAll(RegExp(r'\*\*|\*|##\s?|#\s?'), '').trim();
    return text.length > 60 ? '${text.substring(0, 60)}…' : text;
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Handle bar
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 16),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Icon(Icons.history_rounded,
                  color: Color(0xFFA855F7), size: 20),
              const SizedBox(width: 10),
              const Text(
                'Past Conversations',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                '${sessions.length} sessions',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.45), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, index) {
              final session = sessions[index];
              final isActive = session.id == currentSessionId;
              return GestureDetector(
                onTap: () => onSessionSelected(session),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF3B82F6).withOpacity(0.15)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isActive
                          ? const Color(0xFF3B82F6).withOpacity(0.4)
                          : Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF3B82F6).withOpacity(0.2)
                              : Colors.white.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isActive
                              ? Icons.chat_bubble
                              : Icons.chat_bubble_outline,
                          color: isActive
                              ? const Color(0xFF3B82F6)
                              : Colors.white.withOpacity(0.5),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _preview(session),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_formatDate(session.updatedAt)} · '
                              '${session.messages.length} messages',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Active',
                            style: TextStyle(
                                color: Color(0xFF3B82F6),
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: () async {
                            final confirmed = await showDialog<bool>(
                              context: ctx,
                              builder: (dCtx) => AlertDialog(
                                backgroundColor: const Color(0xFF1E293B),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: const Text(
                                  'Delete Conversation?',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                content: Text(
                                  'This will permanently delete "${_preview(session)}".',
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dCtx, false),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(
                                          color: Color(0xFF64748B)),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dCtx, true),
                                    child: const Text(
                                      'Delete',
                                      style: TextStyle(
                                          color: Color(0xFFEF4444)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              onDeleteSession(session);
                            }
                          },
                          child: Icon(Icons.delete_outline,
                              color: Colors.white.withOpacity(0.25), size: 18),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
