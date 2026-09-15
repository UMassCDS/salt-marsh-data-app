/// Database schema definitions and initialization SQL
class DbSchema {
  static const String schemaVersion = '1.0';

  /// All CREATE TABLE statements
  static const List<String> createTableStatements = [
    // Users & Organizations
    _usersTable,
    _organizationsTable,
    _orgMembersTable,

    // Data tables
    _fieldOutingsTable,
    _vegetationRecordsTable,
    _hydrologyRecordsTable,
    _elevationRecordsTable,

    // Species lookup
    _speciesLookupTable,

    // Form configuration
    _formConfigsTable,
    _formFieldsTable,
    _repeatingGroupsTable,
    _speciesCacheTable,
    _customFormFieldsTable,
    _formVersionsTable,

    // Dynamic form templates (multi-org support)
    _formTemplatesTable,
    _orgFormTemplatesTable,
    _formSubmissionsTable,
    _formSubmissionRecordsTable,

    // Sync
    _syncQueueTable,
    _pendingUploadsTable,
    _syncStateTable,

    // Protocol cache
    _protocolCacheTable,
  ];

  // ============================================================================
  // AUTH & ORGANIZATION TABLES
  // ============================================================================

  static const String _usersTable = '''
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT UNIQUE NOT NULL,
      full_name TEXT NOT NULL,
      is_active INTEGER DEFAULT 1,
      is_superadmin INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now')),
      last_login TEXT
    )
  ''';

  static const String _organizationsTable = '''
    CREATE TABLE IF NOT EXISTS organizations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      slug TEXT UNIQUE NOT NULL,
      description TEXT,
      contact_email TEXT,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now'))
    )
  ''';

  static const String _orgMembersTable = '''
    CREATE TABLE IF NOT EXISTS org_members (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      org_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
      role TEXT NOT NULL CHECK(role IN ('viewer', 'contributor', 'manager', 'owner')),
      joined_at TEXT DEFAULT (datetime('now')),
      UNIQUE(user_id, org_id)
    )
  ''';

  // ============================================================================
  // DATA TABLES
  // ============================================================================

  static const String _fieldOutingsTable = '''
    CREATE TABLE IF NOT EXISTS field_outings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      local_id TEXT UNIQUE,
      server_id INTEGER UNIQUE,
      org_id INTEGER NOT NULL,
      created_by_user_id INTEGER REFERENCES users(id),
      site_name TEXT NOT NULL,
      other_members TEXT,
      monitoring_type TEXT NOT NULL CHECK(monitoring_type IN ('vegetation', 'hydrology', 'elevation')),
      start_time TEXT,
      end_time TEXT,
      submission_time TEXT,
      latitude REAL,
      longitude REAL,
      accuracy_m REAL,
      location_quality TEXT,
      approval_status TEXT DEFAULT 'pending' CHECK(approval_status IN ('pending', 'approved', 'rejected')),
      approved_by_user_id INTEGER REFERENCES users(id),
      approved_at TEXT,
      rejection_reason TEXT,
      sync_status TEXT DEFAULT 'pending',
      is_draft INTEGER DEFAULT 0,
      visibility TEXT,
      embargo_until TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    )
  ''';

  static const String _vegetationRecordsTable = '''
    CREATE TABLE IF NOT EXISTS vegetation_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      local_id TEXT UNIQUE,
      server_id INTEGER UNIQUE,
      outing_id INTEGER NOT NULL REFERENCES field_outings(id) ON DELETE CASCADE,
      transect_id TEXT,
      plot_number INTEGER NOT NULL,
      plot_id TEXT,
      habitat_type TEXT,
      distance_along_transect_m REAL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      elevation_m REAL,
      accuracy_m REAL,
      location_quality TEXT,
      canopy_height_m REAL,
      thatch_height_m REAL,
      species_observations TEXT NOT NULL,
      photo_local_path TEXT,
      photo_filename TEXT,
      photo_upload_error TEXT,
      photo_upload_attempts INTEGER DEFAULT 0,
      notes TEXT,
      protocol_code TEXT,
      subclass TEXT,
      rtk_point_number TEXT,
      sync_status TEXT DEFAULT 'pending',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    )
  ''';

  static const String _hydrologyRecordsTable = '''
    CREATE TABLE IF NOT EXISTS hydrology_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      local_id TEXT UNIQUE,
      server_id INTEGER UNIQUE,
      outing_id INTEGER NOT NULL REFERENCES field_outings(id) ON DELETE CASCADE,
      area_treatment TEXT,
      wlr_type TEXT,
      serial_number TEXT NOT NULL,
      elevation_waypoint_type TEXT,
      waypoint_number TEXT,
      rtk_elevation_navd88_m REAL,
      time_water_elevation_taken TEXT,
      water_above_below_nut_m REAL,
      well_rim_to_water_m REAL,
      well_rim_to_marsh_m REAL,
      well_rim_to_sensor_m REAL,
      well_length_m REAL,
      notes TEXT,
      sync_status TEXT DEFAULT 'pending',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    )
  ''';

  static const String _elevationRecordsTable = '''
    CREATE TABLE IF NOT EXISTS elevation_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      local_id TEXT UNIQUE,
      server_id INTEGER UNIQUE,
      outing_id INTEGER NOT NULL REFERENCES field_outings(id) ON DELETE CASCADE,
      transect_id TEXT NOT NULL,
      point_number INTEGER NOT NULL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      accuracy_m REAL,
      location_quality TEXT,
      elevation_navd88_m REAL NOT NULL,
      feature_type TEXT,
      notes TEXT,
      sync_status TEXT DEFAULT 'pending',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      UNIQUE(outing_id, transect_id, point_number)
    )
  ''';

  static const String _speciesLookupTable = '''
    CREATE TABLE IF NOT EXISTS species_lookup (
      species_code TEXT PRIMARY KEY,
      scientific_name TEXT NOT NULL,
      common_name TEXT,
      family TEXT,
      growth_form TEXT,
      native_status TEXT,
      active INTEGER DEFAULT 1
    )
  ''';

  // ============================================================================
  // FORM CONFIGURATION TABLES
  // ============================================================================

  static const String _formConfigsTable = '''
    CREATE TABLE IF NOT EXISTS form_configs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      org_id INTEGER NOT NULL UNIQUE,
      config_version TEXT NOT NULL,
      config_hash TEXT NOT NULL,
      common_form_json TEXT NOT NULL,
      vegetation_form_json TEXT NOT NULL,
      hydrology_form_json TEXT NOT NULL,
      elevation_form_json TEXT NOT NULL,
      downloaded_at TEXT DEFAULT (datetime('now')),
      last_validated_at TEXT,
      FOREIGN KEY(org_id) REFERENCES organizations(id) ON DELETE CASCADE
    )
  ''';

  static const String _formFieldsTable = '''
    CREATE TABLE IF NOT EXISTS form_fields (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      org_id INTEGER NOT NULL,
      form_name TEXT NOT NULL,
      field_id TEXT NOT NULL,
      field_label TEXT NOT NULL,
      field_type TEXT NOT NULL,
      required INTEGER DEFAULT 0,
      validation_rules TEXT,
      options_json TEXT,
      data_source TEXT,
      parent_group_id TEXT,
      section_name TEXT,
      help_text TEXT,
      order_index INTEGER,
      downloaded_at TEXT DEFAULT (datetime('now')),
      UNIQUE(org_id, form_name, field_id),
      FOREIGN KEY(org_id) REFERENCES organizations(id) ON DELETE CASCADE
    )
  ''';

  static const String _repeatingGroupsTable = '''
    CREATE TABLE IF NOT EXISTS repeating_groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      org_id INTEGER NOT NULL,
      form_name TEXT NOT NULL,
      group_id TEXT NOT NULL,
      group_label TEXT NOT NULL,
      min_items INTEGER DEFAULT 0,
      max_items INTEGER,
      downloaded_at TEXT DEFAULT (datetime('now')),
      UNIQUE(org_id, form_name, group_id),
      FOREIGN KEY(org_id) REFERENCES organizations(id) ON DELETE CASCADE
    )
  ''';

  static const String _speciesCacheTable = '''
    CREATE TABLE IF NOT EXISTS species_cache (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      org_id INTEGER NOT NULL,
      species_code TEXT NOT NULL,
      common_name TEXT,
      scientific_name TEXT,
      family TEXT,
      growth_form TEXT,
      native_status TEXT,
      active INTEGER DEFAULT 1,
      downloaded_at TEXT DEFAULT (datetime('now')),
      UNIQUE(org_id, species_code),
      FOREIGN KEY(org_id) REFERENCES organizations(id) ON DELETE CASCADE
    )
  ''';

  static const String _customFormFieldsTable = '''
    CREATE TABLE IF NOT EXISTS custom_form_fields (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      org_id INTEGER NOT NULL,
      form_name TEXT NOT NULL CHECK(form_name IN ('common', 'vegetation', 'hydrology', 'elevation')),
      field_id TEXT NOT NULL,
      field_label TEXT NOT NULL,
      field_type TEXT NOT NULL,
      required INTEGER DEFAULT 0,
      validation_rules TEXT,
      options_json TEXT,
      help_text TEXT,
      order_index INTEGER,
      is_active INTEGER DEFAULT 1,
      created_by_user_id INTEGER,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      UNIQUE(org_id, form_name, field_id),
      FOREIGN KEY(org_id) REFERENCES organizations(id) ON DELETE CASCADE,
      FOREIGN KEY(created_by_user_id) REFERENCES users(id)
    )
  ''';

  static const String _formVersionsTable = '''
    CREATE TABLE IF NOT EXISTS form_versions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      org_id INTEGER NOT NULL,
      form_name TEXT NOT NULL CHECK(form_name IN ('common', 'vegetation', 'hydrology', 'elevation', 'marker_horizon')),
      version_number INTEGER NOT NULL,
      config_hash TEXT NOT NULL,
      published_by_user_id INTEGER,
      published_at TEXT,
      is_active INTEGER DEFAULT 1,
      description TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      UNIQUE(org_id, form_name, version_number),
      FOREIGN KEY(org_id) REFERENCES organizations(id) ON DELETE CASCADE,
      FOREIGN KEY(published_by_user_id) REFERENCES users(id)
    )
  ''';

  // ============================================================================
  // DYNAMIC FORM TEMPLATES (MULTI-ORG SUPPORT)
  // ============================================================================

  static const String _formTemplatesTable = '''
    CREATE TABLE IF NOT EXISTS form_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      template_code TEXT UNIQUE NOT NULL,
      template_name TEXT NOT NULL,
      description TEXT,
      monitoring_type TEXT NOT NULL,
      schema_json TEXT NOT NULL,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now'))
    )
  ''';

  static const String _orgFormTemplatesTable = '''
    CREATE TABLE IF NOT EXISTS org_form_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      org_id INTEGER NOT NULL,
      template_id INTEGER NOT NULL,
      customizations_json TEXT,
      is_enabled INTEGER DEFAULT 1,
      enabled_at TEXT DEFAULT (datetime('now')),
      UNIQUE(org_id, template_id),
      FOREIGN KEY(org_id) REFERENCES organizations(id) ON DELETE CASCADE,
      FOREIGN KEY(template_id) REFERENCES form_templates(id) ON DELETE CASCADE
    )
  ''';

  static const String _formSubmissionsTable = '''
    CREATE TABLE IF NOT EXISTS form_submissions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      local_id TEXT UNIQUE NOT NULL,
      server_id INTEGER UNIQUE,
      org_id INTEGER NOT NULL,
      template_id INTEGER NOT NULL,
      outing_id INTEGER,
      form_version INTEGER DEFAULT 1,
      header_data_json TEXT NOT NULL,
      sync_status TEXT DEFAULT 'pending',
      created_by_user_id INTEGER,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY(org_id) REFERENCES organizations(id) ON DELETE CASCADE,
      FOREIGN KEY(template_id) REFERENCES form_templates(id),
      FOREIGN KEY(outing_id) REFERENCES field_outings(id) ON DELETE CASCADE,
      FOREIGN KEY(created_by_user_id) REFERENCES users(id)
    )
  ''';

  static const String _formSubmissionRecordsTable = '''
    CREATE TABLE IF NOT EXISTS form_submission_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      local_id TEXT UNIQUE NOT NULL,
      submission_id INTEGER NOT NULL,
      group_id TEXT NOT NULL,
      record_index INTEGER NOT NULL,
      data_json TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      UNIQUE(submission_id, group_id, record_index),
      FOREIGN KEY(submission_id) REFERENCES form_submissions(id) ON DELETE CASCADE
    )
  ''';

  // ============================================================================
  // SYNC TABLES
  // ============================================================================

  static const String _syncQueueTable = '''
    CREATE TABLE IF NOT EXISTS sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      local_id TEXT UNIQUE NOT NULL,
      org_id INTEGER NOT NULL,
      entity_type TEXT NOT NULL,
      action TEXT NOT NULL CHECK(action IN ('create', 'update', 'delete')),
      server_id INTEGER,
      data_json TEXT NOT NULL,
      created_locally_at TEXT DEFAULT (datetime('now')),
      synced_at TEXT,
      sync_attempts INTEGER DEFAULT 0,
      last_sync_error TEXT,
      is_pending INTEGER DEFAULT 1,
      FOREIGN KEY(org_id) REFERENCES organizations(id),
      FOREIGN KEY(server_id) REFERENCES field_outings(id)
    )
  ''';

  static const String _pendingUploadsTable = '''
    CREATE TABLE IF NOT EXISTS pending_uploads (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      local_id TEXT UNIQUE NOT NULL,
      org_id INTEGER NOT NULL,
      sync_queue_id INTEGER REFERENCES sync_queue(id),
      filename TEXT NOT NULL,
      local_path TEXT NOT NULL,
      file_size_bytes INTEGER,
      content_type TEXT,
      file_hash TEXT,
      uploaded_bytes INTEGER DEFAULT 0,
      upload_status TEXT DEFAULT 'pending' CHECK(upload_status IN ('pending', 'uploading', 'completed', 'failed')),
      upload_percentage INTEGER DEFAULT 0,
      s3_key TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      completed_at TEXT,
      error_message TEXT,
      FOREIGN KEY(org_id) REFERENCES organizations(id)
    )
  ''';

  static const String _syncStateTable = '''
    CREATE TABLE IF NOT EXISTS sync_state (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      device_id TEXT UNIQUE NOT NULL,
      last_full_sync TEXT,
      last_partial_sync TEXT,
      last_form_config_sync TEXT,
      pending_changes_count INTEGER DEFAULT 0,
      pending_uploads_count INTEGER DEFAULT 0,
      updated_at TEXT DEFAULT (datetime('now'))
    )
  ''';

  // ============================================================================
  // PROTOCOL CACHE TABLE
  // ============================================================================

  static const String _protocolCacheTable = '''
    CREATE TABLE IF NOT EXISTS protocol_cache (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      org_id INTEGER NOT NULL UNIQUE,
      protocol_code TEXT NOT NULL,
      protocol_name TEXT NOT NULL,
      definition_json TEXT NOT NULL,
      cached_at TEXT DEFAULT (datetime('now'))
    )
  ''';

  /// Create all indices for performance
  static const List<String> createIndexStatements = [
    'CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)',
    'CREATE INDEX IF NOT EXISTS idx_orgs_slug ON organizations(slug)',
    'CREATE INDEX IF NOT EXISTS idx_members_user ON org_members(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_members_org ON org_members(org_id)',
    'CREATE INDEX IF NOT EXISTS idx_members_role ON org_members(org_id, role)',
    'CREATE INDEX IF NOT EXISTS idx_outings_org ON field_outings(org_id)',
    'CREATE INDEX IF NOT EXISTS idx_outings_approval ON field_outings(org_id, approval_status)',
    'CREATE INDEX IF NOT EXISTS idx_outings_creator ON field_outings(created_by_user_id)',
    'CREATE INDEX IF NOT EXISTS idx_outings_draft ON field_outings(is_draft, org_id)',
    'CREATE INDEX IF NOT EXISTS idx_veg_outing ON vegetation_records(outing_id)',
    'CREATE INDEX IF NOT EXISTS idx_hydro_outing ON hydrology_records(outing_id)',
    'CREATE INDEX IF NOT EXISTS idx_elev_outing ON elevation_records(outing_id)',
    'CREATE INDEX IF NOT EXISTS idx_form_configs_org ON form_configs(org_id)',
    'CREATE INDEX IF NOT EXISTS idx_form_fields_org ON form_fields(org_id)',
    'CREATE INDEX IF NOT EXISTS idx_form_fields_form ON form_fields(org_id, form_name)',
    'CREATE INDEX IF NOT EXISTS idx_species_cache_org ON species_cache(org_id)',
    'CREATE INDEX IF NOT EXISTS idx_species_cache_code ON species_cache(org_id, species_code)',
    'CREATE INDEX IF NOT EXISTS idx_custom_form_fields_org ON custom_form_fields(org_id)',
    'CREATE INDEX IF NOT EXISTS idx_custom_form_fields_form ON custom_form_fields(org_id, form_name)',
    'CREATE INDEX IF NOT EXISTS idx_form_versions_org ON form_versions(org_id)',
    'CREATE INDEX IF NOT EXISTS idx_form_versions_active ON form_versions(org_id, form_name, is_active)',
    'CREATE INDEX IF NOT EXISTS idx_sync_queue_org ON sync_queue(org_id)',
    'CREATE INDEX IF NOT EXISTS idx_sync_queue_pending ON sync_queue(is_pending, created_locally_at)',
    'CREATE INDEX IF NOT EXISTS idx_pending_uploads_org ON pending_uploads(org_id)',
    'CREATE INDEX IF NOT EXISTS idx_pending_uploads_status ON pending_uploads(upload_status)',
    // Form templates indexes
    'CREATE INDEX IF NOT EXISTS idx_form_templates_code ON form_templates(template_code)',
    'CREATE INDEX IF NOT EXISTS idx_form_templates_type ON form_templates(monitoring_type)',
    'CREATE INDEX IF NOT EXISTS idx_org_form_templates_org ON org_form_templates(org_id)',
    'CREATE INDEX IF NOT EXISTS idx_org_form_templates_enabled ON org_form_templates(org_id, is_enabled)',
    'CREATE INDEX IF NOT EXISTS idx_form_submissions_org ON form_submissions(org_id)',
    'CREATE INDEX IF NOT EXISTS idx_form_submissions_template ON form_submissions(template_id)',
    'CREATE INDEX IF NOT EXISTS idx_form_submissions_sync ON form_submissions(sync_status)',
    'CREATE INDEX IF NOT EXISTS idx_form_submission_records_submission ON form_submission_records(submission_id)',
    'CREATE INDEX IF NOT EXISTS idx_protocol_cache_org ON protocol_cache(org_id)',
  ];
}
