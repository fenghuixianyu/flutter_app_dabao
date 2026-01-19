import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/pdf_service.dart';

class AutoBookmarkPage extends StatefulWidget {
  const AutoBookmarkPage({super.key});

  @override
  State<AutoBookmarkPage> createState() => _AutoBookmarkPageState();
}

class _AutoBookmarkPageState extends State<AutoBookmarkPage> {
  List<String> _selectedFiles = [];
  bool _isRunning = false;
  String _logs = "";
  
  // Presets
  String _selectedPreset = 'chapter_cn'; // chapter_cn, number_dot, custom
  
  final TextEditingController _regexCtrl = TextEditingController();
  final TextEditingController _sizeCtrl = TextEditingController(text: "0");

  @override
  void initState() {
    super.initState();
    _applyPreset();
  }

  void _applyPreset() {
    setState(() {
      switch (_selectedPreset) {
        case 'chapter_cn':
          _regexCtrl.text = r"^\s*第[一二三四五六七八九十百0-9]+[章回节]\s*\S+";
          break;
        case 'number_dot':
          _regexCtrl.text = r"^\s*[0-9]+(\.[0-9]+)*\s+\S+";
          break;
        case 'custom':
          // Keep existing
          break;
      }
    });
  }

  Future<void> _pickFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      setState(() {
        _selectedFiles = result.paths.whereType<String>().toList();
        _logs = "已选择 ${_selectedFiles.length} 个文件";
      });
    }
  }

  Future<void> _runTask() async {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请先选择 PDF 文件")));
      return;
    }
    
    setState(() {
      _isRunning = true;
      _logs = "任务开始...\n(后台处理中，请稍候)";
    });

    String outputDir = File(_selectedFiles.first).parent.path;
    
    final config = {
      "level1": {
        "regex": _regexCtrl.text,
        "font_size": int.tryParse(_sizeCtrl.text) ?? 0
      }
    };

    final result = await PdfService.runAutoBookmark(
      filePaths: _selectedFiles,
      outputDir: outputDir,
      config: config
    );

    setState(() {
      _isRunning = false;
      String currentLogs = result['logs'] ?? "";
      if (result['success'] == true) {
         currentLogs = "=== 任务完成 ===\n生成的书签文件后缀为 _bk.pdf\n" + currentLogs;
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("处理完成")));
      } else {
         currentLogs = "=== 任务失败 ===\n" + currentLogs;
      }
      _logs = currentLogs;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("自动生成书签")),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                 Card(
                   child: ListTile(
                     leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                     title: Text(_selectedFiles.isEmpty ? "点击选择 PDF 文件" : "已选 ${_selectedFiles.length} 个文件"),
                     subtitle: const Text("支持批量处理"),
                     onTap: _isRunning ? null : _pickFiles,
                     trailing: const Icon(Icons.upload_file),
                   ),
                 ),
                 
                 const SizedBox(height: 20),
                 const Text("配置方案", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                 DropdownButton<String>(
                   value: _selectedPreset,
                   isExpanded: true,
                   items: const [
                     DropdownMenuItem(value: 'chapter_cn', child: Text("中文章节 (第x章 标题)")),
                     DropdownMenuItem(value: 'number_dot', child: Text("数字章节 (1.1 标题)")),
                     DropdownMenuItem(value: 'custom', child: Text("自定义正则")),
                   ],
                   onChanged: (v) {
                     if (v != null) {
                       setState(() => _selectedPreset = v);
                       _applyPreset();
                     }
                   },
                 ),
                 
                 const SizedBox(height: 10),
                 TextField(
                   controller: _regexCtrl,
                   enabled: _selectedPreset == 'custom',
                   decoration: const InputDecoration(
                     labelText: "正则表达式",
                     border: OutlineInputBorder(),
                   ),
                 ),
                 
                 const SizedBox(height: 15),
                 TextField(
                   controller: _sizeCtrl,
                   keyboardType: TextInputType.number,
                   decoration: const InputDecoration(
                     labelText: "忽略小字号 (行高阈值)",
                     border: OutlineInputBorder(),
                     helperText: "设为 0 则不忽略，建议 10-15 过滤页眉页脚",
                   ),
                 ),
              ],
            ),
          ),
          
          if (_isRunning) const LinearProgressIndicator(),

          Container(
             color: Colors.grey[100], // Updated from black to light grey
             height: 150,
             width: double.infinity,
             padding: const EdgeInsets.all(8),
             child: SingleChildScrollView(
               child: Text(_logs, style: const TextStyle(color: Colors.black87, fontFamily: 'monospace', fontSize: 12)),
             ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
               width: double.infinity,
               height: 50,
               child: ElevatedButton(
                 onPressed: (_isRunning || _selectedFiles.isEmpty) ? null : _runTask,
                 child: const Text("开始自动生成"),
               ),
            ),
          )
        ],
      ),
    );
  }
}
