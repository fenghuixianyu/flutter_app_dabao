import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Simple Model for UI manipulation
class BookmarkItem {
  String title;
  int pageNumber; // 1-based
  List<BookmarkItem> children;
  
  BookmarkItem({required this.title, required this.pageNumber, List<BookmarkItem>? children})
      : children = children ?? [];

  Map<String, dynamic> toJson() => {
    'title': title,
    'pageNumber': pageNumber,
    'children': children.map((e) => e.toJson()).toList(),
  };

  factory BookmarkItem.fromJson(Map<String, dynamic> json) {
    return BookmarkItem(
      title: json['title'],
      pageNumber: json['pageNumber'],
      children: (json['children'] as List).map((e) => BookmarkItem.fromJson(e)).toList(),
    );
  }
}

class PdfService {
  
  // --- Editor Methods ---

  /// Get bookmark tree from PDF
  static Future<List<BookmarkItem>> getBookmarks(String filePath) async {
    return await compute(_getBookmarksHandler, filePath);
  }

  /// Save bookmark tree to PDF
  static Future<void> saveBookmarks({
    required String filePath,
    required List<BookmarkItem> bookmarks,
    String? outputFilePath,
  }) async {
    await compute(_saveBookmarksHandler, {
      'filePath': filePath,
      'outputFilePath': outputFilePath ?? filePath, // Default to overwrite
      'bookmarks': bookmarks.map((e) => e.toJson()).toList(), // Pass as JSON for isolate safety
    });
  }

  // --- Existing Methods (Auto/Tools) ---

  static Future<Map<String, dynamic>> runAutoBookmark({
    required List<String> filePaths,
    required String outputDir,
    required Map<String, dynamic> config,
  }) async {
    return await compute(_autoBookmarkHandler, {
      'files': filePaths,
      'outputDir': outputDir,
      'config': config,
    });
  }

  static Future<Map<String, dynamic>> addBookmarks({
    required List<String> filePaths,
    required String outputDir,
    required int offset,
  }) async {
    return await compute(_addBookmarksHandler, {
      'files': filePaths,
      'outputDir': outputDir,
      'offset': offset,
    });
  }

  static Future<Map<String, dynamic>> extractBookmarks({
    required List<String> filePaths,
    required String outputDir,
  }) async {
    return await compute(_extractBookmarksHandler, {
      'files': filePaths,
      'outputDir': outputDir,
    });
  }
}

// --- Isolate Handlers ---

Future<List<BookmarkItem>> _getBookmarksHandler(String filePath) async {
  final file = File(filePath);
  final bytes = file.readAsBytesSync();
  final document = PdfDocument(inputBytes: bytes);
  
  List<BookmarkItem> parse(PdfBookmarkBase collection) {
    List<BookmarkItem> list = [];
    for (int i = 0; i < collection.count; i++) {
      final b = collection[i];
      int page = 1;
      if (b.destination != null) {
        // Find page index
        page = document.pages.indexOf(b.destination!.page) + 1;
      }
      list.add(BookmarkItem(
        title: b.title,
        pageNumber: page,
        children: parse(b), // Recursive
      ));
    }
    return list;
  }

  final result = parse(document.bookmarks);
  document.dispose();
  return result;
}

Future<void> _saveBookmarksHandler(Map<String, dynamic> args) async {
  final String filePath = args['filePath'];
  final String outputFilePath = args['outputFilePath'];
  final List<BookmarkItem> items = (args['bookmarks'] as List)
      .map((e) => BookmarkItem.fromJson(e))
      .toList();

  final file = File(filePath);
  final bytes = file.readAsBytesSync();
  final document = PdfDocument(inputBytes: bytes);

  // Clear existing
  document.bookmarks.clear();

  // Re-add
  void add(BookmarkItem item, PdfBookmarkBase parent) {
    // Determine page object
    int pageIndex = item.pageNumber - 1;
    if (pageIndex < 0) pageIndex = 0;
    if (pageIndex >= document.pages.count) pageIndex = document.pages.count - 1;
    
    // Add to parent
    PdfBookmark b = parent.add(item.title);
    b.destination = PdfDestination(document.pages[pageIndex], const Offset(0, 0));
    // Color/Style can be added here if we expand model
    
    for (var child in item.children) {
      add(child, b);
    }
  }

  for (var item in items) {
    add(item, document.bookmarks);
  }

  File(outputFilePath).writeAsBytesSync(await document.save());
  document.dispose();
}

Future<Map<String, dynamic>> _autoBookmarkHandler(Map<String, dynamic> args) async {
    // ... (Keep existing implementation logic, just ensure imports match)
    // implementation details omitted for brevity, will copy from previous step if needed or just keep structure
    // actually, I must provide full content to overwrite.
  try {
    final List<String> files = args['files'];
    final String outputDir = args['outputDir'];
    final Map<String, dynamic> config = args['config'];
    
    final StringBuffer logs = StringBuffer();
    logs.writeln("开始处理 ${files.length} 个文件...");

    // Pre-compile Regex
    RegExp? regexL1;
    if (config['level1']?['regex'] != null) {
      regexL1 = RegExp(config['level1']['regex']);
    }

    final dir = Directory(outputDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    for (var path in files) {
      final file = File(path);
      final filename = file.uri.pathSegments.last;
      logs.writeln("处理中: $filename");

      try {
        final List<int> bytes = file.readAsBytesSync();
        final PdfDocument document = PdfDocument(inputBytes: bytes);
        final PdfTextExtractor extractor = PdfTextExtractor(document);

        document.bookmarks.clear();
        int addedCount = 0;
        double fontSizeThreshold = (config['level1']?['font_size'] ?? 0).toDouble();

        for (int i = 0; i < document.pages.count; i++) {
          final List<TextLine> lines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
          
          for (var line in lines) {
            final String text = line.text.trim();
            if (text.isEmpty) continue;

            if (regexL1 != null && regexL1.hasMatch(text)) {
               if (fontSizeThreshold > 0 && line.bounds.height < fontSizeThreshold) {
                 continue;
               }

               final PdfBookmark bookmark = document.bookmarks.add(text);
               bookmark.destination = PdfDestination(document.pages[i], Offset(line.bounds.left, line.bounds.top));
               addedCount++;
            }
          }
        }
        
        logs.writeln("  已添加 $addedCount 个书签");

        final savePath = "$outputDir/${filename}"; // Overwrite original if in same folder logic is handled by caller? 
        // User asked for "outputDir". Logic suggests safe save usually.
        // Let's use _bk suffix to be safe unless overwrite requested.
        // Markdown logic said "_bk".
        final safeSavePath = "$outputDir/${filename.replaceAll('.pdf', '')}_bk.pdf";
        
        File(safeSavePath).writeAsBytesSync(await document.save());
        document.dispose();
        
      } catch (e) {
        logs.writeln("  错误: $e");
      }
    }
    return {'success': true, 'logs': logs.toString()};
  } catch (e) {
    return {'success': false, 'logs': '系统错误: $e'};
  }
}

Future<Map<String, dynamic>> _addBookmarksHandler(Map<String, dynamic> args) async {
  try {
    final List<String> files = args['files'];
    final String outputDir = args['outputDir'];
    final int offset = args['offset'];
    
    final StringBuffer logs = StringBuffer();
    final dir = Directory(outputDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    for (var path in files) {
      final file = File(path);
      final filename = file.uri.pathSegments.last;
      final txtPath = path.replaceAll('.pdf', '.txt');
      
      if (!File(txtPath).existsSync()) {
        logs.writeln("跳过 $filename (未找到同名 .txt 文件)");
        continue;
      }
      
      logs.writeln("正在处理: $filename");
      
      try {
        final List<int> bytes = file.readAsBytesSync();
        final PdfDocument document = PdfDocument(inputBytes: bytes);
        document.bookmarks.clear();
        
        final lines = File(txtPath).readAsLinesSync();
        
        for (var line in lines) {
           if (line.trim().isEmpty) continue;
           final match = RegExp(r'(.*)\s+(\d+)$').firstMatch(line);
           if (match != null) {
              String title = match.group(1)!.trim();
              int page = int.parse(match.group(2)!) + offset;
              if (page < 1) page = 1;
              if (page > document.pages.count) page = document.pages.count;

              final PdfBookmark bmp = document.bookmarks.add(title);
              bmp.destination = PdfDestination(document.pages[page - 1], const Offset(0, 0));
           }
        }
        
        final savePath = "$outputDir/${filename}";
        File(savePath).writeAsBytesSync(await document.save());
        document.dispose();
        logs.writeln("  已保存");
      
      } catch (e) {
        logs.writeln("  错误: $e");
      }
    }
    return {'success': true, 'logs': logs.toString()};
  } catch (e) {
    return {'success': false, 'logs': '系统错误: $e'};
  }
}

Future<Map<String, dynamic>> _extractBookmarksHandler(Map<String, dynamic> args) async {
  try {
    final List<String> files = args['files'];
    final String outputDir = args['outputDir'];
    
    final StringBuffer logs = StringBuffer();
    final dir = Directory(outputDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    for (var path in files) {
      final file = File(path);
      final filename = file.uri.pathSegments.last;
      logs.writeln("正在提取: $filename");
      
      try {
        final List<int> bytes = file.readAsBytesSync();
        final PdfDocument document = PdfDocument(inputBytes: bytes);
        final StringBuffer txtContent = StringBuffer();
        
        void parseBookmarks(PdfBookmarkBase collection, int depth) {
           for (int i=0; i<collection.count; i++) {
              PdfBookmark b = collection[i];
              String indent = '\t' * depth;
              int pageIndex = -1;
              if (b.destination != null) {
                pageIndex = document.pages.indexOf(b.destination!.page);
              }
              txtContent.writeln("$indent${b.title}\t${pageIndex + 1}");
              if (b.count > 0) parseBookmarks(b, depth + 1);
           }
        }
        
        parseBookmarks(document.bookmarks, 0);
        
        final txtName = filename.replaceAll('.pdf', '.txt');
        // Save to PDF source dir usually requested, but here we honor outputDir
        File("$outputDir/$txtName").writeAsStringSync(txtContent.toString());
        document.dispose();
        logs.writeln("  已导出: $txtName");
        
      } catch (e) {
        logs.writeln("  错误: $e");
      }
    }
    return {'success': true, 'logs': logs.toString()};
  } catch (e) {
    return {'success': false, 'logs': '系统错误: $e'};
  }
}
