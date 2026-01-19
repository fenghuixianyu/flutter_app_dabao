import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/pdf_service.dart';
import 'dart:io';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  String? _filePath;
  List<BookmarkItem> _bookmarks = [];
  bool _isLoading = false;
  BookmarkItem? _selectedItem;

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
        final list = await PdfService.getBookmarks(path);
        setState(() {
          _bookmarks = list;
          _isLoading = false;
        });
      } catch (e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("加载失败: $e")));
      }
    }
  }

  Future<void> _save() async {
    if (_filePath == null) return;
    setState(() => _isLoading = true);
    
    try {
      // Overwrite original for now (or could ask)
      await PdfService.saveBookmarks(filePath: _filePath!, bookmarks: _bookmarks);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("保存成功!")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("保存失败: $e")));
    }
    
    setState(() => _isLoading = false);
  }

  // --- Actions ---

  void _addRoot() {
    setState(() {
      _bookmarks.add(BookmarkItem(title: "新书签", pageNumber: 1));
    });
  }

  void _addChild() {
    if (_selectedItem == null) return;
    setState(() {
      _selectedItem!.children.add(BookmarkItem(title: "子书签", pageNumber: _selectedItem!.pageNumber));
      // Expand?
    });
  }

  void _delete() {
    if (_selectedItem == null) return;
    setState(() {
      _removeItem(_bookmarks, _selectedItem!);
      _selectedItem = null;
    });
  }
  
  bool _removeItem(List<BookmarkItem> list, BookmarkItem target) {
    if (list.remove(target)) return true;
    for (var item in list) {
      if (_removeItem(item.children, target)) return true;
    }
    return false;
  }

  void _applyOffset(int offset) {
    setState(() {
      _offsetRecursive(_bookmarks, offset);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("已对所有页码偏移 $offset")));
  }

  void _offsetRecursive(List<BookmarkItem> list, int offset) {
    for (var item in list) {
      item.pageNumber += offset;
      if (item.pageNumber < 1) item.pageNumber = 1;
      _offsetRecursive(item.children, offset);
    }
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("书签编辑器"),
        actions: [
          if (_filePath != null)
             IconButton(icon: const Icon(Icons.save), onPressed: _isLoading ? null : _save),
        ],
      ),
      body: Column(
        children: [
          if (_filePath == null)
            Expanded(
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text("打开 PDF 文件"),
                ),
              ),
            )
          else ...[
            // Toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: Row(
                children: [
                   IconButton(icon: const Icon(Icons.add), tooltip: "添加根书签", onPressed: _addRoot),
                   IconButton(icon: const Icon(Icons.add_circle_outline), tooltip: "添加子书签", onPressed: _selectedItem == null ? null : _addChild),
                   IconButton(icon: const Icon(Icons.delete), tooltip: "删除选中", onPressed: _selectedItem == null ? null : _delete),
                   const VerticalDivider(width: 20),
                   TextButton.icon(
                     onPressed: () => _showOffsetDialog(),
                     icon: const Icon(Icons.exposure),
                     label: const Text("批量偏移"),
                   ),
                ],
              ),
            ),
            
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _bookmarks.isEmpty 
                    ? const Center(child: Text("暂无书签"))
                    : ListView(
                        children: _buildList(_bookmarks, 0),
                      ),
            ),
          ]
        ],
      ),
    );
  }

  List<Widget> _buildList(List<BookmarkItem> items, int depth) {
    List<Widget> widgets = [];
    for (var item in items) {
      widgets.add(_buildTile(item, depth));
      if (item.children.isNotEmpty) {
        // Simple expansion logic: always expanded or toggled? 
        // For simple editor, keeping expanded is easier, or use ExpansionTile.
        // Let's use indentation for custom tree look.
        widgets.addAll(_buildList(item.children, depth + 1));
      }
    }
    return widgets;
  }

  Widget _buildTile(BookmarkItem item, int depth) {
    final isSelected = item == _selectedItem;
    return InkWell(
      onTap: () => setState(() => _selectedItem = item),
      child: Container(
        color: isSelected ? Colors.blueAccent.withOpacity(0.2) : null,
        padding: EdgeInsets.only(left: 16.0 * depth, right: 8, top: 4, bottom: 4),
        child: Row(
          children: [
            Icon(item.children.isEmpty ? Icons.bookmark_border : Icons.bookmark, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                   Expanded(
                     child: TextFormField(
                       initialValue: item.title,
                       decoration: const InputDecoration.collapsed(hintText: "标题"),
                       onChanged: (v) => item.title = v,
                     ),
                   ),
                   const SizedBox(width: 8),
                   SizedBox(
                     width: 50,
                     child: TextFormField(
                       initialValue: item.pageNumber.toString(),
                       keyboardType: TextInputType.number,
                       decoration: const InputDecoration.collapsed(hintText: "页码"),
                       onChanged: (v) => item.pageNumber = int.tryParse(v) ?? item.pageNumber,
                     ),
                   ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOffsetDialog() async {
    final ctrl = TextEditingController(text: "0");
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("批量偏移页码"),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "偏移量 (例如 +1 或 -1)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          TextButton(onPressed: () {
            final val = int.tryParse(ctrl.text) ?? 0;
            if (val != 0) _applyOffset(val);
            Navigator.pop(ctx);
          }, child: const Text("应用")),
        ],
      ),
    );
  }
}
