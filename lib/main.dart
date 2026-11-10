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
import 'package:excel/excel.dart' as xl;

List<CameraDescription> _availableCameras = [];

const String _defaultApiKey = "";
const String _defaultModel = "gemini-3.6-flash";
const String _defaultEndpoint = "https://generativelanguage.googleapis.com/v1beta/models";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _availableCameras = await availableCameras();
  } catch (e) {
    debugPrint("Камера не найдена: $e");
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
    id: "excel_logist",
    name: "Логист / Разбор счетов (Excel)",
    description: "Авто-сведение: Посылка, Сводка Печатные платы и филиал",
    icon: Icons.table_chart_outlined,
    systemInstruction:
        "Ты — персональный эксперт-логист Александра по учету и отгрузке плат (ООО «Печатные платы» и ООО «ЭЛЕКТРОконнект», Москва). "
        "Александр передает файлы: «Посылка», «Сводка ООО Печатные платы» и «Сводка филиал». "
        "ТВОЙ АЛГОРИТМ РАБОТЫ (СТРОГО ПО АНАЛОГИИ С ВЕРХНИМИ СТРОКАМИ ПОСЫЛКИ): "
        "1. ИСХОДНЫЕ ДАННЫЕ: В файле «Посылка» в конце таблицы находится свежий приход (заполнены Фирма, PS, Сч/Н Новосибирска, Получено, Отгрузить!, а Счет пп и По счету пустые). "
        "2. СОПОСТАВЛЕНИЕ СО СВОДКАМИ (ПОИСК ПО PS ИЛИ ПО СВЯЗКЕ Сч/Н + ФИРМА): "
        "   - Найди каждую позицию в «Сводке Печатные платы» (для головных заказов) или в «Сводке филиал» (для филиала). "
        "   - ПОДТЯНИ 'Счет пп': извлеки московский номер счета. ОБЯЗАТЕЛЬНО сохраняй ведущие нули (например, 0585, 0643, 0441, 0615). Если счета в сводке нет — оставь пусто. "
        "   - ПОДТЯНИ 'По счету': найди исходный полный тираж заказа по счету/договору. Например: если в посылке получено 484 и отгрузить 484, а в сводке заказ на 500 — в колонку 'По счету' обязательно поставь 500! "
        "   - ПОДТЯНИ 'Доставка': определи способ доставки (Самовывоз, К, ДМ, СДЭК и т.д.). "
        "   - ПРОВЕРЬ 'ОТК': если в примечании, названии фирмы или сводке указан паспорт/ОТК — пропиши ОТК. "
        "3. РАЗДЕЛЕНИЕ НА БЛОКИ: "
        "   - Сначала выведи все головные заказы ООО «Печатные платы». "
        "   - В середине поставь разделительную строку: филиал;;;;;;;;; "
        "   - Затем выведи все заказы филиала (ЭЛЕКТРОконнект). "
        "4. ФОРМАТ ОТВЕТА: "
        "   В самом начале напиши краткую сводку: сколько позиций сведено (головных и филиала) и общую сумму штук к отгрузке. "
        "   Затем выведи итоговый реестр строго в одном блоке кода ```csv со столбцами: "
        "   Фирма;PS;Счет пп;Сч/Н;По счету;Получено;Отгрузить;ОТК;Примечание/Этикетка;Доставка",
  ),
  const AgentPreset(
    id: "companion",
    name: "Живой напарник",
    description: "Разговорный стиль, кратко, без воды",
    icon: Icons.chat_bubble_outline,
    systemInstruction:
        "Ты — BlackPocket, персональный живой ИИ-напарник Александра. "
        "Отвечай кратко, ёмко, по-живому, дружелюбно, без бюрократии.",
  ),
];

class AttachedDoc {
  final String fileName;
  final String content;

  AttachedDoc({required this.fileName, required this.content});

  Map<String, dynamic> toJson() => {'fileName': fileName, 'content': content};
  factory AttachedDoc.fromJson(Map<String, dynamic> json) =>
      AttachedDoc(fileName: json['fileName'] ?? '', content: json['content'] ?? '');
}

class ChatMessage {
  String text;
  final bool isUser;
  final String? imageBase64;
  final List<String> fileNames;
  String? modelUsed;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.imageBase64,
    List<String>? fileNames,
    this.modelUsed,
    DateTime? timestamp,
  })  : fileNames = fileNames ?? [],
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'imageBase64': imageBase64,
        'fileNames': fileNames,
        'modelUsed': modelUsed,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'] ?? '',
        isUser: json['isUser'] ?? false,
        imageBase64: json['imageBase64'],
        fileNames: (json['fileNames'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
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
  String _targetRussianLocaleId = "ru-RU";
  bool _russianLocaleConfirmed = false;

  String? _selectedImageBase64;
  final List<AttachedDoc> _attachedDocs = [];

  String _apiKey = _defaultApiKey;
  String _modelName = _defaultModel;
  String _apiEndpoint = _defaultEndpoint;
  String _selectedAgentId = "excel_logist";

  String _memoryFacts =
      "Пользователя зовут Александр (Шурик). "
      "Он логист в Москве по учету печатных плат (ООО «Печатные платы» и ООО «ЭЛЕКТРОконнект»). "
      "Сводит накладные «Посылка» со «Сводками». Отвечай емко, строго следуй данным из таблиц.";

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
      debugPrint("Камера не найдена: $e");
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
    bool available = await _speech.initialize(
      onError: (val) => debugPrint("Ошибка STT: $val"),
      onStatus: (status) {
        if (status == 'notListening' && _isListening) {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );

    if (available) {
      try {
        final locales = await _speech.locales();
        for (final loc in locales) {
          final normalized = loc.localeId.toLowerCase().replaceAll('_', '-');
          if (normalized == 'ru-ru' || normalized.startsWith('ru')) {
            _targetRussianLocaleId = loc.localeId;
            _russianLocaleConfirmed = true;
            break;
          }
        }
      } catch (_) {
        _targetRussianLocaleId = "ru-RU";
      }
    }
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
    if (migrationTag != 'v31_perfect_logist') {
      await prefs.setString('bp_clean_migration', 'v31_perfect_logist');
      await prefs.setString('modelName', 'gemini-3.6-flash');
    }

    setState(() {
      _apiKey = prefs.getString('apiKey') ?? _defaultApiKey;
      _modelName = prefs.getString('modelName') ?? _defaultModel;
      if (_modelName.contains('1.5') || _modelName.contains('lite')) {
        _modelName = 'gemini-3.6-flash';
      }
      _apiEndpoint = prefs.getString('apiEndpoint') ?? _defaultEndpoint;
      _selectedAgentId = prefs.getString('selectedAgentId') ?? "excel_logist";
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

  void _copyToClipboard(String text, [String notify = 'Скопировано в буфер']) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(notify),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF1E293B),
      ),
    );
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

    if (!_speech.isAvailable) {
      await _initSpeechRecognizer();
    }

    if (mounted) {
      HapticFeedback.lightImpact();
      setState(() => _isListening = true);

      final statusMsg = _russianLocaleConfirmed
          ? '🎤 Слушаю (Русский: $_targetRussianLocaleId)...'
          : '⚠️ Внимание: Используй микрофон клавиатуры!';

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(statusMsg),
          duration: const Duration(seconds: 2),
          backgroundColor: _russianLocaleConfirmed ? const Color(0xFF1E293B) : Colors.red.shade900,
        ),
      );

      _speech.listen(
        localeId: _targetRussianLocaleId,
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        pauseFor: const Duration(seconds: 2),
        listenFor: const Duration(seconds: 30),
        onResult: (val) {
          final words = val.recognizedWords.trim();
          _inputController.text = words;

          final lower = words.toLowerCase();
          if (lower == 'стоп' ||
              lower == 'хватит' ||
              lower == 'замолчи' ||
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

  String _parseExcelFile(List<int> bytes) {
    try {
      final excel = xl.Excel.decodeBytes(bytes);
      final buffer = StringBuffer();

      for (final table in excel.tables.keys) {
        if (table.toLowerCase().contains('диаграмм') || table.toLowerCase().contains('chart')) {
          continue;
        }

        final currentSheet = excel.tables[table];
        if (currentSheet == null || currentSheet.rows.isEmpty) continue;

        buffer.writeln("[ЛИСТ: $table]");

        final allRows = currentSheet.rows;
        List<List<xl.Data?>> targetRows = [];

        if (allRows.length > 120) {
          targetRows.addAll(allRows.take(10));
          targetRows.addAll(allRows.skip(allRows.length - 80));
        } else {
          targetRows = allRows;
        }

        for (final row in targetRows) {
          final List<String> rowValues = [];
          for (final cell in row) {
            if (cell == null || cell.value == null) {
              rowValues.add('');
            } else {
              rowValues.add(cell.value.toString().trim());
            }
          }

          if (rowValues.every((val) => val.isEmpty)) continue;
          buffer.writeln(rowValues.join(" | "));
        }
        buffer.writeln();
      }

      final result = buffer.toString().trim();
      return result.isEmpty ? "(Таблица пустая)" : result;
    } catch (e) {
      debugPrint("Сбой декодирования Excel: $e");
      return "(Ошибка разбора файла: $e)";
    }
  }

  Future<void> _pickMultipleFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv', 'tsv', 'txt', 'log', 'json', 'py', 'dart', 'yaml', 'md'],
      );

      if (result != null && result.files.isNotEmpty) {
        HapticFeedback.selectionClick();
        int addedCount = 0;

        for (final f in result.files) {
          if (f.path == null) continue;
          final fileName = f.name;
          final ext = fileName.split('.').last.toLowerCase();
          String parsedContent = '';

          if (ext == 'xlsx' || ext == 'xls') {
            final bytes = await File(f.path!).readAsBytes();
            parsedContent = _parseExcelFile(bytes);
          } else {
            parsedContent = await File(f.path!).readAsString();
          }

          _attachedDocs.add(AttachedDoc(fileName: fileName, content: parsedContent));
          addedCount++;
        }

        setState(() {});

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📊 Загружено файлов: $addedCount'),
            backgroundColor: const Color(0xFF1E293B),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Ошибка чтения файлов: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка обработки файлов: $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _saveCodeToFile(String codeSnippet, [String defaultExt = "xlsx"]) async {
    try {
      HapticFeedback.mediumImpact();
      final downloadsDir = Directory('/storage/emulated/0/Download');
      final targetDir = await downloadsDir.exists() ? downloadsDir : Directory.systemTemp;

      final excel = xl.Excel.createExcel();
      final sheetName = excel.getDefaultSheet() ?? 'Лист1';
      final sheet = excel[sheetName];

      final lines = const LineSplitter().convert(codeSnippet.trim());
      int rowIdx = 0;

      final blackBorder = xl.Border(borderStyle: xl.BorderStyle.Thin, borderColorHex: xl.ExcelColor.fromHexString('#000000'));
      final whiteColor = xl.ExcelColor.fromHexString('#FFFFFF');

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (RegExp(r'^\|?\s*[-:]+[-|\s:]*$').hasMatch(trimmed)) continue;

        List<String> cells = [];
        if (trimmed.contains(';')) {
          cells = trimmed.split(';').map((c) => c.trim()).toList();
        } else if (trimmed.contains('|')) {
          cells = trimmed.split('|').map((c) => c.trim()).toList();
          if (cells.isNotEmpty && cells.first.isEmpty) cells.removeAt(0);
          if (cells.isNotEmpty && cells.last.isEmpty) cells.removeLast();
        } else if (trimmed.contains('\t')) {
          cells = trimmed.split('\t').map((c) => c.trim()).toList();
        } else {
          cells = trimmed.split(',').map((c) => c.trim()).toList();
        }

        final bool isHeader = rowIdx == 0;
        final bool isFilialRow = cells.isNotEmpty && cells[0].toLowerCase().contains('филиал');
        final bool isSamovyvozRow = cells.any((c) => c.toLowerCase().contains('самовывоз'));

        for (int colIdx = 0; colIdx < cells.length; colIdx++) {
          final cellValue = cells[colIdx];
          final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: colIdx, rowIndex: rowIdx));

          final cleanNumStr = cellValue.replaceAll(' ', '').replaceAll(',', '.');
          final numVal = num.tryParse(cleanNumStr);
          if (colIdx != 2 && numVal != null && !cellValue.startsWith('0') && cellValue.length < 11 && !isHeader) {
            cell.value = xl.IntCellValue(numVal.toInt());
          } else {
            cell.value = xl.TextCellValue(cellValue);
          }

          xl.HorizontalAlign align = xl.HorizontalAlign.Center;
          if (colIdx == 0 && !isFilialRow) {
            align = xl.HorizontalAlign.Left;
          }

          final int fontSize = (colIdx == 0 || isHeader) ? 18 : 16;
          xl.ExcelColor fontColor = xl.ExcelColor.black;
          xl.ExcelColor bgColor = whiteColor;

          if (isFilialRow) {
            if (colIdx == 0) {
              bgColor = xl.ExcelColor.fromHexString('#B91C1C');
            }
          } else if (isSamovyvozRow) {
            bgColor = xl.ExcelColor.fromHexString('#F59E0B');
            if (colIdx == 6 || colIdx == 9) {
              fontColor = xl.ExcelColor.fromHexString('#CC0000');
            }
          } else if (!isHeader) {
            if (colIdx == 6) {
              fontColor = xl.ExcelColor.fromHexString('#CC0000');
            }
            if (colIdx == 7 && cellValue.toUpperCase().contains('ОТК')) {
              fontColor = xl.ExcelColor.fromHexString('#0044CC');
            }
            if (colIdx == 9) {
              final valUp = cellValue.toUpperCase();
              if (valUp == 'К' || valUp == 'ДМ' || valUp.contains('САМОВЫВОЗ')) {
                fontColor = xl.ExcelColor.fromHexString('#CC0000');
              }
            }
            if (colIdx == 8 && cellValue.isNotEmpty) {
              bgColor = xl.ExcelColor.fromHexString('#FCE7F3');
            }
          }

          cell.cellStyle = xl.CellStyle(
            fontFamily: 'Tahoma',
            fontSize: fontSize,
            bold: true,
            fontColorHex: fontColor,
            backgroundColorHex: bgColor,
            horizontalAlign: align,
            verticalAlign: xl.VerticalAlign.Center,
            leftBorder: blackBorder,
            rightBorder: blackBorder,
            topBorder: blackBorder,
            bottomBorder: blackBorder,
          );
        }
        rowIdx++;
      }

      final fileBytes = excel.save();
      if (fileBytes != null) {
        final fileName = "Посылка_Сводка_${DateTime.now().millisecondsSinceEpoch}.xlsx";
        final file = File('${targetDir.path}/$fileName');
        await file.writeAsBytes(fileBytes);
        _showSavedToast(fileName);
      }
    } catch (e) {
      debugPrint("Ошибка сохранения Excel: $e");
      _copyToClipboard(codeSnippet, 'Скопировано в буфер (ошибка сохранения)');
    }
  }

  void _showSavedToast(String fileName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📊 Таблица Excel сохранена: $fileName'),
        backgroundColor: Colors.green.shade800,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _renameSession(String id, String currentTitle) {
    final titleController = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2128),
        title: const Text('Переименовать тему'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название диалога',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              final newName = titleController.text.trim();
              if (newName.isNotEmpty) {
                HapticFeedback.selectionClick();
                setState(() {
                  final s = _sessions.firstWhere((sess) => sess.id == id);
                  s.title = newName;
                });
                _saveData();
              }
              Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  dynamic _buildContentsHistory(dynamic historyList, dynamic currentParts) {
    final resultList = [];
    final dynamic history = (historyList is List) ? historyList : [];

    final int startIdx = history.length > 6 ? history.length - 6 : 0;
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

  Future<void> _handleSend([String? forcedText]) async {
    final text = (forcedText ?? _inputController.text).trim();
    if (text.isEmpty && _selectedImageBase64 == null && _attachedDocs.isEmpty && !_isLiveActive) return;
    if (_isLoading) return;

    final lower = text.toLowerCase();
    if (lower == 'стоп' || lower == 'хватит' || lower == 'замолчи' || lower.contains('стоп')) {
      await _stopSpeaking();
      _inputController.clear();
      return;
    }

    HapticFeedback.lightImpact();
    _stopListening();

    String? imageToSend = _selectedImageBase64;
    final List<AttachedDoc> docsToSend = List.from(_attachedDocs);

    _selectedImageBase64 = null;
    _attachedDocs.clear();

    final session = _activeSession;
    final botMessage = ChatMessage(text: '', isUser: false, modelUsed: _modelName);
    final previousHistory = session.messages.toList();

    final displayPrompt = text;
    final sentFileNames = docsToSend.map((d) => d.fileName).toList();

    setState(() {
      session.messages.add(ChatMessage(
        text: displayPrompt,
        isUser: true,
        imageBase64: imageToSend,
        fileNames: sentFileNames,
      ));
      session.messages.add(botMessage);

      if (session.title == "Новый чат") {
        if (displayPrompt.isNotEmpty) {
          session.title = displayPrompt.length > 26 ? "${displayPrompt.substring(0, 26)}..." : displayPrompt;
        } else if (sentFileNames.isNotEmpty) {
          session.title = "Файлы: ${sentFileNames.first}";
        }
      }
      _isLoading = true;
      _inputController.clear();
    });
    _saveData();
    _scrollToBottom();

    try {
      final buffer = StringBuffer();
      if (text.isNotEmpty) {
        buffer.writeln(text);
      }

      if (docsToSend.isNotEmpty) {
        buffer.writeln("\n[ПРИКРЕПЛЕННЫЕ ТАБЛИЦЫ]:");
        for (final doc in docsToSend) {
          buffer.writeln("\n--- ФАЙЛ: ${doc.fileName} ---");
          buffer.writeln(doc.content);
        }
      }

      final combinedSystemPrompt =
          "${_currentAgent.systemInstruction}\n\n[ПАМЯТЬ АССИСТЕНТА]:\n$_memoryFacts";

      String finalInstruction = buffer.toString().trim();
      if (text.isEmpty && docsToSend.isNotEmpty) {
        finalInstruction =
            "Сведи накладные (${sentFileNames.join(', ')}): возьми свежие данные из Посылки, сверь со Сводками, "
            "размести филиал под строку-разделитель 'филиал', сохрани ведущие нули в счетах ПП и выдай CSV внутри ```csv.";
      } else if (finalInstruction.isEmpty) {
        finalInstruction = "Слушаю вас.";
      }

      final currentParts = [];
      currentParts.add({"text": finalInstruction});

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

      // ТОЛЬКО ДЕЙСТВУЮЩИЕ И МОЩНЫЕ МОДЕЛИ GOOGLE API
      final modelsQueue = [
        "gemini-3.6-flash",
        "gemini-2.5-flash",
      ];

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
              },
              "generationConfig": {
                "temperature": 0.0,
                "topP": 0.95
              }
            });

            final client = http.Client();
            final streamedResponse = await client.send(request).timeout(const Duration(seconds: 35));

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
        setState(() {
          botMessage.text = "Связь с сервером прервалась. Проверь VPN.";
        });
      }
    } catch (e) {
      setState(() {
        botMessage.text = "Сбой соединения: $e";
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
      _attachedDocs.clear();
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
              'Факты об Александре (без кода и лишних знаков):',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: memCtrl,
              maxLines: 5,
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
                    labelText: 'Основная модель (gemini-3.6-flash)',
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

  List<String> _extractCodeBlocks(String markdown) {
    final reg = RegExp(r'```(?:[a-zA-Z0-9_\-]+)?\n([\s\S]*?)```');
    return reg.allMatches(markdown).map((m) => m.group(1)?.trim() ?? '').where((s) => s.isNotEmpty).toList();
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
                colors: [Color(0xFF030508), Color(0xFF070B14), Color(0xFF0A142B)],
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
                          padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 100),
                          itemCount: messages.length,
                          itemBuilder: (context, idx) {
                            final m = messages[idx];
                            final codeBlocks = !m.isUser ? _extractCodeBlocks(m.text) : <String>[];

                            return Align(
                              alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: GestureDetector(
                                onLongPress: () {
                                  if (m.text.isNotEmpty) {
                                    _copyToClipboard(m.text, m.isUser ? 'Ваш запрос скопирован' : 'Ответ скопирован');
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
                                  decoration: BoxDecoration(
                                    color: m.isUser ? const Color(0xFF1E293B) : const Color(0xFF111827),
                                    borderRadius: BorderRadius.circular(20),
                                    border: m.isUser ? null : Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (m.fileNames.isNotEmpty)
                                        Padding(
                                          padding: EdgeInsets.only(bottom: m.text.isNotEmpty ? 6 : 0),
                                          child: Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: m.fileNames.map((fName) {
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.greenAccent.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.table_chart_outlined, size: 14, color: Colors.greenAccent),
                                                    const SizedBox(width: 4),
                                                    Text(fName, style: const TextStyle(fontSize: 12, color: Colors.greenAccent)),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      if (m.isUser)
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            if (m.text.isNotEmpty)
                                              SelectableText(
                                                m.text,
                                                style: const TextStyle(fontSize: 16, color: Colors.white),
                                              ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.copy_outlined, size: 16, color: Colors.white38),
                                                  tooltip: 'Скопировать',
                                                  constraints: const BoxConstraints(),
                                                  padding: const EdgeInsets.only(top: 6, left: 6),
                                                  onPressed: () => _copyToClipboard(m.text, 'Запрос скопирован'),
                                                ),
                                              ],
                                            ),
                                          ],
                                        )
                                      else
                                        MarkdownBody(
                                          data: m.text.isEmpty && _isLoading ? '...' : m.text,
                                          selectable: true,
                                          styleSheet: MarkdownStyleSheet(
                                            p: const TextStyle(fontSize: 16, color: Color(0xFFE2E8F0), height: 1.45),
                                            code: const TextStyle(
                                              backgroundColor: Color(0xFF1E293B),
                                              color: Color(0xFF38BDF8),
                                              fontFamily: 'monospace',
                                              fontSize: 13,
                                            ),
                                            codeblockPadding: const EdgeInsets.all(12),
                                            codeblockDecoration: BoxDecoration(
                                              color: const Color(0xFF0F172A),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.white12),
                                            ),
                                          ),
                                        ),

                                      if (!m.isUser && codeBlocks.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Wrap(
                                            spacing: 8,
                                            children: codeBlocks.map((code) {
                                              return ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF1E293B),
                                                  foregroundColor: Colors.greenAccent,
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                                icon: const Icon(Icons.download_for_offline_outlined, size: 18),
                                                label: const Text('Сохранить файл', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                onPressed: () => _saveCodeToFile(code),
                                              );
                                            }).toList(),
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
                                              tooltip: 'Скопировать ответ',
                                              onPressed: () => _copyToClipboard(m.text, 'Ответ скопирован'),
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
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          if (_attachedDocs.isNotEmpty)
            Positioned(
              bottom: 95,
              left: 18,
              right: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _attachedDocs.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final doc = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.table_chart_outlined, size: 16, color: Colors.greenAccent),
                            const SizedBox(width: 6),
                            Text(doc.fileName, style: const TextStyle(fontSize: 12, color: Colors.white)),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => setState(() => _attachedDocs.removeAt(idx)),
                              child: const Icon(Icons.close, size: 16, color: Colors.white54),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

          Positioned(
            left: 18,
            right: 18,
            bottom: 20,
            child: _buildGeminiPillBar(),
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
          const SizedBox(width: 4),
          Text(_currentAgent.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
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
        children: const [
          Icon(Icons.auto_awesome, size: 64, color: Colors.blueAccent),
          SizedBox(height: 24),
          Text(
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
    final bool hasContent = _inputController.text.trim().isNotEmpty || _attachedDocs.isNotEmpty;

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2128),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white70, size: 26),
            onPressed: _pickMultipleFiles,
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
              }
            },
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFF1D4ED8),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_upward, color: Colors.white, size: 22),
            ),
          ),
        ],
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

            const Divider(color: Colors.white12, height: 20),

            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _sessions.length,
                itemBuilder: (context, idx) {
                  final s = _sessions[idx];
                  final isCurrent = s.id == _currentSessionId;
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 16, right: 8),
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.white54),
                          onPressed: () => _renameSession(s.id, s.title),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.white38),
                          onPressed: () => _deleteSession(s.id),
                        ),
                      ],
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
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white12))),
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
                  const Text('ALEKSANDR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
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
}
