// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/core/enums.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/service/anki_import_service.dart';
import 'package:varnamala/views/theme.dart';
import 'package:varnamala/views/widgets/gems_display.dart';
import 'package:varnamala/l10n/app_localizations.dart';
import 'package:varnamala/views/widgets/loader.dart';

class StatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StatAppBar({Key? key}) : super(key: key);

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 60,
      leading: const Padding(
        padding: EdgeInsets.only(left: 8),
        child: LanguageSwitch(),
      ),
      leadingWidth: 64,
      title: const SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScoreCard(),
            Padding(padding: EdgeInsets.symmetric(horizontal: 4)),
            Streak(),
            Padding(padding: EdgeInsets.symmetric(horizontal: 4)),
            GemsDisplay(),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.auto_awesome,
            color: VarnamalaTheme.peacockTeal,
            size: 22,
          ),
          tooltip: AppLocalizations.of(context)!.homeAiCourseDesigner,
          onPressed: () => context.router.push(const AiWishChatRoute()),
        ),
      ],
    );
  }
}

/// Menu key for the "Import Anki" action.
const _kImportAnki = 'import_anki';

/// Menu key for the "New Language" action.
const _kNewLanguage = 'new_language';

class LanguageSwitch extends StatefulWidget {
  const LanguageSwitch({super.key});

  @override
  State<LanguageSwitch> createState() => _LanguageSwitchState();
}

class _LanguageSwitchState extends State<LanguageSwitch> {
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final current = context.select((LanguageProvider p) => p.selectedLanguage);

    return PopupMenuButton<String>(
      onSelected: _onMenuSelected,
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[];

        // Language selection items.
        for (final lang in TargetLanguage.values) {
          items.add(
            PopupMenuItem<String>(
              value: 'lang_${lang.name}',
              child: Row(
                children: [
                  Icon(
                    Icons.language_rounded,
                    size: 18,
                    color: lang == current
                        ? VarnamalaTheme.peacockTeal
                        : VarnamalaTheme.textHint,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    lang.displayName,
                    style: TextStyle(
                      fontWeight:
                          lang == current ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Divider before actions.
        items.add(const PopupMenuDivider());

        // Import Anki action.
        items.add(
          PopupMenuItem<String>(
            value: _kImportAnki,
            enabled: !_importing,
            child: Row(
              children: [
                Icon(
                  Icons.upload_file_rounded,
                  size: 18,
                  color: VarnamalaTheme.textHint,
                ),
                const SizedBox(width: 8),
                _importing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(AppLocalizations.of(context)!.homeFromAnki),
              ],
            ),
          ),
        );

        // New Language action.
        items.add(
          PopupMenuItem<String>(
            value: _kNewLanguage,
            child: Row(
              children: [
                Icon(
                  Icons.add_circle_outline_rounded,
                  size: 18,
                  color: VarnamalaTheme.textHint,
                ),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.homeNewCourse),
              ],
            ),
          ),
        );

        return items;
      },
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          Icons.language_rounded,
          size: 22,
          color: VarnamalaTheme.peacockTeal,
        ),
      ),
    );
  }

  void _onMenuSelected(String value) {
    if (value.startsWith('lang_')) {
      final langName = value.substring(5);
      final lang = TargetLanguage.values.firstWhere(
        (e) => e.name == langName,
        orElse: () => TargetLanguage.turkish,
      );
      context.read<LanguageProvider>().setLanguage(lang);
      unawaited(context.read<LanguageProvider>().cacheLanguage());
      return;
    }

    switch (value) {
      case _kImportAnki:
        _startAnkiImport();
        break;
      case _kNewLanguage:
        _showNewLanguageDialog();
        break;
    }
  }

  void _startAnkiImport() async {
    setState(() => _importing = true);
    try {
      final service = AnkiImportService();
      final count = await service.importFromCsv();
      if (!context.mounted) return;
      _showSnackBar(
        AppLocalizations.of(context)!.ankiImportSuccess(count),
        VarnamalaTheme.success,
      );
    } on ImportCancelledException {
      // User cancelled — no feedback needed.
    } on ImportEmptyException catch (e) {
      if (!context.mounted) return;
      _showSnackBar(e.toString(), VarnamalaTheme.error);
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(AppLocalizations.of(context)!.ankiImportError, VarnamalaTheme.error);
    } finally {
      if (context.mounted) setState(() => _importing = false);
    }
  }

  void _showSnackBar(String message, Color bgColor) {
    // Use addPostFrameCallback to avoid "deactivated widget" errors when
    // the SnackBar is shown immediately after a dialog/menu dismiss.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: bgColor,
          ),
        );
      } catch (_) {
        // ScaffoldMessenger lookup failed — widget tree is being torn down.
      }
    });
  }

  void _showNewLanguageDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.homeNewCourse),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.homeNewCourseComingSoon),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.homeNewCourseUseAi,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_),
            child: Text(AppLocalizations.of(context)!.dialogClose),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(_);
              context.router.push(const AiWishChatRoute());
            },
            child: Text(AppLocalizations.of(context)!.homeDesignWithAi),
          ),
        ],
      ),
    );
  }
}

class Streak extends StatelessWidget {
  const Streak({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: VarnamalaTheme.streakChipBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded,
              color: VarnamalaTheme.streakChipText(context), size: 20),
          const SizedBox(width: 4),
          StreamBuilder<int>(
            stream: context.read<GameProvider>().getUserStreakStream(),
            builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Loader();
              }
              if (snapshot.hasError) {
                return const Text('0');
              }
              return AnimatedCounter(
                target: snapshot.data ?? 0,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: VarnamalaTheme.streakChipText(context),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ScoreCard extends StatelessWidget {
  const ScoreCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: VarnamalaTheme.scoreChipBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stars_rounded, color: VarnamalaTheme.scoreChipText(context), size: 20),
          const SizedBox(width: 4),
          StreamBuilder<int>(
            stream: context.read<GameProvider>().getUserScoreStream(),
            builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Loader();
              }
              if (snapshot.hasError) {
                return const Text('0');
              }
              return AnimatedCounter(
                target: snapshot.data ?? 0,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: VarnamalaTheme.scoreChipText(context),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class AnimatedCounter extends StatefulWidget {
  final int target;
  final TextStyle style;

  const AnimatedCounter({
    Key? key,
    required this.target,
    required this.style,
  }) : super(key: key);

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter> {
  /// The value the counter was last displaying. The next tween animates from
  /// this value to the new target, so score/streak updates count up from the
  /// previous number instead of resetting to zero on every stream emit.
  late int _from = widget.target;

  @override
  void didUpdateWidget(covariant AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _from = oldWidget.target;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: TweenAnimationBuilder<int>(
        tween: IntTween(begin: _from, end: widget.target),
        duration: const Duration(milliseconds: 1000),
        builder: (context, value, child) {
          return Text(
            value.toString(),
            style: widget.style,
          );
        },
      ),
    );
  }
}