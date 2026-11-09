import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
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
    debugPrint("Ошибка камеры: $e");
  }
  runApp(const GeminiBlackPocketApp());
}

class GeminiBlackPocketApp extends StatelessWidget {
  const GeminiBlackPocketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemini',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF030712),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2563EB),
          surface: Color(0xFF111827),
          background: Color(0xFF030712),
        ),
      ),
      home: const GeminiMainScreen(),
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
        title: json['title'] ?? 'Новый чат',
        messages: (json['messages'] as List<dynamic>? ?? [])
            .map((m) => ChatMessage.fromJson(m))
            .toList(),
      );
}

class GeminiMainScreen extends StatefulWidget {
  const GeminiMainScreen({super.key});

  @override
  State<GeminiMainScreen> createState() => _GeminiMainScreenState();
}

class _GeminiMainScreenState extends State<GeminiMainScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  CameraController? _cameraController;

  List<ChatSession> _sessions = [];
  String _currentSessionId = "";

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isLoading = false;
  bool _isLiveActive = false;
  bool _showLiveCamera = true;
  double _speechRate = 0.45;
  String? _selectedImageBase64;

  String _apiUrl = "https://api.groq.com/openai/v1/chat/completions";
  String _apiKey = "";
  String _modelName = "qwen/qwen3.8-27b";
  String _systemPrompt =
      "Ты — Gemini, персональный живой интеллектуальный ассистент Александра. "
      "ПРАВИЛО №1: ВСЕГДА отвечай СТРОГО на русском языке! Ни слова на английском! "
      "Отвечай емко, по-живому, точно, с пониманием дела, без роботизированных штампов. "
      "Если передано фото или кадр камеры — сразу анализируй суть увиденного.";

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initTts();
    _initSpeechRecognizer();
    _loadData();
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
        debugPrint("Камера init error: $e");
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
        if (_isLiveActive && !_isLoading) {
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
      onError: (val) => debugPrint("STT error: $val"),
      onStatus: (status) {
        if (status == 'notListening' && _isListening) {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
  }

  ChatSession get _activeSession {
    if (_sessions.isEmpty) {
      final s = ChatSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: "Новый чат",
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

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiUrl = prefs.getString('apiUrl') ?? _apiUrl;
      _apiKey = prefs.getString('apiKey') ?? _apiKey;
      _modelName = prefs.getString('modelName') ?? _modelName;
      _systemPrompt = prefs.getString('systemPrompt') ?? _systemPrompt;
      _speechRate = prefs.getDouble('speechRate') ?? 0.45;

      final historyJson = prefs.getString('gemini_sessions_list');
      if (historyJson != null && historyJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(historyJson);
        _sessions = decoded.map((e) => ChatSession.fromJson(e)).toList();
      }

      if (_sessions.isEmpty) {
        final first = ChatSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: "Новый чат",
          messages: [],
        );
        _sessions.add(first);
        _currentSessionId = first.id;
      } else {
        _currentSessionId = prefs.getString('active_session_id') ?? _sessions.first.id;
      }
    });
    await _tts.setSpeechRate(_speechRate);
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_sessions.map((e) => e.toJson()).toList());
    await prefs.setString('gemini_sessions_list', encoded);
    await prefs.setString('active_session_id', _currentSessionId);
    await prefs.setString('apiUrl', _apiUrl);
    await prefs.setString('apiKey', _apiKey);
    await prefs.setString('modelName', _modelName);
    await prefs.setString('systemPrompt', _systemPrompt);
    await prefs.setDouble('speechRate', _speechRate);
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

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _speakText(String text) async {
    await _stopSpeaking();
    final clean = text.replaceAll(RegExp(r'[\*\_#`>]'), '');
    setState(() => _isSpeaking = true);
    await _tts.setSpeechRate(_speechRate);
    await _tts.speak(clean);
  }

  void _startSpeechListening() async {
    if (_isSpeaking) await _stopSpeaking();

    bool available = await _speech.initialize();
    if (available && mounted) {
      setState(() => _isListening = true);
      _speech.listen(
        localeId: "ru_RU",
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 30),
        onResult: (val) {
          final words = val.recognizedWords.trim();
          _inputController.text = words;

          final lower = words.toLowerCase();
          if (lower == 'стоп' || lower == 'хватит' || lower == 'замолчи' || lower == 'молчать') {
            _stopSpeaking();
            _speech.stop();
            setState(() {
              _isListening = false;
              _inputController.clear();
            });
            return;
          }

          if (val.finalResult && words.isNotEmpty) {
            _handleSend(words);
          }
        },
      );
    }
  }

  void _stopListening() async {
    await _speech.stop();
    if (mounted) setState(() => _isListening = false);
  }

  void _toggleLiveModal() {
    setState(() {
      _isLiveActive = !_isLiveActive;
    });
    if (_isLiveActive) {
      _startSpeechListening();
    } else {
      _stopListening();
      _stopSpeaking();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1024);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _selectedImageBase64 = base64Encode(bytes);
      });
    }
  }

  Future<void> _handleSend([String? forcedText]) async {
    final text = (forcedText ?? _inputController.text).trim();
    if (text.isEmpty && _selectedImageBase64 == null && !_isLiveActive) return;
    if (_isLoading) return;

    final lower = text.toLowerCase();
    if (lower == 'стоп' || lower == 'хватит' || lower == 'замолчи') {
      await _stopSpeaking();
      _inputController.clear();
      return;
    }

    _stopListening();

    String? imageToSend = _selectedImageBase64;
    _selectedImageBase64 = null;

    if (imageToSend == null && _isLiveActive && _cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final XFile file = await _cameraController!.takePicture();
        final bytes = await file.readAsBytes();
        imageToSend = base64Encode(bytes);
      } catch (e) {
        debugPrint("Кадр ошибка: $e");
      }
    }

    final session = _activeSession;
    setState(() {
      session.messages.add(ChatMessage(
        text: text.isEmpty ? "Посмотри на изображение" : text,
        isUser: true,
        imageBase64: imageToSend,
      ));
      if (session.title == "Новый чат" && text.isNotEmpty) {
        session.title = text.length > 26 ? "${text.substring(0, 26)}..." : text;
      }
      _isLoading = true;
      _inputController.clear();
    });
    _saveData();
    _scrollToBottom();

    try {
      List<dynamic> content = [];
      content.add({
        "type": "text",
        "text": "${text.isEmpty ? 'Что здесь изображено?' : text}\n\n(ВАЖНО: Отвечай строго на русском языке, живо, кратко и четко!)"
      });

      if (imageToSend != null) {
        content.add({
          "type": "image_url",
          "image_url": {"url": "data:image/jpeg;base64,$imageToSend"}
        });
      }

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          "model": _modelName,
          "messages": [
            {"role": "system", "content": _systemPrompt},
            {"role": "user", "content": content}
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final reply = data['choices'][0]['message']['content'] ?? 'Пустой ответ';
        setState(() {
          session.messages.add(ChatMessage(text: reply, isUser: false));
        });
        _saveData();
        _speakText(reply);
      } else {
        setState(() {
          session.messages.add(ChatMessage(
            text: "Ошибка API (${response.statusCode}): ${response.body}",
            isUser: false,
          ));
        });
      }
    } catch (e) {
      setState(() {
        session.messages.add(ChatMessage(text: "Сбой сети: $e", isUser: false));
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  void _createNewChat() {
    final s = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: "Новый чат",
      messages: [],
    );
    setState(() {
      _sessions.insert(0, s);
      _currentSessionId = s.id;
      _isLiveActive = false;
      _selectedImageBase64 = null;
    });
    _saveData();
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  void _showAttachmentBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1F24),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Colors.blueAccent),
              title: const Text('Сделать фото'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Colors.purpleAccent),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsModal() {
    final urlCtrl = TextEditingController(text: _apiUrl);
    final keyCtrl = TextEditingController(text: _apiKey);
    final modelCtrl = TextEditingController(text: _modelName);
    final promptCtrl = TextEditingController(text: _systemPrompt);
    double rate = _speechRate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131316),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Настройки Gemini BlackPocket', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'API Endpoint URL')),
                TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: 'API Key'), obscureText: true),
                TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'Model Name')),
                TextField(controller: promptCtrl, decoration: const InputDecoration(labelText: 'System Prompt'), maxLines: 2),
                const SizedBox(height: 12),
                Text('Скорость голоса: ${rate.toStringAsFixed(2)}'),
                Slider(
                  value: rate,
                  min: 0.25,
                  max: 0.75,
                  divisions: 10,
                  onChanged: (v) {
                    setModal(() => rate = v);
                    _tts.setSpeechRate(v);
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _apiUrl = urlCtrl.text.trim();
                        _apiKey = keyCtrl.text.trim();
                        _modelName = modelCtrl.text.trim();
                        _systemPrompt = promptCtrl.text.trim();
                        _speechRate = rate;
                      });
                      _saveData();
                      Navigator.pop(context);
                    },
                    child: const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _activeSession;
    final messages = session.messages;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildGeminiDrawer(),
      body: Stack(
        children: [
          // Основной фон: глубокий синий градиент Gemini снизу вверх
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF030508),
                  Color(0xFF070B14),
                  Color(0xFF0A142B),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildTopAppBar(),

                Expanded(
                  child: messages.isEmpty
                      ? _buildWelcomeCenter()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 90),
                          itemCount: messages.length,
                          itemBuilder: (context, idx) {
                            final m = messages[idx];
                            return Align(
                              alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
                                decoration: BoxDecoration(
                                  color: m.isUser ? const Color(0xFF1E293B) : const Color(0xFF111827),
                                  borderRadius: BorderRadius.circular(20),
                                  border: m.isUser ? null : Border.all(color: Colors.white12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (m.imageBase64 != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8.0),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.memory(
                                            base64Decode(m.imageBase64!),
                                            height: 180,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    m.isUser
                                        ? Text(m.text, style: const TextStyle(fontSize: 16, color: Colors.white))
                                        : MarkdownBody(
                                            data: m.text,
                                            styleSheet: MarkdownStyleSheet(
                                              p: const TextStyle(fontSize: 16, color: Color(0xFFE2E8F0), height: 1.45),
                                            ),
                                          ),
                                    if (!m.isUser)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.copy_outlined, size: 18, color: Colors.grey),
                                            onPressed: () {
                                              Clipboard.setData(ClipboardData(text: m.text));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Скопировано')),
                                              );
                                            },
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              _isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                                              size: 18,
                                              color: _isSpeaking ? Colors.blueAccent : Colors.grey,
                                            ),
                                            onPressed: () => _isSpeaking ? _stopSpeaking() : _speakText(m.text),
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
              ],
            ),
          ),

          // Превью прикрепленного изображения
          if (_selectedImageBase64 != null)
            Positioned(
              bottom: 95,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(base64Decode(_selectedImageBase64!), width: 44, height: 44, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 8),
                    const Text('Фото прикреплено', style: TextStyle(fontSize: 13, color: Colors.white70)),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _selectedImageBase64 = null),
                    ),
                  ],
                ),
              ),
            ),

          // Нижняя плавающая капсула ввода (Gemini Pill Bar)
          Positioned(
            left: 18,
            right: 18,
            bottom: 20,
            child: _buildGeminiPillBar(),
          ),

          // Полноэкранный живой режим Live Mode (с видоискателем камеры и волной)
          if (_isLiveActive) _buildLiveOverlay(),

          // Кнопка быстрой остановки речи "Стоп"
          if (_isSpeaking && !_isLiveActive)
            Positioned(
              bottom: 95,
              right: 20,
              child: FloatingActionButton.extended(
                backgroundColor: const Color(0xFF2563EB),
                icon: const Icon(Icons.stop, color: Colors.white),
                label: const Text('СТОП', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: _stopSpeaking,
              ),
            ),
        ],
      ),
    );
  }

  // Верхняя панель Gemini
  Widget _buildTopAppBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, size: 26, color: Colors.white70),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          const SizedBox(width: 6),
          Row(
            children: const [
              Text('Gemini Flash', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
              SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 20),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined, color: Colors.white70),
            onPressed: () {},
          ),
          GestureDetector(
            onTap: _showSettingsModal,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blueAccent, width: 2),
                color: Colors.redAccent.shade700,
              ),
              child: const Center(
                child: Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Центральный блок "ALEKSANDR, что дальше?" со звёздочкой Gemini
  Widget _buildWelcomeCenter() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Звезда-кристалл Gemini (градиент)
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF4285F4), Color(0xFF9B72CF), Color(0xFFD96570), Color(0xFFF4B400)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: const Icon(Icons.auto_awesome, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 24),
          const Text(
            'ALEKSANDR, что\nдальше?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.5,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  // Нижняя капсула входа (Gemini Pill Bar)
  Widget _buildGeminiPillBar() {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2128),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white70, size: 26),
            onPressed: _showAttachmentBottomSheet,
          ),
          Expanded(
            child: TextField(
              controller: _inputController,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 16, color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Спросить ...',
                hintStyle: TextStyle(color: Colors.white54, fontSize: 16),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              ),
              onSubmitted: (txt) => _handleSend(txt),
            ),
          ),
          IconButton(
            icon: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              color: _isListening ? Colors.redAccent : Colors.white70,
              size: 24,
            ),
            onPressed: () {
              if (_isListening) {
                _stopListening();
              } else {
                _startSpeechListening();
              }
            },
          ),
          const SizedBox(width: 4),
          // Синяя круглая кнопка Live со звуковой волной
          GestureDetector(
            onTap: _toggleLiveModal,
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFF1D4ED8),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.graphic_eq, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  // Окно живого диалога Gemini Live
  Widget _buildLiveOverlay() {
    return Container(
      color: const Color(0xFF070B14).withOpacity(0.96),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: _toggleLiveModal,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(_showLiveCamera ? Icons.videocam : Icons.videocam_off, color: Colors.white70),
                    onPressed: () => setState(() => _showLiveCamera = !_showLiveCamera),
                  ),
                ],
              ),
            ),

            if (_showLiveCamera && _cameraController != null && _cameraController!.value.isInitialized)
              Container(
                height: 230,
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.4), width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: CameraPreview(_cameraController!),
                ),
              ),

            const Spacer(),

            // Анимированная звезда Live
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFFEC4899)],
              ).createShader(bounds),
              child: const Icon(Icons.auto_awesome, size: 80, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(
              _isSpeaking
                  ? "Gemini говорит..."
                  : (_isListening ? "Слушаю вас..." : "Обработка запроса..."),
              style: const TextStyle(fontSize: 18, color: Colors.white70, fontWeight: FontWeight.w500),
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton.large(
                    backgroundColor: _isSpeaking ? Colors.redAccent : const Color(0xFF1D4ED8),
                    onPressed: () {
                      if (_isSpeaking) {
                        _stopSpeaking();
                      } else if (!_isListening) {
                        _startSpeechListening();
                      }
                    },
                    child: Icon(_isSpeaking ? Icons.stop : Icons.mic, size: 36, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Боковое меню (Drawer) в точности как на скриншоте Gemini
  Widget _buildGeminiDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0B0F17),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  const Text('Gemini', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.search, color: Colors.white70), onPressed: () {}),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),

            // Кнопка "Новый чат"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: InkWell(
                onTap: _createNewChat,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2128),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                      SizedBox(width: 14),
                      Text('Новый чат', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Пункты меню
            _drawerTile(Icons.grid_view, 'Библиотека'),
            _drawerTile(Icons.schedule, 'Запланировано'),
            _drawerTile(Icons.school_outlined, 'Учащиеся'),
            _drawerTile(Icons.more_horiz, 'Ещё'),

            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Text('Блокноты', style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            _drawerTile(Icons.add, 'Новый блокнот'),

            const Divider(color: Colors.white12, height: 24),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text('Все', style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
            ),

            // Список чатов пользователя
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _sessions.length,
                itemBuilder: (context, idx) {
                  final s = _sessions[idx];
                  final isCurrent = s.id == _currentSessionId;
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: Icon(
                      Icons.chat_bubble_outline,
                      size: 18,
                      color: isCurrent ? Colors.blueAccent : Colors.white60,
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
                    trailing: const Icon(Icons.push_pin_outlined, size: 16, color: Colors.white30),
                    onTap: () {
                      setState(() => _currentSessionId = s.id);
                      _saveData();
                      Navigator.pop(context);
                      _scrollToBottom();
                    },
                  );
                },
              ),
            ),

            // Подвал профиля "ALEKSANDR Ku81 PRO"
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blueAccent, width: 2),
                      color: Colors.redAccent.shade700,
                    ),
                    child: const Center(
                      child: Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text('ALEKSANDR Ku81', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('PRO', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: Colors.white70),
                    onPressed: () {
                      Navigator.pop(context);
                      _showSettingsModal();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerTile(IconData icon, String title) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
      onTap: () {},
    );
  }
}
