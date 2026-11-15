// lib/meteo_service.dart
// Service météo basé sur Open-Meteo (gratuit, sans clé API)
// + moteur d'alertes maladies selon les conditions climatiques

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────
// MODÈLES
// ─────────────────────────────────────────────

class DonneesMeteo {
  final double temperatureActuelle; // °C
  final double humiditeActuelle;    // %
  final double precipitations;      // mm (dernières heures)
  final double vitesseVent;         // km/h
  final int    codeMeteo;           // WMO weather code
  final String description;
  final String emoji;
  final double temperatureMin;
  final double temperatureMax;
  final List<PrevisionJour> previsions; // 7 jours

  const DonneesMeteo({
    required this.temperatureActuelle,
    required this.humiditeActuelle,
    required this.precipitations,
    required this.vitesseVent,
    required this.codeMeteo,
    required this.description,
    required this.emoji,
    required this.temperatureMin,
    required this.temperatureMax,
    required this.previsions,
  });
}

class PrevisionJour {
  final String date;
  final double tempMin;
  final double tempMax;
  final double precipitations;
  final double humiditeMax;
  final int    codeMeteo;
  final String emoji;

  const PrevisionJour({
    required this.date,
    required this.tempMin,
    required this.tempMax,
    required this.precipitations,
    required this.humiditeMax,
    required this.codeMeteo,
    required this.emoji,
  });
}

class AlerteMaladie {
  final String          maladie;
  final String          culture;
  final NiveauRisque    niveau;
  final String          raison;     // explication météo
  final String          conseil;    // action préventive
  final String          emoji;

  const AlerteMaladie({
    required this.maladie,
    required this.culture,
    required this.niveau,
    required this.raison,
    required this.conseil,
    required this.emoji,
  });
}

enum NiveauRisque { faible, modere, eleve, critique }

extension NiveauRisqueExt on NiveauRisque {
  String get label {
    switch (this) {
      case NiveauRisque.faible:   return 'Faible';
      case NiveauRisque.modere:   return 'Modéré';
      case NiveauRisque.eleve:    return 'Élevé';
      case NiveauRisque.critique: return 'Critique';
    }
  }

  String get emoji {
    switch (this) {
      case NiveauRisque.faible:   return '🟢';
      case NiveauRisque.modere:   return '🟡';
      case NiveauRisque.eleve:    return '🟠';
      case NiveauRisque.critique: return '🔴';
    }
  }
}

// ─────────────────────────────────────────────
// SERVICE MÉTÉO
// ─────────────────────────────────────────────
class MeteoService {
  static const String _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  /// Récupère les données météo pour une position GPS
  static Future<DonneesMeteo> obtenirMeteo(Position position) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'latitude':                    position.latitude.toString(),
      'longitude':                   position.longitude.toString(),
      'current':                     'temperature_2m,relative_humidity_2m,precipitation,weather_code,wind_speed_10m',
      'daily':                       'temperature_2m_max,temperature_2m_min,precipitation_sum,relative_humidity_2m_max,weather_code',
      'timezone':                    'auto',
      'forecast_days':               '7',
      'wind_speed_unit':             'kmh',
    });

    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Erreur API météo : ${response.statusCode}');
    }

    final data = json.decode(response.body);
    final current = data['current'];
    final daily   = data['daily'];

    // Prévisions 7 jours
    final List<PrevisionJour> previsions = [];
    final dates = daily['time'] as List;
    for (int i = 0; i < dates.length; i++) {
      final code = (daily['weather_code'][i] as num).toInt();
      previsions.add(PrevisionJour(
        date:          dates[i],
        tempMin:       (daily['temperature_2m_min'][i] as num).toDouble(),
        tempMax:       (daily['temperature_2m_max'][i] as num).toDouble(),
        precipitations:(daily['precipitation_sum'][i] as num).toDouble(),
        humiditeMax:   (daily['relative_humidity_2m_max'][i] as num).toDouble(),
        codeMeteo:     code,
        emoji:         _emojiPourCode(code),
      ));
    }

    final codeActuel = (current['weather_code'] as num).toInt();
    final temp       = (current['temperature_2m'] as num).toDouble();
    final humidite   = (current['relative_humidity_2m'] as num).toDouble();
    final pluie      = (current['precipitation'] as num).toDouble();
    final vent       = (current['wind_speed_10m'] as num).toDouble();

    return DonneesMeteo(
      temperatureActuelle: temp,
      humiditeActuelle:    humidite,
      precipitations:      pluie,
      vitesseVent:         vent,
      codeMeteo:           codeActuel,
      description:         _descriptionPourCode(codeActuel),
      emoji:               _emojiPourCode(codeActuel),
      temperatureMin:      (daily['temperature_2m_min'][0] as num).toDouble(),
      temperatureMax:      (daily['temperature_2m_max'][0] as num).toDouble(),
      previsions:          previsions,
    );
  }

  // ─────────────────────────────────────────────
  // MOTEUR D'ALERTES MALADIES
  // Basé sur les conditions favorisant chaque maladie
  // ─────────────────────────────────────────────
  static List<AlerteMaladie> calculerAlertes(DonneesMeteo meteo) {
    final alertes = <AlerteMaladie>[];
    final t  = meteo.temperatureActuelle;
    final h  = meteo.humiditeActuelle;
    final p  = meteo.precipitations;

    // ── POMMIER ──────────────────────────────────

    // Tavelure du pommier : T 15–24°C + humidité > 70% + pluie récente
    if (t >= 15 && t <= 24 && h >= 70) {
      alertes.add(AlerteMaladie(
        maladie: 'Tavelure du pommier',
        culture: 'Pommier',
        niveau:  h >= 85 || p > 2 ? NiveauRisque.critique : NiveauRisque.eleve,
        raison:  'Température ${t.toStringAsFixed(1)}°C et humidité ${h.toStringAsFixed(0)}% '
                 'idéales pour le développement de Venturia inaequalis.',
        conseil: 'Appliquer un fongicide préventif (captane ou mancozèbe) '
                 'avant les prochaines pluies. Inspecter les jeunes pousses.',
        emoji:   '🍎',
      ));
    }

    // Rouille du pommier : T 18–24°C + humidité > 60%
    if (t >= 18 && t <= 24 && h >= 60) {
      alertes.add(AlerteMaladie(
        maladie: 'Rouille du pommier',
        culture: 'Pommier',
        niveau:  h >= 80 ? NiveauRisque.eleve : NiveauRisque.modere,
        raison:  'Conditions humides et températures douces favorisent '
                 'Gymnosporangium tremelloides.',
        conseil: 'Surveiller les feuilles (pustules orange). '
                 'Traitement au soufre si symptômes détectés.',
        emoji:   '🍎',
      ));
    }

    // ── MAÏS ─────────────────────────────────────

    // Rouille commune du maïs : T 16–23°C + humidité > 75%
    if (t >= 16 && t <= 23 && h >= 75) {
      alertes.add(AlerteMaladie(
        maladie: 'Rouille commune du maïs',
        culture: 'Maïs',
        niveau:  h >= 90 ? NiveauRisque.critique : NiveauRisque.eleve,
        raison:  'Humidité élevée (${h.toStringAsFixed(0)}%) et fraîcheur nocturne '
                 'propices à Puccinia sorghi.',
        conseil: 'Appliquer un fongicide triazole au stade V6–V8. '
                 'Éviter l\'irrigation foliaire le soir.',
        emoji:   '🌽',
      ));
    }

    // Tache foliaire Cercospora : T > 25°C + humidité > 80%
    if (t >= 25 && h >= 80) {
      alertes.add(AlerteMaladie(
        maladie: 'Tache foliaire à Cercospora',
        culture: 'Maïs',
        niveau:  t >= 28 && h >= 85 ? NiveauRisque.critique : NiveauRisque.eleve,
        raison:  'Chaleur (${t.toStringAsFixed(1)}°C) et forte humidité '
                 'accélèrent la sporulation de Cercospora zeae-maydis.',
        conseil: 'Rotation des cultures recommandée. '
                 'Fongicide strobilurine si infection > 5% de surface foliaire.',
        emoji:   '🌽',
      ));
    }

    // Brûlure du nord : T 20–30°C + nuits fraîches + rosée
    if (t >= 20 && t <= 30 && h >= 85) {
      alertes.add(AlerteMaladie(
        maladie: 'Brûlure du nord du maïs',
        culture: 'Maïs',
        niveau:  NiveauRisque.modere,
        raison:  'Conditions de rosée prolongée favorisent Exserohilum turcicum.',
        conseil: 'Surveiller les lésions en forme de cigare sur les feuilles. '
                 'Traitement fongicide préventif si variété sensible.',
        emoji:   '🌽',
      ));
    }

    // ── VIGNE ─────────────────────────────────────

    // Mildiou (non dans le modèle mais prévention utile) / Esca :
    // T > 25°C + période sèche après stress hydrique
    if (t >= 25 && p < 1 && h < 50) {
      alertes.add(AlerteMaladie(
        maladie: 'Esca / Rougeot parasite',
        culture: 'Vigne',
        niveau:  t >= 30 ? NiveauRisque.eleve : NiveauRisque.modere,
        raison:  'Stress hydrique (faible humidité ${h.toStringAsFixed(0)}%, '
                 'pas de pluie) affaiblit les ceps et favorise l\'Esca.',
        conseil: 'Irriguer modérément si possible. '
                 'Éviter les tailles en période de forte chaleur. '
                 'Protéger les plaies de taille.',
        emoji:   '🍇',
      ));
    }

    // Brûlure des feuilles de vigne : T > 30°C + ensoleillement fort
    if (t >= 30 && h < 40) {
      alertes.add(AlerteMaladie(
        maladie: 'Brûlure des feuilles de vigne',
        culture: 'Vigne',
        niveau:  t >= 35 ? NiveauRisque.critique : NiveauRisque.eleve,
        raison:  'Température très élevée (${t.toStringAsFixed(1)}°C) '
                 'et air sec provoquent des brûlures foliaires.',
        conseil: 'Kaolin en poudrage pour réfléchir la chaleur. '
                 'Irrigation au pied tôt le matin. '
                 'Ombrage temporaire sur jeunes plants.',
        emoji:   '🍇',
      ));
    }

    // Pourriture noire vigne : T 24–29°C + humidité > 70% + pluie
    if (t >= 24 && t <= 29 && h >= 70 && p > 0) {
      alertes.add(AlerteMaladie(
        maladie: 'Pourriture noire de la vigne',
        culture: 'Vigne',
        niveau:  h >= 85 ? NiveauRisque.critique : NiveauRisque.eleve,
        raison:  'Pluie récente et humidité élevée favorisent '
                 'Guignardia bidwellii sur baies et feuilles.',
        conseil: 'Traitement fongicide systémique (métalaxyl). '
                 'Effeuillage pour améliorer la ventilation de la grappe.',
        emoji:   '🍇',
      ));
    }

    // ── TOMATE ───────────────────────────────────

    // Tache bactérienne tomate : T 24–30°C + humidité > 85% + pluie
    if (t >= 24 && t <= 30 && h >= 85) {
      alertes.add(AlerteMaladie(
        maladie: 'Tache bactérienne de la tomate',
        culture: 'Tomate',
        niveau:  p > 5 ? NiveauRisque.critique : NiveauRisque.eleve,
        raison:  'Chaleur humide (T=${t.toStringAsFixed(1)}°C, H=${h.toStringAsFixed(0)}%) '
                 'et pluie éclaboussante propagent Xanthomonas vesicatoria.',
        conseil: 'Traitement au cuivre (bouillie bordelaise). '
                 'Éviter l\'arrosage par aspersion. '
                 'Espacer les plants pour aérer.',
        emoji:   '🍅',
      ));
    }

    // Moisissure des feuilles de tomate : T 18–25°C + humidité > 85%
    if (t >= 18 && t <= 25 && h >= 85) {
      alertes.add(AlerteMaladie(
        maladie: 'Moisissure des feuilles de tomate',
        culture: 'Tomate',
        niveau:  h >= 95 ? NiveauRisque.critique : NiveauRisque.eleve,
        raison:  'Humidité très élevée (${h.toStringAsFixed(0)}%) '
                 'et températures fraîches propices à Passalora fulva.',
        conseil: 'Ventiler les serres. Réduire l\'humidité nocturne. '
                 'Fongicide chlorothalonil en préventif.',
        emoji:   '🍅',
      ));
    }

    // Mildiou tomate (alerte générale) : T 10–25°C + humidité > 90%
    if (t >= 10 && t <= 25 && h >= 90) {
      alertes.add(AlerteMaladie(
        maladie: 'Risque mildiou (tomate/vigne)',
        culture: 'Tomate / Vigne',
        niveau:  NiveauRisque.critique,
        raison:  'Humidité extrême (${h.toStringAsFixed(0)}%) '
                 'et températures fraîches : conditions parfaites pour Phytophthora.',
        conseil: 'Traitement préventif immédiat au mancozèbe ou cymoxanil. '
                 'Inspecter quotidiennement les feuilles basses.',
        emoji:   '⚠️',
      ));
    }

    // Trier par niveau de risque décroissant
    alertes.sort((a, b) => b.niveau.index.compareTo(a.niveau.index));
    return alertes;
  }

  // ─────────────────────────────────────────────
  // UTILITAIRES WMO CODES
  // ─────────────────────────────────────────────
  static String _descriptionPourCode(int code) {
    if (code == 0)              return 'Ciel dégagé';
    if (code <= 3)              return 'Partiellement nuageux';
    if (code <= 48)             return 'Brouillard';
    if (code <= 55)             return 'Bruine';
    if (code <= 65)             return 'Pluie';
    if (code <= 75)             return 'Neige';
    if (code <= 82)             return 'Averses';
    if (code <= 86)             return 'Averses de neige';
    if (code <= 99)             return 'Orage';
    return 'Conditions inconnues';
  }

  static String _emojiPourCode(int code) {
    if (code == 0)              return '☀️';
    if (code <= 3)              return '⛅';
    if (code <= 48)             return '🌫️';
    if (code <= 55)             return '🌦️';
    if (code <= 65)             return '🌧️';
    if (code <= 75)             return '❄️';
    if (code <= 82)             return '🌨️';
    if (code <= 86)             return '🌨️';
    if (code <= 99)             return '⛈️';
    return '🌡️';
  }
}