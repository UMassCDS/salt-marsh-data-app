import 'package:flutter/material.dart';
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
import '../../models/field_outing/draft_snapshot.dart';
import '../../models/field_outing/field_outing.dart';
import '../../models/field_outing/plot_data.dart';
import '../../providers/auth_provider.dart';
import '../../providers/field_outing_provider.dart';
import '../../providers/org_provider.dart';
import '../../services/draft_autosave.dart';
import '../../services/species_service.dart';
import '../../services/protocol_service.dart';
import '../../utils/id_utils.dart';
import '../../utils/snackbar_utils.dart';
import 'widgets/action_bar.dart';
import 'widgets/common_fields.dart';
import 'widgets/monitoring_forms.dart';
import 'widgets/plot_card.dart';

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

  AutosaveStatus _autosaveStatus = AutosaveStatus.idle;
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

  /// Get GPS location and update plot coordinates
  Future<void> _getGPSLocation(int plotIndex) async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable location services')),
          );
        }
        return;
      }

      // Check location permissions
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

      // Approximate location grants can't satisfy a "high" accuracy fix and
      // will hang indefinitely (getCurrentPosition has no default timeout).
      final accuracyStatus = await Geolocator.getLocationAccuracy();
      final desiredAccuracy = accuracyStatus == LocationAccuracyStatus.reduced
          ? LocationAccuracy.reduced
          : LocationAccuracy.high;

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: desiredAccuracy,
          timeLimit: const Duration(seconds: 20),
        ),
      );

      // Update plot coordinates
      setState(() {
        _plots[plotIndex].latitude = position.latitude;
        _plots[plotIndex].longitude = position.longitude;
        _plots[plotIndex].latController.text = position.latitude.toStringAsFixed(6);
        _plots[plotIndex].lngController.text = position.longitude.toStringAsFixed(6);
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ GPS error: $e')),
        );
      }
    }
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
          FormActionBar(
            autosaveStatus: _autosaveStatus,
            onSaveDraft: () => _saveDraft(context, ref),
            onEndSession: () => _endSessionWithConfirm(context, ref),
          ),
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
                              const SectionHeader('Field Session Information'),
                              ReadOnlyField(
                                'Observer',
                                ref.watch(authProvider).user?.fullName ?? '',
                                Icons.person,
                              ),
                              AppTextField(_siteNameController, 'Site Name', Icons.location_on),
                              AppTextField(_otherMembersController, 'Other Team Members', Icons.people, maxLines: 2),
                              TimeField(_startTimeController, 'Start Time'),
                              TimeField(_endTimeController, 'End Time'),
                              VisibilitySelector(
                                visibility: _visibility,
                                embargoUntil: _embargoUntil,
                                onVisibilityChanged: (v) => setState(() {
                                  _visibility = v;
                                  if (v != 'embargo') _embargoUntil = null;
                                }),
                                onEmbargoChanged: (d) => setState(() => _embargoUntil = d),
                              ),

                              const SizedBox(height: 24),

                              if (widget.monitoringType == 'vegetation')
                                _buildVegetationSectionHeader()
                              else if (widget.monitoringType == 'hydrology')
                                HydrologyForm(
                                  areaTreatmentController: _areaTreatmentController,
                                  wlrTypeController: _wlrTypeController,
                                  serialNumberController: _serialNumberController,
                                  waypointNumberController: _waypointNumberController,
                                  rtkElevationController: _rtkElevationController,
                                  waterAboveBelowController: _waterAboveBelowController,
                                  wellRimToWaterController: _wellRimToWaterController,
                                  wellRimToMarshController: _wellRimToMarshController,
                                )
                              else if (widget.monitoringType == 'elevation')
                                ElevationForm(
                                  transectIdController: _transectIdController,
                                  pointNumberController: _pointNumberController,
                                  latitudeController: _latitudeController,
                                  longitudeController: _longitudeController,
                                  elevationNavd88Controller: _elevationNavd88Controller,
                                  featureTypeController: _featureTypeController,
                                ),
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
        const SectionHeader('Vegetation Plots'),
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
          ? PlotCard(
              index: index,
              plot: plot,
              canDelete: _plots.length > 1,
              activeProtocol: _activeProtocol,
              allSpecies: _allSpecies,
              onCollapse: () => setState(() => _expandedPlotLocalId = null),
              onDelete: () => _deletePlot(index),
              onFieldChanged: (field, value) => _onPlotFieldChanged(index, field, value),
              onGetGpsLocation: () => _getGPSLocation(index),
              onRtkChanged: (v) {
                setState(() => plot.rtkPointNumber = v.isEmpty ? null : v);
                _onEdited();
              },
              onSubclassChanged: (v) {
                setState(() => plot.subclass = v);
                _onEdited();
              },
              onRemovePhoto: () => setState(() {
                _plots[index].photoFile = null;
                _plots[index].photoPath = null;
              }),
              onTakePhoto: () => _pickImageFromCamera(index),
              onChoosePhoto: () => _pickImageFromGallery(index),
              onSpeciesChanged: () {
                setState(() {});
                _onEdited();
              },
            )
          : CollapsedPlotSummary(
              plot: plot,
              onTap: () => setState(() => _expandedPlotLocalId = plot.localId),
            ),
    );
  }

  void _deletePlot(int index) {
    setState(() {
      final removed = _plots.removeAt(index);
      _plotCardKeys.remove(removed.localId);
      if (_expandedPlotLocalId == removed.localId) {
        _expandedPlotLocalId = _plots.isEmpty ? null : _plots.last.localId;
      }
      removed.dispose();
    });
    _onEdited();
  }

  void _onPlotFieldChanged(int plotIndex, String field, String value) {
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
        case 'habitatType':
          _plots[plotIndex].habitatType = value;
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
    if (mounted) setState(() => _autosaveStatus = AutosaveStatus.saving);
    try {
      final captured = _captureDraft();
      await _writeDraft(captured);
      _markClean();
      if (mounted) {
        setState(() => _autosaveStatus = AutosaveStatus.saved);
        // A static "Saved" label stops getting read after a few seconds;
        // fading it back to idle keeps it meaningful as a one-off event.
        // Errors are left out of this - they stay until the next attempt
        // resolves, since that's the one state a user needs to act on
        _autosaveFadeTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && _autosaveStatus == AutosaveStatus.saved) {
            setState(() => _autosaveStatus = AutosaveStatus.idle);
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _autosaveStatus = AutosaveStatus.error);
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
      if (_currentDraftId != null && childTable != null) {
        // Finalizes the existing draft row in place (one transaction) rather
        // than deleting it and creating a new one - a process death between
        // those two steps used to be able to lose the session entirely
        await service.updateDraftWithChildren(
            _currentDraftId!, outing, snapshot.toChildRows(), childTable,
            isDraft: false);
      } else if (childTable != null) {
        await service.saveFieldOutingWithChildren(
            outing, snapshot.toChildRows(), childTable);
      } else {
        await service.saveFieldOuting(outing);
      }

      _currentDraftId = null;
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
