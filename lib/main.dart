import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BlackPocketApp());
}

class BlackPocketApp extends StatelessWidget {
  const BlackPocketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlackPocket',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
          surface: const Color(0xFF141414),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final String? imagePath;

  ChatMessage({required this.text, required this.isUser, this.imagePath});

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'imagePath': imagePath,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'] ?? '',
        isUser: json['isUser'] ?? false,
        imagePath: json['imagePath'],
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

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  List<ChatSession> _sessions = [];
  String _currentSessionId = "";

  bool _isLoading = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _autoSpeak = true;
  bool _liveVoiceMode = false;
  double _speechRate = 0.45;
  File? _selectedImage;

  String _apiUrl = "https://openrouter.ai/api/v1/chat/completions";
  String _apiKey = "";
  String _modelName = "openrouter/free";
  String _systemPrompt =
      "Ты — BlackPocket, личный интеллектуальный партнер и надежный напарник. "
      "ВАЖНЕЙШЕЕ ПРАВИЛО: ВСЕГДА отвечай СТРОГО на русском языке. Любой ответ должен быть на чистом русском! "
      "Общайся естественно, открыто, уверенно и с легким юмором, как опытный знающий друг. "
      "Отвечай кратко, емко, по делу и разговорным языком, идеально подходящим для восприятия на слух. "
      "Если передано фото, сразу анализируй увиденное без лишних вступлений.";

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadAll();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("ru-RU");
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(_speechRate);

    _tts.setCompletionHandler(() {
      setState(() => _isSpeaking = false);
      if (_liveVoiceMode && mounted) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_liveVoiceMode && mounted && !_isLoading) {
            _startContinuousListening();
          }
        });
      }
    });

    _tts.setErrorHandler((msg) {
      setState(() => _isSpeaking = false);
    });
  }

  ChatSession get _currentSession {
    if (_sessions.isEmpty) {
      final newS = ChatSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: "Новый чат",
        messages: [],
      );
      _sessions.add(newS);
      _currentSessionId = newS.id;
      return newS;
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
      _autoSpeak = prefs.getBool('autoSpeak') ?? true;
      _speechRate = prefs.getDouble('speechRate') ?? 0.45;

      final historyJson = prefs.getString('blackpocket_sessions');
      if (historyJson != null && historyJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(historyJson);
        _sessions = decoded.map((e) => ChatSession.fromJson(e)).toList();
      }

      if (_sessions.isEmpty) {
        final firstSession = ChatSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: "Новый чат",
          messages: [],
        );
        _sessions.add(firstSession);
        _currentSessionId = firstSession.id;
      } else {
        _currentSessionId = prefs.getString('active_session_id') ?? _sessions.first.id;
      }
    });
    await _tts.setSpeechRate(_speechRate);
    _scrollToBottom();
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_sessions.map((e) => e.toJson()).toList());
    await prefs.setString('blackpocket_sessions', encoded);
    await prefs.setString('active_session_id', _currentSessionId);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('apiUrl', _apiUrl);
    await prefs.setString('apiKey', _apiKey);
    await prefs.setString('modelName', _modelName);
    await prefs.setString('systemPrompt', _systemPrompt);
    await prefs.setBool('autoSpeak', _autoSpeak);
    await prefs.setDouble('speechRate', _speechRate);
    await _tts.setSpeechRate(_speechRate);
  }

  void _createNewChat() {
    final newSession = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: "Новый чат",
      messages: [],
    );
    setState(() {
      _sessions.insert(0, newSession);
      _currentSessionId = newSession.id;
      _selectedImage = null;
      _controller.clear();
    });
    _saveSessions();
    Navigator.pop(context); // закрываем шторку
  }

  void _switchChat(String id) {
    setState(() {
      _currentSessionId = id;
      _selectedImage = null;
      _controller.clear();
    });
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
          title: "Новый чат",
          messages: [],
        );
        _sessions.add(fallback);
      }
      _currentSessionId = _sessions.first.id;
    });
    _saveSessions();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
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

  Future<void> _captureAndSendLiveEye() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera, imageQuality: 65, maxWidth: 1024);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
      _sendMessage();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1024);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _startContinuousListening() async {
    bool available = await _speech.initialize();
    if (available && mounted) {
      setState(() => _isListening = true);
      _speech.listen(
        localeId: "ru_RU",
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
        onResult: (val) {
          setState(() {
            _controller.text = val.recognizedWords;
          });
          if (val.finalResult && val.recognizedWords.trim().isNotEmpty) {
            _sendMessage();
          }
        },
      );
    }
  }

  void _toggleLiveMode() async {
    if (_liveVoiceMode) {
      setState(() {
        _liveVoiceMode = false;
        _isListening = false;
      });
      await _speech.stop();
      await _tts.stop();
    } else {
      setState(() {
        _liveVoiceMode = true;
      });
      _startContinuousListening();
    }
  }

  void _toggleListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          localeId: "ru_RU",
          onResult: (val) => setState(() {
            _controller.text = val.recognizedWords;
          }),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скопировано в буфер обмена'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _selectedImage == null) || _isLoading) return;

    final currentImage = _selectedImage;
    final imagePath = currentImage?.path;
    _controller.clear();
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }

    final activeSession = _currentSession;

    setState(() {
      activeSession.messages.add(ChatMessage(
        text: text,
        isUser: true,
        imagePath: imagePath,
      ));

      if (activeSession.title == "Новый чат" && text.isNotEmpty) {
        activeSession.title = text.length > 28 ? "${text.substring(0, 28)}..." : text;
      }

      _selectedImage = null;
      _isLoading = true;
    });
    _saveSessions();
    _scrollToBottom();

    try {
      List<dynamic> contentPayload = [];
      if (text.isNotEmpty) {
        contentPayload.add({"type": "text", "text": "$text (Отвечай строго на русском языке)"});
      } else {
        contentPayload.add({
          "type": "text",
          "text": "Внимательно изучи это фото и кратко своими словами расскажи на русском языке, что ты видишь."
        });
      }

      if (currentImage != null) {
        final bytes = await currentImage.readAsBytes();
        final base64Image = base64Encode(bytes);
        contentPayload.add({
          "type": "image_url",
          "image_url": {"url": "data:image/jpeg;base64,$base64Image"}
        });
      }

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
          'HTTP-Referer': 'https://github.com/black-pocket',
          'X-Title': 'BlackPocket',
        },
        body: jsonEncode({
          "model": _modelName,
          "messages": [
            {"role": "system", "content": _systemPrompt},
            {
              "role": "user",
              "content": contentPayload.length == 1 && contentPayload[0]['type'] == 'text'
                  ? contentPayload[0]['text']
                  : contentPayload
            }
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final reply = data['choices'][0]['message']['content'] ?? 'Пустой ответ';
        setState(() {
          activeSession.messages.add(ChatMessage(text: reply, isUser: false));
        });
        _saveSessions();

        if (_autoSpeak || _liveVoiceMode) {
          _speakText(reply);
        }
      } else {
        setState(() {
          activeSession.messages.add(ChatMessage(text: "Ошибка API (${response.statusCode}): ${response.body}", isUser: false));
        });
      }
    } catch (e) {
      setState(() {
        activeSession.messages.add(ChatMessage(text: "Ошибка соединения: $e", isUser: false));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _openSettingsDialog() {
    final urlController = TextEditingController(text: _apiUrl);
    final keyController = TextEditingController(text: _apiKey);
    final modelController = TextEditingController(text: _modelName);
    final systemController = TextEditingController(text: _systemPrompt);
    bool tempAutoSpeak = _autoSpeak;
    double tempSpeechRate = _speechRate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Настройки BlackPocket'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: urlController, decoration: const InputDecoration(labelText: 'API Endpoint URL')),
                TextField(controller: keyController, decoration: const InputDecoration(labelText: 'API Key'), obscureText: true),
                TextField(controller: modelController, decoration: const InputDecoration(labelText: 'Model Name')),
                TextField(controller: systemController, decoration: const InputDecoration(labelText: 'System Prompt'), maxLines: 3),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Автоозвучка ответов'),
                  value: tempAutoSpeak,
                  onChanged: (val) => setDialogState(() => tempAutoSpeak = val),
                ),
                const SizedBox(height: 8),
                Text('Скорость голоса: ${tempSpeechRate.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
                const Text('(0.3 - размеренно, 0.45 - оптимум, 0.65 - быстро)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Slider(
                  value: tempSpeechRate,
                  min: 0.2,
                  max: 0.8,
                  divisions: 12,
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
                  _autoSpeak = tempAutoSpeak;
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
              color: Colors.black38,
              child: Row(
                children: [
                  const Icon(Icons.bolt, color: Colors.deepPurpleAccent),
                  const SizedBox(width: 10),
                  const Text('Диалоги BlackPocket', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add_comment_outlined, color: Colors.deepPurpleAccent),
                    tooltip: 'Новый чат',
                    onPressed: _createNewChat,
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add, color: Colors.white70),
              title: const Text('Создать новый чат', style: TextStyle(fontWeight: FontWeight.bold)),
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
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.remove_red_eye),
            tooltip: 'Посмотреть вокруг (Камера)',
            onPressed: _isLoading ? null : _captureAndSendLiveEye,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Настройки',
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_liveVoiceMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.redAccent.withOpacity(0.15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.graphic_eq, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _isSpeaking ? "Ассистент отвечает..." : (_isListening ? "Слушаю тебя..." : "Живой диалог активен"),
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.headset_mic_outlined, size: 56, color: Colors.deepPurple.shade300),
                        const SizedBox(height: 14),
                        const Text('На связи. Включи гарнитуру или спроси текстом.',
                            style: TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return Align(
                        alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 7),
                          padding: const EdgeInsets.all(14),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
                          decoration: BoxDecoration(
                            color: msg.isUser ? Colors.deepPurple.shade700 : const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(16),
                            border: msg.isUser ? null : Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (msg.imagePath != null && File(msg.imagePath!).existsSync())
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(File(msg.imagePath!), height: 180, width: double.infinity, fit: BoxFit.cover),
                                  ),
                                ),
                              if (msg.text.isNotEmpty)
                                msg.isUser
                                    ? Text(
                                        msg.text,
                                        style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.35),
                                      )
                                    : MarkdownBody(
                                        data: msg.text,
                                        styleSheet: MarkdownStyleSheet(
                                          p: const TextStyle(fontSize: 17, height: 1.45, color: Color(0xFFEDEDED)),
                                          h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                          h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                          code: const TextStyle(fontSize: 15, backgroundColor: Colors.black26),
                                        ),
                                      ),
                              if (!msg.isUser) ...[
                                const SizedBox(height: 8),
                                const Divider(height: 1, color: Colors.white10),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.copy_outlined, size: 20, color: Colors.grey),
                                      tooltip: 'Скопировать',
                                      onPressed: () => _copyToClipboard(msg.text),
                                    ),
                                    IconButton(
                                      icon: Icon(_isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                                          size: 20, color: _isSpeaking ? Colors.redAccent : Colors.grey),
                                      tooltip: 'Озвучить',
                                      onPressed: () => _speakText(msg.text),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(6.0), child: LinearProgressIndicator(minHeight: 2)),
          if (_selectedImage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black38,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(_selectedImage!, width: 48, height: 48, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  const Text('Фото готово к отправке', style: TextStyle(fontSize: 14, color: Colors.white70)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() => _selectedImage = null)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: const Color(0xFF0F0F0F),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined),
                  onPressed: () => _pickImage(ImageSource.camera),
                  tooltip: 'Камера',
                ),
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  onPressed: () => _pickImage(ImageSource.gallery),
                  tooltip: 'Галерея',
                ),
                IconButton(
                  icon: Icon(
                    _liveVoiceMode ? Icons.headset : Icons.headset_off_outlined,
                    color: _liveVoiceMode ? Colors.redAccent : Colors.grey,
                  ),
                  onPressed: _toggleLiveMode,
                  tooltip: 'Живой режим Hands-Free',
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: _liveVoiceMode ? 'Идет живой диалог...' : (_isListening ? 'Слушаю...' : 'Сообщение...'),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? Colors.redAccent : null),
                  onPressed: _toggleListening,
                  tooltip: 'Разовый микрофон',
                ),
                IconButton.filled(
                  onPressed: _isLoading ? null : _sendMessage,
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
