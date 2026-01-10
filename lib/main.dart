import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gal/gal.dart'; // 👈 引入神器
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LOFTER 修复机',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        cardTheme: const CardTheme(elevation: 2, margin: EdgeInsets.all(8)),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  static const platform = MethodChannel('com.example.lofter_fixer/processor');

  double _confidence = 0.4;
  String? _wmPath;
  String? _noWmPath;
  String? _resultPath;
  bool _isProcessing = false;
  String _log = "✅ 准备就绪\n📂 修复后的图片将保存到相册的【LofterFixed】相簿";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("📖 使用说明"),
        content: const Text("1. 选择有水印图和原图\n2. 点击修复\n3. 修复成功后，图片会自动出现在系统相册的 LofterFixed 文件夹中。"),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
      ),
    );
  }

  Future<void> _pickImage(bool isWm) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        if (isWm) _wmPath = image.path;
        else _noWmPath = image.path;
        _resultPath = null;
      });
    }
  }

  Future<void> _processSingle() async {
    if (_wmPath == null || _noWmPath == null) {
      Fluttertoast.showToast(msg: "请先选择两张图片");
      return;
    }
    _runNativeRepair([{'wm': _wmPath!, 'clean': _noWmPath!}], isSingle: true);
  }

  Future<void> _pickFilesBatch() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.image);
    if (result != null) {
      List<String> files = result.paths.whereType<String>().toList();
      _matchAndProcess(files);
    }
  }

  void _matchAndProcess(List<String> files) {
    List<Map<String, String>> tasks = [];
    List<String> wmFiles = files.where((f) => f.toLowerCase().contains("-wm.")).toList();
    for (var wm in wmFiles) {
      String expectedOrig = wm.replaceAll(RegExp(r'-wm\.', caseSensitive: false), '-orig.');
      String? foundOrig;
      try {
        foundOrig = files.firstWhere((f) => f == expectedOrig);
      } catch (e) {
        try { foundOrig = files.firstWhere((f) => f.toLowerCase() == expectedOrig.toLowerCase()); } catch (_) {}
      }
      if (foundOrig != null) tasks.add({'wm': wm, 'clean': foundOrig});
    }

    if (tasks.isEmpty) {
      _addLog("❌ 未找到匹配图片");
    } else {
      _addLog("✅ 匹配到 ${tasks.length} 组任务");
      _runNativeRepair(tasks, isSingle: false);
    }
  }

  Future<void> _runNativeRepair(List<Map<String, String>> tasks, {required bool isSingle}) async {
    setState(() => _isProcessing = true);
    try {
      // 1. 调用 Kotlin 进行计算，返回的是【缓存文件的路径列表】
      final List<dynamic> resultPaths = await platform.invokeMethod('processImages', {
        'tasks': tasks,
        'confidence': _confidence,
      });

      int successCount = 0;
      
      // 2. 遍历路径，使用 Gal 库保存到相册
      for (var path in resultPaths) {
        if (path is String && path.isNotEmpty) {
          try {
            // Gal 自动处理权限和路径
            await Gal.putImage(path, album: "LofterFixed");
            successCount++;
          } catch (e) {
             _addLog("⚠️ 保存失败: $e");
          }
        }
      }

      String msg = successCount > 0 
          ? "🎉 成功修复 $successCount 张！\n📂 已保存至相册的 LofterFixed 相簿" 
          : "⚠️ 修复后保存失败，请检查权限";
      
      _addLog(msg);
      Fluttertoast.showToast(msg: successCount > 0 ? "修复完成" : "保存失败");

      // 预览最后一张成功图片
      if (isSingle && successCount > 0 && resultPaths.isNotEmpty) {
        setState(() => _resultPath = resultPaths.first);
      }

    } on PlatformException catch (e) {
      _addLog("❌ 错误: ${e.message}\n${e.details ?? ''}");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _addLog(String msg) {
    setState(() => _log = "$msg\n----------------\n$_log");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("LOFTER 修复机"),
        actions: [IconButton(onPressed: _showHelp, icon: const Icon(Icons.help_outline))],
        bottom: TabBar(controller: _tabController, tabs: const [Tab(text: "单张精修"), Tab(text: "批量处理")]),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text("🕵️ 侦探置信度: "),
                Expanded(
                  child: Slider(value: _confidence, min: 0.1, max: 0.9, divisions: 8, label: "${(_confidence * 100).toInt()}%", onChanged: (v) => setState(() => _confidence = v)),
                ),
                Text("${(_confidence * 100).toInt()}%"),
              ],
            ),
          ),
          Expanded(child: TabBarView(controller: _tabController, children: [_buildSingleTab(), _buildBatchTab()])),
          if (_resultPath != null)
            Container(
              height: 120, padding: const EdgeInsets.all(8), color: Colors.green.withOpacity(0.1),
              child: Row(children: [
                  AspectRatio(aspectRatio: 1, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(_resultPath!), fit: BoxFit.cover))),
                  const SizedBox(width: 10),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text("✨ 修复成功", style: TextStyle(fontWeight: FontWeight.bold)),
                      Text("图片已存入相册", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ])),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _resultPath = null))
              ]),
            ),
          Container(height: 120, width: double.infinity, color: Colors.black.withOpacity(0.05), padding: const EdgeInsets.all(8), child: SingleChildScrollView(child: Text(_log, style: const TextStyle(fontSize: 12, fontFamily: "monospace"))))
        ],
      ),
    );
  }
  
  // ... (buildSingleTab, buildBatchTab, imgBtn 代码保持不变，直接用之前的即可) ...
  Widget _buildSingleTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _imgBtn("有水印图", _wmPath, true),
              const Icon(Icons.add_circle_outline, color: Colors.grey),
              _imgBtn("无水印图", _noWmPath, false),
            ],
          ),
          const SizedBox(height: 30),
          FilledButton.icon(
            onPressed: _isProcessing ? null : _processSingle,
            icon: _isProcessing 
                ? const SizedBox(width:16, height:16, child: CircularProgressIndicator(strokeWidth:2, color:Colors.white)) 
                : const Icon(Icons.auto_fix_high),
            label: Text(_isProcessing ? "正在修复..." : "开始修复"),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_zip, size: 80, color: Colors.teal),
          const SizedBox(height: 20),
          const Text("请选择包含以下后缀的图片对：", style: TextStyle(color: Colors.grey)),
          const Text("-wm.jpg (水印图)\n-orig.jpg (原图)", style: TextStyle(fontWeight: FontWeight.bold, height: 1.5)),
          const SizedBox(height: 30),
          FilledButton(
            onPressed: _isProcessing ? null : _pickFilesBatch,
            child: const Text("📂 批量选择并修复"),
          ),
        ],
      ),
    );
  }

  Widget _imgBtn(String label, String? path, bool isWm) {
    return GestureDetector(
      onTap: () => _pickImage(isWm),
      child: Column(
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
              image: path != null ? DecorationImage(image: FileImage(File(path)), fit: BoxFit.cover) : null,
            ),
            child: path == null ? const Icon(Icons.image_search, size: 40, color: Colors.grey) : null,
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}