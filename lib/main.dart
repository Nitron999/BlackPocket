import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BlackPocketApp());
}

class BlackPocketApp extends StatelessWidget {
  const BlackPocketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlackPocket',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
          surface: const Color(0xFF141414),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final String? imagePath;

  ChatMessage({required this.text, required this.isUser, this.imagePath});

  Map<String, dynamic> toJson() => {
        'text': text,
        'isUser': isUser,
        'imagePath': imagePath,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        text: json['text'] ?? '',
        isUser: json['isUser'] ?? false,
        imagePath: json['imagePath'],
      );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final ImagePicker _picker = ImagePicker();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _isLoading = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _autoSpeak = true;
  File? _selectedImage;

  String _apiUrl = "https://openrouter.ai/api/v1/chat/completions";
  String _apiKey = "";
  String _modelName = "openrouter/free";
  String _systemPrompt = "Ты — умный голосовой ассистент BlackPocket. Отвечай точно, грамотно, по делу и на русском языке.";

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadAll();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("ru-RU");
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.9);
    _tts.setCompletionHandler(() {
      setState(() => _isSpeaking = false);
    });
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiUrl = prefs.getString('apiUrl') ?? _apiUrl;
      _apiKey = prefs.getString('apiKey') ?? _apiKey;
      _modelName = prefs.getString('modelName') ?? _modelName;
      _systemPrompt = prefs.getString('systemPrompt') ?? _systemPrompt;
      _autoSpeak = prefs.getBool('autoSpeak') ?? true;

      final historyJson = prefs.getString('chat_history');
      if (historyJson != null && historyJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(historyJson);
        _messages.clear();
        _messages.addAll(decoded.map((e) => ChatMessage.fromJson(e)).toList());
      }
    });
    _scrollToBottom();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_messages.map((e) => e.toJson()).toList());
    await prefs.setString('chat_history', encoded);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('apiUrl', _apiUrl);
    await prefs.setString('apiKey', _apiKey);
    await prefs.setString('modelName', _modelName);
    await prefs.setString('systemPrompt', _systemPrompt);
    await prefs.setBool('autoSpeak', _autoSpeak);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _speakText(String text) async {
    if (_isSpeaking) {
      await _tts.stop();
      setState(() => _isSpeaking = false);
      return;
    }
    // Очищаем markdown-разметку перед воспроизведением речи
    final cleanText = text.replaceAll(RegExp(r'[\*\_#`>]'), '');
    setState(() => _isSpeaking = true);
    await _tts.speak(cleanText);
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await _picker.pickImage(source: source, imageQuality: 70, maxWidth: 1024);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  void _toggleListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          localeId: "ru_RU",
          onResult: (val) => setState(() {
            _controller.text = val.recognizedWords;
          }),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Текст скопирован в буфер обмена'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _clearChatHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить диалог?'),
        content: const Text('Вся история сообщений будет удалена с устройства.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              setState(() => _messages.clear());
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('chat_history');
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _selectedImage == null) || _isLoading) return;

    final currentImage = _selectedImage;
    final imagePath = currentImage?.path;
    _controller.clear();

    setState(() {
      _messages.add(ChatMessage(
        text: text.isEmpty ? "Что на этой картинке?" : text,
        isUser: true,
        imagePath: imagePath,
      ));
      _selectedImage = null;
      _isLoading = true;
    });
    _saveHistory();
    _scrollToBottom();

    try {
      List<dynamic> contentPayload = [];
      if (text.isNotEmpty) {
        contentPayload.add({"type": "text", "text": text});
      } else {
        contentPayload.add({"type": "text", "text": "Опиши подробно, что изображено на фото."});
      }

      if (currentImage != null) {
        final bytes = await currentImage.readAsBytes();
        final base64Image = base64Encode(bytes);
        contentPayload.add({
          "type": "image_url",
          "image_url": {"url": "data:image/jpeg;base64,$base64Image"}
        });
      }

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
          'HTTP-Referer': 'https://github.com/black-pocket',
          'X-Title': 'BlackPocket',
        },
        body: jsonEncode({
          "model": _modelName,
          "messages": [
            {"role": "system", "content": _systemPrompt},
            {
              "role": "user",
              "content": contentPayload.length == 1 && contentPayload[0]['type'] == 'text'
                  ? contentPayload[0]['text']
                  : contentPayload
            }
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final reply = data['choices'][0]['message']['content'] ?? 'Пустой ответ';
        setState(() {
          _messages.add(ChatMessage(text: reply, isUser: false));
        });
        _saveHistory();

        if (_autoSpeak) {
          _speakText(reply);
        }
      } else {
        setState(() {
          _messages.add(ChatMessage(text: "Ошибка API (${response.statusCode}): ${response.body}", isUser: false));
        });
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(text: "Ошибка соединения: $e", isUser: false));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _openSettingsDialog() {
    final urlController = TextEditingController(text: _apiUrl);
    final keyController = TextEditingController(text: _apiKey);
    final modelController = TextEditingController(text: _modelName);
    final systemController = TextEditingController(text: _systemPrompt);
    bool tempAutoSpeak = _autoSpeak;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Настройки BlackPocket'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: urlController, decoration: const InputDecoration(labelText: 'API Endpoint URL')),
                TextField(controller: keyController, decoration: const InputDecoration(labelText: 'API Key'), obscureText: true),
                TextField(controller: modelController, decoration: const InputDecoration(labelText: 'Model Name')),
                TextField(controller: systemController, decoration: const InputDecoration(labelText: 'System Prompt'), maxLines: 3),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Автоозвучка ответов'),
                  value: tempAutoSpeak,
                  onChanged: (val) => setDialogState(() => tempAutoSpeak = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                setState(() {
                  _apiUrl = urlController.text.trim();
                  _apiKey = keyController.text.trim();
                  _modelName = modelController.text.trim();
                  _systemPrompt = systemController.text.trim();
                  _autoSpeak = tempAutoSpeak;
                });
                _saveSettings();
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BlackPocket', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Очистить историю',
            onPressed: _messages.isEmpty ? null : _clearChatHistory,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Настройки',
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.record_voice_over_outlined, size: 52, color: Colors.deepPurple.shade300),
                        const SizedBox(height: 14),
                        const Text('Готов к диалогу. Задай вопрос или пришли фото.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return Align(
                        alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 7),
                          padding: const EdgeInsets.all(14),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
                          decoration: BoxDecoration(
                            color: msg.isUser ? Colors.deepPurple.shade700 : const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(16),
                            border: msg.isUser ? null : Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (msg.imagePath != null && File(msg.imagePath!).existsSync())
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(File(msg.imagePath!), height: 180, width: double.infinity, fit: BoxFit.cover),
                                  ),
                                ),
                              msg.isUser
                                  ? Text(
                                      msg.text,
                                      style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.35),
                                    )
                                  : MarkdownBody(
                                      data: msg.text,
                                      styleSheet: MarkdownStyleSheet(
                                        p: const TextStyle(fontSize: 17, height: 1.45, color: Color(0xFFEDEDED)),
                                        h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                        h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                        code: const TextStyle(fontSize: 15, backgroundColor: Colors.black26),
                                      ),
                                    ),
                              if (!msg.isUser) ...[
                                const SizedBox(height: 8),
                                const Divider(height: 1, color: Colors.white10),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.copy_outlined, size: 20, color: Colors.grey),
                                      tooltip: 'Скопировать',
                                      onPressed: () => _copyToClipboard(msg.text),
                                    ),
                                    IconButton(
                                      icon: Icon(_isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                                          size: 20, color: _isSpeaking ? Colors.redAccent : Colors.grey),
                                      tooltip: 'Озвучить',
                                      onPressed: () => _speakText(msg.text),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(6.0), child: LinearProgressIndicator(minHeight: 2)),
          if (_selectedImage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black38,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(_selectedImage!, width: 48, height: 48, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  const Text('Фото выбрано', style: TextStyle(fontSize: 14, color: Colors.white70)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() => _selectedImage = null)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: const Color(0xFF0F0F0F),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined),
                  onPressed: () => _pickImage(ImageSource.camera),
                  tooltip: 'Камера',
                ),
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  onPressed: () => _pickImage(ImageSource.gallery),
                  tooltip: 'Галерея',
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: _isListening ? 'Слушаю речь...' : 'Спроси что-нибудь...',
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(_isListening ? Icons.mic : Icons.mic_none, color: _isListening ? Colors.redAccent : null),
                  onPressed: _toggleListening,
                  tooltip: 'Голос',
                ),
                IconButton.filled(
                  onPressed: _isLoading ? null : _sendMessage,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
