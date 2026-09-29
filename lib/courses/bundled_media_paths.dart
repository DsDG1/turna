/// Rewrite authoring `media/…` refs into Flutter asset paths.
///
/// Builtin courses are seeded from `assets/courses/<dir>/`. Image and audio
/// widgets already understand `assets/…` paths, so the seeder rewrites the
/// known media fields before insert. Anything that is not a safe `media/`
/// ref — word ids, `anki://`, `turnapack://`, `..` — is returned unchanged.
String? rewriteBundledMediaRef(String? raw, String assetDir) {
  if (raw == null) return null;
  final normalized = raw.replaceAll('\\', '/').trim();
  if (!normalized.startsWith('media/')) return raw;
  final rest = normalized.substring('media/'.length);
  if (_unsafeRelative(rest)) return raw;
  final dir = assetDir.endsWith('/')
      ? assetDir.substring(0, assetDir.length - 1)
      : assetDir;
  return '$dir/media/$rest';
}

bool _unsafeRelative(String relative) {
  if (relative.isEmpty || relative.startsWith('/') || relative.contains(':')) {
    return true;
  }
  final parts = relative.split('/');
  return parts.any((part) => part.isEmpty || part == '.' || part == '..');
}

/// Walk a JSON tree and rewrite `audioAsset` / `imageAsset` and their lists.
dynamic rewriteBundledMediaTree(dynamic node, String assetDir) {
  if (node is Map) {
    final out = <String, dynamic>{};
    node.forEach((key, value) {
      final name = '$key';
      if ((name == 'audioAsset' || name == 'imageAsset') && value is String) {
        out[name] = rewriteBundledMediaRef(value, assetDir) ?? value;
      } else if ((name == 'audioAssets' || name == 'imageAssets') &&
          value is List) {
        out[name] = [
          for (final item in value)
            item is String
                ? (rewriteBundledMediaRef(item, assetDir) ?? item)
                : rewriteBundledMediaTree(item, assetDir),
        ];
      } else {
        out[name] = rewriteBundledMediaTree(value, assetDir);
      }
    });
    return out;
  }
  if (node is List) {
    return [for (final item in node) rewriteBundledMediaTree(item, assetDir)];
  }
  return node;
}
