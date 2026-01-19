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
  
  List<BookmarkNode> _flatNodes = [];
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
  }
  
  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _textCtrl.dispose();
    _focusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.index == 1) _refreshPreview();
  }
  
  void _refreshPreview() {
     if (_textCtrl.text.isNotEmpty) {
       setState(() {
         _flatNodes = TextParser.textToBookmarks(_textCtrl.text);
       });
     }
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null) _loadFile(result.files.single.path!);
  }

  Future<void> _loadFile(String path) async {
    setState(() => _isLoading = true);
    _filePath = path; 
    try {
      final bookmarks = await PdfHandler.readBookmarks(path);
      final text = TextParser.bookmarksToText(bookmarks);
      setState(() {
        _textCtrl.text = text;
        _isLoading = false;
        _flatNodes = bookmarks;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("读取失败: $e");
    }
  }

  Future<void> _save() async {
    if (_filePath == null) return;
    setState(() => _isLoading = true);
    try {
      final nodes = TextParser.textToBookmarks(_textCtrl.text);
      String savePath = await PdfHandler.writeBookmarks(_filePath!, nodes);
      _showSuccess(savePath);
    } catch (e) {
      _showError("保存失败: $e");
    }
    setState(() => _isLoading = false);
  }
  
  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  
  void _showSuccess(String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("保存成功"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             const Text("文件已保存至："),
             const SizedBox(height: 8),
             Container(padding: const EdgeInsets.all(8), color: Colors.grey[200], child: Text(path, style: const TextStyle(fontSize: 12))),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("好"))],
      ),
    );
  }

  // --- Toolbar Logic ---
  
  void _insertTab() {
     final text = _textCtrl.text;
    final selection = _textCtrl.selection;
    if (selection.start < 0) return;
    final newText = text.replaceRange(selection.start, selection.end, AppConfig.indentChar);
    _textCtrl.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: selection.start + 1));
  }

  void _removeTab() {
    final text = _textCtrl.text;
    final selection = _textCtrl.selection;
    if (selection.start <= 0) return;
    if (text.substring(selection.start - 1, selection.start) == AppConfig.indentChar) {
       final newText = text.replaceRange(selection.start - 1, selection.start, '');
       _textCtrl.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: selection.start - 1));
    }
  }
  
  void _clearAll() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("清空确认"),
      content: const Text("确定要清空编辑器内容吗？"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
        TextButton(onPressed: () { _textCtrl.clear(); Navigator.pop(ctx); }, child: const Text("清空", style: TextStyle(color: Colors.red))),
      ]
    ));
  }

  // --- Advanced Tools ---

  void _applyToSelection(int Function(String title, int page) modifier) {
    final text = _textCtrl.text;
    if (text.isEmpty) return;
    
    final selection = _textCtrl.selection;
    int start = 0;
    int end = text.length;

    bool hasSelection = selection.start != -1 && selection.end != -1 && selection.start != selection.end;
    if (hasSelection) {
       start = selection.start;
       end = selection.end;
    }
    
    String before = text.substring(0, start);
    int lineStart = before.lastIndexOf('\n') + 1;
    int lineEnd = text.indexOf('\n', end);
    if (lineEnd == -1) lineEnd = text.length;
    
    String rangeText = text.substring(lineStart, lineEnd);
    List<String> lines = rangeText.split('\n');
    List<String> newLines = [];
    
    for (var line in lines) {
      final match = RegExp(r'^(.*)\s+(\d+)$').firstMatch(line);
      if (match != null) {
        String pre = match.group(1)!;
        int oldPage = int.parse(match.group(2)!);
        int newPage = modifier(pre, oldPage);
        if (newPage < 1) newPage = 1;
        newLines.add("$pre\t$newPage");
      } else {
        newLines.add(line);
      }
    }
    
    String replacement = newLines.join('\n');
    String newText = text.replaceRange(lineStart, lineEnd, replacement);
    
    _textCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lineStart + replacement.length),
    );
    
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(hasSelection ? "已对选中行应用" : "已对全文应用")));
  }
  
  void _showOffsetDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("整体偏移"),
        content: TextField(controller: ctrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "偏移量 (+/- N)")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(onPressed: () {
            int val = int.tryParse(ctrl.text) ?? 0;
            if (val != 0) _applyToSelection((t, p) => p + val);
            Navigator.pop(ctx);
          }, child: const Text("执行")),
        ],
      )
    );
  }

  // --- UI Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_filePath == null ? AppConfig.appName : File(_filePath!).uri.pathSegments.last.replaceAll('.pdf', '')),
        actions: [
          if (_filePath != null) ...[
             IconButton(icon: const Icon(Icons.file_open), tooltip: "切换文件", onPressed: _pickFile),
             IconButton(icon: const Icon(Icons.save), onPressed: _isLoading ? null : _save),
          ]
        ],
        bottom: _filePath != null ? TabBar(
          controller: _tabController,
          tabs: const [Tab(text: "编辑"), Tab(text: "预览")],
        ) : null,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _filePath == null 
            ? Center(child: ElevatedButton(onPressed: _pickFile, child: const Text("打开 PDF 文件")))
            : TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(), 
                children: [
                  Column(
                    children: [
                      // Toolbar directly inserted
                      KeyboardAccessory(
                         onTab: _insertTab,
                         onUntab: _removeTab,
                         onOffset: _showOffsetDialog,
                         onClear: _clearAll,
                         onPreview: () { _focusNode.unfocus(); _tabController.animateTo(1); },
                         onHideKeyboard: () => _focusNode.unfocus(),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _textCtrl,
                          focusNode: _focusNode,
                          maxLines: null,
                          expands: true,
                          keyboardType: TextInputType.multiline,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 16, height: 1.5),
                          decoration: const InputDecoration(contentPadding: EdgeInsets.all(16), border: InputBorder.none),
                        ),
                      ),
                    ],
                  ),
                  _buildFoldablePreview(),
                ],
              ),
    );
  }
  
  Widget _buildFoldablePreview() {
     if (_flatNodes.isEmpty) return const Center(child: Text("无书签"));
     List<BookmarkNode> roots = _buildTree(_flatNodes);
     return ListView(children: roots.map((n) => _buildNode(n)).toList());
  }
  
  Widget _buildNode(BookmarkNode node) {
     if (node.children.isEmpty) {
       return ListTile(
         dense: true,
         title: Text(node.title),
         trailing: Text(node.pageNumber.toString()),
         contentPadding: EdgeInsets.only(left: 16.0 + (node.level * 16), right: 16),
       );
     } else {
       return ExpansionTile(
         title: Text(node.title),
         trailing: Text(node.pageNumber.toString()),
         tilePadding: EdgeInsets.only(left: 16.0 + (node.level * 16), right: 16),
         children: node.children.map((c) => _buildNode(c)).toList(),
       );
     }
  }
  
  List<BookmarkNode> _buildTree(List<BookmarkNode> flat) {
     return _reconstruct(flat);
  }
  
  List<BookmarkNode> _reconstruct(List<BookmarkNode> flat) {
     List<BookmarkNode> roots = [];
     List<BookmarkNode> stack = []; 
     
     for (var node in flat) {
        node.children.clear(); 
        
        if (node.level == 0) {
           roots.add(node);
           stack = [node]; 
        } else {
           if (node.level > stack.length) {
              if (stack.isNotEmpty) stack.last.children.add(node);
           } else {
              while (stack.length > node.level) {
                 stack.removeLast();
              }
              if (stack.isNotEmpty) stack.last.children.add(node);
           }
           stack.add(node); 
        }
     }
     return roots;
  }
}
