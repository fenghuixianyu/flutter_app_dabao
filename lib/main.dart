import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:gal/gal.dart'; // 👈 引入相册神器
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
  String? _previewPath; // 用于显示的图片路径
  bool _isProcessing = false;
  String _log = "✅ 准备就绪\n📂 图片将自动保存到系统相册";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  // Gal 插件会在保存时自动请求权限，这里只做基础检查
  Future<void> _checkPermission() async {
    // 基础存储权限检查
    await Permission.storage.request();
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("📖 使用说明书"),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("1. 核心原理", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("AI 识别 + 像素级覆盖修复。"),
              SizedBox(height: 10),
              Text("2. 保存位置", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("修复成功后，图片会自动出现在您的【系统相册】中。"),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("懂了"))],
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
        _previewPath = null;
      });
    }
  }

  Future<void> _processSingle() async {
    if (_wmPath == null || _noWmPath == null) {
      Fluttertoast.showToast(msg: "请先选择两张图片");
      return;
    }
    await _checkPermission();
    _runNativeRepair([{'wm': _wmPath!, 'clean': _noWmPath!}]);
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
        try {
          foundOrig = files.firstWhere((f) => f.toLowerCase() == expectedOrig.toLowerCase());
        } catch (_) {}
      }
      if (foundOrig != null) tasks.add({'wm': wm, 'clean': foundOrig});
    }

    if (tasks.isEmpty) {
      _addLog("❌ 未找到匹配图片。请确保文件名包含 -wm 和 -orig");
    } else {
      _addLog("✅ 匹配到 ${tasks.length} 组任务");
      _runNativeRepair(tasks);
    }
  }

  Future<void> _runNativeRepair(List<Map<String, String>> tasks) async {
    setState(() => _isProcessing = true);
    try {
      // 1. 调用 Kotlin 识别并修复，拿到缓存路径
      final result = await platform.invokeMethod('processImages', {
        'tasks': tasks,
        'confidence': _confidence,
      });

      // result 结构: { "paths": ["/cache/Fixed_1.jpg", ...], "logs": "..." }
      final Map<dynamic, dynamic> resultMap = result as Map<dynamic, dynamic>;
      final List<dynamic> paths = resultMap['paths'] ?? [];
      final String logs = resultMap['logs'] ?? "";

      if (logs.isNotEmpty) {
        _addLog("⚠️ 调试日志:\n$logs");
      }

      if (paths.isEmpty) {
        _addLog("⚠️ 没有图片修复成功，请检查置信度");
        Fluttertoast.showToast(msg: "修复失败");
      } else {
        int savedCount = 0;
        // 2. 使用 Flutter 插件把缓存文件存入相册
        for (String path in paths) {
          try {
            // Gal.putImage 将图片存入系统相册
            await Gal.putImage(path);
            savedCount++;
            // 设置最后一张为预览图
            setState(() => _previewPath = path);
          } catch (e) {
            _addLog("❌ 保存相册失败 ($path): $e");
          }
        }

        String msg = "🎉 成功修复并保存 $savedCount 张！\n请打开系统相册查看";
        _addLog(msg);
        Fluttertoast.showToast(msg: "成功保存到相册");
      }

    } on PlatformException catch (e) {
      _addLog("❌ 错误: ${e.message}");
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
        actions: [
          IconButton(onPressed: _showHelp, icon: const Icon(Icons.help_outline)),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: "单张精修"), Tab(text: "批量处理")],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text("🕵️ 侦探置信度: "),
                Expanded(
                  child: Slider(
                    value: _confidence,
                    min: 0.1,
                    max: 0.9,
                    divisions: 8,
                    label: "${(_confidence * 100).toInt()}%",
                    onChanged: (v) => setState(() => _confidence = v),
                  ),
                ),
                Text("${(_confidence * 100).toInt()}%"),
              ],
            ),
          ),
          
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSingleTab(),
                _buildBatchTab(),
              ],
            ),
          ),

          // 预览区
          if (_previewPath != null)
            Container(
              height: 120,
              padding: const EdgeInsets.all(8),
              color: Colors.green.withOpacity(0.1),
              child: Row(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(_previewPath!), fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("✨ 修复成功", style: TextStyle(fontWeight: FontWeight.bold)),
                      Text("已保存到系统相册", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  )),
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    onPressed: () {},
                  )
                ],
              ),
            ),

          Container(
            height: 120,
            width: double.infinity,
            color: Colors.black.withOpacity(0.05),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Text(_log, style: const TextStyle(fontSize: 12, fontFamily: "monospace")),
            ),
          )
        ],
      ),
    );
  }

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