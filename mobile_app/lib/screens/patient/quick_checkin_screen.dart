import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../state/patient_data_provider.dart';
import '../../widgets/bilingual_text.dart';
import 'result_screen.dart';

/// Quick Check-in — POST /entries with entry_type=quick + the 1-5 slider
/// values + medicine_status + symptom checklist (per the task spec).
///
/// Sleep is implemented as an hours field (0-24), not a sixth 1-5 slider —
/// a deliberate deviation from the prototype mockup, which draws Sleep
/// visually as one of five identical 1-5 sliders. That mockup predates the
/// confirmed backend scale (`entries.sleep_value` is hours, sourced from
/// the mobile field-requirements doc — see context/decisions-log.md,
/// 2026-08-24). Energy/Mood/Appetite/Mobility stay 1-5 sliders, matching
/// both the prototype and app/schemas/entry.py's confirmed bounds.
class QuickCheckinScreen extends StatefulWidget {
  const QuickCheckinScreen({super.key});

  @override
  State<QuickCheckinScreen> createState() => _QuickCheckinScreenState();
}

class _QuickCheckinScreenState extends State<QuickCheckinScreen> {
  double _sleep = 7;
  double _energy = 3;
  double _mood = 3;
  double _appetite = 3;
  double _mobility = 3;
  double? _weight;
  int? _systolic;
  int? _diastolic;
  int? _bloodSugar;
  String _medicine = 'taken';
  final _weightCtrl = TextEditingController();
  final _systolicCtrl = TextEditingController();
  final _diastolicCtrl = TextEditingController();
  final _bloodSugarCtrl = TextEditingController();
  final Set<int> _selectedSymptomIds = {};
  bool _submitting = false;

  @override
  void dispose() {
    _weightCtrl.dispose();
    _systolicCtrl.dispose();
    _diastolicCtrl.dispose();
    _bloodSugarCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final entry = await context.read<PatientDataProvider>().submitEntry(
            entryType: 'quick',
            sleepValue: _sleep,
            energyValue: _energy,
            moodValue: _mood,
            appetiteValue: _appetite,
            mobilityValue: _mobility,
            weightValue: _weight,
            systolicBp: _systolic,
            diastolicBp: _diastolic,
            bloodSugarMgDl: _bloodSugar,
            medicineStatus: _medicine,
            symptomIds: _selectedSymptomIds.toList(),
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResultScreen(entry: entry)),
      );
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final checklist = context.watch<PatientDataProvider>().symptomChecklist;

    return Scaffold(
      appBar: AppBar(title: const Text("Today's check-in")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const BilingualText(
              en: "Today's quick check-in",
              ur: 'Aaj ka roz-marra',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              "Nothing here is a test — move each line to whatever feels true today.",
              style: TextStyle(color: context.rnMuted(0.65)),
            ),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _HoursField(
                      label: 'Sleep last night',
                      value: _sleep,
                      onChanged: (v) => setState(() => _sleep = v),
                    ),
                    const Divider(height: 28),
                    _FiveSlider(label: 'Energy', low: 'Very low', high: 'Very good', value: _energy, onChanged: (v) => setState(() => _energy = v)),
                    const SizedBox(height: 18),
                    _FiveSlider(label: 'Mood', low: 'Very low', high: 'Very good', value: _mood, onChanged: (v) => setState(() => _mood = v)),
                    const SizedBox(height: 18),
                    _FiveSlider(label: 'Appetite', low: 'Very poor', high: 'Very good', value: _appetite, onChanged: (v) => setState(() => _appetite = v)),
                    const SizedBox(height: 18),
                    _FiveSlider(label: 'Mobility', low: 'Very limited', high: 'Very good', value: _mobility, onChanged: (v) => setState(() => _mobility = v)),
                    const Divider(height: 28),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _weightCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Weight today (kg) — optional',
                            ),
                            onChanged: (v) => setState(() => _weight = double.tryParse(v)),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    // Added 2026-09-07 — same "clearly optional" treatment
                    // as the weight field above: muted helper text, no
                    // red-asterisk required marker, `hintText` (not
                    // `labelText`) so an empty field never LOOKS
                    // incomplete. Only visible to doctors once saved —
                    // NOT yet part of risk scoring, see
                    // context/decisions-log.md.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Blood pressure (optional)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.rnMuted(0.9)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Only if you've taken a reading at home today — skip it otherwise.",
                      style: TextStyle(fontSize: 12, color: context.rnMuted(0.55)),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _systolicCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(hintText: 'Systolic'),
                            onChanged: (v) => setState(() => _systolic = int.tryParse(v)),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('/', style: TextStyle(fontSize: 18)),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _diastolicCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(hintText: 'Diastolic'),
                            onChanged: (v) => setState(() => _diastolic = int.tryParse(v)),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 10),
                          child: Text('mmHg', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    TextField(
                      controller: _bloodSugarCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Blood sugar (optional, mg/dL)',
                        hintText: "Only if you've checked it today",
                      ),
                      onChanged: (v) => setState(() => _bloodSugar = int.tryParse(v)),
                    ),
                    const Divider(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Medicine today', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'taken', label: Text('Taken')),
                            ButtonSegment(value: 'missed', label: Text('Missed')),
                          ],
                          selected: {_medicine},
                          onSelectionChanged: (s) => setState(() => _medicine = s.first),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ANYTHING TODAY?', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: RnColors.accent)),
                    const SizedBox(height: 12),
                    if (checklist.isEmpty)
                      Text(
                        'No specific checklist for your diagnosis — describe anything unusual in a Voice Diary entry instead.',
                        style: TextStyle(color: context.rnMuted(0.6), fontSize: 13),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: checklist.map((s) {
                          final selected = _selectedSymptomIds.contains(s.id);
                          return FilterChip(
                            label: Text(s.symptomName),
                            selected: selected,
                            onSelected: (v) => setState(() {
                              if (v) {
                                _selectedSymptomIds.add(s.id);
                              } else {
                                _selectedSymptomIds.remove(s.id);
                              }
                            }),
                            selectedColor: RnColors.accent200,
                            checkmarkColor: RnColors.accentDark,
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text("Save today's check-in"),
            ),
          ],
        ),
      ),
    );
  }
}

class _FiveSlider extends StatelessWidget {
  const _FiveSlider({
    required this.label,
    required this.low,
    required this.high,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String low;
  final String high;
  final double value;
  final ValueChanged<double> onChanged;

  static const _words = ['Very low', 'Low', 'Usual', 'Good', 'Very good'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text(_words[value.round() - 1], style: const TextStyle(color: RnColors.accentDark)),
          ],
        ),
        Slider(
          value: value,
          min: 1,
          max: 5,
          divisions: 4,
          onChanged: onChanged,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(low, style: TextStyle(fontSize: 11, color: context.rnMuted(0.5))),
            Text(high, style: TextStyle(fontSize: 11, color: context.rnMuted(0.5))),
          ],
        ),
      ],
    );
  }
}

class _HoursField extends StatelessWidget {
  const _HoursField({required this.label, required this.value, required this.onChanged});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text('${value.toStringAsFixed(1)}h', style: const TextStyle(color: RnColors.accentDark)),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: 14,
          divisions: 28,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
