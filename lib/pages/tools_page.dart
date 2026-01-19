import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/pdf_service.dart';

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  List<String> _selectedFiles = [];
  String _logs = "";
  bool _isRunning = false;

  Future<void> _pickFiles() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null) {
      setState(() => _selectedFiles = result.paths.whereType<String>().toList());
    }
  }

  Future<void> _runAction(String action, String label) async {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("请先选择文件")));
      return;
    }
    
    setState(() {
      _isRunning = true;
      _logs = "正在执行: $label...\n";
    });

    String outputDir = File(_selectedFiles.first).parent.path;
    Map<String, dynamic> result;

    if (action == 'extract') {
        result = await PdfService.extractBookmarks(
            filePaths: _selectedFiles,
            outputDir: outputDir
        );
    } else if (action == 'add_bookmarks') {
        result = await PdfService.addBookmarks(
            filePaths: _selectedFiles,
            outputDir: outputDir, 
            offset: 0
        );
    } else {
        result = {'success': false, 'logs': '未知操作'};
    }

    setState(() {
      _isRunning = false;
      String status = result['success'] ? "成功" : "失败";
      _logs = "=== $status ===\n" + (result['logs'] ?? "");
      if (result['success']) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$label 完成")));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("书签工具箱")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
               child: ListTile(
                 leading: const Icon(Icons.library_books, color: Colors.orangeAccent),
                 title: Text(_selectedFiles.isEmpty ? "点击选择 PDF 文件" : "已选 ${_selectedFiles.length} 个文件"),
                 subtitle: const Text("对选中的文件进行批量操作"),
                 onTap: _isRunning ? null : _pickFiles,
                 trailing: const Icon(Icons.upload_file),
               ),
            ),
          ),
          
          if (_selectedFiles.isNotEmpty)
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 20),
               alignment: Alignment.centerLeft,
               child: Text("输出目录: ${File(_selectedFiles.first).parent.path}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
             ),
          
          Expanded(
            child: ListView(
               padding: const EdgeInsets.all(16),
               children: [
                 _buildActionButton(
                   icon: Icons.upload,
                   label: "提取书签 (PDF -> TXT)",
                   desc: "将书签导出为同名 TXT 文件",
                   onTap: () => _runAction('extract', '提取书签'),
                 ),
                 const SizedBox(height: 10),
                 _buildActionButton(
                   icon: Icons.download,
                   label: "写入书签 (TXT -> PDF)",
                   desc: "读取同名 TXT 文件并写入到新 PDF",
                   onTap: () => _runAction('add_bookmarks', '写入书签'),
                 ),
                 const Padding(
                   padding: EdgeInsets.all(8.0),
                   child: Text(
                     "注意：写入书签时，程序会自动在 PDF 同级目录下查找同名的 .txt 文件。",
                     style: TextStyle(color: Colors.grey, fontSize: 12),
                   ),
                 )
               ],
            ),
          ),
          
          if (_isRunning) const LinearProgressIndicator(),

          Container(
             color: Colors.grey[100],
             height: 200,
             width: double.infinity,
             padding: const EdgeInsets.all(8),
             child: SingleChildScrollView(
               child: Text(_logs, style: const TextStyle(color: Colors.black87, fontFamily: 'monospace', fontSize: 12)),
             ),
          )
        ],
      )
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required String desc, required VoidCallback onTap}) {
     return ElevatedButton(
       style: ElevatedButton.styleFrom(
         padding: const EdgeInsets.all(16),
         alignment: Alignment.centerLeft,
       ),
       onPressed: _isRunning ? null : onTap,
       child: Row(
         children: [
           Icon(icon, size: 32),
           const SizedBox(width: 16),
           Expanded(
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                 Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
               ],
             ),
           )
         ],
       ),
     );
  }
}
