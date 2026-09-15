import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../constants/species_constants.dart';
import '../models/field_outing/draft_snapshot.dart';
import '../models/field_outing/field_outing.dart';
import '../models/field_outing/plot_data.dart';
import '../providers/auth_provider.dart';
import '../providers/field_outing_provider.dart';
import '../providers/org_provider.dart';
import '../services/draft_autosave.dart';
import '../services/species_service.dart';
import '../services/protocol_service.dart';
import '../utils/id_utils.dart';
import '../utils/photo_viewer.dart';
import '../utils/snackbar_utils.dart';

enum _AutosaveStatus { idle, saving, saved, error }

class FormScreen extends ConsumerStatefulWidget {
  final String monitoringType;
  final int? draftId;

  const FormScreen({
    required this.monitoringType,
    this.draftId,
    super.key,
  });

  @override
  ConsumerState<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends ConsumerState<FormScreen>
    with WidgetsBindingObserver {
  late final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  late final _siteNameController = TextEditingController();
  late final _otherMembersController = TextEditingController();
  late final _startTimeController = TextEditingController();
  late final _endTimeController = TextEditingController();

  // For vegetation monitoring - store multiple plots
  late List<PlotData> _plots;

  // Next plot number is derived from the plots that currently exist, so
  // deleting a plot frees its number for the next one added.
  int get _nextPlotNumber => _plots.isEmpty
      ? 1
      : _plots.map((p) => p.plotNumber).reduce((a, b) => a > b ? a : b) + 1;

  // Visibility
  String _visibility = 'public';
  String? _embargoUntil;

  // GPS capture state, keyed by plot.localId (not list index) - a plot can
  // be deleted while a ~15s capture is in flight, which would otherwise
  // shift indices and write the result into the wrong plot
  final Set<String> _gpsCapturing = {};
  final Map<String, double> _gpsLiveAccuracy = {};

  // Image picker
  final ImagePicker _imagePicker = ImagePicker();

  // Hydrology fields
  late final _areaTreatmentController = TextEditingController();
  late final _wlrTypeController = TextEditingController();
  late final _serialNumberController = TextEditingController();
  late final _waypointNumberController = TextEditingController();
  late final _rtkElevationController = TextEditingController();
  late final _waterAboveBelowController = TextEditingController();
  late final _wellRimToWaterController = TextEditingController();
  late final _wellRimToMarshController = TextEditingController();

  // Elevation fields
  late final _transectIdController = TextEditingController();
  late final _pointNumberController = TextEditingController();
  late final _latitudeController = TextEditingController();
  late final _longitudeController = TextEditingController();
  late final _elevationNavd88Controller = TextEditingController();
  late final _featureTypeController = TextEditingController();

  // Habitat type options for vegetation
  static const List<String> _habitatOptions = [
    'Low Marsh',
    'High Marsh',
    'Pool',
    'Upper Edge',
    'Transition',
    'Panne',
    'Ditch'
  ];

  // Species loaded from API/cache
  List<SpeciesItem> _allSpecies = [];

  // Active protocol definition (fetched per org)
  ProtocolDefinition? _activeProtocol;

  // The draft row this form is bound to (created on first save, then updated
  // in place). Starts as the opened draft's id, or null for a new form.
  int? _currentDraftId;

  // Held for the life of the form so autosave updates one hydrology/elevation row
  final String _singleRecordLocalId = 'rec_${const Uuid().v4()}';

  // Null means nothing is expanded - every place that adds or loads plots
  // sets this explicitly, so collapsing the open plot has somewhere to land
  // without silently re-expanding whatever happens to be last
  String? _expandedPlotLocalId;
  final Map<String, GlobalKey> _plotCardKeys = {};

  GlobalKey _keyFor(PlotData plot) =>
      _plotCardKeys.putIfAbsent(plot.localId, () => GlobalKey());

  bool _isPlotExpanded(PlotData plot) {
    final expandedId = _expandedPlotLocalId;
    return plot.localId == expandedId;
  }

  late final DraftAutosave _autosave = DraftAutosave(save: _persistDraft);

  _AutosaveStatus _autosaveStatus = _AutosaveStatus.idle;
  Timer? _autosaveFadeTimer;

  void _onEdited() {
    if (!_isDirty) return;
    _autosave.schedule();
  }

  // Snapshot of the form state at the last save (or initial load), used to
  // decide whether the "unsaved changes" prompt is needed.
  String _savedSignature = '';

  String _generatePlotId(String transectId, int plotNumber) =>
      generatePlotId(transectId, plotNumber);

  DraftSnapshot _buildSnapshot() {
    return DraftSnapshot(
      monitoringType: widget.monitoringType,
      singleRecordLocalId: _singleRecordLocalId,
      protocolCode: _activeProtocol?.protocolCode ?? 'MassMarshVeg',
      plots: _plots,
      hydrology: widget.monitoringType != 'hydrology'
          ? null
          : HydrologyFields(
              areaTreatment: _areaTreatmentController.text.isEmpty
                  ? null
                  : _areaTreatmentController.text,
              wlrType:
                  _wlrTypeController.text.isEmpty ? null : _wlrTypeController.text,
              serialNumber: _serialNumberController.text,
              waypointNumber: _waypointNumberController.text,
              rtkElevationNavd88M: double.tryParse(_rtkElevationController.text),
              waterAboveBelowNutM: double.tryParse(_waterAboveBelowController.text),
              wellRimToWaterM: double.tryParse(_wellRimToWaterController.text),
              wellRimToMarshM: double.tryParse(_wellRimToMarshController.text),
            ),
      elevation: widget.monitoringType != 'elevation'
          ? null
          : ElevationFields(
              transectId: _transectIdController.text,
              pointNumber: int.tryParse(_pointNumberController.text) ?? 1,
              latitude: double.tryParse(_latitudeController.text) ?? 0.0,
              longitude: double.tryParse(_longitudeController.text) ?? 0.0,
              elevationNavd88M:
                  double.tryParse(_elevationNavd88Controller.text) ?? 0.0,
              featureType: _featureTypeController.text.isEmpty
                  ? null
                  : _featureTypeController.text,
            ),
    );
  }

  /// Serializes the current form state so it can be compared against the
  /// state at the last save to detect real unsaved changes.
  String _formSignature() {
    final plotSig = _plots.map((plot) {
      final speciesSig = (plot.species
              .map((s) => '${s.speciesCode}:${s.percentageCover}')
              .toList()
            ..sort())
          .join(',');
      return [
        plot.transectId,
        plot.plotNumber,
        plot.plotIdController.text,
        plot.habitatType,
        plot.distanceAlongTransect,
        plot.latController.text,
        plot.lngController.text,
        plot.canopyHeight,
        plot.thatchHeight,
        plot.elevation,
        plot.notes,
        plot.photoPath,
        plot.subclass,
        plot.rtkPointNumberController.text,
        speciesSig,
      ].join('|');
    }).join(';');

    return [
      _siteNameController.text,
      _otherMembersController.text,
      _startTimeController.text,
      _endTimeController.text,
      _visibility,
      _embargoUntil,
      _areaTreatmentController.text,
      _wlrTypeController.text,
      _serialNumberController.text,
      _waypointNumberController.text,
      _rtkElevationController.text,
      _waterAboveBelowController.text,
      _wellRimToWaterController.text,
      _wellRimToMarshController.text,
      _transectIdController.text,
      _pointNumberController.text,
      _latitudeController.text,
      _longitudeController.text,
      _elevationNavd88Controller.text,
      _featureTypeController.text,
      plotSig,
    ].join('||');
  }

  void _markClean() => _savedSignature = _formSignature();

  bool get _isDirty => _formSignature() != _savedSignature;

  Future<void> _onBackPressed() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
            'You have unsaved changes. What would you like to do?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('keep'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('save'),
            child: const Text('Save draft'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (result == 'save') {
      await _saveDraft(context, ref, navigateAway: true);
    } else if (result == 'discard') {
      Navigator.of(context).pop();
    }
    // 'keep' or null (tapped outside) → stay on form
  }



  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Last chance to write before Android can reclaim the process
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _autosave.flush().catchError((_) {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _plots = [];
    _currentDraftId = widget.draftId;
    // Load species, protocol, and default visibility after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final org = ref.read(selectedOrgProvider);
      if (org != null && mounted) {
        // Programmatic defaults shouldn't count as user edits, so keep the
        // saved-state baseline in sync when the form was clean before.
        final wasClean = !_isDirty;
        setState(() => _visibility = org.defaultVisibility);
        if (wasClean) _markClean();
        ProtocolService.instance.fetchAndCache(org.id).then((protocol) {
          if (mounted) {
            final wasClean = !_isDirty;
            setState(() {
              _activeProtocol = protocol;
              // Seed RTK point number to "1" for the first plot if the protocol uses it
              if (protocol.hasExtraField('rtk_point_number') &&
                  _plots.isNotEmpty &&
                  (_plots.first.rtkPointNumber == null || _plots.first.rtkPointNumber!.isEmpty)) {
                _plots.first.rtkPointNumber = '1';
                _plots.first.rtkPointNumberController.text = '1';
              }
            });
            if (wasClean) _markClean();
          }
        });
      }
      SpeciesService.instance.fetchAndCache().then((species) {
        if (mounted) setState(() => _allSpecies = species);
      });
    });
    if (widget.monitoringType == 'vegetation' && widget.draftId == null) {
      _plots.add(PlotData(
        transectId: '',
        plotNumber: 1,
        plotId: _generatePlotId('', 1),
        habitatType: '',
        distanceAlongTransect: 0,
        latitude: 0,
        longitude: 0,
        canopyHeight: 0,
        thatchHeight: 0,
        species: [],
      ));
      _expandedPlotLocalId = _plots.first.localId;
    }
    _markClean();

    // Load draft data if draftId is provided
    if (widget.draftId != null) {
      _loadDraftData();
    }
  }

  Future<void> _loadDraftData() async {
    try {
      final service = ref.read(fieldOutingServiceProvider);
      final draft = await service.getDraftById(widget.draftId!);
      
      if (draft == null) return;
      
      // Load basic fields
      _siteNameController.text = draft.siteName;
      if (draft.otherMembers != null) {
        _otherMembersController.text = draft.otherMembers!;
      }
      
      // Load times if available
      if (draft.startTime != null) {
        final start = draft.startTime!;
        _startTimeController.text = '${start.hour > 12 ? start.hour - 12 : start.hour == 0 ? 12 : start.hour}:${start.minute.toString().padLeft(2, '0')} ${start.hour >= 12 ? 'PM' : 'AM'}';
      }
      if (draft.endTime != null) {
        final end = draft.endTime!;
        _endTimeController.text = '${end.hour > 12 ? end.hour - 12 : end.hour == 0 ? 12 : end.hour}:${end.minute.toString().padLeft(2, '0')} ${end.hour >= 12 ? 'PM' : 'AM'}';
      }

      // Restore visibility settings
      setState(() {
        if (draft.visibility != null) _visibility = draft.visibility!;
        _embargoUntil = draft.embargoUntil;
      });

      // Load child records based on monitoring type
      final db = await ref.read(appDatabaseProvider.future);
      final database = await db.database;
      
      if (widget.monitoringType == 'vegetation') {
        final vegRecords = await database.query(
          'vegetation_records',
          where: 'outing_id = ?',
          whereArgs: [widget.draftId],
          orderBy: 'plot_number',
        );
        
        setState(() {
          _plots = vegRecords.map((record) {
            List<PlotSpeciesEntry> species = [];
            if (record['species_observations'] != null) {
              final speciesJson = jsonDecode(record['species_observations'] as String) as List;
              species = speciesJson.map((s) => PlotSpeciesEntry(
                speciesCode: s['species_code'] as String,
                percentageCover: s['percentage_cover'] as int,
              )).toList();
            }
            
            // photoPath alone isn't enough - the thumbnail renders off
            // photoFile, which a freshly loaded draft never had a chance to set
            final photoPath = record['photo_local_path'] as String?;
            final photoFile = photoPath != null && File(photoPath).existsSync()
                ? File(photoPath)
                : null;

            return PlotData(
              localId: record['local_id'] as String?,
              transectId: record['transect_id'] as String? ?? '',
              plotNumber: record['plot_number'] as int? ?? 1,
              plotId: record['plot_id'] as String? ?? '',
              plotIdManuallySet: (record['plot_id'] as String?)?.isNotEmpty ?? false,
              habitatType: record['habitat_type'] as String? ?? '',
              distanceAlongTransect: (record['distance_along_transect_m'] as num?)?.toDouble() ?? 0.0,
              latitude: (record['latitude'] as num?)?.toDouble() ?? 0.0,
              longitude: (record['longitude'] as num?)?.toDouble() ?? 0.0,
              accuracyM: (record['accuracy_m'] as num?)?.toDouble(),
              locationQuality: record['location_quality'] as String?,
              canopyHeight: (record['canopy_height_m'] as num?)?.toDouble() ?? 0.0,
              thatchHeight: (record['thatch_height_m'] as num?)?.toDouble() ?? 0.0,
              elevation: (record['elevation_m'] as num?)?.toDouble(),
              notes: record['notes'] as String?,
              photoPath: photoPath,
              photoFile: photoFile,
              species: species,
              subclass: record['subclass'] as String?,
              rtkPointNumber: record['rtk_point_number'] as String?,
              pinnedCodes: _activeProtocol?.speciesConfig.pinnedSpecies ?? const ['SPALT', 'SPPAT', 'BARE', 'DEAD'],
            );
          }).toList();
          _expandedPlotLocalId = _plots.isEmpty ? null : _plots.last.localId;
        });
      } else if (widget.monitoringType == 'hydrology') {
        final hydroRecords = await database.query(
          'hydrology_records',
          where: 'outing_id = ?',
          whereArgs: [widget.draftId],
          limit: 1,
        );
        
        if (hydroRecords.isNotEmpty) {
          final record = hydroRecords.first;
          setState(() {
            if (record['area_treatment'] != null) {
              _areaTreatmentController.text = record['area_treatment'] as String;
            }
            if (record['wlr_type'] != null) {
              _wlrTypeController.text = record['wlr_type'] as String;
            }
            if (record['serial_number'] != null) {
              _serialNumberController.text = record['serial_number'] as String;
            }
            if (record['waypoint_number'] != null) {
              _waypointNumberController.text = record['waypoint_number'] as String;
            }
            if (record['rtk_elevation_navd88_m'] != null) {
              _rtkElevationController.text = record['rtk_elevation_navd88_m'].toString();
            }
            if (record['water_above_below_nut_m'] != null) {
              _waterAboveBelowController.text = record['water_above_below_nut_m'].toString();
            }
            if (record['well_rim_to_water_m'] != null) {
              _wellRimToWaterController.text = record['well_rim_to_water_m'].toString();
            }
            if (record['well_rim_to_marsh_m'] != null) {
              _wellRimToMarshController.text = record['well_rim_to_marsh_m'].toString();
            }
          });
        }
      } else if (widget.monitoringType == 'elevation') {
        final elevRecords = await database.query(
          'elevation_records',
          where: 'outing_id = ?',
          whereArgs: [widget.draftId],
          limit: 1,
        );
        
        if (elevRecords.isNotEmpty) {
          final record = elevRecords.first;
          setState(() {
            if (record['transect_id'] != null) {
              _transectIdController.text = record['transect_id'] as String;
            }
            if (record['point_number'] != null) {
              _pointNumberController.text = record['point_number'].toString();
            }
            if (record['latitude'] != null) {
              _latitudeController.text = record['latitude'].toString();
            }
            if (record['longitude'] != null) {
              _longitudeController.text = record['longitude'].toString();
            }
            if (record['elevation_navd88_m'] != null) {
              _elevationNavd88Controller.text = record['elevation_navd88_m'].toString();
            }
            if (record['feature_type'] != null) {
              _featureTypeController.text = record['feature_type'] as String;
            }
          });
        }
      }

      // The freshly loaded draft is the saved state — start clean.
      _markClean();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading draft: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosaveFadeTimer?.cancel();

    // dispose cannot await, so the write happens detached after this returns
    final pending = _autosave.hasPendingWork ? _captureDraft() : null;
    _autosave.cancel();
    if (pending != null) {
      _writeDraft(pending).catchError((_) {});
    }

    for (final plot in _plots) {
      plot.dispose();
    }
    _siteNameController.dispose();
    _otherMembersController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    _areaTreatmentController.dispose();
    _wlrTypeController.dispose();
    _serialNumberController.dispose();
    _waypointNumberController.dispose();
    _rtkElevationController.dispose();
    _waterAboveBelowController.dispose();
    _wellRimToWaterController.dispose();
    _wellRimToMarshController.dispose();
    _transectIdController.dispose();
    _pointNumberController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _elevationNavd88Controller.dispose();
    _featureTypeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Quality tiers inferred from accuracy, since geolocator's Position has
  // no `provider` field to read on Android 12+ (fused always wins there) -
  // see the GPS design note in the v0.8 backlog plan.
  static const _gpsGoodAccuracyM = 8.0;
  static const _gpsFairAccuracyM = 20.0;
  static const _gpsSampleWindow = Duration(seconds: 15);
  static const _gpsMaxFixAge = Duration(seconds: 5);
  static const _gpsPhotoStampMaxAge = Duration(minutes: 2);

  static String _qualityTierFor(double accuracyM) {
    if (accuracyM <= _gpsGoodAccuracyM) return 'gps_good';
    if (accuracyM <= _gpsFairAccuracyM) return 'gps_fair';
    return 'coarse';
  }

  static String _qualityLabel(String tier) => switch (tier) {
        'gps_good' => 'good',
        'gps_fair' => 'fair',
        'coarse' => 'coarse',
        _ => tier,
      };

  /// Samples live GPS fixes for up to [_gpsSampleWindow], discarding stale
  /// and mocked fixes, keeping the best-accuracy fix seen, and stopping
  /// early once accuracy crosses the "good" threshold. On timeout, keeps
  /// whatever best fix was seen (labelled by its quality tier) rather than
  /// failing outright - a fix is more useful than none in the field.
  Future<void> _getGPSLocation(String plotLocalId) async {
    // Resolved fresh each time it's needed - a ~15s capture can outlive the
    // plot's position in the list, or the plot itself, if the user deletes
    // a plot while a capture is in flight
    int? currentIndex() {
      final idx = _plots.indexWhere((p) => p.localId == plotLocalId);
      return idx == -1 ? null : idx;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable location services')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission denied')),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions permanently denied'),
            ),
          );
        }
        return;
      }

      final accuracyStatus = await Geolocator.getLocationAccuracy();
      final desiredAccuracy = accuracyStatus == LocationAccuracyStatus.reduced
          ? LocationAccuracy.reduced
          : LocationAccuracy.best;

      setState(() {
        _gpsCapturing.add(plotLocalId);
        _gpsLiveAccuracy.remove(plotLocalId);
      });

      Position? best;
      final stream = Geolocator.getPositionStream(
        locationSettings: LocationSettings(accuracy: desiredAccuracy),
      );
      final sub = stream.listen(null);
      final completer = Completer<void>();

      sub.onData((position) {
        if (position.isMocked) return;
        final age = DateTime.now().difference(position.timestamp);
        if (age > _gpsMaxFixAge) return; // stale cached/fused fix, ignore

        if (best == null || position.accuracy < best!.accuracy) {
          best = position;
          if (mounted) {
            setState(() => _gpsLiveAccuracy[plotLocalId] = position.accuracy);
          }
        }
        if (position.accuracy <= _gpsGoodAccuracyM && !completer.isCompleted) {
          completer.complete();
        }
      });
      sub.onError((_) {});

      await Future.any([
        completer.future,
        Future.delayed(_gpsSampleWindow),
      ]);
      await sub.cancel();

      if (!mounted) return;

      if (best == null) {
        setState(() {
          _gpsCapturing.remove(plotLocalId);
          _gpsLiveAccuracy.remove(plotLocalId);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get a GPS fix - try again in the open')),
          );
        }
        return;
      }

      final position = best!;
      final tier = _qualityTierFor(position.accuracy);
      final index = currentIndex();
      setState(() {
        if (index != null) {
          _plots[index].latitude = position.latitude;
          _plots[index].longitude = position.longitude;
          _plots[index].accuracyM = position.accuracy;
          _plots[index].locationQuality = tier;
          _plots[index].latController.text = position.latitude.toStringAsFixed(6);
          _plots[index].lngController.text = position.longitude.toStringAsFixed(6);
        }
        _gpsCapturing.remove(plotLocalId);
        _gpsLiveAccuracy.remove(plotLocalId);
      });
      if (index == null) return; // plot was deleted mid-capture
      _onEdited();
      if (tier == 'coarse' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              'GPS fix is coarse (±${position.accuracy.toStringAsFixed(0)}m) - consider moving to open sky and retrying')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _gpsCapturing.remove(plotLocalId);
          _gpsLiveAccuracy.remove(plotLocalId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ GPS error: $e')),
        );
      }
    }
  }

  Widget? _buildAutosaveIndicator() {
    final colorScheme = Theme.of(context).colorScheme;
    final IconData icon;
    final String label;
    final Color color;

    switch (_autosaveStatus) {
      case _AutosaveStatus.idle:
        return null;
      case _AutosaveStatus.saving:
        icon = Icons.sync;
        label = 'Saving to device…';
        color = colorScheme.onSurface.withValues(alpha: 0.6);
      case _AutosaveStatus.saved:
        icon = Icons.check_circle_outline;
        label = 'Saved on this device';
        color = colorScheme.onSurface.withValues(alpha: 0.6);
      case _AutosaveStatus.error:
        icon = Icons.error_outline;
        label = 'Not saved yet, retrying…';
        color = colorScheme.error;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    final indicator = _buildAutosaveIndicator();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?indicator,
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: () => _saveDraft(context, ref),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Draft'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () => _endSessionWithConfirm(context, ref),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('End Session'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _endSessionWithConfirm(BuildContext context, WidgetRef ref) async {
    final saved = await _saveDraft(context, ref, navigateAway: false);
    if (!saved || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End this session?'),
        content: const Text(
          'Draft saved. Do you want to end and finalize this field session? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange[800]),
            child: const Text('End Session'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _saveFieldOuting(context, ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleMap = {
      'vegetation': 'Vegetation Monitoring Form',
      'hydrology': 'Hydrology Monitoring Form',
      'elevation': 'Elevation Monitoring Form',
    };

    final title = titleMap[widget.monitoringType] ?? 'Field Session Form';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBackPressed();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save Draft',
            onPressed: () => _saveDraft(context, ref),
          ),
        ],
      ),
      floatingActionButton: widget.monitoringType == 'vegetation'
          ? FloatingActionButton.extended(
              onPressed: _addNewPlot,
              icon: const Icon(Icons.add),
              label: const Text('Add Plot'),
            )
          : null,
      body: Column(
        children: [
          _buildActionBar(),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Form(
                  key: _formKey,
                  onChanged: _onEdited,
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // COMMON FIELDS FOR ALL FORMS
                              _buildSectionHeader('Field Session Information'),
                              _buildReadOnlyField(
                                'Observer',
                                ref.watch(authProvider).user?.fullName ?? '',
                                Icons.person,
                              ),
                              _buildTextField(_siteNameController, 'Site Name', Icons.location_on),
                              _buildTextField(_otherMembersController, 'Other Team Members', Icons.people, maxLines: 2),
                              _buildTimeField(_startTimeController, 'Start Time'),
                              _buildTimeField(_endTimeController, 'End Time'),
                              _buildVisibilitySelector(),

                              const SizedBox(height: 24),

                              if (widget.monitoringType == 'vegetation')
                                _buildVegetationSectionHeader()
                              else if (widget.monitoringType == 'hydrology')
                                _buildHydrologyForm()
                              else if (widget.monitoringType == 'elevation')
                                _buildElevationForm(),
                            ],
                          ),
                        ),
                      ),
                      // Only the plot list is a lazy sliver: with 50+ plots
                      // fully expanded, the old eager Column built every
                      // field and controller for all of them at once
                      if (widget.monitoringType == 'vegetation')
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList.builder(
                            itemCount: _plots.length,
                            itemBuilder: (context, index) =>
                                _buildPlotEntry(index, _plots[index]),
                          ),
                        ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 16 +
                              MediaQuery.paddingOf(context).bottom +
                              (widget.monitoringType == 'vegetation' ? 72 : 0),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildVegetationSectionHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Vegetation Plots'),
        Text(
          '${_plots.length} plot(s) added',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildPlotEntry(int index, PlotData plot) {
    return KeyedSubtree(
      key: _keyFor(plot),
      child: _isPlotExpanded(plot)
          ? _buildPlotCard(index, plot)
          : _buildCollapsedPlotSummary(plot),
    );
  }

  Widget _buildCollapsedPlotSummary(PlotData plot) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = plot.plotId.isNotEmpty
        ? plot.plotId
        : 'Plot ${plot.plotNumber}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expandedPlotLocalId = plot.localId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (plot.photoFile != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      plot.photoFile!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      cacheWidth: 80,
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plot ${plot.plotNumber} · $label',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                    if (plot.species.isNotEmpty)
                      Text('${plot.species.length} species recorded',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withValues(alpha: 0.6),
                              )),
                  ],
                ),
              ),
              Icon(Icons.expand_more, color: colorScheme.onSurface.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  void _addNewPlot() {
    late final PlotData newPlot;
    setState(() {
      final plotNum = _nextPlotNumber;
      final transectId = _plots.isNotEmpty ? _plots.first.transectId : '';

      // Continue the previous plot's ID pattern when it ends in a
      // number (plotHELLO_001 -> plotHELLO_002); otherwise fall back
      // to transect_number generation.
      String? autoPlotId;
      var inheritedManualId = false;
      if (_plots.isNotEmpty) {
        final prev = _plots.last;
        autoPlotId = incrementTrailingNumber(prev.plotId);
        inheritedManualId = autoPlotId != null && prev.plotIdManuallySet;
      }

      // Auto-increment RTK point number if the protocol uses it,
      // continuing whatever format the last non-empty value used.
      String? autoRtk;
      if (_activeProtocol?.hasExtraField('rtk_point_number') ?? false) {
        final prevRtk = _plots
            .map((p) => p.rtkPointNumber?.trim() ?? '')
            .lastWhere((v) => v.isNotEmpty, orElse: () => '');
        autoRtk = prevRtk.isEmpty ? '1' : incrementTrailingNumber(prevRtk);
      }

      newPlot = PlotData(
        transectId: transectId,
        plotNumber: plotNum,
        plotId: autoPlotId ?? _generatePlotId(transectId, plotNum),
        plotIdManuallySet: inheritedManualId,
        habitatType: '',
        distanceAlongTransect: 0,
        latitude: 0,
        longitude: 0,
        canopyHeight: 0,
        thatchHeight: 0,
        species: [],
        rtkPointNumber: autoRtk,
        pinnedCodes: _activeProtocol?.speciesConfig.pinnedSpecies ?? const ['SPALT', 'SPPAT', 'BARE', 'DEAD'],
      );
      _plots.add(newPlot);
      _expandedPlotLocalId = newPlot.localId;
    });
    _onEdited();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keyFor(newPlot).currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildPlotCard(int index, PlotData plot) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Plot header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Plot ${plot.plotNumber}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.expand_less),
                      tooltip: 'Collapse',
                      onPressed: () => setState(() => _expandedPlotLocalId = null),
                    ),
                    if (_plots.length > 1)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        final removed = _plots.removeAt(index);
                        _plotCardKeys.remove(removed.localId);
                        if (_expandedPlotLocalId == removed.localId) {
                          _expandedPlotLocalId =
                              _plots.isEmpty ? null : _plots.last.localId;
                        }
                        removed.dispose();
                      });
                      _onEdited();
                    },
                  ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Plot fields — conditional per protocol
            if (!(_activeProtocol?.isFieldHidden('transect_id') ?? false))
              _buildPlotTextField(
                index,
                'transectId',
                plot.transectId,
                'Transect ID',
                Icons.timeline,
              ),
            _buildPlotTextField(
              index,
              'plotId',
              '',
              'Plot ID (e.g. CB_T1_P1)',
              Icons.tag,
              isOptional: true,
              controller: plot.plotIdController,
            ),
            if (!(_activeProtocol?.isFieldHidden('habitat_type') ?? false))
              _buildPlotTextField(
                index,
                'habitatType',
                plot.habitatType,
                'Habitat Type',
                Icons.terrain,
                isDropdown: true,
                dropdownOptions: _habitatOptions,
              ),
            if (!(_activeProtocol?.isFieldHidden('distance_along_transect_m') ?? false))
              _buildPlotTextField(
                index,
                'distanceAlongTransect',
                plot.distanceAlongTransect == 0 ? '' : plot.distanceAlongTransect.toString(),
                'Distance Along Transect (m)',
                Icons.straighten,
                isNumber: true,
              ),
            _buildPlotTextField(
              index,
              'latitude',
              '',
              'Latitude',
              Icons.location_on,
              isNumber: true,
              controller: plot.latController,
            ),
            _buildPlotTextField(
              index,
              'longitude',
              '',
              'Longitude',
              Icons.location_on,
              isNumber: true,
              controller: plot.lngController,
            ),

            // GPS Button + live/result accuracy indicator
            Builder(builder: (context) {
              final isCapturing = _gpsCapturing.contains(plot.localId);
              final liveAccuracy = _gpsLiveAccuracy[plot.localId];
              final hasFix = plot.latitude != 0 || plot.longitude != 0;
              final tier = plot.locationQuality;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: isCapturing ? null : () => _getGPSLocation(plot.localId),
                        icon: isCapturing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.my_location),
                        label: Text(isCapturing
                            ? (liveAccuracy != null
                                ? 'Capturing… ±${liveAccuracy.toStringAsFixed(0)} m'
                                : 'Capturing GPS…')
                            : (hasFix ? 'Recapture GPS Location' : 'Get GPS Location')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    if (!isCapturing && hasFix && plot.accuracyM != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Chip(
                          avatar: Icon(
                            tier == 'gps_good'
                                ? Icons.check_circle
                                : (tier == 'gps_fair' ? Icons.info : Icons.warning),
                            size: 18,
                            color: tier == 'gps_good'
                                ? Colors.green
                                : (tier == 'gps_fair' ? Colors.orange : Colors.red),
                          ),
                          label: Text(
                            '±${plot.accuracyM!.toStringAsFixed(0)} m · ${_qualityLabel(tier ?? '')}',
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              );
            }),

            if (!(_activeProtocol?.isFieldHidden('canopy_height_m') ?? false))
              _buildPlotTextField(
                index,
                'canopyHeight',
                plot.canopyHeight == 0 ? '' : plot.canopyHeight.toString(),
                'Canopy Height (m)',
                Icons.height,
                isNumber: true,
                allowNegative: false,
              ),
            if (!(_activeProtocol?.isFieldHidden('thatch_height_m') ?? false))
              _buildPlotTextField(
                index,
                'thatchHeight',
                plot.thatchHeight == 0 ? '' : plot.thatchHeight.toString(),
                'Thatch Height (m)',
                Icons.height,
                isNumber: true,
                allowNegative: false,
              ),
            if (!(_activeProtocol?.isFieldHidden('elevation_navd88_m') ?? false))
              _buildPlotTextField(
                index,
                'elevation',
                plot.elevation?.toString() ?? '',
                'Elevation (m)',
                Icons.landscape,
                isNumber: true,
                isOptional: true,
              ),

            // UASCommunity extra fields
            if (_activeProtocol?.hasExtraField('rtk_point_number') ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: plot.rtkPointNumberController,
                  decoration: const InputDecoration(
                    labelText: 'RTK Point #',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.pin_drop),
                  ),
                  onChanged: (v) {
                    setState(() => plot.rtkPointNumber = v.isEmpty ? null : v);
                    _onEdited();
                  },
                ),
              ),
            if (_activeProtocol?.hasExtraField('subclass') ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('subclass_${plot.localId}_${plot.subclass}'),
                  initialValue: plot.subclass,
                  decoration: const InputDecoration(
                    labelText: 'Subclass',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.category),
                  ),
                  isExpanded: true,
                  items: (_activeProtocol!.subclassOptions ?? [])
                      .map((opt) => DropdownMenuItem(
                            value: opt,
                            child: Text(opt, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => plot.subclass = v);
                    _onEdited();
                  },
                ),
              ),

            _buildPlotTextField(
              index,
              'notes',
              plot.notes ?? '',
              'Notes',
              Icons.note,
              maxLines: 2,
              isOptional: true,
            ),

            const SizedBox(height: 16),

            // Photo section
            Text(
              'Plot Photo',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (plot.photoFile != null)
              Stack(
                children: [
                  GestureDetector(
                    onTap: () => showFullScreenPhoto(context, plot.photoFile!),
                    child: Image.file(
                      plot.photoFile!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      // The file on disk stays full-resolution; only the
                      // decoded-for-display copy is downsized, since a 12MP
                      // photo decoded per plot is what likely OOM'd the app
                      cacheWidth: 800,
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('Tap to enlarge',
                                style: TextStyle(color: Colors.white, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: Icon(Icons.close, color: Colors.red[400]),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() {
                          _plots[index].photoFile = null;
                          _plots[index].photoPath = null;
                        });
                      },
                    ),
                  ),
                ],
              )
            else
              Container(
                height: 100,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text('No photo selected'),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImageFromCamera(index),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Take Photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImageFromGallery(index),
                    icon: const Icon(Icons.image),
                    label: const Text('Choose Photo'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            Divider(),
            const SizedBox(height: 16),

            // Species observations
            SpeciesCoverInput(
              plot: plot,
              allSpecies: _allSpecies,
              onChanged: () {
                setState(() {});
                _onEdited();
              },
              coverIncrement: _activeProtocol?.speciesConfig.coverIncrement ?? 1,
              pinnedCodes: _activeProtocol?.speciesConfig.pinnedSpecies ?? const ['SPALT', 'SPPAT', 'BARE', 'DEAD'],
              require100Percent: _activeProtocol?.speciesConfig.require100Percent ?? true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlotTextField(
    int plotIndex,
    String field,
    String currentValue,
    String label,
    IconData icon, {
    bool isNumber = false,
    bool isDropdown = false,
    bool isOptional = false,
    bool allowNegative = true,
    int maxLines = 1,
    List<String>? dropdownOptions,
    TextEditingController? controller,
  }) {
    if (isDropdown && dropdownOptions != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: currentValue.isEmpty ? null : currentValue,
          items: dropdownOptions.map((option) {
            return DropdownMenuItem(
              value: option,
              child: Text(option),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                switch (field) {
                  case 'habitatType':
                    _plots[plotIndex].habitatType = value;
                }
              });
              _onEdited();
            }
          },
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(icon),
          ),
          validator: (value) {
            if (!isOptional && (value == null || value.isEmpty)) {
              return 'This field is required';
            }
            return null;
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        initialValue: controller != null ? null : currentValue,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
        ),
        keyboardType: isNumber
            ? TextInputType.numberWithOptions(decimal: true, signed: allowNegative)
            : TextInputType.text,
        inputFormatters: isNumber && !allowNegative
            ? [FilteringTextInputFormatter.deny(RegExp(r'-'))]
            : null,
        maxLines: maxLines,
        onChanged: (value) {
          setState(() {
            switch (field) {
              case 'plotId':
                _plots[plotIndex].plotId = value;
                _plots[plotIndex].plotIdManuallySet = value.isNotEmpty;
              case 'transectId':
                _plots[plotIndex].transectId = value;
                if (!_plots[plotIndex].plotIdManuallySet) {
                  final id = _generatePlotId(
                    value,
                    _plots[plotIndex].plotNumber,
                  );
                  _plots[plotIndex].plotId = id;
                  _plots[plotIndex].plotIdController.text = id;
                }
              case 'distanceAlongTransect':
                _plots[plotIndex].distanceAlongTransect = double.tryParse(value) ?? 0;
              case 'latitude':
                _plots[plotIndex].latitude = double.tryParse(value) ?? 0;
              case 'longitude':
                _plots[plotIndex].longitude = double.tryParse(value) ?? 0;
              case 'canopyHeight':
                _plots[plotIndex].canopyHeight = double.tryParse(value) ?? 0;
              case 'thatchHeight':
                _plots[plotIndex].thatchHeight = double.tryParse(value) ?? 0;
              case 'elevation':
                _plots[plotIndex].elevation = double.tryParse(value);
              case 'notes':
                _plots[plotIndex].notes = value;
            }
          });
          _onEdited();
        },
        validator: (value) {
          if (!isOptional && (value == null || value.isEmpty)) {
            return 'This field is required';
          }
          if (!allowNegative && value != null) {
            final parsed = double.tryParse(value);
            if (parsed != null && parsed < 0) {
              return 'Cannot be negative';
            }
          }
          return null;
        },
      ),
    );
  }

  Widget _buildHydrologyForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Hydrology Measurement Information'),
        _buildTextField(_areaTreatmentController, 'Area Treatment', Icons.eco, isOptional: true),
        _buildTextField(_wlrTypeController, 'WLR Type', Icons.water, isOptional: true),
        _buildTextField(_serialNumberController, 'Serial Number', Icons.fingerprint, isOptional: true),
        _buildTextField(_waypointNumberController, 'Waypoint Number', Icons.location_on, inputType: TextInputType.number),
        _buildTextField(_rtkElevationController, 'RTK Elevation (NAVD88 m)', Icons.height, inputType: TextInputType.number),
        _buildTextField(_waterAboveBelowController, 'Water Above/Below NUT (m)', Icons.water, inputType: TextInputType.number, isOptional: true),
        _buildTextField(_wellRimToWaterController, 'Well Rim to Water (m)', Icons.water, inputType: TextInputType.number, isOptional: true),
        _buildTextField(_wellRimToMarshController, 'Well Rim to Marsh (m)', Icons.water, inputType: TextInputType.number, isOptional: true),
      ],
    );
  }

  Widget _buildElevationForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader('Elevation Point Information'),
        _buildTextField(_transectIdController, 'Transect ID', Icons.timeline),
        _buildTextField(_pointNumberController, 'Point Number', Icons.numbers, inputType: TextInputType.number),
        _buildTextField(_latitudeController, 'Latitude', Icons.location_on, inputType: TextInputType.number),
        _buildTextField(_longitudeController, 'Longitude', Icons.location_on, inputType: TextInputType.number),
        _buildTextField(_elevationNavd88Controller, 'Elevation (NAVD88 m)', Icons.landscape, inputType: TextInputType.number),
        _buildTextField(_featureTypeController, 'Feature Type', Icons.landscape, isOptional: true),
      ],
    );
  }

  Widget _buildVisibilitySelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Visibility', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'public', label: Text('Public'), icon: Icon(Icons.public, size: 16)),
              ButtonSegment(value: 'private', label: Text('Private'), icon: Icon(Icons.lock, size: 16)),
              ButtonSegment(value: 'embargo', label: Text('Embargo'), icon: Icon(Icons.schedule, size: 16)),
            ],
            selected: {_visibility},
            onSelectionChanged: (v) => setState(() {
              _visibility = v.first;
              if (_visibility != 'embargo') _embargoUntil = null;
            }),
          ),
          if (_visibility == 'embargo') ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(_embargoUntil != null
                  ? 'Embargo until: $_embargoUntil'
                  : 'Pick embargo date'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 90)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (picked != null && mounted) {
                  setState(() => _embargoUntil = picked.toIso8601String().substring(0, 10));
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Colors.green[700],
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(4),
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(value, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
            Icon(Icons.lock_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType inputType = TextInputType.text,
    int maxLines = 1,
    bool isOptional = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
          prefixIcon: Icon(icon),
        ),
        keyboardType: inputType,
        maxLines: maxLines,
        validator: (value) {
          if (!isOptional && (value == null || value.isEmpty)) {
            if (label.contains('Crew Leader') || label.contains('Site Name')) {
              return 'This field is required';
            }
          }
          return null;
        },
      ),
    );
  }

  Widget _buildTimeField(
    TextEditingController controller,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.access_time),
        ),
        readOnly: true,
        onTap: () async {
          final time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.now(),
          );
          if (time != null && mounted) {
            controller.text = time.format(context);
          }
        },
      ),
    );
  }

  /// Copies the picked image to the app's documents directory so the path
  /// remains valid after iOS clears its temporary cache.
  Future<String> _copyImageToPermanentStorage(String tempPath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(docsDir.path, 'photos'));
    if (!await photosDir.exists()) await photosDir.create(recursive: true);
    final filename = '${DateTime.now().millisecondsSinceEpoch}${p.extension(tempPath)}';
    final dest = p.join(photosDir.path, filename);
    await File(tempPath).copy(dest);
    return dest;
  }

  // Redundant with the coordinates already saved on the plot record, but a
  // photo that carries its own location survives even if that record is lost
  Future<void> _stampPhotoLocation(String path, int plotIndex) async {
    try {
      var lat = _plots[plotIndex].latitude;
      var lon = _plots[plotIndex].longitude;
      if (lat == 0 && lon == 0) {
        // Mirrors _getGPSLocation's permission handling - on a fresh
        // install nothing has requested location access yet, so this
        // photo-time stamp needs to ask too, not just the GPS button
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return;
        }

        final last = await Geolocator.getLastKnownPosition();
        if (last == null) return;
        // An unbounded cached fix can be arbitrarily old (a fix from a
        // different site, hours earlier) - write no GPS EXIF at all rather
        // than stamp the photo with a wrong location.
        if (DateTime.now().difference(last.timestamp) > _gpsPhotoStampMaxAge) {
          return;
        }
        if (last.isMocked) return;
        lat = last.latitude;
        lon = last.longitude;
      }

      final exif = await Exif.fromPath(path);
      try {
        await exif.writeAttributes({
          'GPSLatitude': lat.abs().toString(),
          'GPSLatitudeRef': lat >= 0 ? 'N' : 'S',
          'GPSLongitude': lon.abs().toString(),
          'GPSLongitudeRef': lon >= 0 ? 'E' : 'W',
        });
      } finally {
        await exif.close();
      }
    } catch (_) {
      // Best-effort only - the database record is the record that matters
    }
  }

  Future<void> _pickImageFromCamera(int plotIndex) async {
    try {
      // The camera intent backgrounds this app and Android can kill the
      // process while it's away (OS memory pressure) - flush before
      // handing off so nothing typed since the last debounce is lost
      await _autosave.flush();
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
      );
      if (image != null && mounted) {
        final permanentPath = await _copyImageToPermanentStorage(image.path);
        // Awaited and run before the photo is ever displayed - native EXIF
        // writes rewrite the whole file in place, and racing that against
        // a concurrent Image.file decode of the same path is what was
        // producing "could not decompress image"
        await _stampPhotoLocation(permanentPath, plotIndex);
        setState(() {
          _plots[plotIndex].photoFile = File(permanentPath);
          _plots[plotIndex].photoPath = permanentPath;
        });
        // Flushed rather than scheduled: a photo is expensive to retake
        await _autosave.flush();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error taking photo: $e')),
        );
      }
    }
  }

  Future<void> _pickImageFromGallery(int plotIndex) async {
    try {
      // Same reasoning as the camera path - the gallery picker also hands
      // off to another activity Android can kill this process behind
      await _autosave.flush();
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );
      if (image != null && mounted) {
        final permanentPath = await _copyImageToPermanentStorage(image.path);
        setState(() {
          _plots[plotIndex].photoFile = File(permanentPath);
          _plots[plotIndex].photoPath = permanentPath;
        });
        // Flushed rather than scheduled: a photo is expensive to retake
        await _autosave.flush();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting photo: $e')),
        );
      }
    }
  }

  DateTime? _parseTimeString(String timeStr) {
    if (timeStr.isEmpty) return null;

    try {
      final now = DateTime.now();
      // Handle 12-hour format with AM/PM (e.g., "3:51 PM" or "3:51PM")
      final cleanTime = timeStr.replaceAll(' ', '').toUpperCase();
      final isPM = cleanTime.contains('PM');
      final isAM = cleanTime.contains('AM');

      // Remove AM/PM
      String timePart = cleanTime.replaceAll('PM', '').replaceAll('AM', '');
      final parts = timePart.split(':');

      if (parts.length != 2) return null;

      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);

      // Convert to 24-hour format
      if (isPM && hour != 12) {
        hour += 12;
      } else if (isAM && hour == 12) {
        hour = 0;
      }

      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (e) {
      return null;
    }
  }

  // Must never await, so it stays valid even mid-teardown
  ({FieldOuting outing, String? childTable, List<Map<String, dynamic>> rows})
      _captureDraft() {
    final startTime = _startTimeController.text.isNotEmpty
        ? _parseTimeString(_startTimeController.text)
        : null;
    final endTime = _endTimeController.text.isNotEmpty
        ? _parseTimeString(_endTimeController.text)
        : null;

    final outing = FieldOuting(
      orgId: ref.read(selectedOrgIdProvider),
      createdByUserId: ref.read(authProvider).user?.id,
      siteName: _siteNameController.text,
      otherMembers: _otherMembersController.text.isEmpty
          ? null
          : _otherMembersController.text,
      monitoringType: widget.monitoringType,
      startTime: startTime,
      endTime: endTime,
      isDraft: true,
      visibility: _visibility,
      embargoUntil: _embargoUntil,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final snapshot = _buildSnapshot();
    final childTable = snapshot.childTable;

    return (
      outing: outing,
      childTable: childTable,
      rows: childTable == null ? const <Map<String, dynamic>>[] : snapshot.toChildRows(),
    );
  }

  Future<void> _writeDraft(
    ({FieldOuting outing, String? childTable, List<Map<String, dynamic>> rows})
        captured,
  ) async {
    final service = ref.read(fieldOutingServiceProvider);
    final childTable = captured.childTable;

    if (childTable != null) {
      if (_currentDraftId != null) {
        await service.updateDraftWithChildren(
            _currentDraftId!, captured.outing, captured.rows, childTable);
      } else {
        final localId = await service.saveFieldOutingWithChildren(
            captured.outing, captured.rows, childTable);
        _currentDraftId = await service.getDbIdByLocalId(localId);
      }
    } else {
      final localId = await service.saveFieldOuting(captured.outing);
      _currentDraftId ??= await service.getDbIdByLocalId(localId);
    }
  }

  // Shared by the manual Save Draft button and autosave, so both drive the
  // same status indicator instead of tracking it separately
  Future<void> _persistDraft() async {
    // Any in-flight fade belongs to a previous save - let this attempt's
    // own outcome (saved or error) decide what's shown next
    _autosaveFadeTimer?.cancel();
    if (mounted) setState(() => _autosaveStatus = _AutosaveStatus.saving);
    try {
      final captured = _captureDraft();
      await _writeDraft(captured);
      _markClean();
      if (mounted) {
        setState(() => _autosaveStatus = _AutosaveStatus.saved);
        // A static "Saved" label stops getting read after a few seconds;
        // fading it back to idle keeps it meaningful as a one-off event.
        // Errors are left out of this - they stay until the next attempt
        // resolves, since that's the one state a user needs to act on
        _autosaveFadeTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && _autosaveStatus == _AutosaveStatus.saved) {
            setState(() => _autosaveStatus = _AutosaveStatus.idle);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _autosaveStatus = _AutosaveStatus.error);
      rethrow;
    }
  }

  Future<bool> _saveDraft(BuildContext context, WidgetRef ref, {bool navigateAway = false}) async {
    // Don't require validation for drafts - they can be incomplete
    try {
      await _persistDraft();

      if (mounted) {
        showAppSnackBar(context, 'Draft saved!');

        if (navigateAway) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) Navigator.of(context).pop();
        }
      }
      return true;
    } catch (e) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Error saving draft: $e',
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        );
      }
      return false;
    }
  }

  Future<void> _saveFieldOuting(BuildContext context, WidgetRef ref) async {
    if (!_formKey.currentState!.validate()) {
      // Scroll to the top so the user can see the highlighted required fields.
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Please fill in all required fields before saving.'),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    try {
      // If this session was saved as a draft, remove the draft row before
      // creating the final outing.
      if (_currentDraftId != null) {
        final service = ref.read(fieldOutingServiceProvider);
        await service.deleteDraft(_currentDraftId!);
        _currentDraftId = null;
      }

      // Parse start and end times
      final startTime = _parseTimeString(_startTimeController.text);
      final endTime = _parseTimeString(_endTimeController.text);

      // Create the field outing object
      final outing = FieldOuting(
        orgId: ref.read(selectedOrgIdProvider),
        createdByUserId: ref.read(authProvider).user?.id,
        siteName: _siteNameController.text,
        otherMembers: _otherMembersController.text.isEmpty
            ? null
            : _otherMembersController.text,
        monitoringType: widget.monitoringType,
        startTime: startTime,
        endTime: endTime,
        isDraft: false,
        visibility: _visibility,
        embargoUntil: _embargoUntil,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final service = ref.read(fieldOutingServiceProvider);

      final snapshot = _buildSnapshot();
      final childTable = snapshot.childTable;
      if (childTable != null) {
        await service.saveFieldOutingWithChildren(
            outing, snapshot.toChildRows(), childTable);
      } else {
        await service.saveFieldOuting(outing);
      }

      _markClean();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session saved, uploading to server...'),
            duration: Duration(seconds: 2),
          ),
        );

        // Navigate back after snackbar appears
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving field session: $e')),
        );
      }
    }
  }
}

/// Blocks non-digit characters and clamps the parsed value to [0, 100] as
/// the user types, so the field can never visibly hold an out-of-range %.
class _PercentInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(text: digits);
    }
    final parsed = int.parse(digits).clamp(0, 100);
    digits = parsed.toString();
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

class SpeciesCoverInput extends StatefulWidget {
  final PlotData plot;
  final List<SpeciesItem> allSpecies;
  final VoidCallback onChanged;
  final int coverIncrement;
  final List<String> pinnedCodes;
  final bool require100Percent;

  const SpeciesCoverInput({
    super.key,
    required this.plot,
    required this.allSpecies,
    required this.onChanged,
    this.coverIncrement = 1,
    this.pinnedCodes = const ['SPALT', 'SPPAT', 'BARE', 'DEAD'],
    this.require100Percent = false,
  });

  @override
  State<SpeciesCoverInput> createState() => SpeciesCoverInputState();
}

class SpeciesCoverInputState extends State<SpeciesCoverInput> {
  static const _pinnedLabels = {
    'SPALT': 'Smooth Cordgrass',
    'SPPAT': 'Salt Meadow Cordgrass',
    'BARE': 'Bare Ground',
    'DEAD': 'Dead Vegetation',
  };

  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, GlobalKey> _pinnedRowKeys = {};

  GlobalKey _pinnedKey(String code) =>
      _pinnedRowKeys.putIfAbsent(code, () => GlobalKey());

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SpeciesItem> _filteredSpecies() {
    final q = _searchQuery.toLowerCase().trim();
    if (q.isEmpty) return [];

    final addedCodes = widget.plot.species.map((s) => s.speciesCode).toSet();

    return widget.allSpecies.where((s) {
      if (widget.pinnedCodes.contains(s.code)) return false;
      if (addedCodes.contains(s.code)) return false;
      final haystack = '${s.label.toLowerCase()} ${s.scientificName.toLowerCase()}';
      return s.code.toLowerCase().contains(q) || haystack.contains(q);
    }).toList()
      ..sort((a, b) {
        final aStarts = a.code.toLowerCase().startsWith(q) ? 0 : 1;
        final bStarts = b.code.toLowerCase().startsWith(q) ? 0 : 1;
        return aStarts.compareTo(bStarts);
      });
  }

  /// Pinned species matching the search query, so a field user typing an
  /// abbreviation for an already-pinned species can still find it - just
  /// routed to the fixed pinned row above instead of a second, duplicate entry.
  List<String> _filteredPinnedMatches() {
    final q = _searchQuery.toLowerCase().trim();
    if (q.isEmpty) return [];
    final speciesMap = {for (final s in widget.allSpecies) s.code: s};
    return widget.pinnedCodes.where((code) {
      final item = speciesMap[code];
      final commonName = item?.commonName ?? _pinnedLabels[code] ?? '';
      final scientificName = item?.scientificName ?? '';
      final haystack = '$code $commonName $scientificName'.toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  void _jumpToPinned(String code) {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
    });
    final ctx = _pinnedKey(code).currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
  }

  void _updatePinned(String code, String rawValue) {
    final percent = int.tryParse(rawValue);
    final plot = widget.plot;
    setState(() {
      plot.species.removeWhere((s) => s.speciesCode == code);
      if (percent != null && percent > 0) {
        plot.species.add(PlotSpeciesEntry(
          speciesCode: code,
          percentageCover: percent.clamp(0, 100),
        ));
      }
    });
    widget.onChanged();
  }

  void _addExtra(SpeciesItem species) {
    final plot = widget.plot;
    if (plot.species.any((s) => s.speciesCode == species.code)) return;
    setState(() {
      plot.species.add(PlotSpeciesEntry(speciesCode: species.code, percentageCover: 0));
      plot.extraControllers[species.code] = TextEditingController(text: '');
      _searchController.clear();
      _searchQuery = '';
    });
    widget.onChanged();
  }

  void _removeExtra(String code) {
    final plot = widget.plot;
    setState(() {
      plot.species.removeWhere((s) => s.speciesCode == code);
      plot.extraControllers[code]?.dispose();
      plot.extraControllers.remove(code);
    });
    widget.onChanged();
  }

  void _updateExtra(String code, String rawValue) {
    final percent = int.tryParse(rawValue);
    final plot = widget.plot;
    final idx = plot.species.indexWhere((s) => s.speciesCode == code);
    if (idx < 0 || percent == null) return;
    setState(() {
      plot.species[idx] = PlotSpeciesEntry(
        speciesCode: code,
        percentageCover: percent.clamp(0, 100),
      );
    });
    widget.onChanged();
  }

  Widget _speciesLabel(BuildContext context, String code, String commonLabel, String scientificName,
      {required bool isWideScreen}) {
    final theme = Theme.of(context);
    // A touch smaller on narrow phones so more of the name fits before it
    // has to truncate - still ellipsizes past that, by design
    final primaryStyle = isWideScreen ? theme.textTheme.bodyLarge : theme.textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          scientificName.isEmpty ? commonLabel : scientificName,
          style: primaryStyle?.copyWith(
            fontStyle: scientificName.isEmpty ? FontStyle.normal : FontStyle.italic,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (scientificName.isNotEmpty)
          Text(
            commonLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plot = widget.plot;
    final extraSpecies = plot.species
        .where((s) => !widget.pinnedCodes.contains(s.speciesCode))
        .toList();
    final filtered = _filteredSpecies();
    final pinnedMatches = _filteredPinnedMatches();

    // Build a lookup map for extra species scientific names
    final speciesMap = {for (final s in widget.allSpecies) s.code: s};

    // Wide screens (tablets in the field) get a bigger, easier-to-hit box
    final isWideScreen = MediaQuery.sizeOf(context).width >= 600;
    final coverBoxWidth = isWideScreen ? 88.0 : 68.0;
    final darkOutline = OutlineInputBorder(
      borderSide: BorderSide(color: theme.colorScheme.outline, width: 1.5),
    );

    // Helper: builds a cover input — TextField for increment=1, ChoiceChips otherwise
    Widget buildCoverInput({
      required String code,
      required TextEditingController? controller,
      required int currentValue,
      required void Function(String) onChanged,
    }) {
      if (widget.coverIncrement == 1) {
        return SizedBox(
          width: coverBoxWidth,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [_PercentInputFormatter()],
            style: isWideScreen ? theme.textTheme.titleMedium : null,
            decoration: InputDecoration(
              suffixText: '%',
              border: darkOutline,
              enabledBorder: darkOutline,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              isDense: true,
            ),
            onChanged: onChanged,
          ),
        );
      }
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: List.generate(11, (i) {
          final v = i * 10;
          return ChoiceChip(
            label: Text('$v', style: const TextStyle(fontSize: 11)),
            selected: currentValue == v,
            onSelected: (_) => onChanged(v.toString()),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
          );
        }),
      );
    }

    final coverTotal = plot.species
        .where((s) => !kCoverExcludedSpeciesCodes.contains(s.speciesCode))
        .fold<int>(0, (sum, s) => sum + s.percentageCover);
    final totalMet = coverTotal == 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'Species in this Plot (${plot.species.length})',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: totalMet
                    ? Colors.green.withValues(alpha: 0.15)
                    : (widget.require100Percent
                        ? Colors.orange.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerHighest),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.require100Percent
                    ? 'Total: $coverTotal% ${totalMet ? '' : '(need 100%)'}'
                    : 'Total: $coverTotal%',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: totalMet
                      ? Colors.green.shade800
                      : (widget.require100Percent ? Colors.orange.shade900 : null),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Pinned species rows (always shown in fixed order)
        ...widget.pinnedCodes.map((code) {
          // .commonName, not .label - label already has "CODE - " baked in,
          // and the row below prepends code again, showing it twice
          final commonName = speciesMap[code]?.commonName ?? _pinnedLabels[code];
          final commonLabel = commonName ?? code;
          final scientificName = speciesMap[code]?.scientificName ?? '';
          final controller = plot.pinnedControllers[code];
          final currentValue = plot.species
              .firstWhere((s) => s.speciesCode == code,
                  orElse: () => PlotSpeciesEntry(speciesCode: code, percentageCover: 0))
              .percentageCover;
          if (widget.coverIncrement == 1) {
            return Padding(
              key: _pinnedKey(code),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _speciesLabel(context, code, '$code \u2013 $commonLabel', scientificName,
                        isWideScreen: isWideScreen),
                  ),
                  buildCoverInput(
                    code: code,
                    controller: controller,
                    currentValue: currentValue,
                    onChanged: (v) => _updatePinned(code, v),
                  ),
                ],
              ),
            );
          }
          return Padding(
            key: _pinnedKey(code),
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _speciesLabel(context, code, '$code \u2013 $commonLabel', scientificName,
                    isWideScreen: isWideScreen),
                const SizedBox(height: 4),
                buildCoverInput(
                  code: code,
                  controller: controller,
                  currentValue: currentValue,
                  onChanged: (v) => _updatePinned(code, v),
                ),
              ],
            ),
          );
        }),

        // Extra (non-pinned) added species
        if (extraSpecies.isNotEmpty) ...[
          const Divider(height: 20),
          ...extraSpecies.map((obs) {
            final code = obs.speciesCode;
            final item = speciesMap[code];
            final commonLabel = item?.label ?? code;
            final scientificName = item?.scientificName ?? '';
            final controller = plot.extraControllers[code] ??
                TextEditingController(text: obs.percentageCover.toString());
            if (widget.coverIncrement == 1) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _speciesLabel(context, code, commonLabel, scientificName, isWideScreen: isWideScreen)),
                    buildCoverInput(
                      code: code,
                      controller: controller,
                      currentValue: obs.percentageCover,
                      onChanged: (v) => _updateExtra(code, v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Colors.red),
                      padding: EdgeInsets.zero,
                      onPressed: () => _removeExtra(code),
                    ),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _speciesLabel(context, code, commonLabel, scientificName, isWideScreen: isWideScreen)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.red),
                        padding: EdgeInsets.zero,
                        onPressed: () => _removeExtra(code),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  buildCoverInput(
                    code: code,
                    controller: controller,
                    currentValue: obs.percentageCover,
                    onChanged: (v) => _updateExtra(code, v),
                  ),
                ],
              ),
            );
          }),
        ],

        // Search field
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 20),
            hintText: 'Search to add more species...',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),

        // Search results (pinned matches first, greyed - they route back to
        // the fixed pinned row above rather than adding a duplicate)
        if (filtered.isNotEmpty || pinnedMatches.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: pinnedMatches.length + filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i < pinnedMatches.length) {
                  final code = pinnedMatches[i];
                  final item = speciesMap[code];
                  final commonLabel = item?.commonName ?? _pinnedLabels[code] ?? code;
                  return ListTile(
                    dense: true,
                    title: Text(
                      '$code – $commonLabel (pinned)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    subtitle: Text(
                      item?.scientificName ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_upward, size: 18),
                    onTap: () => _jumpToPinned(code),
                  );
                }
                final s = filtered[i - pinnedMatches.length];
                return ListTile(
                  dense: true,
                  title: Text(s.label, style: theme.textTheme.bodyMedium),
                  subtitle: Text(
                    s.scientificName,
                    style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                  ),
                  trailing: const Icon(Icons.add, size: 18),
                  onTap: () => _addExtra(s),
                );
              },
            ),
          ),
      ],
    );
  }
}
