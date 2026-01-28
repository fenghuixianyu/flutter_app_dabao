import 'dart:async';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/statistics.dart';
import 'dart:convert';
import 'dart:io';

/// FFmpeg 任务执行服务
/// 
/// 核心功能：
/// 1. 无损剪切视频 (使用 -c copy)
/// 2. 多片段合并
/// 3. 同组视频无损拼接
/// 4. 异组视频智能重编码拼接
class FFmpegService {
  /// 进度回调
  final _progressController = StreamController<TaskProgress>.broadcast();
  Stream<TaskProgress> get progressStream => _progressController.stream;

  /// 分析视频，获取元数据
  Future<VideoMeta?> analyzeVideo(String path) async {
    try {
      final session = await FFprobeKit.execute(
        '-v error -select_streams v:0 -show_entries '
        'stream=codec_name,width,height,r_frame_rate,bit_rate:format=duration,size '
        '-of json "$path"'
      );

      final output = await session.getOutput();
      if (output == null || output.isEmpty) return null;

      final json = jsonDecode(output);
      final streams = json['streams'] as List?;
      final format = json['format'] as Map<String, dynamic>?;

      if (streams == null || streams.isEmpty) return null;
      final stream = streams[0] as Map<String, dynamic>;

      // 解析帧率
      double fps = 0;
      final fpsRaw = stream['r_frame_rate'] as String?;
      if (fpsRaw != null && fpsRaw.contains('/')) {
        final parts = fpsRaw.split('/');
        final num = double.tryParse(parts[0]) ?? 0;
        final den = double.tryParse(parts[1]) ?? 1;
        fps = den > 0 ? num / den : 0;
      }

      return VideoMeta(
        path: path,
        codec: stream['codec_name'] ?? 'unknown',
        width: stream['width'] ?? 0,
        height: stream['height'] ?? 0,
        fps: fps,
        duration: double.tryParse(format?['duration'] ?? '0') ?? 0,
        fileSize: int.tryParse(format?['size'] ?? '0') ?? 0,
      );
    } catch (e) {
      print('❌ analyzeVideo error: $e');
      return null;
    }
  }

  /// 无损剪切单个片段
  Future<bool> cutVideo({
    required String inputPath,
    required String outputPath,
    required double startSeconds,
    required double endSeconds,
  }) async {
    try {
      _emitProgress('准备剪切', 0, '构建命令...');

      final startTime = _formatTime(startSeconds);
      final endTime = _formatTime(endSeconds);

      // 核心命令：-c copy 实现无损复制
      final command = '-y '
          '-ss $startTime '
          '-to $endTime '
          '-i "$inputPath" '
          '-c copy '
          '-avoid_negative_ts 1 '
          '-map_metadata 0 '
          '"$outputPath"';

      print('🔨 FFmpeg: ffmpeg $command');

      final session = await FFmpegKit.executeAsync(
        command,
        (session) async {
          final code = await session.getReturnCode();
          if (ReturnCode.isSuccess(code)) {
            _emitProgress('剪切完成', 100, '成功');
          }
        },
        null,
        (stats) => _updateProgress(stats, endSeconds - startSeconds),
      );

      final code = await session.getReturnCode();
      return ReturnCode.isSuccess(code);
    } catch (e) {
      _emitProgress('错误', 0, '$e');
      return false;
    }
  }

  /// 无损拼接同组视频 (concat demuxer)
  Future<bool> stitchSameGroup({
    required List<String> inputPaths,
    required String outputPath,
  }) async {
    try {
      _emitProgress('准备拼接', 0, '同组无损模式');

      // 创建 concat 列表文件
      final listPath = '${Directory.systemTemp.path}/concat_list.txt';
      final listFile = File(listPath);
      final buffer = StringBuffer();
      for (final path in inputPaths) {
        final safePath = path.replaceAll("'", "'\\''");
        buffer.writeln("file '$safePath'");
      }
      listFile.writeAsStringSync(buffer.toString());

      final command = '-y '
          '-f concat '
          '-safe 0 '
          '-i "$listPath" '
          '-c copy '
          '"$outputPath"';

      print('🔨 FFmpeg: ffmpeg $command');

      final session = await FFmpegKit.execute(command);
      
      // 清理临时文件
      try { listFile.deleteSync(); } catch (_) {}

      final code = await session.getReturnCode();
      if (ReturnCode.isSuccess(code)) {
        _emitProgress('拼接完成', 100, '成功');
      }
      return ReturnCode.isSuccess(code);
    } catch (e) {
      _emitProgress('错误', 0, '$e');
      return false;
    }
  }

  /// 智能重编码拼接异组视频
  Future<bool> stitchDifferentGroup({
    required List<VideoMeta> videos,
    required String outputPath,
    int crf = 23,
  }) async {
    try {
      _emitProgress('准备转码', 0, '异组重编码模式');

      // 计算目标分辨率 (取最大值)
      int maxW = 0, maxH = 0;
      for (final v in videos) {
        if (v.width > maxW) maxW = v.width;
        if (v.height > maxH) maxH = v.height;
      }

      print('🎯 目标: ${maxW}x$maxH | CRF $crf');

      // 构建滤镜链
      String inputs = '';
      String filter = '';
      for (int i = 0; i < videos.length; i++) {
        inputs += '-i "${videos[i].path}" ';
        filter += '[$i:v]scale=$maxW:$maxH:force_original_aspect_ratio=decrease,'
            'pad=$maxW:$maxH:(ow-iw)/2:(oh-ih)/2,setsar=1[v$i];';
        filter += '[$i:a]aformat=sample_rates=44100:channel_layouts=stereo[a$i];';
      }

      String concat = '';
      for (int i = 0; i < videos.length; i++) {
        concat += '[v$i][a$i]';
      }
      filter += '${concat}concat=n=${videos.length}:v=1:a=1[outv][outa]';

      final command = '-y $inputs'
          '-filter_complex "$filter" '
          '-map "[outv]" -map "[outa]" '
          '-c:v libx264 -crf $crf -preset veryfast '
          '-c:a aac -b:a 128k '
          '"$outputPath"';

      print('🔨 FFmpeg: ffmpeg $command');

      final session = await FFmpegKit.executeAsync(
        command,
        (session) async {
          final code = await session.getReturnCode();
          if (ReturnCode.isSuccess(code)) {
            _emitProgress('转码完成', 100, '成功');
          }
        },
      );

      final code = await session.getReturnCode();
      return ReturnCode.isSuccess(code);
    } catch (e) {
      _emitProgress('错误', 0, '$e');
      return false;
    }
  }

  // ========== 私有方法 ==========
  
  String _formatTime(double seconds) {
    final h = (seconds / 3600).floor();
    final m = ((seconds % 3600) / 60).floor();
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toStringAsFixed(3).padLeft(6, '0')}';
  }

  void _updateProgress(Statistics stats, double duration) {
    final time = stats.getTime() / 1000;
    if (duration > 0) {
      final pct = ((time / duration) * 100).clamp(0, 99).toInt();
      _emitProgress('处理中', pct, '${time.toStringAsFixed(1)}s / ${duration.toStringAsFixed(1)}s');
    }
  }

  void _emitProgress(String phase, int pct, String msg) {
    if (!_progressController.isClosed) {
      _progressController.add(TaskProgress(phase: phase, percentage: pct, message: msg));
    }
  }

  void dispose() {
    _progressController.close();
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
  final int fileSize;
  
  String? groupLabel;
  int? groupColorIndex;

  VideoMeta({
    required this.path,
    required this.codec,
    required this.width,
    required this.height,
    required this.fps,
    required this.duration,
    required this.fileSize,
  });

  /// 视频指纹 (用于分组)
  String get fingerprint => '${codec}_${width}x${height}_${fps.round()}';
  
  String get fileName => path.split('/').last;
  
  String get resolution => '${width}x$height';
  
  String get fileSizeStr {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 任务进度
class TaskProgress {
  final String phase;
  final int percentage;
  final String message;
  
  TaskProgress({required this.phase, required this.percentage, required this.message});
}
