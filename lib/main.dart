import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const DiaryApp());
}

// --- 1. 数据模型 ---

class DiaryEntry {
  String id;
  DateTime date;
  String content;

  DiaryEntry({required this.id, required this.date, required this.content});

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'content': content,
      };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    return DiaryEntry(
      id: json['id'],
      date: DateTime.parse(json['date']),
      content: json['content'],
    );
  }
}

class FutureLetter {
  String id;
  DateTime createDate;
  DateTime targetDate;
  String content;
  bool isRead;

  FutureLetter({
    required this.id,
    required this.createDate,
    required this.targetDate,
    required this.content,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'createDate': createDate.toIso8601String(),
        'targetDate': targetDate.toIso8601String(),
        'content': content,
        'isRead': isRead,
      };

  factory FutureLetter.fromJson(Map<String, dynamic> json) {
    return FutureLetter(
      id: json['id'],
      createDate: DateTime.parse(json['createDate']),
      targetDate: DateTime.parse(json['targetDate']),
      content: json['content'],
      isRead: json['isRead'] ?? false,
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
        scaffoldBackgroundColor: const Color(0xFFF9F9F9),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5D6D7E),
          surface: const Color(0xFFF9F9F9),
        ),
        // 定义全局文本样式，正文使用自定义字体
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontFamily: 'MyFont', fontSize: 16, height: 1.6),
          bodyMedium: TextStyle(fontFamily: 'MyFont', fontSize: 15, height: 1.6),
        ),
      ),
      home: const DiaryHomePage(),
    );
  }
}

// --- 3. 首页 ---

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
    _loadAllData();
  }

  // 加载数据：日记 + 信件
  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. 加载日记
    final String? diaryData = prefs.getString('diary_data');
    if (diaryData != null) {
      final List<dynamic> jsonList = jsonDecode(diaryData);
      entries = jsonList.map((e) => DiaryEntry.fromJson(e)).toList();
      entries.sort((a, b) => b.date.compareTo(a.date)); // 倒序
    } else {
      // 首次使用引导
      _saveEntry(DiaryEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        date: DateTime.now(), 
        content: "欢迎来到你的时光日记。\n这里的所有数据都只保存在你的手机里。\n尝试点击右下角的羽毛笔开始记录吧。"
      ));
    }

    // 2. 加载信件
    final String? letterData = prefs.getString('future_letters');
    if (letterData != null) {
      final List<dynamic> jsonList = jsonDecode(letterData);
      letters = jsonList.map((e) => FutureLetter.fromJson(e)).toList();
    }

    setState(() {});

    // 3. 检查是否有“来自过去的信”送达
    _checkArrivedLetters();
  }

  // 保存日记列表
  Future<void> _saveAllEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString('diary_data', data);
    setState(() {});
  }

  // 新增或更新单条日记
  void _saveEntry(DiaryEntry entry) {
    // 检查是否已存在（编辑模式）
    int index = entries.indexWhere((e) => e.id == entry.id);
    if (index != -1) {
      entries[index] = entry;
    } else {
      entries.insert(0, entry);
    }
    entries.sort((a, b) => b.date.compareTo(a.date));
    _saveAllEntries();
  }

  // 删除日记
  void _deleteEntry(String id) {
    entries.removeWhere((e) => e.id == id);
    _saveAllEntries();
  }

  // 保存信件列表
  Future<void> _saveAllLetters() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(letters.map((e) => e.toJson()).toList());
    await prefs.setString('future_letters', data);
  }

  // 检查信件
  void _checkArrivedLetters() {
    final now = DateTime.now();
    // 筛选条件：目标日期 <= 今天，且未读
    final arrived = letters.where((l) => l.targetDate.isBefore(now.add(const Duration(days: 1))) && !l.isRead).toList();
    
    if (arrived.isNotEmpty) {
      // 延迟一点弹出，等页面构建完
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        _showArrivedLetterDialog(arrived.first);
      });
    }
  }

  // 弹出信件阅读窗口
  void _showArrivedLetterDialog(FutureLetter letter) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("📧 来自过去的信"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("写于: ${DateFormat('yyyy-MM-dd').format(letter.createDate)}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            Text(letter.content, style: const TextStyle(fontFamily: 'MyFont', fontSize: 16)),
            const SizedBox(height: 20),
            const Text("你想对那时的自己说什么？(可作为日记保存)", style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // 标记为已读
              letter.isRead = true;
              _saveAllLetters();
              Navigator.pop(context);
            },
            child: const Text("仅收信"),
          ),
          FilledButton(
            onPressed: () {
              letter.isRead = true;
              _saveAllLetters();
              Navigator.pop(context);
              // 跳转写日记，预填回复
              _openEditor(date: DateTime.now(), initialContent: "收到 ${DateFormat('yyyy-MM-dd').format(letter.createDate)} 的来信：\n\n“${letter.content}”\n\n我想说：\n");
            },
            child: const Text("回复并记录"),
          ),
        ],
      ),
    );
  }

  // 打开写日记/编辑日记 (跳转到新页面)
  void _openEditor({DiaryEntry? existingEntry, DateTime? date, String? initialContent}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DiaryDetailPage(
          entry: existingEntry,
          defaultDate: date ?? DateTime.now(),
          defaultContent: initialContent,
        ),
      ),
    );

    if (result != null) {
      if (result['action'] == 'save') {
        _saveEntry(result['entry']);
      } else if (result['action'] == 'delete') {
        _deleteEntry(result['id']);
      }
    }
  }

  // 搜索功能
  void _showSearch() {
    showSearch(context: context, delegate: DiarySearchDelegate(entries, (entry) {
      _openEditor(existingEntry: entry);
    }));
  }

  // 导出 Markdown
  Future<void> _exportMarkdown() async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/my_diary_export.md');
      
      StringBuffer buffer = StringBuffer();
      buffer.writeln("# 我的时光日记\n");
      for (var entry in entries) {
        buffer.writeln("## ${DateFormat('yyyy-MM-dd HH:mm').format(entry.date)}");
        buffer.writeln(entry.content);
        buffer.writeln("\n---\n");
      }

      await file.writeAsString(buffer.toString());
      await Share.shareXFiles([XFile(file.path)], text: '这是我的日记备份');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("导出失败: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF9F9F9),
      // 侧边栏
      endDrawer: _buildDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        backgroundColor: Colors.black,
        elevation: 4,
        child: const Icon(Icons.edit_outlined, color: Colors.white),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180.0,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFFF9F9F9),
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.search, color: Colors.black54, size: 28),
              onPressed: _showSearch,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.menu, color: Colors.black54, size: 28),
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              ),
              const SizedBox(width: 10),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                DateFormat('MM月 dd日').format(DateTime.now()),
                style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w300, fontSize: 24),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset('assets/images/header.jpg', fit: BoxFit.cover),
                  // 渐变遮罩，保证文字清晰
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, const Color(0xFFF9F9F9).withOpacity(0.8), const Color(0xFFF9F9F9)],
                        stops: const [0.0, 0.8, 1.0],
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.only(top: 10, bottom: 80),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return GestureDetector(
                    onTap: () => _openEditor(existingEntry: entries[index]),
                    child: TimelineItem(entry: entries[index]),
                  );
                },
                childCount: entries.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 侧边栏构建
  Widget _buildDrawer() {
    // 统计数据
    int totalWords = entries.fold(0, (sum, item) => sum + item.content.length);
    int totalDays = entries.map((e) => DateFormat('yyyyMMdd').format(e.date)).toSet().length;

    return Drawer(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFFF5F5F7)),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("数据统计", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statItem("累计天数", "$totalDays"),
                      _statItem("总字数", "$totalWords"),
                    ],
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.mark_email_unread_outlined),
            title: const Text("写给未来"),
            subtitle: const Text("寄往某天的信件管理"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => FutureLettersPage(
                letters: letters, 
                onSave: (ls) {
                  letters = ls; 
                  _saveAllLetters();
                  setState((){});
                }
              )));
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text("导出日记"),
            subtitle: const Text("生成 Markdown 备份"),
            onTap: () {
              Navigator.pop(context);
              _exportMarkdown();
            },
          ),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.all(20.0),
            child: Text("v1.2.0 By Flutter Cloud", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

// --- 4. 详情编辑页 (沉浸式阅读与编辑) ---

class DiaryDetailPage extends StatefulWidget {
  final DiaryEntry? entry;
  final DateTime defaultDate;
  final String? defaultContent;

  const DiaryDetailPage({super.key, this.entry, required this.defaultDate, this.defaultContent});

  @override
  State<DiaryDetailPage> createState() => _DiaryDetailPageState();
}

class _DiaryDetailPageState extends State<DiaryDetailPage> {
  late TextEditingController _contentController;
  late DateTime _selectedDate;
  bool _isEditing = false; // 是否处于编辑模式

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.entry?.date ?? widget.defaultDate;
    _contentController = TextEditingController(text: widget.entry?.content ?? widget.defaultContent ?? "");
    
    // 如果是新建日记，默认直接进入编辑模式
    if (widget.entry == null) {
      _isEditing = true;
    }
  }

  void _save() {
    if (_contentController.text.trim().isEmpty) return;
    
    final entry = DiaryEntry(
      id: widget.entry?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      date: _selectedDate,
      content: _contentController.text,
    );
    Navigator.pop(context, {'action': 'save', 'entry': entry});
  }

  void _delete() {
    if (widget.entry == null) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("确认删除"),
      content: const Text("这条回忆将被永久抹去。"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
        TextButton(onPressed: () {
          Navigator.pop(ctx);
          Navigator.pop(context, {'action': 'delete', 'id': widget.entry!.id});
        }, child: const Text("删除", style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('zh'), // 尝试中文适配
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day, DateTime.now().hour, DateTime.now().minute);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 仿照设计图的干净风格
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined, color: Colors.black54),
              onPressed: _pickDate,
            ),
            TextButton(
              onPressed: _save,
              child: const Text("完成", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ] else ...[
             IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _delete,
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.black87),
              onPressed: () => setState(() => _isEditing = true),
            ),
          ]
        ],
      ),
      body: GestureDetector(
        // 点击空白处收起键盘
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          color: Colors.white, // 确保全屏点击有效
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 大号日期显示
              GestureDetector(
                onTap: _isEditing ? _pickDate : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('yyyy.MM').format(_selectedDate),
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    Text(
                      DateFormat('dd').format(_selectedDate),
                      style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w300, height: 1.0, color: Colors.black87),
                    ),
                    const SizedBox(height: 10),
                     Text(
                      "${DateFormat('HH:mm').format(_selectedDate)}  |  ${_getWeekday(_selectedDate)}",
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              const Divider(height: 1),
              const SizedBox(height: 20),
              // 内容编辑区
              Expanded(
                child: _isEditing 
                ? TextField(
                    controller: _contentController,
                    maxLines: null, // 无限高度
                    style: const TextStyle(fontFamily: 'MyFont', fontSize: 18, height: 1.8, color: Colors.black87),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: "写点什么吧...",
                    ),
                  )
                : SingleChildScrollView(
                    child: Text(
                      _contentController.text,
                      style: const TextStyle(fontFamily: 'MyFont', fontSize: 18, height: 1.8, color: Colors.black87),
                    ),
                  ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getWeekday(DateTime date) {
    const weeks = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
    return weeks[date.weekday % 7];
  }
}

// --- 5. 未来信箱管理页 ---

class FutureLettersPage extends StatefulWidget {
  final List<FutureLetter> letters;
  final Function(List<FutureLetter>) onSave;

  const FutureLettersPage({super.key, required this.letters, required this.onSave});

  @override
  State<FutureLettersPage> createState() => _FutureLettersPageState();
}

class _FutureLettersPageState extends State<FutureLettersPage> {
  late List<FutureLetter> _letters;

  @override
  void initState() {
    super.initState();
    _letters = List.from(widget.letters);
    _letters.sort((a, b) => a.targetDate.compareTo(b.targetDate));
  }

  void _addLetter() async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2050),
      helpText: "选择寄送日期",
    );

    if (pickedDate == null) return;
    if (!mounted) return;

    TextEditingController controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("写给 ${DateFormat('yyyy-MM-dd').format(pickedDate)}"),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(hintText: "未来的我，你好吗..."),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          FilledButton(onPressed: () {
            if (controller.text.isNotEmpty) {
              setState(() {
                _letters.add(FutureLetter(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  createDate: DateTime.now(),
                  targetDate: pickedDate,
                  content: controller.text,
                ));
                _letters.sort((a, b) => a.targetDate.compareTo(b.targetDate));
              });
              widget.onSave(_letters);
              Navigator.pop(context);
            }
          }, child: const Text("寄出")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("时光信箱")),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addLetter,
        label: const Text("写封新信"),
        icon: const Icon(Icons.send),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _letters.isEmpty 
        ? const Center(child: Text("还没有寄出的信件", style: TextStyle(color: Colors.grey)))
        : ListView.builder(
            itemCount: _letters.length,
            itemBuilder: (context, index) {
              final letter = _letters[index];
              final isArrived = letter.targetDate.isBefore(DateTime.now());
              return ListTile(
                leading: Icon(
                  letter.isRead ? Icons.mark_email_read : (isArrived ? Icons.mark_email_unread : Icons.hourglass_top),
                  color: isArrived ? Colors.black : Colors.grey,
                ),
                title: Text("寄往: ${DateFormat('yyyy-MM-dd').format(letter.targetDate)}"),
                subtitle: Text(
                  letter.content, 
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'MyFont'),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                  onPressed: () {
                     setState(() {
                       _letters.removeAt(index);
                       widget.onSave(_letters);
                     });
                  },
                ),
                onTap: isArrived || true ? () { // 测试方便，允许随时查看，实际逻辑可限制 isArrived
                   showDialog(context: context, builder: (ctx) => AlertDialog(
                     title: Text(isArrived ? "已送达" : "运输中..."),
                     content: Text(letter.content, style: const TextStyle(fontFamily: 'MyFont', fontSize: 16)),
                     actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("关闭"))],
                   ));
                } : null,
              );
            },
          ),
    );
  }
}

// --- 6. 搜索代理 ---

class DiarySearchDelegate extends SearchDelegate {
  final List<DiaryEntry> entries;
  final Function(DiaryEntry) onSelected;

  DiarySearchDelegate(this.entries, this.onSelected);

  @override
  String get searchFieldLabel => "搜索记忆...";

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = "")];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, null));
  }

  @override
  Widget buildResults(BuildContext context) => _buildList();

  @override
  Widget buildSuggestions(BuildContext context) => _buildList();

  Widget _buildList() {
    final results = entries.where((e) => e.content.contains(query)).toList();
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final entry = results[index];
        return ListTile(
          title: Text(DateFormat('yyyy-MM-dd').format(entry.date)),
          subtitle: Text(entry.content, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () {
            close(context, null);
            onSelected(entry);
          },
        );
      },
    );
  }
}

// --- 7. 时间轴组件 (UI复用) ---

class TimelineItem extends StatelessWidget {
  final DiaryEntry entry;
  const TimelineItem({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final yearMonth = DateFormat('yyyy.MM').format(entry.date);
    final day = DateFormat('dd').format(entry.date);
    final fullDate = DateFormat('yyyy年MM月dd日').format(entry.date);
    final time = DateFormat('HH:mm').format(entry.date);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(height: 10),
                Text(yearMonth, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(day, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
          ),
          SizedBox(
            width: 40,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Container(
                  width: 1,
                  height: double.infinity,
                  color: Colors.grey.withOpacity(0.3),
                  margin: const EdgeInsets.only(top: 15),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 22),
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 40, right: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fullDate, style: const TextStyle(fontSize: 16, color: Colors.black87)),
                  const SizedBox(height: 4),
                  Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  // 这里应用了全局 MyFont 字体
                  Text(
                    entry.content,
                    maxLines: 4, // 首页只显示4行，点击进入详情看全部
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, color: Colors.black54, height: 1.6),
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
