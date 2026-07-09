// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:url_launcher/url_launcher.dart';

class PatreonButton extends StatefulWidget {
  const PatreonButton({Key? key}) : super(key: key);

  @override
  State<PatreonButton> createState() => _PatreonButtonState();
}

class _PatreonButtonState extends State<PatreonButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () async {
        const url = 'https://www.patreon.com';
        try {
          final uri = Uri.parse(url);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not launch Patreon: $e')),
            );
          }
        }
      },
      icon: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 1.2).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: const Icon(
          Icons.favorite,
          color: Color(0xFFFF424D),
          size: 20,
        ),
      ),
    );
  }
}
