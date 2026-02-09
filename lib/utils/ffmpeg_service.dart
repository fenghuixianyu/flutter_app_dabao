import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:path_provider/path_provider.dart';

/// 进度回调类型
/// [progress] 0.0 ~ 1.0 表示进度百分比
typedef ProgressCallback = void Function(double progress);

/// FFmpeg 服务封装类
/// 提供无损视频剪切和合并功能
class FFmpegService {

  /// 无损剪切视频
  /// 
  /// [inputPath] 输入视频路径
  /// [outputPath] 输出视频路径
  /// [startTime] 起始时间（格式：HH:MM:SS 或秒数）
  /// [endTime] 结束时间（格式：HH:MM:SS 或秒数）
  /// [onProgress] 进度回调
  /// 
  /// 返回：成功返回输出文件路径，失败返回 null
  static Future<String?> cutVideo({
    required String inputPath,
    required String outputPath,
    required String startTime,
    required String endTime,
    ProgressCallback? onProgress,
  }) async {
    // 构造 FFmpeg 命令
    // -ss: 起始时间（放在 -i 前面可实现更快的 seek）
    // -to: 结束时间
    // -c copy: 不重新编码，直接拷贝码流（无损）
    // -map 0: 保留所有轨道（视频+音频+字幕）
    // -avoid_negative_ts make_zero: 修复时间戳问题
    final command = '-ss $startTime -to $endTime -i "$inputPath" '
        '-c copy -map 0 -avoid_negative_ts make_zero -y "$outputPath"';

    print('🔧 执行剪切命令: $command');

    // 执行命令
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      print('✅ 剪切成功: $outputPath');
      return outputPath;
    } else {
      final logs = await session.getAllLogsAsString();
      print('❌ 剪切失败: $logs');
      return null;
    }
  }

  /// 无损合并多个视频
  /// 
  /// [inputPaths] 输入视频路径列表（按顺序合并）
  /// [outputPath] 输出视频路径
  /// [onProgress] 进度回调
  /// 
  /// 注意：所有视频必须具有相同的编码参数（分辨率、编码器、音频采样率等）
  /// 
  /// 返回：成功返回输出文件路径，失败返回 null
  static Future<String?> mergeVideos({
    required List<String> inputPaths,
    required String outputPath,
    ProgressCallback? onProgress,
  }) async {
    if (inputPaths.isEmpty) {
      print('❌ 输入文件列表为空');
      return null;
    }

    if (inputPaths.length == 1) {
      // 只有一个文件时，直接复制
      await File(inputPaths.first).copy(outputPath);
      return outputPath;
    }

    // 创建临时的 list.txt 文件（FFmpeg concat demuxer 需要）
    final tempDir = await getTemporaryDirectory();
    final listFile = File('${tempDir.path}/concat_list.txt');
    
    // 写入文件列表
    // 格式：每行 file '/path/to/video.mp4'
    final listContent = inputPaths.map((path) => "file '$path'").join('\n');
    await listFile.writeAsString(listContent);
    
    print('📝 合并列表文件: ${listFile.path}');
    print('📋 内容:\n$listContent');

    // 构造 FFmpeg 命令
    // -f concat: 使用 concat demuxer
    // -safe 0: 允许绝对路径
    // -c copy: 不重新编码（无损）
    final command = '-f concat -safe 0 -i "${listFile.path}" '
        '-c copy -y "$outputPath"';

    print('🔧 执行合并命令: $command');

    // 执行命令
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    // 清理临时文件
    if (await listFile.exists()) {
      await listFile.delete();
    }

    if (ReturnCode.isSuccess(returnCode)) {
      print('✅ 合并成功: $outputPath');
      return outputPath;
    } else {
      final logs = await session.getAllLogsAsString();
      print('❌ 合并失败: $logs');
      return null;
    }
  }

  /// 获取视频时长（秒）
  /// 
  /// [videoPath] 视频文件路径
  /// 返回：视频时长（秒），失败返回 0
  static Future<double> getVideoDuration(String videoPath) async {
    // 使用 ffprobe 获取视频信息
    final command = '-v error -show_entries format=duration '
        '-of default=noprint_wrappers=1:nokey=1 "$videoPath"';
    
    final session = await FFmpegKit.execute('-i "$videoPath" 2>&1');
    final output = await session.getOutput();
    
    // 解析时长信息
    // 格式通常是: Duration: 00:01:30.50, ...
    final durationRegex = RegExp(r'Duration:\s*(\d{2}):(\d{2}):(\d{2}\.\d+)');
    final match = durationRegex.firstMatch(output ?? '');
    
    if (match != null) {
      final hours = int.parse(match.group(1)!);
      final minutes = int.parse(match.group(2)!);
      final seconds = double.parse(match.group(3)!);
      return hours * 3600 + minutes * 60 + seconds;
    }
    
    return 0;
  }

  /// 格式化时间（秒 -> HH:MM:SS）
  static String formatTime(double seconds) {
    final duration = Duration(milliseconds: (seconds * 1000).round());
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final secs = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$secs';
  }

  /// 解析时间字符串（HH:MM:SS -> 秒）
  static double parseTime(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length == 3) {
      final hours = int.tryParse(parts[0]) ?? 0;
      final minutes = int.tryParse(parts[1]) ?? 0;
      final seconds = double.tryParse(parts[2]) ?? 0;
      return hours * 3600 + minutes * 60 + seconds;
    }
    return 0;
  }

  /// 生成输出文件名
  /// 在原文件名后添加后缀
  static String generateOutputPath(String inputPath, String suffix) {
    final file = File(inputPath);
    final dir = file.parent.path;
    final name = file.uri.pathSegments.last;
    final dotIndex = name.lastIndexOf('.');
    
    if (dotIndex > 0) {
      final baseName = name.substring(0, dotIndex);
      final ext = name.substring(dotIndex);
      return '$dir/${baseName}_$suffix$ext';
    }
    return '$dir/${name}_$suffix';
  }
}
