/// Official-compatible Typed Answer HTML helpers. Dart does not parse templates.
class OfficialAnkiTypedAnswerHtml {
  OfficialAnkiTypedAnswerHtml._();

  static final _typeMarker = RegExp(r'\[\[type:[^\]]+\]\]');
  static const placeholder =
      '<span id="typeans-placeholder" class="typeans-ph"></span>';

  static String apply({
    required String html,
    String? comparisonHtml,
  }) {
    if (comparisonHtml != null && comparisonHtml.isNotEmpty) {
      return html.replaceAll(_typeMarker, comparisonHtml);
    }
    return html.replaceAll(_typeMarker, placeholder);
  }

  static bool hasFrontSideAnswerRule(String html) {
    return html.contains('<hr id=answer>') ||
        html.contains('<hr id="answer">') ||
        html.contains("<hr id='answer'>");
  }
}
