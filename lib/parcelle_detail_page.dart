// lib/parcelle_detail_page.dart
// Page détail d'une parcelle après scan QR :
// historique analyses, traitements, météo, graphique santé

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'database_helper.dart';
import 'parcelle_helper.dart';
import 'meteo_service.dart';
import 'package:geolocator/geolocator.dart' as geo;

// ─────────────────────────────────────────────
// MODÈLE DONNÉES GRAPHIQUE SANTÉ
// ─────────────────────────────────────────────
class _PointSante {
  final DateTime date;
  final double   scoresSante; // 0–100
  _PointSante(this.date, this.scoresSante);
}

// ═════════════════════════════════════════════
// PAGE DÉTAIL PARCELLE
// ═════════════════════════════════════════════
class ParcelleDetailPage extends StatefulWidget {
  final Parcelle parcelle;
  const ParcelleDetailPage({super.key, required this.parcelle});

  @override
  State<ParcelleDetailPage> createState() => _ParcelleDetailPageState();
}

class _ParcelleDetailPageState extends State<ParcelleDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List<Analyse>       _analyses      = [];
  List<_PointSante>   _courbesSante  = [];
  List<AlerteMaladie> _alertesMeteo  = [];
  DonneesMeteo?       _meteo;
  bool                _chargement    = true;

  // Stats
  int    _totalAnalyses   = 0;
  int    _totalMalades    = 0;
  double _scoreSante      = 100;
  String _derniereMaladie = '—';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _charger();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  // ─────────────────────────────────────────
  // CHARGEMENT
  // ─────────────────────────────────────────
  Future<void> _charger() async {
    setState(() => _chargement = true);

    // Analyses depuis SQLite filtrées par culture de la parcelle
    final toutes  = await DatabaseHelper.instance.getAllAnalyses();
    final filtrees = toutes.where((a) =>
        a.maladie.toLowerCase().contains(
            widget.parcelle.culture.toLowerCase()) ||
        widget.parcelle.culture == 'Autre').toList();

    // Météo si GPS disponible
    if (widget.parcelle.latitude != null) {
      try {
        final pos = geo.Position(
          latitude:        widget.parcelle.latitude!,
          longitude:       widget.parcelle.longitude!,
          timestamp:       DateTime.now(),
          accuracy:        0, altitude: 0, altitudeAccuracy: 0,
          heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
        );
        _meteo        = await MeteoService.obtenirMeteo(pos);
        _alertesMeteo = MeteoService.calculerAlertes(_meteo!);
      } catch (_) {}
    }

    _calculerStats(filtrees);
    setState(() { _analyses = filtrees; _chargement = false; });
  }

  void _calculerStats(List<Analyse> analyses) {
    _totalAnalyses = analyses.length;
    _totalMalades  = analyses.where((a) => !a.estSain).length;
    _scoreSante    = _totalAnalyses > 0
        ? ((_totalAnalyses - _totalMalades) / _totalAnalyses * 100)
        : 100;

    final malades = analyses.where((a) => !a.estSain).toList();
    if (malades.isNotEmpty) _derniereMaladie = malades.first.maladie;

    // Courbe santé par semaine
    final Map<String, List<Analyse>> parSemaine = {};
    for (final a in analyses) {
      try {
        DateTime date;
        if (a.date.contains('/')) {
          final p = a.date.split(' ')[0].split('/');
          date = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
        } else {
          date = DateTime.parse(a.date);
        }
        final debut = date.subtract(Duration(days: date.weekday - 1));
        final cle   = '${debut.year}-${debut.month.toString().padLeft(2,'0')}-${debut.day.toString().padLeft(2,'0')}';
        parSemaine.putIfAbsent(cle, () => []).add(a);
      } catch (_) {}
    }

    final entries = parSemaine.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    _courbesSante = entries.map((e) {
      final sains = e.value.where((a) => a.estSain).length;
      final score = e.value.isEmpty ? 100.0 : (sains / e.value.length * 100);
      return _PointSante(DateTime.parse(e.key), score);
    }).toList();
  }

  // ─────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F0),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : NestedScrollView(
              headerSliverBuilder: (_, __) => [
                SliverAppBar(
                  expandedHeight: 220,
                  pinned: true,
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  flexibleSpace: FlexibleSpaceBar(
                    background: _EnTeteParcelle(
                      parcelle: widget.parcelle,
                      scoreSante: _scoreSante,
                    ),
                  ),
                  title: Text(widget.parcelle.nom,
                      style: const TextStyle(color: Colors.white)),
                  bottom: TabBar(
                    controller: _tabs,
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    tabs: const [
                      Tab(icon: Icon(Icons.history),     text: 'Historique'),
                      Tab(icon: Icon(Icons.show_chart),  text: 'Santé'),
                      Tab(icon: Icon(Icons.wb_sunny),    text: 'Météo'),
                    ],
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabs,
                children: [
                  _OngletHistorique(analyses: _analyses),
                  _OngletSante(
                    scoreSante:      _scoreSante,
                    totalAnalyses:   _totalAnalyses,
                    totalMalades:    _totalMalades,
                    derniereMaladie: _derniereMaladie,
                    courbesSante:    _courbesSante,
                  ),
                  _OngletMeteo(
                    meteo:     _meteo,
                    alertes:   _alertesMeteo,
                    latitude:  widget.parcelle.latitude,
                    longitude: widget.parcelle.longitude,
                  ),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────
// EN-TÊTE PARCELLE
// ─────────────────────────────────────────────
class _EnTeteParcelle extends StatelessWidget {
  final Parcelle parcelle;
  final double   scoreSante;
  const _EnTeteParcelle({required this.parcelle, required this.scoreSante});

  Color get _couleurScore => scoreSante >= 70
      ? Colors.green
      : scoreSante >= 40
          ? Colors.orange
          : Colors.red;

  @override
  Widget build(BuildContext context) {
    final aPhoto = parcelle.photoPath != null && !kIsWeb;
    return Stack(fit: StackFit.expand, children: [
      // Fond : photo ou dégradé
      aPhoto
          ? Image.file(File(parcelle.photoPath!), fit: BoxFit.cover)
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade800, Colors.teal.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
      // Overlay sombre
      Container(color: Colors.black.withValues(alpha: 0.45)),
      // Contenu
      Positioned(
        bottom: 60, left: 20, right: 20,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(parcelle.culture,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
              const SizedBox(height: 6),
              if (parcelle.superficie != null)
                Text('${parcelle.superficie!.toStringAsFixed(2)} ha',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              if (parcelle.latitude != null)
                Text('📍 ${parcelle.latitude!.toStringAsFixed(3)}, ${parcelle.longitude!.toStringAsFixed(3)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ),
          // Badge santé
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _couleurScore.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: _couleurScore, width: 2),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${scoreSante.toStringAsFixed(0)}%',
                  style: TextStyle(
                      color: _couleurScore,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              Text('santé', style: TextStyle(color: _couleurScore, fontSize: 10)),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════
// ONGLET 1 — HISTORIQUE DES ANALYSES
// ═════════════════════════════════════════════
class _OngletHistorique extends StatelessWidget {
  final List<Analyse> analyses;
  const _OngletHistorique({required this.analyses});

  @override
  Widget build(BuildContext context) {
    if (analyses.isEmpty) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.history, size: 60, color: Colors.grey),
          SizedBox(height: 12),
          Text('Aucune analyse pour cette culture',
              style: TextStyle(color: Colors.grey, fontSize: 15)),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: analyses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final a = analyses[i];
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: a.estSain
                  ? Colors.green.shade200
                  : Colors.red.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(
                  a.estSain ? Icons.check_circle : Icons.warning_rounded,
                  color: a.estSain ? Colors.green : Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(a.maladie,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: a.estSain
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(a.confiance * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 12,
                        color: a.estSain ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.calendar_today,
                    size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(a.date,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 12),
                const Icon(Icons.language, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text(a.langue,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
              ]),
              if (!a.estSain && a.top3.isNotEmpty &&
                  a.top3 != '[]') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(a.top3,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
                ),
              ],
              // Aperçu conseils (3 lignes)
              if (a.conseils.isNotEmpty &&
                  a.conseils != 'Déclaration manuelle par l\'agriculteur.') ...[
                const SizedBox(height: 8),
                Text(a.conseils,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black87)),
              ],
              if (a.conseils == 'Déclaration manuelle par l\'agriculteur.') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('📍 Déclaration manuelle sur la carte',
                      style: TextStyle(fontSize: 11, color: Colors.deepOrange)),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════
// ONGLET 2 — GRAPHIQUE SANTÉ
// ═════════════════════════════════════════════
class _OngletSante extends StatelessWidget {
  final double            scoreSante;
  final int               totalAnalyses;
  final int               totalMalades;
  final String            derniereMaladie;
  final List<_PointSante> courbesSante;

  const _OngletSante({
    required this.scoreSante,
    required this.totalAnalyses,
    required this.totalMalades,
    required this.derniereMaladie,
    required this.courbesSante,
  });

  @override
  Widget build(BuildContext context) {
    final couleur = scoreSante >= 70
        ? Colors.green
        : scoreSante >= 40 ? Colors.orange : Colors.red;
    final totalSains = totalAnalyses - totalMalades;

    if (totalAnalyses == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.show_chart, size: 60, color: Colors.grey),
            SizedBox(height: 12),
            Text('Aucune donnée de santé disponible pour cette parcelle.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 15)),
          ]),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [

        // ── Jauge santé ───────────────────────
        Container(
          height: 200,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.all(12),
          child: SfRadialGauge(
            axes: [
              RadialAxis(
                minimum: 0, maximum: 100,
                startAngle: 180, endAngle: 0,
                ranges: [
                  GaugeRange(startValue: 0,  endValue: 40,
                      color: Colors.red,    startWidth: 18, endWidth: 18),
                  GaugeRange(startValue: 40, endValue: 70,
                      color: Colors.orange, startWidth: 18, endWidth: 18),
                  GaugeRange(startValue: 70, endValue: 100,
                      color: Colors.green,  startWidth: 18, endWidth: 18),
                ],
                pointers: [
                  NeedlePointer(
                    value: scoreSante,
                    needleColor: Colors.black87,
                    knobStyle: const KnobStyle(
                        color: Colors.black87, knobRadius: 0.08),
                  ),
                ],
                annotations: [
                  GaugeAnnotation(
                    positionFactor: 0.5, angle: 90,
                    widget: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${scoreSante.toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: couleur)),
                      Text('Indice de santé',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── KPIs ──────────────────────────────
        Row(children: [
          _KpiCard(valeur: '$totalAnalyses', label: 'Analyses', couleur: Colors.blue,  icone: Icons.analytics),
          const SizedBox(width: 10),
          _KpiCard(valeur: '$totalSains',    label: 'Saines',   couleur: Colors.green, icone: Icons.check_circle),
          const SizedBox(width: 10),
          _KpiCard(valeur: '$totalMalades',  label: 'Malades',  couleur: Colors.red,   icone: Icons.warning),
        ]),

        const SizedBox(height: 12),

        // Dernière maladie
        if (derniereMaladie != '—')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(children: [
              const Text('🦠', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Dernière maladie détectée',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text(derniereMaladie,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ])),
            ]),
          ),

        const SizedBox(height: 16),

        // ── Courbe évolution santé ─────────────
        if (courbesSante.length >= 2) ...[
          const Align(alignment: Alignment.centerLeft,
            child: Text('Évolution du score de santé',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
          const SizedBox(height: 8),
          Container(
            height: 220,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.all(12),
            child: SfCartesianChart(
              primaryXAxis: DateTimeAxis(
                intervalType: DateTimeIntervalType.days,
                labelStyle: const TextStyle(fontSize: 10),
                labelRotation: -30,
              ),
              primaryYAxis: NumericAxis(
                minimum: 0, maximum: 100,
                title: AxisTitle(text: '%'),
              ),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: [
                SplineAreaSeries<_PointSante, DateTime>(
                  dataSource:   courbesSante,
                  xValueMapper: (d, _) => d.date,
                  yValueMapper: (d, _) => d.scoresSante,
                  name:         'Santé (%)',
                  color:        Colors.green.withValues(alpha: 0.25),
                  borderColor:  Colors.green,
                  borderWidth:  2,
                  markerSettings: const MarkerSettings(isVisible: true),
                ),
              ],
            ),
          ),
        ] else
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: const Center(
              child: Text(
                'Pas assez de données pour afficher la courbe.\nEffectuez au moins 2 analyses sur des semaines différentes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ),

        const SizedBox(height: 20),
      ]),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String   valeur;
  final String   label;
  final Color    couleur;
  final IconData icone;
  const _KpiCard({required this.valeur, required this.label,
      required this.couleur, required this.icone});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: couleur.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Icon(icone, color: couleur, size: 22),
          const SizedBox(height: 4),
          Text(valeur, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: couleur)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// ONGLET 3 — MÉTÉO DE LA PARCELLE
// ═════════════════════════════════════════════
class _OngletMeteo extends StatelessWidget {
  final DonneesMeteo?       meteo;
  final List<AlerteMaladie> alertes;
  final double?             latitude;
  final double?             longitude;

  const _OngletMeteo({
    required this.meteo,
    required this.alertes,
    required this.latitude,
    required this.longitude,
  });

  @override
  Widget build(BuildContext context) {
    if (latitude == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.location_off, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('Aucune localisation GPS pour cette parcelle.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center),
            SizedBox(height: 8),
            Text('Modifiez la parcelle pour ajouter ses coordonnées.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center),
          ]),
        ),
      );
    }

    if (meteo == null) {
      return const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text('Données météo indisponibles.\nVérifiez votre connexion.',
              style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
        ]),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [

        // ── Carte météo ───────────────────────
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade700, Colors.teal.shade500],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${meteo!.temperatureActuelle.toStringAsFixed(1)}°C',
                  style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w300)),
              Text(meteo!.emoji, style: const TextStyle(fontSize: 40)),
            ]),
            Text(meteo!.description,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _MetriqueMeteo('💧', '${meteo!.humiditeActuelle.toStringAsFixed(0)}%', 'Humidité'),
              _MetriqueMeteo('🌧️', '${meteo!.precipitations.toStringAsFixed(1)}mm', 'Pluie'),
              _MetriqueMeteo('💨', '${meteo!.vitesseVent.toStringAsFixed(0)}km/h', 'Vent'),
            ]),
          ]),
        ),

        const SizedBox(height: 16),

        // ── Alertes maladies ──────────────────
        if (alertes.isNotEmpty) ...[
          const Align(alignment: Alignment.centerLeft,
            child: Text('⚠️ Risques pour cette parcelle',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
          const SizedBox(height: 8),
          ...alertes.map((a) {
            final couleur = a.niveau == NiveauRisque.critique ? Colors.red
                : a.niveau == NiveauRisque.eleve ? Colors.orange
                : Colors.amber.shade700;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: couleur.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: couleur.withValues(alpha: 0.4)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(a.maladie, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(8)),
                      child: Text('${a.niveau.emoji} ${a.niveau.label}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(a.raison, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Text('💡', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(a.conseil, style: const TextStyle(fontSize: 12))),
                    ]),
                  ),
                ])),
              ]),
            );
          }),
        ] else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: const Row(children: [
              Text('✅', style: TextStyle(fontSize: 24)),
              SizedBox(width: 12),
              Expanded(child: Text('Aucun risque météo détecté pour cette parcelle.',
                  style: TextStyle(color: Colors.green))),
            ]),
          ),

        // ── Prévisions 7 jours ────────────────
        const SizedBox(height: 16),
        const Align(alignment: Alignment.centerLeft,
          child: Text('Prévisions 7 jours',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: meteo!.previsions.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (_, i) {
              final p    = meteo!.previsions[i];
              final date = DateTime.tryParse(p.date);
              const jours = ['Lu','Ma','Me','Je','Ve','Sa','Di'];
              final jour  = date != null ? jours[date.weekday - 1] : 'J${i+1}';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  SizedBox(width: 32, child: Text(jour, style: TextStyle(fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal))),
                  Text(p.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.precipitations > 0 ? '${p.precipitations.toStringAsFixed(1)} mm' : 'Sec',
                      style: TextStyle(fontSize: 12, color: p.precipitations > 5 ? Colors.blue : Colors.grey),
                    ),
                  ),
                  Text('${p.tempMin.toStringAsFixed(0)}° / ${p.tempMax.toStringAsFixed(0)}°',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                ]),
              );
            },
          ),
        ),
        const SizedBox(height: 30),
      ]),
    );
  }
}

class _MetriqueMeteo extends StatelessWidget {
  final String emoji, valeur, label;
  const _MetriqueMeteo(this.emoji, this.valeur, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 2),
      Text(valeur, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
    ]);
  }
}