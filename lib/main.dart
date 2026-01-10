import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 👇 这里的 title 只影响任务管理器，我们在 build.yml 里还会强制改一次
      title: 'LOFTER 修复机',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        cardTheme: CardTheme(elevation: 2, margin: const EdgeInsets.all(8)),
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

  double _confidence = 0.4; // 默认 0.4 比较适中
  String? _wmPath;
  String? _noWmPath;
  String? _resultPath; // 🆕 存储修复后的图片路径用于预览
  bool _isProcessing = false;
  String _log = "✅ 准备就绪\n📂 图片将保存至：手机内部存储/Download/LofterFixed";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [Permission.storage, Permission.manageExternalStorage].request();
  }

  // --- UI 组件：说明书弹窗 ---
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
              Text("利用 AI 识别水印位置，从无水印原图中截取对应区域覆盖修复。"),
              SizedBox(height: 10),
              Text("2. 单张模式", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("手动选择一张【带水印图】和一张【无水印图】，点击修复即可。"),
              SizedBox(height: 10),
              Text("3. 批量模式", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("选择多张图片。系统会自动匹配文件名：\n- 水印图需包含 '-wm'\n- 原图需包含 '-orig'"),
              SizedBox(height: 10),
              Text("4. 关于置信度", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("建议 40%-50%。如果修补位置不对，请调低；如果没反应，请调低。"),
              SizedBox(height: 10),
              Text("5. 文件位置", style: TextStyle(fontWeight: FontWeight.bold)),
              Text("修复后的图片保存在【Download/LofterFixed】文件夹。"),
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
        _resultPath = null; // 重选图片清空预览
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
      _runNativeRepair(tasks, isSingle: false);
    }
  }

  Future<void> _runNativeRepair(List<Map<String, String>> tasks, {required bool isSingle}) async {
    setState(() => _isProcessing = true);
    try {
      final result = await platform.invokeMethod('processImages', {
        'tasks': tasks,
        'confidence': _confidence,
      });

      // Kotlin 现在返回的是修复成功的数量
      int successCount = result is int ? result : 0;
      
      String msg = successCount > 0 
          ? "🎉 成功修复 $successCount 张！\n📂 已保存至 Download/LofterFixed" 
          : "⚠️ 未能修复，请尝试降低置信度";
      
      _addLog(msg);
      Fluttertoast.showToast(msg: successCount > 0 ? "修复完成" : "修复失败");

      // 🆕 如果是单张模式且成功，推算输出路径用于预览
      if (isSingle && successCount > 0 && _wmPath != null) {
        String fileName = File(_wmPath!).uri.pathSegments.last;
        // 这是一个猜测路径，对应 Kotlin 里的保存逻辑
        String fixedPath = "/storage/emulated/0/Download/LofterFixed/Fixed_$fileName";
        if (File(fixedPath).existsSync()) {
          setState(() => _resultPath = fixedPath);
        }
      }

    } on PlatformException catch (e) {
      _addLog("❌ 错误: ${e.message}\n${e.details ?? ''}");
      _showErrorDialog(e.message ?? "未知错误", e.details?.toString());
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showErrorDialog(String title, String? content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("⚠️ $title"),
        content: Text(content ?? "无详细日志"),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("关闭"))],
      ),
    );
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
          // 置信度
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

          // 🆕 结果预览区 (仅单张模式且有结果时显示)
          if (_resultPath != null)
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
                      child: Image.file(File(_resultPath!), fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("✨ 修复效果预览", style: TextStyle(fontWeight: FontWeight.bold)),
                      Text("已自动保存到 Download 文件夹", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  )),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _resultPath = null),
                  )
                ],
              ),
            ),

          // 日志区
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