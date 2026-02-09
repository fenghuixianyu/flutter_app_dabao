import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/ffmpeg_service.dart';

/// 视频剪切页面
class VideoCutPage extends StatefulWidget {
  const VideoCutPage({super.key});

  @override
  State<VideoCutPage> createState() => _VideoCutPageState();
}

class _VideoCutPageState extends State<VideoCutPage> {
  // 视频控制器
  VideoPlayerController? _controller;
  
  // 选中的视频文件路径
  String? _videoPath;
  String? _videoName;
  
  // 视频时长（秒）
  double _duration = 0;
  
  // 起止时间（秒）
  double _startTime = 0;
  double _endTime = 0;
  
  // 处理状态
  bool _isProcessing = false;
  String _statusMessage = '';
  
  // 输出文件路径
  String? _outputPath;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// 选择视频文件
  Future<void> _pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null) {
          await _loadVideo(file.path!, file.name);
        }
      }
    } catch (e) {
      _showError('选择文件失败: $e');
    }
  }

  /// 加载视频
  Future<void> _loadVideo(String path, String name) async {
    setState(() {
      _statusMessage = '正在加载视频...';
    });

    // 释放旧控制器
    await _controller?.dispose();
    
    // 创建新控制器
    _controller = VideoPlayerController.file(File(path));
    
    try {
      await _controller!.initialize();
      
      final duration = _controller!.value.duration.inMilliseconds / 1000.0;
      
      setState(() {
        _videoPath = path;
        _videoName = name;
        _duration = duration;
        _startTime = 0;
        _endTime = duration;
        _statusMessage = '';
        _outputPath = null;
      });
    } catch (e) {
      _showError('加载视频失败: $e');
    }
  }

  /// 执行剪切
  Future<void> _cutVideo() async {
    if (_videoPath == null) {
      _showError('请先选择视频文件');
      return;
    }
    
    if (_startTime >= _endTime) {
      _showError('起始时间必须小于结束时间');
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = '正在剪切视频...';
      _outputPath = null;
    });

    try {
      // 生成输出路径
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = _videoPath!.split('.').last;
      final outputPath = '${tempDir.path}/cut_$timestamp.$ext';
      
      // 执行剪切
      final result = await FFmpegService.cutVideo(
        inputPath: _videoPath!,
        outputPath: outputPath,
        startTime: FFmpegService.formatTime(_startTime),
        endTime: FFmpegService.formatTime(_endTime),
      );
      
      if (result != null) {
        setState(() {
          _outputPath = result;
          _statusMessage = '✅ 剪切完成！';
        });
        _showSuccess('视频剪切成功！');
      } else {
        _showError('剪切失败，请检查视频格式');
      }
    } catch (e) {
      _showError('剪切出错: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  /// 分享输出文件
  Future<void> _shareOutput() async {
    if (_outputPath == null) return;
    
    try {
      await Share.shareXFiles([XFile(_outputPath!)], text: '剪切后的视频');
    } catch (e) {
      _showError('分享失败: $e');
    }
  }

  /// 显示错误提示
  void _showError(String message) {
    setState(() {
      _statusMessage = '❌ $message';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// 显示成功提示
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('视频剪切'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 视频预览区
              _buildVideoPreview(colorScheme),
              
              const SizedBox(height: 20),
              
              // 时间选择区
              if (_controller != null && _controller!.value.isInitialized)
                _buildTimeSelector(colorScheme),
              
              const SizedBox(height: 20),
              
              // 状态显示
              if (_statusMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusMessage,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              
              const SizedBox(height: 20),
              
              // 操作按钮
              _buildActionButtons(colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建视频预览区
  Widget _buildVideoPreview(ColorScheme colorScheme) {
    return Card(
      child: InkWell(
        onTap: _isProcessing ? null : _pickVideo,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
          ),
          child: _controller != null && _controller!.value.isInitialized
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                      // 播放/暂停按钮
                      _buildPlayButton(colorScheme),
                      // 重新选择按钮
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton.filledTonal(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          onPressed: _pickVideo,
                          tooltip: '重新选择',
                        ),
                      ),
                      // 文件名
                      Positioned(
                        bottom: 8,
                        left: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _videoName ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.video_file_rounded,
                      size: 64,
                      color: colorScheme.primary.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '点击选择视频文件',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// 构建播放按钮
  Widget _buildPlayButton(ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_controller!.value.isPlaying) {
            _controller!.pause();
          } else {
            _controller!.play();
          }
        });
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Icon(
          _controller!.value.isPlaying
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          size: 40,
          color: Colors.white,
        ),
      ),
    );
  }

  /// 构建时间选择器
  Widget _buildTimeSelector(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择剪切范围',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            
            // 时间显示
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTimeDisplay('起始', _startTime, colorScheme),
                Icon(Icons.arrow_forward, color: colorScheme.primary),
                _buildTimeDisplay('结束', _endTime, colorScheme),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // 范围滑块
            RangeSlider(
              values: RangeValues(_startTime, _endTime),
              min: 0,
              max: _duration,
              divisions: (_duration * 10).round().clamp(1, 1000),
              labels: RangeLabels(
                FFmpegService.formatTime(_startTime),
                FFmpegService.formatTime(_endTime),
              ),
              onChanged: (values) {
                setState(() {
                  _startTime = values.start;
                  _endTime = values.end;
                });
                // 跳转到起始位置预览
                _controller?.seekTo(
                  Duration(milliseconds: (_startTime * 1000).round()),
                );
              },
            ),
            
            // 时长提示
            Center(
              child: Text(
                '片段时长: ${FFmpegService.formatTime(_endTime - _startTime)}',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建时间显示
  Widget _buildTimeDisplay(String label, double time, ColorScheme colorScheme) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            FFmpegService.formatTime(time),
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建操作按钮
  Widget _buildActionButtons(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 剪切按钮
        FilledButton.icon(
          onPressed: _isProcessing || _videoPath == null ? null : _cutVideo,
          icon: _isProcessing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onPrimary,
                  ),
                )
              : const Icon(Icons.content_cut_rounded),
          label: Text(_isProcessing ? '处理中...' : '开始剪切'),
        ),
        
        // 分享按钮
        if (_outputPath != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _shareOutput,
            icon: const Icon(Icons.share_rounded),
            label: const Text('分享/保存'),
          ),
        ],
      ],
    );
  }
}
