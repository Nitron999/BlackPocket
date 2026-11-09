import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

List<CameraDescription> _availableCameras = [];

const String _defaultApiKey = "AQ.Ab8RN6INDiAIoK2cYOusWKutVqD0XFZpPLDOyYAriMWojxlNyQ";
const String _defaultModel = "gemini-3.8-flash";
const String _defaultEndpoint = "https://generativelanguage.googleapis.com/v1beta/models";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _availableCameras = await availableCameras();
  } catch (e) {
    debugPrint("Камера не найдена или ошибка: $e");
  }
  runApp(const GeminiBlackPocketApp());
}

class GeminiBlackPocketApp extends StatelessWidget {
  const GeminiBlackPocketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlackPocket AI',
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
  final String? fileName;

  ChatMessage({required this.text, required this.isUser, this.imageBase64, this.fileName});

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'imageBase64': imageBase64,
        'fileName': fileName,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'] ?? '',
        isUser: json['isUser'] ?? false,
        imageBase64: json['imageBase64'],
        fileName: json['fileName'],
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
  String? _attachedFileName;
  String? _attachedFileContent;

  String _apiKey = _defaultApiKey;
  String _modelName = _defaultModel;
  String _apiEndpoint = _defaultEndpoint;

  String _memoryFacts =
      "Пользователя зовут Александр (Шурик). "
      "Отвечай кратко, емко, по-живому, на чистом русском языке. "
      "Он ценит техническую грамотность, конструктив, отсутствие шаблонных вежливых вступлений.";

  final String _systemPrompt =
      "Ты — BlackPocket, персональный ИИ-напарник Александра. "
      "ПРАВИЛО №1: ВСЕГДА отвечай СТРОГО на русском языке! Ни слова на английском! "
      "Отвечай кратко, разговорно, по делу, с техническим пониманием. "
      "Если передано фото или кадр камеры — сразу без вступлений говори по сути увиденного.";

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
        debugPrint("Камера не найдена или ошибка: $e");
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
      onError: (val) => debugPrint("Ошибка STT: $val"),
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
      _apiKey = prefs.getString('apiKey') ?? _defaultApiKey;
      _modelName = prefs.getString('modelName') ?? _defaultModel;
      _apiEndpoint = prefs.getString('apiEndpoint') ?? _defaultEndpoint;
      _memoryFacts = prefs.getString('memoryFacts') ?? _memoryFacts;
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
    await prefs.setString('apiKey', _apiKey);
    await prefs.setString('modelName', _modelName);
    await prefs.setString('apiEndpoint', _apiEndpoint);
    await prefs.setString('memoryFacts', _memoryFacts);
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
        _attachedFileName = null;
        _attachedFileContent = null;
      });
    }
  }

  Future<void> _pickDocumentFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'log', 'json', 'py', 'dart', 'csv', 'yaml', 'md'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final text = await file.readAsString();
        setState(() {
          _attachedFileName = result.files.single.name;
          _attachedFileContent = text;
          _selectedImageBase64 = null;
        });
      }
    } catch (e) {
      debugPrint("Ошибка чтения файла: $e");
    }
  }

  Future<void> _handleSend([String? forcedText]) async {
    final text = (forcedText ?? _inputController.text).trim();
    if (text.isEmpty && _selectedImageBase64 == null && _attachedFileContent == null && !_isLiveActive) return;
    if (_isLoading) return;

    final lower = text.toLowerCase();
    if (lower == 'стоп' || lower == 'хватит' || lower == 'замолчи') {
      await _stopSpeaking();
      _inputController.clear();
      return;
    }

    _stopListening();

    String? imageToSend = _selectedImageBase64;
    String? fileContentToSend = _attachedFileContent;
    String? fileNameToSend = _attachedFileName;

    _selectedImageBase64 = null;
    _attachedFileContent = null;
    _attachedFileName = null;

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
        text: text.isEmpty ? (fileNameToSend != null ? "Изучи файл $fileNameToSend" : "Посмотри на изображение") : text,
        isUser: true,
        imageBase64: imageToSend,
        fileName: fileNameToSend,
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
      String userFullPrompt = text;
      if (fileContentToSend != null) {
        userFullPrompt += "\n\n[СОДЕРЖИМОЕ ФАЙЛА '$fileNameToSend']:\n$fileContentToSend";
      }

      final combinedSystemPrompt = "$_systemPrompt\n\n[ПАМЯТЬ АССИСТЕНТА О ПОЛЬЗОВАТЕЛЕ]:\n$_memoryFacts";

      final userParts = [];
      userParts.add({
        "text": userFullPrompt.isEmpty ? "Что здесь изображено? Ответь кратко на русском." : userFullPrompt
      });

      if (imageToSend != null) {
        userParts.add({
          "inlineData": {
            "mimeType": "image/jpeg",
            "data": imageToSend,
          }
        });
      }

      final cleanKey = _apiKey.trim();
      final endpointBase = _apiEndpoint.trim().replaceAll(RegExp(r'/$'), '');
      final targetUri = Uri.parse("$endpointBase/$_modelName:generateContent");

      final response = await http.post(
        targetUri,
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': cleanKey,
        },
        body: jsonEncode({
          "contents": [
            {
              "role": "user",
              "parts": userParts,
            }
          ],
          "systemInstruction": {
            "parts": [
              {"text": combinedSystemPrompt}
            ]
          }
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        String reply = 'Пустой ответ от Gemini';

        if (data['candidates'] != null &&
            (data['candidates'] as List).isNotEmpty &&
            data['candidates'][0]['content'] != null &&
            data['candidates'][0]['content']['parts'] != null &&
            (data['candidates'][0]['content']['parts'] as List).isNotEmpty) {
          reply = data['candidates'][0]['content']['parts'][0]['text'] ?? '';
        }

        setState(() {
          session.messages.add(ChatMessage(text: reply, isUser: false));
        });
        _saveData();
        _speakText(reply);
      } else {
        final errData = jsonDecode(utf8.decode(response.bodyBytes));
        final errMsg = errData['error']?['message'] ?? response.body;
        setState(() {
          session.messages.add(ChatMessage(
            text: "Ошибка Gemini API (${response.statusCode}): $errMsg",
            isUser: false,
          ));
        });
      }
    } on TimeoutException {
      setState(() {
        session.messages.add(ChatMessage(
          text: "Таймаут соединения (20 сек). Сервер не ответил. Проверь, включен ли VPN на телефоне.",
          isUser: false,
        ));
      });
    } catch (e) {
      setState(() {
        session.messages.add(ChatMessage(
          text: "Сбой сети: $e. Убедись, что подключен VPN для доступа к Google API.",
          isUser: false,
        ));
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
      _attachedFileName = null;
      _attachedFileContent = null;
    });
    _saveData();
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  void _showAttachmentBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2128),
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
            ListTile(
              leading: const Icon(Icons.description_outlined, color: Colors.greenAccent),
              title: const Text('Загрузить документ (.txt, .log, .json, .py, .dart)'),
              onTap: () {
                Navigator.pop(context);
                _pickDocumentFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMemoryDialog() {
    final memCtrl = TextEditingController(text: _memoryFacts);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.psychology, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Память ассистента'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Факты и предпочтения, которые ИИ помнит во всех чатах:',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: memCtrl,
              maxLines: 6,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0xFF1E2128),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              setState(() => _memoryFacts = memCtrl.text.trim());
              _saveData();
              Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _showSettingsModal() {
    final keyCtrl = TextEditingController(text: _apiKey);
    final modelCtrl = TextEditingController(text: _modelName);
    final endpointCtrl = TextEditingController(text: _apiEndpoint);
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
                const Text('Настройки BlackPocket AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Google Gemini API Key (AQ...)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Имя модели (по умолчанию gemini-3.8-flash)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: endpointCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Endpoint URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Скорость голоса: ${rate.toStringAsFixed(2)}x'),
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          keyCtrl.text = _defaultApiKey;
                          modelCtrl.text = _defaultModel;
                          endpointCtrl.text = _defaultEndpoint;
                        },
                        child: const Text('По умолчанию'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _apiKey = keyCtrl.text.trim();
                            _modelName = modelCtrl.text.trim();
                            _apiEndpoint = endpointCtrl.text.trim();
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
                                    if (m.fileName != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        margin: const EdgeInsets.only(bottom: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.greenAccent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.attach_file, size: 16, color: Colors.greenAccent),
                                            const SizedBox(width: 4),
                                            Text(m.fileName!, style: const TextStyle(fontSize: 12, color: Colors.greenAccent)),
                                          ],
                                        ),
                                      ),
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

          if (_selectedImageBase64 != null || _attachedFileName != null)
            Positioned(
              bottom: 95,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    if (_selectedImageBase64 != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(base64Decode(_selectedImageBase64!), width: 40, height: 40, fit: BoxFit.cover),
                      )
                    else
                      const Icon(Icons.description, color: Colors.greenAccent, size: 30),
                    const SizedBox(width: 8),
                    Text(_attachedFileName ?? 'Фото прикреплено', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        _selectedImageBase64 = null;
                        _attachedFileName = null;
                        _attachedFileContent = null;
                      }),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            left: 18,
            right: 18,
            bottom: 20,
            child: _buildGeminiPillBar(),
          ),

          if (_isLiveActive) _buildLiveOverlay(),

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
            children: [
              Text(_modelName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(width: 4),
              const Icon(Icons.check_circle, color: Colors.blueAccent, size: 16),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.psychology_outlined, color: Colors.blueAccent),
            tooltip: 'Память ассистента',
            onPressed: _showMemoryDialog,
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

  Widget _buildWelcomeCenter() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
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
                  const Text('BlackPocket', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),

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

            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.psychology, color: Colors.blueAccent, size: 22),
              title: const Text('Память ассистента', style: TextStyle(color: Colors.white, fontSize: 15)),
              onTap: () {
                Navigator.pop(context);
                _showMemoryDialog();
              },
            ),

            const Divider(color: Colors.white12, height: 24),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text('История чатов', style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
            ),

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
                    tooltip: 'Настройки',
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
}
