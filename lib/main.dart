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
import 'package:share_plus/share_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  runApp(const PechatnyePlatyApp());
}

class PechatnyePlatyApp extends StatefulWidget {
  const PechatnyePlatyApp({super.key});

  @override
  State<PechatnyePlatyApp> createState() => _PechatnyePlatyAppState();
}

class _PechatnyePlatyAppState extends State<PechatnyePlatyApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('is_dark_theme') ?? true;
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final nextDark = _themeMode != ThemeMode.dark;
    await prefs.setBool('is_dark_theme', nextDark);
    setState(() {
      _themeMode = nextDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Печатные платы Pro',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0F1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF14B8A6),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF111827),
          surfaceVariant: Color(0xFF1E293B),
          error: Color(0xFFEF4444),
        ),
        fontFamily: 'Roboto',
      ),
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0D9488),
          secondary: Color(0xFF0284C7),
          surface: Colors.white,
          surfaceVariant: Color(0xFFE2E8F0),
          error: Color(0xFFDC2626),
        ),
        fontFamily: 'Roboto',
      ),
      home: MainScreen(
        isDark: _themeMode == ThemeMode.dark,
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

class OperationLogEntry {
  final String time;
  final String module;
  final String title;
  final String details;
  final bool isError;

  OperationLogEntry({
    required this.time,
    required this.module,
    required this.title,
    required this.details,
    this.isError = false,
  });

  Map<String, dynamic> toJson() => {
        'time': time,
        'module': module,
        'title': title,
        'details': details,
        'isError': isError,
      };

  factory OperationLogEntry.fromJson(Map<String, dynamic> json) =>
      OperationLogEntry(
        time: json['time'] ?? '',
        module: json['module'] ?? '',
        title: json['title'] ?? '',
        details: json['details'] ?? '',
        isError: json['isError'] ?? false,
      );
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
  final bool isDark;
  final VoidCallback onToggleTheme;

  const MainScreen({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _chatInputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  // Контроллеры путей для Панели 1: Сведение накладных
  final TextEditingController _posylkaPathController = TextEditingController();
  final TextEditingController _svodkaPpPathController = TextEditingController();
  final TextEditingController _svodkaFilialPathController =
      TextEditingController();

  // Контроллеры для Панели 2: Электроконнект Мейджер Экспресс
  late final TextEditingController _majorFirmController;
  late final TextEditingController _majorDateController;
  late final TextEditingController _majorTimeController;
  late final TextEditingController _majorWeightController;
  late final TextEditingController _majorPlacesController;
  late final TextEditingController _majorDescController;
  late final TextEditingController _majorInfoController;
  final TextEditingController _majorFirmSearchController =
      TextEditingController();

  // Контроллеры для Панели 3: Платы Мейджер Экспресс
  late final TextEditingController _platyFirmController;
  late final TextEditingController _platyDateController;
  late final TextEditingController _platyTimeController;
  late final TextEditingController _platyWeightController;
  late final TextEditingController _platyPlacesController;
  late final TextEditingController _platyDescController;
  late final TextEditingController _platyInfoController;
  final TextEditingController _platyFirmSearchController =
      TextEditingController();

  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  static const MethodChannel _ttsChannel =
      MethodChannel('blackpocket/native_tts');

  int _selectedNavIndex = 0;
  bool _isSidebarCollapsed = false;
  String _searchQuery = '';
  bool _sumatraFound = false;

  bool _isLoading = false;
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
  List<OperationLogEntry> _operationLogs = [];

  List<String> _electroFirms = [];
  List<String> _platyFirms = [];
  String _majorFirmFilter = '';
  String _platyFirmFilter = '';

  String? _lastCsvResult;
  String _lastOtpravkaHeader = '';
  int _lastHeadCount = 0;
  int _lastFilialCount = 0;
  String? _lastGeneratedMajorScriptPath;
  String? _lastGeneratedPlatyScriptPath;
  String _lastMajorAction = 'Готов к запуску';
  String _lastPlatyAction = 'Готов к запуску';
  String _lastLogisticsAction = 'Ожидает файлы';

  final _availableModels = [
    'qwen/qwen3.8-27b',
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'llama-3.2-11b-vision-preview',
  ];

  String _selectedModel = 'qwen/qwen3.8-27b';

  // Встроенная база получателей Электроконнект (из шаблонов Major Express)
  static const List<String> _defaultElectroconnectFirms = [
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
    'ООО "Электроконнект" Питер',
    'ООО "Электроконнект" Санкт-Петербург',
    'Электроконнект Новосибирск завод',
    'ООО "ДИСТАНЦИЯ"',
    'АО "Мостком"',
    'ИП Лебедев Олег Александрович',
    'ООО "АТС Т"',
    'ООО "ПЛ ИНЖИНИРИНГ"',
    'АНО " Школа 21"',
    'ООО "АЙСИЭЛ ЭЛЕКТРОНИКС"',
    'ООО "КОМПАНИЯ "СТРИМ ЛАБС"',
    'ООО "Дельта Солюшнс"',
    'Упак-Лайнер',
    'ООО "Олл ин пром"',
    'ИП Гулин Станислав Евгеньевич',
    'АО "Научно-производственное "Рязаньприбор"',
    'АО"ГЗАС им Попова"',
    'ООО "Корд-группа"',
    'ООО "МИР-СПОРТ-ЦЕНТР"',
    'ЗАО "Сетевые Технологии"',
    'ООО "Лигель"',
    'ООО «АВТОМАТИКА плюс»',
    'ООО "Гидравлические Комплексные Системы"',
    'ООО "РТЦ"',
    'ООО" Грош Торг"',
    'АО "ИНФОРМТЕХНИКА И СВЯЗЬ"',
    'ООО "НПО "ОРИГИНАЛЬНЫЕ РУССКИЕ КОНТРОЛЛЕРЫ"',
    'ООО "НПО "ОРК"',
    'ООО "Деко-сервис"',
    'ИП Рухлов Дмитрий Сергеевич',
    'ООО"Натшелл"',
    'АО "НПО "Радиозавод им. А.С.Попова"',
    'ООО "Ателье Гончарова"',
    'АО "Электромеханика"',
    'ООО "РЭСТОК"',
    'ООО "МикроЭМ Технологии"',
    'ООО "Декаст"',
    'ООО "Технологии Света"',
    'АО ПФ "ЭЛВИРА"',
    'ООО "Гемодженикс"',
    'ООО "Комито"',
    'ООО "НПО "Вольт инжиниринг"',
    'ООО "Ревотех"',
    'ООО "Орион-Р"',
    'ООО "Трансаммиак"',
    'ООО "Промприбор-Р"',
    'ООО "Галс плюс"',
    'ООО НПО "Грань"',
    'ИП Козин Дмитрий Владимирович',
    'ООО "Нетстелл"',
    'ООО "ТИОН"',
    'ИП Отчерцов Андрей Владимирович',
    'ИП Румянцев Андрей Александрович',
    'АО "РНТ"',
    'Бриз-Ал',
    'ООО "РТК-Технологии"',
    'ООО "Мотив НТ"',
    'ООО ПКФ "Экс-Форма"',
    'КБ Урал',
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
    'ООО "ИЦ "Лебер"',
    'ООО "НПО "Визит" им. В.Ф. Сотникова"',
    'ООО "РЭМО-Технологии"',
    'ПАО "Вектор"',
    'ООО НПФ "Радиосервис"',
    'МФТИ, ФИЗТЕХ',
    'ИП Рыбкина Светлана Александровна',
    'ООО "Парк Чудес"',
    'ПАКС',
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
    'Аквариус Шуя',
    'Аквариус Тверь',
    'АО "КМК"',
    'ФГУП "ВНИИФТРИ"',
    'ООО "Интехпро"',
    'АО "Коралл-Телеком"',
    'АО "НИИП имени В.В. Тихомирова"',
    'ООО "ТУРКОВ"',
    'ООО "НИИКАМ"',
    'ООО "Три точки мануфактуринг"',
    'ООО "Неовэлл"',
    'ООО "СГ-Терм"',
    'ИП Громов Андрей Васильевич',
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
    'АО "НПО "Орион"',
    'АО "Лаборатория Электроники"',
    'АО "ОДК"',
    'ООО "Хьюман Филмс"',
    'ИП Кузьменко Лариса Юрьевна',
    'АО НПЦ "ЭЛВИС"',
    'ООО "Дантекс Рус"',
    'АО "Альбатрос"',
    'ООО "САУК"',
    'ООО "НТР"',
    'ООО "Инженерные решения"',
    'ООО "МКМ"',
    'ООО "СФТ центр"',
    'ООО "Зов птицы"',
    'ИП Смирнов Сергей Андреевич',
    'ООО "НПЦ "Аналитех"',
    'ООО "Кортэк"',
    'ООО "Монитрон"',
    'ООО "ЛТ"',
    'ООО "Экзоатлет"',
    'ООО "КБ Основание"',
    'ООО "Универсал Акустикс"',
    'АО "МикроЭМ"',
    'ООО "ФЛАВТ"',
    'ООО "РусИнтелл"',
    'АО "Центр ВОСПИ"',
    'ООО НПП "Фликс"',
    'ИП Талалаев Александр Леонидович',
    'ИП Инкин Владимир Викторович',
    'ООО "НПП Антарес"',
    'ООО УК "ЭТАЛОН"',
    'ООО "ТД « ДЕЛОВЫЕ ТЕХНОЛОГИИ"',
    'ООО"КОАЛИЦИЯ"',
    'ООО "СТМ-К"',
    'ИП Бизяев Юрий Михайлович',
    'ООО "Сомтек"',
    'ООО "Инвапром"',
    'АО "ГНПП "Регион"',
    'АО "ОКБ "Кристалл"',
    'ООО "Меанотек"',
    'ИП Потягова Инесса Геннадьевна',
    'ИП Есин Юрий Дмитриевич',
    'ООО "Радиоавтоматика"',
    'ООО "Промсветмонтаж"',
    'ООО "ЧЗПЭ"',
    'ООО "ПРОМАВТОМАТИКА – КД"',
    'ООО"ВКМЗ"',
    'ООО НПФ "ЭТНА ПЛЮС"',
    'ИП Лыга Михаил Александрович',
    'ООО НТЦ "ПИК"',
    'АО "ОКБ МЭИ"',
    'ИП Оголихин Александр Дмитриевич',
    'ООО "АП"',
    'ООО "Новиком"',
    'ООО "Арт Аудио Лаб"',
    'ООО "Ювента"',
    'ИП Лебедев Александр Владимирович',
    'ООО "АС Полюс"',
    'АО "ВПК НПО Машиностроения"',
    'ООО "Техноквант"',
    'ООО "АВБ Лабс"',
    'ООО "Л-Петро"',
    'ООО "Элдике-системы"',
    'ООО "СОРБ Инжиниринг"',
    'ООО "БА"',
    'АО "Термотехник-МЛ"',
    'ООО "РСВ Консалт"',
    'ООО "Ампермагнит"',
    'ООО "Группа компаний Эмулсол"',
    'ИПФ РАН',
    'ООО "ПЭ Контракт Электроника"',
    'ИП Катаев Роман Алексеевич',
    'ООО "ПИЭЛСИ Технолоджи"',
    'ООО" Электрорешения"',
    'ООО "Финанстерра"',
    'ООО "МПС"',
    'ООО "НПО Сфера Безопасности"',
    'АО "ЛИКК"',
    'АО "НПО "ПЭС"',
    'ООО "МСП"',
    'ИП Белова Татьяна Юрьевна',
    'ООО "НТЦ "Разработка сложных систем"',
    'ООО "НПП "Когерент"',
    'АО "САРАТОВСКИЙ АГРЕГАТНЫЙ ЗАВОД"',
    'ООО "Завод Конвертор"',
    'АО "ПОЗиС"',
    'ООО "Гумич РТК"',
    'ПАО "ЯЗКМ"',
    'ООО "ТЗВТО"',
    'ООО "Инферит"',
    'ООО "ТСДСТОР"',
    'АО "Авиакор - авиационный завод"',
    'ООО "АВСистемы"',
    'ООО "АДФ"',
    'ИП Дудулин Аркадий Львович',
    'ООО "ВЦТО"',
    'АО "Эка"',
    'ООО "НПП "МЕРА"',
    'ООО "Трансгард"',
    'ООО "Софтитек"',
    'ООО "Крокс Плюс"',
    'ООО "Основа Безопасности"',
    'АО "Микрон"',
    'ООО "НПП Энерготехника"',
    'АО "ТРИНИТИ СОЛЮШНС"',
    'ООО "ЭСВО"',
    'ИП Косых Бронислав Викторович',
    'Кузьмичев Дмитрий Олегович',
    'Аверьянов Юрий Иванович',
    'Виноградов Максим Владимирович',
    'Касьяненко Евгений Евгеньевич',
    'Воробьёв Сергей Викторович',
    'Максумов Осман Сары Оглы',
    'Сапаров Никита Сергеевич',
    'Иванов Алексей Валерьевич',
    'Евдокимов Даниил Алексеевич',
    'Куприянов Егор Сергеевич',
    'Вашкевич Сергей Александрович',
    'Алеев Азиз Шамильевич',
    'Войцеховский Сергей Евгеньевич',
    'Александр Кузнецов',
    'Киселёв Николай Владимирович',
    'Чесноков Артур Александрович',
    'Соколов Павел Андреевич',
    'Галаев Дмитрий Александрович',
    'Федянин Владислав Станиславович',
    'Равочкин Александр Сергеевич',
    'Ракуль Алексей Юрьевич',
    'Русанюк Роман Васильевич',
    'Клочков Роман Сергеевич',
    'Кадыков Павел Юрьевич',
    'Мельников Денис Юрьевич',
    'Киян Сергей Андреевич',
    'Притугин Алексей Валерьевич',
    'Лукин Кирилл Андреевич',
    'Плотников Игорь Владимирович',
    'Яковлев Михаил Валерьевич',
    'Шашков Павел Сергеевич',
    'Гусейнов Давуд Вадимович',
    'Донин Антон Сергеевич',
    'Смирнов Игорь Викторович',
    'Шахов Александр Юрьевич',
    'Ильичев Иван Геннадьевич',
    'Чепель Владимир Александрович',
    'Крутилин Алексей Владимирович',
    'Гончаров Дмитрий Михайлович',
    'Сильченко Анна Викторовна',
    'Орджоникидзе Михаил Андреевич',
    'Арефьев Денис Владимирович',
    'Грибов Алексей Алексеевич',
    'Левицкий Виктор Иосифович',
    'Чекмарев Николай Владимирович',
    'Кузьмин Александр Владиславович',
    'Полозов Виктор Иванович',
    'Прохоров Евгений Александрович',
    'Кондрашов Алексей Владимирович',
    'Киселев Василий Александрович',
    'Бровкин Олег Юрьевич',
    'Закора Игорь Викторович',
    'Попелышко Михаил Валентинович',
    'Бойченко Дмитрий Сергеевич',
    'Лещев Сергей Сергеевич',
    'Хорькин Андрей Юрьевич',
    'Шевелько Александр Петрович',
    'Козьменко Светлана Васильевна',
    'Ильин Ефим Алексеевич',
    'Нефедов Дмитрий Сергеевич',
    'Рупасов Дмитрий Васильевич',
    'Белоусов Дмитрий Николаевич',
    'Тиунов Михаил Юрьевич',
    'Кожухов Евгений Викторович',
    'Лавренко Олег Георгиевич',
    'Туровский Евгений Валерьевич',
    'Андреев Дмитрий Алексеевич',
    'Кнышев Александр Леонидович',
    'Субботин Валентин Викторович',
    'Романов Дмитрий Анатольевич',
    'Селивановский Всеволод Сергеевич',
    'Маслов Юрий Яковлевич',
    'Ерусланов Дмитрий Сергеевич',
    'Лукин Феликс Александрович',
    'Смирнов Алексей Викторович',
  ];

  String _todayFormatted() {
    final now = DateTime.now();
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    return '$d.$m.${now.year}';
  }

  String _nowTimeFormatted() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _normalizePathInput(String raw) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('"') &&
        cleaned.endsWith('"') &&
        cleaned.length >= 2) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }
    return cleaned;
  }

  @override
  void initState() {
    super.initState();
    final today = _todayFormatted();

    _majorFirmController = TextEditingController();
    _majorDateController = TextEditingController(text: today);
    _majorTimeController = TextEditingController(text: '14:00-18:00');
    _majorWeightController = TextEditingController(text: '1');
    _majorPlacesController = TextEditingController(text: '1');
    _majorDescController = TextEditingController(text: 'платы');
    _majorInfoController = TextEditingController(text: 'УПД');

    _platyFirmController = TextEditingController();
    _platyDateController = TextEditingController(text: today);
    _platyTimeController = TextEditingController(text: '14:00-18:00');
    _platyWeightController = TextEditingController(text: '1');
    _platyPlacesController = TextEditingController(text: '1');
    _platyDescController = TextEditingController(text: 'платы');
    _platyInfoController = TextEditingController(text: 'с/ч');

    WidgetsBinding.instance.addObserver(this);
    _checkSumatraPresence();
    _initFirmsDictionaries();
    _loadSettingsAndChats();
    _inputFocusNode.addListener(() {
      if (_inputFocusNode.hasFocus) {
        _scrollToBottom(delayMs: 300);
      }
    });
  }

  // =========================================================================
  // СПРАВОЧНИК КОМПАНИЙ В ТЕКСТОВОМ БЛОКНОТЕ (.TXT) + ПАМЯТЬ ПРОГРАММЫ
  // =========================================================================

  Future<File> _getFirmsDictionaryFile(bool isPlaty) async {
    final fileName = isPlaty ? 'platy_firms.txt' : 'electroconnect_firms.txt';
    if (Platform.isWindows) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      return File('$exeDir\\$fileName');
    }
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  Future<void> _initFirmsDictionaries() async {
    await _loadFirmsFromDisk(isPlaty: false);
    await _loadFirmsFromDisk(isPlaty: true);
  }

  Future<void> _loadFirmsFromDisk({required bool isPlaty}) async {
    try {
      final file = await _getFirmsDictionaryFile(isPlaty);
      if (!file.existsSync()) {
        final initialList =
            isPlaty ? <String>[] : List<String>.from(_defaultElectroconnectFirms);
        await file.writeAsString(initialList.join('\n'), encoding: utf8);
        setState(() {
          if (isPlaty) {
            _platyFirms = initialList;
          } else {
            _electroFirms = initialList;
          }
        });
        return;
      }

      final content = await file.readAsString(encoding: utf8);
      final parsed = content
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      if (!isPlaty && parsed.isEmpty) {
        parsed.addAll(_defaultElectroconnectFirms);
        await file.writeAsString(parsed.join('\n'), encoding: utf8);
      }

      setState(() {
        if (isPlaty) {
          _platyFirms = parsed;
        } else {
          _electroFirms = parsed;
        }
      });
    } catch (_) {
      if (!isPlaty) {
        setState(() {
          _electroFirms = List<String>.from(_defaultElectroconnectFirms);
        });
      }
    }
  }

  Future<void> _addFirmToDictionary({
    required bool isPlaty,
    required String rawName,
  }) async {
    final cleaned = rawName.trim();
    if (cleaned.isEmpty) {
      _showSnackbar('Сначала впиши название фирмы!');
      return;
    }

    final targetList = isPlaty ? _platyFirms : _electroFirms;
    if (targetList.any((e) => e.toLowerCase() == cleaned.toLowerCase())) {
      _showSnackbar('Эта компания уже есть в списке!');
      return;
    }

    final updated = [cleaned, ...targetList];
    setState(() {
      if (isPlaty) {
        _platyFirms = updated;
      } else {
        _electroFirms = updated;
      }
    });

    try {
      final file = await _getFirmsDictionaryFile(isPlaty);
      await file.writeAsString(updated.join('\n'), encoding: utf8);
      _showSnackbar('Добавлено в справочник: $cleaned');
    } catch (e) {
      _showSnackbar('Ошибка сохранения в файл: $e');
    }
  }

  Future<void> _removeFirmFromDictionary({
    required bool isPlaty,
    required String firmName,
  }) async {
    final targetList = isPlaty ? _platyFirms : _electroFirms;
    final updated = targetList.where((e) => e != firmName).toList();
    setState(() {
      if (isPlaty) {
        _platyFirms = updated;
      } else {
        _electroFirms = updated;
      }
    });
    try {
      final file = await _getFirmsDictionaryFile(isPlaty);
      await file.writeAsString(updated.join('\n'), encoding: utf8);
    } catch (_) {}
  }

  Future<void> _openFirmsTxtInNotepad({required bool isPlaty}) async {
    try {
      final file = await _getFirmsDictionaryFile(isPlaty);
      if (!file.existsSync()) {
        await file.writeAsString('', encoding: utf8);
      }
      await OpenFilex.open(file.path);
    } catch (e) {
      _showSnackbar('Не удалось открыть файл: $e');
    }
  }

  void _checkSumatraPresence() {
    if (!Platform.isWindows) return;
    final appExeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$appExeDir\\SumatraPDF.exe',
      r'C:\PechatnyePlaty\SumatraPDF.exe',
      r'C:\SumatraPDF.exe',
    ];
    final exists = candidates.any((p) => File(p).existsSync());
    setState(() {
      _sumatraFound = exists;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inputFocusNode.dispose();
    _searchController.dispose();

    _posylkaPathController.dispose();
    _svodkaPpPathController.dispose();
    _svodkaFilialPathController.dispose();

    _majorFirmController.dispose();
    _majorDateController.dispose();
    _majorTimeController.dispose();
    _majorWeightController.dispose();
    _majorPlacesController.dispose();
    _majorDescController.dispose();
    _majorInfoController.dispose();
    _majorFirmSearchController.dispose();

    _platyFirmController.dispose();
    _platyDateController.dispose();
    _platyTimeController.dispose();
    _platyWeightController.dispose();
    _platyPlacesController.dispose();
    _platyDescController.dispose();
    _platyInfoController.dispose();
    _platyFirmSearchController.dispose();

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

  Future<void> _addOperationLog(
    String module,
    String title,
    String details, {
    bool isError = false,
  }) async {
    final entry = OperationLogEntry(
      time: '${_todayFormatted()} ${_nowTimeFormatted()}',
      module: module,
      title: title,
      details: details,
      isError: isError,
    );
    setState(() {
      _operationLogs.insert(0, entry);
      if (_operationLogs.length > 50) {
        _operationLogs = _operationLogs.sublist(0, 50);
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'operation_logs',
      jsonEncode(_operationLogs.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _speak(String text, {bool force = false}) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!_isVoiceEnabled && !force) return;
    try {
      await _ttsChannel.invokeMethod('speak', {'text': text});
    } catch (_) {}
  }

  Future<void> _stopVoice() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await _ttsChannel.invokeMethod('stop');
    } catch (_) {}
  }

  Future<void> _saveSavedLogisticsPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'saved_posylka_path', _normalizePathInput(_posylkaPathController.text));
    await prefs.setString('saved_svodka_pp_path',
        _normalizePathInput(_svodkaPpPathController.text));
    await prefs.setString('saved_svodka_filial_path',
        _normalizePathInput(_svodkaFilialPathController.text));
  }

  void _syncFileFromPath(int type, String rawPath) {
    final cleaned = _normalizePathInput(rawPath);
    setState(() {
      if (type == 1) {
        _posylkaFile = cleaned.isNotEmpty ? File(cleaned) : null;
      } else if (type == 2) {
        _svodkaPpFile = cleaned.isNotEmpty ? File(cleaned) : null;
      } else if (type == 3) {
        _svodkaFilialFile = cleaned.isNotEmpty ? File(cleaned) : null;
      }
    });
    _saveSavedLogisticsPaths();
  }

  Future<void> _loadSettingsAndChats() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('groq_api_key') ?? '';
    final savedModel = prefs.getString('groq_model') ?? 'qwen/qwen3.8-27b';
    final savedVoice = prefs.getBool('is_voice_enabled') ?? false;
    final sidebarCollapsed = prefs.getBool('sidebar_collapsed') ?? false;

    final savedPosPath = prefs.getString('saved_posylka_path') ?? '';
    final savedPpPath = prefs.getString('saved_svodka_pp_path') ?? '';
    final savedFilPath = prefs.getString('saved_svodka_filial_path') ?? '';

    setState(() {
      _isVoiceEnabled = savedVoice;
      _isSidebarCollapsed = sidebarCollapsed;
      if (savedPosPath.isNotEmpty) {
        _posylkaPathController.text = savedPosPath;
        _posylkaFile = File(savedPosPath);
      }
      if (savedPpPath.isNotEmpty) {
        _svodkaPpPathController.text = savedPpPath;
        _svodkaPpFile = File(savedPpPath);
      }
      if (savedFilPath.isNotEmpty) {
        _svodkaFilialPathController.text = savedFilPath;
        _svodkaFilialFile = File(savedFilPath);
      }
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

    final logsJson = prefs.getString('operation_logs');
    if (logsJson != null) {
      try {
        final decodedLogs = jsonDecode(logsJson) as List;
        setState(() {
          _operationLogs = decodedLogs
              .map((e) =>
                  OperationLogEntry.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        });
      } catch (_) {}
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
      _createNewChat();
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

  void _createNewChat() {
    final newSession = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title:
          'Чат от ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      messages: <ChatMessage>[],
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
          if (type == 1) {
            _posylkaFile = File(path);
            _posylkaPathController.text = path;
          }
          if (type == 2) {
            _svodkaPpFile = File(path);
            _svodkaPpPathController.text = path;
          }
          if (type == 3) {
            _svodkaFilialFile = File(path);
            _svodkaFilialPathController.text = path;
          }
        });
        await _saveSavedLogisticsPaths();
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (Platform.isAndroid || Platform.isIOS)
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
              title: const Text('Выбрать изображение'),
              onTap: () {
                Navigator.pop(ctx);
                _pickChatImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.insert_drive_file, color: Colors.greenAccent),
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
  // МОДУЛИ 2 И 3: MAJOR EXPRESS (ЭЛЕКТРОКОННЕКТ И ПЛАТЫ) — ЛОГИКА СОХРАНЕНА
  // =========================================================================

  String _sanitizeFilename(String raw) {
    final cleaned = raw
        .replaceAll('"', '')
        .replaceAll('«', '')
        .replaceAll('»', '')
        .replaceAll(RegExp(r'[\\/:*?<>|]'), '_')
        .trim();
    return cleaned.isEmpty ? 'Major_Express_Order' : cleaned;
  }

  String _buildMajorExpressPythonScript({
    required String login,
    required String password,
    required String shipperName,
    required String consigneeName,
    required String pickupDate,
    required String pickupTime,
    required String weight,
    required String places,
    required String description,
    required String pickupInfo,
    required String appExeDir,
  }) {
    final escapedShipper = shipperName.replaceAll("'", "\\'");
    final escapedFirm = consigneeName.replaceAll("'", "\\'");
    final safeDate =
        pickupDate.trim().isEmpty ? _todayFormatted() : pickupDate.trim();
    final safeTimeFull =
        pickupTime.trim().isEmpty ? '14:00-18:00' : pickupTime.trim();
    final timePrefixMatch = RegExp(r'^\d{1,2}').firstMatch(safeTimeFull);
    final timeFilterCode = timePrefixMatch?.group(0) ?? '14';

    final safeWeight = weight.trim().isEmpty ? '1' : weight.trim();
    final safePlaces = places.trim().isEmpty ? '1' : places.trim();
    final escapedDesc =
        (description.trim().isEmpty ? 'платы' : description.trim())
            .replaceAll('"', '\\"');
    final escapedInfo = (pickupInfo.trim().isEmpty ? 'УПД' : pickupInfo.trim())
        .replaceAll('"', '\\"');
    final escapedAppDir = appExeDir.replaceAll('\\', '\\\\');

    return '''import os
import sys
import datetime
import time
import tempfile
import subprocess
from urllib.parse import urlparse, parse_qs, urlencode
from playwright.sync_api import sync_playwright

LOGIN = "$login"
PASSWORD = "$password"
APP_DIR = "$escapedAppDir"

def find_sumatra_pdf():
    candidates = [
        os.path.join(APP_DIR, "SumatraPDF.exe"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "SumatraPDF.exe"),
        r"C:\\SumatraPDF.exe",
        r"C:\\SumatraPDF\\SumatraPDF.exe",
        r"C:\\Program Files\\SumatraPDF\\SumatraPDF.exe",
        r"C:\\Program Files (x86)\\SumatraPDF\\SumatraPDF.exe",
        os.path.join(os.environ.get("LOCALAPPDATA", ""), "SumatraPDF", "SumatraPDF.exe"),
    ]
    for path in candidates:
        if path and os.path.exists(path):
            return path
    return None

def main():
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(
                headless=False,
                slow_mo=100,
                args=[
                    "--disable-blink-features=AutomationControlled",
                    "--disable-infobars",
                    "--no-sandbox"
                ]
            )
            context = browser.new_context(
                viewport={'width': 1280, 'height': 800},
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            )
            context.add_init_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
            page = context.new_page()

            print("1. Открываю страницу входа Major Express...")
            page.goto("https://lke.major-express.ru/login.aspx")
            page.wait_for_load_state("domcontentloaded")

            # Ввод логина
            login_input = page.locator("input[name='TextBox1']")
            login_input.click()
            login_input.fill(LOGIN)

            # Ввод пароля
            pass_input = page.locator("input[name='TextBox2']")
            pass_input.click()
            pass_input.fill(PASSWORD)
            page.wait_for_timeout(500)

            print("-> Нажимаю 'Вход'...")
            pass_input.press("Enter")
            try:
                page.locator("#Button1, input[name='Button1'], input[value='Вход']").first.click(timeout=3000)
            except Exception:
                pass

            print("\\n>>> Если появилась капча — реши её в браузере и нажми 'Вход'!")
            page.wait_for_selector("a:has-text('ЗАКАЗЫ')", timeout=180000)
            print("-> Вход выполнен. Перехожу к созданию заказа...")

            page.get_by_role("link", name="ЗАКАЗЫ").click()
            page.get_by_role("button", name="Вызвать курьера").click()
            page.wait_for_load_state("networkidle")

            print("2. Заполняю данные...")

            # =========================================================
            # 1. ОТПРАВИТЕЛЬ: $escapedShipper
            # =========================================================
            shipper_name = '$escapedShipper'
            print(f"-> Фиксирую отправителя: {shipper_name}...")
            shipper_inp = page.locator("#ctl00_MainPlaceHolder_o_cs_ddlListShippers_I")
            shipper_inp.click()
            shipper_inp.press("ControlOrMeta+A")
            shipper_inp.press("Backspace")
            shipper_inp.fill(shipper_name)
            page.wait_for_timeout(1500)
            page.keyboard.press("ArrowDown")
            page.keyboard.press("Enter")
            page.wait_for_timeout(1000)

            # =========================================================
            # 2. ПОЛУЧАТЕЛЬ: $escapedFirm
            # =========================================================
            consignee_name = '$escapedFirm'
            print(f"-> Вбиваю получателя: {consignee_name}...")
            
            consignee_inp = page.locator("#ctl00_MainPlaceHolder_o_cc_ddlConsignee_I")
            consignee_inp.click()
            consignee_inp.press("ControlOrMeta+A")
            consignee_inp.press("Backspace")
            consignee_inp.fill(consignee_name)
            page.wait_for_timeout(1500)
            page.keyboard.press("ArrowDown")
            page.keyboard.press("Enter")
            page.wait_for_timeout(1000)

            # --- 3. Дата забора ---
            date_inp = page.locator("#ctl00_MainPlaceHolder_o_deDateZabor_I")
            date_inp.click()
            date_inp.press("ControlOrMeta+A")
            date_inp.press("Backspace")
            date_inp.fill("$safeDate")
            page.keyboard.press("Enter")
            page.wait_for_timeout(500)

            # --- 4. Время забора ($safeTimeFull) ---
            print("-> Устанавливаю интервал $safeTimeFull...")
            time_inp = page.locator("#ctl00_MainPlaceHolder_o_ddlZakazTimeNum_I")
            time_inp.click()
            time_inp.press("ControlOrMeta+A")
            time_inp.press("Backspace")
            time_inp.fill("$timeFilterCode")
            page.wait_for_timeout(1500)
            try:
                page.locator("[id*='ctl00_MainPlaceHolder_o_ddlZakazTimeNum_DDD'] td").filter(has_text="$timeFilterCode").first.click(timeout=3000)
            except Exception:
                page.keyboard.press("ArrowDown")
                page.keyboard.press("Enter")
            page.wait_for_timeout(500)

            # --- 5. Параметры груза ---
            page.locator("#ctl00_MainPlaceHolder_o_tbWeight_I").fill("$safeWeight")
            page.locator("#ctl00_MainPlaceHolder_o_tbPlaceCount_I").fill("$safePlaces")
            
            # Описание груза
            desc_inp = page.locator("#ctl00_MainPlaceHolder_o_ddlDescription_I")
            desc_inp.click()
            desc_inp.press("ControlOrMeta+A")
            desc_inp.press("Backspace")
            desc_inp.fill("$escapedDesc")
            page.keyboard.press("Enter")

            # Информация для забора груза
            rem_inp = page.locator("#ctl00_MainPlaceHolder_o_tbRem")
            rem_inp.fill("$escapedInfo")

            print("-> Все поля заполнены. Создаю заказ...")
            page.wait_for_timeout(1000)

            # --- 6. Создание заказа ---
            page.once("dialog", lambda dialog: dialog.accept())
            page.get_by_role("button", name="Создать заказ").click()

            try:
                page.get_by_role("button", name="OK").click(timeout=6000)
            except Exception:
                pass

            print("-> Перехожу к созданию накладной...")
            page.locator("span").filter(has_text="Создать накладную").click()
            page.wait_for_load_state("networkidle")

            page.get_by_role("button", name="Сохранить накладную").click()
            page.wait_for_load_state("networkidle")

            # Ждем генерацию PDF на сервере Major Express
            print("-> Жду подготовку PDF на сервере...")
            page.wait_for_timeout(3000)

            # Перехватываем чистый PDF по сети во время открытия страницы печати
            pdf_bytes_holder = []
            def handle_response(response):
                try:
                    ct = response.headers.get("content-type", "").lower()
                    if "application/pdf" in ct or "invoicereportviewer.ashx" in response.url.lower():
                        body = response.body()
                        if body and body.startswith(b"%PDF"):
                            pdf_bytes_holder.append(body)
                except Exception:
                    pass

            page.on("response", handle_response)

            print("-> Открываю страницу печати накладной...")
            page.get_by_role("button", name="Печать", exact=True).click()
            page.wait_for_load_state("networkidle")
            page.wait_for_timeout(3000)

            # Если перехватчик не успел — вытаскиваем чистый параметр data= (без &returnUrl) и качаем PDF
            if not pdf_bytes_holder:
                try:
                    parsed = urlparse(page.url)
                    qs = parse_qs(parsed.query)
                    if "data" in qs and qs["data"]:
                        clean_query = urlencode({"data": qs["data"][0]})
                        direct_url = f"https://lke.major-express.ru/Handlers/InvoiceReportViewer.ashx?{clean_query}"
                        print("-> Скачиваю PDF напрямую по параметру data...")
                        resp = context.request.get(direct_url)
                        if resp.ok and resp.body().startswith(b"%PDF"):
                            pdf_bytes_holder.append(resp.body())
                except Exception as e_dl:
                    print(f"-> Ошибка загрузки PDF по data: {e_dl}")

            # --- 7. Железная прямая печать через SumatraPDF.exe ---
            if pdf_bytes_holder:
                tmp_pdf = os.path.join(tempfile.gettempdir(), f"major_invoice_{int(time.time())}.pdf")
                with open(tmp_pdf, "wb") as f_pdf:
                    f_pdf.write(pdf_bytes_holder[-1])
                print(f"-> Чистый PDF сохранен: {tmp_pdf}")

                sumatra_exe = find_sumatra_pdf()
                if sumatra_exe:
                    print(f"-> Печатаю через {sumatra_exe}...")
                    subprocess.run([sumatra_exe, "-print-to-default", "-silent", tmp_pdf], check=False)
                    print("-> ГОТОВО! Накладная мгновенно отправлена на принтер по умолчанию!")
                    page.wait_for_timeout(2000)
                    browser.close()
                    return
                else:
                    print("-> [ВНИМАНИЕ] SumatraPDF.exe не найден рядом с программой!")
                    print(f"-> Положи SumatraPDF.exe в папку: {APP_DIR}")
                    if os.name == "nt":
                        os.startfile(tmp_pdf)
            else:
                print("-> Не удалось скачать PDF автоматически, распечатай вручную из окна браузера.")

            input("Нажми ENTER в этой консоли, чтобы закрыть браузер...")
            browser.close()

    except Exception as e:
        print(f"\\n[ОШИБКА]: {e}")
        input("Нажми ENTER для выхода...")

if __name__ == "__main__":
    main()
''';
  }

  Future<void> _executeOrShareScript(
      String filePath, String safeFileName) async {
    if (Platform.isWindows) {
      try {
        await Process.start(
          'python',
          [filePath],
          mode: ProcessStartMode.detached,
        );
        _showSnackbar('Запускаю браузер Major Express ($safeFileName)...');
      } catch (e) {
        _showSnackbar(
            'Ошибка запуска Python: $e. Проверь, установлен ли Python.');
      }
    } else {
      await _shareScriptByPath(filePath);
    }
  }

  // Генерация для Панели 2: Электроконнект Мейджер Экспресс
  Future<void> _generateMajorExpressScript() async {
    final firmName = _majorFirmController.text.trim();
    if (firmName.isEmpty) {
      _showSnackbar('Впиши название фирмы-получателя!');
      return;
    }

    final pickupDate = _majorDateController.text.trim().isEmpty
        ? _todayFormatted()
        : _majorDateController.text.trim();
    final pickupTime = _majorTimeController.text.trim().isEmpty
        ? '14:00-18:00'
        : _majorTimeController.text.trim();
    final weight = _majorWeightController.text.trim().isEmpty
        ? '1'
        : _majorWeightController.text.trim();
    final places = _majorPlacesController.text.trim().isEmpty
        ? '1'
        : _majorPlacesController.text.trim();
    final desc = _majorDescController.text.trim().isEmpty
        ? 'платы'
        : _majorDescController.text.trim();
    final pickupInfo = _majorInfoController.text.trim().isEmpty
        ? 'УПД'
        : _majorInfoController.text.trim();

    try {
      final appExeDir = File(Platform.resolvedExecutable).parent.path;
      final scriptContent = _buildMajorExpressPythonScript(
        login: 'Electroconnect',
        password: 'Y2501212e4e5d62',
        shipperName: 'ООО «ЭЛЕКТРОконнект» Москва',
        consigneeName: firmName,
        pickupDate: pickupDate,
        pickupTime: pickupTime,
        weight: weight,
        places: places,
        description: desc,
        pickupInfo: pickupInfo,
        appExeDir: appExeDir,
      );

      final dir = await getApplicationDocumentsDirectory();
      final safeFileName = '${_sanitizeFilename(firmName)}.py';
      final filePath = '${dir.path}${Platform.pathSeparator}$safeFileName';

      final f = File(filePath);
      await f.writeAsString(scriptContent, encoding: utf8);

      if (Platform.isAndroid) {
        try {
          final downloadDir = Directory('/storage/emulated/0/Download');
          if (downloadDir.existsSync()) {
            final publicFile = File('${downloadDir.path}/$safeFileName');
            await publicFile.writeAsString(scriptContent, encoding: utf8);
          }
        } catch (_) {}
      }

      setState(() {
        _lastGeneratedMajorScriptPath = filePath;
        _lastMajorAction = '$firmName ($pickupDate)';
      });

      final details =
          '$firmName ($pickupDate, $pickupTime, $weight кг, $places мест, $desc, $pickupInfo)';
      _appendMessage('user', '🚚 Электроконнект Мейджер Экспресс: $details');
      _appendMessage('assistant', scriptContent);
      await _addOperationLog(
        'Электроконнект',
        'Вызов курьера Major Express',
        details,
      );
      await _speak('Скрипт Электроконнект для фирмы $firmName готов, Шурик!');

      await _executeOrShareScript(filePath, safeFileName);
    } catch (e) {
      await _addOperationLog(
        'Электроконнект',
        'Ошибка запуска',
        '$e',
        isError: true,
      );
      _showSnackbar('Ошибка создания скрипта: $e');
    }
  }

  // Генерация для Панели 3: Платы Мейджер Экспресс
  Future<void> _generatePlatyMajorExpressScript() async {
    final firmName = _platyFirmController.text.trim();
    if (firmName.isEmpty) {
      _showSnackbar('Впиши название фирмы-получателя!');
      return;
    }

    final pickupDate = _platyDateController.text.trim().isEmpty
        ? _todayFormatted()
        : _platyDateController.text.trim();
    final pickupTime = _platyTimeController.text.trim().isEmpty
        ? '14:00-18:00'
        : _platyTimeController.text.trim();
    final weight = _platyWeightController.text.trim().isEmpty
        ? '1'
        : _platyWeightController.text.trim();
    final places = _platyPlacesController.text.trim().isEmpty
        ? '1'
        : _platyPlacesController.text.trim();
    final desc = _platyDescController.text.trim().isEmpty
        ? 'платы'
        : _platyDescController.text.trim();
    final pickupInfo = _platyInfoController.text.trim().isEmpty
        ? 'с/ч'
        : _platyInfoController.text.trim();

    try {
      final appExeDir = File(Platform.resolvedExecutable).parent.path;
      final scriptContent = _buildMajorExpressPythonScript(
        login: 'Palat',
        password: 'Z250121e9a7a762',
        shipperName: 'ООО«Печатные платы»',
        consigneeName: firmName,
        pickupDate: pickupDate,
        pickupTime: pickupTime,
        weight: weight,
        places: places,
        description: desc,
        pickupInfo: pickupInfo,
        appExeDir: appExeDir,
      );

      final dir = await getApplicationDocumentsDirectory();
      final safeFileName = '${_sanitizeFilename(firmName)}.py';
      final filePath = '${dir.path}${Platform.pathSeparator}$safeFileName';

      final f = File(filePath);
      await f.writeAsString(scriptContent, encoding: utf8);

      if (Platform.isAndroid) {
        try {
          final downloadDir = Directory('/storage/emulated/0/Download');
          if (downloadDir.existsSync()) {
            final publicFile = File('${downloadDir.path}/$safeFileName');
            await publicFile.writeAsString(scriptContent, encoding: utf8);
          }
        } catch (_) {}
      }

      setState(() {
        _lastGeneratedPlatyScriptPath = filePath;
        _lastPlatyAction = '$firmName ($pickupDate)';
      });

      final details =
          '$firmName ($pickupDate, $pickupTime, $weight кг, $places мест, $desc, $pickupInfo)';
      _appendMessage('user', '📦 Платы Мейджер Экспресс: $details');
      _appendMessage('assistant', scriptContent);
      await _addOperationLog(
        'Печатные платы',
        'Вызов курьера Major Express',
        details,
      );
      await _speak('Скрипт Платы для фирмы $firmName готов, Шурик!');

      await _executeOrShareScript(filePath, safeFileName);
    } catch (e) {
      await _addOperationLog(
        'Печатные платы',
        'Ошибка запуска',
        '$e',
        isError: true,
      );
      _showSnackbar('Ошибка создания скрипта: $e');
    }
  }

  Future<void> _shareScriptByPath(String? path) async {
    if (path == null || !File(path).existsSync()) {
      _showSnackbar('Сначала сформируй скрипт!');
      return;
    }
    final fileName = path.split(Platform.pathSeparator).last;
    if (Platform.isWindows) {
      await _executeOrShareScript(path, fileName);
      return;
    }
    await Share.shareXFiles(
      [XFile(path, mimeType: 'text/x-python')],
      text: fileName,
    );
  }

  // =========================================================================
  // МОДУЛЬ 1: ПРЯМОЙ АВТОНОМНЫЙ АЛГОРИТМ СВЕДЕНИЯ НАКЛАДНЫХ (БЕЗ ЛИМИТОВ)
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
    final p1 = _normalizePathInput(_posylkaPathController.text);
    final p2 = _normalizePathInput(_svodkaPpPathController.text);
    final p3 = _normalizePathInput(_svodkaFilialPathController.text);

    if (p1.isNotEmpty) _posylkaFile = File(p1);
    if (p2.isNotEmpty) _svodkaPpFile = File(p2);
    if (p3.isNotEmpty) _svodkaFilialFile = File(p3);
    await _saveSavedLogisticsPaths();

    final posFile = _posylkaFile;
    if (posFile == null || !posFile.existsSync()) {
      _showSnackbar(
          'Файл Посылки не найден! Укажи верный путь или выбери файл.');
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
      final posRows = await _extractSheetMatrix(posFile,
          preferredSheetName: 'Посылка', maxCols: 14);
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
        final ppRows = await _extractSheetMatrix(_svodkaPpFile!,
            preferredSheetName: 'СВОДКА', maxCols: 16);
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
            if (firmVal.isNotEmpty &&
                !firmVal.toLowerCase().startsWith('заявка')) {
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
        final filRows = await _extractSheetMatrix(_svodkaFilialFile!,
            preferredSheetName: 'ФИЛИАЛ', maxCols: 16);
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
          if (extractedSchn.isNotEmpty &&
              extractedSchn.length >= 4 &&
              extractedSchn.length <= 6) {
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

      // Сортируем внутри каждого блока: ДМ -> СДЭК -> К -> Самовывоз
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

      final summaryMsg = '''
✅ Накладная сведена автоматически!
${_lastOtpravkaHeader.isNotEmpty ? '📅 Блок: $_lastOtpravkaHeader\n' : ''}• Голова (ООО «Печатные платы»): ${headItems.length} поз.
• Филиал (ЭЛЕКТРОконнект): ${filialItems.length} поз.

Нажми зелёную кнопку «Скачать Excel», чтобы открыть готовый оформленный файл.

```csv
$finalCsv
```''';

      _appendMessage('assistant', summaryMsg);
      await _addOperationLog(
        'Сведение накладных',
        'Успешно сведено ($fileName)',
        'Голова: ${headItems.length} поз., Филиал: ${filialItems.length} поз. ${_lastOtpravkaHeader.isNotEmpty ? "($_lastOtpravkaHeader)" : ""}',
      );
      await _speak(
          'Накладная успешно сведена, Шурик! Голова: ${headItems.length}, филиал: ${filialItems.length}.');
    } catch (e) {
      await _addOperationLog(
        'Сведение накладных',
        'Ошибка сведения',
        '$e',
        isError: true,
      );
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
      final xmlStr = utf8.decode(sharedStringsFile.content as List<int>,
          allowMalformed: true);
      final document = XmlDocument.parse(xmlStr);
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
              f.name.startsWith('xl/worksheets/sheet') &&
              f.name.endsWith('.xml'))
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
  // ВЫГРУЗКА В EXCEL: ТАХОМА 18 / 16 BOLD + ЖИРНЫЕ ГРАНИЦЫ THICK ПО ВСЕМУ ЛИСТУ
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
        textWrapping: wrapText ? ex.TextWrapping.WrapText : null,
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

      final colWidths = [
        56.0, // A: Фирма (Tahoma 18)
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

      // 1. Шапка таблицы
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
          hAlign:
              c == 0 ? ex.HorizontalAlign.Left : ex.HorizontalAlign.Center,
          wrapText: true,
        );
      }
      currentRow++;

      // 2. Пустой отступ + строка даты отправки + пустой отступ
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
          hAlign: ex.HorizontalAlign.Left,
        );
        currentRow++;

        _styleEmptyRowWithThickGrid(sheet, currentRow, rowHeight: 18);
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

          _styleEmptyRowWithThickGrid(sheet, currentRow, rowHeight: 18);
          currentRow++;

          sheet.setRowHeight(currentRow, 28);
          _styleEmptyRowWithThickGrid(sheet, currentRow, rowHeight: 28);
          final filCell = sheet.cell(ex.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: currentRow));
          filCell.value = ex.TextCellValue('филиал');
          filCell.cellStyle = _buildCellStyle(
            fontSize: 18,
            fontHex: '#FFFFFFFF',
            bgHex: '#FFFF0000',
            hAlign: ex.HorizontalAlign.Center,
          );
          currentRow++;

          _styleEmptyRowWithThickGrid(sheet, currentRow, rowHeight: 18);
          currentRow++;
          continue;
        }

        sheet.setRowHeight(currentRow, 28);

        for (int c = 0; c < 13; c++) {
          final val = c < cells.length ? cells[c].trim() : '';
          final cell = sheet.cell(ex.CellIndex.indexByColumnRow(
              columnIndex: c, rowIndex: currentRow));

          if (c >= 4 && c <= 6 && int.tryParse(val) != null) {
            cell.value = ex.IntCellValue(int.parse(val));
          } else {
            cell.value = ex.TextCellValue(val);
          }

          String? bgColor;
          String fontColor = '#FF000000';

          if (isSamovyvoz) {
            if (!isInsideFilialBlock) {
              bgColor = '#FFFF99CC';
            } else {
              bgColor = '#FFFFC000';
            }
          }

          if (c == 2 && val.isNotEmpty) {
            fontColor = '#FFFF0000';
          }

          if (c == 7 && val.toUpperCase() == 'ОТК') {
            fontColor = '#FF0000FF';
          }

          if (c == 6) {
            fontColor = '#FFFF0000';
          }

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

      // 4. Протягиваем жирную сетку и формат ячеек (18 для Фирмы, 16 для остальных) на 35 пустых строк вниз
      final totalRowsWithBuffer = currentRow + 35;
      for (int r = currentRow; r < totalRowsWithBuffer; r++) {
        _styleEmptyRowWithThickGrid(sheet, r, rowHeight: 24);
      }

      final dir = await getApplicationDocumentsDirectory();
      final filePath =
          '${dir.path}${Platform.pathSeparator}Посылка_Сведение_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final fileBytes = excel.save();

      if (fileBytes != null) {
        final f = File(filePath);
        await f.writeAsBytes(fileBytes);
        await _addOperationLog(
          'Экспорт Excel',
          'Сформирован файл .xlsx',
          filePath,
        );
        _showSnackbar('Excel сохранен: $filePath');
        await OpenFilex.open(filePath);
      }
    } catch (e) {
      await _addOperationLog(
        'Экспорт Excel',
        'Ошибка выгрузки',
        '$e',
        isError: true,
      );
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

  void _appendMessage(String role, String text,
      {String? imagePath, String? fileName}) {
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
      if (msgs.length == 1 && role == 'user') {
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // =========================================================================
  // НОВЫЙ ДИЗАЙН: КОМПОНЕНТЫ ИНТЕРФЕЙСА (SIDEBAR, TOPBAR, КАРТОЧКИ, МОДУЛИ)
  // =========================================================================

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
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 13, color: _subtleText),
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        filled: true,
        fillColor: widget.isDark
            ? const Color(0xFF182235)
            : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _borderCol),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _borderCol),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 840;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      drawer:
          isWide ? null : Drawer(child: _buildSidebarContent(isDrawer: true)),
      body: Row(
        children: [
          if (isWide) _buildSidebarContent(isDrawer: false),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(isWide: isWide),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _buildActiveWorkspace(),
                  ),
                ),
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
        color: const Color(0xFF14B8A6),
      ),
      (
        index: 1,
        title: 'Сведение накладных',
        subtitle: 'Посылка / Сводки',
        icon: Icons.table_chart_rounded,
        color: const Color(0xFF38BDF8),
      ),
      (
        index: 2,
        title: 'Электроконнект',
        subtitle: 'Major Express',
        icon: Icons.local_shipping_rounded,
        color: const Color(0xFFF59E0B),
      ),
      (
        index: 3,
        title: 'Печатные платы',
        subtitle: 'Major Express',
        icon: Icons.developer_board_rounded,
        color: const Color(0xFFA855F7),
      ),
      (
        index: 4,
        title: 'Журнал операций',
        subtitle: 'История и логи',
        icon: Icons.history_rounded,
        color: const Color(0xFF10B981),
      ),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: collapsed ? 74 : 255,
      decoration: BoxDecoration(
        color: _sidebarBg,
        border: Border(right: BorderSide(color: _borderCol)),
      ),
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
                        colors: [Color(0xFF14B8A6), Color(0xFF0284C7)],
                      ),
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
                          const Text(
                            'Печатные платы',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Logistics Suite v2.8',
                            style: TextStyle(fontSize: 11, color: _subtleText),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: _borderCol),
            const SizedBox(height: 10),
            if (!collapsed)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'РАБОЧИЕ РАЗДЕЛЫ',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: _subtleText,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                itemCount: navItems.length,
                itemBuilder: (context, idx) {
                  final item = navItems[idx];
                  final isSelected = _selectedNavIndex == item.index;
                  return Tooltip(
                    message: collapsed ? item.title : '',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() {
                          _selectedNavIndex = item.index;
                        });
                        if (isDrawer) Navigator.pop(context);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: EdgeInsets.symmetric(
                          horizontal: collapsed ? 0 : 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? item.color.withOpacity(0.16)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? item.color.withOpacity(0.45)
                                : Colors.transparent,
                          ),
                        ),
                        child: collapsed
                            ? Center(
                                child: Icon(
                                  item.icon,
                                  color: isSelected ? item.color : _subtleText,
                                  size: 22,
                                ),
                              )
                            : Row(
                                children: [
                                  Icon(
                                    item.icon,
                                    color:
                                        isSelected ? item.color : _subtleText,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: isSelected
                                                ? (widget.isDark
                                                    ? Colors.white
                                                    : Colors.black87)
                                                : null,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          item.subtitle,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: _subtleText,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: item.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: _borderCol),
            if (!collapsed && Platform.isWindows)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _sumatraFound
                        ? const Color(0xFF10B981).withOpacity(0.1)
                        : const Color(0xFFF59E0B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _sumatraFound
                          ? const Color(0xFF10B981).withOpacity(0.3)
                          : const Color(0xFFF59E0B).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _sumatraFound
                            ? Icons.print_rounded
                            : Icons.warning_amber_rounded,
                        size: 18,
                        color: _sumatraFound
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _sumatraFound
                              ? 'Автопечать SumatraPDF готова'
                              : 'SumatraPDF.exe не найден',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
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
                      tooltip: collapsed ? 'Развернуть меню' : 'Свернуть меню',
                      icon: Icon(
                        collapsed
                            ? Icons.keyboard_double_arrow_right
                            : Icons.keyboard_double_arrow_left,
                        size: 20,
                        color: _subtleText,
                      ),
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
    final titles = [
      'Обзор и ИИ-ассистент',
      'Сведение накладных (Посылка / Сводки)',
      'Электроконнект — Major Express',
      'Печатные платы — Major Express',
      'Журнал операций',
    ];

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _cardBg,
        border: Border(bottom: BorderSide(color: _borderCol)),
      ),
      child: Row(
        children: [
          if (!isWide)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                tooltip: 'Меню разделов',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titles[_selectedNavIndex],
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      Platform.isWindows ? 'ONLINE • Windows' : 'ONLINE',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isWide)
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) =>
                      setState(() => _searchQuery = val.trim().toLowerCase()),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Поиск по разделам и логам...',
                    hintStyle: TextStyle(fontSize: 12, color: _subtleText),
                    prefixIcon:
                        Icon(Icons.search, size: 17, color: _subtleText),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 15),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: widget.isDark
                        ? const Color(0xFF182235)
                        : const Color(0xFFF1F5F9),
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          if (!Platform.isWindows)
            IconButton(
              tooltip: _isVoiceEnabled ? 'Звук включен' : 'Звук выключен',
              icon: Icon(
                _isVoiceEnabled ? Icons.volume_up : Icons.volume_off,
                color: _isVoiceEnabled ? const Color(0xFF14B8A6) : _subtleText,
              ),
              onPressed: () async {
                final newVal = !_isVoiceEnabled;
                if (!newVal) await _stopVoice();
                setState(() => _isVoiceEnabled = newVal);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('is_voice_enabled', newVal);
                _showSnackbar(
                    newVal ? 'Автоозвучка включена' : 'Автоозвучка выключена');
              },
            ),
          IconButton(
            tooltip: widget.isDark ? 'Светлая тема' : 'Тёмная тема',
            icon: Icon(
              widget.isDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: 20,
            ),
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            tooltip: 'История чатов',
            icon: const Icon(Icons.chat_bubble_outline, size: 20),
            onPressed: () => _showChatsDrawer(context),
          ),
          IconButton(
            tooltip: 'Журнал операций (${_operationLogs.length})',
            icon: Badge(
              isLabelVisible: _operationLogs.isNotEmpty,
              label: Text('${_operationLogs.length}'),
              child: const Icon(Icons.notifications_none_rounded, size: 22),
            ),
            onPressed: () => setState(() => _selectedNavIndex = 4),
          ),
          IconButton(
            tooltip: 'Настройки API и системы',
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: () => _showSettingsDialog(context),
          ),
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

  // =========================================================================
  // ЭКРАН 0: ДАШБОРД С КАРТОЧКАМИ МОДУЛЕЙ + ЧАТ С ГЕНОЙ
  // =========================================================================

  Widget _buildDashboardAndChatView() {
    final rawMessages = _currentSession?.messages as List? ?? [];
    final isWin = Platform.isWindows;

    final cards = [
      (
        navIdx: 1,
        title: 'Сведение накладных',
        subtitle: 'Посылки и сводки (ПП + Филиал)',
        status: _lastCsvResult != null ? 'Готово' : 'Ожидает',
        statusColor: _lastCsvResult != null
            ? const Color(0xFF10B981)
            : const Color(0xFF38BDF8),
        metric: _lastLogisticsAction,
        icon: Icons.table_chart_rounded,
        accent: const Color(0xFF38BDF8),
      ),
      (
        navIdx: 2,
        title: 'Электроконнект',
        subtitle: 'Вызов курьера Major Express (УПД)',
        status: 'Онлайн',
        statusColor: const Color(0xFFF59E0B),
        metric: _lastMajorAction,
        icon: Icons.local_shipping_rounded,
        accent: const Color(0xFFF59E0B),
      ),
      (
        navIdx: 3,
        title: 'Печатные платы',
        subtitle: 'Вызов курьера Major Express (с/ч)',
        status: 'Активно',
        statusColor: const Color(0xFFA855F7),
        metric: _lastPlatyAction,
        icon: Icons.developer_board_rounded,
        accent: const Color(0xFFA855F7),
      ),
    ];

    final filteredCards = _searchQuery.isEmpty
        ? cards
        : cards
            .where((c) =>
                c.title.toLowerCase().contains(_searchQuery) ||
                c.subtitle.toLowerCase().contains(_searchQuery) ||
                c.metric.toLowerCase().contains(_searchQuery))
            .toList();

    return Column(
      key: const ValueKey('dashboard_view'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isRow = constraints.maxWidth >= 720;
              if (filteredCards.isEmpty) return const SizedBox.shrink();

              if (isRow) {
                return Row(
                  children: filteredCards
                      .map((c) => Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              child: _buildModuleCard(c),
                            ),
                          ))
                      .toList(),
                );
              } else {
                return SizedBox(
                  height: 138,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: filteredCards.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, idx) => SizedBox(
                      width: 265,
                      child: _buildModuleCard(filteredCards[idx]),
                    ),
                  ),
                );
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.smart_toy_outlined, size: 16, color: _subtleText),
              const SizedBox(width: 6),
              Text(
                'Рабочий чат с Геной (${_currentSession?.title ?? "Чат"})',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _subtleText),
              ),
              const Spacer(),
              TextButton.icon(
                style:
                    TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Новый чат', style: TextStyle(fontSize: 12)),
                onPressed: _createNewChat,
              ),
            ],
          ),
        ),
        Expanded(
          child: rawMessages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome,
                          size: 38,
                          color: const Color(0xFF14B8A6).withOpacity(0.5)),
                      const SizedBox(height: 10),
                      Text(
                        'Выбери карточку модуля сверху или напиши вопрос в чат',
                        style: TextStyle(fontSize: 14, color: _subtleText),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  itemCount: rawMessages.length,
                  itemBuilder: (context, idx) {
                    final m = rawMessages[idx] as ChatMessage;
                    if (_searchQuery.isNotEmpty &&
                        !m.text.toLowerCase().contains(_searchQuery)) {
                      return const SizedBox.shrink();
                    }
                    final isUser = m.role == 'user';
                    final isSystem = m.role == 'system';

                    return Align(
                      alignment:
                          isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.78,
                        ),
                        decoration: BoxDecoration(
                          color: isUser
                              ? const Color(0xFF0F766E)
                              : isSystem
                                  ? const Color(0xFF7F1D1D)
                                  : _cardBg,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isUser ? 16 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 16),
                          ),
                          border: Border.all(
                            color: isUser
                                ? const Color(0xFF14B8A6).withOpacity(0.4)
                                : isSystem
                                    ? Colors.redAccent.withOpacity(0.4)
                                    : _borderCol,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (m.imagePath != null &&
                                File(m.imagePath!).existsSync())
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(m.imagePath!),
                                    height: 180,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            if (m.fileName != null && m.fileName!.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8.0),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black26,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.insert_drive_file,
                                        size: 16, color: Colors.greenAccent),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        m.fileName!,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.greenAccent,
                                            fontWeight: FontWeight.w500),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            SelectableText(
                              m.text,
                              style: TextStyle(
                                fontSize: 15,
                                color: isUser || isSystem || widget.isDark
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                            if (!isUser && !isSystem && !isWin)
                              Align(
                                alignment: Alignment.bottomRight,
                                child: InkWell(
                                  onTap: () => _speak(m.text, force: true),
                                  child: const Padding(
                                    padding: EdgeInsets.only(top: 6.0),
                                    child: Icon(
                                      Icons.volume_up,
                                      size: 20,
                                      color: Color(0xFF14B8A6),
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
                      strokeWidth: 2, color: Color(0xFF14B8A6)),
                ),
                SizedBox(width: 8),
                Text('Обработка...', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        _buildChatInputArea(),
      ],
    );
  }

  Widget _buildModuleCard(dynamic card) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _selectedNavIndex = card.navIdx),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderCol),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(widget.isDark ? 0.22 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (card.accent as Color).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(card.icon, color: card.accent, size: 20),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (card.statusColor as Color).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    card.status,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: card.statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              card.title,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              card.subtitle,
              style: TextStyle(fontSize: 12, color: _subtleText),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    card.metric,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: card.accent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (card.accent as Color).withOpacity(0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Открыть',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: card.accent,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          size: 13, color: card.accent),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // ЭКРАН 1: ПОЛНОЭКРАННЫЙ МОДУЛЬ СВЕДЕНИЯ НАКЛАДНЫХ + ЛОКАЛЬНЫЕ/СЕТЕВЫЕ ПУТИ
  // =========================================================================

  Widget _buildLogisticsWorkspace() {
    return SingleChildScrollView(
      key: const ValueKey('logistics_workspace'),
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
                  border: Border.all(color: _borderCol),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.table_chart_rounded,
                              color: Color(0xFF38BDF8), size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Автоматическое сведение накладных',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Выбери файлы через проводник или вставь прямой путь (включая сетевые папки \\\\Server\\...)',
                                style:
                                    TextStyle(fontSize: 13, color: _subtleText),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildFilePathCard(
                      type: 1,
                      step: '1. Посылка (Обязательно)',
                      hint:
                          r'Например: C:\Посылка.xlsx или \\Server\Общая\Посылка.xlsx',
                      controller: _posylkaPathController,
                      accent: const Color(0xFF38BDF8),
                    ),
                    const SizedBox(height: 12),
                    _buildFilePathCard(
                      type: 2,
                      step: '2. Сводка ПП (Голова)',
                      hint:
                          r'Например: C:\Сводка_ПП.xlsx или \\Server\Общая\Сводка.xlsx',
                      controller: _svodkaPpPathController,
                      accent: const Color(0xFF14B8A6),
                    ),
                    const SizedBox(height: 12),
                    _buildFilePathCard(
                      type: 3,
                      step: '3. Сводка Филиал (ЭЛЕКТРОконнект)',
                      hint:
                          r'Например: C:\Филиал.xlsx или \\Server\Общая\Филиал.xlsx',
                      controller: _svodkaFilialPathController,
                      accent: const Color(0xFFA855F7),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.play_arrow_rounded,
                                    size: 22),
                            label: Text(
                              _isLoading
                                  ? 'ИДЁТ СВЕДЕНИЕ...'
                                  : 'СВЕСТИ НАКЛАДНУЮ',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold),
                            ),
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
                                  horizontal: 20, vertical: 15),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.download_rounded, size: 22),
                            label: const Text(
                              'СКАЧАТЬ EXCEL (.XLSX)',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            onPressed: _exportToFormattedExcel,
                          ),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
              if (_lastCsvResult != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFF10B981).withOpacity(0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: Color(0xFF10B981), size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Результат сведения${_lastOtpravkaHeader.isNotEmpty ? " ($_lastOtpravkaHeader)" : ""}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          Chip(
                            label: Text('Голова: $_lastHeadCount'),
                            backgroundColor:
                                const Color(0xFF38BDF8).withOpacity(0.15),
                          ),
                          const SizedBox(width: 6),
                          Chip(
                            label: Text('Филиал: $_lastFilialCount'),
                            backgroundColor:
                                const Color(0xFFA855F7).withOpacity(0.15),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: widget.isDark
                              ? const Color(0xFF0A0F1A)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _borderCol),
                        ),
                        child: SelectableText(
                          _lastCsvResult!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilePathCard({
    required int type,
    required String step,
    required String hint,
    required TextEditingController controller,
    required Color accent,
  }) {
    final cleaned = _normalizePathInput(controller.text);
    final hasText = cleaned.isNotEmpty;
    final fileExists = hasText && File(cleaned).existsSync();

    final statusColor = !hasText
        ? accent
        : (fileExists ? const Color(0xFF10B981) : Colors.amberAccent);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF162032)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fileExists
              ? const Color(0xFF10B981).withOpacity(0.6)
              : _borderCol,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                fileExists
                    ? Icons.check_circle_rounded
                    : (hasText
                        ? Icons.warning_amber_rounded
                        : Icons.folder_open_rounded),
                size: 18,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Text(
                step,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
              const Spacer(),
              if (hasText)
                Text(
                  fileExists ? 'Файл найден' : 'Путь не найден',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: (val) => _syncFileFromPath(type, val),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    hintStyle: TextStyle(fontSize: 12, color: _subtleText),
                    prefixIcon: const Icon(Icons.lan_outlined, size: 17),
                    suffixIcon: hasText
                        ? IconButton(
                            tooltip: 'Очистить путь',
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              controller.clear();
                              _syncFileFromPath(type, '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: widget.isDark
                        ? const Color(0xFF0D1320)
                        : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _borderCol),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _borderCol),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent.withOpacity(0.18),
                  foregroundColor: accent,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: accent.withOpacity(0.4)),
                  ),
                ),
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text(
                  'Обзор',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _pickFile(type),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // ЭКРАНЫ 2 И 3: MAJOR EXPRESS + ПРАВЫЙ СПРАВОЧНИК КОМПАНИЙ (.TXT)
  // =========================================================================

  Widget _buildMajorCourierWorkspace({required bool isPlaty}) {
    final isWin = Platform.isWindows;
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
    final lastScriptPath = isPlaty
        ? _lastGeneratedPlatyScriptPath
        : _lastGeneratedMajorScriptPath;

    final formCard = Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPlaty
                      ? Icons.developer_board_rounded
                      : Icons.local_shipping_rounded,
                  color: accent,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPlaty
                          ? 'ООО «Печатные платы» — Major Express'
                          : 'ООО «ЭЛЕКТРОконнект» — Major Express',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      isPlaty
                          ? 'Отправитель: ООО«Печатные платы» • Логин: Palat • Автопечать A4'
                          : 'Отправитель: ООО «ЭЛЕКТРОконнект» Москва • Логин: Electroconnect • Автопечать A4',
                      style: TextStyle(fontSize: 12.5, color: _subtleText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _styledInputField(
                  controller: firmCtrl,
                  label: 'Фирма-получатель (выбери справа или впиши)',
                  icon: Icons.business_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Добавить эту компанию в справочник (.txt)',
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981).withOpacity(0.18),
                    foregroundColor: const Color(0xFF10B981),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                          color: const Color(0xFF10B981).withOpacity(0.45)),
                    ),
                  ),
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('+ В базу',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _addFirmToDictionary(
                    isPlaty: isPlaty,
                    rawName: firmCtrl.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _styledInputField(
                  controller: dateCtrl,
                  label: 'Дата забора',
                  icon: Icons.calendar_today_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _styledInputField(
                  controller: timeCtrl,
                  label: 'Интервал времени забора',
                  icon: Icons.access_time_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                label: const Text('Сегодня', style: TextStyle(fontSize: 12)),
                onPressed: () =>
                    setState(() => dateCtrl.text = _todayFormatted()),
              ),
              ActionChip(
                label:
                    const Text('10:00-14:00', style: TextStyle(fontSize: 12)),
                onPressed: () => setState(() => timeCtrl.text = '10:00-14:00'),
              ),
              ActionChip(
                label:
                    const Text('14:00-18:00', style: TextStyle(fontSize: 12)),
                onPressed: () => setState(() => timeCtrl.text = '14:00-18:00'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _styledInputField(
                  controller: weightCtrl,
                  label: 'Вес, кг',
                  icon: Icons.scale_rounded,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _styledInputField(
                  controller: placesCtrl,
                  label: 'Кол-во мест',
                  icon: Icons.inventory_2_outlined,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _styledInputField(
                  controller: descCtrl,
                  label: 'Описание вложения',
                  icon: Icons.description_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _styledInputField(
            controller: infoCtrl,
            label: 'Информация для забора груза (примечание)',
            icon: Icons.info_outline_rounded,
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    isWin ? Icons.rocket_launch_rounded : Icons.code_rounded,
                    size: 20,
                  ),
                  label: Text(
                    isWin
                        ? 'ОФОРМИТЬ И РАСПЕЧАТАТЬ НАКЛАДНУЮ'
                        : 'СФОРМИРОВАТЬ СКРИПТ (.PY)',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  onPressed: isPlaty
                      ? _generatePlatyMajorExpressScript
                      : _generateMajorExpressScript,
                ),
              ),
              if (lastScriptPath != null) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                    side: const BorderSide(color: Color(0xFF10B981)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(isWin ? Icons.replay : Icons.share),
                  label: Text(isWin ? 'Повторить' : 'Скачать .py'),
                  onPressed: () => _shareScriptByPath(lastScriptPath),
                ),
              ]
            ],
          ),
        ],
      ),
    );

    final directoryCard = _buildFirmsDirectoryPanel(
      isPlaty: isPlaty,
      accent: accent,
      onSelectFirm: (selectedName) {
        setState(() {
          firmCtrl.text = selectedName;
        });
        _showSnackbar('Выбрано: $selectedName');
      },
    );

    return LayoutBuilder(
      key: ValueKey(isPlaty ? 'platy_workspace' : 'electro_workspace'),
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;
        if (isWide) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: SingleChildScrollView(child: formCard),
                ),
                const SizedBox(width: 18),
                Expanded(
                  flex: 4,
                  child: directoryCard,
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              formCard,
              const SizedBox(height: 16),
              SizedBox(height: 420, child: directoryCard),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFirmsDirectoryPanel({
    required bool isPlaty,
    required Color accent,
    required ValueChanged<String> onSelectFirm,
  }) {
    final searchCtrl =
        isPlaty ? _platyFirmSearchController : _majorFirmSearchController;
    final filter = isPlaty ? _platyFirmFilter : _majorFirmFilter;
    final fullList = isPlaty ? _platyFirms : _electroFirms;

    final filtered = filter.isEmpty
        ? fullList
        : fullList
            .where((f) => f.toLowerCase().contains(filter.toLowerCase()))
            .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.contacts_rounded, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Справочник получателей (${fullList.length})',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Tooltip(
                message: 'Открыть файл списка в Блокноте (.txt)',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_note_rounded, size: 20),
                  onPressed: () => _openFirmsTxtInNotepad(isPlaty: isPlaty),
                ),
              ),
              Tooltip(
                message: 'Обновить список из файла (.txt)',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  onPressed: () async {
                    await _loadFirmsFromDisk(isPlaty: isPlaty);
                    _showSnackbar('Список обновлён из блокнота!');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: searchCtrl,
            onChanged: (val) {
              setState(() {
                if (isPlaty) {
                  _platyFirmFilter = val.trim();
                } else {
                  _majorFirmFilter = val.trim();
                }
              });
            },
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Поиск компании (введи часть названия)...',
              hintStyle: TextStyle(fontSize: 12, color: _subtleText),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: filter.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        searchCtrl.clear();
                        setState(() {
                          if (isPlaty) {
                            _platyFirmFilter = '';
                          } else {
                            _majorFirmFilter = '';
                          }
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: widget.isDark
                  ? const Color(0xFF182235)
                  : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _borderCol),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _borderCol),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isPlaty && fullList.isEmpty
                              ? 'Список для Плат пока пуст.\nДобавь компанию кнопкой «+ В базу» или в файл platy_firms.txt'
                              : 'Ничего не найдено по запросу «$filter»',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: _subtleText),
                        ),
                        if (filter.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.add, size: 16),
                            label: Text('Добавить «$filter» в базу'),
                            onPressed: () {
                              _addFirmToDictionary(
                                  isPlaty: isPlaty, rawName: filter);
                              onSelectFirm(filter);
                            },
                          ),
                        ]
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: _borderCol.withOpacity(0.6)),
                    itemBuilder: (context, idx) {
                      final name = filtered[idx];
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onSelectFirm(name),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.apartment_rounded,
                                  size: 16, color: accent.withOpacity(0.85)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              InkWell(
                                onTap: () => _removeFirmFromDictionary(
                                  isPlaty: isPlaty,
                                  firmName: name,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(Icons.close,
                                      size: 14,
                                      color: _subtleText.withOpacity(0.6)),
                                ),
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
  }

  // =========================================================================
  // ЭКРАН 4: ЖУРНАЛ ОПЕРАЦИЙ И УВЕДОМЛЕНИЙ
  // =========================================================================

  Widget _buildLogsWorkspace() {
    final filteredLogs = _searchQuery.isEmpty
        ? _operationLogs
        : _operationLogs
            .where((l) =>
                l.title.toLowerCase().contains(_searchQuery) ||
                l.details.toLowerCase().contains(_searchQuery) ||
                l.module.toLowerCase().contains(_searchQuery))
            .toList();

    return Padding(
      key: const ValueKey('logs_workspace'),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderCol),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.history_rounded,
                        color: Color(0xFF10B981), size: 24),
                    const SizedBox(width: 10),
                    const Text(
                      'Журнал выполненных операций и ошибок',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (_operationLogs.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Colors.redAccent),
                        label: const Text('Очистить',
                            style: TextStyle(color: Colors.redAccent)),
                        onPressed: () async {
                          setState(() => _operationLogs.clear());
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('operation_logs');
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: _borderCol),
                Expanded(
                  child: filteredLogs.isEmpty
                      ? Center(
                          child: Text(
                            'История операций пока пуста',
                            style: TextStyle(fontSize: 14, color: _subtleText),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filteredLogs.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: _borderCol),
                          itemBuilder: (context, idx) {
                            final item = filteredLogs[idx];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              leading: CircleAvatar(
                                backgroundColor: item.isError
                                    ? Colors.redAccent.withOpacity(0.15)
                                    : const Color(0xFF10B981)
                                        .withOpacity(0.15),
                                child: Icon(
                                  item.isError
                                      ? Icons.error_outline
                                      : Icons.check_rounded,
                                  color: item.isError
                                      ? Colors.redAccent
                                      : const Color(0xFF10B981),
                                  size: 20,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF14B8A6)
                                          .withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.module,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF14B8A6),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    item.time,
                                    style: TextStyle(
                                        fontSize: 11.5, color: _subtleText),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: SelectableText(
                                  item.details,
                                  style: TextStyle(
                                      fontSize: 12.5, color: _subtleText),
                                ),
                              ),
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

  // =========================================================================
  // НИЖНЯЯ ПАНЕЛЬ ВВОДА СООБЩЕНИЙ И ДИАЛОГИ
  // =========================================================================

  Widget _buildChatInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: _cardBg,
        border: Border(top: BorderSide(color: _borderCol)),
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
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 16),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insert_drive_file,
                        color: Colors.greenAccent, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _chatAttachedFile!.path
                            .split(Platform.pathSeparator)
                            .last,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _chatAttachedFile = null),
                      child: const Icon(Icons.close, size: 16),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Прикрепить файл или фото',
                  icon: Icon(Icons.attach_file_rounded, color: _subtleText),
                  onPressed: _showAttachmentMenu,
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.isDark
                          ? const Color(0xFF182235)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _borderCol),
                    ),
                    child: TextField(
                      focusNode: _inputFocusNode,
                      controller: _chatInputController,
                      maxLines: 4,
                      minLines: 1,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Напиши сообщение или прикрепи документ...',
                        hintStyle: TextStyle(color: _subtleText, fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendChatMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF14B8A6),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    tooltip: 'Отправить',
                    icon: const Icon(Icons.arrow_upward_rounded,
                        color: Colors.white, size: 20),
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

  void _showChatsDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
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
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14B8A6),
                        foregroundColor: Colors.white,
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
                const Divider(),
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
                              ? const Color(0xFF14B8A6).withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          title: Text(
                            session.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color:
                                  isSelected ? const Color(0xFF14B8A6) : null,
                            ),
                          ),
                          onTap: () {
                            setState(() => _currentSession = session);
                            Navigator.pop(ctx);
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _renameChat(session);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    size: 18, color: Colors.redAccent),
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

  void _showSettingsDialog(BuildContext context) {
    String tempModel = _selectedModel;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Настройки API и системы'),
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
                  'Модель ИИ для чата:',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 5),
                DropdownButtonFormField<String>(
                  value: tempModel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  ),
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
                if (Platform.isWindows) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        _sumatraFound ? Icons.check_circle : Icons.error,
                        size: 16,
                        color: _sumatraFound
                            ? Colors.greenAccent
                            : Colors.amberAccent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _sumatraFound
                              ? 'SumatraPDF.exe обнаружен (автопечать активна)'
                              : 'SumatraPDF.exe не найден в папке программы',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ]
              ],
            ),
            actions: [
              TextButton(
                child: const Text('Отмена'),
                onPressed: () => Navigator.pop(ctx),
              ),
              OutlinedButton(
                child: _isKeyValidating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
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
                  backgroundColor: const Color(0xFF14B8A6),
                  foregroundColor: Colors.white,
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
