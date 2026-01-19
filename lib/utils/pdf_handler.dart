import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart'; // For some platform assumptions if needed
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'text_parser.dart';
import '../config/app_config.dart';

class PdfHandler {
  
  static Future<List<BookmarkNode>> readBookmarks(String path) async {
    final file = File(path);
    if (!file.existsSync()) throw Exception("文件不存在: $path");
    
    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    
    List<BookmarkNode> nodes = [];
    
    void parse(PdfBookmarkBase collection, int currentLevel) {
      for (int i = 0; i < collection.count; i++) {
        final item = collection[i];
        int page = 1;
        if (item.destination != null) {
          page = document.pages.indexOf(item.destination!.page) + 1;
        }
        nodes.add(BookmarkNode(title: item.title, pageNumber: page, level: currentLevel));
        if (item.count > 0) parse(item, currentLevel + 1);
      }
    }
    
    parse(document.bookmarks, 0);
    document.dispose();
    return nodes;
  }

  static Future<String> writeBookmarks(String sourcePath, List<BookmarkNode> nodes) async {
    final file = File(sourcePath);
    if (!file.existsSync()) throw Exception("源文件丢失");

    final bytes = await file.readAsBytes();
    final document = PdfDocument(inputBytes: bytes);
    
    document.bookmarks.clear();
    
    List<PdfBookmarkBase> parentStack = [document.bookmarks];
    
    for (var node in nodes) {
      while (parentStack.length > node.level + 1) {
        parentStack.removeLast();
      }
      final parent = parentStack.last;
      
      int pageIndex = node.pageNumber - 1;
      if (pageIndex < 0) pageIndex = 0;
      if (pageIndex >= document.pages.count) pageIndex = document.pages.count - 1;
      
      final newBm = parent.add(node.title);
      newBm.destination = PdfDestination(document.pages[pageIndex], const Offset(0, 0));
      
      if (parentStack.length <= node.level + 1) {
         parentStack.add(newBm);
      } else {
         parentStack[node.level + 1] = newBm;
      }
    }
    
    String filename = Uri.file(sourcePath).pathSegments.last;
    String nameWithoutExt = filename.toLowerCase().endsWith('.pdf') 
        ? filename.substring(0, filename.length - 4) 
        : filename;
    
    String adjacentPath = "${file.parent.path}/${nameWithoutExt}_new.pdf";
    String finalPath = adjacentPath;
    
    try {
      // Logic: If path contains 'cache', it means we are in sandbox and adjacent write is useless/invisible.
      // In this case, throw immediately to trigger fallback to Downloads.
      if (adjacentPath.contains('cache')) {
         throw FileSystemException("Cache path detected");
      }
      await File(adjacentPath).writeAsBytes(await document.save());
    } catch (e) {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (downloadDir.existsSync()) {
        final appDir = Directory("${downloadDir.path}/${AppConfig.appName}");
        if (!appDir.existsSync()) appDir.createSync(recursive: true);
        finalPath = "${appDir.path}/${nameWithoutExt}_new.pdf";
        await File(finalPath).writeAsBytes(await document.save());
      } else {
         rethrow;
      }
    }
    
    document.dispose();
    return finalPath;
  }
}
