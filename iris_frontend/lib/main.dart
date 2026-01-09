import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:window_manager/window_manager.dart';

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

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final Map<String, List<_Message>> conversationMessages = {
    'Chat with Alice': [],
    'Project IRIS': [],
    'Random Thoughts': [],
  };
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();

  bool isSidebarCollapsed = false;
  int selectedConversation = 0;

  List<String> get conversations => conversationMessages.keys.toList();

  void sendMessage() {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    final conversation = conversations[selectedConversation];

    setState(() {
      conversationMessages[conversation]!.add(_Message(text, true));
      conversationMessages[conversation]!.add(_Message("Thinking…", false));
    });

    controller.clear();

    // auto-scroll
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void addConversation() {
    final int newIndex = conversationMessages.length; 
    final String newName = 'New Chat ${newIndex + 1}';
    setState(() {
      conversationMessages[newName] = [];
      selectedConversation = newIndex;
    });
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


  List<_Message> get currentMessages {
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
                            return MessageBubble(
                              message: currentMessages[index],
                            );
                          },
                        ),
                      ),
                      _InputBar(
                        controller: controller,
                        onSend: sendMessage,
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
  final TextEditingController controller;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.onSend,
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
              onPressed: onSend,
            ),
          ],
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final _Message message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final alignment =
        message.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final color =
        message.isUser ? const Color(0xFF3A6DF0) : const Color(0xFF1A1D23);

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 600),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message.text,
          style: const TextStyle(fontSize: 15),
        ),
      ),
    );
  }
}

/* ---------- DATA MODEL ---------- */

class _Message {
  final String text;
  final bool isUser;

  _Message(this.text, this.isUser);
}
