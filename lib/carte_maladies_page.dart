import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'database_helper.dart';

// ─── Constantes
const String _baseUrl = 'http://10.10.31.62:8000';// address de la machine hote
const double _rayonAlerteKm = 10.0; // Alerte si maladie à < 10 km
const int _seuilEpidemie = 3;        

// ─── Couleurs par culture 
const Map<String, Color> _couleursCulture = {
  'Pommier': Colors.red,
  'Maïs': Colors.amber,
  'Vigne': Colors.purple,
  'Tomate': Colors.orange,
  'Sain': Colors.green,
};

Color _couleurPourMaladie(String maladie) {
  if (maladie.toLowerCase().contains('sain')) return Colors.green;
  for (final entry in _couleursCulture.entries) {
    if (maladie.startsWith(entry.key)) return entry.value;
  }
  return Colors.blue;
}

IconData _iconePourMaladie(String maladie) {
  if (maladie.toLowerCase().contains('sain')) return Icons.check_circle;
  if (maladie.contains('Pommier')) return Icons.eco;
  if (maladie.contains('Maïs')) return Icons.grass;
  if (maladie.contains('Vigne')) return Icons.local_florist;
  if (maladie.contains('Tomate')) return Icons.circle;
  return Icons.warning;
}

// ─── Modèle point communautaire 
class PointMaladie {
  final double lat;
  final double lon;
  final String maladie;
  final double confiance;
  final String date;
  final bool estLocal; 

  const PointMaladie({
    required this.lat,
    required this.lon,
    required this.maladie,
    required this.confiance,
    required this.date,
    this.estLocal = false,
  });

  factory PointMaladie.fromJson(Map<String, dynamic> j) => PointMaladie(
        lat: j['latitude'].toDouble(),
        lon: j['longitude'].toDouble(),
        maladie: j['maladie'],
        confiance: (j['confiance'] ?? 0).toDouble(),
        date: j['date'] ?? '',
      );

  factory PointMaladie.fromAnalyse(Analyse a) => PointMaladie(
        lat: a.latitude!,
        lon: a.longitude!,
        maladie: a.maladie,
        confiance: a.confiance,
        date: a.date,
        estLocal: true,
      );

  LatLng get latLng => LatLng(lat, lon);
}

// ─── Alerte épidémie
class AlerteEpidemie {
  final String maladie;
  final int nombreCas;
  final double distanceKm;

  const AlerteEpidemie({
    required this.maladie,
    required this.nombreCas,
    required this.distanceKm,
  });
}

class CarteMaladiesPage extends StatefulWidget {
  const CarteMaladiesPage({super.key});

  @override
  State<CarteMaladiesPage> createState() => _CarteMaladiesPageState();
}

class _CarteMaladiesPageState extends State<CarteMaladiesPage> {
  final MapController _mapController = MapController();

  List<PointMaladie> _points = [];
  Position? _maPosition;
  bool _chargement = true;
  String? _erreur;
  List<AlerteEpidemie> _alertes = [];

  // Filtres
  String _filtreActif = 'Tous'; // Tous, Pommier, Maïs, Vigne, Tomate
  bool _afficherSains = false;

  @override
  void initState() {
    super.initState();
    _chargerDonnees();
  }

  // ── Chargement données 
  Future<void> _chargerDonnees() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      // 1. Position GPS utilisateur
      _maPosition = await _obtenirPosition();

      // 2. Données locales SQLite
      final analysesLocales =
          await DatabaseHelper.instance.getAnalysesAvecGPS();
      final pointsLocaux =
          analysesLocales.map((a) => PointMaladie.fromAnalyse(a)).toList();

      // 3. Données communautaires depuis l'API
      final pointsAPI = await _chargerDonneesAPI();

      // 4. Fusion (éviter doublons exacts)
      final tousLesPoints = [...pointsLocaux, ...pointsAPI];

      // 5. Calcul alertes épidémies
      final alertes = _maPosition != null
          ? _calculerAlertes(tousLesPoints, _maPosition!)
          : <AlerteEpidemie>[];

      setState(() {
        _points = tousLesPoints;
        _alertes = alertes;
        _chargement = false;
      });

      // Centrer la carte sur la position utilisateur
      if (_maPosition != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.move(
            LatLng(_maPosition!.latitude, _maPosition!.longitude),
            10.0,
          );
        });
      }
    } catch (e) {
      setState(() {
        _erreur = 'Erreur de chargement : $e';
        _chargement = false;
      });
    }
  }

  Future<List<PointMaladie>> _chargerDonneesAPI() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/analyses/geo'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((j) => PointMaladie.fromJson(j)).toList();
      }
    } catch (_) {
      // API indisponible → on continue avec les données locales
    }
    return [];
  }

  Future<Position?> _obtenirPosition() async {
    try {
      bool serviceActif = await Geolocator.isLocationServiceEnabled();
      if (!serviceActif) return null;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return null;
      }
      if (perm == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Calcul alertes épidémies
  List<AlerteEpidemie> _calculerAlertes(
      List<PointMaladie> points, Position maPos) {
    // Grouper par maladie (sans les sains)
    final Map<String, List<PointMaladie>> parMaladie = {};

    for (final p in points) {
      if (p.maladie.toLowerCase().contains('sain')) continue;

      final distKm = _distanceKm(
        maPos.latitude,
        maPos.longitude,
        p.lat,
        p.lon,
      );

      if (distKm <= _rayonAlerteKm) {
        parMaladie.putIfAbsent(p.maladie, () => []).add(p);
      }
    }

    // Garder seulement ceux qui atteignent le seuil d'épidémie
    final alertes = <AlerteEpidemie>[];
    parMaladie.forEach((maladie, pts) {
      if (pts.length >= _seuilEpidemie) {
        final distMin = pts
            .map((p) => _distanceKm(
                  maPos.latitude,
                  maPos.longitude,
                  p.lat,
                  p.lon,
                ))
            .reduce(min);
        alertes.add(AlerteEpidemie(
          maladie: maladie,
          nombreCas: pts.length,
          distanceKm: distMin,
        ));
      }
    });

    alertes.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    return alertes;
  }

  // Formule Haversine pour distance en km
  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double deg) => deg * pi / 180;

  // ── Filtrage 
  List<PointMaladie> get _pointsFiltres {
    return _points.where((p) {
      if (!_afficherSains && p.maladie.toLowerCase().contains('sain')) {
        return false;
      }
      if (_filtreActif != 'Tous' && !p.maladie.startsWith(_filtreActif)) {
        return false;
      }
      return true;
    }).toList();
  }

  // ── Construire marqueurs
  List<Marker> _construireMarqueurs() {
    final marqueurs = <Marker>[];

    // Marqueur position utilisateur
    if (_maPosition != null) {
      marqueurs.add(Marker(
        point: LatLng(_maPosition!.latitude, _maPosition!.longitude),
        width: 50,
        height: 50,
        child: const _MarqueurUtilisateur(),
      ));
    }

    // Marqueurs maladies
    for (final point in _pointsFiltres) {
      marqueurs.add(Marker(
        point: point.latLng,
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () => _afficherDetailPoint(point),
          child: _MarqueurMaladie(point: point),
        ),
      ));
    }

    return marqueurs;
  }

  // ── Popup détail d'un point ───────────────────────────────
  void _afficherDetailPoint(PointMaladie point) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                _iconePourMaladie(point.maladie),
                color: _couleurPourMaladie(point.maladie),
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  point.maladie,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (point.estLocal)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Votre analyse',
                      style: TextStyle(fontSize: 12, color: Colors.blue)),
                ),
            ]),
            const SizedBox(height: 12),
            _InfoRow(
                icone: Icons.verified,
                texte:
                    'Confiance : ${(point.confiance * 100).toStringAsFixed(1)}%'),
            _InfoRow(
                icone: Icons.calendar_today,
                texte:
                    'Date : ${point.date.substring(0, 10).replaceAll('-', '/')}'),
            _InfoRow(
                icone: Icons.location_on,
                texte:
                    'Coordonnées : ${point.lat.toStringAsFixed(4)}, ${point.lon.toStringAsFixed(4)}'),
            if (_maPosition != null) ...[
              const SizedBox(height: 4),
              _InfoRow(
                icone: Icons.near_me,
                texte:
                    'Distance : ${_distanceKm(_maPosition!.latitude, _maPosition!.longitude, point.lat, point.lon).toStringAsFixed(1)} km',
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte des maladies'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _chargerDonnees,
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : _erreur != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(_erreur!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _chargerDonnees,
                          child: const Text('Réessayer')),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    // ── CARTE ────────────────────────────────
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _maPosition != null
                            ? LatLng(_maPosition!.latitude,
                                _maPosition!.longitude)
                            : const LatLng(13.5, 2.1), // Niamey par défaut
                        initialZoom: 10,
                        maxZoom: 18,
                        minZoom: 3,
                      ),
                      children: [
                        // Tuiles OpenStreetMap
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.agritech',
                        ),
                        // Cercle de rayon d'alerte
                        if (_maPosition != null)
                          CircleLayer(circles: [
                            CircleMarker(
                              point: LatLng(_maPosition!.latitude,
                                  _maPosition!.longitude),
                              radius: _rayonAlerteKm * 1000,
                              useRadiusInMeter: true,
                              color: Colors.blue.withValues(alpha: 0.08),
                              borderColor: Colors.blue.withValues(alpha: 0.4),
                              borderStrokeWidth: 2,
                            ),
                          ]),
                        // Marqueurs
                        MarkerLayer(markers: _construireMarqueurs()),
                      ],
                    ),

                    // ── FILTRES (haut) ───────────────────────
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 8,
                      child: _BarreFiltres(
                        filtreActif: _filtreActif,
                        afficherSains: _afficherSains,
                        onFiltreChange: (f) =>
                            setState(() => _filtreActif = f),
                        onToggleSains: () =>
                            setState(() => _afficherSains = !_afficherSains),
                      ),
                    ),

                    // ── ALERTES ÉPIDÉMIES ────────────────────
                    if (_alertes.isNotEmpty)
                      Positioned(
                        bottom: 80,
                        left: 12,
                        right: 12,
                        child: _PanneauAlertes(alertes: _alertes),
                      ),

                    // ── STATISTIQUES (bas gauche) ────────────
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: _BadgeStats(
                        total: _points.length,
                        malades: _points
                            .where((p) =>
                                !p.maladie.toLowerCase().contains('sain'))
                            .length,
                      ),
                    ),

                    // ── BOUTON CENTRER ───────────────────────
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: FloatingActionButton.small(
                        onPressed: () {
                          if (_maPosition != null) {
                            _mapController.move(
                              LatLng(_maPosition!.latitude,
                                  _maPosition!.longitude),
                              12,
                            );
                          }
                        },
                        backgroundColor: Colors.white,
                        child: const Icon(Icons.my_location,
                            color: Colors.green),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _MarqueurUtilisateur extends StatelessWidget {
  const _MarqueurUtilisateur();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.4), blurRadius: 8)],
      ),
      child: const Icon(Icons.person, color: Colors.white, size: 22),
    );
  }
}

class _MarqueurMaladie extends StatelessWidget {
  final PointMaladie point;
  const _MarqueurMaladie({required this.point});

  @override
  Widget build(BuildContext context) {
    final couleur = _couleurPourMaladie(point.maladie);
    return Container(
      decoration: BoxDecoration(
        color: couleur,
        shape: BoxShape.circle,
        border: Border.all(
          color: point.estLocal ? Colors.blue : Colors.white,
          width: point.estLocal ? 3 : 2,
        ),
        boxShadow: [BoxShadow(color: couleur.withValues(alpha: 0.5), blurRadius: 6)],
      ),
      child: Icon(
        _iconePourMaladie(point.maladie),
        color: Colors.white,
        size: 20,
      ),
    );
  }
}

class _BarreFiltres extends StatelessWidget {
  final String filtreActif;
  final bool afficherSains;
  final ValueChanged<String> onFiltreChange;
  final VoidCallback onToggleSains;

  const _BarreFiltres({
    required this.filtreActif,
    required this.afficherSains,
    required this.onFiltreChange,
    required this.onToggleSains,
  });

  @override
  Widget build(BuildContext context) {
    final filtres = ['Tous', 'Pommier', 'Maïs', 'Vigne', 'Tomate'];
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: filtres.map((f) {
                    final actif = filtreActif == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => onFiltreChange(f),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: actif
                                ? (_couleursCulture[f] ?? Colors.green)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            f,
                            style: TextStyle(
                              color: actif ? Colors.white : Colors.black87,
                              fontSize: 13,
                              fontWeight: actif
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            // Toggle sains
            IconButton(
              icon: Icon(
                afficherSains ? Icons.visibility : Icons.visibility_off,
                size: 20,
                color: afficherSains ? Colors.green : Colors.grey,
              ),
              tooltip: afficherSains ? 'Masquer sains' : 'Afficher sains',
              onPressed: onToggleSains,
            ),
          ],
        ),
      ),
    );
  }
}

class _PanneauAlertes extends StatelessWidget {
  final List<AlerteEpidemie> alertes;
  const _PanneauAlertes({required this.alertes});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.shade50,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.red.shade300, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded,
                  color: Colors.red.shade700, size: 20),
              const SizedBox(width: 6),
              Text(
                '⚠ Alerte épidémie à proximité',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                  fontSize: 14,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            ...alertes.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.circle, size: 8, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${a.maladie} — ${a.nombreCas} cas à ${a.distanceKm.toStringAsFixed(1)} km',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ]),
                )),
          ],
        ),
      ),
    );
  }
}

class _BadgeStats extends StatelessWidget {
  final int total;
  final int malades;
  const _BadgeStats({required this.total, required this.malades});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$total signalement${total > 1 ? 's' : ''}',
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            Text(
              '$malades malade${malades > 1 ? 's' : ''} · ${total - malades} sain${(total - malades) > 1 ? 's' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icone;
  final String texte;
  const _InfoRow({required this.icone, required this.texte});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icone, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Expanded(
            child: Text(texte, style: const TextStyle(fontSize: 14))),
      ]),
    );
  }
}