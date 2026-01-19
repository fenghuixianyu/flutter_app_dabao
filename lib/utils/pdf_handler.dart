import 'dart:io';
import 'dart:ui'; // For Offset
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'text_parser.dart';
import '../config/app_config.dart';

/// 负责 PDF 文件的 I/O 操作 (使用 syncfusion_flutter_pdf)
class PdfHandler {
  
  /// 读取 PDF 中的书签，返回节点列表 (扁平化结构，含层级)
  static Future<List<BookmarkNode>> readBookmarks(String path) async {
    final file = File(path);
    if (!file.existsSync()) throw Exception("文件不存在: $path");
    
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    
    List<BookmarkNode> nodes = [];
    
    // 递归解析
    void parse(PdfBookmarkBase collection, int currentLevel) {
      for (int i = 0; i < collection.count; i++) {
        final item = collection[i];
        
        int page = 1;
        if (item.destination != null) {
          // 获取页码索引 (0-based) -> 转换为 1-based
          page = document.pages.indexOf(item.destination!.page) + 1;
        }
        
        nodes.add(BookmarkNode(title: item.title, pageNumber: page, level: currentLevel));
        
        // 递归子节点
        if (item.count > 0) {
          parse(item, currentLevel + 1);
        }
      }
    }
    
    parse(document.bookmarks, 0);
    document.dispose();
    return nodes;
  }

  /// 将书签列表写入 PDF
  /// [sourcePath]: 原文件路径
  /// [nodes]: 书签数据
  /// [saveAsPath]: 另存为路径 (如果为 null 则覆盖源文件 - 暂不建议直接覆盖，除非有备份)
  static Future<void> writeBookmarks(String sourcePath, List<BookmarkNode> nodes, {String? saveAsPath}) async {
    final file = File(sourcePath);
    if (!file.existsSync()) throw Exception("源文件不存在");
    
    // 1. 自动备份逻辑
    if (AppConfig.autoBackup) {
      final bakPath = sourcePath.replaceAll('.pdf', '_bak.pdf');
      if (!File(bakPath).existsSync()) {
         await file.copy(bakPath);
      }
    }
    
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    
    // 2. 清除现有书签
    document.bookmarks.clear();
    
    // 3. 重建书签树 (使用 Stack 追踪父节点)
    // Stack 存储每一级的父节点容器
    // Level 0 的父节点是 document.bookmarks
    List<PdfBookmarkBase> parentStack = [document.bookmarks];
    
    for (var node in nodes) {
      // 调整 Stack 以匹配当前 Level
      // 如果当前 Level 是 0，Stack 应该只有 [doc.bm] (长度1)
      // 如果当前 Level 是 1，Stack 应该有 [doc.bm, level0_bm] (长度2)
      
      // 如果 Stack 过深 (即 Level 变小了，回退了)，弹出
      while (parentStack.length > node.level + 1) {
        parentStack.removeLast();
      }
      
      // 如果 Stack 不够深 (即 Level 跳跃增加，例如 0 -> 2)，这是不合法的层级结构
      // 策略: 自动修正为当前最大深度的子节点
      // 这里不做强校验，直接取 Stack 最后作为父节点
      
      final parent = parentStack.last;
      
      // 添加书签
      int pageIndex = node.pageNumber - 1;
      // 边界检查
      if (pageIndex < 0) pageIndex = 0;
      if (pageIndex >= document.pages.count) pageIndex = document.pages.count - 1;
      
      final newBm = parent.add(node.title);
      newBm.destination = PdfDestination(document.pages[pageIndex], const Offset(0, 0));
      
      // 将当前节点推入 Stack，作为下一级可能的父节点
      // 注意: 这里不仅是推入，还需要确保下一次循环能对应上
      // 简单的逻辑: 如果下一个节点是 Level+1，它就会用这个 newBm 做父节点
      // 如果下一个节点是 Level，它会在下次循环开头 pop 掉这个 newBm，用同一个 parent
      
      // 只有当 parentStack 还没有对应当前 level 的子节点容器时... 
      // 不，应该是: 我们始终将当前节点作为 "Level+1" 的潜在父节点
      
      if (parentStack.length <= node.level + 1) {
         parentStack.add(newBm);
      } else {
         // 这里理论上不会执行，因为前面已经 pop 过了
         parentStack[node.level + 1] = newBm;
      }
    }
    
    // 4. 保存
    final targetPath = saveAsPath ?? sourcePath;
    await File(targetPath).writeAsBytes(await document.save());
    document.dispose();
  }
}
