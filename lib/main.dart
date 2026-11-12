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
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:image_picker/image_picker.dart';

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

class ChatMessage {
  final String role;
  final String text;
  final String? imagePath;
  final String? fileName;

  ChatMessage({
    required this.role,
    required this.text,
    this.imagePath,
    this.fileName,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'imagePath': imagePath,
        'fileName': fileName,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] ?? 'assistant',
        text: json['text'] ?? '',
        imagePath: json['imagePath'],
        fileName: json['fileName'],
      );
}

class ChatSession {
  String id;
  String title;
  dynamic messages;

  ChatSession({required this.id, required this.title, required this.messages});

  Map<String, dynamic> toJson() {
    var rawList = messages as List;
    return {
      'id': id,
      'title': title,
      'messages': rawList.map((m) => m.toJson()).toList(),
    };
  }

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    var rawMsgs = json['messages'] as List? ?? [];
    var parsedMsgs = rawMsgs
        .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return ChatSession(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Чат',
      messages: parsedMsgs,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  static const MethodChannel _ttsChannel = MethodChannel('blackpocket/native_tts');

  bool _isLoading = false;
  bool _isLogisticsExpanded = false;
  String _apiStatus = 'Ключ не настроен';
  bool _isKeyValidating = false;
  bool? _isKeyWorking;
  bool _isVoiceEnabled = false;

  File? _posylkaFile;
  File? _svodkaPpFile;
  File? _svodkaFilialFile;

  File? _chatImage;
  File? _chatAttachedFile;

  var _sessions = [];
  ChatSession? _currentSession;
  String? _lastCsvResult;

  final _availableModels = [
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'qwen/qwen3.8-27b',
    'meta-llama/llama-4-scout-17b-16e-instruct',
    'llama-3.2-11b-vision-preview',
  ];

  String _selectedModel = 'openai/gpt-oss-120b';

  static const String _logisticsSystemPrompt = '''
Ты — промышленный парсер и калькулятор логистических накладных для ООО «Печатные платы» (Москва) и ООО «ЭЛЕКТРОконнект» (Филиал Новосибирск).
Температура: 0.0. Без домыслов и гаданий.

СТРУКТУРА CSV (13 колонок через точку с запятой ';'):
Фирма;PS;Счет пп;Сч/Н;По счету;Получено;Отгрузить;Этикетка;на складе!;долг;Доставка;Расходная накладная;Major

ПРАВИЛА:
1. ГОЛОВА (ООО «Печатные платы»):
- Поиск по PS в сводке ПП. Заполнить фирму, если не указана.
- Счет пп: московский счет с ведущими нулями (0654, 0644, 0611).
- По счету: ПОЛНЫЙ тираж из сводки ПП (колонка «количество», столбец 4). Не дублировать «Получено»!
- Этикетка: всегда "ОТК".
- Доставка: "ДМ", "СДЭК", "К", "Самовывоз".

2. РАЗДЕЛИТЕЛЬ:
филиал;;;;;;;;;;;;

3. ФИЛИАЛ (ООО «ЭЛЕКТРОконнект»):
- Счет пп: СТРОГО ПУСТО.
- Этикетка: СТРОГО ПУСТО (ОТК нет!).
- По счету: найти в сводке филиала по связке [Сч/Н + PS] значение из столбца 7 («кол-во»). Это полный заказ (например, Кортэк = 50, Промприбор = 5000).
- Доставка: Нейрософт и Кузьминский -> "К"; АТБ-Электроника -> "ДМ"; СДЭК -> "СДЭК"; Самовывоз -> "Самовывоз".

4. СОРТИРОВКА ВНУТРИ КАЖДОГО БЛОКА:
ДМ -> СДЭК -> К -> Самовывоз.

Формат ответа: только блок ```csv ... ``` без лишнего текста.
''';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettingsAndChats();
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus) {
        _scrollToBottom(delayMs: 300);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottomInset = WidgetsBinding.instance.window.viewInsets.bottom;
    if (bottomInset > 0) {
      _scrollToBottom(delayMs: 150);
    }
  }

  void _scrollToBottom({int delayMs = 100}) {
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _speak(String text, {bool force = false}) async {
    if (!_isVoiceEnabled && !force) return;
    try {
      await _ttsChannel.invokeMethod('speak', {'text': text});
    } catch (_) {}
  }

  Future<void> _stopVoice() async {
    try {
      await _ttsChannel.invokeMethod('stop');
    } catch (_) {}
  }

  Future<void> _loadSettingsAndChats() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('groq_api_key') ?? '';
    final savedModel = prefs.getString('groq_model') ?? 'openai/gpt-oss-120b';
    final savedVoice = prefs.getBool('is_voice_enabled') ?? false;

    setState(() {
      _isVoiceEnabled = savedVoice;
    });

    if (key.isNotEmpty) {
      _apiKeyController.text = key;
      setState(() {
        _apiStatus = 'Ключ сохранен';
        _isKeyWorking = true;
      });
    }

    if (_availableModels.contains(savedModel)) {
      setState(() {
        _selectedModel = savedModel;
      });
    }

    final chatsJson = prefs.getString('chat_sessions');
    if (chatsJson != null) {
      try {
        final decoded = jsonDecode(chatsJson) as List;
        setState(() {
          _sessions = decoded
              .map((e) => ChatSession.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        });
      } catch (_) {}
    }

    if (_sessions.isEmpty) {
      _createNewChat(
        initMessage:
            'Здорово, Шурик! Я на связи. Спрашивай что нужно, кидай фото или файлы через скрепку, а для накладных разворачивай панель сверху 📦.',
      );
    } else {
      setState(() {
        _currentSession = _sessions.first as ChatSession;
      });
    }
  }

  Future<void> _saveChats() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_sessions.map((e) => e.toJson()).toList());
    await prefs.setString('chat_sessions', encoded);
  }

  void _createNewChat({String? initMessage}) {
    final newSession = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title:
          'Чат от ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      messages: [
        ChatMessage(
          role: 'assistant',
          text: initMessage ??
              'Здорово, Шурик! Новый чат готов к работе. Чем займемся?',
        )
      ],
    );
    setState(() {
      _sessions.insert(0, newSession);
      _currentSession = newSession;
    });
    _saveChats();
  }

  void _renameChat(ChatSession session) {
    final titleController = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF162032),
        title: const Text('Переименовать чат'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                session.title = titleController.text.trim().isEmpty
                    ? 'Без названия'
                    : titleController.text.trim();
              });
              _saveChats();
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _deleteChat(ChatSession session) {
    setState(() {
      _sessions.remove(session);
      if (_sessions.isEmpty) {
        _createNewChat();
      } else if (_currentSession == session) {
        _currentSession = _sessions.first as ChatSession;
      }
    });
    _saveChats();
  }

  Future<void> _saveSettingsOnly(String key, String model) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmedKey = key.trim();
    await prefs.setString('groq_api_key', trimmedKey);
    await prefs.setString('groq_model', model);
    setState(() {
      _selectedModel = model;
      if (trimmedKey.isNotEmpty) {
        _apiStatus = 'Ключ сохранен';
        _isKeyWorking = true;
      } else {
        _apiStatus = 'Ключ не настроен';
        _isKeyWorking = false;
      }
    });
    _showSnackbar('Настройки успешно сохранены!');
  }

  Future<void> _validateKeyOnly(String key) async {
    final trimmedKey = key.trim();
    if (trimmedKey.isEmpty) {
      setState(() {
        _isKeyWorking = false;
        _apiStatus = 'Ключ не введен';
      });
      _showSnackbar('Сначала введите ключ!');
      return;
    }

    setState(() {
      _isKeyValidating = true;
    });

    try {
      final url = Uri.parse('https://api.groq.com/openai/v1/models');
      final resp = await http.get(
        url,
        headers: {'Authorization': 'Bearer $trimmedKey'},
      );

      if (resp.statusCode == 200) {
        setState(() {
          _isKeyWorking = true;
          _apiStatus = 'Ключ активен и проверен';
        });
        _showSnackbar('Ключ рабочий и активен!');
      } else {
        setState(() {
          _isKeyWorking = false;
          _apiStatus = 'Ошибка: неверный ключ';
        });
        _showSnackbar('Ошибка: неверный API ключ!');
      }
    } catch (_) {
      setState(() {
        _isKeyWorking = false;
        _apiStatus = 'Ошибка сети';
      });
      _showSnackbar('Ошибка сети при проверке.');
    } finally {
      setState(() {
        _isKeyValidating = false;
      });
    }
  }

  Future<void> _pickFile(int type) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv', 'txt'],
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.single.path;
      if (path != null && path.isNotEmpty) {
        setState(() {
          if (type == 1) _posylkaFile = File(path);
          if (type == 2) _svodkaPpFile = File(path);
          if (type == 3) _svodkaFilialFile = File(path);
        });
      }
    }
  }

  Future<void> _pickChatImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (picked != null) {
      setState(() {
        _chatImage = File(picked.path);
        _chatAttachedFile = null;
      });
    }
  }

  Future<void> _pickChatDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null && result.files.isNotEmpty) {
      final path = result.files.single.path;
      if (path != null && path.isNotEmpty) {
        setState(() {
          _chatAttachedFile = File(path);
          _chatImage = null;
        });
      }
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF162032),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
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
              title: const Text('Выбрать фото из галереи'),
              onTap: () {
                Navigator.pop(ctx);
                _pickChatImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file, color: Colors.greenAccent),
              title: const Text('Прикрепить файл (Excel, CSV, TXT, и др.)'),
              onTap: () {
                Navigator.pop(ctx);
                _pickChatDocument();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendChatMessage() async {
    final text = _chatInputController.text.trim();
    if (text.isEmpty && _chatImage == null && _chatAttachedFile == null) return;

    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showSnackbar('Сначала введи ключ Groq в настройках!');
      return;
    }

    final activeImage = _chatImage;
    final activeDoc = _chatAttachedFile;

    String displayPrompt = text;
    if (displayPrompt.isEmpty) {
      if (activeImage != null) {
        displayPrompt = 'Что на фото?';
      } else if (activeDoc != null) {
        displayPrompt = 'Проанализируй прикрепленный файл.';
      }
    }

    final docName = activeDoc?.path.split(Platform.pathSeparator).last;

    _chatInputController.clear();
    _appendMessage(
      'user',
      displayPrompt,
      imagePath: activeImage?.path,
      fileName: docName,
    );

    setState(() {
      _chatImage = null;
      _chatAttachedFile = null;
      _isLoading = true;
    });

    try {
      String finalPromptForApi = displayPrompt;
      String modelToUse = _selectedModel;

      // Авто-роутинг моделей под тип контента:
      if (activeImage != null) {
        // 1. Для картинок — vision-модель
        if (!modelToUse.contains('vision') && !modelToUse.contains('llama-4')) {
          modelToUse = 'llama-3.2-11b-vision-preview';
        }
      } else if (activeDoc != null && activeDoc.existsSync()) {
        // 2. Для документов/таблиц через скрепку — экономичная и быстрая модель с высоким лимитом
        modelToUse = 'openai/gpt-oss-20b';
        final docContent = await _readAnyFileSafe(activeDoc, maxRows: 80, maxChars: 7500);
        finalPromptForApi =
            '$displayPrompt\n\n=== СОДЕРЖИМОЕ ФАЙЛА ($docName) ===\n$docContent';
      }
      // 3. Для обычного текста остается выбранная в настройках модель (_selectedModel)

      final historyList = _currentSession?.messages as List? ?? [];

      final responseText = await _callGroqWithHistory(
        apiKey: apiKey,
        model: modelToUse,
        systemInstruction:
            'Ты — Гена (Геннадий), персональный ИИ-ассистент Александра (Шурика). Отвечай четко, по делу, с юмором где уместно, поддерживай любые технические, логистические и бытовые темы на русском языке.',
        messages: historyList,
        overrideLastUserText: finalPromptForApi,
        imageFile: activeImage,
        temperature: 0.2,
      );

      _appendMessage('assistant', responseText);
      await _speak(responseText);
    } catch (e) {
      _appendMessage('system', 'Ошибка: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _processLogistics() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showSnackbar('Введите ключ Groq в настройках!');
      return;
    }

    final posFile = _posylkaFile;
    if (posFile == null || !posFile.existsSync()) {
      _showSnackbar('Выберите файл Посылки!');
      return;
    }

    setState(() {
      _isLoading = true;
      _lastCsvResult = null;
    });

    // Авто-роутинг для логистики: всегда используем оптимальную по токенам и скорости модель
    const String logisticsModel = 'openai/gpt-oss-20b';

    final fileName = posFile.path.split(Platform.pathSeparator).last;
    _appendMessage(
      'user',
      '📦 Запуск сведения накладной (автовыбор: $logisticsModel): $fileName',
    );

    try {
      final posylkaContent = await _readAnyFileSafe(posFile, maxRows: 80, maxChars: 3500);
      final filterTokens = _extractSearchTokensFromPosylka(posylkaContent);

      String svodkaPpContent = '';
      final ppFile = _svodkaPpFile;
      if (ppFile != null && ppFile.existsSync()) {
        svodkaPpContent = await _readAnyFileSafe(
          ppFile,
          maxRows: 80,
          maxChars: 3000,
          filterTokens: filterTokens,
        );
      }

      String svodkaFilialContent = '';
      final filFile = _svodkaFilialFile;
      if (filFile != null && filFile.existsSync()) {
        svodkaFilialContent = await _readAnyFileSafe(
          filFile,
          maxRows: 80,
          maxChars: 3000,
          filterTokens: filterTokens,
        );
      }

      final promptText = '''
ВХОДНЫЕ ДАННЫЕ ДЛЯ СВЕДЕНИЯ:

=== 1. ФАЙЛ ПОСЫЛКА (ТЕКУЩИЙ ПРИХОД) ===
$posylkaContent

=== 2. СВОДКА ООО ПЕЧАТНЫЕ ПЛАТЫ (ГОЛОВА) ===
$svodkaPpContent

=== 3. СВОДКА ФИЛИАЛ (ЭЛЕКТРОКОННЕКТ) ===
$svodkaFilialContent

Выполни сопоставление по инструкции и верни CSV.
''';

      final response = await _callGroqRaw(
        apiKey: apiKey,
        model: logisticsModel,
        systemInstruction: _logisticsSystemPrompt,
        prompt: promptText,
        temperature: 0.0,
      );

      final csv = _extractCsv(response);
      setState(() {
        _lastCsvResult = csv;
      });

      _appendMessage('assistant', response);
      await _speak("Накладная успешно сведена, Шурик!");
    } catch (e) {
      _appendMessage('system', 'Ошибка логистики: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Set<String> _extractSearchTokensFromPosylka(String posylkaCsv) {
    final tokens = <String>{};
    final stopWords = {'ооо', 'зао', 'оао', 'сдэк', 'самовывоз', 'отк', 'плата', 'платы', 'лист', 'посылка'};
    final lines = posylkaCsv.split('\n');
    for (int i = 1; i < lines.length; i++) {
      final parts = lines[i].split(';');
      for (final rawPart in parts) {
        final clean = rawPart.trim().toLowerCase();
        if (clean.length >= 3 && !stopWords.contains(clean)) {
          if (RegExp(r'\d').hasMatch(clean) && RegExp(r'^[a-zа-я0-9\-/\.]+$').hasMatch(clean)) {
            tokens.add(clean);
            final digits = RegExp(r'\d{3,}').allMatches(clean).map((m) => m.group(0)!);
            tokens.addAll(digits);
          }
        }
      }
    }
    return tokens;
  }

  Future<String> _readAnyFileSafe(
    File file, {
    int maxRows = 150,
    int maxChars = 6000,
    Set<String>? filterTokens,
  }) async {
    String rawText = '';
    final path = file.path.toLowerCase();

    if (path.endsWith('.xlsx')) {
      rawText = await _parseXlsxDirectlyViaXml(
        file,
        maxRows: maxRows,
        filterTokens: filterTokens,
      );
    } else if (path.endsWith('.xls')) {
      try {
        final bytes = await file.readAsBytes();
        final excel = ex.Excel.decodeBytes(bytes);
        final sb = StringBuffer();
        for (final entry in excel.tables.entries) {
          sb.writeln('Лист: ${entry.key}');
          for (final row in entry.value.rows) {
            final vals = row.map((c) => c?.value?.toString() ?? '').toList();
            if (vals.any((v) => v.trim().isNotEmpty)) {
              sb.writeln(vals.join(';'));
            }
          }
        }
        rawText = sb.toString();
      } catch (_) {
        rawText = '[Файл .xls старого бинарного формата — пересохраните в .xlsx или .csv]';
      }
    } else {
      try {
        final bytes = await file.readAsBytes();
        try {
          rawText = utf8.decode(bytes);
        } catch (_) {
          rawText = latin1.decode(bytes);
        }
      } catch (e) {
        rawText = '[Не удалось прочитать текстовый файл: $e]';
      }
    }

    if (rawText.length > maxChars) {
      return '${rawText.substring(0, maxChars)}\n... [Обрезано по лимиту API]';
    }
    return rawText;
  }

  Future<String> _parseXlsxDirectlyViaXml(
    File file, {
    int maxRows = 150,
    Set<String>? filterTokens,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      List<String> sharedStrings = [];
      final sharedStringsFile = archive.findFile('xl/sharedStrings.xml');
      if (sharedStringsFile != null) {
        final xmlStr = utf8.decode(sharedStringsFile.content as List<int>, allowMalformed: true);
        final document = XmlDocument.parse(xmlStr);
        for (final si in document.findAllElements('si')) {
          final textBuffer = StringBuffer();
          for (final t in si.findAllElements('t')) {
            textBuffer.write(t.innerText);
          }
          sharedStrings.add(textBuffer.toString().replaceAll(';', ' ').replaceAll('\n', ' ').trim());
        }
      }

      final sheetFiles = archive.files
          .where((f) => f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (sheetFiles.isEmpty) {
        return '[Пустая книга Excel]';
      }

      final sb = StringBuffer();
      final sheetsToRead = sheetFiles.take(1);

      for (final sheetFile in sheetsToRead) {
        final sheetXmlStr = utf8.decode(sheetFile.content as List<int>, allowMalformed: true);
        final sheetDoc = XmlDocument.parse(sheetXmlStr);
        final allRowElements = sheetDoc.findAllElements('row').toList();

        if (allRowElements.isEmpty) continue;

        List<String> parsedRows = [];

        for (final rowEl in allRowElements) {
          final cells = rowEl.findAllElements('c').toList();
          if (cells.isEmpty) continue;

          Map<int, String> rowMap = {};
          int maxColIdx = 0;

          for (final c in cells) {
            final ref = c.getAttribute('r') ?? '';
            final colIdx = _columnLettersToIndex(ref);
            if (colIdx > 14) continue;
            if (colIdx > maxColIdx) maxColIdx = colIdx;

            final type = c.getAttribute('t');
            String cellVal = '';

            if (type == 's') {
              final vEl = c.findElements('v').firstOrNull;
              final idx = int.tryParse(vEl?.innerText ?? '');
              if (idx != null && idx >= 0 && idx < sharedStrings.length) {
                cellVal = sharedStrings[idx];
              }
            } else if (type == 'inlineStr') {
              final tEl = c.findAllElements('t').firstOrNull;
              cellVal = tEl?.innerText ?? '';
            } else {
              final vEl = c.findElements('v').firstOrNull;
              cellVal = vEl?.innerText ?? '';
            }

            cellVal = cellVal.replaceAll(';', ' ').replaceAll('\n', ' ').trim();
            rowMap[colIdx] = cellVal;
          }

          List<String> rowValues = [];
          bool hasAnyData = false;
          for (int i = 0; i <= maxColIdx; i++) {
            final v = rowMap[i] ?? '';
            if (v.isNotEmpty) hasAnyData = true;
            rowValues.add(v);
          }

          while (rowValues.isNotEmpty && rowValues.last.isEmpty) {
            rowValues.removeLast();
          }

          if (hasAnyData && rowValues.isNotEmpty) {
            parsedRows.add(rowValues.join(';'));
          }
        }

        if (parsedRows.isEmpty) continue;

        sb.writeln(parsedRows.first);

        if (filterTokens != null && filterTokens.isNotEmpty) {
          int matchedCount = 0;
          for (int i = 1; i < parsedRows.length; i++) {
            final rowLower = parsedRows[i].toLowerCase();
            bool matches = false;
            for (final token in filterTokens) {
              if (rowLower.contains(token)) {
                matches = true;
                break;
              }
            }
            if (matches) {
              sb.writeln(parsedRows[i]);
              matchedCount++;
              if (matchedCount >= maxRows) break;
            }
          }
          if (matchedCount == 0) {
            final fallbackStart = parsedRows.length > 26 ? (parsedRows.length - 25) : 1;
            for (int i = fallbackStart; i < parsedRows.length; i++) {
              sb.writeln(parsedRows[i]);
            }
          }
        } else {
          final startIdx = parsedRows.length > (maxRows + 1) ? (parsedRows.length - maxRows) : 1;
          for (int i = startIdx; i < parsedRows.length; i++) {
            sb.writeln(parsedRows[i]);
          }
        }
      }

      return sb.toString();
    } catch (e) {
      throw Exception('Ошибка разбора XML таблицы: $e');
    }
  }

  int _columnLettersToIndex(String cellRef) {
    final letters = cellRef.replaceAll(RegExp(r'[0-9]'), '').toUpperCase();
    if (letters.isEmpty) return 0;
    int col = 0;
    for (int i = 0; i < letters.length; i++) {
      col = col * 26 + (letters.codeUnitAt(i) - 64);
    }
    return col - 1;
  }

  String _extractGroqMessageText(Map? message) {
    if (message == null) return '';
    final content = message['content']?.toString().trim() ?? '';
    if (content.isNotEmpty) return content;
    final reasoning = message['reasoning']?.toString().trim() ?? '';
    return reasoning;
  }

  Future<String> _callGroqWithHistory({
    required String apiKey,
    required String model,
    required String systemInstruction,
    required dynamic messages,
    String? overrideLastUserText,
    File? imageFile,
    required double temperature,
  }) async {
    final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

    var formattedMessages = [];
    formattedMessages.add({'role': 'system', 'content': systemInstruction});

    var msgList = messages as List;
    final startMsgIdx = msgList.length > 6 ? (msgList.length - 6) : 0;

    for (int i = startMsgIdx; i < msgList.length; i++) {
      var msg = msgList[i] as ChatMessage;
      final isLastUser = (i == msgList.length - 1 && msg.role == 'user');
      final textToSend = (isLastUser && overrideLastUserText != null)
          ? overrideLastUserText
          : msg.text;

      if (isLastUser && imageFile != null) {
        final bytes = await imageFile.readAsBytes();
        final base64Img = base64Encode(bytes);
        formattedMessages.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': textToSend},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$base64Img'}
            }
          ]
        });
      } else {
        formattedMessages.add({
          'role': msg.role == 'user' ? 'user' : 'assistant',
          'content': textToSend
        });
      }
    }

    final Map<String, dynamic> payload = {
      'model': model,
      'temperature': temperature,
      'max_tokens': 2000,
      'messages': formattedMessages,
    };

    if (model.contains('gpt-oss')) {
      payload['reasoning_effort'] = 'low';
    }

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
    final text = _extractGroqMessageText(message);

    if (text.isEmpty) {
      throw Exception('Пустой ответ от модели.');
    }
    return text;
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

    final Map<String, dynamic> payload = {
      'model': model,
      'temperature': temperature,
      'max_tokens': 2500,
      'messages': [
        {'role': 'system', 'content': systemInstruction},
        {'role': 'user', 'content': userContent}
      ]
    };

    if (model.contains('gpt-oss')) {
      payload['reasoning_effort'] = 'low';
    }

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
    final text = _extractGroqMessageText(message);

    if (text.isEmpty) {
      throw Exception('Пустой ответ от модели.');
    }
    return text;
  }

  String _extractCsv(String text) {
    if (text.contains('```csv')) {
      final start = text.indexOf('```csv') + 6;
      final end = text.indexOf('```', start);
      if (end != -1) return text.substring(start, end).trim();
    } else if (text.contains('```')) {
      final start = text.indexOf('```') + 3;
      final end = text.indexOf('```', start);
      if (end != -1) return text.substring(start, end).trim();
    }
    return text.trim();
  }

  Future<void> _exportToFormattedExcel() async {
    final csvData = _lastCsvResult;
    if (csvData == null || csvData.isEmpty) {
      _showSnackbar('Нет данных CSV!');
      return;
    }

    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel['Посылка'];
      excel.delete('Sheet1');

      final lines = csvData.split('\n');
      for (int r = 0; r < lines.length; r++) {
        final line = lines[r].trim();
        if (line.isEmpty) continue;
        final cells = line.split(';');

        for (int c = 0; c < cells.length; c++) {
          final val = cells[c].trim();
          final cellIndex =
              ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);
          if (r > 0 && c >= 4 && c <= 6 && int.tryParse(val) != null) {
            sheet.cell(cellIndex).value = ex.IntCellValue(int.parse(val));
          } else {
            sheet.cell(cellIndex).value = ex.TextCellValue(val);
          }
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final filePath =
          '${dir.path}/Посылка_Сведение_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final fileBytes = excel.save();

      if (fileBytes != null) {
        final f = File(filePath);
        await f.writeAsBytes(fileBytes);
        _showSnackbar('Excel сохранен: $filePath');
        await OpenFilex.open(filePath);
      }
    } catch (e) {
      _showSnackbar('Ошибка выгрузки: $e');
    }
  }

  void _appendMessage(String role, String text, {String? imagePath, String? fileName}) {
    if (_currentSession == null) return;
    setState(() {
      var msgs = _currentSession!.messages as List;
      msgs.add(
        ChatMessage(
          role: role,
          text: text,
          imagePath: imagePath,
          fileName: fileName,
        ),
      );
      if (msgs.length == 2 && role == 'user') {
        _currentSession!.title =
            text.length > 20 ? '${text.substring(0, 20)}...' : text;
      }
    });
    _saveChats();
    _scrollToBottom();
  }

  void _showSnackbar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: const Color(0xFF1E293B),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawMessages = _currentSession?.messages as List? ?? [];

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BlackPocket AI',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: const [
                    Icon(Icons.bolt, color: Colors.greenAccent, size: 14),
                    SizedBox(width: 2),
                    Text(
                      'Онлайн',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isVoiceEnabled ? Icons.volume_up : Icons.volume_off,
              color: _isVoiceEnabled ? const Color(0xFF38BDF8) : Colors.white38,
            ),
            tooltip: _isVoiceEnabled ? 'Звук включен' : 'Звук выключен',
            onPressed: () async {
              final newVal = !_isVoiceEnabled;
              if (!newVal) {
                await _stopVoice();
              }
              setState(() {
                _isVoiceEnabled = newVal;
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('is_voice_enabled', newVal);
              _showSnackbar(newVal ? 'Автоозвучка включена' : 'Автоозвучка выключена');
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.white70),
            tooltip: 'История чатов',
            onPressed: () => _showChatsDrawer(context),
          ),
          IconButton(
            icon: Icon(
              _isLogisticsExpanded
                  ? Icons.inventory_2
                  : Icons.inventory_2_outlined,
              color: _isLogisticsExpanded
                  ? const Color(0xFF38BDF8)
                  : Colors.white70,
            ),
            tooltip: 'Модуль логистики',
            onPressed: () {
              setState(() {
                _isLogisticsExpanded = !_isLogisticsExpanded;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () => _showSettingsDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildLogisticsTopPanel(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              itemCount: rawMessages.length,
              itemBuilder: (context, idx) {
                final m = rawMessages[idx] as ChatMessage;
                final role = m.role;
                final isUser = role == 'user';
                final isSystem = role == 'system';
                final text = m.text;
                final imgPath = m.imagePath;
                final docName = m.fileName;

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
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
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
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
                        if (imgPath != null && File(imgPath).existsSync())
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                File(imgPath),
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        if (docName != null && docName.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8.0),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.insert_drive_file, size: 16, color: Colors.greenAccent),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    docName,
                                    style: const TextStyle(fontSize: 13, color: Colors.greenAccent, fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        SelectableText(
                          text,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        if (!isUser && !isSystem)
                          Align(
                            alignment: Alignment.bottomRight,
                            child: InkWell(
                              onTap: () => _speak(text, force: true),
                              child: const Padding(
                                padding: EdgeInsets.only(top: 8.0),
                                child: Icon(
                                  Icons.volume_up,
                                  size: 20,
                                  color: Color(0xFF38BDF8),
                                ),
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
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Гена думает...',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),
          _buildChatInputArea(),
        ],
      ),
    );
  }

  void _showChatsDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF131B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: const EdgeInsets.all(16),
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'История чатов',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Новый чат'),
                      onPressed: () {
                        _createNewChat();
                        Navigator.pop(ctx);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const Divider(color: Color(0xFF334155)),
                Expanded(
                  child: ListView.builder(
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index] as ChatSession;
                      final isSelected = session == _currentSession;
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF1E293B)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          title: Text(
                            session.title,
                            style: TextStyle(
                              fontSize: 15,
                              color: isSelected
                                  ? const Color(0xFF38BDF8)
                                  : Colors.white70,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _currentSession = session;
                            });
                            Navigator.pop(ctx);
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  size: 18,
                                  color: Colors.white54,
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _renameChat(session);
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () {
                                  _deleteChat(session);
                                  setModalState(() {});
                                  setState(() {});
                                },
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
          );
        },
      ),
    );
  }

  Widget _buildLogisticsTopPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF101726),
        border: Border(
          bottom: BorderSide(color: const Color(0xFF1E293B).withOpacity(0.8)),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isLogisticsExpanded = !_isLogisticsExpanded;
              });
            },
            child: Row(
              children: [
                const Icon(
                  Icons.local_shipping_outlined,
                  size: 18,
                  color: Color(0xFF38BDF8),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Сведение накладных (Посылка / Сводки)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const Spacer(),
                Icon(
                  _isLogisticsExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: Colors.white54,
                ),
              ],
            ),
          ),
          if (_isLogisticsExpanded) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _fileBtn(
                    label: _posylkaFile == null ? '1. Посылка' : 'Посылка: OK',
                    active: _posylkaFile != null,
                    onTap: () => _pickFile(1),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _fileBtn(
                    label: _svodkaPpFile == null ? '2. Сводка ПП' : 'Сводка ПП: OK',
                    active: _svodkaPpFile != null,
                    onTap: () => _pickFile(2),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _fileBtn(
                    label: _svodkaFilialFile == null ? '3. Филиал' : 'Филиал: OK',
                    active: _svodkaFilialFile != null,
                    onTap: () => _pickFile(3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text(
                      'СВЕСТИ НАКЛАДНУЮ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _isLoading ? null : _processLogistics,
                  ),
                ),
                if (_lastCsvResult != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.download),
                    tooltip: 'Скачать Excel',
                    onPressed: _exportToFormattedExcel,
                  )
                ]
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildChatInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF101726),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_chatImage != null)
              Container(
                alignment: Alignment.centerLeft,
                margin: const EdgeInsets.only(bottom: 8, left: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _chatImage!,
                        height: 60,
                        width: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => setState(() => _chatImage = null),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_chatAttachedFile != null)
              Container(
                alignment: Alignment.centerLeft,
                margin: const EdgeInsets.only(bottom: 8, left: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insert_drive_file, color: Colors.greenAccent, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _chatAttachedFile!.path.split(Platform.pathSeparator).last,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _chatAttachedFile = null),
                      child: const Icon(Icons.close, color: Colors.white70, size: 16),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.white70),
                  onPressed: _showAttachmentMenu,
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF182235),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF334155).withOpacity(0.5),
                      ),
                    ),
                    child: TextField(
                      focusNode: _inputFocusNode,
                      controller: _chatInputController,
                      maxLines: 4,
                      minLines: 1,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'Спроси или отправь фото/файл...',
                        hintStyle: TextStyle(
                          color: Colors.white38,
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
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
                    icon: const Icon(
                      Icons.arrow_upward,
                      color: Colors.white,
                      size: 20,
                    ),
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

  Widget _fileBtn({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: active ? Colors.greenAccent : Colors.grey,
        side: BorderSide(
          color: active ? Colors.greenAccent : Colors.grey.shade700,
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onTap,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isKeyWorking == true
                            ? Colors.greenAccent
                            : _isKeyWorking == false
                                ? Colors.redAccent
                                : Colors.orangeAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _apiStatus,
                      style: TextStyle(
                        fontSize: 13,
                        color: _isKeyWorking == true
                            ? Colors.greenAccent
                            : _isKeyWorking == false
                                ? Colors.redAccent
                                : Colors.orangeAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                const Text(
                  'Модель для обычного чата:',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  value: tempModel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
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
              ],
            ),
            actions: [
              TextButton(
                child: const Text('Отмена'),
                onPressed: () => Navigator.pop(ctx),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF38BDF8),
                  side: const BorderSide(color: Color(0xFF38BDF8)),
                ),
                child: _isKeyValidating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF38BDF8),
                        ),
                      )
                    : const Text('Проверить ключ'),
                onPressed: _isKeyValidating
                    ? null
                    : () async {
                        await _validateKeyOnly(_apiKeyController.text);
                        setDialogState(() {});
                      },
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                ),
                child: const Text('Сохранить'),
                onPressed: () {
                  _saveSettingsOnly(_apiKeyController.text, tempModel);
                  Navigator.pop(ctx);
                  setState(() {});
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
