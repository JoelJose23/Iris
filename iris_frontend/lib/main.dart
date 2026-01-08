import 'package:flutter/material.dart';
import 'dart:ui';

void main() {
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
    this.opacity = 46,
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
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: borderRadius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 56),
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
                isSidebarCollapsed
                    ? Icons.chevron_right
                    : Icons.chevron_left,
              ),
              onPressed: toggleSidebar,
            ),
            if (!isSidebarCollapsed)
              const Expanded(
                child: Text(
                  'Chats',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (!isSidebarCollapsed)
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: addConversation,
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

            return ListTile(
              dense: true,
              tileColor: isSelected
                  ? const Color(0xFF1A1D23)
                  : Colors.transparent,
              leading: const Icon(Icons.chat_bubble_outline, size: 18),
              title: isSidebarCollapsed
                  ? null
                  : Text(
                      conversations[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: !isSidebarCollapsed
                  ? IconButton(
                      icon: const Icon(Icons.delete, size: 16),
                      onPressed: () => deleteConversation(index),
                    )
                  : null,
              onTap: () {
                setState(() {
                  selectedConversation = index;
                });
              },
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
              color: Colors.black.withValues(alpha:46 ),
            ),
          ),

          // ---------- ACTUAL UI ----------
          SafeArea(
            child: Row(
              children: [
                // Sidebar
                AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: isSidebarCollapsed ? 60 : 260,
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
