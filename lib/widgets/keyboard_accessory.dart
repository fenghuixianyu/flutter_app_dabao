import 'package:flutter/material.dart';

/// 键盘上方的辅助工具栏
/// 提供 Tab 缩进、页码调整等快捷键
class KeyboardAccessory extends StatelessWidget {
  final VoidCallback onTab;
  final VoidCallback onUntab;
  final VoidCallback onPageInc;
  final VoidCallback onPageDec;
  final VoidCallback onPreview;
  final VoidCallback onHideKeyboard;

  const KeyboardAccessory({
    super.key,
    required this.onTab,
    required this.onUntab,
    required this.onPageInc,
    required this.onPageDec,
    required this.onPreview,
    required this.onHideKeyboard,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: Colors.grey[200],
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _buildBtn(Icons.keyboard_tab, "缩进", onTab),
          _buildBtn(Icons.west, "反缩进", onUntab),
          const VerticalDivider(width: 20, indent: 10, endIndent: 10),
          _buildBtn(Icons.add, "页码+1", onPageInc),
          _buildBtn(Icons.remove, "页码-1", onPageDec),
          const VerticalDivider(width: 20, indent: 10, endIndent: 10),
          _buildBtn(Icons.visibility, "预览", onPreview),
          _buildBtn(Icons.keyboard_hide, "收起", onHideKeyboard),
        ],
      ),
    );
  }

  Widget _buildBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.blue[700]),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}
