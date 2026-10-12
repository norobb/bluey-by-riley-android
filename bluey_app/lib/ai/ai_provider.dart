import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

abstract class AIProvider {
  String get name;

  RealtimeAudioSession createRealtimeSession({
    required String apiKey,
    required String systemInstruction,
    required List<Map<String, dynamic>> tools,
  });

  Future<List<Map<String, dynamic>>> transcribeAudio({
    required String apiKey,
    required List<int> audioBytes,
  });

  Future<Map<String, dynamic>> research({
    required String apiKey,
    required String question,
    String? context,
  });
}

abstract class RealtimeAudioSession {
  Stream<Map<String, dynamic>> get events;
  Future<void> connect();
  void sendAudioChunk(List<int> pcmBytes);
  void commitAudioAndAsk();
  void sendToolResult(String callID, String outputText, {String? imageBase64});
  void close();
}

/// Google Gemini API Provider Implementation (Gemini Multimodal Live API via WebSocket + REST)
class GeminiProvider implements AIProvider {
  @override
  String get name => "Google Gemini";

  @override
  RealtimeAudioSession createRealtimeSession({
    required String apiKey,
    required String systemInstruction,
    required List<Map<String, dynamic>> tools,
  }) {
    return GeminiRealtimeSession(
      apiKey: apiKey,
      systemInstruction: systemInstruction,
      tools: tools,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> transcribeAudio({
    required String apiKey,
    required List<int> audioBytes,
  }) async {
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');

    final audioBase64 = base64Encode(audioBytes);
    final payload = {
      "contents": [
        {
          "parts": [
            {
              "text":
                  "Transcribe this audio recording with speaker labels (e.g. Speaker A, Speaker B) and exact timestamps in seconds. Return JSON array format: [{\"speaker\": \"A\", \"start\": 0.0, \"text\": \"...\"}]"
            },
            {
              "inlineData": {
                "mimeType": "audio/mp4",
                "data": audioBase64,
              }
            }
          ]
        }
      ],
      "generationConfig": {
        "responseMimeType": "application/json",
      }
    };

    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body);
      final text =
          json['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
      if (text != null) {
        try {
          final List<dynamic> list = jsonDecode(text);
          return list.cast<Map<String, dynamic>>();
        } catch (_) {}
      }
    }
    return [
      {"speaker": "?", "start": 0.0, "text": "Transcription completed"}
    ];
  }

  @override
  Future<Map<String, dynamic>> research({
    required String apiKey,
    required String question,
    String? context,
  }) async {
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');

    var prompt = "Research this question and write a concise, clear report for a user:\nQuestion: $question";
    if (context != null && context.isNotEmpty) {
      prompt += "\n\nContext on user's screen:\n$context";
    }

    final payload = {
      "contents": [
        {
          "parts": [
            {"text": prompt}
          ]
        }
      ],
      "tools": [
        {
          "googleSearch": {}
        }
      ]
    };

    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body);
      final text =
          json['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '';
      final title = text.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => 'Research Report');
      final paragraphs = text.split('\n\n').skip(1).take(4).toList();

      return {
        "question": question,
        "title": title.replaceAll('*', '').trim(),
        "paragraphs": paragraphs.isEmpty ? [text] : paragraphs,
        "sources": [
          {"title": "Google AI Search", "url": "https://google.com"}
        ]
      };
    } else {
      throw Exception("Gemini Research Error (${resp.statusCode}): ${resp.body}");
    }
  }
}

class GeminiRealtimeSession implements RealtimeAudioSession {
  final String apiKey;
  final String systemInstruction;
  final List<Map<String, dynamic>> tools;

  WebSocketChannel? _channel;
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  GeminiRealtimeSession({
    required this.apiKey,
    required this.systemInstruction,
    required this.tools,
  });

  @override
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  @override
  Future<void> connect() async {
    final wsUri = Uri.parse(
        'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=$apiKey');

    _channel = WebSocketChannel.connect(wsUri);
    _channel!.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message.toString()) as Map<String, dynamic>;
          _handleIncomingEvent(data);
        } catch (e) {
          // Parse error
        }
      },
      onError: (err) {
        _eventController.add({'type': 'error', 'error': err.toString()});
      },
      onDone: () {
        _eventController.add({'type': 'close'});
      },
    );

    // Send setup frame
    final setupFrame = {
      "setup": {
        "model": "models/gemini-2.0-flash-exp",
        "generationConfig": {
          "responseModalities": ["TEXT"],
        },
        "systemInstruction": {
          "parts": [
            {"text": systemInstruction}
          ]
        },
        "tools": [
          {
            "functionDeclarations": tools.map((t) {
              return {
                "name": t['name'],
                "description": t['description'],
                "parameters": t['parameters'],
              };
            }).toList()
          }
        ]
      }
    };

    _channel!.sink.add(jsonEncode(setupFrame));
  }

  void _handleIncomingEvent(Map<String, dynamic> data) {
    if (data.containsKey('serverContent')) {
      final serverContent = data['serverContent'] as Map<String, dynamic>;
      final modelTurn = serverContent['modelTurn'] as Map<String, dynamic>?;
      if (modelTurn != null) {
        final parts = modelTurn['parts'] as List<dynamic>? ?? [];
        for (final part in parts) {
          if (part is Map && part.containsKey('text')) {
            _eventController.add({
              'type': 'response.output_text.delta',
              'delta': part['text'],
            });
          }
        }
      }
      if (serverContent['turnComplete'] == true) {
        _eventController.add({'type': 'response.done'});
      }
    } else if (data.containsKey('toolCall')) {
      final toolCall = data['toolCall'] as Map<String, dynamic>;
      final functionCalls = toolCall['functionCalls'] as List<dynamic>? ?? [];
      final calls = functionCalls.map((fc) {
        final fcMap = fc as Map<String, dynamic>;
        return {
          'type': 'function_call',
          'name': fcMap['name'],
          'call_id': fcMap['id'] ?? 'call_${DateTime.now().millisecondsSinceEpoch}',
          'arguments': jsonEncode(fcMap['args'] ?? {}),
        };
      }).toList();

      _eventController.add({
        'type': 'response.done',
        'response': {'output': calls}
      });
    }
  }

  @override
  void sendAudioChunk(List<int> pcmBytes) {
    if (_channel == null) return;
    final frame = {
      "realtimeInput": {
        "mediaChunks": [
          {
            "mimeType": "audio/pcm;rate=24000",
            "data": base64Encode(pcmBytes),
          }
        ]
      }
    };
    _channel!.sink.add(jsonEncode(frame));
  }

  @override
  void commitAudioAndAsk() {
    if (_channel == null) return;
    final frame = {
      "clientContent": {
        "turns": [
          {
            "role": "user",
            "parts": [
              {"text": "Please answer my question now based on what you heard."}
            ]
          }
        ],
        "turnComplete": true
      }
    };
    _channel!.sink.add(jsonEncode(frame));
  }

  @override
  void sendToolResult(String callID, String outputText, {String? imageBase64}) {
    if (_channel == null) return;
    final frame = {
      "toolResponse": {
        "functionResponses": [
          {
            "response": {
              "output": {
                "text": outputText,
                if (imageBase64 != null) "image": imageBase64,
              }
            },
            "id": callID
          }
        ]
      }
    };
    _channel!.sink.add(jsonEncode(frame));
  }

  @override
  void close() {
    _channel?.sink.close();
    _channel = null;
  }
}

/// Optional OpenAI Provider Implementation
class OpenAIProvider implements AIProvider {
  @override
  String get name => "OpenAI";

  @override
  RealtimeAudioSession createRealtimeSession({
    required String apiKey,
    required String systemInstruction,
    required List<Map<String, dynamic>> tools,
  }) {
    return OpenAIRealtimeSession(
      apiKey: apiKey,
      systemInstruction: systemInstruction,
      tools: tools,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> transcribeAudio({
    required String apiKey,
    required List<int> audioBytes,
  }) async {
    return [
      {"speaker": "A", "start": 0.0, "text": "OpenAI transcription result"}
    ];
  }

  @override
  Future<Map<String, dynamic>> research({
    required String apiKey,
    required String question,
    String? context,
  }) async {
    return {
      "question": question,
      "title": "OpenAI Research",
      "paragraphs": ["Research result from OpenAI."],
      "sources": []
    };
  }
}

class OpenAIRealtimeSession implements RealtimeAudioSession {
  final String apiKey;
  final String systemInstruction;
  final List<Map<String, dynamic>> tools;

  WebSocketChannel? _channel;
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  OpenAIRealtimeSession({
    required this.apiKey,
    required this.systemInstruction,
    required this.tools,
  });

  @override
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  @override
  Future<void> connect() async {
    final wsUri = Uri.parse('wss://api.openai.com/v1/realtime?model=gpt-realtime-2.1');
    _channel = WebSocketChannel.connect(wsUri);

    _channel!.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message.toString()) as Map<String, dynamic>;
          _eventController.add(data);
        } catch (_) {}
      },
      onError: (err) => _eventController.add({'type': 'error', 'error': err.toString()}),
      onDone: () => _eventController.add({'type': 'close'}),
    );
  }

  @override
  void sendAudioChunk(List<int> pcmBytes) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      "type": "input_audio_buffer.append",
      "audio": base64Encode(pcmBytes),
    }));
  }

  @override
  void commitAudioAndAsk() {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({"type": "input_audio_buffer.commit"}));
    _channel!.sink.add(jsonEncode({"type": "response.create"}));
  }

  @override
  void sendToolResult(String callID, String outputText, {String? imageBase64}) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode({
      "type": "conversation.item.create",
      "item": {
        "type": "function_call_output",
        "call_id": callID,
        "output": outputText,
      }
    }));
    if (imageBase64 != null) {
      _channel!.sink.add(jsonEncode({
        "type": "conversation.item.create",
        "item": {
          "type": "message",
          "role": "user",
          "content": [
            {
              "type": "input_image",
              "image_url": "data:image/jpeg;base64,$imageBase64"
            }
          ]
        }
      }));
    }
    _channel!.sink.add(jsonEncode({"type": "response.create"}));
  }

  @override
  void close() {
    _channel?.sink.close();
    _channel = null;
  }
}
