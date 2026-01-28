import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:window_manager/window_manager.dart';
import 'api.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    titleBarStyle: TitleBarStyle.hidden, // 👈 kills top bar
    windowButtonVisibility: false,       // 👈 no close/min/max
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const IrisApp());
}


class IrisApp extends StatelessWidget {
  const IrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IRIS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent, // 👈 important
        fontFamily: 'Roboto',
      ),
      home: const ChatScreen(),
    );
  }
}

class Glass extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius borderRadius;

  const Glass({
    super.key,
    required this.child,
    this.blur = 20,
    this.opacity = 0.2,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            borderRadius: borderRadius,
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class BubbleGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final double opacity;

  const BubbleGlass({
    super.key,
    required this.child,
    required this.borderRadius,
    this.opacity = 0.18,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            borderRadius: borderRadius,
            border: Border.all(
              color: Colors.white.withOpacity(0.25),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}


class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class ChatMessage {
  String text;
  final bool isUser;
  ChatMessage(this.text, {required this.isUser});
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final Map<String, List<ChatMessage>> conversationMessages = {};
  List<String> conversationOrder = [];

  final List<String> _charQueue = [];
  Timer? _typingTimer;
  bool _isTyping = false;
  bool _isStreaming = false;


  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();

  bool isSidebarCollapsed = false;
  int selectedConversation = 0;

  List<String> get conversations => conversationOrder;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  void sendMessage() {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    final conversationKey = conversations[selectedConversation];

    setState(() {
      // User message
      conversationMessages[conversationKey]!
          .add(ChatMessage(text, isUser: true));

      // Assistant placeholder (empty, will stream into this)
      conversationMessages[conversationKey]!
          .add(ChatMessage("", isUser: false));
    });

    controller.clear();

    final assistantMessage =
        conversationMessages[conversationKey]!.last;

    _isStreaming = true;

    IrisApi.streamMessage(prompt: text,
  conversation: selectedConversation,
  context: "default",
  messages: conversationMessages[conversationKey]!
      .map((m) => {
            "role": m.isUser ? "user" : "assistant",
            "content": m.text,
          })
      .toList(),).listen(
      (chunk) {
        for (int i = 0; i < chunk.length; i++) {
          _charQueue.add(chunk[i]);
        }

        if (!_isTyping) {
          _startTyping(assistantMessage);
        }
      },
      onDone: () {
        _isStreaming = false;
      },
      onError: (e) {
        _isStreaming = false;
        setState(() {
          assistantMessage.text += "\n\n⚠️ Error generating response.";
        });
      },
    );
  }

  void addConversation() {
    final int newIndex = conversationMessages.length; 
    final String newName = 'New Chat ${newIndex + 1}';
    setState(() {
      conversationMessages[newName] = [];
      selectedConversation = newIndex;
    });
  }

  Future<void> _loadConversations() async {
  final result = await IrisApi.fetchConversations();

  if (result.isEmpty) {
    _createInitialConversation();
    return;
  }

  setState(() {
    conversationOrder.clear();
    conversationMessages.clear();

    for (final conv in result) {
      conversationOrder.add(conv.title);
      conversationMessages[conv.title] = [];
    }
  });
  }


  void _startTyping(ChatMessage assistantMessage) {
  _isTyping = true;

  _typingTimer?.cancel();
  _typingTimer = Timer.periodic(
    const Duration(milliseconds:5), // Terminal-fast typing
    (timer) {
      if (_charQueue.isEmpty) {
        if (!_isStreaming) {
          timer.cancel();
          _isTyping = false;
        }
        return;
      }

      setState(() {
        assistantMessage.text += _charQueue.removeAt(0);
      });

      if (scrollController.hasClients) {
        scrollController.jumpTo(
          scrollController.position.maxScrollExtent,
        );
      }
    },
  );
}

  void _createInitialConversation() {
  const title = "Conversation 1";

  setState(() {
    conversationOrder.add(title);
    conversationMessages[title] = [
      ChatMessage(
        "Hi, I’m Iris. What is it going to be today?",
        isUser: false,
      ),
    ];
    selectedConversation = 0;
  });

  IrisApi.createConversation(title);
  }

  void addConvo() {
  final index = conversationOrder.length + 1;
  final title = "Conversation $index";

  setState(() {
    conversationOrder.add(title);
    conversationMessages[title] = [
      ChatMessage(
        "Hi, I’m Iris. What is it going to be today?",
        isUser: false,
      ),
    ];
    selectedConversation = conversationOrder.length - 1;
  });

  IrisApi.createConversation(title);
}


  void deleteConversation(int index) {
    final key = conversations[index];
    setState(() {
      conversationMessages.remove(key);
      if (selectedConversation >= conversations.length) {
        selectedConversation = conversations.length - 1;
      }
    });
  }

  void toggleSidebar() {
    setState(() {
      isSidebarCollapsed = !isSidebarCollapsed;
    });
  }

  Widget buildSidebar() {
  return Column(
    children: [
      // ---------- SIDEBAR HEADER ----------
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                isSidebarCollapsed ? Icons.chevron_right : Icons.chevron_left,
              ),
              onPressed: toggleSidebar,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            if (!isSidebarCollapsed)
              Expanded(
                child: Text(
                  'Chats',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (!isSidebarCollapsed)
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: addConversation,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),

      const Divider(height: 1),

      // ---------- CHAT LIST ----------
      Expanded(
        child: ListView.builder(
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            final isSelected = index == selectedConversation;
            final conversationName = conversations[index];

            return GestureDetector(
              onTap: () {
                setState(() {
                  selectedConversation = index;
                });
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF1A1D23)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, size: 18),
                    if (!isSidebarCollapsed)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            conversationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    if (!isSidebarCollapsed)
                      IconButton(
                        icon: const Icon(Icons.delete, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => deleteConversation(index),
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


  List<ChatMessage> get currentMessages {
  if (conversationMessages.isEmpty) return [];

  final key = conversations[selectedConversation];
  return conversationMessages[key] ?? [];
}

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ---------- BACKGROUND IMAGE ----------
          Positioned.fill(
            child: Image.asset(
              'assets/bg.jpg',
              fit: BoxFit.cover,
            ),
          ),

          // ---------- DARK OVERLAY (READABILITY) ----------
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5),
            ),
          ),

          // ---------- ACTUAL UI ----------
          SafeArea(
            child: Row(
              children: [
                // Sidebar
                AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: isSidebarCollapsed ? 84 : 260,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Glass(
                        borderRadius: BorderRadius.circular(20),
                        child: buildSidebar(),
                      ),
                    ),
                  ),


                // Chat panel
                Expanded(
                  child: Column(
                    children: [
                      const _Header(),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: currentMessages.length,
                          itemBuilder: (context, index) {
                            final message = currentMessages[index];
                            final isLastMessage =
                                index == currentMessages.length - 1;
                            final isTyping = isLastMessage &&
                                !message.isUser &&
                                (_isTyping || _isStreaming);

                            return MessageBubble(
                              message: message,
                              isTyping: isTyping,
                            );
                          },
                        ),
                      ),
                      _InputBar(
                        controller: controller,
                        onSend: sendMessage,
                        locked: _isStreaming,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------- UI COMPONENTS ---------- */

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Glass(
        child: SizedBox(
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Center title
              const Text(
                'IRIS',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),

              // Right-aligned status
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.circle, color: Colors.green, size: 10),
                      SizedBox(width: 6),
                      Text(
                        'Offline',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _InputBar extends StatelessWidget {
  final bool locked;
  final TextEditingController controller;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.locked,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Glass(
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                enabled: !locked,
                controller: controller,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Ask IRIS...',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: locked ? null : onSend,
            ),
          ],
        ),
      ),
    );
  }
}

class BlinkingCursor extends StatefulWidget {
  const BlinkingCursor({super.key});

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      reverseDuration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const Text(
        " ●",
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isTyping;

  const MessageBubble({
    super.key,
    required this.message,
    this.isTyping = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
      bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
    );

    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.7;

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: BubbleGlass(
          borderRadius: radius,
          opacity: isUser ? 0.22 : 0.16,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Colors.white,
                ),
                children: [
                  TextSpan(text: message.text),
                  if (isTyping)
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: BlinkingCursor(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
