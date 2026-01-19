import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../config/app_config.dart';
import '../utils/text_parser.dart';
import '../utils/pdf_handler.dart';
import '../widgets/keyboard_accessory.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with SingleTickerProviderStateMixin {
  String? _filePath;
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  bool _isLoading = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      final path = result.files.single.path!;
      setState(() {
        _filePath = path;
        _isLoading = true;
      });
      
      try {
        final bookmarks = await PdfHandler.readBookmarks(path);
        final text = TextParser.bookmarksToText(bookmarks);
        setState(() {
          _textCtrl.text = text;
          _isLoading = false;
        });
      } catch (e) {
        setState(() => _isLoading = false);
        _showError("读取失败: $e");
      }
    }
  }

  Future<void> _save() async {
    if (_filePath == null) return;
    setState(() => _isLoading = true);
    
    try {
      final nodes = TextParser.textToBookmarks(_textCtrl.text);
      await PdfHandler.writeBookmarks(_filePath!, nodes);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("保存成功!")));
    } catch (e) {
      _showError("保存失败: $e");
    }
    
    setState(() => _isLoading = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // --- Logic for Accessory Bar ---

  void _insertTab() {
    final text = _textCtrl.text;
    final selection = _textCtrl.selection;
    if (selection.start < 0) return;

    final newText = text.replaceRange(selection.start, selection.end, AppConfig.indentChar);
    _textCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: selection.start + 1),
    );
  }

  void _removeTab() {
    // 简单实现：删除光标前的一个字符如果是 Tab
    final text = _textCtrl.text;
    final selection = _textCtrl.selection;
    if (selection.start <= 0) return;
    
    if (text.substring(selection.start - 1, selection.start) == AppConfig.indentChar) {
       final newText = text.replaceRange(selection.start - 1, selection.start, '');
       _textCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start - 1),
      );
    }
  }

  void _adjustPage(int delta) {
    // 调整当前行页码，或者选区内的所有行的页码
    final text = _textCtrl.text;
    final selection = _textCtrl.selection;
    
    // 获取受影响的行
    // 简化逻辑: 只处理光标所在行，或者选区覆盖的完整行
    // 这里做最简单的: 仅处理整个文本 (批量) 还是 当前行?
    // PdgLite 要求 "当前行 +1/-1"
    
    // 找到光标所在行的范围
    int start = selection.start;
    if (start < 0) start = 0;
    
    // Find line start/end
    String before = text.substring(0, start);
    int lineStart = before.lastIndexOf('\n') + 1;
    int lineEnd = text.indexOf('\n', start);
    if (lineEnd == -1) lineEnd = text.length;
    
    String line = text.substring(lineStart, lineEnd);
    
    // Parse Page
    final match = RegExp(r'^(.*)\s+(\d+)$').firstMatch(line);
    if (match != null) {
      String pre = match.group(1)!;
      int page = int.parse(match.group(2)!);
      page += delta;
      if (page < 1) page = 1;
      
      String newLine = "$pre\t$page";
      final newText = text.replaceRange(lineStart, lineEnd, newLine);
       _textCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: lineStart + newLine.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_filePath == null ? AppConfig.appName : File(_filePath!).uri.pathSegments.last),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: "编辑"), Tab(text: "预览")],
        ),
        actions: [
          if (_filePath != null)
             IconButton(icon: const Icon(Icons.save), onPressed: _isLoading ? null : _save)
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _filePath == null 
            ? Center(child: ElevatedButton(onPressed: _pickFile, child: const Text("打开 PDF")))
            : TabBarView(
                controller: _tabController,
                children: [
                  // Text Mode
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        // Accessory Bar (Visible even if keyboard is hidden for easy access?)
                        // Or only visible when focusing? Let's make it always visible for convenience
                        child: KeyboardAccessory(
                          onTab: _insertTab,
                          onUntab: _removeTab,
                          onPageInc: () => _adjustPage(1),
                          onPageDec: () => _adjustPage(-1),
                          onPreview: () {
                             _focusNode.unfocus();
                             _tabController.animateTo(1);
                          },
                          onHideKeyboard: () => _focusNode.unfocus(),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _textCtrl,
                          focusNode: _focusNode,
                          maxLines: null,
                          expands: true,
                          keyboardType: TextInputType.multiline,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 16, height: 1.5),
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.all(16),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Preview Mode (Tree)
                  _buildPreview(),
                ],
              ),
    );
  }

  Widget _buildPreview() {
    // Parse on the fly
    final nodes = TextParser.textToBookmarks(_textCtrl.text);
    if (nodes.isEmpty) return const Center(child: Text("无书签"));
    
    return ListView.builder(
      itemCount: nodes.length,
      itemBuilder: (context, index) {
        final node = nodes[index];
        return Padding(
          padding: EdgeInsets.only(left: 16.0 * node.level, top: 4, bottom: 4, right: 16),
          child: Row(
            children: [
              // Icon(Icons.bookmark, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(child: Text(node.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(node.pageNumber.toString(), style: const TextStyle(color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }
}
