
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'database_helper.dart';
import 'meteo_service.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';
import 'package:intl/intl.dart';
class DonneesCamembert {
  final String label;
  final int    valeur;
  final Color  couleur;
  DonneesCamembert(this.label, this.valeur, this.couleur);
}

class DonneesBarres {
  final String culture;
  final int    malades;
  final int    sains;
  DonneesBarres(this.culture, this.malades, this.sains);
}

class DonneesCourbe {
  final DateTime date;
  final int      total;
  final int      malades;
  DonneesCourbe(this.date, this.total, this.malades);
}

class DonneesCarteThermique {
  final String jour;
  final String parametre;
  final double valeur;       // 0.0 → 1.0 (risque normalisé)
  final Color  couleur;
  DonneesCarteThermique(this.jour, this.parametre, this.valeur, this.couleur);
}

// ─────────────────────────────────────────────
// COULEURS PAR CULTURE
// ─────────────────────────────────────────────
const Map<String, Color> _couleursCulture = {
  'Pommier': Color(0xFFE53935),
  'Maïs':    Color(0xFFFDD835),
  'Vigne':   Color(0xFF8E24AA),
  'Tomate':  Color(0xFFFF7043),
  'Autre':   Color(0xFF78909C),
};

// ═════════════════════════════════════════════
// PAGE TABLEAU DE BORD
// ═════════════════════════════════════════════
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Données analyses
  List<Analyse>             _analyses      = [];
  List<DonneesCamembert>    _dataCamembert = [];
  List<DonneesBarres>       _dataBarres    = [];
  List<DonneesCourbe>       _dataCourbe    = [];

  // Données météo
  List<PrevisionJour>          _previsions   = [];
  List<DonneesCarteThermique>  _carteTherm   = [];

  bool _chargement = true;

  // KPIs
  int    _totalAnalyses   = 0;
  int    _totalMalades    = 0;
  int    _totalSains      = 0;
  double _tauxDetection   = 0;
  String _maladieTop      = '—';
  String _cultureTop      = '—';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _chargerDonnees();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // CHARGEMENT ET CALCUL DES DONNÉES
  // ─────────────────────────────────────────────
  Future<void> _chargerDonnees() async {
    setState(() => _chargement = true);

    // 1. Analyses SQLite
    final analyses = await DatabaseHelper.instance.getAllAnalyses();

    // 2. Météo (best-effort)
    List<PrevisionJour> previsions = [];
    try {
      final geo.Position? pos = await _obtenirPosition();
      if (pos != null) {
        final meteo = await MeteoService.obtenirMeteo(pos);
        previsions  = meteo.previsions;
      }
    } catch (_) {}

    // 3. Calculs statistiques
    _calculerStats(analyses);
    _calculerCamembert(analyses);
    _calculerBarres(analyses);
    _calculerCourbe(analyses);
    _calculerCarteThermique(previsions);

    setState(() {
      _analyses    = analyses;
      _previsions  = previsions;
      _chargement  = false;
    });
  }

  Future<geo.Position?> _obtenirPosition() async {
    try {
      if (!await geo.Geolocator.isLocationServiceEnabled()) return null;
      geo.LocationPermission p = await geo.Geolocator.checkPermission();
      if (p == geo.LocationPermission.denied) {
        p = await geo.Geolocator.requestPermission();
        if (p == geo.LocationPermission.denied) return null;
      }
      if (p == geo.LocationPermission.deniedForever) return null;
      return await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.low,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) { return null; }
  }

  // ── KPIs ────────────────────────────────────
  void _calculerStats(List<Analyse> analyses) {
    _totalAnalyses = analyses.length;
    _totalSains    = analyses.where((a) => a.estSain).length;
    _totalMalades  = _totalAnalyses - _totalSains;
    _tauxDetection = _totalAnalyses > 0
        ? (_totalMalades / _totalAnalyses * 100)
        : 0;

    // Maladie la plus fréquente
    final Map<String, int> comptMaladies = {};
    final Map<String, int> comptCultures = {};
    for (final a in analyses) {
      if (!a.estSain) {
        comptMaladies[a.maladie] = (comptMaladies[a.maladie] ?? 0) + 1;
        final culture = a.maladie.split('—').first.trim();
        comptCultures[culture] = (comptCultures[culture] ?? 0) + 1;
      }
    }
    if (comptMaladies.isNotEmpty) {
      _maladieTop = comptMaladies.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
    }
    if (comptCultures.isNotEmpty) {
      _cultureTop = comptCultures.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
    }
  }

  // ── Camembert maladies ───────────────────────
  void _calculerCamembert(List<Analyse> analyses) {
    final Map<String, int> compteur = {};
    for (final a in analyses) {
      final label = a.estSain ? 'Sain' : a.maladie;
      compteur[label] = (compteur[label] ?? 0) + 1;
    }

    final couleurs = [
      const Color(0xFF4CAF50), const Color(0xFFE53935),
      const Color(0xFF8E24AA), const Color(0xFFFF7043),
      const Color(0xFF1E88E5), const Color(0xFFFDD835),
      const Color(0xFF00ACC1), const Color(0xFF43A047),
    ];

    final entries = compteur.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    _dataCamembert = entries.asMap().entries.map((e) {
      final idx = e.key % couleurs.length;
      return DonneesCamembert(e.value.key, e.value.value, couleurs[idx]);
    }).toList();
  }

  // ── Barres groupées par culture ──────────────
  void _calculerBarres(List<Analyse> analyses) {
    final Map<String, Map<String, int>> parCulture = {};
    for (final a in analyses) {
      final culture = a.maladie.contains('—')
          ? a.maladie.split('—').first.trim()
          : 'Autre';
      parCulture.putIfAbsent(culture, () => {'malades': 0, 'sains': 0});
      if (a.estSain) {
        parCulture[culture]!['sains'] = parCulture[culture]!['sains']! + 1;
      } else {
        parCulture[culture]!['malades'] = parCulture[culture]!['malades']! + 1;
      }
    }
    _dataBarres = parCulture.entries
        .map((e) => DonneesBarres(e.key, e.value['malades']!, e.value['sains']!))
        .toList();
  }

  // ── Courbe temporelle ────────────────────────
  void _calculerCourbe(List<Analyse> analyses) {
    if (analyses.isEmpty) { _dataCourbe = []; return; }

    // Regrouper par semaine
    final Map<String, List<Analyse>> parSemaine = {};
    for (final a in analyses) {
      try {
        // Accepte formats "dd/MM/yyyy HH:mm" et ISO
        DateTime date;
        if (a.date.contains('/')) {
          final parts = a.date.split(' ')[0].split('/');
          date = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        } else {
          date = DateTime.parse(a.date);
        }
        // Clé = début de semaine (lundi)
        final debutSemaine = date.subtract(Duration(days: date.weekday - 1));
        final cle = '${debutSemaine.year}-${debutSemaine.month.toString().padLeft(2,'0')}-${debutSemaine.day.toString().padLeft(2,'0')}';
        parSemaine.putIfAbsent(cle, () => []).add(a);
      } catch (_) {}
    }

    final entries = parSemaine.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    _dataCourbe = entries.map((e) {
      final date    = DateTime.parse(e.key);
      final total   = e.value.length;
      final malades = e.value.where((a) => !a.estSain).length;
      return DonneesCourbe(date, total, malades);
    }).toList();
  }

  // ── Carte thermique météo ────────────────────
  void _calculerCarteThermique(List<PrevisionJour> previsions) {
    if (previsions.isEmpty) { _carteTherm = []; return; }

    _carteTherm = [];
    final jours = ['Lu', 'Ma', 'Me', 'Je', 'Ve', 'Sa', 'Di'];

    for (int i = 0; i < previsions.length && i < 7; i++) {
      final p    = previsions[i];
      final date = DateTime.tryParse(p.date);
      final jour = date != null ? jours[date.weekday - 1] : 'J${i+1}';

      // Température normalisée (0–1) entre 0°C et 40°C
      final normTemp = ((p.tempMax - 0) / 40).clamp(0.0, 1.0);
      // Humidité normalisée
      final normHum  = (p.humiditeMax / 100).clamp(0.0, 1.0);
      // Précipitations normalisées (0–20mm max)
      final normPluie = (p.precipitations / 20).clamp(0.0, 1.0);
      // Risque fongique combiné
      final risqueFongique = ((normHum * 0.5) + (normPluie * 0.3) +
          (normTemp > 0.4 && normTemp < 0.75 ? 0.2 : 0)).clamp(0.0, 1.0);

      Color couleurRisque(double v) {
        if (v < 0.25) return const Color(0xFF4CAF50);
        if (v < 0.50) return const Color(0xFFFDD835);
        if (v < 0.75) return const Color(0xFFFF7043);
        return const Color(0xFFE53935);
      }

      _carteTherm.addAll([
        DonneesCarteThermique(jour, 'Temp.', normTemp,
            Color.lerp(const Color(0xFF90CAF9), const Color(0xFFE53935), normTemp)!),
        DonneesCarteThermique(jour, 'Humidité', normHum,
            Color.lerp(const Color(0xFFE3F2FD), const Color(0xFF1565C0), normHum)!),
        DonneesCarteThermique(jour, 'Pluie', normPluie,
            Color.lerp(const Color(0xFFE8F5E9), const Color(0xFF0D47A1), normPluie)!),
        DonneesCarteThermique(jour, 'Risque', risqueFongique,
            couleurRisque(risqueFongique)),
      ]);
    }
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F0),
      appBar: AppBar(
        title: const Text('Tableau de bord', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _chargerDonnees,
            tooltip: 'Actualiser',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.bar_chart), text: 'Analyses'),
            Tab(icon: Icon(Icons.timeline), text: 'Tendances'),
            Tab(icon: Icon(Icons.thermostat), text: 'Météo'),
          ],
        ),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : _analyses.isEmpty
              ? _vueVide()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _OngletAnalyses(
                      totalAnalyses:  _totalAnalyses,
                      totalMalades:   _totalMalades,
                      totalSains:     _totalSains,
                      tauxDetection:  _tauxDetection,
                      maladieTop:     _maladieTop,
                      cultureTop:     _cultureTop,
                      dataCamembert:  _dataCamembert,
                      dataBarres:     _dataBarres,
                    ),
                    _OngletTendances(dataCourbe: _dataCourbe),
                    _OngletMeteo(
                      previsions:  _previsions,
                      carteTherm:  _carteTherm,
                    ),
                  ],
                ),
    );
  }

  Widget _vueVide() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Aucune donnée disponible',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('Analysez des plantes pour voir les statistiques',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// ONGLET 1 — ANALYSES
// ═════════════════════════════════════════════
class _OngletAnalyses extends StatelessWidget {
  final int    totalAnalyses;
  final int    totalMalades;
  final int    totalSains;
  final double tauxDetection;
  final String maladieTop;
  final String cultureTop;
  final List<DonneesCamembert> dataCamembert;
  final List<DonneesBarres>    dataBarres;

  const _OngletAnalyses({
    required this.totalAnalyses,
    required this.totalMalades,
    required this.totalSains,
    required this.tauxDetection,
    required this.maladieTop,
    required this.cultureTop,
    required this.dataCamembert,
    required this.dataBarres,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── KPIs ──────────────────────────────
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: [
              _CarteKpi(
                icone:   Icons.analytics,
                valeur:  '$totalAnalyses',
                label:   'Analyses totales',
                couleur: Colors.blue,
              ),
              _CarteKpi(
                icone:   Icons.warning_rounded,
                valeur:  '$totalMalades',
                label:   'Maladies détectées',
                couleur: Colors.red,
              ),
              _CarteKpi(
                icone:   Icons.check_circle,
                valeur:  '$totalSains',
                label:   'Plantes saines',
                couleur: Colors.green,
              ),
              _CarteKpi(
                icone:   Icons.percent,
                valeur:  '${tauxDetection.toStringAsFixed(1)}%',
                label:   'Taux de maladie',
                couleur: tauxDetection > 50 ? Colors.red : Colors.orange,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Top maladie / culture ─────────────
          Row(children: [
            Expanded(
              child: _CarteInfo(
                icone:   '🦠',
                titre:   'Maladie la + fréquente',
                valeur:  maladieTop.contains('—')
                    ? maladieTop.split('—').last.trim()
                    : maladieTop,
                couleur: Colors.red.shade50,
                bordure: Colors.red.shade200,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _CarteInfo(
                icone:   '🌿',
                titre:   'Culture la + touchée',
                valeur:  cultureTop,
                couleur: Colors.orange.shade50,
                bordure: Colors.orange.shade200,
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // ── Camembert ─────────────────────────
          const Text('Répartition des diagnostics',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            height: 300,
            decoration: _boxDeco(),
            padding: const EdgeInsets.all(12),
            child: SfCircularChart(
              legend: Legend(
                isVisible: true,
                position: LegendPosition.bottom,
                overflowMode: LegendItemOverflowMode.wrap,
                textStyle: const TextStyle(fontSize: 11),
              ),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CircularSeries>[
                DoughnutSeries<DonneesCamembert, String>(
                  dataSource:   dataCamembert,
                  xValueMapper: (d, _) => d.label.contains('—')
                      ? d.label.split('—').last.trim()
                      : d.label,
                  yValueMapper: (d, _) => d.valeur,
                  pointColorMapper: (d, _) => d.couleur,
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: true,
                    labelPosition: ChartDataLabelPosition.outside,
                    textStyle: TextStyle(fontSize: 11),
                  ),
                  innerRadius: '55%',
                  animationDuration: 800,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Barres groupées par culture ────────
          const Text('Sains vs Malades par culture',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            height: 280,
            decoration: _boxDeco(),
            padding: const EdgeInsets.all(12),
            child: SfCartesianChart(
              primaryXAxis: CategoryAxis(
                labelStyle: const TextStyle(fontSize: 11),
              ),
              primaryYAxis: NumericAxis(
                title: AxisTitle(text: 'Nombre'),
              ),
              legend: Legend(isVisible: true),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CartesianSeries>[
                StackedBarSeries<DonneesBarres, String>(
                  dataSource:   dataBarres,
                  xValueMapper: (d, _) => d.culture,
                  yValueMapper: (d, _) => d.malades,
                  name:         'Malades',
                  color:        Colors.red.shade400,
                  borderRadius: const BorderRadius.only(
                    topLeft:  Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                StackedBarSeries<DonneesBarres, String>(
                  dataSource:   dataBarres,
                  xValueMapper: (d, _) => d.culture,
                  yValueMapper: (d, _) => d.sains,
                  name:         'Sains',
                  color:        Colors.green.shade400,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Jauge taux de maladie ─────────────
          const Text('Indice de santé des cultures',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            height: 200,
            decoration: _boxDeco(),
            padding: const EdgeInsets.all(12),
            child: SfRadialGauge(
              axes: <RadialAxis>[
                RadialAxis(
                  minimum: 0,
                  maximum: 100,
                  startAngle: 180,
                  endAngle: 0,
                  showLabels: true,
                  showTicks: true,
                  ranges: <GaugeRange>[
                    GaugeRange(startValue: 0,  endValue: 30,
                        color: Colors.green,  startWidth: 20, endWidth: 20),
                    GaugeRange(startValue: 30, endValue: 60,
                        color: Colors.orange, startWidth: 20, endWidth: 20),
                    GaugeRange(startValue: 60, endValue: 100,
                        color: Colors.red,    startWidth: 20, endWidth: 20),
                  ],
                  pointers: <GaugePointer>[
                    NeedlePointer(
                      value: tauxDetection,
                      needleColor: Colors.black87,
                      knobStyle: const KnobStyle(
                          color: Colors.black87, knobRadius: 0.08),
                    ),
                  ],
                  annotations: <GaugeAnnotation>[
                    GaugeAnnotation(
                      positionFactor: 0.5,
                      angle: 90,
                      widget: Text(
                        '${tauxDetection.toStringAsFixed(1)}%\nde maladies',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: tauxDetection > 60
                              ? Colors.red
                              : tauxDetection > 30
                                  ? Colors.orange
                                  : Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// ONGLET 2 — TENDANCES
// ═════════════════════════════════════════════
class _OngletTendances extends StatelessWidget {
  final List<DonneesCourbe> dataCourbe;
  const _OngletTendances({required this.dataCourbe});

  @override
  Widget build(BuildContext context) {
    if (dataCourbe.isEmpty) {
      return const Center(
        child: Text('Pas assez de données pour afficher les tendances.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Courbe analyses par semaine ────────
          const Text('Évolution hebdomadaire',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            height: 280,
            decoration: _boxDeco(),
            padding: const EdgeInsets.all(12),
            child: SfCartesianChart(
              primaryXAxis: DateTimeAxis(
                intervalType: DateTimeIntervalType.days,
                dateFormat: DateFormat('dd/MM'),
                labelRotation: -30,
                labelStyle: const TextStyle(fontSize: 10),
              ),
              primaryYAxis: NumericAxis(
                title: AxisTitle(text: 'Analyses'),
                minimum: 0,
              ),
              legend: Legend(isVisible: true, position: LegendPosition.bottom),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CartesianSeries>[
                SplineAreaSeries<DonneesCourbe, DateTime>(
                  dataSource:   dataCourbe,
                  xValueMapper: (d, _) => d.date,
                  yValueMapper: (d, _) => d.total,
                  name:         'Total analyses',
                  color:        Colors.green.withValues(alpha: 0.3),
                  borderColor:  Colors.green,
                  borderWidth:  2,
                ),
                SplineSeries<DonneesCourbe, DateTime>(
                  dataSource:   dataCourbe,
                  xValueMapper: (d, _) => d.date,
                  yValueMapper: (d, _) => d.malades,
                  name:         'Maladies détectées',
                  color:        Colors.red,
                  width:        2,
                  markerSettings: const MarkerSettings(isVisible: true),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Courbe taux de maladie ─────────────
          const Text('Taux de maladie par semaine (%)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            height: 220,
            decoration: _boxDeco(),
            padding: const EdgeInsets.all(12),
            child: SfCartesianChart(
              primaryXAxis: DateTimeAxis(
                intervalType: DateTimeIntervalType.days,
                dateFormat: DateFormat('dd/MM'),
                labelRotation: -30,
                labelStyle: const TextStyle(fontSize: 10),
              ),
              primaryYAxis: NumericAxis(
                minimum: 0,
                maximum: 100,
                title: AxisTitle(text: '%'),
              ),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CartesianSeries>[
                SplineAreaSeries<DonneesCourbe, DateTime>(
                  dataSource:   dataCourbe,
                  xValueMapper: (d, _) => d.date,
                  yValueMapper: (d, _) => d.total > 0
                      ? (d.malades / d.total * 100).roundToDouble()
                      : 0,
                  name:         'Taux maladie',
                  color:        Colors.orange.withValues(alpha: 0.3),
                  borderColor:  Colors.orange,
                  borderWidth:  2,
                ),
              ],
              // Ligne de référence à 50%
              annotations: <CartesianChartAnnotation>[
                CartesianChartAnnotation(
                  widget: Container(
                    width: 300,
                    height: 1,
                    color: Colors.red.withValues(alpha: 0.4),
                  ),
                  coordinateUnit: CoordinateUnit.point,
                  x: dataCourbe.first.date,
                  y: 50,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Résumé textuel tendance ────────────
          _ResumeTendance(dataCourbe: dataCourbe),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _ResumeTendance extends StatelessWidget {
  final List<DonneesCourbe> dataCourbe;
  const _ResumeTendance({required this.dataCourbe});

  @override
  Widget build(BuildContext context) {
    if (dataCourbe.length < 2) return const SizedBox.shrink();

    final derniere  = dataCourbe.last;
    final avantDern = dataCourbe[dataCourbe.length - 2];
    final tauxDern  = derniere.total  > 0 ? derniere.malades  / derniere.total  : 0.0;
    final tauxAvant = avantDern.total > 0 ? avantDern.malades / avantDern.total : 0.0;
    final evolution = tauxDern - tauxAvant;
    final enHausse  = evolution > 0.05;
    final enBaisse  = evolution < -0.05;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: enHausse
            ? Colors.red.shade50
            : enBaisse
                ? Colors.green.shade50
                : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enHausse
              ? Colors.red.shade200
              : enBaisse
                  ? Colors.green.shade200
                  : Colors.blue.shade200,
        ),
      ),
      child: Row(
        children: [
          Text(
            enHausse ? '📈' : enBaisse ? '📉' : '➡️',
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enHausse
                      ? 'Tendance à la hausse'
                      : enBaisse
                          ? 'Tendance à la baisse'
                          : 'Situation stable',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  enHausse
                      ? 'Le taux de maladie augmente cette semaine. '
                        'Renforcez la surveillance de vos cultures.'
                      : enBaisse
                          ? 'Bonne nouvelle ! Le taux de maladie diminue. '
                            'Continuez vos pratiques actuelles.'
                          : 'Le taux de maladie est stable cette semaine.',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// ONGLET 3 — MÉTÉO / CARTE THERMIQUE
// ═════════════════════════════════════════════
class _OngletMeteo extends StatelessWidget {
  final List<PrevisionJour>          previsions;
  final List<DonneesCarteThermique>  carteTherm;
  const _OngletMeteo({required this.previsions, required this.carteTherm});

  @override
  Widget build(BuildContext context) {
    if (previsions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('Données météo indisponibles.\nActivez le GPS et vérifiez votre connexion.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Carte thermique ────────────────────
          const Text('Carte thermique des risques (7 jours)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
            'Plus la couleur est foncée, plus le risque est élevé.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: _boxDeco(),
            padding: const EdgeInsets.all(12),
            child: _CarteThermique(donnees: carteTherm),
          ),

          const SizedBox(height: 20),

          // ── Barres précipitations 7j ───────────
          const Text('Précipitations prévues (mm)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            height: 220,
            decoration: _boxDeco(),
            padding: const EdgeInsets.all(12),
            child: SfCartesianChart(
              primaryXAxis: CategoryAxis(
                labelStyle: const TextStyle(fontSize: 11),
              ),
              primaryYAxis: NumericAxis(
                title: AxisTitle(text: 'mm'),
                minimum: 0,
              ),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CartesianSeries>[
                ColumnSeries<PrevisionJour, String>(
                  dataSource:   previsions,
                  xValueMapper: (p, _) {
                    final d = DateTime.tryParse(p.date);
                    if (d == null) return p.date;
                    const j = ['Lu','Ma','Me','Je','Ve','Sa','Di'];
                    return j[d.weekday - 1];
                  },
                  yValueMapper:   (p, _) => p.precipitations,
                  name:           'Pluie (mm)',
                  pointColorMapper: (p, _) => p.precipitations > 10
                      ? Colors.blue.shade700
                      : p.precipitations > 5
                          ? Colors.blue.shade400
                          : Colors.blue.shade200,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: true,
                    textStyle: TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Courbe températures min/max ────────
          const Text('Températures min / max (°C)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            height: 220,
            decoration: _boxDeco(),
            padding: const EdgeInsets.all(12),
            child: SfCartesianChart(
              primaryXAxis: CategoryAxis(
                labelStyle: const TextStyle(fontSize: 11),
              ),
              primaryYAxis: NumericAxis(
                title: AxisTitle(text: '°C'),
              ),
              legend: Legend(isVisible: true, position: LegendPosition.bottom),
              tooltipBehavior: TooltipBehavior(enable: true),
              series: <CartesianSeries>[
                SplineSeries<PrevisionJour, String>(
                  dataSource:   previsions,
                  xValueMapper: (p, _) {
                    final d = DateTime.tryParse(p.date);
                    if (d == null) return p.date;
                    const j = ['Lu','Ma','Me','Je','Ve','Sa','Di'];
                    return j[d.weekday - 1];
                  },
                  yValueMapper: (p, _) => p.tempMax,
                  name:         'Temp. max',
                  color:        Colors.red.shade400,
                  width:        2,
                  markerSettings: const MarkerSettings(isVisible: true),
                ),
                SplineSeries<PrevisionJour, String>(
                  dataSource:   previsions,
                  xValueMapper: (p, _) {
                    final d = DateTime.tryParse(p.date);
                    if (d == null) return p.date;
                    const j = ['Lu','Ma','Me','Je','Ve','Sa','Di'];
                    return j[d.weekday - 1];
                  },
                  yValueMapper: (p, _) => p.tempMin,
                  name:         'Temp. min',
                  color:        Colors.blue.shade400,
                  width:        2,
                  markerSettings: const MarkerSettings(isVisible: true),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Légende carte thermique ────────────
          _LegendeCarteThermique(),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// WIDGET CARTE THERMIQUE CUSTOM
// ─────────────────────────────────────────────
class _CarteThermique extends StatelessWidget {
  final List<DonneesCarteThermique> donnees;
  const _CarteThermique({required this.donnees});

  @override
  Widget build(BuildContext context) {
    // Extraire jours et paramètres uniques
    final jours      = donnees.map((d) => d.jour).toSet().toList();
    final parametres = ['Temp.', 'Humidité', 'Pluie', 'Risque'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // En-tête colonnes (jours)
        Row(children: [
          const SizedBox(width: 70),
          ...jours.map((j) => Expanded(
            child: Center(
              child: Text(j,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          )),
        ]),
        const SizedBox(height: 6),
        // Lignes (paramètres)
        ...parametres.map((param) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              SizedBox(
                width: 70,
                child: Text(param,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ),
              ...jours.map((jour) {
                final cellule = donnees.firstWhere(
                  (d) => d.jour == jour && d.parametre == param,
                  orElse: () => DonneesCarteThermique(jour, param, 0, Colors.grey.shade200),
                );
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 36,
                    decoration: BoxDecoration(
                      color: cellule.couleur,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        _valeurAffichee(param, cellule.valeur),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: cellule.valeur > 0.5
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ]),
          );
        }),
      ],
    );
  }

  String _valeurAffichee(String param, double valeur) {
    switch (param) {
      case 'Temp.':    return '${(valeur * 40).toStringAsFixed(0)}°';
      case 'Humidité': return '${(valeur * 100).toStringAsFixed(0)}%';
      case 'Pluie':    return '${(valeur * 20).toStringAsFixed(0)}mm';
      case 'Risque':
        if (valeur < 0.25) return '🟢';
        if (valeur < 0.50) return '🟡';
        if (valeur < 0.75) return '🟠';
        return '🔴';
      default: return '';
    }
  }
}

class _LegendeCarteThermique extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Légende — Risque fongique',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ItemLegende('🟢', 'Faible',    Colors.green.shade100),
              _ItemLegende('🟡', 'Modéré',    Colors.amber.shade100),
              _ItemLegende('🟠', 'Élevé',     Colors.orange.shade100),
              _ItemLegende('🔴', 'Critique',  Colors.red.shade100),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemLegende extends StatelessWidget {
  final String emoji;
  final String label;
  final Color  couleur;
  const _ItemLegende(this.emoji, this.label, this.couleur);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$emoji $label', style: const TextStyle(fontSize: 12)),
    );
  }
}

// ─────────────────────────────────────────────
// WIDGETS RÉUTILISABLES
// ─────────────────────────────────────────────
class _CarteKpi extends StatelessWidget {
  final IconData icone;
  final String   valeur;
  final String   label;
  final Color    couleur;
  const _CarteKpi({
    required this.icone,
    required this.valeur,
    required this.label,
    required this.couleur,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: couleur.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
        border: Border.all(color: couleur.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icone, color: couleur, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(valeur,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: couleur)),
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ]),
    );
  }
}

class _CarteInfo extends StatelessWidget {
  final String icone;
  final String titre;
  final String valeur;
  final Color  couleur;
  final Color  bordure;
  const _CarteInfo({
    required this.icone,
    required this.titre,
    required this.valeur,
    required this.couleur,
    required this.bordure,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: couleur,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icone, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(titre,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(valeur,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

BoxDecoration _boxDeco() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(16),
  boxShadow: [
    BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 8,
        offset: const Offset(0, 2)),
  ],
);

// Formateur de date simple sans intl
class _DateFormat {
  String call(DateTime date) =>
      '${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}';
}