-- DB schema v7, fresh install at commit 93faa79

CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT UNIQUE NOT NULL,
      full_name TEXT NOT NULL,
      is_active INTEGER DEFAULT 1,
      is_superadmin INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now')),
      last_login TEXT
    );

CREATE TABLE organizations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      slug TEXT UNIQUE NOT NULL,
      description TEXT,
      contact_email TEXT,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now'))
    );

CREATE TABLE org_members (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      org_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
      role TEXT NOT NULL CHECK(role IN ('viewer', 'contributor', 'manager', 'owner')),
      joined_at TEXT DEFAULT (datetime('now')),
      UNIQUE(user_id, org_id)
    );

CREATE TABLE field_outings (
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
    );

CREATE TABLE vegetation_records (
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
      canopy_height_m REAL,
      thatch_height_m REAL,
      species_observations TEXT NOT NULL,
      photo_local_path TEXT,
      photo_filename TEXT,
      notes TEXT,
      protocol_code TEXT,
      subclass TEXT,
      rtk_point_number TEXT,
      sync_status TEXT DEFAULT 'pending',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

CREATE TABLE hydrology_records (
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
    );

CREATE TABLE elevation_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      local_id TEXT UNIQUE,
      server_id INTEGER UNIQUE,
      outing_id INTEGER NOT NULL REFERENCES field_outings(id) ON DELETE CASCADE,
      transect_id TEXT NOT NULL,
      point_number INTEGER NOT NULL,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      elevation_navd88_m REAL NOT NULL,
      feature_type TEXT,
      notes TEXT,
      sync_status TEXT DEFAULT 'pending',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      UNIQUE(outing_id, transect_id, point_number)
    );

CREATE TABLE species_lookup (
      species_code TEXT PRIMARY KEY,
      scientific_name TEXT NOT NULL,
      common_name TEXT,
      family TEXT,
      growth_form TEXT,
      native_status TEXT,
      active INTEGER DEFAULT 1
    );

CREATE TABLE form_configs (
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
    );

CREATE TABLE form_fields (
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
    );

CREATE TABLE repeating_groups (
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
    );

CREATE TABLE species_cache (
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
    );

CREATE TABLE custom_form_fields (
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
    );

CREATE TABLE form_versions (
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
    );

CREATE TABLE form_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      template_code TEXT UNIQUE NOT NULL,
      template_name TEXT NOT NULL,
      description TEXT,
      monitoring_type TEXT NOT NULL,
      schema_json TEXT NOT NULL,
      is_active INTEGER DEFAULT 1,
      created_at TEXT DEFAULT (datetime('now'))
    );

CREATE TABLE org_form_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      org_id INTEGER NOT NULL,
      template_id INTEGER NOT NULL,
      customizations_json TEXT,
      is_enabled INTEGER DEFAULT 1,
      enabled_at TEXT DEFAULT (datetime('now')),
      UNIQUE(org_id, template_id),
      FOREIGN KEY(org_id) REFERENCES organizations(id) ON DELETE CASCADE,
      FOREIGN KEY(template_id) REFERENCES form_templates(id) ON DELETE CASCADE
    );

CREATE TABLE form_submissions (
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
    );

CREATE TABLE form_submission_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      local_id TEXT UNIQUE NOT NULL,
      submission_id INTEGER NOT NULL,
      group_id TEXT NOT NULL,
      record_index INTEGER NOT NULL,
      data_json TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      UNIQUE(submission_id, group_id, record_index),
      FOREIGN KEY(submission_id) REFERENCES form_submissions(id) ON DELETE CASCADE
    );

CREATE TABLE sync_queue (
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
    );

CREATE TABLE pending_uploads (
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
    );

CREATE TABLE sync_state (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      device_id TEXT UNIQUE NOT NULL,
      last_full_sync TEXT,
      last_partial_sync TEXT,
      last_form_config_sync TEXT,
      pending_changes_count INTEGER DEFAULT 0,
      pending_uploads_count INTEGER DEFAULT 0,
      updated_at TEXT DEFAULT (datetime('now'))
    );

CREATE TABLE protocol_cache (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      org_id INTEGER NOT NULL UNIQUE,
      protocol_code TEXT NOT NULL,
      protocol_name TEXT NOT NULL,
      definition_json TEXT NOT NULL,
      cached_at TEXT DEFAULT (datetime('now'))
    );

CREATE INDEX idx_users_email ON users(email);

CREATE INDEX idx_orgs_slug ON organizations(slug);

CREATE INDEX idx_members_user ON org_members(user_id);

CREATE INDEX idx_members_org ON org_members(org_id);

CREATE INDEX idx_members_role ON org_members(org_id, role);

CREATE INDEX idx_outings_org ON field_outings(org_id);

CREATE INDEX idx_outings_approval ON field_outings(org_id, approval_status);

CREATE INDEX idx_outings_creator ON field_outings(created_by_user_id);

CREATE INDEX idx_outings_draft ON field_outings(is_draft, org_id);

CREATE INDEX idx_veg_outing ON vegetation_records(outing_id);

CREATE INDEX idx_hydro_outing ON hydrology_records(outing_id);

CREATE INDEX idx_elev_outing ON elevation_records(outing_id);

CREATE INDEX idx_form_configs_org ON form_configs(org_id);

CREATE INDEX idx_form_fields_org ON form_fields(org_id);

CREATE INDEX idx_form_fields_form ON form_fields(org_id, form_name);

CREATE INDEX idx_species_cache_org ON species_cache(org_id);

CREATE INDEX idx_species_cache_code ON species_cache(org_id, species_code);

CREATE INDEX idx_custom_form_fields_org ON custom_form_fields(org_id);

CREATE INDEX idx_custom_form_fields_form ON custom_form_fields(org_id, form_name);

CREATE INDEX idx_form_versions_org ON form_versions(org_id);

CREATE INDEX idx_form_versions_active ON form_versions(org_id, form_name, is_active);

CREATE INDEX idx_sync_queue_org ON sync_queue(org_id);

CREATE INDEX idx_sync_queue_pending ON sync_queue(is_pending, created_locally_at);

CREATE INDEX idx_pending_uploads_org ON pending_uploads(org_id);

CREATE INDEX idx_pending_uploads_status ON pending_uploads(upload_status);

CREATE INDEX idx_form_templates_code ON form_templates(template_code);

CREATE INDEX idx_form_templates_type ON form_templates(monitoring_type);

CREATE INDEX idx_org_form_templates_org ON org_form_templates(org_id);

CREATE INDEX idx_org_form_templates_enabled ON org_form_templates(org_id, is_enabled);

CREATE INDEX idx_form_submissions_org ON form_submissions(org_id);

CREATE INDEX idx_form_submissions_template ON form_submissions(template_id);

CREATE INDEX idx_form_submissions_sync ON form_submissions(sync_status);

CREATE INDEX idx_form_submission_records_submission ON form_submission_records(submission_id);

CREATE INDEX idx_protocol_cache_org ON protocol_cache(org_id);
