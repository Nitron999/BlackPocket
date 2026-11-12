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
  runApp(const PechatnyePlatyApp());
}

class PechatnyePlatyApp extends StatelessWidget {
  const PechatnyePlatyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Печатные платы',
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

class _LogisticsItem {
  String firm;
  String ps;
  String schetPp;
  String schN;
  String poSchetu;
  String polucheno;
  String otgruzit;
  String etiketka;
  String naSklade;
  String dolg;
  String dostavka;
  String raskhodnaya;
  String major;
  bool isFilial;

  _LogisticsItem({
    required this.firm,
    required this.ps,
    required this.schetPp,
    required this.schN,
    required this.poSchetu,
    required this.polucheno,
    required this.otgruzit,
    required this.etiketka,
    this.naSklade = '',
    this.dolg = '',
    required this.dostavka,
    this.raskhodnaya = '',
    this.major = '',
    required this.isFilial,
  });

  List<String> toRowCells() => [
        firm,
        ps,
        schetPp,
        schN,
        poSchetu,
        polucheno,
        otgruzit,
        etiketka,
        naSklade,
        dolg,
        dostavka,
        raskhodnaya,
        major,
      ];
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
  String _lastOtpravkaHeader = '';

  final _availableModels = [
    'qwen/qwen3.8-27b',
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'llama-3.2-11b-vision-preview',
  ];

  String _selectedModel = 'qwen/qwen3.8-27b';

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
    final savedModel = prefs.getString('groq_model') ?? 'qwen/qwen3.8-27b';
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
      final url = Uri.https('api.groq.com', '/openai/v1/models');
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

  // =========================================================================
  // ПРЯМОЙ АВТОНОМНЫЙ АЛГОРИТМ СВЕДЕНИЯ НАКЛАДНЫХ (БЕЗ ОГРАНИЧЕНИЙ ТОКЕНОВ)
  // =========================================================================

  String _cleanNumStr(String raw) {
    final trimmed = raw.trim();
    if (trimmed.endsWith('.0')) {
      return trimmed.substring(0, trimmed.length - 2);
    }
    return trimmed;
  }

  String _extractDigitsOnly(String raw) {
    final match = RegExp(r'\d+').firstMatch(raw.trim());
    return match?.group(0) ?? '';
  }

  bool _isOtpravkaHeaderCell(String text) {
    final up = text
        .toUpperCase()
        .replaceAll('O', 'О')
        .replaceAll('T', 'Т')
        .replaceAll('P', 'Р')
        .replaceAll('A', 'А')
        .replaceAll('B', 'В')
        .replaceAll('K', 'К')
        .replaceAll('H', 'Н')
        .replaceAll('X', 'Х');
    return up.contains('ОТПРАВК') || up.contains('ПРИХОД');
  }

  String _mapDeliveryKeyword(String rawText) {
    final low = rawText.toLowerCase();
    if (low.contains('доставка москва') || low == 'дм') return 'ДМ';
    if (low.contains('сдэк')) return 'СДЭК';
    if (low.contains('самовывоз')) return 'Самовывоз';
    if (low.contains('курьер') || low == 'к') return 'К';
    return '';
  }

  int _deliverySortWeight(String delivery) {
    switch (delivery.trim().toUpperCase()) {
      case 'ДМ':
        return 1;
      case 'СДЭК':
        return 2;
      case 'К':
        return 3;
      case 'САМОВЫВОЗ':
        return 4;
      default:
        return 5;
    }
  }

  Future<void> _processLogistics() async {
    final posFile = _posylkaFile;
    if (posFile == null || !posFile.existsSync()) {
      _showSnackbar('Выберите файл Посылки!');
      return;
    }

    setState(() {
      _isLoading = true;
      _lastCsvResult = null;
      _lastOtpravkaHeader = '';
    });

    final fileName = posFile.path.split(Platform.pathSeparator).last;
    _appendMessage(
      'user',
      '📦 Прямое сведение накладной (авто-движок без лимитов): $fileName',
    );

    try {
      final posRows = await _extractSheetMatrix(posFile, preferredSheetName: 'Посылка', maxCols: 14);
      if (posRows.isEmpty) {
        throw Exception('Лист "Посылка" пуст или не найден.');
      }

      int startRowIdx = 0;
      for (int i = posRows.length - 1; i >= 0; i--) {
        final rowJoined = posRows[i].join(' ');
        if (_isOtpravkaHeaderCell(rowJoined)) {
          startRowIdx = i;
          for (final cell in posRows[i]) {
            if (_isOtpravkaHeaderCell(cell)) {
              _lastOtpravkaHeader = cell.trim();
              break;
            }
          }
          break;
        }
      }

      final headItems = <_LogisticsItem>[];
      final filialItems = <_LogisticsItem>[];
      bool inFilial = false;

      for (int i = startRowIdx + 1; i < posRows.length; i++) {
        final r = posRows[i];
        final c0 = r.isNotEmpty ? r[0].trim() : '';
        final c1 = r.length > 1 ? _cleanNumStr(r[1]) : '';
        final c2 = r.length > 2 ? r[2].trim() : '';
        final c3 = r.length > 3 ? _cleanNumStr(r[3]) : '';
        final c4 = r.length > 4 ? _cleanNumStr(r[4]) : '';
        final c5 = r.length > 5 ? _cleanNumStr(r[5]) : '';
        final c6 = r.length > 6 ? _cleanNumStr(r[6]) : '';
        final c7 = r.length > 7 ? r[7].trim() : '';
        final c8 = r.length > 8 ? r[8].trim() : '';
        final c9 = r.length > 9 ? r[9].trim() : '';
        final c10 = r.length > 10 ? r[10].trim() : '';
        final c11 = r.length > 11 ? r[11].trim() : '';
        final c12 = r.length > 12 ? r[12].trim() : '';

        if (c0.toLowerCase() == 'филиал') {
          inFilial = true;
          continue;
        }

        if (c1.isEmpty && c3.isEmpty) continue;

        final item = _LogisticsItem(
          firm: c0,
          ps: c1,
          schetPp: c2,
          schN: c3,
          poSchetu: c4,
          polucheno: c5.isNotEmpty ? c5 : c4,
          otgruzit: c6.isNotEmpty ? c6 : (c5.isNotEmpty ? c5 : c4),
          etiketka: c7,
          naSklade: c8,
          dolg: c9,
          dostavka: c10,
          raskhodnaya: c11,
          major: c12,
          isFilial: inFilial,
        );

        if (inFilial) {
          filialItems.add(item);
        } else {
          headItems.add(item);
        }
      }

      // Индексируем Сводку ПП
      final Map<String, Map<String, String>> ppByPs = {};
      if (_svodkaPpFile != null && _svodkaPpFile!.existsSync()) {
        final ppRows = await _extractSheetMatrix(_svodkaPpFile!, preferredSheetName: 'СВОДКА', maxCols: 16);
        String currentMoscowSchet = '';
        String currentFirm = '';
        String currentDelivery = '';

        for (int i = 3; i < ppRows.length; i++) {
          final r = ppRows[i];
          final colA = r.isNotEmpty ? r[0].trim() : '';
          final psVal = r.length > 2 ? _cleanNumStr(r[2]) : '';
          final qtyVal = r.length > 4 ? _cleanNumStr(r[4]) : '';
          final moscowVal = r.length > 12 ? r[12].trim() : '';
          final colN = r.length > 13 ? _cleanNumStr(r[13]) : '';
          final firmVal = r.length > 14 ? r[14].trim() : '';

          if (colA.isNotEmpty || firmVal.isNotEmpty) {
            if (moscowVal.isNotEmpty && RegExp(r'^\d+$').hasMatch(moscowVal)) {
              currentMoscowSchet = moscowVal;
            } else if (colA.isNotEmpty && moscowVal.isEmpty) {
              currentMoscowSchet = '';
            }
            if (firmVal.isNotEmpty && !firmVal.toLowerCase().startsWith('заявка')) {
              currentFirm = firmVal;
            }
            currentDelivery = '';
          }

          for (final cell in r) {
            final mapped = _mapDeliveryKeyword(cell);
            if (mapped.isNotEmpty) {
              currentDelivery = mapped;
            }
          }

          if (psVal.isNotEmpty && RegExp(r'^\d{5,}$').hasMatch(psVal)) {
            ppByPs[psVal] = {
              'firm': currentFirm,
              'schetPp': currentMoscowSchet,
              'poSchetu': qtyVal,
              'schn': RegExp(r'^\d+$').hasMatch(colN) ? colN : '',
              'dostavka': currentDelivery,
            };
          }
        }
      }

      // Индексируем Сводку Филиал
      final Map<String, Map<String, String>> filBySchnPs = {};
      final Map<String, Map<String, String>> filByPs = {};

      if (_svodkaFilialFile != null && _svodkaFilialFile!.existsSync()) {
        final filRows = await _extractSheetMatrix(_svodkaFilialFile!, preferredSheetName: 'ФИЛИАЛ', maxCols: 16);
        String currentSchn = '';
        String currentFirm = '';
        String currentDelivery = '';

        for (int i = 5; i < filRows.length; i++) {
          final r = filRows[i];
          final colA = r.isNotEmpty ? _cleanNumStr(r[0]) : '';
          final colB = r.length > 1 ? r[1].trim() : '';
          final psVal = r.length > 4 ? _cleanNumStr(r[4]) : '';
          final qtyVal = r.length > 7 ? _cleanNumStr(r[7]) : '';

          final extractedSchn = _extractDigitsOnly(colA);
          if (extractedSchn.isNotEmpty && extractedSchn.length >= 4 && extractedSchn.length <= 6) {
            currentSchn = extractedSchn;
            if (colB.isNotEmpty) {
              currentFirm = colB;
            }
            currentDelivery = '';
          }

          if (colB.isNotEmpty) {
            final mapped = _mapDeliveryKeyword(colB);
            if (mapped.isNotEmpty) {
              currentDelivery = mapped;
              if (currentSchn.isNotEmpty) {
                for (final entry in filBySchnPs.entries) {
                  if (entry.key.startsWith('${currentSchn}_') &&
                      (entry.value['dostavka'] ?? '').isEmpty) {
                    entry.value['dostavka'] = currentDelivery;
                  }
                }
              }
            }
          }

          if (psVal.isNotEmpty && RegExp(r'^\d{5,}$').hasMatch(psVal)) {
            final record = {
              'firm': currentFirm,
              'schn': currentSchn,
              'poSchetu': qtyVal,
              'dostavka': currentDelivery,
            };
            if (currentSchn.isNotEmpty) {
              filBySchnPs['${currentSchn}_$psVal'] = record;
            }
            filByPs[psVal] = record;
          }
        }
      }

      // Заполняем блок "Голова"
      for (final item in headItems) {
        final info = ppByPs[item.ps];
        if (info != null) {
          if (item.firm.isEmpty && (info['firm'] ?? '').isNotEmpty) {
            item.firm = info['firm']!;
          }
          if (item.schetPp.isEmpty && (info['schetPp'] ?? '').isNotEmpty) {
            item.schetPp = info['schetPp']!;
          }
          if ((info['poSchetu'] ?? '').isNotEmpty) {
            item.poSchetu = info['poSchetu']!;
          }
          if (item.dostavka.isEmpty && (info['dostavka'] ?? '').isNotEmpty) {
            item.dostavka = info['dostavka']!;
          }
        }
        if (item.poSchetu.isEmpty) {
          item.poSchetu = item.polucheno.isNotEmpty ? item.polucheno : item.otgruzit;
        }
        item.etiketka = 'ОТК';
        if (item.dostavka.isEmpty) {
          final fLow = item.firm.toLowerCase();
          if (fLow.contains('авэкс') || fLow.contains('марс')) {
            item.dostavka = 'ДМ';
          } else if (fLow.contains('внииа')) {
            item.dostavka = 'Самовывоз';
          } else {
            item.dostavka = 'К';
          }
        }
      }

      // Заполняем блок "Филиал"
      for (final item in filialItems) {
        item.schetPp = '';
        item.etiketka = '';

        final cleanSchn = _extractDigitsOnly(item.schN);
        final info = filBySchnPs['${cleanSchn}_${item.ps}'] ??
            filBySchnPs['${item.schN}_${item.ps}'] ??
            filByPs[item.ps];

        if (info != null) {
          if ((info['poSchetu'] ?? '').isNotEmpty) {
            item.poSchetu = info['poSchetu']!;
          }
          if (item.dostavka.isEmpty && (info['dostavka'] ?? '').isNotEmpty) {
            item.dostavka = info['dostavka']!;
          }
        }

        // Если в сводке не нашлось По счету — подставляем из Получено (например, 1)
        if (item.poSchetu.isEmpty) {
          item.poSchetu = item.polucheno.isNotEmpty ? item.polucheno : item.otgruzit;
        }

        final fLow = item.firm.toLowerCase();
        if (fLow.contains('нейрософт') || fLow.contains('кузьминский')) {
          item.dostavka = 'К';
        } else if (fLow.contains('атб-электроника') || fLow.contains('атб электроника')) {
          item.dostavka = 'ДМ';
        } else if (item.dostavka.isEmpty) {
          item.dostavka = 'К';
        }
      }

      // Сортируем внутри каждого блока: ДМ -> СДЭК -> К -> Самовывоз
      headItems.sort((a, b) =>
          _deliverySortWeight(a.dostavka).compareTo(_deliverySortWeight(b.dostavka)));
      filialItems.sort((a, b) =>
          _deliverySortWeight(a.dostavka).compareTo(_deliverySortWeight(b.dostavka)));

      final csvBuffer = StringBuffer();
      csvBuffer.writeln(
          'Фирма;PS;Счет пп;Сч/Н;По счету;Получено;Отгрузить!;Этикетка;на складе!;долг;Доставка;Расходная накладная;Major');

      for (final item in headItems) {
        csvBuffer.writeln(item.toRowCells().join(';'));
      }

      if (filialItems.isNotEmpty) {
        csvBuffer.writeln('филиал;;;;;;;;;;;;');
        for (final item in filialItems) {
          csvBuffer.writeln(item.toRowCells().join(';'));
        }
      }

      final finalCsv = csvBuffer.toString().trim();
      setState(() {
        _lastCsvResult = finalCsv;
      });

      final summaryMsg = '''
✅ Накладная сведена автоматически!
${_lastOtpravkaHeader.isNotEmpty ? '📅 Блок: $_lastOtpravkaHeader\n' : ''}• Голова (ООО «Печатные платы»): ${headItems.length} поз.
• Филиал (ЭЛЕКТРОконнект): ${filialItems.length} поз.

Нажми зелёную кнопку скачивания справа сверху, чтобы открыть готовый оформленный Excel.

```csv
$finalCsv
```''';

      _appendMessage('assistant', summaryMsg);
      await _speak(
          'Накладная успешно сведена, Шурик! Голова: ${headItems.length}, филиал: ${filialItems.length}.');
    } catch (e) {
      _appendMessage('system', 'Ошибка сведения: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<List<List<String>>> _extractSheetMatrix(
    File file, {
    String? preferredSheetName,
    int maxCols = 16,
  }) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    List<String> sharedStrings = [];
    final sharedStringsFile = archive.findFile('xl/sharedStrings.xml');
    if (sharedStringsFile != null) {
      final xmlStr =
          utf8.decode(sharedStringsFile.content as List<int>, allowMalformed: true);
      final document = XmlDocument.parse(xmlStr);
      for (final si in document.findAllElements('si')) {
        final textBuffer = StringBuffer();
        for (final t in si.findAllElements('t')) {
          textBuffer.write(t.innerText);
        }
        sharedStrings.add(
            textBuffer.toString().replaceAll(';', ' ').replaceAll('\n', ' ').trim());
      }
    }

    ArchiveFile? targetSheetFile;
    final wbFile = archive.findFile('xl/workbook.xml');
    final relsFile = archive.findFile('xl/_rels/workbook.xml.rels');

    if (wbFile != null && relsFile != null) {
      final wbDoc = XmlDocument.parse(
          utf8.decode(wbFile.content as List<int>, allowMalformed: true));
      final relsDoc = XmlDocument.parse(
          utf8.decode(relsFile.content as List<int>, allowMalformed: true));

      Map<String, String> rIdToTarget = {};
      for (final rel in relsDoc.findAllElements('Relationship')) {
        final id = rel.getAttribute('Id');
        final target = rel.getAttribute('Target');
        if (id != null && target != null) {
          rIdToTarget[id] = target.startsWith('xl/') ? target : 'xl/$target';
        }
      }

      for (final sheetEl in wbDoc.findAllElements('sheet')) {
        final name = sheetEl.getAttribute('name') ?? '';
        final rId = sheetEl.getAttribute('r:id');
        final target = rId != null ? rIdToTarget[rId] : null;
        if (target != null && target.contains('worksheets/')) {
          final found = archive.findFile(target);
          if (found != null) {
            if (preferredSheetName != null &&
                name.toLowerCase().contains(preferredSheetName.toLowerCase())) {
              targetSheetFile = found;
              break;
            }
            targetSheetFile ??= found;
          }
        }
      }
    }

    if (targetSheetFile == null) {
      final sheetFiles = archive.files
          .where((f) =>
              f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (sheetFiles.isNotEmpty) {
        targetSheetFile = sheetFiles.first;
      }
    }

    if (targetSheetFile == null) return [];

    final sheetXmlStr =
        utf8.decode(targetSheetFile.content as List<int>, allowMalformed: true);
    final sheetDoc = XmlDocument.parse(sheetXmlStr);
    final allRowElements = sheetDoc.findAllElements('row').toList();

    List<List<String>> matrix = [];

    for (final rowEl in allRowElements) {
      final cells = rowEl.findAllElements('c').toList();
      if (cells.isEmpty) continue;

      List<String> rowValues = List.filled(maxCols, '');
      bool hasAnyData = false;

      for (final c in cells) {
        final ref = c.getAttribute('r') ?? '';
        final colIdx = _columnLettersToIndex(ref);
        if (colIdx < 0 || colIdx >= maxCols) continue;

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
        if (cellVal.isNotEmpty) hasAnyData = true;
        rowValues[colIdx] = cellVal;
      }

      if (hasAnyData) {
        matrix.add(rowValues);
      }
    }

    return matrix;
  }

  // =========================================================================
  // ВЫГРУЗКА В EXCEL: ТАХОМА 18 / 16 BOLD БЕЗ СЖАТИЯ + ЖИРНЫЕ ГРАНИЦЫ THICK
  // =========================================================================

  ex.CellStyle _buildCellStyle({
    required int fontSize,
    required String fontHex,
    String? bgHex,
    required ex.HorizontalAlign hAlign,
    bool wrapText = false,
  }) {
    final borderThick = ex.Border(
      borderStyle: ex.BorderStyle.Thick,
      borderColorHex: ex.ExcelColor.fromHexString('#FF000000'),
    );

    if (bgHex != null && bgHex.isNotEmpty) {
      return ex.CellStyle(
        fontFamily: 'Tahoma',
        fontSize: fontSize,
        bold: true,
        fontColorHex: ex.ExcelColor.fromHexString(fontHex),
        backgroundColorHex: ex.ExcelColor.fromHexString(bgHex),
        horizontalAlign: hAlign,
        verticalAlign: ex.VerticalAlign.Center,
        textWrapping: wrapText ? ex.TextWrapping.WrapText : ex.TextWrapping.Clip,
        leftBorder: borderThick,
        rightBorder: borderThick,
        topBorder: borderThick,
        bottomBorder: borderThick,
      );
    }

    return ex.CellStyle(
      fontFamily: 'Tahoma',
      fontSize: fontSize,
      bold: true,
      fontColorHex: ex.ExcelColor.fromHexString(fontHex),
      horizontalAlign: hAlign,
      verticalAlign: ex.VerticalAlign.Center,
      textWrapping: wrapText ? ex.TextWrapping.WrapText : ex.TextWrapping.Clip,
      leftBorder: borderThick,
      rightBorder: borderThick,
      topBorder: borderThick,
      bottomBorder: borderThick,
    );
  }

  void _fillBlankGridRow(ex.Sheet sheet, int rowIndex, {double rowHeight = 20}) {
    sheet.setRowHeight(rowIndex, rowHeight);
    for (int c = 0; c < 13; c++) {
      final cell = sheet.cell(
          ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex));
      cell.value = ex.TextCellValue('');
      cell.cellStyle = _buildCellStyle(
        fontSize: c == 0 ? 18 : 16,
        fontHex: '#FF000000',
        hAlign: (c >= 1 && c <= 10)
            ? ex.HorizontalAlign.Center
            : ex.HorizontalAlign.Left,
      );
    }
  }

  Future<void> _exportToFormattedExcel() async {
    final csvData = _lastCsvResult;
    if (csvData == null || csvData.isEmpty) {
      _showSnackbar('Нет данных для выгрузки!');
      return;
    }

    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel['Посылка'];
      excel.delete('Sheet1');

      final colWidths = [
        56.0, // A: Фирма (Tahoma 18 без автосжатия)
        15.0, // B: PS (Tahoma 16)
        13.0, // C: Счет пп
        14.0, // D: Сч/Н
        14.0, // E: По счету
        15.0, // F: Получено
        16.0, // G: Отгрузить!
        14.0, // H: Этикетка
        15.0, // I: на складе!
        12.0, // J: долг
        18.0, // K: Доставка
        30.0, // L: Расходная накладная
        24.0, // M: Major
      ];

      for (int i = 0; i < colWidths.length; i++) {
        sheet.setColumnWidth(i, colWidths[i]);
      }

      final rawLines = csvData
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('```'))
          .toList();

      if (rawLines.isEmpty) return;

      int currentRow = 0;

      // 1. Шапка таблицы (бирюзовая, с жёлтыми ячейками Отгрузить! и на складе!)
      final headerCells = rawLines[0].split(';');
      sheet.setRowHeight(currentRow, 42);
      for (int c = 0; c < 13; c++) {
        final val = c < headerCells.length ? headerCells[c].trim() : '';
        final cell = sheet.cell(
            ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: currentRow));
        cell.value = ex.TextCellValue(val);

        String headerBg = '#FF00B0AC';
        String headerFont = '#FFFFFFFF';
        if (c == 6 || c == 8) {
          headerBg = '#FFFFFF00';
          headerFont = '#FFFF0000';
        }

        cell.cellStyle = _buildCellStyle(
          fontSize: c == 0 ? 16 : 13,
          fontHex: headerFont,
          bgHex: headerBg,
          hAlign: c == 0
              ? ex.HorizontalAlign.Left
              : ex.HorizontalAlign.Center,
          wrapText: true,
        );
      }
      currentRow++;

      // 2. Отступ + строка даты отправки + отступ (везде жирная сетка!)
      _fillBlankGridRow(sheet, currentRow, rowHeight: 18);
      currentRow++;

      if (_lastOtpravkaHeader.isNotEmpty) {
        _fillBlankGridRow(sheet, currentRow, rowHeight: 24);
        final dateCell = sheet.cell(
            ex.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentRow));
        dateCell.value = ex.TextCellValue(_lastOtpravkaHeader);
        dateCell.cellStyle = _buildCellStyle(
          fontSize: 14,
          fontHex: '#FF9C0006',
          hAlign: ex.HorizontalAlign.Left,
        );
        currentRow++;

        _fillBlankGridRow(sheet, currentRow, rowHeight: 18);
        currentRow++;
      }

      // 3. Строки данных
      bool isInsideFilialBlock = false;

      for (int i = 1; i < rawLines.length; i++) {
        final cells = rawLines[i].split(';');
        final firstColLower =
            cells.isNotEmpty ? cells[0].trim().toLowerCase() : '';
        final deliveryVal =
            cells.length > 10 ? cells[10].trim().toLowerCase() : '';

        final isFilialDivider = firstColLower == 'филиал';
        final isSamovyvoz = deliveryVal.contains('самовывоз');
        final isSdek = deliveryVal.contains('сдэк');

        if (isFilialDivider) {
          isInsideFilialBlock = true;

          // Пустая строка-отступ с жирной сеткой перед "филиал"
          _fillBlankGridRow(sheet, currentRow, rowHeight: 18);
          currentRow++;

          // Строка "филиал" (красная плашка в колонке A + жирные границы по всем 13 колонкам)
          sheet.setRowHeight(currentRow, 28);
          for (int c = 0; c < 13; c++) {
            final filCell = sheet.cell(
                ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: currentRow));
            filCell.value = ex.TextCellValue(c == 0 ? 'филиал' : '');
            filCell.cellStyle = _buildCellStyle(
              fontSize: c == 0 ? 18 : 16,
              fontHex: c == 0 ? '#FFFFFFFF' : '#FF000000',
              bgHex: c == 0 ? '#FFFF0000' : null,
              hAlign: ex.HorizontalAlign.Center,
            );
          }
          currentRow++;

          // Пустая строка-отступ с жирной сеткой после "филиал"
          _fillBlankGridRow(sheet, currentRow, rowHeight: 18);
          currentRow++;
          continue;
        }

        sheet.setRowHeight(currentRow, 28);

        for (int c = 0; c < 13; c++) {
          final val = c < cells.length ? cells[c].trim() : '';
          final cell = sheet.cell(
              ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: currentRow));

          if (c >= 4 && c <= 6 && int.tryParse(val) != null) {
            cell.value = ex.IntCellValue(int.parse(val));
          } else {
            cell.value = ex.TextCellValue(val);
          }

          String? bgColor;
          String fontColor = '#FF000000';

          // Заливка строки только при "Самовывоз" (розовая в ПП, жёлто-оранжевая в Филиале)
          if (isSamovyvoz) {
            if (!isInsideFilialBlock) {
              bgColor = '#FFFF99CC';
            } else {
              bgColor = '#FFFFC000';
            }
          }

          // Счет пп (колонка C, индекс 2): красным шрифтом, без лишней заливки
          if (c == 2 && val.isNotEmpty) {
            fontColor = '#FFFF0000';
          }

          // Этикетка "ОТК" (колонка H, индекс 7): синим жирным
          if (c == 7 && val.toUpperCase() == 'ОТК') {
            fontColor = '#FF0000FF';
          }

          // Отгрузить! (колонка G, индекс 6): всегда красным жирным
          if (c == 6) {
            fontColor = '#FFFF0000';
          }

          // Доставка (колонка K, индекс 10): ДМ, К, Самовывоз красным, а СДЭК чёрным
          if (c == 10 && val.isNotEmpty) {
            if (isSdek) {
              fontColor = '#FF000000';
            } else {
              fontColor = '#FFFF0000';
            }
          }

          cell.cellStyle = _buildCellStyle(
            fontSize: c == 0 ? 18 : 16,
            fontHex: fontColor,
            bgHex: bgColor,
            hAlign: (c >= 1 && c <= 10)
                ? ex.HorizontalAlign.Center
                : ex.HorizontalAlign.Left,
          );
        }
        currentRow++;
      }

      // 4. Протягиваем жирную сетку и формат ячеек (18 для Фирмы, 16 для остальных) на 40 пустых строк вниз
      final totalRowsWithBuffer = currentRow + 40;
      for (int r = currentRow; r < totalRowsWithBuffer; r++) {
        _fillBlankGridRow(sheet, r, rowHeight: 24);
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

  // =========================================================================
  // ЧАТ И ПРИКРЕПЛЕНИЕ ДОКУМЕНТОВ / ФОТО ЧЕРЕЗ GROQ API
  // =========================================================================

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

      if (activeImage != null) {
        modelToUse = 'llama-3.2-11b-vision-preview';
      } else if (activeDoc != null && activeDoc.existsSync()) {
        modelToUse = 'qwen/qwen3.8-27b';
        final docContent = await _readAnyFileForChat(activeDoc, maxChars: 6500);
        finalPromptForApi =
            '$displayPrompt\n\n=== СОДЕРЖИМОЕ ФАЙЛА ($docName) ===\n$docContent';
      }

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

  Future<String> _readAnyFileForChat(File file, {int maxChars = 6500}) async {
    String rawText = '';
    final path = file.path.toLowerCase();

    if (path.endsWith('.xlsx')) {
      final rows = await _extractSheetMatrix(file, maxCols: 14);
      final sb = StringBuffer();
      if (rows.isNotEmpty) {
        sb.writeln(rows.first.join(';'));
        final start = rows.length > 60 ? rows.length - 60 : 1;
        for (int i = start; i < rows.length; i++) {
          sb.writeln(rows[i].join(';'));
        }
      }
      rawText = sb.toString();
    } else {
      try {
        final bytes = await file.readAsBytes();
        try {
          rawText = utf8.decode(bytes);
        } catch (_) {
          rawText = latin1.decode(bytes);
        }
      } catch (e) {
        rawText = '[Не удалось прочитать файл: $e]';
      }
    }

    if (rawText.length > maxChars) {
      return '${rawText.substring(0, maxChars)}\n... [Обрезано]';
    }
    return rawText;
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
    String content = message['content']?.toString().trim() ?? '';
    content = content.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
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
    final url = Uri.https('api.groq.com', '/openai/v1/chat/completions');

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
      'max_tokens': 950,
      'messages': formattedMessages,
    };

    if (model.contains('gpt-oss')) {
      payload['reasoning_effort'] = 'low';
    } else if (model.contains('qwen')) {
      payload['reasoning_format'] = 'hidden';
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
              child: const Icon(Icons.memory, color: Color(0xFF38BDF8), size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Печатные платы',
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
                    'Обработка...',
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
