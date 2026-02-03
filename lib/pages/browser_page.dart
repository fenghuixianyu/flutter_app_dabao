import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xhs_downloader_app/models/xhs_note.dart';
import 'package:xhs_downloader_app/services/download_service.dart';

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
      ..setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => setState(() => _isLoading = true),
          onPageFinished: (url) => setState(() => _isLoading = false),
          onNavigationRequest: (request) {
            if (!request.url.startsWith('http')) {
              debugPrint('拦截跳转: ${request.url}'); 
              return NavigationDecision.prevent;
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

  // =====================================================
  // 核心提取逻辑 (移植自 Python 版 web_album_downloader.py)
  // =====================================================
  Future<void> _parseAndDownload() async {
    _showSnack("正在提取页面数据...");
    
    // 核心: 在 WebView 内部执行 JS 脚本，直接读取 window.__INITIAL_STATE__
    // 这与 Python 版 page.evaluate() 原理完全一致
    final result = await _controller.runJavaScriptReturningResult(r'''
      (function() {
        try {
          // ===== 诊断日志 =====
          let debug = [];
          
          // ===== Helper: 获取最高画质视频 =====
          const get_best_video = (stream_obj) => {
            if (!stream_obj) return null;
            let candidates = [];
            const codecs = ['h264', 'h265', 'h266', 'av1'];
            for (const codec of codecs) {
              if (stream_obj[codec] && Array.isArray(stream_obj[codec])) {
                candidates = candidates.concat(stream_obj[codec]);
              }
            }
            if (!candidates.length) return null;
            candidates.sort((a, b) => (b.size || 0) - (a.size || 0));
            return candidates[0].masterUrl;
          };

          // ===== Helper: 清理视频URL =====
          const cleanVideo = (url) => {
            if (!url) return null;
            if (typeof url !== 'string') return null;
            let newUrl = url.replace(/sns-video-\w+\.xhscdn\.com/, 'sns-video-bd.xhscdn.com');
            return newUrl.split('?')[0];
          };

          // ===== 主逻辑: 提取 State =====
          const state = window.__INITIAL_STATE__;
          debug.push("State exists: " + !!state);
          if (!state) return JSON.stringify({error: "No __INITIAL_STATE__ found", debug: debug});
          
          debug.push("State keys: " + Object.keys(state).slice(0,10).join(", "));
          
          const noteObj = state.note;
          debug.push("note exists: " + !!noteObj);
          if (!noteObj) return JSON.stringify({error: "No state.note", debug: debug});
          
          debug.push("note keys: " + Object.keys(noteObj).join(", "));
          
          const map = noteObj.noteDetailMap || {};
          const raw = map._rawValue || map._value || map;
          debug.push("noteDetailMap keys: " + Object.keys(raw).join(", "));
          
          const id = Object.keys(raw)[0];
          if (!id) return JSON.stringify({error: "No noteId in noteDetailMap", debug: debug});
          debug.push("noteId: " + id);
          
          let info = raw[id];
          debug.push("info type: " + typeof info);
          debug.push("info keys (before unwrap): " + (info ? Object.keys(info).join(", ") : "null"));
          
          if (info?._rawValue) info = info._rawValue;
          
          // 关键: 解包嵌套的 note 对象 (新版 XHS 结构)
          if (info?.note) {
            debug.push("Found nested note object, unwrapping...");
            info = info.note;
          }
          if (info?._rawValue) info = info._rawValue;
          
          debug.push("info keys (after unwrap): " + (info ? Object.keys(info).join(", ") : "null"));

          // ===== 提取图片 =====
          const imageList = info?.imageList || info?.images_list || info?.images || [];
          debug.push("imageList length: " + imageList.length);
          
          const images = imageList.map(i => {
            const item = i._rawValue || i;
            
            // Live Photo 视频
            let liveUrl = null;
            if (item.livePhoto) {
              const stream = item.stream?._rawValue || item.stream;
              liveUrl = get_best_video(stream);
              if (!liveUrl) {
                const fid = item.livePhotoFileId || item.live_photo_file_id || item.fileId;
                if (fid) liveUrl = "http://sns-video-bd.xhscdn.com/stream/" + fid;
              }
              liveUrl = cleanVideo(liveUrl);
            }
            
            return { 
              url: item.urlDefault || item.url_default || item.url || '',
              traceId: item.traceId || item.fileId || '',
              liveVideoUrl: liveUrl
            };
          });
          
          debug.push("Extracted images: " + images.length);
          if (images.length > 0) {
            debug.push("First image url: " + (images[0].url || "EMPTY").substring(0, 50));
          }

          // ===== 提取视频 =====
          let vid = info?.video;
          if (vid?._rawValue) vid = vid._rawValue;
          debug.push("video exists: " + !!vid);
          
          let videoUrl = null;
          if (vid) {
            const consumer = vid.consumer?._rawValue || vid.consumer;
            if (consumer?.originVideoKey) {
              videoUrl = "https://sns-video-bd.xhscdn.com/" + consumer.originVideoKey;
            }
            if (!videoUrl) videoUrl = vid.masterUrl;
            if (!videoUrl) {
              const media = vid.media?._rawValue || vid.media;
              const stream = media?.stream?._rawValue || media?.stream;
              videoUrl = get_best_video(stream);
            }
            videoUrl = cleanVideo(videoUrl);
          }

          // ===== 提取标签 =====
          const tags = (info?.tagList || []).map(t => t.name).filter(Boolean);

          return JSON.stringify({
            noteId: id,
            title: info?.title || info?.displayTitle || 'Untitled',
            images: images,
            video: videoUrl,
            tags: tags,
            debug: debug
          });
          
        } catch(e) { 
          return JSON.stringify({error: e.toString()}); 
        }
      })();
    ''');
    
    // 解析 JS 返回结果
    String jsonStr = result.toString();
    
    // WebView 返回结果可能带引号包裹
    if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
      jsonStr = jsonStr.substring(1, jsonStr.length - 1);
      jsonStr = jsonStr.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
    }
    
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      if (data.containsKey('error')) {
        _showErrorDialog("提取失败: ${data['error']}\n\n请确保您已打开一个小红书帖子详情页。");
        return;
      }
      
      final title = data['title'] as String? ?? 'Untitled';
      final noteId = data['noteId'] as String? ?? '';
      final images = (data['images'] as List? ?? []).cast<Map<String, dynamic>>();
      final video = data['video'] as String?;
      
      // 收集所有下载 URL
      List<String> downloadUrls = [];
      
      // 1. 图片
      for (var img in images) {
        final url = img['url'] as String?;
        if (url != null && url.isNotEmpty) {
          // 转换为 CI 原图链接
          final traceId = img['traceId'] as String?;
          if (traceId != null && traceId.isNotEmpty) {
            downloadUrls.add("https://ci.xiaohongshu.com/$traceId?imageView2/2/w/format/png");
          } else {
            downloadUrls.add(url);
          }
        }
        
        // Live Photo 视频
        final liveUrl = img['liveVideoUrl'] as String?;
        if (liveUrl != null && liveUrl.isNotEmpty) {
          downloadUrls.add(liveUrl);
        }
      }
      
      // 2. 纯视频帖
      if (video != null && video.isNotEmpty) {
        downloadUrls.add(video);
      }
      
      if (downloadUrls.isEmpty) {
        // 显示诊断信息帮助调试
        final debugInfo = (data['debug'] as List?)?.join('\n') ?? 'No debug info';
        _showErrorDialog("未找到可下载的资源。\n\n诊断日志:\n$debugInfo");
        return;
      }
      
      // 显示确认对话框
      _showConfirmDialog(
        title: "发现 1 篇笔记",
        content: "标题: $title\n包含 ${downloadUrls.length} 个资源\n\n是否开始下载？",
        onConfirm: () async {
          _showSnack("开始下载 ${downloadUrls.length} 个文件...");
          final stats = await DownloadService.downloadAll(downloadUrls);
          _showSnack("完成! 成功:${stats['success']} 失败:${stats['fail']}");
        },
      );
      
    } catch (e) {
      _showErrorDialog("解析失败: $e\n\n原始数据:\n$jsonStr");
    }
  }

  void _showErrorDialog(String message) {
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
              const Text("如果您已在帖子页面，请尝试刷新后重试。", style: TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              Container(
                 width: double.maxFinite,
                 padding: const EdgeInsets.all(8),
                 color: Colors.grey[200],
                 child: SelectableText(message, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
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

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
