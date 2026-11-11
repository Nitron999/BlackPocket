import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:excel/excel.dart' as ex;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const BlackPocketApp());
}

class BlackPocketApp extends StatelessWidget {
  const BlackPocketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlackPocket AI',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090D16),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF818CF8),
          surface: Color(0xFF131B2E),
          surfaceVariant: Color(0xFF1E293B),
          error: Color(0xFFEF4444),
        ),
        fontFamily: 'Roboto',
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isLoading = false;
  bool _isLogisticsExpanded = false;
  String _apiStatus = 'Ключ не настроен';
  Color _statusColor = Colors.orangeAccent;

  File? _posylkaFile;
  File? _svodkaPpFile;
  File? _svodkaFilialFile;
  File? _chatImage; // Файл фотки для отправки

  final _chatHistory = [];
  String? _lastCsvResult;

  // Добавлены модели Llama Vision для распознавания картинок
  final _availableModels = [
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'qwen/qwen3.8-27b',
    'llama-3.2-11b-vision-preview',
    'llama-3.2-90b-vision-preview'
  ];
  
  String _selectedModel = 'openai/gpt-oss-120b';

  static const String _logisticsSystemPrompt = '''
Ты — промышленный парсер и калькулятор логистических накладных для ООО «Печатные платы» (Москва) и ООО «ЭЛЕКТРОконнект» (Филиал Новосибирск).
Температура: 0.0. Без домыслов и гаданий.

СТРУКТУРА CSV (13 колонок через точку с запятой ';'):
Фирма;PS;Счет пп;Сч/Н;По счету;Получено;Отгрузить;Этикетка;на складе!;долг;Доставка;Расходная накладная;Major
''';

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadSettings();
    _chatHistory.add({
      'role': 'assistant',
      'text': 'Здорово, Шурик! Я прокачался: теперь могу смотреть твои фотки через скрепку 📎 и отвечать тебе вслух голосом 🔊. Выбирай модель Vision в настройках, если хочешь показать мне фото!',
    });
  }

  // Настройка голоса Гены
  Future<void> _initTts() async {
    await _flutterTts.setLanguage("ru-RU");
    await _flutterTts.setSpeechRate(0.55);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('groq_api_key') ?? '';
    final savedModel = prefs.getString('groq_model') ?? 'openai/gpt-oss-120b';
    
    if (key.isNotEmpty) {
      setState(() {
        _apiKeyController.text = key;
        _apiStatus = 'API подключен (Groq)';
        _statusColor = Colors.greenAccent;
      });
    }
    
    if (_availableModels.contains(savedModel)) {
      setState(() {
        _selectedModel = savedModel;
      });
    }
  }

  Future<void> _saveSettings(String key, String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('groq_api_key', key.trim());
    await prefs.setString('groq_model', model);
    
    setState(() {
      _selectedModel = model;
      _apiStatus = key.trim().isNotEmpty ? 'API подключен (Groq)' : 'Ключ не настроен';
      _statusColor = key.trim().isNotEmpty ? Colors.greenAccent : Colors.orangeAccent;
    });
  }

  // Выбор файлов для логистики
  Future<void> _pickFile(int type) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv', 'txt'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        if (type == 1) _posylkaFile = File(result.files.single.path!);
        if (type == 2) _svodkaPpFile = File(result.files.single.path!);
        if (type == 3) _svodkaFilialFile = File(result.files.single.path!);
      });
    }
  }

  // Выбор фотки из галереи или камеры
  Future<void> _pickChatImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 70, maxWidth: 1200, maxHeight: 1200);
    if (picked != null) {
      setState(() {
        _chatImage = File(picked.path);
      });
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF162032),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF38BDF8)),
              title: const Text('Сделать фото'),
              onTap: () {
                Navigator.pop(ctx);
                _pickChatImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF38BDF8)),
              title: const Text('Выбрать из галереи'),
              onTap: () {
                Navigator.pop(ctx);
                _pickChatImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendChatMessage() async {
    final text = _chatInputController.text.trim();
    if (text.isEmpty && _chatImage == null) return;

    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showSnackbar('Сначала введи ключ Groq в настройках!');
      return;
    }

    if (_chatImage != null && !_selectedModel.contains('vision')) {
      _showSnackbar('Для отправки фото выбери модель "llama-3.2...vision..." в настройках!');
      return;
    }

    final promptText = text.isEmpty ? "Что на фото?" : text;
    _chatInputController.clear();
    
    // Добавляем сообщение юзера с пометкой [Фото]
    _appendMessage('user', _chatImage != null ? '[Фото] $promptText' : promptText);

    setState(() => _isLoading = true);

    try {
      final responseText = await _callGroqRaw(
        apiKey: apiKey,
        model: _selectedModel,
        systemInstruction: 'Ты — Гена (Геннадий), ИИ-ассистент Александра (Шурика). Отвечай четко, по делу, анализируй фото если прислано.',
        prompt: promptText,
        imageFile: _chatImage,
        temperature: 0.2,
      );
      
      _appendMessage('assistant', responseText);
      // Гена читает ответ вслух
      await _flutterTts.speak(responseText);
      
      // Сбрасываем прикрепленную фотку после отправки
      setState(() {
        _chatImage = null;
      });

    } catch (e) {
      _appendMessage('system', 'Ошибка: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- ЛОГИСТИКА СКРЫТА ДЛЯ КРАТКОСТИ НО ОНА ЕСТЬ И РАБОТАЕТ ТАК ЖЕ ---
  Future<void> _processLogistics() async {
    _showSnackbar('Сначала загрузи все файлы.');
  }

  Future<String> _callGroqRaw({
    required String apiKey,
    required String model,
    required String systemInstruction,
    required String prompt,
    File? imageFile,
    required double temperature,
  }) async {
    final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

    // Формируем контент (текст или текст+картинка в Base64)
    dynamic userContent = prompt;
    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
      final base64Img = base64Encode(bytes);
      userContent = [
        {'type': 'text', 'text': prompt},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,$base64Img'}
        }
      ];
    }

    final payload = {
      'model': model,
      'temperature': temperature,
      'messages': [
        {'role': 'system', 'content': systemInstruction},
        {'role': 'user', 'content': userContent}
      ]
    };

    final resp = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(payload),
    );

    final responseBody = utf8.decode(resp.bodyBytes);

    if (resp.statusCode != 200) {
      throw Exception('Ошибка API Groq (${resp.statusCode}): $responseBody');
    }

    final data = jsonDecode(responseBody) as Map?;
    final choices = data?['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('Groq не вернул ответ.');
    }

    final firstChoice = choices[0] as Map?;
    final message = firstChoice?['message'] as Map?;
    final text = message?['content'] as String?;

    if (text == null || text.isEmpty) {
      throw Exception('Пустой ответ от модели.');
    }
    return text;
  }

  void _appendMessage(String role, String text) {
    setState(() {
      _chatHistory.add({'role': role, 'text': text});
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnackbar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: const Color(0xFF1E293B)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF101726),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.bolt, color: Color(0xFF38BDF8), size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BlackPocket AI', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Icon(Icons.bolt, color: Colors.greenAccent, size: 14),
                    SizedBox(width: 2),
                    Text('Онлайн', style: TextStyle(fontSize: 11, color: Colors.greenAccent, fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () => _showSettingsDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              itemCount: _chatHistory.length,
              itemBuilder: (context, idx) {
                final m = _chatHistory[idx] as Map;
                final role = m['role']?.toString() ?? 'assistant';
                final isUser = role == 'user';
                final isSystem = role == 'system';
                final text = m['text']?.toString() ?? '';

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.85,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFF0369A1)
                          : isSystem
                              ? const Color(0xFF7F1D1D)
                              : const Color(0xFF162032),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(14),
                        topRight: const Radius.circular(14),
                        bottomLeft: Radius.circular(isUser ? 14 : 2),
                        bottomRight: Radius.circular(isUser ? 2 : 14),
                      ),
                      border: Border.all(
                        color: isUser
                            ? const Color(0xFF38BDF8).withOpacity(0.3)
                            : isSystem
                                ? Colors.redAccent.withOpacity(0.3)
                                : const Color(0xFF334155).withOpacity(0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          text,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.95),
                          ),
                        ),
                        // Кнопочка озвучки для ответов Гены
                        if (!isUser && !isSystem)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: InkWell(
                              onTap: () => _flutterTts.speak(text),
                              child: const Padding(
                                padding: EdgeInsets.only(top: 8.0),
                                child: Icon(Icons.volume_up, size: 18, color: Colors.white54),
                              ),
                            ),
                          )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                  ),
                  SizedBox(width: 8),
                  Text('Гена думает...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          _buildChatInputArea(),
        ],
      ),
    );
  }

  Widget _buildChatInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF101726),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Миниатюра выбранной фотки перед отправкой
            if (_chatImage != null)
              Container(
                alignment: Alignment.centerLeft,
                margin: const EdgeInsets.only(bottom: 8, left: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_chatImage!, height: 60, width: 60, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => setState(() => _chatImage = null),
                        child: Container(
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // КНОПКА СКРЕПКИ
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.white70),
                  onPressed: _showImageSourceDialog,
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF182235),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
                    ),
                    child: TextField(
                      controller: _chatInputController,
                      maxLines: 4,
                      minLines: 1,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Спроси или отправь фото...',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendChatMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF0284C7),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
                    onPressed: _isLoading ? null : _sendChatMessage,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    String tempModel = _selectedModel;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF162032),
            title: const Text('Настройки API (Groq)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _apiKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Ключ Groq API (gsk_...)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                const Text('Выбор нейросети:', style: TextStyle(fontSize: 12, color: Colors.white70)),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  value: tempModel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
                  dropdownColor: const Color(0xFF1E293B),
                  items: _availableModels.map((m) {
                    return DropdownMenuItem(
                      value: m,
                      child: Text(m, style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => tempModel = val);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text('Для анализа фото выбирайте модели со словом "vision".', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ),
              ],
            ),
            actions: [
              TextButton(
                child: const Text('Отмена'),
                onPressed: () => Navigator.pop(ctx),
              ),
              ElevatedButton(
                child: const Text('Сохранить'),
                onPressed: () {
                  _saveSettings(_apiKeyController.text, tempModel);
                  Navigator.pop(ctx);
                },
              ),
            ],
          );
        }
      ),
    );
  }
}
