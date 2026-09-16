import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../services/sync_service.dart';
import 'db_schema.dart';
import 'daos/field_outing_dao.dart';
// import 'daos/form_config_dao.dart';
import 'seeds/template_seeds.dart';
// TODO: Temporarily commented out until Freezed models are fixed
// import 'daos/form_template_dao.dart';
// import 'daos/form_submission_dao.dart';

/// Main database class for MassMarsh app
class AppDatabase {
  static const String _dbName = 'mass_marsh.db';
  static const int _dbVersion = 8;

  static final AppDatabase _instance = AppDatabase._internal();

  Database? _database;

  AppDatabase._internal();

  factory AppDatabase() {
    return _instance;
  }

  static AppDatabase get instance => _instance;

  /// Get database instance (lazy initialization)
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// Get FieldOutingDao
  FieldOutingDao get fieldOutingDao {
    if (_database == null) {
      throw Exception('Database not initialized. Call await database first.');
    }
    return FieldOutingDao(_database!);
  }

  // TODO: Temporarily commented out until form_config_dao is fixed
  // /// Get FormConfigDao
  // FormConfigDao get formConfigDao {
  //   if (_database == null) {
  //     throw Exception('Database not initialized. Call await database first.');
  //   }
  //   return FormConfigDao(_database!);
  // }

  // TODO: Temporarily commented out until Freezed models are fixed
  // /// Get FormTemplateDao
  // FormTemplateDAO get formTemplateDao {
  //   if (_database == null) {
  //     throw Exception('Database not initialized. Call await database first.');
  //   }
  //   return FormTemplateDAO(_database!);
  // }

  // /// Get FormSubmissionDao
  // FormSubmissionDAO get formSubmissionDao {
  //   if (_database == null) {
  //     throw Exception('Database not initialized. Call await database first.');
  //   }
  //   return FormSubmissionDAO(_database!);
  // }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  /// Called when database is created for first time
  Future<void> _onCreate(Database db, int version) async {
    // Enable foreign keys
    await db.execute('PRAGMA foreign_keys = ON');

    // Create all tables
    for (final sql in DbSchema.createTableStatements) {
      await db.execute(sql);
    }

    // Create indices
    for (final sql in DbSchema.createIndexStatements) {
      await db.execute(sql);
    }

    // Seed initial data if needed
    await _seedData(db);
  }

  /// Called when database is opened
  Future<void> _onOpen(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    // Ensure orgs exist even if db was created before this seed was added
    await TemplateSeeds.seedOrganizations(db);
  }

  /// Called when database version changes.
  /// Keep the `if (oldVersion < N)` blocks below in ascending N order - they
  /// run in source order, not numeric order, so a later migration assuming an
  /// earlier one already ran would silently misbehave if these were reordered.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Migration from version 1 to 2: Add server_id column to field_outings
    // Note: SQLite doesn't support UNIQUE constraint in ALTER TABLE, so we add it without UNIQUE
    // New databases will have UNIQUE from the schema definition
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE field_outings ADD COLUMN server_id INTEGER');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE vegetation_records ADD COLUMN plot_id TEXT');
    }
    if (oldVersion < 4) {
      // Remove FK constraint on org_id - org IDs come from the API, not local DB.
      // SQLite requires recreating the table to drop a constraint.
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('ALTER TABLE field_outings RENAME TO _field_outings_old');
      await db.execute('''
        CREATE TABLE field_outings (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          local_id TEXT UNIQUE,
          server_id INTEGER UNIQUE,
          kobo_id INTEGER UNIQUE,
          kobo_uuid TEXT UNIQUE,
          org_id INTEGER NOT NULL,
          created_by_user_id INTEGER REFERENCES users(id),
          crew_leader TEXT NOT NULL,
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
          created_at TEXT DEFAULT (datetime('now')),
          updated_at TEXT DEFAULT (datetime('now'))
        )
      ''');
      await db.execute('''
        INSERT INTO field_outings SELECT * FROM _field_outings_old
      ''');
      await db.execute('DROP TABLE _field_outings_old');
      await db.execute('PRAGMA foreign_keys = ON');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE field_outings ADD COLUMN visibility TEXT');
      await db.execute('ALTER TABLE field_outings ADD COLUMN embargo_until TEXT');
    }
    if (oldVersion < 6) {
      // Drop kobo_id, kobo_uuid, and crew_leader columns.
      // SQLite requires a table rebuild to drop columns.
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute(
        'ALTER TABLE field_outings RENAME TO _field_outings_old',
      );
      await db.execute('''
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
        )
      ''');
      await db.execute('''
        INSERT INTO field_outings (
          id, local_id, server_id, org_id, created_by_user_id,
          site_name, other_members, monitoring_type,
          start_time, end_time, latitude, longitude,
          approval_status, approved_by_user_id, approved_at, rejection_reason,
          sync_status, is_draft, visibility, embargo_until, created_at, updated_at
        )
        SELECT
          id, local_id, server_id, org_id, created_by_user_id,
          site_name, other_members, monitoring_type,
          start_time, end_time, latitude, longitude,
          approval_status, approved_by_user_id, approved_at, rejection_reason,
          sync_status, is_draft, visibility, embargo_until, created_at, updated_at
        FROM _field_outings_old
      ''');
      await db.execute('DROP TABLE _field_outings_old');
      await db.execute('PRAGMA foreign_keys = ON');
    }
    if (oldVersion < 7) {
      // Add protocol_cache table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS protocol_cache (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          org_id INTEGER NOT NULL UNIQUE,
          protocol_code TEXT NOT NULL,
          protocol_name TEXT NOT NULL,
          definition_json TEXT NOT NULL,
          cached_at TEXT DEFAULT (datetime('now'))
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_protocol_cache_org ON protocol_cache(org_id)',
      );
      // Add protocol-specific columns to vegetation_records
      await db.execute(
        'ALTER TABLE vegetation_records ADD COLUMN protocol_code TEXT',
      );
      await db.execute(
        'ALTER TABLE vegetation_records ADD COLUMN subclass TEXT',
      );
      await db.execute(
        'ALTER TABLE vegetation_records ADD COLUMN rtk_point_number TEXT',
      );
    }
    if (oldVersion < 8) {
      // Separate from sync_status so a failed photo isn't indistinguishable from a synced one
      await db.execute(
        'ALTER TABLE vegetation_records ADD COLUMN photo_upload_error TEXT',
      );
      await db.execute(
        'ALTER TABLE vegetation_records ADD COLUMN photo_upload_attempts INTEGER DEFAULT 0',
      );
    }
  }

  /// Seed initial data into database
  Future<void> _seedData(Database db) async {
    await _seedSpeciesData(db);
    await TemplateSeeds.seedAll(db);
  }

  /// Seed species lookup table with all species
  Future<void> _seedSpeciesData(Database db) async {
    const species = [
      ('BARE', 'Bare Ground', null),
      ('TEST_NEW', 'Test New', null),
      ('DEAD', 'Dead Vegetation', null),
      ('WRACK', 'Wrack', null),
      ('TRMAR', 'Triglochin maritima', 'Seaside Arrowgrass'),
      ('TECAN', 'Teucrium canadensis', 'Canada Germander'),
      ('JUBAL', 'Juncus balticus', 'Baltic Rush'),
      ('JUGER', 'Juncus gerardii', 'Black Grass'),
      ('TYLAT', 'Typha latifolia', 'Cattail'),
      ('PORUM', 'Polygonum ramosissimum', 'Bushy Knotweed'),
      ('SCAME', 'Schoenoplectus americanus', 'Chairmaker Bulrush'),
      ('SADEP', 'Salicornia depressa', 'Glasswort'),
      ('PHAUS', 'Phragmites australis', 'Common Reed'),
      ('AGSTO', 'Agrostis stolonifera', 'Creeping Bent'),
      ('BAHAL', 'Baccharis halimifolia', 'Groundsel Bush'),
      ('CASEP', 'Calystegia sepium', 'Bindweed'),
      ('IMCAP', 'Impatiens capensis', 'Orange Balsam'),
      ('IVFRU', 'Iva frutescens', 'Marsh Elder'),
      ('ATPAT', 'Atriplex patula', 'Spearscale'),
      ('JUEFF', 'Juncus effusus', 'Soft Rush'),
      ('SPLAT', 'Spiraea latifolia', 'Meadowsweet'),
      ('TYANG', 'Typha angustifolia', 'Narrow-leaved Cattail'),
      ('MYPEN', 'Myrica pennsylvanica', 'Northern Bayberry'),
      ('TORAD', 'Toxicodendron radicans', 'Poison Ivy'),
      ('SPPEC', 'Spartina pectinata', 'Prairie Cordgrass'),
      ('LYSAL', 'Lythrum salicaria', 'Purple Loosestrife'),
      ('FERUB', 'Festuca rubra', 'Red Fescue'),
      ('PHARU', 'Phalaris arundinacea', 'Reed Canary Grass'),
      ('RORAG', 'Rosa rugosa', 'Rugosa Rose'),
      ('SYTEN', 'Symphyotrichium tenuifolius', 'Alkali Marsh Aster'),
      ('BOMAR', 'Bolboschoenus maritimus', 'Sea Bulrush'),
      ('BOROB', 'Bolboschoenus robustus', 'Sturdy Bulrush'),
      ('AGMAR', 'Agalinas maritima', 'Goat Rue'),
      ('SPPAT', 'Spartina patens', 'Salt Meadow Cordgrass'),
      ('SPALT', 'Spartina alterniflora', 'Smooth Cordgrass'),
      ('SULIN', 'Suaeda linearis', 'Alkali Seepweed'),
      ('LICAR', 'Limonium carolinianum', 'Sea Lavender'),
      ('GLMAR', 'Glaux maritima', 'Sea Milkwort'),
      ('PUMAR', 'Puccinellia maritima', 'Alkali Grass'),
      ('TRMAR2', 'Triglochin maritima', 'Seaside Arrowgrass'),
      ('SOSEM', 'Solidago sempervirens', 'Seaside Goldenrod'),
      ('PLMAR', 'Plantago maritima', 'Goose-tongue'),
      ('ARANS', 'Argentina anserina', 'Silverweed'),
      ('DISPI', 'Distichlis spicata', 'Desert Saltgrass'),
      ('MYGAL', 'Myrica gale', 'Sweet Gale'),
      ('PAVIR', 'Panicum virgatum', 'Switchgrass'),
      ('UNK', 'Unknown Species', 'Unknown'),
      ('RUMAR', 'Ruppia maritima', 'Widgeon Grass'),
    ];

    for (final (code, scientificName, commonName) in species) {
      await db.insert(
        'species_lookup',
        {
          'species_code': code,
          'scientific_name': scientificName,
          'common_name': commonName,
          'active': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  /// Close database
  Future<void> close() async {
    // Awaited so the WAL is checkpointed before anyone copies the file
    await _database?.close();
    _database = null;
  }

  /// Clear all data (for testing/reset)
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('field_outings');
    await db.delete('vegetation_records');
    await db.delete('hydrology_records');
    await db.delete('elevation_records');
    await db.delete('sync_queue');
    await db.delete('pending_uploads');
  }

  /// Get database stats
  Future<Map<String, int>> getDatabaseStats() async {
    final db = await database;
    final stats = <String, int>{};

    // Count tables
    final tables = [
      'users',
      'organizations',
      'field_outings',
      'vegetation_records',
      'hydrology_records',
      'elevation_records',
      'sync_queue',
      'pending_uploads',
      'form_configs',
    ];

    for (final table in tables) {
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $table'),
      );
      stats[table] = count ?? 0;
    }

    return stats;
  }

  /// Export database to a file that can be shared or imported elsewhere.
  ///
  /// Creates a copy of the database file in the app's documents directory
  /// with a timestamped filename for easy identification.
  ///
  /// Returns the File object of the exported database.
  ///
  /// Example usage:
  /// ```dart
  /// final exportedFile = await AppDatabase.instance.exportDatabase();
  /// // Share file using share_plus or file_picker
  /// ```
  Future<File> exportDatabase() async {
    final dbPath = await getDatabasesPath();
    final dbFile = File(join(dbPath, _dbName));

    // Auto-sync and background sync both open their own queries against this
    // database - paused around the close/reopen below so they can't hit a
    // "database has been closed" error mid-export
    SyncService.instance.stopAutoSync();
    try {
      // Ensure database is closed before copying
      await _database?.close();
      _database = null;

      final exportDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final exportPath = join(
        exportDir.path,
        'mass_marsh_export_$timestamp.db',
      );

      final exportedFile = await dbFile.copy(exportPath);

      // Reopen database
      await database;

      return exportedFile;
    } finally {
      SyncService.instance.startAutoSync();
    }
  }

  /// Import a database file, replacing the current database.
  ///
  /// CAUTION: This will completely replace the existing database with the
  /// imported one. All current data will be lost. Make sure to backup first
  /// if needed.
  ///
  /// Parameters:
  /// - [importPath]: The absolute path to the database file to import
  ///
  /// Throws an exception if the import fails.
  ///
  /// Example usage:
  /// ```dart
  /// // After user picks a .db file
  /// await AppDatabase.instance.importDatabase(pickedFilePath);
  /// ```
  Future<void> importDatabase(String importPath) async {
    final dbPath = await getDatabasesPath();
    final targetPath = join(dbPath, _dbName);

    SyncService.instance.stopAutoSync();
    try {
      // Close existing database
      await _database?.close();
      _database = null;

      // Copy imported file to database location
      final importFile = File(importPath);
      if (!await importFile.exists()) {
        throw Exception('Import file does not exist: $importPath');
      }

      await importFile.copy(targetPath);

      // Reopen database to validate
      await database;
    } finally {
      SyncService.instance.startAutoSync();
    }
  }

  /// Get the current database file path.
  ///
  /// Useful for debugging or advanced file operations.
  Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, _dbName);
  }
}
