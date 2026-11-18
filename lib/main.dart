import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as ex;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BlackPocketApp());
}

class BlackPocketApp extends StatefulWidget {
  const BlackPocketApp({super.key});

  @override
  State<BlackPocketApp> createState() => _BlackPocketAppState();
}

class _BlackPocketAppState extends State<BlackPocketApp> {
  bool _isDark = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDark = prefs.getBool('is_dark_theme') ?? true;
    });
  }

  Future<void> _toggleTheme() async {
    final next = !_isDark;
    setState(() => _isDark = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_theme', next);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Печатные платы — Logistics & Major Express',
      debugShowCheckedModeBanner: false,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF0D9488),
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF14B8A6),
        scaffoldBackgroundColor: const Color(0xFF090D16),
      ),
      home: MainWorkspaceScreen(
        isDark: _isDark,
        onToggleTheme: _toggleTheme,
      ),
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
        role: json['role']?.toString() ?? 'user',
        text: json['text']?.toString() ?? '',
        imagePath: json['imagePath']?.toString(),
        fileName: json['fileName']?.toString(),
      );
}

class ChatSession {
  String title;
  List<ChatMessage> messages;

  ChatSession({required this.title, required this.messages});

  Map<String, dynamic> toJson() => {
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) => ChatSession(
        title: json['title']?.toString() ?? 'Новый чат',
        messages: (json['messages'] as List? ?? [])
            .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class LogisticsItem {
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
  String rashodnaya;
  String major;

  LogisticsItem({
    this.firm = '',
    this.ps = '',
    this.schetPp = '',
    this.schN = '',
    this.poSchetu = '',
    this.polucheno = '',
    this.otgruzit = '',
    this.etiketka = '',
    this.naSklade = '',
    this.dolg = '',
    this.dostavka = '',
    this.rashodnaya = '',
    this.major = '',
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
        rashodnaya,
        major,
      ];
}

class OperationLogEntry {
  final String module;
  final String title;
  final String details;
  final String time;
  final bool isError;

  OperationLogEntry({
    required this.module,
    required this.title,
    required this.details,
    required this.time,
    this.isError = false,
  });

  Map<String, dynamic> toJson() => {
        'module': module,
        'title': title,
        'details': details,
        'time': time,
        'isError': isError,
      };

  factory OperationLogEntry.fromJson(Map<String, dynamic> json) =>
      OperationLogEntry(
        module: json['module']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        details: json['details']?.toString() ?? '',
        time: json['time']?.toString() ?? '',
        isError: json['isError'] == true,
      );
}

class MainWorkspaceScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback onToggleTheme;

  const MainWorkspaceScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  State<MainWorkspaceScreen> createState() => _MainWorkspaceScreenState();
}

class _MainWorkspaceScreenState extends State<MainWorkspaceScreen> {
  int _selectedNavIndex = 0;
  bool _isSidebarCollapsed = false;

  final TextEditingController _apiKeyController = TextEditingController();
  String _selectedModel = 'llama-3.3-70b-versatile';
  final List<String> _availableModels = const [
    'llama-3.3-70b-versatile',
    'qwen/qwen3.8-27b',
    'openai/gpt-oss-20b',
    'llama-3.1-8b-instant',
  ];
  String _apiStatus = 'Ключ не проверен';
  bool? _isKeyWorking;
  bool _isKeyValidating = false;

  List<ChatSession> _sessions = [];
  ChatSession? _currentSession;
  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  File? _chatImage;
  File? _chatAttachedFile;
  bool _isLoading = false;
  bool _sumatraFound = false;

  // Модуль 1: Сведение накладных
  File? _posylkaFile;
  File? _svodkaPpFile;
  File? _svodkaFilialFile;
  final TextEditingController _posylkaPathController = TextEditingController();
  final TextEditingController _svodkaPpPathController = TextEditingController();
  final TextEditingController _svodkaFilialPathController =
      TextEditingController();

  String? _lastCsvResult;
  String _lastOtpravkaHeader = '';
  int _lastHeadCount = 0;
  int _lastFilialCount = 0;
  String _lastLogisticsAction = 'Файлы не выбраны';

  // Модуль 2: Электроконнект (Major Express)
  final TextEditingController _majorFirmController = TextEditingController();
  final TextEditingController _majorDateController = TextEditingController();
  final TextEditingController _majorTimeController =
      TextEditingController(text: '10:00-14:00');
  final TextEditingController _majorWeightController =
      TextEditingController(text: '1');
  final TextEditingController _majorPlacesController =
      TextEditingController(text: '1');
  final TextEditingController _majorDescController =
      TextEditingController(text: 'Документы');
  final TextEditingController _majorInfoController = TextEditingController();
  final TextEditingController _majorFirmSearchController =
      TextEditingController();
  String _majorFirmFilter = '';
  List<String> _electroFirms = [];
  String _lastMajorAction = 'Готов к оформлению';

  // Модуль 3: Печатные платы (Major Express)
  final TextEditingController _platyFirmController = TextEditingController();
  final TextEditingController _platyDateController = TextEditingController();
  final TextEditingController _platyTimeController =
      TextEditingController(text: '10:00-14:00');
  final TextEditingController _platyWeightController =
      TextEditingController(text: '1');
  final TextEditingController _platyPlacesController =
      TextEditingController(text: '1');
  final TextEditingController _platyDescController =
      TextEditingController(text: 'Платы');
  final TextEditingController _platyInfoController = TextEditingController();
  final TextEditingController _platyFirmSearchController =
      TextEditingController();
  String _platyFirmFilter = '';
  List<String> _platyFirms = [];
  String _lastPlatyAction = 'Готов к оформлению';

  List<OperationLogEntry> _operationLogs = [];

  static const List<String> _defaultElectroFirms = [
    'ООО "РУТСТЕР"',
    'ООО "СТК"',
    'АО "Концерн Вега"',
    'АО "НИИСТТ"',
    'ООО "МЭЩ"',
    'ООО "ЭМУЛС"',
    'ООО "Техноресурс"',
    'ООО "РДВ-Технолоджи"',
    'ООО "ФОРВАРД-ВЕНТ"',
    'ИП Годына Александр Николаевич',
    'ООО « ЦЕНТР ИНЖЕНЕРНЫХ РАЗРАБОТОК « ПАРУС »',
    'ООО "КВ СИСТЕМЫ"',
    'ООО " НПК ИСКРА"',
    'ООО " Международный центр квантовой оптики',
    'ООО "Электроконнект"',
    'ООО "ДИСТАНЦИЯ"',
    'АО "Мостком"',
    'ООО "АТС Т"',
    'ООО "ПЛ ИНЖИНИРИНГ"',
    'АНО " Школа 21"',
    'ООО "АЙСИЭЛ ЭЛЕКТРОНИКС"',
    'ООО "КОМПАНИЯ "СТРИМ ЛАБС"',
    'ООО "Дельта Солюшнс"',
    'Упак-Лайнер',
    'ООО "Олл ин пром"',
    'АО "Научно-производственное "Рязаньприбор"',
    'АО"ГЗАС им Попова"',
    'ООО "Корд-группа"',
    'ООО "МИР-СПОРТ-ЦЕНТР"',
    'ЗАО "Сетевые Технологии"',
    'ООО Лигель',
    'ООО «АВТОМАТИКА плюс»',
    'Гидравлические Комплексные Системы',
    'ООО "РТЦ"',
    'АО "ИНФОРМТЕХНИКА И СВЯЗЬ"',
    'ООО "НПО "ОРИГИНАЛЬНЫЕ РУССКИЕ КОНТРОЛЛЕРЫ"',
    'ООО "Деко-сервис"',
    'АО "НПО "Радиозавод им. А.С.Попова"',
    'АО "Электромеханика"',
    'ООО "РЭСТОК"',
    'ООО "МикроЭМ Технологии"',
    'ООО "Декаст"',
    'ООО "Технологии Света"',
    'АО ПФ "ЭЛВИРА"',
    'ООО "Комито"',
    'ООО "НПО "Вольт инжиниринг"',
    'ООО "Ревотех"',
    'ООО "Орион-Р"',
    'ООО "Трансаммиак"',
    'ООО "Промприбор-Р"',
    'ООО "Галсплюс"',
    'ООО НПО "Грань"',
    'ООО "ТИОН"',
    'АО "РНТ"',
    'ООО "РТК-Технологии"',
    'ООО "Мотив НТ"',
    'ООО ПКФ "Экс-Форма"',
    'ООО "СД Группа"',
    'ООО "Элпром"',
    'АО "НПП "Исток" им. Шокина"',
    'ООО "Видар"',
    'АО "СИП РС"',
    'ООО "ИВК АИР ГРУПП"',
    'ООО ВНПЗ "Куб"',
    'ООО "Интегра Про"',
    'ООО "Смарт Групп"',
    'ООО "Максбионик"',
    'ООО "ЭН-ЭС-ДЖИ"',
    'ООО "ПЦРНИК"',
    'ООО "Катран-Интех"',
    'ООО "Энерготрейд"',
    'АО "Аэроэлектромаш"',
    'ООО "Фирма "Радиал"',
    'АО "АМТЕО М"',
    'ООО "Милти"',
    'ООО "Цезарь Системс"',
    'ООО "Лебер"',
    'ООО "НПО "Визит" им. В.Ф. Сотникова"',
    'ООО "РЭМО-Технологии"',
    'ПАО "Вектор"',
    'ООО НПФ "Радиосервис"',
    'МФТИ, ФИЗТЕХ',
    'ООО "Радиотехнологии"',
    'ООО "Эмеральд Экотехнологии"',
    'ООО "Лаборатория электроприводов "АДАПТТО"',
    'ООО "Фактор спецэлектроника"',
    'ООО "С-Компонент Дубна"',
    'АО "Росатом РДС"',
    'ООО "Чистое небо"',
    'ООО "НВС Навигационные Технологии"',
    'ООО "Панометрик"',
    'Аквариус Москва',
    'АО "КМК"',
    'ФГУП "ВНИИФТРИ"',
    'ООО "Интехпро"',
    'АО "Коралл-Телеком"',
    'АО "НИИП имени В.В. Тихомирова"',
    'ООО "Турков"',
    'ООО "НИИКАМ"',
    'ООО "Три точки мануфактуринг"',
    'ООО "Неовэлл"',
    'ООО "СГ-Терм"',
    'ООО "ИРЗ"',
    'ООО "Динакор Силовые Технологии"',
    'ООО "ТД "Энергостандарт"',
    'ООО "Карат Рус"',
    'ООО "Амперка Роботс"',
    'АО "НИИМА "Прогресс"',
    'ООО "ПРОТОН"',
    'АО "БСЗ"',
    'АО "ПИК ПРОГРЕСС"',
    'ООО "Образование Будущего"',
    'ООО "ИНТ"',
    'ООО "Ольвия"',
    'ООО "Перспективная Электроника"',
    'ООО "Лиитс"',
    'ООО "Производственное предприятие КОНСТАР"',
    'АО "РНИЦ по Рязанской области"',
    'Аквариус Шуя',
    'Аквариус Тверь',
    'АО "НПО "Орион"',
    'АО "Лаборатория Электроники"',
    'АО "ОДК"',
    'АО НПЦ "ЭЛВИС"',
    'ООО "Дантекс Рус"',
    'ООО "САУК"',
    'ООО "НТР"',
    'АО "Микрон"',
    'АО "ЭЗАН"',
    'АО НПП "Пульсар"',
    'АО "Плазма"',
  ];

  static const List<String> _defaultPlatyFirms = [
    '18 ЦНИИ МО РФ МГУП',
    'OOO "АПС"',
    'Агарков Алексей Сергеевич',
    'Антон Киструга',
    'АО " Гирооптика"',
    'АО " Горизонт"',
    'АО " НИИАО"',
    'АО "766 УПТК"',
    'АО "АВЭКС"',
    'АО "АЛМАЗ"',
    'АО "Бета ир"',
    'АО "Вибратор"',
    'АО "ГНПП "Регион"',
    'АО "ДМЗ" им. Н.П. Федорова',
    'АО "Завод Кризо"',
    'АО "ЗАВОД" ЭЛЕКТРОМАШ"',
    'АО "КБТочмаш им. А.Э. Нудельмана"',
    'АО "КИПЗ"',
    'АО "КОБРА"',
    'АО "Концерн Вега"',
    'АО "Корпарация "Внииэм"',
    'АО "Корпорация "ВНИИЭМ"',
    'АО "Корпорация "Фазотрон-НИИР"',
    'АО "Красный гидропресс"',
    'АО "КЭТЗ"',
    'АО "МОРИНСИС-АГАТ-КИП"',
    'АО "МПОТК"Технокомплект"',
    'АО "НАНОТРОНИКА"',
    'АО "НИИ "КУЛОН"',
    'АО "НИИ "Октава"',
    'АО "НИИ "Полюс" им.М.Ф.Стельм',
    'АО "НИИ "ЭЛПА"',
    'АО "НИИ КП"',
    'АО "НИИ Проблем Автоматизации "Северэвмкомплекс"',
    'АО "НИИИ',
    'АО "НИИИТ-Опытный завод"',
    'АО "НИИИТ-РК"',
    'АО "НИИМЭ"',
    'АО "НИИПП"',
    'АО "НИИЭМ"',
    'АО "НПК "СПП"',
    'АО "НПО "КИС"',
    'АО "НПО "ОРИОН"',
    'АО "НПО "РусБИТех"',
    'АО "НПО "РЯЗАНЬПРИБОР"',
    'АО "НПП "КРАСНОЗНАМЁНЕЦ"',
    'АО "НПП "Пульсар"',
    'АО "НПП" РЕАКОНТ"',
    'АО "НПП"Геофизика-Космос',
    'АО "НПФ "Микран"',
    'АО "НПЦ" "АСПЕКТ"',
    'АО "НТП "АВИАТЕСТ"',
    'АО "НЦ ПЭ"',
    'АО "Обуховское"',
    'АО "ОДК"',
    'АО "ОКБ МЭИ"',
    'АО "Плазма"',
    'АО "ПО "СЕВЕР"',
    'АО "ПО "СЕВЕР" Михеев',
    'АО "Радиозавод"',
    'АО "РПЗ"',
    'АО "Рязанский радиозавод"',
    'АО "Серпуховский Завод "Металлист"',
    'АО "СПС"',
    'АО "СУП"',
    'АО "ТехПромИмпорт"',
    'АО "Трансмаш"',
    'АО "Уральские Заводы"',
    'АО "ЦНИИ "Буревестник"',
    'АО "ЦНИИ "Волна"',
    'АО "Цнииаг"',
    'АО "ЦНИТИ "Техномаш"',
    'АО "ЭВРИКА"',
    'АО "ЭЗАН"',
    'АО "ЭПМ"',
    'АО "ЭРА Марин"',
    'АО «ЗАВОД «ФИОЛЕНТ»',
    'АО «НИИ НПО «ЛУЧ»',
    'АО «РДТ-Темп»',
    'АО «РЗП»',
    'АО АНИТТ "РЕКОРД"',
    'АО АПЗ "РОТОР"',
    'АО ВП "ЭРА"',
    'АО Корпорация "ВНИИЭМ"',
    'АО МТЗ ТРАНСМАШ',
    'АО МТЗ ТРАНСМАШ ИМ. А.А. ЕГОРЕНКОВА',
    'АО НИИПП',
    'АО НИЦ "РЕЗОНАНС"',
    'АО НПП ЦИФРОВЫЕ РЕШЕНИЯ',
    'АО"ГЗАС им Попова"',
    'АО"КЗТМ"',
    'Беленькая Татьяна Ивановна',
    'Блохина Ирина Валерьевна',
    'Валентин Дерябкин',
    'Валерий Белоусов',
    'Владимир Бузовский',
    'ГАЗ-СИСТЕМА-СЕРВИС АО НПФ',
    'Гетман Максим',
    'Жиляев Александр Владимирович',
    'ЗАО "БИУС"',
    'ЗАО "ЗЭТ"',
    'ЗАО "КоМЭНС"',
    'ЗАО "Полимерфильтр"',
    'ЗАО "ЭРАСИБ"',
    'ЗАО НПП "Система"',
    'ЗАО НПЦ ФИРМА "НЕЛК"',
    'ИКИ РАН',
    'ИП Артемьев Евгений Александрович',
    'ИПМТ ДВО РАН',
    'Калугаприбор',
    'Ленар Гимадиев',
    'Максимов Алексей',
    'МОКБ "Марс"',
    'НП ЗАО "РЭКО-ВЕК"',
    'ОАО "Егоршинский радиозавод"',
    'ОАО "Завод Электросигнал"',
    'ОАО "Казанский завод "Электроприбор"',
    'ОАО "НПП КП "Квант"',
    'ОАО "ПЯТИГОРСКИЙ ЗАВОД "ИМПУЛЬС"',
    'Ольга',
    'ООО "Арматех"',
    'ООО "Беспилотные Системы"',
    'ООО "БОРЕЙ"',
    'ООО "Вибратор"',
    'ООО "ГЕТМОБИТ"',
    'ООО "ДЖИ-ТЭК"',
    'ООО "Джусто"',
    'ООО "ИНДЖЕР"',
    'ООО "ИНИТЕЛ"',
    'ООО "ИСТОЧНИК"',
    'ООО "КИНОТЕАТРАЛЬНЫЕ ТЕХНОЛОГИИ"',
    'ООО "Компания "Объединенная энергия"',
    'ООО "ЛазерСервис"',
    'ООО "ЛОГИС"',
    'ООО "Логические Системы"',
    'ООО "Лотес ТМ"',
    'ООО "МГ-СЕРВИС"',
    'ООО "Наутилус"',
    'ООО "Нейрософт"',
    'ООО "НИИ Энерготехнологий"',
    'ООО "Николь"',
    'ООО "НИЦ СЭ И НК"',
    'ООО "НТП "Энергоконтроль"',
    'ООО "НЭК"',
    'ООО "ОПТИМАЛЬНАЯ ФАБРИКА"',
    'ООО "ПК" АЛЛЕГРИ"',
    'ООО "ПКФ ПОЛЁТ"',
    'ООО "ПЛАЗ"',
    'ООО "Рембаза"',
    'ООО "РТС-БИТ"',
    'ООО "РТСОФТ-ВС"',
    'ООО "Сибаналитприбор"',
    'ООО "Сигналатомприбор"',
    'ООО "СМТ ФЛЕКС"',
    'ООО "СТС"',
    'ООО "Тир Строй Монтаж"',
    'ООО "ТПС"',
    'ООО "ТЭНСНАБ"',
    'ООО "УРАРТУ"',
    'ООО "Фабметалл"',
    'ООО "ФИНКО"',
    'ООО "Электроконнект"',
    'ООО "Электроконнект" Санкт-Петербург',
    'ООО "Электропром"',
    'ООО <НПП <ПАРК-ЦЕНТР>',
    'ООО «ЛЭМЗ-Т»',
    'ООО НПО " Горизонт"',
    'ООО НПП "ЭЛЕКТРОМАШ"',
    'ООО НППГА"ЛУЧ"',
    'ООО"КТЦ КЭБ"',
    'ООО"РАДАРАВИАСЕРВИС"',
    'ООО«Печатные платы»',
    'ОП "НИИ АЭМ ТУСУР"',
    'Павел Титов',
    'ПАО "НПО "Алмаз"',
    'ПАО "НПП "Импульс"',
    'ПАО "РЕАТОН"',
    'ПАО "Яковлев"',
    'ПАО АК "Рубин"',
    'ПАО НПО "Наука"',
    'ПАО ПЗ "Сигнал"',
    'ПАО"ГЗАС им Попова"',
    'ПАО"Саратовский электроприборостроительный з-д им.',
    'Поляков Олег',
    'Приходько Сергей Викторович',
    'РусБитех',
    'Самарский университет',
    'Симакина Екатерина Михайловна',
    'Синвайтес Инжиниринг',
    'Сколковский институт науки и технологий Сколтех',
    'Соколов Павел Андреевич',
    'Стас',
    'Степанова Марина',
    'Сумин Евгений',
    'Сушецкий Велес',
    'Татьяна',
    'Тепляков Пётр',
    'Терёхина Галина Александровна',
    'Толстова Татьяна',
    'УФК М.О (ИБП РАН)',
    'Ф+ тек Берсенева Ксения',
    'ФГБОУ ВО "ВГУ"',
    'ФГБУ ФНЦ ВНИИФК',
    'ФГКУ В/Ч "45187"',
    'ФГУП "ВНИИФТРИ"',
    'ФГУП "Крыловский государственный научный центр"',
    'ФГУП "НАМИ"',
    'ФГУП"ВНИИА"',
    'Филиал ИФП СО РАН "КТИПМ"',
    'Черникова Ольга',
    'ЧТУП "Печатные платы"',
    'ЮРГПУ (НПИ)',
    'ЮФУ, ЮФУ ЮЖНЫЙ ФЕДЕРАЛЬНЫЙ УНИВЕРСИТЕТ, ФГАОУ ВО',
  ];

  @override
  void initState() {
    super.initState();
    _majorDateController.text = _todayFormatted();
    _platyDateController.text = _todayFormatted();
    _initApp();
  }

  String _todayFormatted() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
  }

  Future<void> _initApp() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('groq_api_key') ?? '';
      final savedModel = prefs.getString('groq_model');
      if (savedModel != null && _availableModels.contains(savedModel)) {
        _selectedModel = savedModel;
      }
      _isSidebarCollapsed = prefs.getBool('sidebar_collapsed') ?? false;

      final p1 = prefs.getString('saved_path_posylka') ?? '';
      final p2 = prefs.getString('saved_path_svodka_pp') ?? '';
      final p3 = prefs.getString('saved_path_svodka_fil') ?? '';
      _posylkaPathController.text = p1;
      _svodkaPpPathController.text = p2;
      _svodkaFilialPathController.text = p3;
      if (p1.isNotEmpty && File(p1).existsSync()) _posylkaFile = File(p1);
      if (p2.isNotEmpty && File(p2).existsSync()) _svodkaPpFile = File(p2);
      if (p3.isNotEmpty && File(p3).existsSync()) _svodkaFilialFile = File(p3);

      final logsJson = prefs.getString('operation_logs');
      if (logsJson != null) {
        _operationLogs = (jsonDecode(logsJson) as List)
            .map((e) =>
                OperationLogEntry.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      final chatsJson = prefs.getString('chat_sessions');
      if (chatsJson != null) {
        _sessions = (jsonDecode(chatsJson) as List)
            .map((e) => ChatSession.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      if (_sessions.isEmpty) {
        _sessions.add(ChatSession(title: 'Основной чат', messages: []));
      }
      _currentSession = _sessions.first;
    });

    await _checkSumatraPdf();
    await _loadFirmsFromDisk(isPlaty: false);
    await _loadFirmsFromDisk(isPlaty: true);

    if (_apiKeyController.text.trim().isNotEmpty) {
      _validateKeyOnly(_apiKeyController.text);
    }
  }

  Future<String> _getWorkDirPath() async {
    if (Platform.isWindows) {
      const customPath = r'C:\PechatnyePlaty';
      final dir = Directory(customPath);
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      if (dir.existsSync()) return customPath;
    }
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }

  Future<void> _checkSumatraPdf() async {
    if (!Platform.isWindows) return;
    final workDir = await _getWorkDirPath();
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final found = File('$workDir\\SumatraPDF.exe').existsSync() ||
        File('$exeDir\\SumatraPDF.exe').existsSync();
    setState(() => _sumatraFound = found);
  }

  Future<void> _addOperationLog(
    String module,
    String title,
    String details, {
    bool isError = false,
  }) async {
    final now = DateTime.now();
    final timeStr =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _operationLogs.insert(
        0,
        OperationLogEntry(
          module: module,
          title: title,
          details: details,
          time: timeStr,
          isError: isError,
        ),
      );
      if (_operationLogs.length > 100) {
        _operationLogs = _operationLogs.sublist(0, 100);
      }
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'operation_logs',
      jsonEncode(_operationLogs.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveChats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'chat_sessions', jsonEncode(_sessions.map((s) => s.toJson()).toList()));
  }

  void _createNewChat() {
    setState(() {
      final session = ChatSession(title: 'Новый чат', messages: []);
      _sessions.insert(0, session);
      _currentSession = session;
    });
    _saveChats();
  }

  void _deleteChat(ChatSession session) {
    setState(() {
      _sessions.remove(session);
      if (_sessions.isEmpty) {
        _sessions.add(ChatSession(title: 'Основной чат', messages: []));
      }
      if (_currentSession == session) {
        _currentSession = _sessions.first;
      }
    });
    _saveChats();
  }

  void _renameChat(ChatSession session) {
    final ctrl = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать чат'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              setState(() => session.title =
                  ctrl.text.trim().isEmpty ? 'Чат' : ctrl.text.trim());
              _saveChats();
              Navigator.pop(ctx);
            },
            child: const Text('ОК'),
          ),
        ],
      ),
    );
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

  Future<void> _validateKeyOnly(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _isKeyValidating = true;
      _apiStatus = 'Проверка ключа...';
    });
    try {
      final resp = await http.get(
        Uri.https('api.groq.com', '/openai/v1/models'),
        headers: {'Authorization': 'Bearer $trimmed'},
      );
      setState(() {
        _isKeyWorking = resp.statusCode == 200;
        _apiStatus = resp.statusCode == 200
            ? 'Ключ активен (OK)'
            : 'Ошибка ключа (${resp.statusCode})';
      });
    } catch (e) {
      setState(() {
        _isKeyWorking = false;
        _apiStatus = 'Ошибка сети';
      });
    } finally {
      setState(() => _isKeyValidating = false);
    }
  }

  Future<void> _saveSettingsOnly(String key, String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('groq_api_key', key.trim());
    await prefs.setString('groq_model', model);
    setState(() => _selectedModel = model);
    _showSnackbar('Настройки сохранены');
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Прикрепить изображение'),
              onTap: () async {
                Navigator.pop(ctx);
                final picked =
                    await ImagePicker().pickImage(source: ImageSource.gallery);
                if (picked != null) {
                  setState(() => _chatImage = File(picked.path));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('Прикрепить документ (.xlsx, .txt, .csv)'),
              onTap: () async {
                Navigator.pop(ctx);
                final res = await FilePicker.platform.pickFiles();
                if (res != null && res.files.single.path != null) {
                  setState(
                      () => _chatAttachedFile = File(res.files.single.path!));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<File> _getFirmsFile({required bool isPlaty}) async {
    final dir = await _getWorkDirPath();
    final name = isPlaty ? 'platy_firms.txt' : 'electroconnect_firms.txt';
    final file = File('$dir${Platform.pathSeparator}$name');
    if (!file.existsSync()) {
      final defaults = isPlaty ? _defaultPlatyFirms : _defaultElectroFirms;
      await file.writeAsString(defaults.join('\n'), encoding: utf8);
    }
    return file;
  }

  Future<void> _loadFirmsFromDisk({required bool isPlaty}) async {
    try {
      final file = await _getFirmsFile(isPlaty: isPlaty);
      final lines = await file.readAsLines(encoding: utf8);
      final cleaned = lines
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toSet()
          .toList();
      setState(() {
        if (isPlaty) {
          _platyFirms = cleaned;
        } else {
          _electroFirms = cleaned;
        }
      });
    } catch (_) {}
  }

  Future<void> _addFirmToDictionary({
    required bool isPlaty,
    required String rawName,
  }) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      _showSnackbar('Сначала впиши название фирмы!');
      return;
    }
    final list = isPlaty ? _platyFirms : _electroFirms;
    if (!list.any((e) => e.toLowerCase() == name.toLowerCase())) {
      list.insert(0, name);
      final file = await _getFirmsFile(isPlaty: isPlaty);
      await file.writeAsString(list.join('\n'), encoding: utf8);
      setState(() {});
      _showSnackbar('«$name» добавлена в справочник!');
    } else {
      _showSnackbar('Эта компания уже есть в списке.');
    }
  }

  Future<void> _removeFirmFromDictionary({
    required bool isPlaty,
    required String firmName,
  }) async {
    final list = isPlaty ? _platyFirms : _electroFirms;
    list.remove(firmName);
    final file = await _getFirmsFile(isPlaty: isPlaty);
    await file.writeAsString(list.join('\n'), encoding: utf8);
    setState(() {});
  }

  Future<void> _openFirmsTxtInNotepad({required bool isPlaty}) async {
    final file = await _getFirmsFile(isPlaty: isPlaty);
    if (Platform.isWindows) {
      await Process.start('notepad.exe', [file.path]);
    } else {
      await OpenFilex.open(file.path);
    }
  }

  String _escapePy(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', ' ');

  Future<void> _generateMajorExpressScript() async {
    final firm = _majorFirmController.text.trim();
    if (firm.isEmpty) {
      _showSnackbar('Укажи фирму-получателя!');
      return;
    }
    await _runMajorAutomation(
      isPlaty: false,
      login: 'Electroconnect',
      pass: 'Y2501212e4e5d62',
      firm: firm,
      date: _majorDateController.text.trim(),
      time: _majorTimeController.text.trim(),
      weight: _majorWeightController.text.trim(),
      places: _majorPlacesController.text.trim(),
      desc: _majorDescController.text.trim(),
      info: _majorInfoController.text.trim(),
    );
  }

  Future<void> _generatePlatyMajorExpressScript() async {
    final firm = _platyFirmController.text.trim();
    if (firm.isEmpty) {
      _showSnackbar('Укажи фирму-получателя!');
      return;
    }
    await _runMajorAutomation(
      isPlaty: true,
      login: 'Palat',
      pass: 'Z250121e9a7a762',
      firm: firm,
      date: _platyDateController.text.trim(),
      time: _platyTimeController.text.trim(),
      weight: _platyWeightController.text.trim(),
      places: _platyPlacesController.text.trim(),
      desc: _platyDescController.text.trim(),
      info: _platyInfoController.text.trim(),
    );
  }

  Future<void> _runMajorAutomation({
    required bool isPlaty,
    required String login,
    required String pass,
    required String firm,
    required String date,
    required String time,
    required String weight,
    required String places,
    required String desc,
    required String info,
  }) async {
    final workDir = await _getWorkDirPath();
    final prefix = isPlaty ? 'major_platy' : 'major_electro';
    final scriptPath = '$workDir${Platform.pathSeparator}${prefix}_auto.py';

    final pyCode = '''
# -*- coding: utf-8 -*-
import os
import time
import subprocess
from playwright.sync_api import sync_playwright

LOGIN = '${_escapePy(login)}'
PASSWORD = '${_escapePy(pass)}'
FIRM_NAME = '${_escapePy(firm)}'
PICKUP_DATE = '${_escapePy(date)}'
PICKUP_TIME = '${_escapePy(time)}'
WEIGHT = '${_escapePy(weight)}'
PLACES = '${_escapePy(places)}'
DESCRIPTION = '${_escapePy(desc)}'
EXTRA_INFO = '${_escapePy(info)}'
WORK_DIR = r'$workDir'

def print_pdf_silent(pdf_path):
    sumatra_local = os.path.join(WORK_DIR, 'SumatraPDF.exe')
    sumatra_exe = sumatra_local if os.path.exists(sumatra_local) else 'SumatraPDF.exe'
    try:
        subprocess.run([sumatra_exe, '-print-to-default', '-silent', pdf_path], check=True)
        print('PDF отправлен на печать:', pdf_path)
    except Exception as e:
        print('Ошибка печати SumatraPDF:', e)

def main():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        context = browser.new_context(accept_downloads=True)
        page = context.new_page()
        page.goto('https://lk.major-express.ru/login.aspx?ReturnUrl=%2f', timeout=60000)

        page.locator('input[type="text"]').first.fill(LOGIN)
        page.locator('input[type="password"]').first.fill(PASSWORD)
        page.locator('input[type="submit"], button:has-text("Войти")').first.click()
        page.wait_for_load_state('networkidle')

        page.goto('https://lk.major-express.ru/Templates.aspx', timeout=60000)
        page.wait_for_timeout(1500)

        search_inputs = page.locator('input[type="text"]')
        if search_inputs.count() > 0:
            search_inputs.first.fill(FIRM_NAME)
            page.keyboard.press('Enter')
            page.wait_for_timeout(1500)

        create_btn = page.locator('a:has-text("Создать"), button:has-text("Создать")').first
        if create_btn.count() > 0:
            create_btn.click()
            page.wait_for_load_state('networkidle')
            page.wait_for_timeout(1200)

            inputs = page.locator('input[type="text"]')
            for idx in range(inputs.count()):
                el = inputs.nth(idx)
                name_attr = (el.get_attribute('name') or '').lower()
                id_attr = (el.get_attribute('id') or '').lower()
                if 'weight' in name_attr or 'weight' in id_attr or 'вес' in name_attr:
                    el.fill(WEIGHT)
                elif 'place' in name_attr or 'place' in id_attr or 'мест' in name_attr:
                    el.fill(PLACES)
                elif 'desc' in name_attr or 'cargo' in id_attr:
                    el.fill(DESCRIPTION)
                elif 'date' in name_attr or 'date' in id_attr:
                    el.fill(PICKUP_DATE)

            if EXTRA_INFO:
                areas = page.locator('textarea')
                if areas.count() > 0:
                    areas.first.fill(EXTRA_INFO)

        try:
            with page.expect_download(timeout=120000) as download_info:
                pass
            download = download_info.value
            pdf_target = os.path.join(WORK_DIR, f'major_{int(time.time())}.pdf')
            download.save_as(pdf_target)
            print_pdf_silent(pdf_target)
        except Exception:
            pass

        page.wait_for_timeout(15000)

if __name__ == '__main__':
    main()
''';

    await File(scriptPath).writeAsString(pyCode, encoding: utf8);

    setState(() {
      if (isPlaty) {
        _lastPlatyAction = 'Оформлено: $firm';
      } else {
        _lastMajorAction = 'Оформлено: $firm';
      }
    });

    await _addOperationLog(
      isPlaty ? 'Печатные платы (Major)' : 'Электроконнект (Major)',
      'Запуск оформления: $firm',
      'Дата: $date ($time), Вес: $weight кг, Мест: $places',
    );

    if (Platform.isWindows) {
      try {
        await Process.start('python', [scriptPath], workingDirectory: workDir);
        _showSnackbar('Запущен робот Major Express для: $firm');
      } catch (e) {
        _showSnackbar('Скрипт сохранён: $scriptPath (ошибка python: $e)');
      }
    } else {
      await _shareScriptByPath(scriptPath);
    }
  }

  Future<void> _shareScriptByPath(String path) async {
    if (Platform.isWindows) {
      final workDir = await _getWorkDirPath();
      await Process.start('python', [path], workingDirectory: workDir);
      _showSnackbar('Повторный запуск скрипта...');
    } else {
      await Share.shareXFiles([XFile(path)], text: 'Скрипт Major Express');
    }
  }

  String _normalizePathInput(String raw) {
    var s = raw.trim();
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1).trim();
    }
    return s;
  }

  Future<void> _syncFileFromPath(int type, String rawPath) async {
    final cleaned = _normalizePathInput(rawPath);
    final prefs = await SharedPreferences.getInstance();
    final key = type == 1
        ? 'saved_path_posylka'
        : (type == 2 ? 'saved_path_svodka_pp' : 'saved_path_svodka_fil');
    await prefs.setString(key, cleaned);

    setState(() {
      final f = cleaned.isNotEmpty && File(cleaned).existsSync()
          ? File(cleaned)
          : null;
      if (type == 1) _posylkaFile = f;
      if (type == 2) _svodkaPpFile = f;
      if (type == 3) _svodkaFilialFile = f;
    });
  }

  Future<void> _pickFile(int type) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    if (type == 1) _posylkaPathController.text = path;
    if (type == 2) _svodkaPpPathController.text = path;
    if (type == 3) _svodkaFilialPathController.text = path;
    await _syncFileFromPath(type, path);
  }

  String _extractDigitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  int _deliverySortWeight(String d) {
    final low = d.toLowerCase();
    if (low.contains('дм')) return 1;
    if (low.contains('сдэк')) return 2;
    if (low == 'к' || low.contains('курьер')) return 3;
    if (low.contains('самовывоз')) return 4;
    return 5;
  }

  String _mapDeliveryCell(String raw) {
    final low = raw.toLowerCase().trim();
    if (low.isEmpty) return '';
    if (low.contains('самовывоз')) return 'Самовывоз';
    if (low.contains('сдэк') || low.contains('cdek')) return 'СДЭК';
    if (low.contains('дм') || low.contains('деловые')) return 'ДМ';
    if (low == 'к' || low.contains('курьер') || low.contains('major')) {
      return 'К';
    }
    return '';
  }

  Future<void> _processLogistics() async {
    final p1 = _normalizePathInput(_posylkaPathController.text);
    if (p1.isEmpty || !File(p1).existsSync()) {
      _showSnackbar('Укажи существующий файл «1. Посылка»!');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final posylkaFile = File(p1);
      final fileName = posylkaFile.path.split(Platform.pathSeparator).last;

      final posylkaRows = await _extractSheetMatrix(posylkaFile, maxCols: 15);
      final List<LogisticsItem> headItems = [];
      final List<LogisticsItem> filialItems = [];
      bool inFilialSection = false;
      String foundHeaderDate = '';

      for (final row in posylkaRows) {
        final joined = row.join(' ').trim();
        if (joined.isEmpty) continue;

        final lowRow0 = row[0].toLowerCase().trim();
        if (joined.toLowerCase().contains('отправка') &&
            foundHeaderDate.isEmpty) {
          foundHeaderDate = row.firstWhere(
              (c) => c.toLowerCase().contains('отправка'),
              orElse: () => '');
        }
        if (lowRow0 == 'филиал') {
          inFilialSection = true;
          continue;
        }
        if (lowRow0.contains('фирма') && joined.toLowerCase().contains('ps')) {
          continue;
        }

        final psCandidate = _extractDigitsOnly(row[1]);
        if (psCandidate.length < 5) continue;

        final item = LogisticsItem(
          firm: row[0].trim(),
          ps: psCandidate,
          schetPp: row.length > 2 ? row[2].trim() : '',
          schN: row.length > 3 ? row[3].trim() : '',
          poSchetu: row.length > 4 ? row[4].trim() : '',
          polucheno: row.length > 5 ? row[5].trim() : '',
          otgruzit: row.length > 6 ? row[6].trim() : '',
          etiketka: row.length > 7 ? row[7].trim() : '',
          naSklade: row.length > 8 ? row[8].trim() : '',
          dolg: row.length > 9 ? row[9].trim() : '',
          dostavka: row.length > 10 ? row[10].trim() : '',
          rashodnaya: row.length > 11 ? row[11].trim() : '',
          major: row.length > 12 ? row[12].trim() : '',
        );

        if (inFilialSection) {
          filialItems.add(item);
        } else {
          headItems.add(item);
        }
      }

      _lastOtpravkaHeader = foundHeaderDate;

      final Map<String, Map<String, String>> ppByPs = {};
      final p2 = _normalizePathInput(_svodkaPpPathController.text);
      if (p2.isNotEmpty && File(p2).existsSync()) {
        final ppRows = await _extractSheetMatrix(File(p2), maxCols: 16);
        String curFirm = '', curSchet = '', curDelivery = '';

        for (final r in ppRows) {
          final mapped = _mapDeliveryCell(r.join(' '));
          if (mapped.isNotEmpty) curDelivery = mapped;

          for (int c = 0; c < r.length; c++) {
            final cell = r[c].trim();
            if (cell.isEmpty) continue;
            if (RegExp(r'^(ООО|АО|ПАО|ЗАО|ФГУП|ИП)\b', caseSensitive: false)
                .hasMatch(cell)) {
              curFirm = cell;
            }
            if (RegExp(r'^\d{3,4}$').hasMatch(cell) && c <= 3) {
              curSchet = cell;
            }
            final digits = _extractDigitsOnly(cell);
            if (digits.length >= 5) {
              final qty =
                  (c + 1 < r.length) ? _extractDigitsOnly(r[c + 1]) : '';
              ppByPs[digits] = {
                'firm': curFirm,
                'schetPp': curSchet,
                'poSchetu': qty,
                'dostavka': curDelivery,
              };
            }
          }
        }
      }

      final Map<String, Map<String, String>> filBySchnPs = {};
      final Map<String, Map<String, String>> filByPs = {};
      final p3 = _normalizePathInput(_svodkaFilialPathController.text);
      if (p3.isNotEmpty && File(p3).existsSync()) {
        final filRows = await _extractSheetMatrix(File(p3), maxCols: 16);
        String currentFirm = '', currentSchn = '', currentDelivery = '';

        for (final r in filRows) {
          String psVal = '', qtyVal = '';
          for (int c = 0; c < r.length; c++) {
            final val = r[c].trim();
            if (val.isEmpty) continue;
            if (RegExp(r'^(ООО|АО|ПАО|ЗАО|ФГУП|ИП)\b', caseSensitive: false)
                .hasMatch(val)) {
              currentFirm = val;
            }
            if (RegExp(r'^\d{3,4}$').hasMatch(val) && c <= 3) {
              currentSchn = val;
            }
            final d = _extractDigitsOnly(val);
            if (d.length >= 5) {
              psVal = d;
              if (c + 1 < r.length) qtyVal = _extractDigitsOnly(r[c + 1]);
            }
            final mapped = _mapDeliveryCell(val);
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
          item.poSchetu =
              item.polucheno.isNotEmpty ? item.polucheno : item.otgruzit;
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
        if (item.poSchetu.isEmpty) {
          item.poSchetu =
              item.polucheno.isNotEmpty ? item.polucheno : item.otgruzit;
        }
        final fLow = item.firm.toLowerCase();
        if (fLow.contains('нейрософт') || fLow.contains('кузьминский')) {
          item.dostavka = 'К';
        } else if (fLow.contains('атб-электроника') ||
            fLow.contains('атб электроника')) {
          item.dostavka = 'ДМ';
        } else if (item.dostavka.isEmpty) {
          item.dostavka = 'К';
        }
      }

      headItems.sort((a, b) => _deliverySortWeight(a.dostavka)
          .compareTo(_deliverySortWeight(b.dostavka)));
      filialItems.sort((a, b) => _deliverySortWeight(a.dostavka)
          .compareTo(_deliverySortWeight(b.dostavka)));

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
        _lastHeadCount = headItems.length;
        _lastFilialCount = filialItems.length;
        _lastLogisticsAction =
            'Голова: ${headItems.length} • Филиал: ${filialItems.length}';
      });

      final summaryMsg =
          '✅ Накладная сведена автоматически!\n• Голова: ${headItems.length} поз.\n• Филиал: ${filialItems.length} поз.\n\n```csv\n$finalCsv\n```';

      _appendMessage('assistant', summaryMsg);
      await _addOperationLog(
        'Сведение накладных',
        'Успешно сведено ($fileName)',
        'Голова: ${headItems.length}, Филиал: ${filialItems.length}',
      );
    } catch (e) {
      await _addOperationLog(
          'Сведение накладных', 'Ошибка сведения', '$e',
          isError: true);
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

    final List<String> sharedStrings = [];
    final sharedStringsFile = archive.findFile('xl/sharedStrings.xml');
    if (sharedStringsFile != null) {
      final document = XmlDocument.parse(utf8.decode(
          sharedStringsFile.content as List<int>,
          allowMalformed: true));
      for (final si in document.findAllElements('si')) {
        final textBuffer = StringBuffer();
        for (final t in si.findAllElements('t')) {
          textBuffer.write(t.innerText);
        }
        sharedStrings.add(textBuffer
            .toString()
            .replaceAll(';', ' ')
            .replaceAll('\n', ' ')
            .trim());
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

      final Map<String, String> rIdToTarget = {};
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
              f.name.startsWith('xl/worksheets/sheet') &&
              f.name.endsWith('.xml'))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (sheetFiles.isNotEmpty) targetSheetFile = sheetFiles.first;
    }

    if (targetSheetFile == null) return [];

    final sheetDoc = XmlDocument.parse(
        utf8.decode(targetSheetFile.content as List<int>, allowMalformed: true));
    final List<List<String>> matrix = [];

    for (final rowEl in sheetDoc.findAllElements('row')) {
      final cells = rowEl.findAllElements('c').toList();
      if (cells.isEmpty) continue;
      final List<String> rowValues = List.filled(maxCols, '');
      bool hasAnyData = false;

      for (final c in cells) {
        final ref = c.getAttribute('r') ?? '';
        final colIdx = _columnLettersToIndex(ref);
        if (colIdx < 0 || colIdx >= maxCols) continue;

        final type = c.getAttribute('t');
        String cellVal = '';
        if (type == 's') {
          final idx =
              int.tryParse(c.findElements('v').firstOrNull?.innerText ?? '');
          if (idx != null && idx >= 0 && idx < sharedStrings.length) {
            cellVal = sharedStrings[idx];
          }
        } else if (type == 'inlineStr') {
          cellVal = c.findAllElements('t').firstOrNull?.innerText ?? '';
        } else {
          cellVal = c.findElements('v').firstOrNull?.innerText ?? '';
        }
        cellVal = cellVal.replaceAll(';', ' ').replaceAll('\n', ' ').trim();
        if (cellVal.isNotEmpty) hasAnyData = true;
        rowValues[colIdx] = cellVal;
      }
      if (hasAnyData) matrix.add(rowValues);
    }
    return matrix;
  }

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
    return ex.CellStyle(
      fontFamily: 'Tahoma',
      fontSize: fontSize,
      bold: true,
      fontColorHex: ex.ExcelColor.fromHexString(fontHex),
      backgroundColorHex: (bgHex != null && bgHex.isNotEmpty)
          ? ex.ExcelColor.fromHexString(bgHex)
          : ex.ExcelColor.none,
      horizontalAlign: hAlign,
      verticalAlign: ex.VerticalAlign.Center,
      textWrapping: wrapText ? ex.TextWrapping.WrapText : null,
      leftBorder: borderThick,
      rightBorder: borderThick,
      topBorder: borderThick,
      bottomBorder: borderThick,
    );
  }

  void _styleEmptyRowWithThickGrid(ex.Sheet sheet, int rowIndex,
      {double rowHeight = 22}) {
    sheet.setRowHeight(rowIndex, rowHeight);
    for (int c = 0; c < 13; c++) {
      final cell = sheet.cell(
          ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex));
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

      const colWidths = [
        56.0,
        15.0,
        13.0,
        14.0,
        14.0,
        15.0,
        16.0,
        14.0,
        15.0,
        12.0,
        18.0,
        30.0,
        24.0
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
      final headerCells = rawLines[0].split(';');
      sheet.setRowHeight(currentRow, 42);
      for (int c = 0; c < 13; c++) {
        final val = c < headerCells.length ? headerCells[c].trim() : '';
        final cell = sheet.cell(
            ex.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: currentRow));
        cell.value = ex.TextCellValue(val);
        cell.cellStyle = _buildCellStyle(
          fontSize: c == 0 ? 16 : 13,
          fontHex: (c == 6 || c == 8) ? '#FFFF0000' : '#FFFFFFFF',
          bgHex: (c == 6 || c == 8) ? '#FFFFFF00' : '#FF00B0AC',
          hAlign: c == 0 ? ex.HorizontalAlign.Left : ex.HorizontalAlign.Center,
          wrapText: true,
        );
      }
      currentRow++;
      _styleEmptyRowWithThickGrid(sheet, currentRow, rowHeight: 18);
      currentRow++;

      if (_lastOtpravkaHeader.isNotEmpty) {
        _styleEmptyRowWithThickGrid(sheet, currentRow, rowHeight: 26);
        final dateCell = sheet.cell(
            ex.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentRow));
        dateCell.value = ex.TextCellValue(_lastOtpravkaHeader);
        dateCell.cellStyle = _buildCellStyle(
            fontSize: 16,
            fontHex: '#FF9C0006',
            hAlign: ex.HorizontalAlign.Left);
        currentRow++;
        _styleEmptyRowWithThickGrid(sheet, currentRow, rowHeight: 18);
        currentRow++;
      }

      bool isInsideFilialBlock = false;
      for (int i = 1; i < rawLines.length; i++) {
        final cells = rawLines[i].split(';');
        final firstColLower =
            cells.isNotEmpty ? cells[0].trim().toLowerCase() : '';
        final deliveryVal =
            cells.length > 10 ? cells[10].trim().toLowerCase() : '';

        if (firstColLower == 'филиал') {
          isInsideFilialBlock = true;
          _styleEmptyRowWithThickGrid(sheet, currentRow, rowHeight: 18);
          currentRow++;
          _styleEmptyRowWithThickGrid(sheet, currentRow, rowHeight: 28);
          final filCell = sheet.cell(ex.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: currentRow));
          filCell.value = ex.TextCellValue('филиал');
          filCell.cellStyle = _buildCellStyle(
              fontSize: 18,
              fontHex: '#FFFFFFFF',
              bgHex: '#FFFF0000',
              hAlign: ex.HorizontalAlign.Center);
          currentRow++;
          _styleEmptyRowWithThickGrid(sheet, currentRow, rowHeight: 18);
          currentRow++;
          continue;
        }

        sheet.setRowHeight(currentRow, 28);
        final isSamovyvoz = deliveryVal.contains('самовывоз');
        final isSdek = deliveryVal.contains('сдэк');

        for (int c = 0; c < 13; c++) {
          final val = c < cells.length ? cells[c].trim() : '';
          final cell = sheet.cell(ex.CellIndex.indexByColumnRow(
              columnIndex: c, rowIndex: currentRow));
          if (c >= 4 && c <= 6 && int.tryParse(val) != null) {
            cell.value = ex.IntCellValue(int.parse(val));
          } else {
            cell.value = ex.TextCellValue(val);
          }

          String? bgColor = isSamovyvoz
              ? (!isInsideFilialBlock ? '#FFFF99CC' : '#FFFFC000')
              : null;
          String fontColor = '#FF000000';
          if (c == 2 && val.isNotEmpty) fontColor = '#FFFF0000';
          if (c == 7 && val.toUpperCase() == 'ОТК') fontColor = '#FF0000FF';
          if (c == 6) fontColor = '#FFFF0000';
          if (c == 10 && val.isNotEmpty) {
            fontColor = isSdek ? '#FF000000' : '#FFFF0000';
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

      for (int r = currentRow; r < currentRow + 35; r++) {
        _styleEmptyRowWithThickGrid(sheet, r, rowHeight: 24);
      }

      final dir = await getApplicationDocumentsDirectory();
      final filePath =
          '${dir.path}${Platform.pathSeparator}Посылка_Сведение_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final fileBytes = excel.save();
      if (fileBytes != null) {
        await File(filePath).writeAsBytes(fileBytes);
        await _addOperationLog(
            'Экспорт Excel', 'Сформирован файл .xlsx', filePath);
        _showSnackbar('Excel сохранен: $filePath');
        await OpenFilex.open(filePath);
      }
    } catch (e) {
      await _addOperationLog('Экспорт Excel', 'Ошибка выгрузки', '$e',
          isError: true);
      _showSnackbar('Ошибка выгрузки: $e');
    }
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
    final displayPrompt = text.isNotEmpty
        ? text
        : (activeImage != null ? 'Что на фото?' : 'Проанализируй файл.');
    final docName = activeDoc?.path.split(Platform.pathSeparator).last;

    _chatInputController.clear();
    _appendMessage('user', displayPrompt,
        imagePath: activeImage?.path, fileName: docName);

    setState(() {
      _chatImage = null;
      _chatAttachedFile = null;
      _isLoading = true;
    });

    try {
      String finalPrompt = displayPrompt;
      String modelToUse = activeImage != null
          ? 'llama-3.2-11b-vision-preview'
          : _selectedModel;
      if (activeDoc != null && activeDoc.existsSync()) {
        final content = await _readAnyFileForChat(activeDoc);
        finalPrompt = '$displayPrompt\n\n=== ФАЙЛ ($docName) ===\n$content';
      }

      final responseText = await _callGroqWithHistory(
        apiKey: apiKey,
        model: modelToUse,
        systemInstruction:
            'Ты — Гена, персональный ассистент Шурика. Отвечай чётко и по делу на русском языке.',
        messages: _currentSession?.messages ?? [],
        overrideLastUserText: finalPrompt,
        imageFile: activeImage,
      );

      _appendMessage('assistant', responseText);
    } catch (e) {
      _appendMessage('system', 'Ошибка: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String> _readAnyFileForChat(File file) async {
    if (file.path.toLowerCase().endsWith('.xlsx')) {
      final rows = await _extractSheetMatrix(file, maxCols: 14);
      return rows.take(60).map((r) => r.join(';')).join('\n');
    }
    final bytes = await file.readAsBytes();
    final str = utf8.decode(bytes, allowMalformed: true);
    return str.length > 6500 ? '${str.substring(0, 6500)}\n...[Обрезано]' : str;
  }

  int _columnLettersToIndex(String cellRef) {
    final letters = cellRef.replaceAll(RegExp(r'[0-9]'), '').toUpperCase();
    int col = 0;
    for (int i = 0; i < letters.length; i++) {
      col = col * 26 + (letters.codeUnitAt(i) - 64);
    }
    return col - 1;
  }

  Future<String> _callGroqWithHistory({
    required String apiKey,
    required String model,
    required String systemInstruction,
    required List<ChatMessage> messages,
    String? overrideLastUserText,
    File? imageFile,
  }) async {
    final List> formatted = [
      {'role': 'system', 'content': systemInstruction}
    ];
    final startIdx = messages.length > 6 ? messages.length - 6 : 0;

    for (int i = startIdx; i < messages.length; i++) {
      final msg = messages[i];
      final isLast = i == messages.length - 1 && msg.role == 'user';
      final txt = (isLast && overrideLastUserText != null)
          ? overrideLastUserText
          : msg.text;
      if (isLast && imageFile != null) {
        final b64 = base64Encode(await imageFile.readAsBytes());
        formatted.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': txt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$b64'}
            },
          ]
        });
      } else {
        formatted.add({
          'role': msg.role == 'user' ? 'user' : 'assistant',
          'content': txt
        });
      }
    }

    final resp = await http.post(
      Uri.https('api.groq.com', '/openai/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $apiKey'
      },
      body: jsonEncode({
        'model': model,
        'temperature': 0.2,
        'max_tokens': 950,
        'messages': formatted
      }),
    );
    final body = utf8.decode(resp.bodyBytes);
    if (resp.statusCode != 200) throw Exception('Groq (${resp.statusCode}): $body');
    final data = jsonDecode(body) as Map;
    final content =
        (data['choices'] as List).first['message']['content'].toString();
    return content.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
  }

  void _appendMessage(String role, String text,
      {String? imagePath, String? fileName}) {
    if (_currentSession == null) return;
    setState(() {
      _currentSession!.messages.add(ChatMessage(
          role: role, text: text, imagePath: imagePath, fileName: fileName));
      if (_currentSession!.messages.length == 1 && role == 'user') {
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
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    );
  }

  Color get _cardBg => widget.isDark ? const Color(0xFF111827) : Colors.white;
  Color get _sidebarBg =>
      widget.isDark ? const Color(0xFF0D1320) : const Color(0xFFF8FAFC);
  Color get _borderCol =>
      widget.isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);
  Color get _subtleText =>
      widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  Widget _styledInputField({
    required TextEditingController controller,
    required String label,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12.5, color: _subtleText),
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        filled: true,
        fillColor: widget.isDark
            ? const Color(0xFF182235)
            : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _borderCol)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _borderCol)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 840;
    return Scaffold(
      drawer:
          isWide ? null : Drawer(child: _buildSidebarContent(isDrawer: true)),
      body: Row(
        children: [
          if (isWide) _buildSidebarContent(isDrawer: false),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(isWide: isWide),
                Expanded(child: _buildActiveWorkspace()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarContent({required bool isDrawer}) {
    final collapsed = !isDrawer && _isSidebarCollapsed;
    final navItems = [
      (
        index: 0,
        title: 'Обзор и Чат',
        subtitle: 'Главная панель',
        icon: Icons.dashboard_rounded,
        color: const Color(0xFF14B8A6)
      ),
      (
        index: 1,
        title: 'Сведение накладных',
        subtitle: 'Посылка / Сводки',
        icon: Icons.table_chart_rounded,
        color: const Color(0xFF38BDF8)
      ),
      (
        index: 2,
        title: 'Электроконнект',
        subtitle: 'Major Express',
        icon: Icons.local_shipping_rounded,
        color: const Color(0xFFF59E0B)
      ),
      (
        index: 3,
        title: 'Печатные платы',
        subtitle: 'Major Express',
        icon: Icons.developer_board_rounded,
        color: const Color(0xFFA855F7)
      ),
      (
        index: 4,
        title: 'Журнал операций',
        subtitle: 'История и логи',
        icon: Icons.history_rounded,
        color: const Color(0xFF10B981)
      ),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: collapsed ? 74 : 255,
      decoration: BoxDecoration(
          color: _sidebarBg,
          border: Border(right: BorderSide(color: _borderCol))),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: collapsed ? 12 : 16, vertical: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF14B8A6), Color(0xFF0284C7)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        const Icon(Icons.memory, color: Colors.white, size: 22),
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Печатные платы',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis),
                          Text('Logistics v3.0',
                              style:
                                  TextStyle(fontSize: 11, color: _subtleText)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: _borderCol),
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                itemCount: navItems.length,
                itemBuilder: (context, idx) {
                  final item = navItems[idx];
                  final isSelected = _selectedNavIndex == item.index;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() => _selectedNavIndex = item.index);
                      if (isDrawer) Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: EdgeInsets.symmetric(
                          horizontal: collapsed ? 0 : 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? item.color.withOpacity(0.16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: isSelected
                                ? item.color.withOpacity(0.45)
                                : Colors.transparent),
                      ),
                      child: collapsed
                          ? Center(
                              child: Icon(item.icon,
                                  color: isSelected ? item.color : _subtleText,
                                  size: 22))
                          : Row(
                              children: [
                                Icon(item.icon,
                                    color:
                                        isSelected ? item.color : _subtleText,
                                    size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.title,
                                          style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500),
                                          overflow: TextOverflow.ellipsis),
                                      Text(item.subtitle,
                                          style: TextStyle(
                                              fontSize: 11, color: _subtleText),
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: _borderCol),
            if (!collapsed && Platform.isWindows)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Icon(
                      _sumatraFound
                          ? Icons.print_rounded
                          : Icons.warning_amber_rounded,
                      size: 16,
                      color: _sumatraFound
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _sumatraFound
                            ? 'SumatraPDF.exe готов'
                            : 'SumatraPDF.exe не найден',
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.spaceBetween,
                children: [
                  if (!collapsed)
                    TextButton.icon(
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text('Настройки',
                          style: TextStyle(fontSize: 12)),
                      onPressed: () => _showSettingsDialog(context),
                    ),
                  if (!isDrawer)
                    IconButton(
                      icon: Icon(
                          collapsed
                              ? Icons.keyboard_double_arrow_right
                              : Icons.keyboard_double_arrow_left,
                          size: 20,
                          color: _subtleText),
                      onPressed: () async {
                        final next = !_isSidebarCollapsed;
                        setState(() => _isSidebarCollapsed = next);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('sidebar_collapsed', next);
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

  Widget _buildTopBar({required bool isWide}) {
    const titles = [
      'Обзор и ИИ-ассистент',
      'Сведение накладных (Посылка / Сводки)',
      'Электроконнект — Major Express',
      'Печатные платы — Major Express',
      'Журнал операций',
    ];

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
          color: _cardBg,
          border: Border(bottom: BorderSide(color: _borderCol))),
      child: Row(
        children: [
          if (!isWide)
            Builder(
              builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(ctx).openDrawer()),
            ),
          Expanded(
            child: Text(titles[_selectedNavIndex],
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: Icon(
                widget.isDark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                size: 20),
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
              icon: const Icon(Icons.chat_bubble_outline, size: 20),
              onPressed: () => _showChatsDrawer(context)),
          IconButton(
              icon: const Icon(Icons.settings_outlined, size: 20),
              onPressed: () => _showSettingsDialog(context)),
        ],
      ),
    );
  }

  Widget _buildActiveWorkspace() {
    switch (_selectedNavIndex) {
      case 0:
        return _buildDashboardAndChatView();
      case 1:
        return _buildLogisticsWorkspace();
      case 2:
        return _buildMajorCourierWorkspace(isPlaty: false);
      case 3:
        return _buildMajorCourierWorkspace(isPlaty: true);
      case 4:
        return _buildLogsWorkspace();
      default:
        return _buildDashboardAndChatView();
    }
  }

  Widget _buildDashboardAndChatView() {
    final rawMessages = _currentSession?.messages ?? [];
    final cards = [
      (
        navIdx: 1,
        title: 'Сведение накладных',
        subtitle: 'Посылка + ПП + Филиал',
        metric: _lastLogisticsAction,
        icon: Icons.table_chart_rounded,
        accent: const Color(0xFF38BDF8)
      ),
      (
        navIdx: 2,
        title: 'Электроконнект',
        subtitle: 'Major Express',
        metric: _lastMajorAction,
        icon: Icons.local_shipping_rounded,
        accent: const Color(0xFFF59E0B)
      ),
      (
        navIdx: 3,
        title: 'Печатные платы',
        subtitle: 'Major Express',
        metric: _lastPlatyAction,
        icon: Icons.developer_board_rounded,
        accent: const Color(0xFFA855F7)
      ),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: cards
                .map((c) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () =>
                              setState(() => _selectedNavIndex = c.navIdx),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                                color: _cardBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _borderCol)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(c.icon, color: c.accent, size: 22),
                                const SizedBox(height: 8),
                                Text(c.title,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis),
                                Text(c.subtitle,
                                    style: TextStyle(
                                        fontSize: 11.5, color: _subtleText),
                                    overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 6),
                                Text(c.metric,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: c.accent),
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: rawMessages.isEmpty
              ? Center(
                  child: Text('Выбери модуль сверху или напиши вопрос в чат',
                      style: TextStyle(fontSize: 14, color: _subtleText)))
              : ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  itemCount: rawMessages.length,
                  itemBuilder: (context, idx) {
                    final m = rawMessages[idx];
                    final isUser = m.role == 'user';
                    return Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.78),
                        decoration: BoxDecoration(
                          color: isUser ? const Color(0xFF0F766E) : _cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _borderCol),
                        ),
                        child: SelectableText(m.text,
                            style: const TextStyle(fontSize: 14.5)),
                      ),
                    );
                  },
                ),
        ),
        _buildChatInputArea(),
      ],
    );
  }

  Widget _buildLogisticsWorkspace() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _borderCol)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Автоматическое сведение накладных',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildFilePathCard(
                        type: 1,
                        step: '1. Посылка (Обязательно)',
                        controller: _posylkaPathController,
                        accent: const Color(0xFF38BDF8)),
                    const SizedBox(height: 12),
                    _buildFilePathCard(
                        type: 2,
                        step: '2. Сводка ПП (Голова)',
                        controller: _svodkaPpPathController,
                        accent: const Color(0xFF14B8A6)),
                    const SizedBox(height: 12),
                    _buildFilePathCard(
                        type: 3,
                        step: '3. Сводка Филиал (ЭЛЕКТРОконнект)',
                        controller: _svodkaFilialPathController,
                        accent: const Color(0xFFA855F7)),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15)),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(
                                _isLoading
                                    ? 'ИДЁТ СВЕДЕНИЕ...'
                                    : 'СВЕСТИ НАКЛАДНУЮ',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            onPressed: _isLoading ? null : _processLogistics,
                          ),
                        ),
                        if (_lastCsvResult != null) ...[
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF16A34A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 15)),
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('СКАЧАТЬ EXCEL (.XLSX)',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: _exportToFormattedExcel,
                          ),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
              if (_lastCsvResult != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _borderCol)),
                  child: SelectableText(_lastCsvResult!,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12.5)),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilePathCard(
      {required int type,
      required String step,
      required TextEditingController controller,
      required Color accent}) {
    final cleaned = _normalizePathInput(controller.text);
    final fileExists = cleaned.isNotEmpty && File(cleaned).existsSync();
    return Row(
      children: [
        Expanded(
          child: _styledInputField(
            controller: controller,
            label: '$step ${fileExists ? "(Файл найден)" : ""}',
            icon: Icons.folder_open_rounded,
            onChanged: (val) => _syncFileFromPath(type, val),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: accent.withOpacity(0.18),
              foregroundColor: accent,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: const Text('Обзор'),
          onPressed: () => _pickFile(type),
        ),
      ],
    );
  }

  Widget _buildMajorCourierWorkspace({required bool isPlaty}) {
    final accent =
        isPlaty ? const Color(0xFFA855F7) : const Color(0xFFF59E0B);
    final firmCtrl = isPlaty ? _platyFirmController : _majorFirmController;
    final dateCtrl = isPlaty ? _platyDateController : _majorDateController;
    final timeCtrl = isPlaty ? _platyTimeController : _majorTimeController;
    final weightCtrl =
        isPlaty ? _platyWeightController : _majorWeightController;
    final placesCtrl =
        isPlaty ? _platyPlacesController : _majorPlacesController;
    final descCtrl = isPlaty ? _platyDescController : _majorDescController;
    final infoCtrl = isPlaty ? _platyInfoController : _majorInfoController;
    final searchCtrl =
        isPlaty ? _platyFirmSearchController : _majorFirmSearchController;
    final filter = isPlaty ? _platyFirmFilter : _majorFirmFilter;
    final fullList = isPlaty ? _platyFirms : _electroFirms;
    final filtered = filter.isEmpty
        ? fullList
        : fullList
            .where((f) => f.toLowerCase().contains(filter.toLowerCase()))
            .toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _borderCol)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        isPlaty
                            ? 'ООО «Печатные платы» — Major Express'
                            : 'ООО «ЭЛЕКТРОконнект» — Major Express',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                            child: _styledInputField(
                                controller: firmCtrl,
                                label: 'Фирма-получатель',
                                icon: Icons.business_rounded)),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('В базу'),
                          onPressed: () => _addFirmToDictionary(
                              isPlaty: isPlaty, rawName: firmCtrl.text),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: _styledInputField(
                                controller: dateCtrl,
                                label: 'Дата забора',
                                icon: Icons.calendar_today_rounded)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _styledInputField(
                                controller: timeCtrl,
                                label: 'Интервал времени',
                                icon: Icons.access_time_rounded)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: _styledInputField(
                                controller: weightCtrl,
                                label: 'Вес, кг',
                                icon: Icons.scale_rounded)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: _styledInputField(
                                controller: placesCtrl,
                                label: 'Мест',
                                icon: Icons.inventory_2_outlined)),
                        const SizedBox(width: 10),
                        Expanded(
                            flex: 2,
                            child: _styledInputField(
                                controller: descCtrl,
                                label: 'Описание',
                                icon: Icons.description_outlined)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _styledInputField(
                        controller: infoCtrl,
                        label: 'Примечание для курьера',
                        icon: Icons.info_outline_rounded),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15)),
                        icon: const Icon(Icons.rocket_launch_rounded),
                        label: const Text('ОФОРМИТЬ И РАСПЕЧАТАТЬ НАКЛАДНУЮ',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: isPlaty
                            ? _generatePlatyMajorExpressScript
                            : _generateMajorExpressScript,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _borderCol)),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text('Справочник (${fullList.length})',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold))),
                      IconButton(
                          icon: const Icon(Icons.edit_note_rounded),
                          onPressed: () =>
                              _openFirmsTxtInNotepad(isPlaty: isPlaty)),
                      IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          onPressed: () =>
                              _loadFirmsFromDisk(isPlaty: isPlaty)),
                    ],
                  ),
                  TextField(
                    controller: searchCtrl,
                    onChanged: (val) => setState(() => isPlaty
                        ? _platyFirmFilter = val.trim()
                        : _majorFirmFilter = val.trim()),
                    decoration: const InputDecoration(
                        hintText: 'Поиск фирмы...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, idx) {
                        final name = filtered[idx];
                        return ListTile(
                          dense: true,
                          title:
                              Text(name, style: const TextStyle(fontSize: 13)),
                          onTap: () => setState(() => firmCtrl.text = name),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 14),
                            onPressed: () => _removeFirmFromDictionary(
                                isPlaty: isPlaty, firmName: name),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsWorkspace() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _borderCol)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Журнал выполненных операций',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        setState(() => _operationLogs.clear());
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('operation_logs');
                      },
                      child: const Text('Очистить',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: _operationLogs.isEmpty
                      ? Center(
                          child: Text('История пока пуста',
                              style: TextStyle(color: _subtleText)))
                      : ListView.separated(
                          itemCount: _operationLogs.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: _borderCol),
                          itemBuilder: (context, idx) {
                            final item = _operationLogs[idx];
                            return ListTile(
                              title: Text(
                                  '[${item.module}] ${item.title} (${item.time})',
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(item.details,
                                  style: const TextStyle(fontSize: 12)),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: _cardBg,
          border: Border(top: BorderSide(color: _borderCol))),
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.attach_file_rounded),
              onPressed: _showAttachmentMenu),
          Expanded(
            child: TextField(
              controller: _chatInputController,
              decoration: const InputDecoration(
                  hintText: 'Напиши сообщение...', border: InputBorder.none),
              onSubmitted: (_) => _sendChatMessage(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded, color: Color(0xFF14B8A6)),
            onPressed: _isLoading ? null : _sendChatMessage,
          ),
        ],
      ),
    );
  }

  void _showChatsDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        height: 360,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('История чатов',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ElevatedButton(
                  onPressed: () {
                    _createNewChat();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Новый чат'),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _sessions.length,
                itemBuilder: (context, index) {
                  final s = _sessions[index];
                  return ListTile(
                    title: Text(s.title),
                    onTap: () {
                      setState(() => _currentSession = s);
                      Navigator.pop(ctx);
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _renameChat(s)),
                        IconButton(
                            icon: const Icon(Icons.delete, size: 18),
                            onPressed: () => _deleteChat(s)),
                      ],
                    ),
                  );
                },
              ),
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
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Настройки API'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: _apiKeyController,
                  decoration:
                      const InputDecoration(labelText: 'Ключ Groq API (gsk_...)')),
              const SizedBox(height: 10),
              Text(_apiStatus,
                  style: TextStyle(
                      color: _isKeyWorking == true
                          ? Colors.greenAccent
                          : Colors.orangeAccent)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: tempModel,
                items: _availableModels
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => tempModel = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена')),
            OutlinedButton(
              onPressed: _isKeyValidating
                  ? null
                  : () async {
                      await _validateKeyOnly(_apiKeyController.text);
                      setDialogState(() {});
                    },
              child: const Text('Проверить'),
            ),
            ElevatedButton(
              onPressed: () {
                _saveSettingsOnly(_apiKeyController.text, tempModel);
                Navigator.pop(ctx);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
