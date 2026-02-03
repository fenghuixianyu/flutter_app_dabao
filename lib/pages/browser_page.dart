import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xhs_downloader_app/models/xhs_note.dart';
import 'package:xhs_downloader_app/services/download_service.dart';
import 'package:dio/dio.dart' as import_dio; // Alias to avoid conflict if any

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36") // 1. 伪装成电脑
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => setState(() => _isLoading = true),
          onPageFinished: (url) => setState(() => _isLoading = false),
          // 2. 拦截 "打开App" 的跳转 (xhsdiscover://)
          onNavigationRequest: (request) {
            if (!request.url.startsWith('http')) {
              debugPrint('拦截跳转: ${request.url}'); 
              return NavigationDecision.prevent; // 阻止跳转
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.xiaohongshu.com/explore'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('小红书一张图'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              _controller.loadRequest(Uri.parse('https://www.xiaohongshu.com/explore'));
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "刷新页面",
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const LinearProgressIndicator(
              color: Color(0xFFFF2442),
              backgroundColor: Colors.transparent,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFF2442),
        onPressed: _parseAndDownload,
        child: const Icon(Icons.download, color: Colors.white),
      ),
    );
  }

  // --- Core Extraction Logic ---
  Future<void> _parseAndDownload() async {
    String debugLog = "=== Debug Info ===\n";
    try {
      _showSnack("正在分析页面...");

      // 1. Get Environment
      final String? currentUrl = await _controller.currentUrl();
      debugLog += "URL: $currentUrl\n";
      
      final String cookieStr = await _controller.runJavaScriptReturningResult('document.cookie') as String;
      // Strip outer quotes if present (standard webview behavior)
      final cleanCookie = cookieStr.startsWith('"') && cookieStr.endsWith('"') 
          ? cookieStr.substring(1, cookieStr.length - 1) 
          : cookieStr;
          
      debugLog += "Cookie Len: ${cleanCookie.length}\n";
      
      if (cleanCookie.length < 50) {
         debugLog += "⚠️ Cookie 过短，可能未登录或获取失败\n";
      }

      XHSNote? note;
      List<String> noteIds = [];

      // Strategy 0: Robust URL Regex Scan
      // Look for ANY 24-char hex string in the URL (typical XHS Note ID)
      if (currentUrl != null) {
          final RegExp noteIdRegex = RegExp(r'[a-f0-9]{24}');
          final matches = noteIdRegex.allMatches(currentUrl);
          
          if (matches.isNotEmpty) {
             debugLog += "Found ${matches.length} IDs in URL\n";
             for (final match in matches) {
                final id = match.group(0)!;
                debugLog += "Checking ID: $id... ";
                
                try {
                   note = await _fetchNoteDetail(id, cleanCookie);
                   if (note != null) {
                      debugLog += "Success!\n";
                      break; // Found it
                   } else {
                      debugLog += "Null Data\n";
                   }
                } catch (e) {
                   debugLog += "Error: $e\n";
                }
             }
          } else {
             debugLog += "No IDs found in URL\n";
          }
      }

      // If Strategy 0 worked, skip JS injection
      if (note != null && note.resources.isNotEmpty) {
         _showConfirmDialog(
           title: "发现 1 篇笔记 (API)",
           content: "标题: ${note.title}\n包含 ${note.resources.length} 个资源",
           onConfirm: () => _startDownload(note!),
         );
         return;
      }

      // Strategy 1: JS Injection (Fallback)
      debugLog += "\nTrying JS Injection...\n";
      final result = await _controller.runJavaScriptReturningResult('''
        (function() {
          try {
             if (window.__INITIAL_STATE__) return JSON.stringify(window.__INITIAL_STATE__);
             return null;
          } catch(e) {
            return "ERR:" + e.toString();
          }
        })();
      ''');

      final resultStr = result.toString();
      debugLog += "JS Result Len: ${resultStr.length}\n";

      if (resultStr != 'null' && resultStr != '{}' && !resultStr.startsWith('"ERR:')) {
          String jsonStr = resultStr;
          if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
            jsonStr = jsonStr.substring(1, jsonStr.length - 1);
            jsonStr = jsonStr.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
          }
          
          try {
             final Map<String, dynamic> state = jsonDecode(jsonStr);
             
             // Try parse note directly
             if (note == null) {
                note = XHSNote.fromJson(state);
                if (note != null) debugLog += "JS Note parsed: ${note.title}\n";
             }
             
             // Try parse user profile or feed list
             if (state['user'] != null && state['user']['notes'] != null) {
                 final notes = state['user']['notes'];
                 if (notes is List) {
                    noteIds.addAll(notes.map((e) => e['noteId'].toString()));
                 }
                 debugLog += "Found Profile Notes: ${notes.length}\n";
             }
             
             // Regex Fallback (Scan entire state for IDs)
             final rawStateStr = jsonEncode(state);
             final RegExp idRegex = RegExp(r'"noteId":"([a-f0-9]{24})"', caseSensitive: false);
             final ids = idRegex.allMatches(rawStateStr).map((m) => m.group(1)!).toSet().toList();
             if (ids.isNotEmpty) {
               noteIds.addAll(ids);
               debugLog += "Regex Scan Found: ${ids.length}\n";
             }
             
          } catch(e) {
             debugLog += "JSON Parse Error: $e\n";
          }
      } else {
          debugLog += "JS State is Null/Empty (SPA Navigation?)\n";
      }

      // Final Decision
      if (note != null && note!.resources.isNotEmpty) {
         _showConfirmDialog(
           title: "发现 1 篇笔记",
           content: "标题: ${note!.title}\n包含 ${note!.resources.length} 个资源",
           onConfirm: () => _startDownload(note!),
         );
      } else if (noteIds.isNotEmpty) {
        final uniqueIds = noteIds.toSet().toList();
        _showConfirmDialog(
           title: "发现合辑/列表",
           content: "检测到 ${uniqueIds.length} 篇笔记\n是否批量下载？(将后台解析)",
           onConfirm: () => _startBatchDownload(uniqueIds),
        );
      } else {
        // Only show debug dialog if absolutely nothing found
        debugLog += "\n=== Deep Inspection ===\n${StateDebug.lastLog}";
        _showErrorDialog(debugLog);
      }

    } catch (e) {
      debugLog += "\nCRITICAL ERROR: $e\nDeep: ${StateDebug.lastLog}";
      _showErrorDialog(debugLog);
    }
  }

  void _showErrorDialog(String log) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("未能提取数据"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("如果您已在帖子页面，请尝试刷新后重试。\n\n技术调试信息:", style: TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              Container(
                 width: double.maxFinite,
                 padding: const EdgeInsets.all(8),
                 color: Colors.grey[200],
                 child: SelectableText(log, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
              )
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("关闭")),
          FilledButton(onPressed: () { 
             Navigator.pop(ctx);
             _controller.reload();
          }, child: const Text("刷新页面")),
        ],
      ),
    );
  }

  void _showConfirmDialog({required String title, required String content, required VoidCallback onConfirm}) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("取消")),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text("开始"),
          ),
        ],
      ),
    );
  }

  // Single Download
  Future<void> _startDownload(XHSNote note) async {
    _showSnack("开始下载: ${note.title}");
    final urls = note.resources.map((e) => e.url).toList();
    final stats = await DownloadService.downloadAll(urls);
    _showSnack("完成! 成功:${stats['success']} 失败:${stats['fail']}");
  }

  // Batch Download Logic
  Future<void> _startBatchDownload(List<String> noteIds) async {
     _showSnack("正在后台解析 ${noteIds.length} 篇笔记...");
     
     // 1. Sync Cookies from WebView (via JS)
     // WebViewCookieManager does not support getCookies, use JS instead
     final String cookieStr = await _controller.runJavaScriptReturningResult('document.cookie') as String;
     // The result might be quoted "key=value...", strip quotes
     final cleanCookie = cookieStr.startsWith('"') ? cookieStr.substring(1, cookieStr.length-1) : cookieStr;
     
     // 2. Background Processing
     int success = 0;
     for (var i = 0; i < noteIds.length; i++) {
        final id = noteIds[i];
        
        // Update UI every few items? 
        // Showing simple snackbar progress for now
        if (i % 3 == 0) _showSnack("正在处理第 ${i+1}/${noteIds.length} 篇...");

        try {
           final note = await _fetchNoteDetail(id, cleanCookie);
           if (note != null) {
              final urls = note.resources.map((e) => e.url).toList();
              final stats = await DownloadService.downloadAll(urls);
              if (stats['success']! > 0) success++;
           }
        } catch (e) {
           print("Batch Error [$id]: $e");
        }
        
        // Anti-ban delay
        await Future.delayed(const Duration(milliseconds: 1500));
     }
     
     _showSnack("批量任务结束! 成功处理笔记: $success 篇");
  }

  // Fetch HTML and parse manually
  Future<XHSNote?> _fetchNoteDetail(String noteId, String cookie) async {
     try {
       final dio = import_dio.Dio(); 
       final uri = "https://www.xiaohongshu.com/explore/$noteId";
       
       final response = await dio.get(
          uri,
          options: import_dio.Options(
             headers: {
                "Cookie": cookie,
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
             }
          )
       );
       
       final html = response.data.toString();
       final match = RegExp(r'window\.__INITIAL_STATE__=(.*?)</script>').firstMatch(html);
       if (match != null) {
          String jsonStr = match.group(1)!;
          jsonStr = jsonStr.replaceAll("undefined", "null");
          final state = jsonDecode(jsonStr);
          
          // Debugging Structure
          if (state['note'] != null && state['note']['noteDetailMap'] != null) {
              final map = state['note']['noteDetailMap'];
              if (map is Map && map.isNotEmpty) {
                  final key = map.keys.first;
                  final detail = map[key];
                  StateDebug.lastLog = "Detail Keys for $key: ${detail.keys.toList()}";
                  
                  if (detail['imageList'] != null) {
                      StateDebug.lastLog += "\nImageList Len: ${(detail['imageList'] as List).length}";
                  } else {
                      StateDebug.lastLog += "\n⚠️ No imageList found!";
                  }
              }
          }
          
          return XHSNote.fromJson(state);
       }
     } catch (e) {
       print("Fetch Detail Error: $e");
       StateDebug.lastLog = "Fetch Exception: $e";
     }
     return null;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// Global static debug holder
class StateDebug {
  static String lastLog = "";
}
