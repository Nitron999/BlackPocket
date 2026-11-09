import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

List<CameraDescription> _availableCameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _availableCameras = await availableCameras();
  } catch (e) {
    debugPrint("Ошибка инициализации камеры: $e");
  }
  runApp(const BlackPocketApp());
}

class BlackPocketApp extends StatelessWidget {
  const BlackPocketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlackPocket Live',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
          surface: const Color(0xFF141414),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      ),
      home: const LiveAssistantScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final String? imageBase64;

  ChatMessage({required this.text, required this.isUser, this.imageBase64});

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'imageBase64': imageBase64,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'] ?? '',
        isUser: json['isUser'] ?? false,
        imageBase64: json['imageBase64'],
      );
}

class ChatSession {
  final String id;
  String title;
  List<ChatMessage> messages;

  ChatSession({required this.id, required this.title, required this.messages});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: json['title'] ?? 'Новый диалог',
        messages: (json['messages'] as List<dynamic>? ?? [])
            .map((m) => ChatMessage.fromJson(m))
            .toList(),
      );
}

class LiveAssistantScreen extends StatefulWidget {
  const LiveAssistantScreen({super.key});

  @override
  State<LiveAssistantScreen> createState() => _LiveAssistantScreenState();
}

class _LiveAssistantScreenState extends State<LiveAssistantScreen> {
  CameraController? _cameraController;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();

  List<ChatSession> _sessions = [];
  String _currentSessionId = "";

  bool _isCameraActive = true;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isLoading = false;
  bool _liveContinuousMode = false;
  double _speechRate = 0.45;

  String _apiUrl = "https://openrouter.ai/api/v1/chat/completions";
  String _apiKey = "";
  String _modelName = "openrouter/free";
  String _systemPrompt =
      "Ты — BlackPocket, личный живой партнер и собеседник. "
      "ПРАВИЛО №1: ВСЕГДА отвечай СТРОГО на русском языке! Ни слова на английском! "
      "Ты видишь то, что показывает пользователь через камеру в реальном времени. "
      "Отвечай кратко, ёмко, живо и по существу, как опытный знающий напарник. "
      "Не трать время на пустые приветствия — сразу комментируй суть увиденного или вопрос.";

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initTts();
    _initSpeechRecognizer();
    _loadAll();
  }

  Future<void> _initCamera() async {
    if (_availableCameras.isNotEmpty) {
      _cameraController = CameraController(
        _availableCameras[0],
        ResolutionPreset.medium,
        enableAudio: false,
      );
      try {
        await _cameraController!.initialize();
        if (mounted) setState(() {});
      } catch (e) {
        debugPrint("Ошибка камеры: $e");
      }
    }
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("ru-RU");
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(_speechRate);

    _tts.setCompletionHandler(() {
      if (mounted) {
        setState(() => _isSpeaking = false);
        if (_liveContinuousMode && !_isLoading) {
          _startSpeechListening();
        }
      }
    });

    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  Future<void> _initSpeechRecognizer() async {
    await _speech.initialize(
      onError: (val) => debugPrint("Ошибка STT: $val"),
      onStatus: (status) {
        if (status == 'notListening' && _isListening) {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
  }

  ChatSession get _currentSession {
    if (_sessions.isEmpty) {
      final s = ChatSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: "Живой диалог",
        messages: [],
      );
      _sessions.add(s);
      _currentSessionId = s.id;
      return s;
    }
    return _sessions.firstWhere(
      (s) => s.id == _currentSessionId,
      orElse: () => _sessions.first,
    );
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiUrl = prefs.getString('apiUrl') ?? _apiUrl;
      _apiKey = prefs.getString('apiKey') ?? _apiKey;
      _modelName = prefs.getString('modelName') ?? _modelName;
      _systemPrompt = prefs.getString('systemPrompt') ?? _systemPrompt;
      _speechRate = prefs.getDouble('speechRate') ?? 0.45;

      final historyJson = prefs.getString('bp_sessions_live');
      if (historyJson != null && historyJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(historyJson);
        _sessions = decoded.map((e) => ChatSession.fromJson(e)).toList();
      }

      if (_sessions.isEmpty) {
        final firstSession = ChatSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: "Живой диалог",
          messages: [],
        );
        _sessions.add(firstSession);
        _currentSessionId = firstSession.id;
      } else {
        _currentSessionId = prefs.getString('active_session_id') ?? _sessions.first.id;
      }
    });
    await _tts.setSpeechRate(_speechRate);
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_sessions.map((e) => e.toJson()).toList());
    await prefs.setString('bp_sessions_live', encoded);
    await prefs.setString('active_session_id', _currentSessionId);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('apiUrl', _apiUrl);
    await prefs.setString('apiKey', _apiKey);
    await prefs.setString('modelName', _modelName);
    await prefs.setString('systemPrompt', _systemPrompt);
    await prefs.setDouble('speechRate', _speechRate);
    await _tts.setSpeechRate(_speechRate);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _speakText(String text) async {
    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
      return;
    }
    final cleanText = text.replaceAll(RegExp(r'[\*\_#`>]'), '');
    setState(() => _isSpeaking = true);
    await _tts.setSpeechRate(_speechRate);
    await _tts.speak(cleanText);
  }

  void _startSpeechListening() async {
    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
    }

    bool available = await _speech.initialize();
    if (available && mounted) {
      setState(() => _isListening = true);
      _speech.listen(
        localeId: "ru_RU",
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 30),
        onResult: (val) {
          _textController.text = val.recognizedWords;
          if (val.finalResult && val.recognizedWords.trim().isNotEmpty) {
            _processLiveInput(val.recognizedWords.trim());
          }
        },
      );
    }
  }

  void _stopSpeechListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  void _toggleContinuousLive() {
    setState(() {
      _liveContinuousMode = !_liveContinuousMode;
    });
    if (_liveContinuousMode) {
      _startSpeechListening();
    } else {
      _stopSpeechListening();
      _tts.stop();
    }
  }

  Future<void> _processLiveInput(String userText) async {
    if (_isLoading) return;
    _stopSpeechListening();

    String? capturedBase64;
    if (_isCameraActive && _cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final XFile file = await _cameraController!.takePicture();
        final bytes = await file.readAsBytes();
        capturedBase64 = base64Encode(bytes);
      } catch (e) {
        debugPrint("Ошибка захвата кадра с камеры: $e");
      }
    }

    final activeSession = _currentSession;
    setState(() {
      activeSession.messages.add(ChatMessage(
        text: userText,
        isUser: true,
        imageBase64: capturedBase64,
      ));
      if (activeSession.title == "Живой диалог" && userText.isNotEmpty) {
        activeSession.title = userText.length > 25 ? "${userText.substring(0, 25)}..." : userText;
      }
      _isLoading = true;
      _textController.clear();
    });
    _saveSessions();
    _scrollToBottom();

    try {
      List<dynamic> contentPayload = [];
      contentPayload.add({
        "type": "text",
        "text": "$userText\n\n(ВАЖНО: Отвечай строго на русском языке, разговорно, четко и без канцелярита!)"
      });

      if (capturedBase64 != null) {
        contentPayload.add({
          "type": "image_url",
          "image_url": {"url": "data:image/jpeg;base64,$capturedBase64"}
        });
      }

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
          'HTTP-Referer': 'https://github.com/black-pocket',
          'X-Title': 'BlackPocket Live',
        },
        body: jsonEncode({
          "model": _modelName,
          "messages": [
            {"role": "system", "content": _systemPrompt},
            {"role": "user", "content": contentPayload}
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final reply = data['choices'][0]['message']['content'] ?? 'Нет ответа';

        setState(() {
          activeSession.messages.add(ChatMessage(text: reply, isUser: false));
        });
        _saveSessions();
        _speakText(reply);
      } else {
        setState(() {
          activeSession.messages.add(
              ChatMessage(text: "Ошибка API (${response.statusCode}): ${response.body}", isUser: false));
        });
      }
    } catch (e) {
      setState(() {
        activeSession.messages.add(ChatMessage(text: "Ошибка сети: $e", isUser: false));
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _createNewChat() {
    final newSession = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: "Живой диалог",
      messages: [],
    );
    setState(() {
      _sessions.insert(0, newSession);
      _currentSessionId = newSession.id;
    });
    _saveSessions();
    Navigator.pop(context);
  }

  void _switchChat(String id) {
    setState(() => _currentSessionId = id);
    _saveSessions();
    Navigator.pop(context);
    _scrollToBottom();
  }

  void _deleteChat(String id) {
    setState(() {
      _sessions.removeWhere((s) => s.id == id);
      if (_sessions.isEmpty) {
        final fallback = ChatSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: "Живой диалог",
          messages: [],
        );
        _sessions.add(fallback);
      }
      _currentSessionId = _sessions.first.id;
    });
    _saveSessions();
  }

  void _openSettingsDialog() {
    final urlController = TextEditingController(text: _apiUrl);
    final keyController = TextEditingController(text: _apiKey);
    final modelController = TextEditingController(text: _modelName);
    final systemController = TextEditingController(text: _systemPrompt);
    double tempSpeechRate = _speechRate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Параметры BlackPocket'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: urlController, decoration: const InputDecoration(labelText: 'API Endpoint')),
                TextField(controller: keyController, decoration: const InputDecoration(labelText: 'API Key'), obscureText: true),
                TextField(controller: modelController, decoration: const InputDecoration(labelText: 'Model Name')),
                TextField(controller: systemController, decoration: const InputDecoration(labelText: 'System Prompt'), maxLines: 3),
                const SizedBox(height: 12),
                Text('Скорость голоса: ${tempSpeechRate.toStringAsFixed(2)}'),
                Slider(
                  value: tempSpeechRate,
                  min: 0.25,
                  max: 0.75,
                  divisions: 10,
                  label: tempSpeechRate.toStringAsFixed(2),
                  onChanged: (val) {
                    setDialogState(() => tempSpeechRate = val);
                    _tts.setSpeechRate(val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                setState(() {
                  _apiUrl = urlController.text.trim();
                  _apiKey = keyController.text.trim();
                  _modelName = modelController.text.trim();
                  _systemPrompt = systemController.text.trim();
                  _speechRate = tempSpeechRate;
                });
                _saveSettings();
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _speech.stop();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeSession = _currentSession;
    final messages = activeSession.messages;

    return Scaffold(
      drawer: Drawer(
        backgroundColor: const Color(0xFF141416),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(top: 50, left: 16, right: 16, bottom: 16),
              color: Colors.black45,
              child: Row(
                children: [
                  const Icon(Icons.videocam, color: Colors.deepPurpleAccent),
                  const SizedBox(width: 10),
                  const Text('Сессии BlackPocket', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_comment_outlined, color: Colors.deepPurpleAccent),
                    onPressed: _createNewChat,
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add, color: Colors.white70),
              title: const Text('Новая Live-сессия', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: _createNewChat,
            ),
            const Divider(color: Colors.white12),
            Expanded(
              child: ListView.builder(
                itemCount: _sessions.length,
                itemBuilder: (context, index) {
                  final s = _sessions[index];
                  final isCurrent = s.id == _currentSessionId;
                  return ListTile(
                    leading: Icon(
                      Icons.chat_bubble_outline,
                      color: isCurrent ? Colors.deepPurpleAccent : Colors.grey,
                    ),
                    title: Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isCurrent ? Colors.white : Colors.white70,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: _sessions.length > 1
                        ? IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                            onPressed: () => _deleteChat(s.id),
                          )
                        : null,
                    selected: isCurrent,
                    selectedTileColor: Colors.deepPurple.withOpacity(0.15),
                    onTap: () => _switchChat(s.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: Text(activeSession.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_isCameraActive ? Icons.videocam : Icons.videocam_off,
                color: _isCameraActive ? Colors.deepPurpleAccent : Colors.grey),
            tooltip: 'Вкл/Выкл видеокамеру',
            onPressed: () => setState(() => _isCameraActive = !_isCameraActive),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Видоискатель камеры Live View
          if (_isCameraActive && _cameraController != null && _cameraController!.value.isInitialized)
            Container(
              height: 210,
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _liveContinuousMode ? Colors.redAccent : Colors.deepPurpleAccent.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(_cameraController!),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _liveContinuousMode ? Colors.redAccent : Colors.greenAccent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _liveContinuousMode ? "LIVE VISION" : "CAMERA ACTIVE",
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_liveContinuousMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: Colors.redAccent.withOpacity(0.12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.graphic_eq, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _isSpeaking
                        ? "BlackPocket отвечает..."
                        : (_isListening ? "Слушаю твой голос..." : "Идёт обработка кадра..."),
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

          // Список сообщений
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                return Align(
                  alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
                    decoration: BoxDecoration(
                      color: msg.isUser ? Colors.deepPurple.shade800 : const Color(0xFF1E1E20),
                      borderRadius: BorderRadius.circular(16),
                      border: msg.isUser ? null : Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (msg.imageBase64 != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                base64Decode(msg.imageBase64!),
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        msg.isUser
                            ? Text(msg.text, style: const TextStyle(fontSize: 16, color: Colors.white))
                            : MarkdownBody(
                                data: msg.text,
                                styleSheet: MarkdownStyleSheet(
                                  p: const TextStyle(fontSize: 16, color: Color(0xFFEEEEEE), height: 1.4),
                                ),
                              ),
                        if (!msg.isUser)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.copy_outlined, size: 18, color: Colors.grey),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: msg.text));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Скопировано')),
                                  );
                                },
                              ),
                              IconButton(
                                icon: Icon(
                                  _isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                                  size: 18,
                                  color: _isSpeaking ? Colors.redAccent : Colors.grey,
                                ),
                                onPressed: () => _speakText(msg.text),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          if (_isLoading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: LinearProgressIndicator(minHeight: 2)),

          // Нижняя панель ввода
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: const Color(0xFF0F0F10),
            child: Row(
              children: [
                // Кнопка непрерывного режима Live
                IconButton(
                  icon: Icon(
                    _liveContinuousMode ? Icons.headset : Icons.headset_off_outlined,
                    color: _liveContinuousMode ? Colors.redAccent : Colors.grey,
                  ),
                  tooltip: 'Live режим (Камера + Голос)',
                  onPressed: _toggleContinuousLive,
                ),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: _liveContinuousMode
                          ? 'Live-диалог активен...'
                          : (_isListening ? 'Говори по-русски...' : 'Напиши или скажи...'),
                      filled: true,
                      fillColor: const Color(0xFF1B1B1E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (txt) {
                      if (txt.trim().isNotEmpty) _processLiveInput(txt.trim());
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening ? Colors.redAccent : Colors.white70,
                  ),
                  onPressed: () {
                    if (_isListening) {
                      _stopSpeechListening();
                    } else {
                      _startSpeechListening();
                    }
                  },
                ),
                IconButton.filled(
                  onPressed: _isLoading
                      ? null
                      : () {
                          final txt = _textController.text.trim();
                          if (txt.isNotEmpty) _processLiveInput(txt);
                        },
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
