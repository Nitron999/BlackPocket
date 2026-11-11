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

  bool _isLoading = false;
  bool _isLogisticsExpanded = false;
  String _apiStatus = 'Ключ не настроен';
  Color _statusColor = Colors.orangeAccent;

  File? _posylkaFile;
  File? _svodkaPpFile;
  File? _svodkaFilialFile;

  final _chatHistory = [];
  String? _lastCsvResult;

  // Список АКТУАЛЬНЫХ моделей из документации Groq
  final _availableModels = [
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'qwen/qwen3.8-27b',
    'meta-models/muse-spark-open',
    'minimaxai/minimax-m2.7',
    'canopylabs/orpheus-v1-english',
    'llama-3.3-70b-versatile',
    'llama-3.1-8b-instant'
  ];
  
  // Ставим флагманскую бесплатную модель по умолчанию
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
    _loadSettings();
    _chatHistory.add({
      'role': 'assistant',
      'text': 'Здорово, Шурик! Я подтянул актуальные API-ключи и модели Groq. Выбирай любую GPT-OSS или Qwen в настройках ⚙️. Если приехали накладные — разворачивай панель логистики 📦 сверху.',
    });
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

  // Обычный чат
  Future<void> _sendChatMessage() async {
    final text = _chatInputController.text.trim();
    if (text.isEmpty) return;

    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showSnackbar('Сначала введи ключ Groq (gsk_...) в настройках!');
      return;
    }

    _chatInputController.clear();
    _appendMessage('user', text);

    setState(() => _isLoading = true);

    try {
      final responseText = await _callGroqRaw(
        apiKey: apiKey,
        model: _selectedModel,
        systemInstruction: 'Ты — Гена (Геннадий), персональный ИИ-ассистент Александра (Шурика). Отвечай четко, по делу, с юмором где уместно, поддерживай любые технические и бытовые темы.',
        prompt: text,
        temperature: 0.2,
      );
      _appendMessage('assistant', responseText);
    } catch (e) {
      _appendMessage('system', 'Ошибка: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Сведение логистических таблиц
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

    final fileName = posFile.path.split(Platform.pathSeparator).last;
    _appendMessage('user', '📦 Запуск сведения накладной через Groq ($_selectedModel): $fileName');

    try {
      final posylkaContent = await _readExcelTailSafe(posFile, maxRows: 150);
      
      String svodkaPpContent = '';
      final ppFile = _svodkaPpFile;
      if (ppFile != null && ppFile.existsSync()) {
        svodkaPpContent = await _readExcelTailSafe(ppFile, maxRows: 600);
      }
      
      String svodkaFilialContent = '';
      final filFile = _svodkaFilialFile;
      if (filFile != null && filFile.existsSync()) {
        svodkaFilialContent = await _readExcelTailSafe(filFile, maxRows: 1500);
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
        model: _selectedModel,
        systemInstruction: _logisticsSystemPrompt,
        prompt: promptText,
        temperature: 0.0,
      );

      final csv = _extractCsv(response);
      setState(() {
        _lastCsvResult = csv;
      });

      _appendMessage('assistant', response);
    } catch (e) {
      _appendMessage('system', 'Ошибка логистики: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String> _readExcelTailSafe(File file, {int maxRows = 500}) async {
    final path = file.path.toLowerCase();
    if (path.endsWith('.xlsx') || path.endsWith('.xls')) {
      final bytes = await file.readAsBytes();
      final excel = ex.Excel.decodeBytes(bytes);
      final tables = excel.tables;
      if (tables.isEmpty) return '';

      final sb = StringBuffer();
      for (final entry in tables.entries) {
        final tableName = entry.key;
        final sheet = entry.value;

        sb.writeln('Лист: $tableName');
        final allRows = sheet.rows;
        if (allRows.isEmpty) continue;

        // Заголовок
        final header = allRows.first.map((c) => c?.value?.toString() ?? '').toList();
        sb.writeln(header.join(';'));

        // Хвост
        final startIndex = allRows.length > maxRows ? (allRows.length - maxRows) : 1;
        for (int i = startIndex; i < allRows.length; i++) {
          final row = allRows[i];
          final rowList = row.map((c) => c?.value?.toString() ?? '').toList();
          if (rowList.any((v) => v.trim().isNotEmpty)) {
            sb.writeln(rowList.join(';'));
          }
        }
      }
      return sb.toString();
    } else {
      return await file.readAsString();
    }
  }

  // Универсальный метод вызова API Groq
  Future<String> _callGroqRaw({
    required String apiKey,
    required String model,
    required String systemInstruction,
    required String prompt,
    required double temperature,
  }) async {
    final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

    final payload = {
      'model': model,
      'temperature': temperature,
      'messages': [
        {'role': 'system', 'content': systemInstruction},
        {'role': 'user', 'content': prompt}
      ]
    };

    final resp = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(payload),
    );

    if (resp.statusCode != 200) {
      throw Exception('Ошибка API Groq (${resp.statusCode}): ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map?;
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
          final cellIndex = ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);
          if (r > 0 && c >= 4 && c <= 6 && int.tryParse(val) != null) {
            sheet.cell(cellIndex).value = ex.IntCellValue(int.parse(val));
          } else {
            sheet.cell(cellIndex).value = ex.TextCellValue(val);
          }
        }
      }

      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/Посылка_Сведение_${DateTime.now().millisecondsSinceEpoch}.xlsx';
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
                Text('Гена • на связи', style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isLogisticsExpanded ? Icons.inventory_2 : Icons.inventory_2_outlined,
              color: _isLogisticsExpanded ? const Color(0xFF38BDF8) : Colors.white70,
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
                    child: SelectableText(
                      text,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.95),
                        fontFamily: isSystem || text.startsWith('Фирма;') ? 'monospace' : null,
                      ),
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
                const Icon(Icons.local_shipping_outlined, size: 18, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                const Text(
                  'Сведение накладных (Посылка / Сводки)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                ),
                const Spacer(),
                Icon(
                  _isLogisticsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('СВЕСТИ НАКЛАДНУЮ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF101726),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
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
                    hintText: 'Спроси что угодно у Гены...',
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
      ),
    );
  }

  Widget _fileBtn({required String label, required bool active, required VoidCallback onTap}) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: active ? Colors.greenAccent : Colors.grey,
        side: BorderSide(color: active ? Colors.greenAccent : Colors.grey.shade700),
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
                    if (val != null) {
                      setDialogState(() {
                        tempModel = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: _statusColor),
                    const SizedBox(width: 6),
                    Text(_apiStatus, style: TextStyle(color: _statusColor, fontSize: 12)),
                  ],
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
