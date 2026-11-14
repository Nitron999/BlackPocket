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
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
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
        title: 'Анализ Gerber и ТЗ',
        subtitle: 'DFM • ЭЛЕКТРОконнект',
        icon: Icons.precision_manufacturing_rounded,
        color: const Color(0xFFEC4899),
      ),
      (
        index: 5,
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
                            'Logistics & CAM v3.0',
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
      'Анализ Gerber и DFM-контроль (ЭЛЕКТРОконнект)',
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
            onPressed: () => setState(() => _selectedNavIndex = 5),
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
        return _buildGerberAnalysisWorkspace();
      case 5:
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
        subtitle: 'Major Express (УПД)',
        status: 'Онлайн',
        statusColor: const Color(0xFFF59E0B),
        metric: _lastMajorAction,
        icon: Icons.local_shipping_rounded,
        accent: const Color(0xFFF59E0B),
      ),
      (
        navIdx: 3,
        title: 'Печатные платы',
        subtitle: 'Major Express (с/ч)',
        status: 'Активно',
        statusColor: const Color(0xFFA855F7),
        metric: _lastPlatyAction,
        icon: Icons.developer_board_rounded,
        accent: const Color(0xFFA855F7),
      ),
      (
        navIdx: 4,
        title: 'Анализ Gerber и ТЗ',
        subtitle: 'DFM • Нормы ЭЛЕКТРОконнект',
        status: _gerberAnalysis != null ? 'Проверено' : 'DFM',
        statusColor: const Color(0xFFEC4899),
        metric: _lastGerberAction,
        icon: Icons.precision_manufacturing_rounded,
        accent: const Color(0xFFEC4899),
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
              final isRow = constraints.maxWidth >= 920;
              if (filteredCards.isEmpty) return const SizedBox.shrink();

              if (isRow) {
                return Row(
                  children: filteredCards
                      .map((c) => Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 5),
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
                      width: 245,
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
                  const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              card.subtitle,
              style: TextStyle(fontSize: 11.5, color: _subtleText),
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
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: card.accent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: card.accent,
                        ),
                      ),
                      const SizedBox(width: 3),
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
                          'Ничего не найдено по запросу «$filter»',
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
  // ЭКРАН 4: АНАЛИЗ GERBER, DFM-КОНТРОЛЬ ЭЛЕКТРОКОННЕКТ И СПЕЦИФИКАЦИЯ КП
  // =========================================================================

  Widget _buildGerberAnalysisWorkspace() {
    const accent = Color(0xFFEC4899);
    final w = double.tryParse(_gerberWidthController.text.replaceAll(',', '.'));
    final h =
        double.tryParse(_gerberHeightController.text.replaceAll(',', '.'));
    final qty = int.tryParse(_gerberQtyController.text.trim()) ?? 10;

    final singleAreaDm2 = (w != null && h != null) ? (w * h) / 10000.0 : null;
    final totalAreaDm2 =
        singleAreaDm2 != null ? singleAreaDm2 * math.max(qty, 1) : null;

    final dfmChecks = _evaluateElectroconnectDfm();
    final specLine = _buildSpecificationLine();

    return SingleChildScrollView(
      key: const ValueKey('gerber_workspace'),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Верхний блок загрузки архива
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _borderCol),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.precision_manufacturing_rounded,
                          color: accent, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Анализ Gerber / Excellon и технологический контроль',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _gerberAnalysis != null
                                ? 'Загружен архив: ${_gerberAnalysis!.archiveName} (${_gerberAnalysis!.layers.length} файлов)'
                                : 'Загрузи .zip архив проекта (PCAD .TOP/.BOT/.DRL или Gerber .GTL/.GBL/.GKO) для авто-проверки норм ЭЛЕКТРОконнект',
                            style: TextStyle(fontSize: 13, color: _subtleText),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.folder_zip_rounded, size: 20),
                      label: const Text(
                        'ЗАГРУЗИТЬ .ZIP ПРОЕКТА',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _pickAndAnalyzeGerberZip,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Основная сетка: слева параметры и спецификация КП, справа DFM и слои
              LayoutBuilder(
                builder: (context, constraints) {
                  final isTwoCol = constraints.maxWidth >= 900;

                  final leftColumn = Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _borderCol),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Параметры платы и спецификация КП',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _styledInputField(
                                controller: _gerberOrderNameController,
                                label: 'Обозначение платы / децимальный номер',
                                icon: Icons.tag_rounded,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDropdownField(
                                label: 'Тип заказа',
                                value: _gerberOrderType,
                                items: const ['Новый', 'Повтор'],
                                onChanged: (v) =>
                                    setState(() => _gerberOrderType = v!),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _styledInputField(
                                controller: _gerberWidthController,
                                label: 'Длина X, мм',
                                icon: Icons.straighten_rounded,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _styledInputField(
                                controller: _gerberHeightController,
                                label: 'Ширина Y, мм',
                                icon: Icons.straighten_rounded,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _styledInputField(
                                controller: _gerberQtyController,
                                label: 'Тираж, шт.',
                                icon: Icons.layers_rounded,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        if (singleAreaDm2 != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF14B8A6).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color:
                                      const Color(0xFF14B8A6).withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Площадь 1 платы: ${singleAreaDm2.toStringAsFixed(3)} дм²',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  'Партия ($qty шт.): ${totalAreaDm2!.toStringAsFixed(2)} дм²',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF14B8A6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDropdownField(
                                label: 'Слои',
                                value: '$_gerberLayersCount',
                                items: const [
                                  '1',
                                  '2',
                                  '4',
                                  '6',
                                  '8',
                                  '10',
                                  '12',
                                  '16'
                                ],
                                onChanged: (v) => setState(
                                    () => _gerberLayersCount = int.parse(v!)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDropdownField(
                                label: 'Материал',
                                value: _gerberMaterial,
                                items: const ['FR4', 'Алюминий', 'Rogers'],
                                onChanged: (v) =>
                                    setState(() => _gerberMaterial = v!),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDropdownField(
                                label: 'Толщина, мм',
                                value: _gerberThickness,
                                items: const [
                                  '0.5',
                                  '0.8',
                                  '1.0',
                                  '1.5',
                                  '2.0',
                                  '2.5',
                                  '3.0'
                                ],
                                onChanged: (v) =>
                                    setState(() => _gerberThickness = v!),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDropdownField(
                                label: 'Фольга, мкм',
                                value: _gerberFoil,
                                items: const [
                                  '12',
                                  '18',
                                  '35',
                                  '50',
                                  '70',
                                  '105'
                                ],
                                onChanged: (v) =>
                                    setState(() => _gerberFoil = v!),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDropdownField(
                                label: 'Маска (стороны)',
                                value: _gerberMaskSide,
                                items: const [
                                  'С двух сторон',
                                  'С одной стороны',
                                  'Без маски'
                                ],
                                onChanged: (v) =>
                                    setState(() => _gerberMaskSide = v!),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDropdownField(
                                label: 'Цвет маски',
                                value: _gerberMaskColor,
                                items: const [
                                  'Зеленая',
                                  'Синяя',
                                  'Черная',
                                  'Белая',
                                  'Красная'
                                ],
                                onChanged: (v) =>
                                    setState(() => _gerberMaskColor = v!),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDropdownField(
                                label: 'Покрытие',
                                value: _gerberFinish,
                                items: const [
                                  'HAL',
                                  'Иммерсионное золото',
                                  'Иммерсионное олово',
                                  'Без покрытия'
                                ],
                                onChanged: (v) =>
                                    setState(() => _gerberFinish = v!),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDropdownField(
                                label: 'Маркировка',
                                value: _gerberSilkSide,
                                items: const [
                                  'С двух сторон',
                                  'С одной стороны',
                                  'Без маркировки'
                                ],
                                onChanged: (v) =>
                                    setState(() => _gerberSilkSide = v!),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDropdownField(
                                label: 'Цвет маркировки',
                                value: _gerberSilkColor,
                                items: const ['Белая', 'Черная'],
                                onChanged: (v) =>
                                    setState(() => _gerberSilkColor = v!),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildDropdownField(
                                label: 'Контур',
                                value: _gerberContour,
                                items: const ['фрезеровка', 'скрайбирование'],
                                onChanged: (v) =>
                                    setState(() => _gerberContour = v!),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _styledInputField(
                                controller: _gerberMinTrackController,
                                label: 'Мин. дорожка, мм',
                                icon: Icons.timeline_rounded,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _styledInputField(
                                controller: _gerberMinHoleController,
                                label: 'Мин. сверло, мм',
                                icon: Icons.radio_button_unchecked,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Эл. тест',
                                    style: TextStyle(fontSize: 13)),
                                value: _gerberElectroTest,
                                onChanged: (v) => setState(
                                    () => _gerberElectroTest = v ?? true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Готовая строка спецификации (для 1С / КП / Счёта):',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
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
                            specLine,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D9488),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                label: const Text(
                                  'КОПИРОВАТЬ СТРОКУ ДЛЯ КП',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold),
                                ),
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: specLine));
                                  _showSnackbar(
                                      'Строка спецификации скопирована в буфер!');
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: accent,
                                side: const BorderSide(color: accent),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.open_in_new_rounded,
                                  size: 18),
                              label: const Text(
                                'Калькулятор сайта',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              onPressed: _openPselectroCalculator,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );

                  final rightColumn = Column(
                    children: [
                      // Карточка проверки DFM норм ЭЛЕКТРОконнект
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: _cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _borderCol),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.verified_outlined,
                                    color: Color(0xFF10B981), size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Контроль норм «ЭЛЕКТРОконнект»',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_gerberAnalysis?.hasBinaryBrdOnly == true)
                              Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color:
                                          Colors.amberAccent.withOpacity(0.4)),
                                ),
                                child: const Text(
                                  'В архиве обнаружен бинарный .BRD (PCAD) без отдельного текстового контура .GKO — впиши длину X и ширину Y вручную слева.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ...dfmChecks.map((chk) {
                              final col = chk.level == 'error'
                                  ? Colors.redAccent
                                  : chk.level == 'warn'
                                      ? Colors.amberAccent
                                      : const Color(0xFF10B981);
                              final ic = chk.level == 'error'
                                  ? Icons.cancel_rounded
                                  : chk.level == 'warn'
                                      ? Icons.warning_amber_rounded
                                      : Icons.check_circle_rounded;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: col.withOpacity(0.09),
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: col.withOpacity(0.35)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(ic, color: col, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            chk.title,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: col,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            chk.detail,
                                            style: TextStyle(
                                                fontSize: 11.5,
                                                color: _subtleText),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      if (_gerberAnalysis != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: _cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _borderCol),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Состав архива и сверловка (${_gerberAnalysis!.totalHoles} отв.)',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 10),
                              ..._gerberAnalysis!.layers.map((l) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 3),
                                    child: Row(
                                      children: [
                                        Icon(Icons.insert_drive_file_outlined,
                                            size: 15, color: accent),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            l.fileName,
                                            style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          l.role,
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color: _subtleText),
                                        ),
                                      ],
                                    ),
                                  )),
                              if (_gerberAnalysis!
                                  .drillToolsBreakdown.isNotEmpty) ...[
                                Divider(height: 18, color: _borderCol),
                                const Text(
                                  'Инструменты сверловки (.DRL):',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: (_gerberAnalysis!
                                          .drillToolsBreakdown.entries
                                          .toList()
                                        ..sort((a, b) => a.key.compareTo(b.key)))
                                      .map((e) => Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(
                                              'Ø ${e.key} мм — ${e.value} шт.',
                                              style:
                                                  const TextStyle(fontSize: 11),
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ]
                            ],
                          ),
                        ),
                      ],
                    ],
                  );

                  if (isTwoCol) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: leftColumn),
                        const SizedBox(width: 18),
                        Expanded(flex: 5, child: rightColumn),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      leftColumn,
                      const SizedBox(height: 16),
                      rightColumn,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = items.contains(value) ? value : items.first;
    return DropdownButtonFormField<String>(
      value: safeValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: _subtleText),
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
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      items: items
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  // =========================================================================
  // ЭКРАН 5: ЖУРНАЛ ОПЕРАЦИЙ И УВЕДОМЛЕНИЙ
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
