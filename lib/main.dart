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

    // Очистка старых кэшированных битых ключей из памяти смартфона
    final migrationTag = prefs.getString('bp_clean_migration');
    if (migrationTag != 'v4_clean_storage') {
      await prefs.remove('apiKey');
      await prefs.remove('modelName');
      await prefs.remove('apiEndpoint');
      await prefs.setString('bp_clean_migration', 'v4_clean_storage');
    }

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
      
      // Передача ключа и в URL, и в заголовок для максимальной совместимости
      final targetUri = Uri.parse("$endpointBase/$_modelName:generateContent?key=$cleanKey");

      http.Response? response;
      const int maxRetries = 3;

      for (int attempt = 0; attempt < maxRetries; attempt++) {
        try {
          response = await http.post(
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
          ).timeout(const Duration(seconds: 30));

          if (response.statusCode != 503) {
            break;
          }

          if (attempt < maxRetries - 1) {
            await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
          }
        } on TimeoutException {
          if (attempt == maxRetries - 1) rethrow;
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      if (response != null && response.statusCode == 200) {
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
      } else if (response != null) {
        final errData = jsonDecode(utf8.decode(response.bodyBytes));
        final errMsg = errData['error']?['message'] ?? response.body;
        setState(() {
          session.messages.add(ChatMessage(
            text: "Ошибка Gemini API (${response.statusCode}):$errMsg",
            isUser: false,
          ));
        });
      } else {
        setState(() {
          session.messages.add(ChatMessage(
            text: "Сервер не вернул ответ. Проверьте сеть или VPN.",
            isUser: false,
          ));
        });
      }
    } on TimeoutException {
      setState(() {
        session.messages.add(ChatMessage(
          text: "Таймаут соединения (30 сек). Сервер не ответил. Проверь VPN или смени локацию сервера.",
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
      context:
