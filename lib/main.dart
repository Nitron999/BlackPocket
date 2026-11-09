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
const String _defaultModel = "gemini-3.5-flash-lite";
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

class AgentPreset {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final String systemInstruction;

  const AgentPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.systemInstruction,
  });
}

final List<AgentPreset> _availableAgents = [
  const AgentPreset(
    id: "companion",
    name: "Живой напарник",
    description: "Разговорный стиль, кратко, без воды, оптимизирован под голос",
    icon: Icons.chat_bubble_outline,
    systemInstruction:
        "Ты — BlackPocket, персональный живой ИИ-напарник Александра. "
        "ПРАВИЛО №1: ВСЕГДА отвечай СТРОГО на русском языке! "
        "Отвечай кратко (1-3 емких предложения), по-живому, дружелюбно, без шаблонной вежливости. "
        "Идеально подходи для голосового режима и быстрых ответов.",
  ),
  const AgentPreset(
    id: "engineer",
    name: "Инженер / Кодер",
    description: "Глубокая архитектура, чистый код, багфикс и разбор электроники",
    icon: Icons.code,
    systemInstruction:
        "Ты — ведущий инженер-архитектор и разработчик систем. "
        "ПРАВИЛО №1: ВСЕГДА отвечай СТРОГО на русском языке! "
        "Давай точный технический анализ, проектируй надежные решения, "
        "пиши готовый к продакшену программный код в Markdown без лишних предисловий.",
  ),
  const AgentPreset(
    id: "analyst",
    name: "Аналитик документов",
    description: "Тщательный аудит логов, конфигов, таблиц и текстовых файлов",
    icon: Icons.analytics_outlined,
    systemInstruction:
        "Ты — технический аналитик данных и системной документации. "
        "ПРАВИЛО №1: ВСЕГДА отвечай СТРОГО на русском языке! "
        "Глубоко вникай в содержимое прикрепленных файлов, логов, скриптов и отчетов. "
        "Выявляй ошибки, структурируй суть и давай четкие практические выводы.",
  ),
];

class ChatMessage {
  String text;
  final bool isUser;
  final String? imageBase64;
  final String? fileName;
  String? modelUsed;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.imageBase64,
    this.fileName,
    this.modelUsed,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'imageBase64': imageBase64,
        'fileName': fileName,
        'modelUsed': modelUsed,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'] ?? '',
        isUser: json['isUser'] ?? false,
        imageBase64: json['imageBase64'],
        fileName: json['fileName'],
        modelUsed: json['modelUsed'],
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp']) ?? DateTime.now()
            : DateTime.now(),
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

class _GeminiMainScreenState extends State<GeminiMainScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  CameraController? _cameraController;
  int _currentCameraIndex = 0;

  List<ChatSession> _sessions = [];
  String _currentSessionId = "";

  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isLoading = false;
  bool _isLiveActive = false;
  bool _showLiveCamera = true;
  double _speechRate = 0.48;

  String? _selectedImageBase64;
  String? _attachedFileName;
  String? _attachedFileContent;

  String _apiKey = _defaultApiKey;
  String _modelName = _defaultModel;
  String _apiEndpoint = _defaultEndpoint;
  String _selectedAgentId = "companion";

  String _memoryFacts =
      "Пользователя зовут Александр (Шурик). "
      "Отвечай кратко, емко, по-живому, на чистом русском языке. "
      "Он ценит техническую грамотность, конструктив, отсутствие шаблонных вежливых вступлений.";

  late AnimationController _pulseController;

  AgentPreset get _currentAgent =>
      _availableAgents.firstWhere((a) => a.id == _selectedAgentId, orElse: () => _availableAgents.first);

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _initCamera(_currentCameraIndex);
    _initTts();
    _initSpeechRecognizer();
    _loadData();
  }

  void _onInputChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera(int cameraIndex) async {
    if (_availableCameras.isEmpty) return;
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }

    _currentCameraIndex = cameraIndex % _availableCameras.length;
    _cameraController = CameraController(
      _availableCameras[_currentCameraIndex],
      ResolutionPreset.low,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Ошибка камеры: $e");
    }
  }

  Future<void> _switchCamera() async {
    if (_availableCameras.length > 1) {
      HapticFeedback.selectionClick();
      final nextIndex = (_currentCameraIndex + 1) % _availableCameras.length;
      await _initCamera(nextIndex);
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
          Future.delayed(const Duration(milliseconds: 350), () {
            if (mounted && _isLiveActive && !_isLoading && !_isSpeaking) {
              _startSpeechListening();
            }
          });
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

    final migrationTag = prefs.getString('bp_clean_migration');
    if (migrationTag != 'v12_no_stop_btn_fix') {
      await prefs.remove('modelName');
      await prefs.setString('bp_clean_migration', 'v12_no_stop_btn_fix');
    }

    setState(() {
      _apiKey = prefs.getString('apiKey') ?? _defaultApiKey;
      _modelName = prefs.getString('modelName') ?? _defaultModel;
      _apiEndpoint = prefs.getString('apiEndpoint') ?? _defaultEndpoint;
      _selectedAgentId = prefs.getString('selectedAgentId') ?? "companion";
      _memoryFacts = prefs.getString('memoryFacts') ?? _memoryFacts;
      _speechRate = prefs.getDouble('speechRate') ?? 0.48;

      final historyJson = prefs.getString('gemini_sessions_list');
      if (historyJson != null && historyJson.isNotEmpty) {
        final dynamic decoded = jsonDecode(historyJson);
        if (decoded is List) {
          _sessions = decoded.map((e) => ChatSession.fromJson(e)).toList();
        }
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
    await prefs.setString('selectedAgentId', _selectedAgentId);
    await prefs.setString('memoryFacts', _memoryFacts);
    await prefs.setDouble('speechRate', _speechRate);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    HapticFeedback.lightImpact();
    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _speakText(String text) async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }
    await _stopSpeaking();
    await Future.delayed(const Duration(milliseconds: 150));

    final clean = text.replaceAll(RegExp(r'[\*\_#`>]'), '').trim();
    if (clean.isEmpty) return;

    setState(() => _isSpeaking = true);
    await _tts.setSpeechRate(_speechRate);
    await _tts.speak(clean);
  }

  void _startSpeechListening() async {
    if (_isSpeaking) await _stopSpeaking();

    bool available = await _speech.initialize();
    if (available && mounted) {
      HapticFeedback.lightImpact();
      setState(() => _isListening = true);
      _speech.listen(
        localeId: "ru_RU", // Принудительный русский словарь распознавания
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 25),
        onResult: (val) {
          final words = val.recognizedWords.trim();
          _inputController.text = words;

          final lower = words.toLowerCase();
          // Мгновенная голосовая остановка без всяких кнопок
          if (lower == 'стоп' ||
              lower == 'хватит' ||
              lower == 'замолчи' ||
              lower == 'молчать' ||
              lower.contains('стоп')) {
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
    HapticFeedback.lightImpact();
    if (mounted) setState(() => _isListening = false);
  }

  void _toggleLiveModal() {
    HapticFeedback.mediumImpact();
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
      HapticFeedback.selectionClick();
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
        HapticFeedback.selectionClick();
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

  void _checkAndAutoSaveMemory(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.startsWith('запомни:') || lower.startsWith('запомни, что') || lower.startsWith('запомни ')) {
      String fact = text;
      final match = RegExp(r'запомни[,:]?\s*(что\s*)?', caseSensitive: false).firstMatch(text);
      if (match != null) {
        fact = text.substring(match.end).trim();
      }
      if (fact.isNotEmpty) {
        if (!_memoryFacts.contains(fact)) {
          _memoryFacts = "$_memoryFacts\n- $fact";
          _saveData();
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF1E293B),
              content: Text('🧠 Запомнил: $fact', style: const TextStyle(color: Colors.greenAccent)),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  dynamic _buildContentsHistory(dynamic historyList, dynamic currentParts) {
    final resultList = [];
    final dynamic history = (historyList is List) ? historyList : [];

    final int startIdx = history.length > 8 ? history.length - 8 : 0;
    final dynamic recent = history.sublist(startIdx);

    for (final item in recent) {
      if (item is ChatMessage && item.text.trim().isNotEmpty) {
        final role = item.isUser ? "user" : "model";
        if (resultList.isNotEmpty && resultList.last["role"] == role) {
          final parts = resultList.last["parts"];
          if (parts is List && parts.isNotEmpty) {
            final prevText = parts[0]["text"].toString();
            parts[0]["text"] = "$prevText\n\n${item.text}";
          }
        } else {
          resultList.add({
            "role": role,
            "parts": [
              {"text": item.text}
            ],
          });
        }
      }
    }

    while (resultList.isNotEmpty && resultList.first["role"] == "model") {
      resultList.removeAt(0);
    }

    if (resultList.isNotEmpty && resultList.last["role"] == "user") {
      resultList.removeLast();
    }

    resultList.add({
      "role": "user",
      "parts": currentParts,
    });

    return resultList;
  }

  bool _phraseRequestsVision(String text) {
    final lower = text.toLowerCase();
    return lower.contains('посмотри') ||
        lower.contains('что это') ||
        lower.contains('видишь') ||
        lower.contains('глянь') ||
        lower.contains('проверь') ||
        lower.contains('разбери') ||
        lower.contains('в кадре') ||
        lower.contains('на фото');
  }

  Future<void> _handleSend([String? forcedText]) async {
    final text = (forcedText ?? _inputController.text).trim();
    if (text.isEmpty && _selectedImageBase64 == null && _attachedFileContent == null && !_isLiveActive) return;
    if (_isLoading) return;

    final lower = text.toLowerCase();
    if (lower == 'стоп' || lower == 'хватит' || lower == 'замолчи' || lower.contains('стоп')) {
      await _stopSpeaking();
      _inputController.clear();
      return;
    }

    HapticFeedback.lightImpact();
    _stopListening();
    _checkAndAutoSaveMemory(text);

    String? imageToSend = _selectedImageBase64;
    String? fileContentToSend = _attachedFileContent;
    String? fileNameToSend = _attachedFileName;

    _selectedImageBase64 = null;
    _attachedFileContent = null;
    _attachedFileName = null;

    if (imageToSend == null &&
        _isLiveActive &&
        _cameraController != null &&
        _cameraController!.value.isInitialized &&
        (_phraseRequestsVision(text) || text.isEmpty)) {
      try {
        final XFile file = await _cameraController!.takePicture();
        final bytes = await file.readAsBytes();
        imageToSend = base64Encode(bytes);
      } catch (e) {
        debugPrint("Кадр ошибка: $e");
      }
    }

    final session = _activeSession;
    final botMessage = ChatMessage(text: '', isUser: false, modelUsed: _modelName);
    final previousHistory = session.messages.toList();

    final displayPrompt = text.isEmpty
        ? (fileNameToSend != null ? "Изучи файл $fileNameToSend" : "Посмотри в кадр")
        : text;

    setState(() {
      session.messages.add(ChatMessage(
        text: displayPrompt,
        isUser: true,
        imageBase64: imageToSend,
        fileName: fileNameToSend,
      ));
      session.messages.add(botMessage);

      if (session.title == "Новый чат" && displayPrompt.isNotEmpty) {
        session.title = displayPrompt.length > 26 ? "${displayPrompt.substring(0, 26)}..." : displayPrompt;
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

      final combinedSystemPrompt =
          "${_currentAgent.systemInstruction}\n\n[ПАМЯТЬ АССИСТЕНТА О ПОЛЬЗОВАТЕЛЕ]:\n$_memoryFacts";

      final currentParts = [];
      currentParts.add({
        "text": userFullPrompt.isEmpty ? "Что в кадре? Ответь кратко на русском." : userFullPrompt
      });

      if (imageToSend != null) {
        currentParts.add({
          "inlineData": {
            "mimeType": "image/jpeg",
            "data": imageToSend,
          }
        });
      }

      final payloadContents = _buildContentsHistory(previousHistory, currentParts);

      final cleanKey = _apiKey.trim();
      final endpointBase = _apiEndpoint.trim().replaceAll(RegExp(r'/$'), '');

      final modelsQueue = [_modelName];
      if (!modelsQueue.contains("gemini-3.5-flash-lite")) {
        modelsQueue.add("gemini-3.5-flash-lite");
      }
      if (!modelsQueue.contains("gemini-3.6-flash")) {
        modelsQueue.add("gemini-3.6-flash");
      }

      bool success = false;

      for (final modelToTry in modelsQueue) {
        botMessage.modelUsed = modelToTry;
        final streamUri = Uri.parse("$endpointBase/$modelToTry:streamGenerateContent?alt=sse&key=$cleanKey");

        for (int attempt = 0; attempt < 2; attempt++) {
          try {
            final request = http.Request('POST', streamUri);
            request.headers.addAll({
              'Content-Type': 'application/json',
              'x-goog-api-key': cleanKey,
            });
            request.body = jsonEncode({
              "contents": payloadContents,
              "systemInstruction": {
                "parts": [
                  {"text": combinedSystemPrompt}
                ]
              }
            });

            final client = http.Client();
            final streamedResponse = await client.send(request).timeout(const Duration(seconds: 20));

            if (streamedResponse.statusCode == 200) {
              final stream = streamedResponse.stream.transform(utf8.decoder).transform(const LineSplitter());
              String accumulated = '';

              await for (final line in stream) {
                if (line.startsWith('data: ')) {
                  final jsonStr = line.substring(6).trim();
                  if (jsonStr == '[DONE]') continue;
                  try {
                    final dynamic data = jsonDecode(jsonStr);
                    if (data != null &&
                        data['candidates'] is List &&
                        (data['candidates'] as List).isNotEmpty) {
                      final candidate = data['candidates'][0];
                      if (candidate['content'] != null &&
                          candidate['content']['parts'] is List &&
                          (candidate['content']['parts'] as List).isNotEmpty) {
                        final chunk = candidate['content']['parts'][0]['text'] ?? '';
                        accumulated += chunk.toString();
                        setState(() {
                          botMessage.text = accumulated;
                        });
                        _scrollToBottom();
                      }
                    }
                  } catch (_) {}
                }
              }

              if (accumulated.isNotEmpty) {
                success = true;
                HapticFeedback.selectionClick();
                _saveData();
                _speakText(accumulated);
                break;
              }
            } else if (streamedResponse.statusCode == 503) {
              await Future.delayed(const Duration(seconds: 2));
              continue;
            } else if (streamedResponse.statusCode == 429) {
              break;
            } else {
              final errBody = await streamedResponse.stream.bytesToString();
              setState(() {
                botMessage.text = "Ошибка Gemini API (${streamedResponse.statusCode}): $errBody";
              });
              break;
            }
          } on TimeoutException {
            if (attempt == 1) break;
            await Future.delayed(const Duration(seconds: 1));
          } catch (_) {
            if (attempt == 1) break;
          }
        }

        if (success) break;
      }

      if (!success && botMessage.text.isEmpty) {
        final errText = "Связь с сервером прервалась. Проверь VPN.";
        setState(() {
          botMessage.text = errText;
        });
        if (_isLiveActive) _speakText("Связь оборвалась, повтори.");
      }
    } catch (e) {
      final errText = "Сбой сети: $e";
      setState(() {
        botMessage.text = errText;
      });
      if (_isLiveActive) _speakText("Сбой соединения.");
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

  void _deleteSession(String id) {
    setState(() {
      _sessions.removeWhere((s) => s.id == id);
      if (_sessions.isEmpty) {
        final first = ChatSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: "Новый чат",
          messages: [],
        );
        _sessions.add(first);
        _currentSessionId = first.id;
      } else if (_currentSessionId == id) {
        _currentSessionId = _sessions.first.id;
      }
    });
    _saveData();
  }

  void _clearAllSessions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить всю историю?'),
        content: const Text('Все предыдущие диалоги будут удалены безвозвратно.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _sessions.clear();
                final first = ChatSession(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: "Новый чат",
                  messages: [],
                );
                _sessions.add(first);
                _currentSessionId = first.id;
              });
              _saveData();
            },
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
  }

  void _exportCurrentChat() {
    final session = _activeSession;
    final buffer = StringBuffer();
    buffer.writeln("# Экспорт диалога: ${session.title}");
    buffer.writeln("Дата: ${DateTime.now().toLocal().toString().split('.')[0]}\n");

    for (final m in session.messages) {
      final sender = m.isUser ? "Пользователь (Александр)" : "BlackPocket (${m.modelUsed ?? 'AI'})";
      buffer.writeln("### $sender");
      if (m.fileName != null) buffer.writeln("*Прикреплен файл: ${m.fileName}*");
      buffer.writeln("${m.text}\n");
    }

    final fullExport = buffer.toString();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Экспорт диалога (.md)'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              fullExport,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть')),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Скопировать всё'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fullExport));
              HapticFeedback.mediumImpact();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Диалог скопирован в буфер в формате Markdown')),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAgentPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131316),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
              const SizedBox(height: 18),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('Выбор роли ассистента', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              ..._availableAgents.map((agent) {
                final isSelected = agent.id == _selectedAgentId;
                return ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  tileColor: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
                  leading: Icon(agent.icon, color: isSelected ? Colors.blueAccent : Colors.white70),
                  title: Text(agent.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                  subtitle: Text(agent.description, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blueAccent) : null,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedAgentId = agent.id);
                    _saveData();
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
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
              'Факты и предпочтения, которые ИИ помнит во всех диалогах (можно сказать в чате «Запомни: ...»):',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: memCtrl,
              maxLines: 7,
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
              HapticFeedback.selectionClick();
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
                    labelText: 'Основная модель (gemini-3.5-flash-lite / 3.8-flash)',
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
                          HapticFeedback.selectionClick();
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
                                            data: m.text.isEmpty && _isLoading ? '...' : m.text,
                                            selectable: true,
                                            styleSheet: MarkdownStyleSheet(
                                              p: const TextStyle(fontSize: 16, color: Color(0xFFE2E8F0), height: 1.45),
                                              code: const TextStyle(
                                                backgroundColor: Color(0xFF1E293B),
                                                color: Color(0xFF38BDF8),
                                                fontFamily: 'monospace',
                                                fontSize: 14,
                                              ),
                                              codeblockPadding: const EdgeInsets.all(12),
                                              codeblockDecoration: BoxDecoration(
                                                color: const Color(0xFF0F172A),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: Colors.white12),
                                              ),
                                            ),
                                          ),
                                    if (!m.isUser && m.text.isNotEmpty)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          if (m.modelUsed != null)
                                            Padding(
                                              padding: const EdgeInsets.only(right: 8),
                                              child: Text(
                                                m.modelUsed!,
                                                style: const TextStyle(fontSize: 10, color: Colors.white38),
                                              ),
                                            ),
                                          IconButton(
                                            icon: const Icon(Icons.copy_outlined, size: 18, color: Colors.grey),
                                            onPressed: () {
                                              Clipboard.setData(ClipboardData(text: m.text));
                                              HapticFeedback.lightImpact();
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Скопировано')),
                                              );
                                            },
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              _isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                                              size: 18,
                                              color: Colors.blueAccent,
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
          const SizedBox(width: 4),
          InkWell(
            onTap: _showAgentPicker,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  Icon(_currentAgent.icon, size: 18, color: Colors.blueAccent),
                  const SizedBox(width: 6),
                  Text(_currentAgent.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 18),
                ],
              ),
            ),
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
    final bool hasContent = _inputController.text.trim().isNotEmpty ||
        _selectedImageBase64 != null ||
        _attachedFileContent != null;

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
          if (!hasContent)
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
            onTap: () {
              if (hasContent) {
                _handleSend();
              } else {
                _toggleLiveModal();
              }
            },
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFF1D4ED8),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasContent ? Icons.arrow_upward : Icons.graphic_eq,
                color: Colors.white,
                size: 22,
              ),
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
                    icon: const Icon(Icons.flip_camera_ios, color: Colors.white70),
                    tooltip: 'Переключить камеру',
                    onPressed: _switchCamera,
                  ),
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

            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = _isSpeaking || _isListening ? 1.0 + (_pulseController.value * 0.18) : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6), Color(0xFFEC4899)],
                    ).createShader(bounds),
                    child: const Icon(Icons.auto_awesome, size: 84, color: Colors.white),
                  ),
                );
              },
            ),
            const SizedBox(height: 22),
            Text(
              _isSpeaking
                  ? "BlackPocket говорит..."
                  : (_isListening ? "Слушаю вас (Hands-Free)..." : "Обработка запроса..."),
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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

            const SizedBox(height: 6),

            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.file_download_outlined, color: Colors.greenAccent, size: 22),
              title: const Text('Экспорт чата (.md)', style: TextStyle(color: Colors.white, fontSize: 15)),
              onTap: () {
                Navigator.pop(context);
                _exportCurrentChat();
              },
            ),

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

            const Divider(color: Colors.white12, height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  const Text('История чатов', style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_sessions.length > 1 || (_sessions.isNotEmpty && _sessions[0].messages.isNotEmpty))
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white38, size: 20),
                      tooltip: 'Очистить всю историю',
                      onPressed: _clearAllSessions,
                    ),
                ],
              ),
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
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                      tooltip: 'Удалить чат',
                      onPressed: () => _deleteSession(s.id),
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
