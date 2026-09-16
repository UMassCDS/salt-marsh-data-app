/// Field Outing model - represents a single monitoring visit
class FieldOuting {
  int? id;
  String? localId;
  int orgId;
  int? createdByUserId;
  String siteName;
  String? otherMembers;
  String monitoringType; // vegetation, hydrology, elevation
  DateTime? startTime;
  DateTime? endTime;
  DateTime? submissionTime;
  double? latitude;
  double? longitude;
  String approvalStatus;
  String syncStatus;
  int? approvedByUserId;
  DateTime? approvedAt;
  String? rejectionReason;
  bool isDraft;
  String? visibility; // public, private, embargo - null falls back to org default
  String? embargoUntil; // ISO date string, only used when visibility == 'embargo'
  DateTime? createdAt;
  DateTime? updatedAt;

  FieldOuting({
    this.id,
    this.localId,
    required this.orgId,
    this.createdByUserId,
    required this.siteName,
    this.otherMembers,
    required this.monitoringType,
    this.startTime,
    this.endTime,
    this.submissionTime,
    this.latitude,
    this.longitude,
    this.approvalStatus = 'pending',
    this.syncStatus = 'pending',
    this.approvedByUserId,
    this.approvedAt,
    this.rejectionReason,
    this.isDraft = false,
    this.visibility,
    this.embargoUntil,
    this.createdAt,
    this.updatedAt,
  });

  /// Convert to JSON for database storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'local_id': localId,
      'org_id': orgId,
      'created_by_user_id': createdByUserId,
      'site_name': siteName,
      'other_members': otherMembers,
      'monitoring_type': monitoringType,
      'start_time': startTime?.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'submission_time': submissionTime?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'approval_status': approvalStatus,
      'sync_status': syncStatus,
      'approved_by_user_id': approvedByUserId,
      'approved_at': approvedAt?.toIso8601String(),
      'rejection_reason': rejectionReason,
      'is_draft': isDraft ? 1 : 0,
      'visibility': visibility,
      'embargo_until': embargoUntil,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Create from database row
  factory FieldOuting.fromMap(Map<String, dynamic> map) {
    return FieldOuting(
      id: map['id'] as int?,
      localId: map['local_id'] as String?,
      orgId: map['org_id'] as int,
      createdByUserId: map['created_by_user_id'] as int?,
      siteName: map['site_name'] as String,
      otherMembers: map['other_members'] as String?,
      monitoringType: map['monitoring_type'] as String,
      startTime: map['start_time'] != null
          ? DateTime.parse(map['start_time'] as String)
          : null,
      endTime: map['end_time'] != null
          ? DateTime.parse(map['end_time'] as String)
          : null,
      submissionTime: map['submission_time'] != null
          ? DateTime.parse(map['submission_time'] as String)
          : null,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      approvalStatus: map['approval_status'] as String? ?? 'pending',
      syncStatus: map['sync_status'] as String? ?? 'pending',
      approvedByUserId: map['approved_by_user_id'] as int?,
      approvedAt: map['approved_at'] != null
          ? DateTime.parse(map['approved_at'] as String)
          : null,
      rejectionReason: map['rejection_reason'] as String?,
      isDraft: (map['is_draft'] as int?) == 1,
      visibility: map['visibility'] as String?,
      embargoUntil: map['embargo_until'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }
}
