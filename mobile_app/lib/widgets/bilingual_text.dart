import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/language_provider.dart';

/// Renders one of two pre-written strings depending on the language
/// toggle — English or Roman Urdu, matching the prototype's own copy
/// (`RozNoor.dc.html`'s `rn-ur`/`rn-en` pairs) rather than inventing new
/// wording. See context/decisions-log.md for why this is a small fixed
/// dictionary per string rather than a full i18n package: this app has a
/// handful of headline strings, not a large translated surface.
class BilingualText extends StatelessWidget {
  const BilingualText({
    super.key,
    required this.en,
    required this.ur,
    this.style,
    this.textAlign,
  });

  final String en;
  final String ur;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isRomanUrdu;
    return Text(isUrdu ? ur : en, style: style, textAlign: textAlign);
  }
}
