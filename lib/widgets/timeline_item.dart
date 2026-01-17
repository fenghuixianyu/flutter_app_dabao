import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/diary_model.dart';

class TimelineItem extends StatelessWidget {
  final DiaryEntry entry;
  const TimelineItem({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    // 👇👇👇 1. 加入这个缓存边界组件 👇👇👇
    return RepaintBoundary(
      child: _buildContent(context),
    );
  }

  // 把原来的构建逻辑抽离出来
  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final TextStyle? bodyStyle = theme.textTheme.bodyMedium;
    final TextStyle? titleStyle = theme.textTheme.titleLarge;
    final TextStyle? dateStyle = theme.textTheme.displayLarge;

    final Color mainTextColor = titleStyle?.color ?? Colors.black87;
    final Color dateColor = isDark ? Colors.white70 : const Color(0xFF444444);
    final Color lineColor = isDark ? Colors.white24 : Colors.black12;

    const double dateColumnWidth = 85.0;
    const double lineSectionWidth = 40.0;
    const double linePosition = dateColumnWidth + (lineSectionWidth / 2);

    return Stack(
      children: [
        Positioned(
          left: linePosition, 
          top: 24, 
          bottom: 0, 
          width: 1,  
          child: Container(color: lineColor),
        ),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧日期
            SizedBox(
              width: dateColumnWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const SizedBox(height: 10),
                  Text(
                    DateFormat('yyyy.MM').format(entry.date), 
                    style: TextStyle(fontSize: 13, color: dateColor, fontWeight: FontWeight.w600)
                  ),
                  Text(
                    DateFormat('dd').format(entry.date), 
                    style: dateStyle?.copyWith(color: mainTextColor) 
                  ),
                ],
              ),
            ),
            
            // 中间圆点
            SizedBox(
              width: lineSectionWidth,
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: theme.scaffoldBackgroundColor, 
                      border: Border.all(color: mainTextColor, width: 2), 
                      shape: BoxShape.circle
                    ),
                  ),
                ],
              ),
            ),
            
            // 右侧内容
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 40, right: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (entry.title.isNotEmpty)
                      Text(entry.title, style: titleStyle)
                    else
                      Text(DateFormat('yyyy年MM月dd日').format(entry.date), style: titleStyle?.copyWith(fontSize: (titleStyle.fontSize ?? 17) - 1)),
                    
                    const SizedBox(height: 4),
                    Text(DateFormat('HH:mm').format(entry.date), style: TextStyle(fontSize: 12, color: dateColor)),
                    
                    const SizedBox(height: 10),
                    Text(
                      entry.content,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: bodyStyle, 
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}