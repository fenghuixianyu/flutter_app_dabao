import '../config/app_config.dart';

/// 书签节点模型
class BookmarkNode {
  String title;
  int pageNumber;
  int level; // 0-based depth
  
  BookmarkNode({required this.title, required this.pageNumber, required this.level});
}

/// 负责 文本 <-> 书签列表 的转换逻辑
class TextParser {
  
  /// 将书签列表转换为纯文本 (用于编辑器显示)
  /// 格式: [缩进]标题[Tab]页码
  static String bookmarksToText(List<BookmarkNode> nodes) {
    final buffer = StringBuffer();
    for (var node in nodes) {
      String indent = AppConfig.indentChar * node.level;
      // 确保标题中没有换行符
      String cleanTitle = node.title.replaceAll('\n', '').replaceAll('\r', '');
      buffer.writeln("$indent$cleanTitle${AppConfig.indentChar}${node.pageNumber}");
    }
    return buffer.toString();
  }

  /// 将纯文本解析为书签列表
  /// 容错处理: 忽略空行，无法解析的行保留原始内容作为标题(页码默认为0或1?)
  /// 或者标记为错误? 这里倾向于宽容解析。
  static List<BookmarkNode> textToBookmarks(String text) {
    List<BookmarkNode> nodes = [];
    final lines = text.split('\n');
    
    for (var line in lines) {
      if (line.trim().isEmpty) continue;
      
      // 1. 计算缩进 (层级)
      int level = 0;
      while (line.startsWith(AppConfig.indentChar, level)) {
        level++;
      }
      
      String content = line.trim();
      
      // 2. 提取标题和页码
      // 尝试匹配行尾的数字: "Title 123" or "Title\t123"
      // Regex: 任意字符 + 空白 + 数字 + 结尾
      final match = RegExp(r'^(.*)\s+(\d+)$').firstMatch(content);
      
      String title = content;
      int page = 1;
      
      if (match != null) {
        title = match.group(1)!.trim();
        page = int.parse(match.group(2)!);
      } else {
        // 如果没有页码，默认维持 1，或者标记?
        // PdgCntEditor 习惯: 如果没有页码，可能是目录结构?
      }
      
      nodes.add(BookmarkNode(title: title, pageNumber: page, level: level));
    }
    return nodes;
  }
}
