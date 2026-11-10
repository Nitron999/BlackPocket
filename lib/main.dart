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
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF818CF8),
          surface: Color(0xFF1E293B),
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
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  String _apiStatus = 'Ключ не настроен';
  Color _statusColor = Colors.orangeAccent;

  File? _posylkaFile;
  File? _svodkaPpFile;
  File? _svodkaFilialFile;

  final _messages = [];
  String? _lastCsvResult;

  static const String _systemInstruction = '''
Ты — прецизионный промышленный парсер и калькулятор логистических накладных для предприятий:
1) ООО «Печатные платы» (Москва — Головной офис)
2) ООО «ЭЛЕКТРОконнект» (Новосибирск — Филиал)

ТВОЯ ЗАДАЧА:
Принять накладную «Посылка» и свести её со «Сводкой ООО Печатные платы» и «Сводкой филиал».
Температура работы 0.0. Запрещено выдумывать, фантазировать или округлять данные.

СТРОГИЕ ПРАВИЛА РАЗДЕЛЕНИЯ И ОБРАБОТКИ:

1. СТРУКТУРА ВЫХОДНОГО CSV (ровно 13 колонок, разделитель точка с запятой ";"):
Фирма;PS;Счет пп;Сч/Н;По счету;Получено;Отгрузить;Этикетка;на складе!;долг;Доставка;Расходная накладная;Major

2. БЛОК 1: ГОЛОВНОЙ ОФИС (ООО «Печатные платы»)
- Ищется по номеру PS в файле «Сводка ООО Печатные платы» (лист «СВОДКА»).
- Фирма: берётся из сводки (колонка «Фирма, заказчик»). Если в Посылке фирма не указана, ОБЯЗАТЕЛЬНО найти и вписать её точное название!
- Счет пп: московский номер счета с сохранением ВСЕХ ведущих нулей (формат: 0654, 0644, 0615, 0611, 0616).
- Сч/Н: номер счета Новосибирска.
- По счету: ПОЛНЫЙ тираж договора из сводки ПП (колонка «количество», столбец 4). Запрещено ставить туда значение из колонки «Получено»!
- Получено и Отгрузить: фактические значения из таблицы посылки.
- Этикетка: ВСЕГДА ставить значение "ОТК".
- Доставка: определяется по типу: "ДМ" (Доставка Москва), "СДЭК", "К" (Курьер), "Самовывоз".

3. РАЗДЕЛИТЕЛЬ БЛОКОВ:
Ровно одна строка:
филиал;;;;;;;;;;;;

4. БЛОК 2: ФИЛИАЛ (ООО «ЭЛЕКТРОконнект»)
- Все строки, идущие под разделителем «филиал».
- Счет пп: СТРОГО ПУСТОЕ ПОЛЕ (;;). У филиала НЕ БЫВАЕТ счетов «Печатных плат»!
- Этикетка: СТРОГО ПУСТОЕ ПОЛЕ (;;). У филиала НЕ БЫВАЕТ ОТК!
- По счету: искать в «Сводке филиал» (лист «ФИЛИАЛ») по СВЯЗКЕ [Номер счета Новосибирска (Сч/Н, колонка 0) + PS (колонка 4)]. Брать значение строго из колонки 7 («кол-во» / запуск в работу). Это полный оплаченный заказ! (Например, если пришла 1 шт., а в договоре по счету 50 шт. — ставить 50!).
- Доставка: определять по сводке филиала:
  * "Доставка Москва" -> ставить "ДМ"
  * "Курьер" (включая заказы Нейрософт, Кузьминский) -> ставить "К"
  * "СДЭК" / "курьер СДЭК" -> ставить "СДЭК"
  * "Самовывоз" -> ставить "Самовывоз"

5. СТРОГАЯ СОРТИРОВКА ВНУТРИ КАЖДОГО БЛОКА:
Внутри блока Головы, а затем внутри блока Филиала строки ДОЛЖНЫ быть строго отсортированы по доставке:
1) ДМ (в самом верху)
2) СДЭК
3) К
4) Самовывоз

6. ФОРМАТ ОТВЕТА:
Выведи ТОЛЬКО чистый CSV блок внутри ```csv ... ``` без лишних рассуждений.
''';

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('gemini_api_key') ?? '';
    if (key.isNotEmpty) {
      setState(() {
        _apiKeyController.text = key;
        _apiStatus = 'API ключ подключен';
        _statusColor = Colors.greenAccent;
      });
    }
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key.trim());
    setState(() {
      _apiStatus = key.trim().isNotEmpty ? 'API ключ сохранен' : 'Ключ не настроен';
      _statusColor = key.trim().isNotEmpty ? Colors.greenAccent : Colors.orangeAccent;
    });
  }

  Future<void> _pickFile(int type) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv', 'txt'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      setState(() {
        if (type == 1) _posylkaFile = file;
        if (type == 2) _svodkaPpFile = file;
        if (type == 3) _svodkaFilialFile = file;
      });
    }
  }

  Future<void> _processLogistics() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showSnackbar('Введите API ключ Gemini Cloud!');
      return;
    }

    if (_posylkaFile == null) {
      _showSnackbar('Выберите файл Посылки!');
      return;
    }

    setState(() {
      _isLoading = true;
      _lastCsvResult = null;
    });

    _addMessage('user', 'Запуск сведения накладных: ${_posylkaFile!.path.split(Platform.pathSeparator).last}');

    try {
      final posylkaContent = await _readFileData(_posylkaFile!);
      String svodkaPpContent = '';
      if (_svodkaPpFile != null) {
        svodkaPpContent = await _readFileData(_svodkaPpFile!);
      }
      String svodkaFilialContent = '';
      if (_svodkaFilialFile != null) {
        svodkaFilialContent = await _readFileData(_svodkaFilialFile!);
      }

      final promptText = '''
ВХОДНЫЕ ДАННЫЕ ДЛЯ СВЕДЕНИЯ:

=== 1. ФАЙЛ ПОСЫЛКА (ТЕКУЩИЙ ПРИХОД) ===
$posylkaContent

=== 2. СВОДКА ООО ПЕЧАТНЫЕ ПЛАТЫ (ГОЛОВА) ===
$svodkaPpContent

=== 3. СВОДКА ФИЛИАЛ (ЭЛЕКТРОКОННЕКТ) ===
$svodkaFilialContent

Выполни полное сопоставление по инструкции, расставь точные названия клиентов, договорные тиражи «По счету», пустые счета и этикетки для филиала, отсортируй по ДМ -> СДЭК -> К -> Самовывоз и верни CSV.
''';

      final response = await _callGeminiFlash(apiKey, promptText);
      final csv = _extractCsv(response);

      setState(() {
        _lastCsvResult = csv;
      });

      _addMessage('assistant', response);
    } catch (e) {
      _addMessage('system', 'Ошибка при обработке: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<String> _readFileData(File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    if (ext == 'xlsx' || ext == 'xls') {
      final bytes = await file.readAsBytes();
      final excel = ex.Excel.decodeBytes(bytes);
      final sb = StringBuffer();
      for (final table in excel.tables.keys) {
        sb.writeln('Лист: $table');
        final sheet = excel.tables[table]!;
        for (final row in sheet.rows) {
          final rowVals = row.map((c) => c?.value?.toString() ?? '').toList();
          if (rowVals.any((v) => v.trim().isNotEmpty)) {
            sb.writeln(rowVals.join(';'));
          }
        }
      }
      return sb.toString();
    } else {
      return await file.readAsString();
    }
  }

  Future<String> _callGeminiFlash(String apiKey, String prompt) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key=$apiKey',
    );

    final payload = {
      'system_instruction': {
        'parts': [
          {'text': _systemInstruction}
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.0,
        'maxOutputTokens': 8192,
      }
    };

    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (resp.statusCode != 200) {
      throw Exception('Ошибка API (${resp.statusCode}): ${resp.body}');
    }

    final data = jsonDecode(resp.body);
    final text = data['candidates'][0]['content']['parts'][0]['text'] as String;
    return text;
  }

  String _extractCsv(String text) {
    if (text.contains('```csv')) {
      final start = text.indexOf('```csv') + 6;
      final end = text.indexOf('```', start);
      return text.substring(start, end).trim();
    } else if (text.contains('```')) {
      final start = text.indexOf('```') + 3;
      final end = text.indexOf('```', start);
      return text.substring(start, end).trim();
    }
    return text.trim();
  }

  Future<void> _exportToFormattedExcel() async {
    if (_lastCsvResult == null || _lastCsvResult!.isEmpty) {
      _showSnackbar('Нет данных CSV для выгрузки!');
      return;
    }

    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel['Посылка'];
      excel.delete('Sheet1');

      final lines = _lastCsvResult!.split('\n');

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

  void _addMessage(String role, String text) {
    setState(() {
      _messages.add({'role': role, 'text': text});
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
        title: const Row(
          children: [
            Icon(Icons.precision_manufacturing, color: Color(0xFF38BDF8)),
            SizedBox(width: 8),
            Text('BlackPocket AI', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _showSettingsDialog(context),
          )
        ],
        elevation: 2,
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF0F172A),
            child: Row(
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
                    label: _svodkaFilialFile == null ? '3. Сводка Фил.' : 'Филиал: OK',
                    active: _svodkaFilialFile != null,
                    onTap: () => _pickFile(3),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_isLoading ? 'Сведение таблицы...' : 'СВЕСТИ НАКЛАДНУЮ'),
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
                    tooltip: 'Экспорт в Excel',
                    onPressed: _exportToFormattedExcel,
                  )
                ]
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, idx) {
                final m = _messages[idx];
                final isUser = m['role'] == 'user';
                final isSystem = m['role'] == 'system';

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.9),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFF0369A1)
                          : isSystem
                              ? const Color(0xFF7F1D1D)
                              : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      m['text']!,
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileBtn({required String label, required bool active, required VoidCallback onTap}) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: active ? Colors.greenAccent : Colors.grey,
        side: BorderSide(color: active ? Colors.greenAccent : Colors.grey.shade700),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Настройки Google Cloud API'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'Gemini API Key (AQ...)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
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
              _saveApiKey(_apiKeyController.text);
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}
