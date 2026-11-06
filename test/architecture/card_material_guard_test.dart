// 卡面材质守卫：把「一种材质只有一个出处」这条约定钉在源码上。
//
// 两条规则都来自实测踩坑，不是风格偏好：
//
// 1. 品牌渐变主卡（teal → sky）曾经在练习台与记忆卡入口各写一份，连投影的
//    alpha / blur / offset 都逐字相同。改色时改一处、漏一处，两个入口就对不上。
//    现在只有 `TurnaTheme.brandHeroDecoration`。
//
// 2. `BackdropFilter` 是一次全屏背景采样。ADR 0068 定的是「每页至多两张」，
//    实际只允许四处：底部胶囊导航、SnackBar、`GlassSurface.frost`、个人页
//    身份卡（它自己管理环与糊的叠放顺序，没有走 GlassSurface）。别的地方要
//    真模糊，先把 `GlassSurface(frost: true)` 用起来。
//
// 扫描的是源码文本（这两条都是「有没有内联这段字面量」的问题），生成文件与
// 注释行跳过。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 视图层里不允许再出现的内联品牌渐变。
final RegExp _inlineBrandGradient = RegExp(
  r'colors:\s*\[\s*TurnaTheme\.brandTeal\s*,\s*TurnaTheme\.brandSky\s*\]',
);

/// 允许出现 `BackdropFilter` 的文件（相对仓库根，正斜杠）。
const Set<String> _frostBudgets = {
  'lib/views/home/components/text_tab_bar.dart',
  'lib/views/widgets/turna_snack_bar.dart',
  'lib/views/widgets/glass_surface.dart',
  'lib/views/profile/widgets/account_app_bar.dart',
};

bool _isGenerated(String path) =>
    path.endsWith('.g.dart') ||
    path.endsWith('.gr.dart') ||
    path.endsWith('.freezed.dart') ||
    path.contains('/gen/');

/// 去掉整行注释，避免文档里的一句话被判成违规。
String _codeOnly(String source) => source.split('\n').where((line) {
      final trimmed = line.trimLeft();
      return !trimmed.startsWith('//') && !trimmed.startsWith('///');
    }).join('\n');

List<File> _viewSources() {
  final dir = Directory('lib/views');
  expect(dir.existsSync(), isTrue, reason: '必须在仓库根目录运行测试');
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !_isGenerated(f.path.replaceAll('\\', '/')))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

String _rel(File file) => file.path.replaceAll('\\', '/');

void main() {
  test('品牌渐变主卡只能来自 TurnaTheme.brandHeroDecoration', () {
    final offenders = <String>[];
    for (final file in _viewSources()) {
      if (_inlineBrandGradient.hasMatch(_codeOnly(file.readAsStringSync()))) {
        offenders.add(_rel(file));
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '这些文件内联了 teal→sky 品牌渐变：$offenders\n'
          '改用 TurnaTheme.brandHeroDecoration(context, borderRadius: …)，'
          '否则品牌色改一次要改 N 处。',
    );
  });

  test('BackdropFilter 只出现在预算内的四个文件', () {
    final offenders = <String>[];
    for (final file in _viewSources()) {
      final code = _codeOnly(file.readAsStringSync());
      if (!code.contains('BackdropFilter(')) continue;
      if (_frostBudgets.contains(_rel(file))) continue;
      offenders.add(_rel(file));
    }
    expect(
      offenders,
      isEmpty,
      reason: '这些文件新增了实时背景模糊：$offenders\n'
          '每处 BackdropFilter 都是一次全屏采样（ADR 0068）。要用真模糊请走 '
          'GlassSurface(frost: true)，并确认该页主体卡不超过两张。',
    );
  });
}
