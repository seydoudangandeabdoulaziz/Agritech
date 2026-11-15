import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
class Analyse {
  final String? id; // ← String (Firestore ID) au lieu de int
  final String imagePath;
  final String imageUrl; // ← URL Firebase Storage (pour Web/sync)
  final String maladie;
  final double confiance;
  final String top3;
  final String conseils;
  final String langue;
  final String date;
  final double? latitude;
  final double? longitude;

  bool get estSain =>
      maladie.toLowerCase().contains('sain') ||
      maladie.toLowerCase().contains('healthy');

  String get confianceAffichee => "${(confiance * 100).toStringAsFixed(1)} %";

  Analyse({
    this.id,
    required this.imagePath,
    this.imageUrl = '',
    required this.maladie,
    required this.confiance,
    required this.top3,
    required this.conseils,
    required this.langue,
    required this.date,
    this.latitude,
    this.longitude,
  });

  // ✅ Convertir pour Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'imagePath': imagePath,
      'imageUrl': imageUrl,
      'maladie': maladie,
      'confiance': confiance,
      'top3': top3,
      'conseils': conseils,
      'langue': langue,
      'date': date,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  // ✅ Créer depuis Firestore
  factory Analyse.fromFirestore(DocumentSnapshot doc) {
    final map = doc.data() as Map<String, dynamic>;
    return Analyse(
      id: doc.id,
      imagePath: map['imagePath'] ?? '',
      imageUrl: map['imageUrl'] ?? '',
      maladie: map['maladie'] ?? '',
      confiance: _parseConfiance(map['confiance']),
      top3: map['top3'] ?? '',
      conseils: map['conseils'] ?? '',
      langue: map['langue'] ?? '',
      date: map['date'] ?? '',
      latitude: map['latitude'] != null
          ? (map['latitude'] as num).toDouble()
          : null,
      longitude: map['longitude'] != null
          ? (map['longitude'] as num).toDouble()
          : null,
    );
  }

  static double _parseConfiance(dynamic val) {
    if (val == null) return 0.0;
    if (val is double) return val;
    if (val is int) return val.toDouble();
    final str = val.toString().replaceAll('%', '').trim();
    final match = RegExp(r'([\d.]+)').firstMatch(str);
    if (match == null) return 0.0;
    final d = double.tryParse(match.group(1)!) ?? 0.0;
    return d > 1 ? d / 100 : d;
  }
}

// ─────────────────────────────────────────────
// GESTIONNAIRE FIRESTORE
// ─────────────────────────────────────────────
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  DatabaseHelper._init();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ✅ Collection de l'utilisateur connecté
  CollectionReference<Map<String, dynamic>> get _collection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Utilisateur non connecté");
    // Chaque utilisateur a son propre historique : users/{uid}/analyses
    return _db.collection('users').doc(uid).collection('analyses');
  }

  // ─────────────────────────────────────────────
  // CRUD
  // ─────────────────────────────────────────────

  // ✅ Insérer une analyse
  Future<String> insertAnalyse(Analyse analyse) async {
    final doc = await _collection.add(analyse.toFirestore());
    return doc.id;
  }

  // ✅ Toutes les analyses (plus récentes en premier)
  Future<List<Analyse>> getAllAnalyses() async {
    try {
      final snapshot = await _collection
          .orderBy('timestamp', descending: true)
          .get();
      return snapshot.docs.map(Analyse.fromFirestore).toList();
    } catch (e) {
      debugPrint("Erreur getAllAnalyses: $e");
      return [];
    }
  }

  // ✅ Stream temps réel (optionnel)
  Stream<List<Analyse>> streamAnalyses() {
    return _collection
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Analyse.fromFirestore).toList());
  }

  // ✅ Analyses avec GPS
  Future<List<Analyse>> getAnalysesAvecGPS() async {
    try {
      final snapshot = await _collection
          .where('latitude', isNull: false)
          .orderBy('timestamp', descending: true)
          .get();
      return snapshot.docs.map(Analyse.fromFirestore).toList();
    } catch (e) {
      debugPrint("Erreur getAnalysesAvecGPS: $e");
      return [];
    }
  }

  // ✅ Supprimer une analyse
  Future<void> deleteAnalyse(String id) async {
    await _collection.doc(id).delete();
  }

  // ✅ Vider tout l'historique
  Future<void> deleteAll() async {
    final snapshot = await _collection.get();
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ✅ Compter les analyses
  Future<int> countAnalyses() async {
    final snapshot = await _collection.count().get();
    return snapshot.count ?? 0;
  }
}