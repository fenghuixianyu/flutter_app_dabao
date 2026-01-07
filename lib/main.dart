import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const DiaryApp());
}

// --- 1. 数据模型 ---
class DiaryEntry {
  String id;
  DateTime date;
  String content;

  DiaryEntry({required this.id, required this.date, required this.content});

  // 把数据变成 JSON 字符串存手机
  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'content': content,
      };

  // 从手机读取 JSON 变回数据
  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    return DiaryEntry(
      id: json['id'],
      date: DateTime.parse(json['date']),
      content: json['content'],
    );
  }
}

// --- 2. 主程序壳子 ---
class DiaryApp extends StatelessWidget {
  const DiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '时光日记',
      theme: ThemeData(
        useMaterial3: true,
        // 这里的背景色设为稍微带点灰的白，更有纸质感
        scaffoldBackgroundColor: const Color(0xFFF9F9F9),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5D6D7E)),
      ),
      home: const DiaryHomePage(),
    );
  }
}

// --- 3. 首页 (带状态的) ---
class DiaryHomePage extends StatefulWidget {
  const DiaryHomePage({super.key});

  @override
  State<DiaryHomePage> createState() => _DiaryHomePageState();
}

class _DiaryHomePageState extends State<DiaryHomePage> {
  List<DiaryEntry> entries = [];

  @override
  void initState() {
    super.initState();
    _loadEntries(); // 启动时加载日记
  }

  // 读取日记
  Future<void> _loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('diary_data');
    if (data != null) {
      final List<dynamic> jsonList = jsonDecode(data);
      setState(() {
        entries = jsonList.map((e) => DiaryEntry.fromJson(e)).toList();
        // 按时间倒序排列（最新的在上面）
        entries.sort((a, b) => b.date.compareTo(a.date));
      });
    } else {
      // 如果没有日记，加一条默认的 demo
      _addEntry("今天开始使用这个日记APP了。\n复刻的界面真的很还原，感觉像在写一本真正的书。");
    }
  }

  // 保存日记
  Future<void> _saveEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString('diary_data', data);
  }

  // 添加一条新日记
  void _addEntry(String content) {
    final newEntry = DiaryEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: DateTime.now(),
      content: content,
    );
    setState(() {
      entries.insert(0, newEntry); // 加到最前面
    });
    _saveEntries();
  }

  // 弹出写日记窗口
  void _showAddDialog() {
    TextEditingController controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // 让弹窗全屏或变高
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("记录当下", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: "今天发生了什么...",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (controller.text.isNotEmpty) {
                      _addEntry(controller.text);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("保存"),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✨ 悬浮按钮 (羽毛笔)
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: Colors.black, // 黑色底
        child: const Icon(Icons.edit_outlined, color: Colors.white), // 羽毛笔图标
      ),
      body: CustomScrollView(
        slivers: [
          // ✨ 顶部大图 Header
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            backgroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                DateFormat('MM月 dd日').format(DateTime.now()), // 动态显示今天日期
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w300),
              ),
              background: Image.asset(
                'assets/images/header.jpg', // 你的图片路径
                fit: BoxFit.cover,
                // 如果暂时没图，可以用下面这个网络图测试，把上面那行注释掉
                // image: NetworkImage('https://images.unsplash.com/photo-1507525428034-b723cf961d3e'),
              ),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.public, color: Colors.black54), onPressed: () {}),
              IconButton(icon: const Icon(Icons.menu, color: Colors.black54), onPressed: () {}),
            ],
          ),

          // ✨ 下方的时间轴列表
          SliverPadding(
            padding: const EdgeInsets.only(top: 20, bottom: 80),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return TimelineItem(entry: entries[index]);
                },
                childCount: entries.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- 4. 核心组件：时间轴单条样式 (完全复刻设计图) ---
class TimelineItem extends StatelessWidget {
  final DiaryEntry entry;

  const TimelineItem({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    // 格式化日期
    final yearMonth = DateFormat('yyyy.MM').format(entry.date);
    final day = DateFormat('dd').format(entry.date);
    final fullDate = DateFormat('yyyy年MM月dd日').format(entry.date);
    final time = DateFormat('HH:mm').format(entry.date);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [左侧] 日期区 (宽度约 80)
          SizedBox(
            width: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(height: 10), // 对齐微调
                Text(yearMonth, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(day, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
          ),

          // [中间] 时间轴线 (宽度约 40)
          SizedBox(
            width: 40,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                // 竖线 (Container模拟)
                Container(
                  width: 1,
                  height: double.infinity, // 无限高，撑满整行
                  color: Colors.grey.withOpacity(0.3),
                  margin: const EdgeInsets.only(top: 15),
                ),
                // 小圆圈
                Container(
                  margin: const EdgeInsets.only(top: 22), // 稍微往下一点对齐日期的中间
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black54, width: 1.5),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),

          // [右侧] 内容区 (占据剩余空间)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 40, right: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题：全日期
                  Text(fullDate, style: const TextStyle(fontSize: 16, color: Colors.black87)),
                  const SizedBox(height: 4),
                  // 时间
                  Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  // 正文内容
                  Text(
                    entry.content,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black54,
                      height: 1.6, // 行高，让文字读起来舒服
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
