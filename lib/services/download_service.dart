import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class DownloadService {
  static final Dio _dio = Dio();

  /// 判断URL是否为视频
  static bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('video') || 
           lower.contains('.mp4') || 
           lower.contains('.mov') ||
           lower.contains('stream/') ||
           lower.contains('xhscdn.com/stream');
  }
  
  /// 判断是否为 CI 原图服务器
  static bool _isCiUrl(String url) {
    return url.contains('ci.xiaohongshu.com');
  }

  /// Batch download media to Gallery
  static Future<Map<String, int>> downloadAll(
      List<String> urls, {
      Function(int, int)? onProgress,
      }) async {

    // 1. Request Permission
    if (Platform.isAndroid) {
       await Permission.storage.request();
       await Permission.photos.request();
       await Permission.videos.request();
    }
    
    int success = 0;
    int fail = 0;

    for (int i = 0; i < urls.length; i++) {
      String url = urls[i];
      try {
        final bool isVideo = _isVideoUrl(url);
        final bool isCi = _isCiUrl(url);
        
        // 关键: CI 服务器必须 Referer 为空，否则返回 403
        // 文档: 【小红书】图片官方接口解析.md
        final Map<String, dynamic> headers = {
          "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
          "Accept": "*/*",
        };
        
        if (!isCi) {
          // 非 CI 服务器可以带 Referer
          headers["Referer"] = "https://www.xiaohongshu.com/";
        }
        // CI 服务器: 不带 Referer (为空)
        
        // 2. Download Byte Stream
        final response = await _dio.get(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: headers,
          ),
        );

        final bytes = Uint8List.fromList(response.data);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        
        dynamic result;
        
        if (isVideo) {
          // 3a. Save Video: 需要先保存到临时文件，再用 saveFile
          final tempDir = await getTemporaryDirectory();
          final tempPath = "${tempDir.path}/xhs_video_$timestamp.mp4";
          final file = File(tempPath);
          await file.writeAsBytes(bytes);
          
          result = await ImageGallerySaver.saveFile(
            tempPath,
            name: "xhs_video_$timestamp",
            isReturnPathOfIOS: true,
          );
          
          // 清理临时文件
          try { await file.delete(); } catch (_) {}
        } else {
          // 3b. Save Image
          result = await ImageGallerySaver.saveImage(
            bytes,
            quality: 100,
            name: "xhs_$timestamp",
          );
        }
        
        if (result != null && (result['isSuccess'] == true || result is String)) {
           success++;
           print("✅ Saved: ${isVideo ? 'VIDEO' : 'IMAGE'} (${bytes.length} bytes) CI:$isCi");
        } else {
           print("❌ Save Failed: $result");
           fail++;
        }

      } catch (e) {
        print("❌ Download Failed [$url]: $e");
        fail++;
      }

      if (onProgress != null) {
        onProgress(i + 1, urls.length);
      }
    }

    return {"success": success, "fail": fail};
  }
}
