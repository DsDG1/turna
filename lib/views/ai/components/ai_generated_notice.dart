// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';

/// 显式标识：《人工智能生成合成内容标识办法》（2025-09-01 施行）要求
/// 生成合成内容在适当位置带**肉眼可见的文字提示**；华为应用市场把
/// 「应用内已添加内容显式标识截图」列为 AIGC 类应用上架必备材料。
///
/// 所以凡是展示模型输出的位置都必须带上这一层——它既是给用户看的提示，
/// 也是提审时截图取证的那一层。删除它等于让应用变成「未添加显式标识」。
///
/// 两种形态，按场景选：
/// * [AiGeneratedNotice] —— 贴在单条输出下方的一句角标，用于对话气泡、
///   解释卡片等「内容与标识同屏」的地方。
/// * [AiGeneratedBanner] —— 页面级说明，放在功能入口告知整页内容性质。
class AiGeneratedNotice extends StatelessWidget {
  const AiGeneratedNotice({
    super.key,
    this.margin = const EdgeInsets.only(top: 8),
    this.alignment = MainAxisAlignment.start,
  });

  final EdgeInsets margin;
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final tint = TurnaTheme.textHintColor(context);
    return Padding(
      padding: margin,
      child: Row(
        mainAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 12, color: tint),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              AppStrings.aiGeneratedBadge,
              style: TextStyle(fontSize: 11, color: tint, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

/// 复制模型输出到剪贴板时把显式标识一并带上。
///
/// 内容一旦离开应用就没人再替它标注，而《标识办法》第十条禁止删除、隐匿
/// 生成合成内容标识——用户粘贴到别处时标识应当还在。所有「复制」AI 输出
/// 的按钮都必须经过这里，不要直接 `Clipboard.setData(text: body)`。
String labelAiGenerated(String body) =>
    '$body\n\n——${AppStrings.aiGeneratedBadge}';

/// 页面级 AI 生成内容说明。用于 AI 功能入口（AI 中心、引导页、各对话页
/// 顶部），让用户在产生第一轮输出之前就知道内容性质。
class AiGeneratedBanner extends StatelessWidget {
  const AiGeneratedBanner({super.key, this.margin = EdgeInsets.zero});

  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final tint = TurnaTheme.textSecondaryColor(context);
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: TurnaTheme.softTint(context, TurnaTheme.primaryLight),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 14, color: tint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              AppStrings.aiGeneratedBannerText,
              style: TextStyle(fontSize: 12, color: tint, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
