// lib/parcelle_helper.dart
// Modèle Parcelle + CRUD SQLite
// Chaque parcelle a un ID unique qui sert de contenu au QR code

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
// pour réutiliser le même fichier DB

// ─────────────────────────────────────────────
// MODÈLE PARCELLE
// ─────────────────────────────────────────────
class Parcelle {
  final int?    id;
  final String  uid;          // identifiant unique (contenu du QR)
  final String  nom;          // "Champ Nord", "Parcelle A"
  final String  culture;      // "Tomate", "Maïs", etc.
  final double? superficie;   // en hectares
  final double? latitude;
  final double? longitude;
  final String? photoPath;    // chemin vers la photo
  final String  dateCreation;
  final String? notes;

  const Parcelle({
    this.id,
    required this.uid,
    required this.nom,
    required this.culture,
    this.superficie,
    this.latitude,
    this.longitude,
    this.photoPath,
    required this.dateCreation,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
    'id':           id,
    'uid':          uid,
    'nom':          nom,
    'culture':      culture,
    'superficie':   superficie,
    'latitude':     latitude,
    'longitude':    longitude,
    'photoPath':    photoPath,
    'dateCreation': dateCreation,
    'notes':        notes,
  };

  factory Parcelle.fromMap(Map<String, dynamic> m) => Parcelle(
    id:           m['id'],
    uid:          m['uid'],
    nom:          m['nom'],
    culture:      m['culture'],
    superficie:   m['superficie'] != null
        ? (m['superficie'] as num).toDouble()
        : null,
    latitude:     m['latitude'] != null
        ? (m['latitude'] as num).toDouble()
        : null,
    longitude:    m['longitude'] != null
        ? (m['longitude'] as num).toDouble()
        : null,
    photoPath:    m['photoPath'],
    dateCreation: m['dateCreation'],
    notes:        m['notes'],
  );

  /// Contenu encodé dans le QR code
  String get qrData => jsonEncode({
    'type':    'agritech_parcelle',
    'uid':     uid,
    'nom':     nom,
    'culture': culture,
    'version': '1',
  });
}

// ─────────────────────────────────────────────
// DAO PARCELLES
// ─────────────────────────────────────────────
class ParcelleHelper {
  static final ParcelleHelper instance = ParcelleHelper._init();
  static Database? _db;

  ParcelleHelper._init();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, 'parcelles.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE parcelles (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            uid          TEXT    NOT NULL UNIQUE,
            nom          TEXT    NOT NULL,
            culture      TEXT    NOT NULL,
            superficie   REAL,
            latitude     REAL,
            longitude    REAL,
            photoPath    TEXT,
            dateCreation TEXT    NOT NULL,
            notes        TEXT
          )
        ''');
      },
    );
  }

  // ── CRUD ──────────────────────────────────

  Future<int> insertParcelle(Parcelle p) async {
    final db = await database;
    return db.insert('parcelles', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Parcelle>> getAllParcelles() async {
    final db   = await database;
    final maps = await db.query('parcelles', orderBy: 'id DESC');
    return maps.map(Parcelle.fromMap).toList();
  }

  Future<Parcelle?> getParcelleByUid(String uid) async {
    final db   = await database;
    final maps = await db.query('parcelles',
        where: 'uid = ?', whereArgs: [uid], limit: 1);
    if (maps.isEmpty) return null;
    return Parcelle.fromMap(maps.first);
  }

  Future<int> updateParcelle(Parcelle p) async {
    final db = await database;
    return db.update('parcelles', p.toMap(),
        where: 'id = ?', whereArgs: [p.id]);
  }

  Future<void> deleteParcelle(int id) async {
    final db = await database;
    await db.delete('parcelles', where: 'id = ?', whereArgs: [id]);
  }

  /// Génère un UID unique basé sur timestamp + aléatoire
  static String genererUid() {
    final ts  = DateTime.now().millisecondsSinceEpoch;
    final rnd = (ts % 99999).toString().padLeft(5, '0');
    return 'PARC-$ts-$rnd';
  }
}