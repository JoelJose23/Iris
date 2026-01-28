import 'dart:convert';
import 'package:http/http.dart' as http;

// ------------------------------
// Models
// ------------------------------

class ConversationMeta {
  final int id;
  String title; // Now mutable

  ConversationMeta({
    required this.id,
    required this.title,
  });

  factory ConversationMeta.fromJson(Map<String, dynamic> json) {
    return ConversationMeta(
      id: json['id'],
      title: json['title'],
    );
  }
}

class ChatMessage {
  String text;
  final bool isUser;
  ChatMessage(this.text, {required this.isUser});

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      json['content'],
      isUser: json['role'] == 'user',
    );
  }
}


// ------------------------------
// API
// ------------------------------

class IrisApi {
  static const String _baseUrl = 'http://127.0.0.1:8000';

  /// Stream chat response (Ollama)
  static Stream<String> streamMessage({
    required String prompt,
    required int conversation,
    required String context,
    required List<Map<String, String>> messages,
  }) async* {
    final request = http.Request('POST', Uri.parse('$_baseUrl/chat'));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      "prompt": prompt,
      "conversation": conversation,
      "context": context,
      "messages": messages,
    });

    try {
      final response = await request.send();
      if (response.statusCode == 200) {
        final utf8Stream = response.stream.transform(utf8.decoder);
        await for (final chunk in utf8Stream) {
          yield chunk;
        }
      } else {
        throw Exception("Failed to stream message: ${response.statusCode}");
      }
    } catch (e) {
      throw Exception("Failed to connect to the server: $e");
    }
  }

  /// Fetch conversations (sidebar)
  static Future<List<ConversationMeta>> fetchConversations() async {
    final res = await http.get(Uri.parse('$_baseUrl/conversations'));
    if (res.statusCode != 200) {
      throw Exception("Failed to fetch conversations");
    }
    final data = jsonDecode(res.body);
    final List list = data['conversations'];
    return list.map((c) => ConversationMeta.fromJson(c)).toList();
  }

  /// Create new conversation
  static Future<ConversationMeta> createConversation(String title) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/conversation'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"title": title}),
    );
    if (res.statusCode != 201) {
      throw Exception("Failed to create conversation");
    }
    return ConversationMeta.fromJson(jsonDecode(res.body));
  }

  /// Get a single conversation's details, including messages
  static Future<List<ChatMessage>> getConversation(int convId) async {
    final res = await http.get(Uri.parse('$_baseUrl/conversation/$convId'));
    if (res.statusCode != 200) {
      throw Exception("Failed to fetch conversation details");
    }
    final data = jsonDecode(res.body);
    final List messages = data['messages'];
    return messages.map((m) => ChatMessage.fromJson(m)).toList();
  }

  /// Update a conversation's title
  static Future<void> updateConversation(int convId, String newTitle) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/conversation/$convId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"title": newTitle}),
    );
    if (res.statusCode != 200) {
      throw Exception("Failed to update conversation");
    }
  }

  /// Delete a conversation
  static Future<void> deleteConversation(int convId) async {
    final res = await http.delete(Uri.parse('$_baseUrl/conversation/$convId'));
    if (res.statusCode != 204) {
      throw Exception("Failed to delete conversation");
    }
  }
}
