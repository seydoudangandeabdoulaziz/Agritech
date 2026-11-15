import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'database_helper.dart';
import 'historique_page.dart';
import 'carte_maladies_page.dart';
import 'meteo_page.dart';
import 'widget_meteo_resume.dart';
import 'dashboard_page.dart';
import 'login_page.dart';
import 'chatbot_page.dart';
import 'forum_page.dart';
import 'multi_photo_page.dart';
import 'parcelles_page.dart';
import 'pharmacie_page.dart';
import 'experts_page.dart';

// ─────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } else if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  runApp(const MyApp());
}

// ─────────────────────────────────────────────
// APP
// ─────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green, useMaterial3: true),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    // Sur desktop 
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      return const DiseaseDetectorScreen();
    }

    // Sur Web
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Colors.green),
            ),
          );
        }

        return const DiseaseDetectorScreen();
      },
    );
  }
}

// ─────────────────────────────────────────────
// CONFIGURATION DES LANGUES
// ─────────────────────────────────────────────
class Langue {
  final String code;
  final String nom;
  final String drapeau;
  final String ttsCode;

  const Langue({
    required this.code,
    required this.nom,
    required this.drapeau,
    required this.ttsCode,
  });
}

const List<Langue> languesDisponibles = [
  Langue(code: "fr",  nom: "Français", drapeau: "🇫🇷", ttsCode: "fr"),
  Langue(code: "en",  nom: "English",  drapeau: "🇬🇧", ttsCode: "en"),
  Langue(code: "ha",  nom: "Haoussa",  drapeau: "🇳🇬", ttsCode: "fr"),
  Langue(code: "dje", nom: "Zarma",    drapeau: "🇳🇪", ttsCode: "fr"),
  Langue(code: "ar",  nom: "العربية",  drapeau: "🇸🇦", ttsCode: "ar"),
  Langue(code: "ff",  nom: "Fulfulde", drapeau: "🇬🇳", ttsCode: "fr"),
  Langue(code: "tmh", nom: "Tamasheq", drapeau: "🇲🇱", ttsCode: "fr"),
];


// ÉCRAN PRINCIPAL

class DiseaseDetectorScreen extends StatefulWidget {
  const DiseaseDetectorScreen({super.key});

  @override
  State<DiseaseDetectorScreen> createState() => _DiseaseDetectorScreenState();
}

class _DiseaseDetectorScreenState extends State<DiseaseDetectorScreen> {
  // ── Image
  XFile?     _imageFile;     // utilisé sur toutes les plateformes
  Uint8List? _imageBytesWeb; // pour l'affichage Web
  File?      _imageNative;   // pour l'envoi API sur mobile/desktop

  final ImagePicker _picker = ImagePicker();

  String _maladie   = "";
  String _confiance = "";
  String _top3      = "";
  String _conseils  = "";
  bool _isLoadingPrediction = false;
  bool _isLoadingConseils   = false;

  // Langue
  Langue _langueSelectionnee = languesDisponibles[0];

  // TTS
  final FlutterTts _flutterTts = FlutterTts();
  bool     _isSpeaking    = false;
  bool     _isPaused      = false;
  Process? _espeakProcess;

  // GPS
  Position? _dernierePosition;

  // Config réseau
  static const String _baseIP     = "ip_address de votre machine";
  final String        _apiUrl     = "http://$_baseIP:8000/predict";
  static const String _groqApiKey =
      "Votre clé api groq";

  // ── Helpers ───────────────────────────────
  bool get _cameraAvailable {
    if (kIsWeb) return false;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return false;
    return true;
  }

  bool get _aUneImage => _imageFile != null;
  @override
  void initState() {
    super.initState();
    _initTts();
  }

  @override
  void dispose() {
    _espeakProcess?.kill();
    _flutterTts.stop();
    super.dispose();
  }

  // ─────────────────────────────────────────
  // GPS
  // ─────────────────────────────────────────
  Future<Position?> _obtenirPosition() async {
    if (!kIsWeb &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      return null;
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────
  // TTS
  // ─────────────────────────────────────────
  Future<void> _initTts() async {
    if (kIsWeb) return;
    if (!kIsWeb && Platform.isLinux) return;
    await _flutterTts.setLanguage(_langueSelectionnee.ttsCode);
    await _flutterTts.setSpeechRate(0.45);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    _flutterTts.setStartHandler(() => setState(() => _isSpeaking = true));
    _flutterTts.setCompletionHandler(() => setState(() {
      _isSpeaking = false;
      _isPaused   = false;
    }));
    _flutterTts.setCancelHandler(() => setState(() {
      _isSpeaking = false;
      _isPaused   = false;
    }));
    _flutterTts.setPauseHandler(() => setState(() => _isPaused = true));
    _flutterTts.setContinueHandler(() => setState(() => _isPaused = false));
  }

  String _nettoyerMarkdown(String texte) {
    return texte
        .replaceAll(RegExp(r'#{1,6}\s*'), '')
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1')
        .replaceAll('•', '')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }

  Future<void> _lireConseils() async {
    if (_conseils.isEmpty) return;
    final texte = "$_maladie. ${_nettoyerMarkdown(_conseils)}";

    if (!kIsWeb && Platform.isLinux) {
      await _arreterLecture();
      setState(() => _isSpeaking = true);
      try {
        _espeakProcess = await Process.start('espeak-ng', [
          '-v', _langueSelectionnee.ttsCode, '-s', '150', '-p', '50', texte,
        ]);
        _espeakProcess!.exitCode.then((_) {
          if (mounted) setState(() { _isSpeaking = false; _isPaused = false; });
        });
      } catch (_) {
        if (mounted) setState(() { _isSpeaking = false; _isPaused = false; });
      }
    } else if (!kIsWeb) {
      await _flutterTts.setLanguage(_langueSelectionnee.ttsCode);
      if (_isSpeaking && !_isPaused) {
        await _flutterTts.pause();
        setState(() => _isPaused = true);
      } else {
        await _flutterTts.speak(texte);
        setState(() { _isSpeaking = true; _isPaused = false; });
      }
    }
  }

  Future<void> _arreterLecture() async {
    if (!kIsWeb && Platform.isLinux) {
      _espeakProcess?.kill();
      _espeakProcess = null;
    } else if (!kIsWeb) {
      await _flutterTts.stop();
    }
    setState(() { _isSpeaking = false; _isPaused = false; });
  }

  // ─────────────────────────────────────────
  // LANGUE
  // ─────────────────────────────────────────
  void _changerLangue(Langue langue) async {
    await _arreterLecture();
    setState(() { _langueSelectionnee = langue; _conseils = ""; });
    if (_maladie.isNotEmpty && !_maladie.startsWith("❌")) {
      await _getConseilsGroq(_maladie);
    }
  }

  void _ouvrirSelecteurLangue() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("🌍 Choisir la langue des conseils",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...languesDisponibles.map((langue) {
              final bool est = langue.code == _langueSelectionnee.code;
              return ListTile(
                leading: Text(langue.drapeau,
                    style: const TextStyle(fontSize: 28)),
                title: Text(langue.nom,
                    style: TextStyle(
                        fontWeight:
                            est ? FontWeight.bold : FontWeight.normal,
                        color: est ? Colors.green : null)),
                trailing: est
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _changerLangue(langue);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

 
  Future<void> _pickImage(ImageSource source) async {
    await _arreterLecture();
    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _imageFile    = pickedFile;
        _imageBytesWeb = bytes;
        if (!kIsWeb) _imageNative = File(pickedFile.path);
        _isLoadingPrediction = true;
        _maladie   = "";
        _confiance = "";
        _top3      = "";
        _conseils  = "";
      });

      // Obtenir position GPS en parallèle
      _obtenirPosition().then((pos) {
        if (mounted) setState(() => _dernierePosition = pos);
      });

      // ✅ Envoyer à l'API avec les bytes (compatible Web + Android)
      await _sendImageToAPI(bytes, pickedFile.name);
    }
  }


  Future<void> _sendImageToAPI(Uint8List imageBytes, String fileName) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: fileName,
        ),
      );
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception("Délai dépassé (15s)"),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String top3Text = "";
        if (data['top3'] != null) {
          top3Text = (data['top3'] as List)
              .map((e) => "• ${e['classe']} : ${e['probabilite']}")
              .join("\n");
        }
        setState(() {
          _maladie   = data['maladie'] ?? "Résultat inconnu";
          _confiance = data['confiance'] != null
              ? "Fiabilité : ${data['confiance']}"
              : "";
          _top3                = top3Text;
          _isLoadingPrediction = false;
        });
        await _getConseilsGroq(_maladie);
      } else {
        setState(() {
          _maladie             = "Erreur serveur (${response.statusCode})";
          _isLoadingPrediction = false;
        });
      }
    } on SocketException {
      setState(() {
        _maladie =
            "❌ Connexion impossible. Vérifiez l'IP et le serveur.";
        _isLoadingPrediction = false;
      });
    } catch (e) {
      setState(() {
        _maladie             = "❌ Erreur : ${e.toString()}";
        _isLoadingPrediction = false;
      });
    }
  }

  // ─────────────────────────────────────────
  // GROQ — CONSEILS IA
  // ─────────────────────────────────────────
  Future<void> _getConseilsGroq(String maladie) async {
    setState(() { _isLoadingConseils = true; _conseils = ""; });

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
                  "Tu es un expert agronome multilingue. Tu donnes des conseils pratiques aux agriculteurs dans la langue demandée.",
            },
            {
              "role": "user",
              "content": """
Une analyse par IA a détecté : **$maladie**

Structure ta réponse ainsi :

## 🌿 Description de la maladie
## ⚠️ Symptômes à observer
## 💊 Traitement recommandé
## 🛡️ Prévention
## 📅 Urgence

IMPORTANT : Réponds UNIQUEMENT en ${_langueSelectionnee.nom}.
""",
            },
          ],
          "temperature": 0.7,
          "max_tokens": 1024,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data     = jsonDecode(utf8.decode(response.bodyBytes));
        final conseils = data['choices'][0]['message']['content'] ?? "";
        setState(() { _conseils = conseils; _isLoadingConseils = false; });
        await _sauvegarderAnalyse(conseils);
        ElevatedButton.icon(
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PharmaciePage(maladieCible: _maladie),
    ),
  ),
  icon: const Icon(Icons.medication),
  label: const Text("Voir les produits recommandés 💊"),
  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
),
// Après le diagnostic, bouton consulter un expert
if (_maladie.isNotEmpty && !_maladie.startsWith("❌"))
  ElevatedButton.icon(
    onPressed: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpertsPage(
          maladie:  _maladie,
          conseils: _conseils,
        ),
      ),
    ),
    icon: const Icon(Icons.support_agent, color: Colors.white),
    label: const Text("Consulter un expert 🤝",
        style: TextStyle(color: Colors.white)),
    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
  ),

      } else {
        final error = jsonDecode(response.body);
        setState(() {
          _conseils          = "❌ Erreur Groq : ${error['error']['message']}";
          _isLoadingConseils = false;
        });
      }
    } catch (e) {
      setState(() {
        _conseils          = "❌ Impossible de charger les conseils : ${e.toString()}";
        _isLoadingConseils = false;
      });
    }
  }

  // ─────────────────────────────────────────
  // SAUVEGARDE
  // ─────────────────────────────────────────
  Future<void> _sauvegarderAnalyse(String conseils) async {
    if (_imageFile == null || _maladie.isEmpty) return;

    double confianceDouble = 0.0;
    final match = RegExp(r'([\d.]+)').firstMatch(_confiance);
    if (match != null) {
      confianceDouble = double.tryParse(match.group(1)!) ?? 0.0;
      if (confianceDouble > 1) confianceDouble /= 100;
    }

    final now     = DateTime.now();
    final dateStr =
        "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    final analyse = Analyse(
      imagePath:  kIsWeb ? _imageFile!.name : _imageFile!.path,
      imageUrl:   '',
      maladie:    _maladie,
      confiance:  confianceDouble,
      top3:       _top3.isNotEmpty ? _top3 : "[]",
      conseils:   conseils,
      langue:     "${_langueSelectionnee.drapeau} ${_langueSelectionnee.nom}",
      date:       dateStr,
      latitude:   _dernierePosition?.latitude,
      longitude:  _dernierePosition?.longitude,
    );

    await DatabaseHelper.instance.insertAnalyse(analyse);

    if (_dernierePosition != null) _envoyerAnalyseGeo(analyse);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.save, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(_dernierePosition != null
                ? "Analyse sauvegardée avec GPS 📍"
                : "Analyse sauvegardée dans l'historique"),
          ]),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _envoyerAnalyseGeo(Analyse analyse) {
    http.post(
      Uri.parse("http://$_baseIP:8000/analyses/geo"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "maladie":   analyse.maladie,
        "confiance": analyse.confiance,
        "top3":      analyse.top3,
        "latitude":  analyse.latitude,
        "longitude": analyse.longitude,
        "date":      analyse.date,
      }),
    ).timeout(const Duration(seconds: 5)).catchError((_) {});
  }

  // ─────────────────────────────────────────
  // RÉINITIALISATION
  // ─────────────────────────────────────────
  Future<void> _reset() async {
    await _arreterLecture();
    setState(() {
      _imageFile           = null;
      _imageBytesWeb       = null;
      _imageNative         = null;
      _maladie             = "";
      _confiance           = "";
      _top3                = "";
      _conseils            = "";
      _dernierePosition    = null;
      _isLoadingPrediction = false;
      _isLoadingConseils   = false;
    });
  }

  // ─────────────────────────────────────────
  // ✅ WIDGET IMAGE COMPATIBLE WEB + NATIVE
  // ─────────────────────────────────────────
  Widget _buildImageWidget() {
    if (!_aUneImage) {
      return Container(
        height: 260,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.eco, size: 80, color: Colors.green),
            SizedBox(height: 10),
            Text("Aucune image sélectionnée",
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // ✅ Image.memory fonctionne sur Web ET Android
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        _imageBytesWeb!,
        height: 260,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }

  // ─────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool estSain =
        _maladie.toLowerCase().contains("sain") ||
        _maladie.toLowerCase().contains("healthy");

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détecteur de Maladies 🌿',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        centerTitle: true,
        actions: [
          // Langue
          TextButton.icon(
            onPressed: _ouvrirSelecteurLangue,
            icon: Text(_langueSelectionnee.drapeau,
                style: const TextStyle(fontSize: 20)),
            label: Text(_langueSelectionnee.nom,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          // Météo
          IconButton(
            icon: const Icon(Icons.wb_sunny_outlined, color: Colors.white),
            tooltip: 'Météo & Prévention',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MeteoPage())),
          ),
          // Dashboard
          IconButton(
            icon: const Icon(Icons.dashboard_outlined, color: Colors.white),
            tooltip: 'Tableau de bord',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DashboardPage())),
          ),
          // Carte
          IconButton(
            icon: const Icon(Icons.map_outlined, color: Colors.white),
            tooltip: "Carte des maladies",
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const CarteMaladiesPage())),
          ),
          // Historique
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            tooltip: "Historique",
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HistoriquePage())),
          ),
          // Chatbot
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined, color: Colors.white),
            tooltip: 'Assistant agricole',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatbotPage(
                  codeLangue:    _langueSelectionnee.code,
                  nomLangue:     _langueSelectionnee.nom,
                  drapeauLangue: _langueSelectionnee.drapeau,
                ),
              ),
            ),
          ),
          // Import


// Bouton dans l'AppBar
IconButton(
  icon: const Icon(Icons.medication, color: Colors.white),
  tooltip: "Pharmacie agricole",
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const PharmaciePage()),
  ),
),
IconButton(
  icon: const Icon(Icons.support_agent, color: Colors.white),
  tooltip: "Experts agronomes",
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const ExpertsPage()),
  ),
),
          // Dans _getConseilsGroq(), après avoir reçu les conseils :
          // Forum
          IconButton(
            icon: const Icon(Icons.forum, color: Colors.white),
            tooltip: "Forum",
            onPressed: () {
              // Sur desktop → message
              if (!kIsWeb &&
                  (Platform.isLinux ||
                      Platform.isWindows ||
                      Platform.isMacOS)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        "Le forum nécessite un smartphone Android."),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ForumPage()));
              } else {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const LoginPage()));
              }
            },
          ),
          // Multi-photos
          IconButton(
            icon: const Icon(Icons.photo_library, color: Colors.white),
            tooltip: "Diagnostic multi-photos",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MultiPhotoPage()),
            ),
          ),
          // Parcelles QR
          IconButton(
            icon: const Icon(Icons.qr_code_2, color: Colors.white),
            tooltip: 'Mes parcelles & QR codes',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ParcellesPage()),
            ),
          ),
          // Login
          IconButton(
            icon: const Icon(Icons.login, color: Colors.white),
            tooltip: "Connexion",
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LoginPage())),
          ),
          // Reset
          if (_aUneImage)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _reset,
              tooltip: 'Réinitialiser',
            ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [

            // ── Bandeau PC ───────────────────────
            if (!kIsWeb && !_cameraAvailable)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Sur PC, utilisez le bouton Galerie pour importer une image.",
                      style: TextStyle(color: Colors.orange, fontSize: 13),
                    ),
                  ),
                ]),
              ),

            // ── Résumé météo ─────────────────────
            const WidgetMeteoResume(),

            // ── Image ────────────────────────────
            _buildImageWidget(),

            const SizedBox(height: 20),

            // ── Boutons ──────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Tooltip(
                  message: _cameraAvailable
                      ? "Prendre une photo"
                      : "Caméra non disponible",
                  child: ElevatedButton.icon(
                    onPressed: (_isLoadingPrediction || !_cameraAvailable)
                        ? null
                        : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Caméra'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _cameraAvailable
                          ? Colors.green[100]
                          : Colors.grey[200],
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isLoadingPrediction
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galerie'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[100]),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Résultats ────────────────────────
            if (_isLoadingPrediction)
              const Column(children: [
                CircularProgressIndicator(color: Colors.green),
                SizedBox(height: 8),
                Text("Analyse de l'image en cours..."),
              ])
            else if (_maladie.isNotEmpty) ...[

              // Résultat maladie
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: estSain ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: estSain ? Colors.green : Colors.red),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                        estSain
                            ? Icons.check_circle
                            : Icons.warning_rounded,
                        color: estSain ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_maladie,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                      ),
                    ]),
                    if (_confiance.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(_confiance,
                          style: const TextStyle(color: Colors.grey)),
                    ],
                    if (_dernierePosition != null) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.location_on,
                            size: 14, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          "GPS : ${_dernierePosition!.latitude.toStringAsFixed(4)}, "
                          "${_dernierePosition!.longitude.toStringAsFixed(4)}",
                          style: const TextStyle(
                              fontSize: 12, color: Colors.blue),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),

              // Top 3
              if (_top3.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("📊 Top 3 des probabilités :",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue)),
                      const SizedBox(height: 6),
                      Text(_top3,
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Conseils
              if (_isLoadingConseils)
                Column(children: [
                  const CircularProgressIndicator(color: Colors.orange),
                  const SizedBox(height: 8),
                  Text(
                    "Génération des conseils en ${_langueSelectionnee.nom}...",
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ])
              else if (_conseils.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.medical_information,
                            color: Colors.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Conseils — ${_langueSelectionnee.drapeau} ${_langueSelectionnee.nom}",
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber),
                          ),
                        ),
                        if (!kIsWeb) ...[
                          IconButton(
                            onPressed: _lireConseils,
                            icon: Icon(
                              _isSpeaking && !_isPaused
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              color: Colors.green,
                              size: 32,
                            ),
                            tooltip: _isSpeaking && !_isPaused
                                ? "Pause"
                                : "Lire",
                          ),
                          if (_isSpeaking)
                            IconButton(
                              onPressed: _arreterLecture,
                              icon: const Icon(Icons.stop_circle,
                                  color: Colors.red, size: 32),
                              tooltip: "Arrêter",
                            ),
                        ],
                      ]),
                      const Divider(),
                      MarkdownBody(
                        data: _conseils,
                        styleSheet: MarkdownStyleSheet(
                          h2: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.green),
                          p: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isSpeaking)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.volume_up,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _isPaused
                              ? "Lecture en pause"
                              : "Lecture en cours (${_langueSelectionnee.nom})...",
                          style: const TextStyle(
                              color: Colors.green,
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
              ],
            ],

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}