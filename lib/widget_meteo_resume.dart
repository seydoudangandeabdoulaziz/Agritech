// lib/widget_meteo_resume.dart
// Widget compact à intégrer dans main.dart (page d'accueil)
// Affiche : temp, humidité, nb d'alertes, bouton vers MeteoPage

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'meteo_service.dart';
import 'meteo_page.dart';

class WidgetMeteoResume extends StatefulWidget {
  const WidgetMeteoResume({super.key});

  @override
  State<WidgetMeteoResume> createState() => _WidgetMeteoResumeState();
}

class _WidgetMeteoResumeState extends State<WidgetMeteoResume> {
  DonneesMeteo?       _meteo;
  List<AlerteMaladie> _alertes  = [];
  bool                _chargement = true;
  bool                _erreur     = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() { _chargement = true; _erreur = false; });
    try {
      final position = await _obtenirPosition();
      if (position == null) {
        setState(() { _chargement = false; _erreur = true; });
        return;
      }
      final meteo   = await MeteoService.obtenirMeteo(position);
      final alertes = MeteoService.calculerAlertes(meteo);
      setState(() {
        _meteo      = meteo;
        _alertes    = alertes;
        _chargement = false;
      });
    } catch (_) {
      setState(() { _chargement = false; _erreur = true; });
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
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    // Si erreur ou chargement, widget minimal
    if (_chargement) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(children: [
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
          ),
          SizedBox(width: 10),
          Text('Chargement de la météo...',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
        ]),
      );
    }

    if (_erreur || _meteo == null) {
      return GestureDetector(
        onTap: _charger,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(children: [
            Icon(Icons.cloud_off, color: Colors.grey, size: 18),
            SizedBox(width: 8),
            Text('Météo indisponible — appuyer pour réessayer',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ),
      );
    }

    final meteo        = _meteo!;
    final nbAlertes    = _alertes.length;
    final alerteCritique = _alertes.any((a) => a.niveau == NiveauRisque.critique);
    final alerteElevee   = _alertes.any((a) => a.niveau == NiveauRisque.eleve);

    final couleurAlerte = alerteCritique
        ? Colors.red
        : alerteElevee
            ? Colors.orange
            : nbAlertes > 0
                ? Colors.amber.shade700
                : Colors.green;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MeteoPage()),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green.shade600, Colors.teal.shade400],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(children: [
          // Emoji météo + température
          Text(meteo.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${meteo.temperatureActuelle.toStringAsFixed(1)}°C  •  ${meteo.description}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              Text(
                'Humidité ${meteo.humiditeActuelle.toStringAsFixed(0)}%  •  '
                'Vent ${meteo.vitesseVent.toStringAsFixed(0)} km/h',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          // Badge alertes
          if (nbAlertes > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: couleurAlerte,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '$nbAlertes',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade800,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('✅ OK',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: Colors.white70),
        ]),
      ),
    );
  }
}