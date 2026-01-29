// ========================================
// FFmpeg 服务 - 使用 ffmpeg_kit_flutter_minimal
// ========================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_flutter_minimal/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_minimal/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_minimal/return_code.dart';
import 'package:ffmpeg_kit_flutter_minimal/ffmpeg_session.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/time_parser.dart';

/// FFmpeg 服务 - 基于 FFmpegKit (JNI)
class FFmpegService {

  /// 检查 FFmpeg 是否可用 (FFmpegKit 总是内置可用)
  static Future<bool> isReady() async {
    // FFmpegKit 不需要初始化检查，但我们可以简单的验证一下
    return true; 
  }

  /// 分析视频元数据
  static Future<VideoMeta?> analyzeVideo(String path) async {
    try {
      // 使用 ffprobe 获取 JSON 格式元数据
      final cmd = '-v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate,codec_name,duration -of json "$path"';
      final session = await FFprobeKit.execute(cmd);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final output = await session.getOutput();
        if (output != null && output.isNotEmpty) {
          final json = jsonDecode(output);
          final streams = json['streams'] as List;
          if (streams.isNotEmpty) {
            final map = streams[0];
            
            // 解析帧率
            double fps = 0;
            final fpsRaw = map['r_frame_rate']?.toString() ?? '0';
            if (fpsRaw.contains('/')) {
              final parts = fpsRaw.split('/');
              final num = double.tryParse(parts[0]) ?? 0;
              final den = double.tryParse(parts[1]) ?? 1;
              fps = den > 0 ? num / den : 0;
            } else {
              fps = double.tryParse(fpsRaw) ?? 0;
            }

            return VideoMeta(
              path: path,
              codec: map['codec_name'] ?? 'unknown',
              width: int.tryParse(map['width'].toString()) ?? 0,
              height: int.tryParse(map['height'].toString()) ?? 0,
              fps: fps,
              duration: double.tryParse(map['duration'].toString()) ?? 0,
            );
          }
        }
      } else {
        final logs = await session.getLogsAsString();
        print('❌ analyzeVideo failed: $logs');
      }
      return null;
    } catch (e) {
      print('❌ analyzeVideo error: $e');
      return null;
    }
  }

  /// 无损剪切视频
  static Future<bool> cutVideo({
    required String input,
    required String output,
    required double startSeconds,
    required double endSeconds,
  }) async {
    try {
      final start = TimeParser.formatForFFmpeg(startSeconds);
      final end = TimeParser.formatForFFmpeg(endSeconds);
      
      // -avoid_negative_ts 1 确保时间戳正向
      // -c copy 无损模式
      final cmd = '-y -ss $start -to $end -i "$input" -c copy -avoid_negative_ts 1 "$output"';
      
      final session = await FFmpegKit.execute(cmd);
      final returnCode = await session.getReturnCode();
      
      if (ReturnCode.isSuccess(returnCode)) {
        return true;
      } else {
        final logs = await session.getLogsAsString();
        throw Exception("FFmpeg Failed: $logs");
      }
    } catch (e) {
      print('❌ cutVideo error: $e');
      throw Exception(e.toString());
    }
  }

  /// 无损拼接视频 (同规格)
  static Future<bool> stitchVideos({
    required List<String> inputs,
    required String output,
  }) async {
    try {
      // 1. 创建文件列表 List File
      final tempDir = await getTemporaryDirectory();
      final listFile = File('${tempDir.path}/input_list.txt');
      final content = inputs.map((e) => "file '$e'").join('\n');
      await listFile.writeAsString(content);

      // 2. 执行 concat 命令
      final cmd = '-y -f concat -safe 0 -i "${listFile.path}" -c copy "$output"';
      
      final session = await FFmpegKit.execute(cmd);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return true;
      } else {
        final logs = await session.getLogsAsString();
        throw Exception("FFmpeg Stitch Failed: $logs");
      }
    } catch (e) {
      print('❌ stitchVideos error: $e');
      throw Exception(e.toString());
    }
  }
}

/// 视频元数据
class VideoMeta {
  final String path;
  final String codec;
  final int width;
  final int height;
  final double fps;
  final double duration;
  
  String? groupLabel;
  int? groupColorIndex;
  
  VideoMeta({
    required this.path,
    required this.codec,
    required this.width,
    required this.height,
    required this.fps,
    required this.duration,
  });
  
  String get fingerprint => '${codec}_${width}x${height}_${fps.round()}';
  String get fileName => path.split('/').last;
  String get resolution => '${width}x$height';
  
  String formatDuration() => TimeParser.formatSeconds(duration);
}
