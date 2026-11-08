import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
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
          surface: const Color(0xFF121212),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final File? imageFile;
  ChatMessage({required this.text, required this.isUser, this.imageFile});
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

  bool _isLoading = false;
  bool _isListening = false;
  File? _selectedImage;

  // Настройки по умолчанию
  String _apiUrl = "https://openrouter.ai/api/v1/chat/completions";
  String _apiKey = "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";
  String _modelName = "meta-llama/llama-3.2-11b-vision-instruct:free";
  String _systemPrompt = "Ты — умный ассистент BlackPocket. Ты умеешь анализировать изображения и отвечать четко, по делу и без лишней воды.";

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    await _speech.initialize();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiUrl = prefs.getString('apiUrl') ?? _apiUrl;
      _apiKey = prefs.getString('apiKey') ?? _apiKey;
      _modelName = prefs.getString('modelName') ?? _modelName;
      _systemPrompt = prefs.getString('systemPrompt') ?? _systemPrompt;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('apiUrl', _apiUrl);
    await prefs.setString('apiKey', _apiKey);
    await prefs.setString('modelName', _modelName);
    await prefs.setString('systemPrompt', _systemPrompt);
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

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _selectedImage == null) || _isLoading) return;

    final imageToSend = _selectedImage;
    _controller.clear();
    setState(() {
      _messages.add(ChatMessage(text: text.isEmpty ? "Что на этой картинке?" : text, isUser: true, imageFile: imageToSend));
      _selectedImage = null;
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      // Собираем запрос с поддержкой Vision (OpenAI / OpenRouter multimodal)
      List<dynamic> contentPayload = [];
      if (text.isNotEmpty) {
        contentPayload.add({"type": "text", "text": text});
      } else if (imageToSend != null) {
        contentPayload.add({"type": "text", "text": "Опиши подробно, что изображено на этом фото."});
      }

      if (imageToSend != null) {
        final bytes = await imageToSend.readAsBytes();
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Настройки BlackPocket'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: urlController, decoration: const InputDecoration(labelText: 'API Endpoint URL')),
              TextField(controller: keyController, decoration: const InputDecoration(labelText: 'API Key'), obscureText: true),
              TextField(controller: modelController, decoration: const InputDecoration(labelText: 'Model Name (Vision)')),
              TextField(controller: systemController, decoration: const InputDecoration(labelText: 'System Prompt'), maxLines: 3),
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
              });
              _saveSettings();
              Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BlackPocket', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: _openSettingsDialog),
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
                        Icon(Icons.remove_red_eye_outlined, size: 48, color: Colors.deepPurple.shade300),
                        const SizedBox(height: 12),
                        const Text('BlackPocket готов: текст, фото и голос.', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return Align(
                        alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                          decoration: BoxDecoration(
                            color: msg.isUser ? Colors.deepPurple.shade700 : const Color(0xFF121212),
                            borderRadius: BorderRadius.circular(16),
                            border: msg.isUser ? null : Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (msg.imageFile != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(msg.imageFile!, height: 180, width: double.infinity, fit: BoxFit.cover),
                                  ),
                                ),
                              msg.isUser
                                  ? Text(msg.text, style: const TextStyle(color: Colors.white))
                                  : MarkdownBody(data: msg.text),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(8.0), child: LinearProgressIndicator(minHeight: 2)),
          if (_selectedImage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black26,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(_selectedImage!, width: 45, height: 45, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  const Text('Фото прикреплено', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => setState(() => _selectedImage = null)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(10),
            color: const Color(0xFF0F0F0F),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined),
                  onPressed: () => _pickImage(ImageSource.camera),
                  tooltip: 'Сделать фото',
                ),
                IconButton(
                  icon: const Icon(Icons.image_outlined),
                  onPressed: () => _pickImage(ImageSource.gallery),
                  tooltip: 'Выбрать из галереи',
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: _isListening ? 'Слушаю...' : 'Сообщение...',
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
                  tooltip: 'Голосовой ввод',
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
