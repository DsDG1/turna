/// 搜索基元 ——「湿地雾光」内容阅读模式的搜索起点（P2 组件，P4 接线）。
///
/// 词典与卡牌浏览器各自手写了同一份 `Timer` 防抖（250ms），词典注释里
/// 自己承认「same 250ms pattern as the Anki card browser」。本组件把
/// 输入框与防抖收口为一个件：`onDebouncedChanged` 只在停顿后给一次终值，
/// 清除键立即回调（清空不该等防抖）。
///
/// 懒行（结果列表的 `ListView.builder` + 分页）由页面保留——那是各域的
/// 数据装配，不是输入件的事。
library;

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';

/// 搜索输入框（防抖内建）。
class TurnaSearchField extends StatefulWidget {
  const TurnaSearchField({
    required this.onDebouncedChanged,
    this.hint,
    this.onChanged,
    this.controller,
    this.debounceDelay = const Duration(milliseconds: 250),
    this.searching = false,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// 停止输入 [debounceDelay] 后回调一次的查询值。
  final ValueChanged<String> onDebouncedChanged;

  /// 每次按键的即时回调（高亮、统计等轻量跟随）；查询仍走防抖通道。
  final ValueChanged<String>? onChanged;

  /// 外部持有文本时给；缺省组件自管。
  final TextEditingController? controller;

  /// 占位提示文案。
  final String? hint;

  final Duration debounceDelay;

  /// 查询进行中：尾部显示小spinner，清除键暂避。
  final bool searching;

  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<TurnaSearchField> createState() => _TurnaSearchFieldState();
}

class _TurnaSearchFieldState extends State<TurnaSearchField> {
  TextEditingController? _ownedController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _adoptController();
  }

  @override
  void didUpdateWidget(covariant TurnaSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _adoptController();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ownedController?.dispose();
    super.dispose();
  }

  void _adoptController() {
    _ownedController?.dispose();
    _ownedController =
        widget.controller == null ? TextEditingController() : null;
  }

  TextEditingController get _effectiveController =>
      widget.controller ?? _ownedController!;

  void _handleChanged(String value) {
    widget.onChanged?.call(value);
    _debounce?.cancel();
    _debounce = Timer(widget.debounceDelay, () {
      widget.onDebouncedChanged(value);
    });
  }

  void _clear() {
    _debounce?.cancel();
    _effectiveController.clear();
    widget.onChanged?.call('');
    // 清空是明确意图，不等防抖。
    widget.onDebouncedChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final controller = _effectiveController;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          onChanged: _handleChanged,
          textInputAction: TextInputAction.search,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search_rounded),
            // 查询中给 spinner；有词给清除键；都没有就留空——右侧三种态
            // 共用同一个槽位，宽度不跳。
            suffixIcon: widget.searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (value.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: AppStrings.commonClose,
                        onPressed: _clear,
                      )),
            filled: true,
            fillColor: TurnaTheme.inputFillColor(context),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md + 2,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              borderSide: const BorderSide(
                color: TurnaTheme.brandTeal,
                width: 1.5,
              ),
            ),
          ),
        );
      },
    );
  }
}

@Preview(name: 'Search field · light', group: 'Wetland mist')
@Preview(
    name: 'Search field · dark',
    group: 'Wetland mist',
    brightness: Brightness.dark)
Widget turnaSearchFieldPreview() => const Padding(
      padding: EdgeInsets.all(AppSpacing.pageMargin),
      child: TurnaSearchField(
        hint: '搜索词条',
        onDebouncedChanged: _noop,
      ),
    );

void _noop(String value) {}
