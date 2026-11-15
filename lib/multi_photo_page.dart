import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'database_helper.dart';

class MultiPhotoPage extends StatefulWidget {
  const MultiPhotoPage({super.key});

  @override
  State<MultiPhotoPage> createState() => _MultiPhotoPageState();
}

class _MultiPhotoPageState extends State<MultiPhotoPage> {
  final ImagePicker _picker = ImagePicker();
  final FlutterTts _tts = FlutterTts();

  // ✅ Liste des photos (max 5)
  final List<XFile> _photos = [];
  final List<Uint8List> _photosBytes = [];

  // États
  bool _isAnalyse = false;
  String _etape = ""; // Message d'étape en cours
  List<Map<String, dynamic>> _resultatsIndividuels = [];
  String _diagnosticFinal = "";
  String _stade = ""; // "Stade 1", "Stade 2", "Stade 3"
  String _maladiePrincipale = "";
  String _conseils = "";
  bool _isSpeaking = false;
  Process? _espeakProcess;

  static const int _maxPhotos = 5;
  static const String _baseIP = "10.10.31.62";
  final String _apiUrl = "http://$_baseIP:8000/predict";
  static const String _groqApiKey = "VOTRE_CLE_API_GROQ_ICI";

  // Couleurs par stade
  Color get _stadeColor {
    if (_stade.contains("1")) return Colors.green;
    if (_stade.contains("2")) return Colors.orange;
    if (_stade.contains("3")) return Colors.red;
    return Colors.grey;
  }

  IconData get _stadeIcon {
    if (_stade.contains("1")) return Icons.sentiment_satisfied;
    if (_stade.contains("2")) return Icons.sentiment_neutral;
    if (_stade.contains("3")) return Icons.sentiment_very_dissatisfied;
    return Icons.help_outline;
  }

  @override
  void dispose() {
    _espeakProcess?.kill();
    _tts.stop();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // AJOUTER UNE PHOTO
  // ─────────────────────────────────────────────
  Future<void> _ajouterPhoto(ImageSource source) async {
    if (_photos.length >= _maxPhotos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Maximum 5 photos atteint."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final XFile? photo = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1024,
    );
    if (photo == null) return;

    final bytes = await photo.readAsBytes();
    setState(() {
      _photos.add(photo);
      _photosBytes.add(bytes);
      // Réinitialiser les résultats si on change les photos
      _resultatsIndividuels = [];
      _diagnosticFinal = "";
      _stade = "";
      _maladiePrincipale = "";
      _conseils = "";
    });
  }

  void _supprimerPhoto(int index) {
    setState(() {
      _photos.removeAt(index);
      _photosBytes.removeAt(index);
      _resultatsIndividuels = [];
      _diagnosticFinal = "";
      _stade = "";
      _maladiePrincipale = "";
      _conseils = "";
    });
  }

  void _reset() {
    setState(() {
      _photos.clear();
      _photosBytes.clear();
      _resultatsIndividuels = [];
      _diagnosticFinal = "";
      _stade = "";
      _maladiePrincipale = "";
      _conseils = "";
      _isAnalyse = false;
      _etape = "";
    });
  }

  // ─────────────────────────────────────────────
  // ANALYSER TOUTES LES PHOTOS
  // ─────────────────────────────────────────────
  Future<void> _lancerAnalyse() async {
    if (_photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Ajoutez au moins une photo."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isAnalyse = true;
      _resultatsIndividuels = [];
      _diagnosticFinal = "";
      _stade = "";
      _maladiePrincipale = "";
      _conseils = "";
    });

    // ✅ ÉTAPE 1 : Analyser chaque photo individuellement
    for (int i = 0; i < _photos.length; i++) {
      setState(() => _etape =
          "Analyse photo ${i + 1}/${_photos.length}...");

      try {
        final resultat = await _analyserPhoto(i);
        setState(() => _resultatsIndividuels.add(resultat));
      } catch (e) {
        setState(() => _resultatsIndividuels.add({
          'photo': i + 1,
          'maladie': 'Erreur analyse',
          'confiance': 0.0,
          'erreur': e.toString(),
        }));
      }
    }

    // ✅ ÉTAPE 2 : Synthèse via Groq
    setState(() => _etape = "Synthèse du diagnostic final...");
    await _synthetiserDiagnostic();

    setState(() {
      _isAnalyse = false;
      _etape = "";
    });

    // ✅ Sauvegarde dans l'historique
    await _sauvegarderAnalyse();
  }

  // ─────────────────────────────────────────────
  // ANALYSER UNE PHOTO VIA FASTAPI
  // ─────────────────────────────────────────────
  Future<Map<String, dynamic>> _analyserPhoto(int index) async {
    var request = http.MultipartRequest('POST', Uri.parse(_apiUrl));

    if (kIsWeb) {
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        _photosBytes[index],
        filename: 'photo_${index + 1}.jpg',
      ));
    } else {
      request.files.add(
        await http.MultipartFile.fromPath('file', _photos[index].path),
      );
    }

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw Exception("Délai dépassé"),
    );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'photo': index + 1,
        'maladie': data['maladie'] ?? 'Inconnu',
        'confiance': double.tryParse(
                data['confiance']?.toString().replaceAll('%', '') ?? '0') ??
            0.0,
        'top3': data['top3'] ?? [],
      };
    } else {
      throw Exception("Erreur API ${response.statusCode}");
    }
  }

  // ─────────────────────────────────────────────
  // SYNTHÈSE VIA GROQ
  // ─────────────────────────────────────────────
  Future<void> _synthetiserDiagnostic() async {
    // Préparer le résumé des résultats individuels
    final resumeResultats = _resultatsIndividuels.map((r) {
      return "Photo ${r['photo']} : ${r['maladie']} (confiance: ${r['confiance'].toStringAsFixed(1)}%)";
    }).join("\n");

    // Compter les maladies les plus fréquentes
    final compteMaladies = <String, int>{};
    for (final r in _resultatsIndividuels) {
      final maladie = r['maladie'] as String;
      compteMaladies[maladie] = (compteMaladies[maladie] ?? 0) + 1;
    }
    final maladieFrequente = compteMaladies.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    try {
      final response = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $_groqApiKey",
        },
        body: jsonEncode({
          "model": "llama-3.3-70b-versatile",
          "messages": [
            {
              "role": "system",
              "content":
                  "Tu es un expert phytopathologiste. Tu analyses des résultats de détection de maladies de plantes provenant de plusieurs photos et tu donnes un diagnostic précis avec stade de progression. Réponds uniquement en français.",
            },
            {
              "role": "user",
              "content": """
Voici les résultats d'analyse de ${_photos.length} photo(s) d'une même plante :

$resumeResultats

La maladie la plus fréquemment détectée est : $maladieFrequente

Donne un diagnostic unifié structuré EXACTEMENT ainsi (respecte ce format) :

MALADIE_PRINCIPALE: [nom exact de la maladie]

STADE: [Stade 1 / Stade 2 / Stade 3]

EXPLICATION_STADE:
- Stade 1 = Début (maladie détectée sur moins de 30% des photos ou confiance faible)
- Stade 2 = Modéré (maladie sur 30-70% des photos ou confiance moyenne)
- Stade 3 = Avancé (maladie sur plus de 70% des photos ou confiance élevée)

## 🔬 Diagnostic final
(Résumé du diagnostic basé sur les ${_photos.length} photos)

## 📊 Analyse de cohérence
(Les photos sont-elles cohérentes entre elles ? Y a-t-il des divergences ?)

## 🌿 Description du stade détecté
(Description précise du stade et ce que ça implique)

## 💊 Traitement adapté au stade
(Traitement spécifique selon le stade détecté)

## ⚡ Urgence d'intervention
(Immédiate / Dans les 48h / Dans la semaine)
""",
            },
          ],
          "temperature": 0.3,
          "max_tokens": 1500,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content =
            data['choices'][0]['message']['content'] as String;

        // ✅ Extraire MALADIE_PRINCIPALE et STADE du texte
        final regexMaladie =
            RegExp(r'MALADIE_PRINCIPALE:\s*(.+)', caseSensitive: false);
        final regexStade =
            RegExp(r'STADE:\s*(Stade \d)', caseSensitive: false);

        final matchMaladie = regexMaladie.firstMatch(content);
        final matchStade = regexStade.firstMatch(content);

        // Nettoyer le texte pour l'affichage (enlever les lignes MALADIE_PRINCIPALE et STADE)
        String contenuNettoye = content
            .replaceAll(regexMaladie, '')
            .replaceAll(regexStade, '')
            .replaceAll(RegExp(r'EXPLICATION_STADE:.*?\n', dotAll: true), '')
            .trim();

        setState(() {
          _maladiePrincipale = matchMaladie?.group(1)?.trim() ?? maladieFrequente;
          _stade = matchStade?.group(1)?.trim() ?? "Stade 1";
          _diagnosticFinal = contenuNettoye;
          _conseils = contenuNettoye;
        });
      }
    } catch (e) {
      setState(() {
        _maladiePrincipale = maladieFrequente;
        _stade = "Stade 1";
        _diagnosticFinal =
            "## Diagnostic\nMaladie détectée : $maladieFrequente\n\nErreur lors de la synthèse : $e";
        _conseils = _diagnosticFinal;
      });
    }
  }

  // ─────────────────────────────────────────────
  // SAUVEGARDE HISTORIQUE
  // ─────────────────────────────────────────────
  Future<void> _sauvegarderAnalyse() async {
    if (_maladiePrincipale.isEmpty) return;
    try {
      final now = DateTime.now();
      final dateStr =
          "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} "
          "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

      final confianceMoy = _resultatsIndividuels.isEmpty
          ? 0.0
          : _resultatsIndividuels
                  .map((r) => r['confiance'] as double)
                  .reduce((a, b) => a + b) /
              _resultatsIndividuels.length /
              100;

      final analyse = Analyse(
        imagePath: kIsWeb ? '' : (_photos.isNotEmpty ? _photos[0].path : ''),
        imageUrl: '',
        maladie: "$_maladiePrincipale ($_stade)",
        confiance: confianceMoy,
        top3: "${_photos.length} photos analysées",
        conseils: _conseils,
        langue: "🇫🇷 Français",
        date: dateStr,
      );
      await DatabaseHelper.instance.insertAnalyse(analyse);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.save, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text("Diagnostic multi-photos sauvegardé"),
            ]),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Silencieux si non connecté
    }
  }

  // ─────────────────────────────────────────────
  // LECTURE VOCALE
  // ─────────────────────────────────────────────
  Future<void> _lireConseils() async {
    if (_conseils.isEmpty) return;
    final texte = "$_maladiePrincipale. $_stade. "
        "${_conseils.replaceAll(RegExp(r'#{1,6}\s*'), '').replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')}";

    if (!kIsWeb && Platform.isLinux) {
      _espeakProcess?.kill();
      setState(() => _isSpeaking = true);
      _espeakProcess =
          await Process.start('espeak-ng', ['-v', 'fr', '-s', '150', texte]);
      _espeakProcess!.exitCode.then((_) {
        if (mounted) setState(() => _isSpeaking = false);
      });
    } else if (!kIsWeb) {
      await _tts.setLanguage('fr-FR');
      await _tts.setSpeechRate(0.45);
      await _tts.speak(texte);
      setState(() => _isSpeaking = true);
      _tts.setCompletionHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
    }
  }

  Future<void> _arreterLecture() async {
    if (!kIsWeb && Platform.isLinux) {
      _espeakProcess?.kill();
    } else if (!kIsWeb) {
      await _tts.stop();
    }
    setState(() => _isSpeaking = false);
  }

  // ─────────────────────────────────────────────
  // INTERFACE
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Diagnostic multi-photos 📸",
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_photos.isNotEmpty || _diagnosticFinal.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _reset,
              tooltip: "Réinitialiser",
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── En-tête explicatif ──
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Ajoutez 1 à 5 photos sous différents angles pour un diagnostic plus précis avec stade de progression.",
                      style: TextStyle(fontSize: 13, color: Colors.green),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Grille de photos ──
            Row(
              children: [
                Text(
                  "Photos (${_photos.length}/$_maxPhotos)",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const Spacer(),
                Text(
                  "${_maxPhotos - _photos.length} restante(s)",
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Grille photos + bouton ajouter
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: _photos.length < _maxPhotos
                  ? _photos.length + 1
                  : _photos.length,
              itemBuilder: (context, index) {
                // Dernière case = bouton ajouter
                if (index == _photos.length && _photos.length < _maxPhotos) {
                  return _buildBoutonAjouter();
                }
                return _buildMiniaturePhoto(index);
              },
            ),

            const SizedBox(height: 20),

            // ── Bouton lancer analyse ──
            if (_photos.isNotEmpty && !_isAnalyse)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _lancerAnalyse,
                  icon: const Icon(Icons.biotech, color: Colors.white),
                  label: Text(
                    "Analyser ${_photos.length} photo(s)",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

            // ── Indicateur de progression ──
            if (_isAnalyse) ...[
              const SizedBox(height: 16),
              _buildProgressionAnalyse(),
            ],

            // ── Résultats individuels ──
            if (_resultatsIndividuels.isNotEmpty && !_isAnalyse) ...[
              const SizedBox(height: 24),
              _buildResultatsIndividuels(),
            ],

            // ── Diagnostic final ──
            if (_diagnosticFinal.isNotEmpty && !_isAnalyse) ...[
              const SizedBox(height: 16),
              _buildDiagnosticFinal(),
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // WIDGETS
  // ─────────────────────────────────────────────
  Widget _buildBoutonAjouter() {
    return GestureDetector(
      onTap: () => _showSourcePhoto(),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: Colors.green.shade300, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo, color: Colors.green[400], size: 30),
            const SizedBox(height: 4),
            Text("Ajouter",
                style: TextStyle(color: Colors.green[400], fontSize: 11)),
          ],
        ),
      ),
    );
  }

  void _showSourcePhoto() {
    if (kIsWeb || (!kIsWeb && !Platform.isAndroid && !Platform.isIOS)) {
      _ajouterPhoto(ImageSource.gallery);
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text("Prendre une photo"),
              onTap: () {
                Navigator.pop(context);
                _ajouterPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text("Choisir depuis la galerie"),
              onTap: () {
                Navigator.pop(context);
                _ajouterPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniaturePhoto(int index) {
    final bool aResultat = index < _resultatsIndividuels.length;
    final resultat =
        aResultat ? _resultatsIndividuels[index] : null;
    final bool estSain = resultat != null &&
        (resultat['maladie'] as String).toLowerCase().contains('sain');

    return Stack(
      children: [
        // Image
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: kIsWeb
              ? Image.memory(_photosBytes[index],
                  fit: BoxFit.cover, width: double.infinity,
                  height: double.infinity)
              : Image.file(File(_photos[index].path),
                  fit: BoxFit.cover, width: double.infinity,
                  height: double.infinity),
        ),

        // Numéro photo
        Positioned(
          top: 4,
          left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text("${index + 1}",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ),

        // Badge résultat individuel
        if (aResultat)
          Positioned(
            bottom: 4,
            left: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: estSain
                    ? Colors.green.withOpacity(0.85)
                    : Colors.red.withOpacity(0.85),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                resultat!['maladie'] as String,
                style: const TextStyle(color: Colors.white, fontSize: 9),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

        // Bouton supprimer
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _supprimerPhoto(index),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressionAnalyse() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(color: Colors.blue),
          const SizedBox(height: 12),
          Text(
            _etape,
            style: const TextStyle(
                fontWeight: FontWeight.w500, color: Colors.blue),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Barre de progression
          LinearProgressIndicator(
            value: _resultatsIndividuels.length / _photos.length,
            backgroundColor: Colors.blue[100],
            color: Colors.blue,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 6),
          Text(
            "${_resultatsIndividuels.length}/${_photos.length} photos analysées",
            style: TextStyle(fontSize: 12, color: Colors.blue[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildResultatsIndividuels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Résultats par photo",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        ...List.generate(_resultatsIndividuels.length, (i) {
          final r = _resultatsIndividuels[i];
          final bool estSain =
              (r['maladie'] as String).toLowerCase().contains('sain');
          final double confiance = r['confiance'] as double;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: estSain
                      ? Colors.green.shade200
                      : Colors.red.shade200),
            ),
            child: Row(
              children: [
                // Miniature
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: kIsWeb
                      ? Image.memory(_photosBytes[i],
                          width: 50, height: 50, fit: BoxFit.cover)
                      : Image.file(File(_photos[i].path),
                          width: 50, height: 50, fit: BoxFit.cover),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Photo ${i + 1}",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(r['maladie'] as String,
                          style: const TextStyle(fontSize: 13)),
                      // Barre de confiance
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: confiance / 100,
                                backgroundColor: Colors.grey[200],
                                color: confiance > 70
                                    ? Colors.green
                                    : confiance > 40
                                        ? Colors.orange
                                        : Colors.red,
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text("${confiance.toStringAsFixed(1)}%",
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  estSain ? Icons.check_circle : Icons.warning_rounded,
                  color: estSain ? Colors.green : Colors.red,
                  size: 20,
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDiagnosticFinal() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _stadeColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: _stadeColor.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── En-tête : stade ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _stadeColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(_stadeIcon, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      _stade,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _maladiePrincipale,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Bouton TTS
              if (!kIsWeb)
                IconButton(
                  onPressed: _isSpeaking ? _arreterLecture : _lireConseils,
                  icon: Icon(
                    _isSpeaking
                        ? Icons.stop_circle
                        : Icons.play_circle_filled,
                    color: _isSpeaking ? Colors.red : Colors.green,
                    size: 30,
                  ),
                ),
            ],
          ),

          // Description stade
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _stadeColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.analytics, color: _stadeColor, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _getDescriptionStade(),
                    style: TextStyle(
                        color: _stadeColor,
                        fontSize: 12,
                        fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 20),

          // Diagnostic complet en Markdown
          MarkdownBody(
            data: _diagnosticFinal,
            styleSheet: MarkdownStyleSheet(
              h2: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _stadeColor),
              p: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _getDescriptionStade() {
    if (_stade.contains("1")) {
      return "Infection débutante — Intervention rapide recommandée pour limiter la propagation";
    } else if (_stade.contains("2")) {
      return "Infection modérée — Traitement urgent nécessaire dans les 48h";
    } else if (_stade.contains("3")) {
      return "Infection avancée — Intervention immédiate requise, risque de perte de récolte";
    }
    return "";
  }
}