import 'package:flutter/material.dart';

import '../core/first_aid_guidance.dart';
import '../core/theme.dart';

/// Shown on the Result screen ONLY when the just-submitted entry's
/// `risk_result.risk_level` is Red AND its `symptom_names` includes the
/// "Chest pain" hard-flag symptom (the same literal string
/// `app/services/rules.py`'s `HEART_FAILURE_RULES["hard_red_symptoms"]`
/// checks against) — the caller (`result_screen.dart`) decides when to
/// show this widget; it is wired in at the display layer, not inside the
/// rule engine, per the task's explicit instruction.
///
/// The contraindication checklist below must be actively confirmed
/// (all four boxes checked) before the aspirin-specific guidance is
/// revealed. Leaving any box unchecked — including "not sure" — keeps the
/// aspirin guidance suppressed and shows only the call-for-help fallback.
///
/// **PROTOTYPE — NOT clinically reviewed.** See
/// `lib/core/first_aid_guidance.dart`'s own doc comment and
/// `context/pre-deployment-checklist.md` before any non-demo use.
class ChestPainFirstAidPanel extends StatefulWidget {
  const ChestPainFirstAidPanel({super.key});

  @override
  State<ChestPainFirstAidPanel> createState() => _ChestPainFirstAidPanelState();
}

class _ChestPainFirstAidPanelState extends State<ChestPainFirstAidPanel> {
  static const _guidance = FirstAidGuidance.chestPain;
  final List<bool> _confirmed = List.filled(FirstAidGuidance.chestPain.checklistItems.length, false);

  bool get _allConfirmed => _confirmed.every((c) => c);

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: RnColors.riskRed, width: 2),
      ),
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_hospital, color: RnColors.riskRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _guidance.panelTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: RnColors.riskRed,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Instruction #1 — always visible, most prominent, shown
            // regardless of the checklist below.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: RnColors.riskRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _guidance.primaryInstruction,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _guidance.checklistPrompt,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.rnMuted(0.85)),
            ),
            const SizedBox(height: 4),
            ...List.generate(_guidance.checklistItems.length, (i) {
              return CheckboxListTile(
                value: _confirmed[i],
                onChanged: (v) => setState(() => _confirmed[i] = v ?? false),
                title: Text(_guidance.checklistItems[i], style: const TextStyle(fontSize: 14)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              );
            }),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _allConfirmed
                  ? Container(
                      key: const ValueKey('aspirin'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: RnColors.accent100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: RnColors.accent300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SECONDARY — ONLY IF SAFE',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.0,
                              fontWeight: FontWeight.w700,
                              color: RnColors.accentDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(_guidance.aspirinGuidance, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                        ],
                      ),
                    )
                  : Container(
                      key: const ValueKey('suppressed'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.rnMuted(0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _guidance.suppressedNote,
                        style: TextStyle(fontSize: 13.5, height: 1.4, color: context.rnMuted(0.85)),
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: context.rnMuted(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _guidance.disclaimer,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  color: context.rnMuted(0.9),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _guidance.citation,
              style: TextStyle(fontSize: 10.5, color: context.rnMuted(0.55)),
            ),
          ],
        ),
      ),
    );
  }
}
