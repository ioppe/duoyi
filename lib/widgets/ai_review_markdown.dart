import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../core/design_tokens.dart';

/// Read-only AI prose. The original Markdown remains available for history/copy.
class AiReviewMarkdown extends StatelessWidget {
  final String data;

  const AiReviewMarkdown({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final body = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontFamily: DesignTokens.fontFamily,
      fontWeight: DesignTokens.fontWeightRegular,
      fontSize: DesignTokens.fontSizeBody,
      color: cs.onSurface,
      height: 1.6,
    );
    TextStyle heading(double size) => body.copyWith(
      fontSize: size,
      fontWeight: DesignTokens.fontWeightStrong,
      height: 1.4,
    );
    return MarkdownBody(
      data: data,
      selectable: true,
      fitContent: false,
      inlineSyntaxes: [_AiStrongSyntax()],
      onTapLink: (_, href, _) => _openLink(href),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: body,
        a: body.copyWith(
          color: cs.primary,
          decoration: TextDecoration.underline,
        ),
        h1: heading(DesignTokens.fontSizeXxl),
        h2: heading(DesignTokens.fontSizeXl),
        h3: heading(DesignTokens.fontSizeLg),
        h4: heading(DesignTokens.fontSizeMd),
        h5: heading(DesignTokens.fontSizeSection),
        h6: heading(DesignTokens.fontSizeSection),
        h1Padding: const EdgeInsets.only(top: DesignTokens.spaceSm),
        h2Padding: const EdgeInsets.only(top: DesignTokens.spaceSm),
        h3Padding: const EdgeInsets.only(top: DesignTokens.spaceSm),
        strong: body.copyWith(fontWeight: DesignTokens.fontWeightStrong),
        listBullet: body,
        listIndent: DesignTokens.spaceXxl,
        blockSpacing: DesignTokens.spaceMd,
        blockquote: body.copyWith(color: cs.onSurfaceVariant),
        blockquotePadding: const EdgeInsets.all(DesignTokens.spaceMd),
        blockquoteDecoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          border: BorderDirectional(
            start: BorderSide(color: cs.primary, width: 2),
          ),
        ),
        code: body.copyWith(backgroundColor: cs.surfaceContainerHighest),
        codeblockPadding: const EdgeInsets.all(DesignTokens.spaceMd),
        codeblockDecoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: DesignTokens.borderRadiusSm,
        ),
        tableHead: body,
        tableBody: body,
        tableHeadAlign: TextAlign.start,
        tableBorder: TableBorder.all(color: cs.outlineVariant),
        tableCellsPadding: const EdgeInsets.all(DesignTokens.spaceSm),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
      ),
    );
  }

  Future<void> _openLink(String? href) async {
    final uri = Uri.tryParse(href ?? '');
    if (uri == null ||
        !const ['http', 'https', 'mailto'].contains(uri.scheme)) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      // Keep report reading available when the platform has no link handler.
    }
  }
}

/// Some model replies put spaces before closing **, which CommonMark leaves
/// literal. Parse that inline variant without rewriting source or code blocks.
class _AiStrongSyntax extends md.InlineSyntax {
  _AiStrongSyntax() : super(r'\*\*([^\n*]*\S)[ \t]+\*\*');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element(
        'strong',
        md.InlineParser(match[1]!.trim(), parser.document).parse(),
      ),
    );
    return true;
  }
}
