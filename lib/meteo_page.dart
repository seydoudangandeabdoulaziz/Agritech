// lib/meteo_page.dart
// Page météo dédiée avec conditions actuelles, prévisions 7 jours
// et alertes de risque de maladies selon les conditions climatiques

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'meteo_service.dart';

class MeteoPage extends StatefulWidget {
  const MeteoPage({super.key});

  @override
  State<MeteoPage> createState() => _MeteoPageState();
}

class _MeteoPageState extends State<MeteoPage> {
  DonneesMeteo?        _meteo;
  List<AlerteMaladie>  _alertes = [];
  bool                 _chargement = true;
  String?              _erreur;

  @override
  void initState() {
    super.initState();
    _chargerMeteo();
  }

  Future<void> _chargerMeteo() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      final position = await _obtenirPosition();
      if (position == null) {
        setState(() {
          _erreur     = 'GPS indisponible.\nActivez la localisation pour obtenir la météo locale.';
          _chargement = false;
        });
        return;
      }
      final meteo   = await MeteoService.obtenirMeteo(position);
      final alertes = MeteoService.calculerAlertes(meteo);
      setState(() {
        _meteo      = meteo;
        _alertes    = alertes;
        _chargement = false;
      });
    } catch (e) {
      setState(() {
        _erreur     = 'Impossible de charger la météo.\nVérifiez votre connexion internet.\n\n$e';
        _chargement = false;
      });
    }
  }

  Future<Position?> _obtenirPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
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
    } catch (_) { return null; }
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F0),
      appBar: AppBar(
        title: const Text('Météo & Prévention', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _chargerMeteo,
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _chargement
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.green),
                  SizedBox(height: 16),
                  Text('Chargement de la météo...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : _erreur != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(_erreur!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey, fontSize: 15)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _chargerMeteo,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _chargerMeteo,
                  color: Colors.green,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Carte météo actuelle ──────────────
                        _CarteMeteoActuelle(meteo: _meteo!),
                        const SizedBox(height: 16),

                        // ── Alertes maladies ──────────────────
                        _SectionAlertesMaladies(alertes: _alertes),
                        const SizedBox(height: 16),

                        // ── Prévisions 7 jours ────────────────
                        _SectionPrevisions(previsions: _meteo!.previsions),
                        const SizedBox(height: 16),

                        // ── Conseils généraux du jour ─────────
                        _SectionConseilsGeneraux(meteo: _meteo!),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
    );
  }
}

// ═════════════════════════════════════════════
// CARTE MÉTÉO ACTUELLE
// ═════════════════════════════════════════════
class _CarteMeteoActuelle extends StatelessWidget {
  final DonneesMeteo meteo;
  const _CarteMeteoActuelle({required this.meteo});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade700, Colors.teal.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Conditions actuelles',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('Ma localisation',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              Text(meteo.emoji, style: const TextStyle(fontSize: 40)),
            ],
          ),

          const SizedBox(height: 16),

          // Température principale
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${meteo.temperatureActuelle.toStringAsFixed(1)}°',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.w300),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 4),
                child: Text(
                  meteo.description,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            ],
          ),

          Text(
            'Min ${meteo.temperatureMin.toStringAsFixed(0)}° / Max ${meteo.temperatureMax.toStringAsFixed(0)}°',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),

          const SizedBox(height: 16),
          const Divider(color: Colors.white30),
          const SizedBox(height: 12),

          // Métriques agricoles
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MetriqueMeteo(
                icone: Icons.water_drop,
                valeur: '${meteo.humiditeActuelle.toStringAsFixed(0)}%',
                label: 'Humidité',
              ),
              _MetriqueMeteo(
                icone: Icons.umbrella,
                valeur: '${meteo.precipitations.toStringAsFixed(1)} mm',
                label: 'Précip.',
              ),
              _MetriqueMeteo(
                icone: Icons.air,
                valeur: '${meteo.vitesseVent.toStringAsFixed(0)} km/h',
                label: 'Vent',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetriqueMeteo extends StatelessWidget {
  final IconData icone;
  final String   valeur;
  final String   label;
  const _MetriqueMeteo({
    required this.icone,
    required this.valeur,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icone, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(valeur,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }
}

// ═════════════════════════════════════════════
// SECTION ALERTES MALADIES
// ═════════════════════════════════════════════
class _SectionAlertesMaladies extends StatelessWidget {
  final List<AlerteMaladie> alertes;
  const _SectionAlertesMaladies({required this.alertes});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('🌡️ Risques météo-maladies',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          if (alertes.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: alertes.any((a) => a.niveau == NiveauRisque.critique)
                    ? Colors.red
                    : Colors.orange,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${alertes.length} alerte${alertes.length > 1 ? 's' : ''}',
                style: const TextStyle(color: Colors.white,
                    fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
        ]),
        const SizedBox(height: 10),

        if (alertes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: const Row(children: [
              Text('✅', style: TextStyle(fontSize: 24)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Conditions favorables',
                        style: TextStyle(fontWeight: FontWeight.bold,
                            color: Colors.green)),
                    Text('Aucun risque météorologique détecté pour vos cultures.',
                        style: TextStyle(fontSize: 13, color: Colors.green)),
                  ],
                ),
              ),
            ]),
          )
        else
          ...alertes.map((alerte) => _CarteAlerte(alerte: alerte)),
      ],
    );
  }
}

class _CarteAlerte extends StatefulWidget {
  final AlerteMaladie alerte;
  const _CarteAlerte({required this.alerte});

  @override
  State<_CarteAlerte> createState() => _CarteAlerteState();
}

class _CarteAlerteState extends State<_CarteAlerte> {
  bool _developpe = false;

  Color get _couleurNiveau {
    switch (widget.alerte.niveau) {
      case NiveauRisque.faible:   return Colors.green;
      case NiveauRisque.modere:   return Colors.amber.shade700;
      case NiveauRisque.eleve:    return Colors.orange;
      case NiveauRisque.critique: return Colors.red;
    }
  }

  Color get _couleurFond {
    switch (widget.alerte.niveau) {
      case NiveauRisque.faible:   return Colors.green.shade50;
      case NiveauRisque.modere:   return Colors.amber.shade50;
      case NiveauRisque.eleve:    return Colors.orange.shade50;
      case NiveauRisque.critique: return Colors.red.shade50;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _developpe = !_developpe),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _couleurFond,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _couleurNiveau.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Column(
          children: [
            // ── En-tête alerte ──
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Text(widget.alerte.emoji,
                    style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.alerte.maladie,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('Culture : ${widget.alerte.culture}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                // Badge niveau
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _couleurNiveau,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.alerte.niveau.emoji} ${widget.alerte.niveau.label}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _developpe ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey,
                ),
              ]),
            ),

            // ── Détails (déplié) ──
            if (_developpe)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 4),
                    // Raison météo
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: _couleurNiveau),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(widget.alerte.raison,
                              style: const TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Conseil préventif
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _couleurNiveau.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('💡',
                              style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(widget.alerte.conseil,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// SECTION PRÉVISIONS 7 JOURS
// ═════════════════════════════════════════════
class _SectionPrevisions extends StatelessWidget {
  final List<PrevisionJour> previsions;
  const _SectionPrevisions({required this.previsions});

  String _nomJour(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    const jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final now   = DateTime.now();
    if (date.day == now.day) return "Auj.";
    return jours[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('📅 Prévisions 7 jours',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: previsions.length,
            separatorBuilder: (_, __) => const Divider(
                height: 1, indent: 16, endIndent: 16),
            itemBuilder: (_, i) {
              final p = previsions[i];
              // Calculer le risque global de la journée
              final risqueJour = _risqueJour(p);
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(children: [
                  // Jour
                  SizedBox(
                    width: 40,
                    child: Text(_nomJour(p.date),
                        style: TextStyle(
                          fontWeight: i == 0
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 14,
                        )),
                  ),
                  // Emoji météo
                  Text(p.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  // Précipitations
                  Expanded(
                    child: Text(
                      p.precipitations > 0
                          ? '${p.precipitations.toStringAsFixed(1)} mm'
                          : 'Sec',
                      style: TextStyle(
                          fontSize: 12,
                          color: p.precipitations > 5
                              ? Colors.blue
                              : Colors.grey),
                    ),
                  ),
                  // Températures
                  Text(
                    '${p.tempMin.toStringAsFixed(0)}° / ${p.tempMax.toStringAsFixed(0)}°',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 10),
                  // Indicateur risque
                  if (risqueJour != null)
                    Text(risqueJour.emoji,
                        style: const TextStyle(fontSize: 16)),
                ]),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${NiveauRisque.faible.emoji} Faible  '
          '${NiveauRisque.modere.emoji} Modéré  '
          '${NiveauRisque.eleve.emoji} Élevé  '
          '${NiveauRisque.critique.emoji} Critique',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  NiveauRisque? _risqueJour(PrevisionJour p) {
    // Évaluation simplifiée du risque sur la journée
    if (p.humiditeMax >= 90 && p.tempMax >= 20) return NiveauRisque.critique;
    if (p.humiditeMax >= 80 && p.precipitations > 2) return NiveauRisque.eleve;
    if (p.humiditeMax >= 70 && p.precipitations > 0) return NiveauRisque.modere;
    if (p.humiditeMax >= 60) return NiveauRisque.faible;
    return null;
  }
}

// ═════════════════════════════════════════════
// SECTION CONSEILS GÉNÉRAUX
// ═════════════════════════════════════════════
class _SectionConseilsGeneraux extends StatelessWidget {
  final DonneesMeteo meteo;
  const _SectionConseilsGeneraux({required this.meteo});

  List<Map<String, String>> _genererConseils() {
    final conseils = <Map<String, String>>[];
    final t = meteo.temperatureActuelle;
    final h = meteo.humiditeActuelle;
    final p = meteo.precipitations;
    final v = meteo.vitesseVent;

    if (p > 5) {
      conseils.add({
        'icone': '☔',
        'titre': 'Pluie récente',
        'texte': 'Évitez les traitements phytosanitaires dans les 24h. '
                 'Les produits seront lessivés avant d\'agir.',
      });
    }
    if (v > 30) {
      conseils.add({
        'icone': '💨',
        'titre': 'Vent fort (${v.toStringAsFixed(0)} km/h)',
        'texte': 'Ne pas pulvériser de produits — risque de dérive. '
                 'Attendre des conditions plus calmes.',
      });
    }
    if (t > 32) {
      conseils.add({
        'icone': '🌡️',
        'titre': 'Forte chaleur',
        'texte': 'Traitements à faire tôt le matin ou en soirée. '
                 'Irriguer au pied des plants pour éviter le stress hydrique.',
      });
    }
    if (h > 85) {
      conseils.add({
        'icone': '💧',
        'titre': 'Humidité très élevée',
        'texte': 'Risque fongique élevé. '
                 'Inspectez vos cultures quotidiennement et ventilez vos serres.',
      });
    }
    if (t >= 18 && t <= 28 && h >= 40 && h <= 65 && p < 1) {
      conseils.add({
        'icone': '✅',
        'titre': 'Bonnes conditions',
        'texte': 'Moment idéal pour les traitements préventifs et les interventions culturales.',
      });
    }
    if (conseils.isEmpty) {
      conseils.add({
        'icone': '🌿',
        'titre': 'Conditions normales',
        'texte': 'Continuez vos pratiques habituelles. '
                 'Surveillez régulièrement l\'état de vos cultures.',
      });
    }
    return conseils;
  }

  @override
  Widget build(BuildContext context) {
    final conseils = _genererConseils();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('💡 Conseils du jour',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...conseils.map((c) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c['icone']!, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c['titre']!,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(c['texte']!,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black87)),
                      ],
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}