import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设置页面
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _crfValue = 23;
  bool _showLog = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _crfValue = prefs.getInt('crf') ?? 23;
      _showLog = prefs.getBool('showLog') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('crf', _crfValue);
    await prefs.setBool('showLog', _showLog);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 质量设置
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('重编码质量 (CRF)', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _getCrfDescription(_crfValue),
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ),
                Slider(
                  value: _crfValue.toDouble(),
                  min: 18,
                  max: 28,
                  divisions: 10,
                  label: _crfValue.toString(),
                  onChanged: (v) => setState(() => _crfValue = v.round()),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('18 (高质量)', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      Text('28 (小体积)', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 调试设置
          Card(
            child: SwitchListTile(
              title: const Text('显示 FFmpeg 日志'),
              subtitle: const Text('调试时查看详细输出'),
              value: _showLog,
              onChanged: (v) => setState(() => _showLog = v),
            ),
          ),
          const SizedBox(height: 24),

          // 保存按钮
          FilledButton(
            onPressed: _saveSettings,
            child: const Text('保存设置'),
          ),
          const SizedBox(height: 32),

          // 关于
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('关于', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text('视频工坊 v1.0.0', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    '无损视频剪切与智能拼接工具\n'
                    '基于 FFmpeg 实现',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getCrfDescription(int crf) {
    if (crf <= 20) return '高质量模式 - 文件较大，画质接近无损';
    if (crf <= 24) return '标准模式 - 平衡画质与体积';
    return '压缩模式 - 文件较小，适合分享';
  }
}
