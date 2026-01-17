import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import '../models/diary_model.dart';
import '../utils/storage_helper.dart';
import '../utils/theme_service.dart';
import '../widgets/timeline_item.dart';
import 'editor_page.dart';
import 'letter_box_page.dart';
import 'search_page.dart';

class DiaryHomePage extends StatefulWidget {
  const DiaryHomePage({super.key});
  @override
  State<DiaryHomePage> createState() => _DiaryHomePageState();
}

class _DiaryHomePageState extends State<DiaryHomePage> {
  List<DiaryEntry> entries = [];
  List<FutureLetter> letters = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  // --- 数据加载与逻辑 ---

  Future<void> _refreshData() async {
    final e = await StorageHelper.loadEntries();
    final l = await StorageHelper.loadLetters();
    if (mounted) {
      setState(() {
        entries = e;
        letters = l;
      });
    }
    _checkIncomingLetters();
  }

  void _checkIncomingLetters() {
    final now = DateTime.now();
    for (var letter in letters) {
      if (now.isAfter(letter.deliveryDate) && !letter.isRead) {
        // 延迟一点弹出，避免和 build 冲突
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _showLetterDialog(letter);
        });
      }
    }
  }

  void _showLetterDialog(FutureLetter letter) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("📬 来自过去的信"),
        content: SingleChildScrollView(child: Text(letter.content)),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => letter.isRead = true);
              StorageHelper.saveLetters(letters);
              Navigator.pop(context);
              // 跳转去回复
              _goToEditPage(
                initialContent: "收到了一封来自 ${DateFormat('yyyy-MM-dd').format(letter.createDate)} 的信。\n\n${letter.content}\n\n我的回复："
              );
            },
            child: const Text("收下并回复"),
          )
        ],
      ),
    );
  }

  void _goToEditPage({DiaryEntry? existingEntry, String? initialContent}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditorPage(
          entry: existingEntry,
          initialContent: initialContent,
          onSave: (entry) async {
            // 简单处理：删旧加新
            entries.removeWhere((e) => e.id == entry.id);
            entries.add(entry);
            // 重新排序
            entries.sort((a, b) => b.date.compareTo(a.date));
            await StorageHelper.saveEntries(entries);
            _refreshData();
          },
          onDelete: (id) async {
            entries.removeWhere((e) => e.id == id);
            await StorageHelper.saveEntries(entries);
            _refreshData();
          },
        ),
      ),
    );
  }
  
  // --- 导入导出逻辑 ---

  Future<void> _exportData() async {
    StringBuffer buffer = StringBuffer();
    buffer.writeln("# 时光日记备份\n");
    for (var e in entries) {
      buffer.writeln("## ${DateFormat('yyyy-MM-dd').format(e.date)} ${e.title}");
      buffer.writeln(e.content);
      buffer.writeln("\n---\n");
    }
    // 埋藏 JSON 数据
    final jsonString = jsonEncode(entries.map((e) => e.toJson()).toList());
    buffer.writeln("\n<!-- DATA_BACKUP_START");
    buffer.writeln(jsonString);
    buffer.writeln("DATA_BACKUP_END -->");
    
    final String fileName = "时光日记备份_${DateFormat('yyyyMMdd').format(DateTime.now())}.txt";
    await Share.share(buffer.toString(), subject: fileName);
  }

  Future<void> _importData() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      try {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        if (content.contains("DATA_BACKUP_START")) {
          final jsonStr = content.split("DATA_BACKUP_START")[1].split("DATA_BACKUP_END")[0].trim();
          final List<dynamic> jsonList = jsonDecode(jsonStr);
          List<DiaryEntry> newEntries = jsonList.map((e) => DiaryEntry.fromJson(e)).toList();
          
          await StorageHelper.saveEntries(newEntries);
          _refreshData();
          
          if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ 导入成功")));
        } else {
          throw Exception("No backup tag found");
        }
      } catch (e) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ 导入失败，文件格式错误")));
      }
    }
  }

  // --- UI 构建 ---

  @override
  Widget build(BuildContext context) {
    // 获取当前主题
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final headerTextColor = isDark ? Colors.white : Colors.black87;
    final headerIconColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor, // 跟随主题
      endDrawer: _buildDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _goToEditPage(),
        backgroundColor: theme.primaryColor,
        child: const Icon(Icons.edit_outlined, color: Colors.white),
      ),
      body: CustomScrollView(
        // 🚀 性能优化 1：预渲染屏幕外 500 像素的内容，防止滑动白屏
        cacheExtent: 500,
        
        slivers: [
          SliverAppBar(
            expandedHeight: 220.0,
            pinned: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.search, color: headerIconColor),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (c) => SearchPage(allEntries: entries, onEntryTap: (e) {
                  _goToEditPage(existingEntry: e);
                })));
              },
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                DateFormat('MM月 dd日').format(DateTime.now()),
                style: TextStyle(color: headerTextColor, fontWeight: FontWeight.w300),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/header.jpg', 
                    fit: BoxFit.cover,
                    // 🚀 性能优化 2：限制图片加载内存，减少卡顿
                    cacheWidth: 1080, 
                  ),
                  // 渐变层
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, 
                        end: Alignment.bottomCenter, 
                        colors: [
                          Colors.transparent, 
                          theme.scaffoldBackgroundColor.withOpacity(0.95)
                        ]
                      )
                    )
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(icon: Icon(Icons.menu, color: headerIconColor), onPressed: () => _scaffoldKey.currentState?.openEndDrawer()),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.only(top: 20, bottom: 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => GestureDetector(
                  onTap: () => _goToEditPage(existingEntry: entries[index]),
                  child: TimelineItem(entry: entries[index]),
                ),
                childCount: entries.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 侧边栏 (设置中心) ---
  Widget _buildDrawer() {
    final theme = Theme.of(context);
    
    return Drawer(
      width: 300,
      backgroundColor: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20), 
              child: Text("设置与拓展", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.textTheme.titleLarge?.color))
            ),
            
            const Divider(),
            
            // 1. 皮肤选择
            const Padding(padding: EdgeInsets.only(left:20, top:10), child: Align(alignment: Alignment.centerLeft, child: Text("🎨 主题风格", style: TextStyle(color: Colors.grey, fontSize: 12)))),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSkinBtn("经典", const Color(0xFFF9F9F9), "classic"),
                  _buildSkinBtn("羊皮", const Color(0xFFF2EAD3), "warm"),
                  _buildSkinBtn("黑夜", const Color(0xFF222222), "dark", isDarkBtn: true),
                ],
              ),
            ),

            const Divider(),

            // 2. 字体显示设置
            const Padding(padding: EdgeInsets.only(left:20, top:10), child: Align(alignment: Alignment.centerLeft, child: Text("Aa 显示设置", style: TextStyle(color: Colors.grey, fontSize: 12)))),
            
            // 加粗开关
            SwitchListTile(
              title: const Text("字体加粗", style: TextStyle(fontSize: 16)),
              subtitle: const Text("让文字更清晰有力", style: TextStyle(fontSize: 12, color: Colors.grey)),
              value: ThemeService.isBold.value,
              activeColor: theme.primaryColor,
              onChanged: (val) {
                // 这里调用 setState 是为了刷新 Switch 的开关状态动画
                setState(() {});
                ThemeService.updateBold(val);
              },
            ),
            
            // 字号滑块 (优化版)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("字体大小"),
                      Text("${(ThemeService.fontScale.value * 100).toInt()}%", style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  Slider(
                    value: ThemeService.fontScale.value,
                    min: 0.8, 
                    max: 1.3,
                    divisions: 5,
                    activeColor: theme.primaryColor,
                    // 🚀 性能优化 3：拖动时只更新滑块视觉，不触发全局重绘
                    onChanged: (val) {
                      setState(() {
                        ThemeService.fontScale.value = val;
                      });
                    },
                    // 🛑 松手时才触发全局主题更新
                    onChangeEnd: (val) {
                      ThemeService.updateFontScale(val);
                    },
                  ),
                ],
              ),
            ),

            const Divider(),
            
            // 3. 其他功能
            ListTile(leading: const Icon(Icons.mail_outline), title: const Text("写信给未来"), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => LetterBoxPage(onSave: (l) async { letters = l; await StorageHelper.saveLetters(letters); }))); }),
            ListTile(leading: const Icon(Icons.output), title: const Text("备份数据"), onTap: _exportData),
            ListTile(leading: const Icon(Icons.file_download_outlined), title: const Text("恢复日记"), onTap: _importData),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text("共记录 ${entries.length} 篇\n${entries.fold(0, (sum, e) => sum + e.content.length)} 字", style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSkinBtn(String name, Color color, String themeKey, {bool isDarkBtn = false}) {
    return GestureDetector(
      onTap: () => ThemeService.updateTheme(themeKey),
      child: Column(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [BoxShadow(blurRadius: 5, color: Colors.black.withOpacity(0.1))]
            ),
            child: isDarkBtn ? const Icon(Icons.nightlight_round, size: 18, color: Colors.white) : null,
          ),
          const SizedBox(height: 5),
          Text(name, style: const TextStyle(fontSize: 12))
        ],
      ),
    );
  }
}