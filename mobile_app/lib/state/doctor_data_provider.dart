import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/doctor.dart';
import '../models/entry.dart';
import '../models/patient_profile.dart';
import '../services/doctor_service.dart';
import '../services/entry_service.dart';
import '../services/patient_service.dart';

/// Holds every piece of doctor-facing data — roster, alerts, and (per
/// selected patient) profile/timeline/notes — fetched from the FastAPI
/// backend. Mirrors PatientDataProvider's shape/conventions (see
/// context/conventions.md) but keyed off the doctor's own user id, since
/// every doctor-scoped endpoint (`/doctors/{doctor_id}/...`) takes that
/// rather than a patient id.
class DoctorDataProvider extends ChangeNotifier {
  final _doctorService = DoctorService();
  final _patientService = PatientService();
  final _entryService = EntryService();

  int? _doctorId;

  List<DoctorPatientRosterItem> roster = [];
  List<AlertItem> alerts = [];

  bool isLoading = false;
  String? loadError;

  // Per-patient detail state — loaded on demand when a roster/alert row is
  // opened, not part of the initial loadAll.
  PatientProfile? selectedPatient;
  List<Entry> selectedTimeline = []; // newest first, same as the patient app's own timeline
  List<DoctorNote> selectedNotes = [];
  bool isLoadingDetail = false;
  String? detailError;

  int get unreviewedAlertCount => alerts.where((a) => !a.reviewed).length;

  Future<void> loadAll(int doctorId) async {
    _doctorId = doctorId;
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _doctorService.getRoster(doctorId),
        _doctorService.getAlerts(doctorId), // no ?reviewed filter — both screens need the full set
      ]);
      roster = results[0] as List<DoctorPatientRosterItem>;
      alerts = results[1] as List<AlertItem>;
    } on ApiException catch (e) {
      loadError = e.message;
    } catch (_) {
      loadError = 'Could not load your patients right now.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshRoster() async {
    if (_doctorId == null) return;
    try {
      roster = await _doctorService.getRoster(_doctorId!);
      notifyListeners();
    } catch (_) {
      // Silent — same convention as PatientDataProvider.refreshTimeline:
      // the screen keeps whatever it already has rather than clobbering it
      // with an error state on a background pull-to-refresh.
    }
  }

  Future<void> refreshAlerts() async {
    if (_doctorId == null) return;
    try {
      alerts = await _doctorService.getAlerts(_doctorId!);
      notifyListeners();
    } catch (_) {
      // Same convention as above.
    }
  }

  /// Marks an alert reviewed and updates it in place in the already-loaded
  /// list. Deliberately does NOT refresh the roster — a roster row's
  /// `latest_risk_level`/`latest_reasoning` reflect the patient's latest
  /// entry, not alert-review state, so nothing there changes from this
  /// call. Lets any ApiException/other error propagate to the caller
  /// (the Alerts screen shows it inline) rather than swallowing it — unlike
  /// the background refreshes above, this is a direct user action and
  /// should surface a failure.
  Future<void> reviewAlert(int alertId) async {
    final updated = await _doctorService.reviewAlert(alertId);
    final idx = alerts.indexWhere((a) => a.id == alertId);
    if (idx != -1) {
      alerts[idx] = updated;
      notifyListeners();
    }
  }

  Future<void> loadPatientDetail(int patientId) async {
    isLoadingDetail = true;
    detailError = null;
    selectedPatient = null;
    selectedTimeline = [];
    selectedNotes = [];
    notifyListeners();
    try {
      final results = await Future.wait([
        _patientService.getPatient(patientId),
        _entryService.getTimeline(patientId),
        _patientService.getNotes(patientId),
      ]);
      selectedPatient = results[0] as PatientProfile;
      selectedTimeline = results[1] as List<Entry>;
      selectedNotes = results[2] as List<DoctorNote>;
    } on ApiException catch (e) {
      detailError = e.message;
    } catch (_) {
      detailError = 'Could not load this patient right now.';
    } finally {
      isLoadingDetail = false;
      notifyListeners();
    }
  }

  /// Adds a note and prepends it to the already-loaded list (newest-first,
  /// matching GET /patients/{id}/notes' own ordering) rather than
  /// re-fetching. Lets errors propagate — the caller (the add-note sheet)
  /// shows them inline, same reasoning as reviewAlert above.
  Future<void> addNote(int patientId, String noteText) async {
    final note = await _patientService.addNote(patientId, noteText);
    selectedNotes = [note, ...selectedNotes];
    notifyListeners();
  }

  void reset() {
    _doctorId = null;
    roster = [];
    alerts = [];
    selectedPatient = null;
    selectedTimeline = [];
    selectedNotes = [];
    isLoading = false;
    loadError = null;
    isLoadingDetail = false;
    detailError = null;
  }
}
