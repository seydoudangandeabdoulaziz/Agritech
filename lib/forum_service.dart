import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

// ─────────────────────────────────────────────
// MODÈLE MESSAGE
// ─────────────────────────────────────────────
class Message {
  final String id;
  final String uid;
  final String nomAuteur;
  final String langueAuteur;
  final String type;
  final String contenu;
  final String? texteOriginal;
  final Timestamp date;
  final Map<String, String> traductions;

  Message({
    required this.id,
    required this.uid,
    required this.nomAuteur,
    required this.langueAuteur,
    required this.type,
    required this.contenu,
    this.texteOriginal,
    required this.date,
    required this.traductions,
  });

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Message(
      id: doc.id,
      uid: data['uid'] ?? '',
      nomAuteur: data['nomAuteur'] ?? 'Anonyme',
      langueAuteur: data['langueAuteur'] ?? 'fr',
      type: data['type'] ?? 'texte',
      contenu: data['contenu'] ?? '',
      texteOriginal: data['texteOriginal'],
      date: data['date'] ?? Timestamp.now(),
      traductions: Map<String, String>.from(data['traductions'] ?? {}),
    );
  }
}

// ─────────────────────────────────────────────
// SERVICE FORUM
// ─────────────────────────────────────────────
class ForumService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  static const String _groqApiKey = "VOTRE_CLE_API_GROQ_ICI";

  static const List<String> _langues = [
    'fr', 'en', 'ha', 'dje', 'ar', 'ff', 'tmh'
  ];

  static const Map<String, String> _nomsLangues = {
    'fr': 'Français', 'en': 'Anglais', 'ha': 'Haoussa',
    'dje': 'Zarma', 'ar': 'Arabe', 'ff': 'Fulfulde', 'tmh': 'Tamasheq',
  };

  // ─────────────────────────────────────────────
  // FLUX MESSAGES TEMPS RÉEL
  // ─────────────────────────────────────────────
  static Stream<List<Message>> getMessages() {
    return _db
        .collection('forum')
        .orderBy('date', descending: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => Message.fromFirestore(doc)).toList());
  }

  // ─────────────────────────────────────────────
  // ENVOYER TEXTE
  // ─────────────────────────────────────────────
  static Future<void> envoyerTexte(String texte) async {
    final user = AuthService.currentUser;
    if (user == null) return;

    final profil = await AuthService.getProfil(user.uid);
    final langueAuteur = profil?['langue'] ?? 'fr';
    final nomAuteur = profil?['nom'] ?? 'Agriculteur';

    final traductions = await _traduireDansToutes(texte, langueAuteur);

    await _db.collection('forum').add({
      'uid': user.uid,
      'nomAuteur': nomAuteur,
      'langueAuteur': langueAuteur,
      'type': 'texte',
      'contenu': texte,
      'date': FieldValue.serverTimestamp(),
      'traductions': traductions,
    });
  }

  // ─────────────────────────────────────────────
  // ENVOYER PHOTO (Android/iOS — File)
  // ─────────────────────────────────────────────
  static Future<void> envoyerPhoto(File photo, String? legende) async {
    final user = AuthService.currentUser;
    if (user == null) return;

    final profil = await AuthService.getProfil(user.uid);
    final langueAuteur = profil?['langue'] ?? 'fr';
    final nomAuteur = profil?['nom'] ?? 'Agriculteur';

    final ref = _storage.ref().child(
        'forum/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putFile(photo);
    final url = await ref.getDownloadURL();

    Map<String, String> traductions = {};
    if (legende != null && legende.isNotEmpty) {
      traductions = await _traduireDansToutes(legende, langueAuteur);
    }

    await _db.collection('forum').add({
      'uid': user.uid,
      'nomAuteur': nomAuteur,
      'langueAuteur': langueAuteur,
      'type': 'photo',
      'contenu': url,
      'texteOriginal': legende ?? '',
      'date': FieldValue.serverTimestamp(),
      'traductions': traductions,
    });
  }

  // ─────────────────────────────────────────────
  // ✅ ENVOYER PHOTO (Web — Uint8List bytes)
  // ─────────────────────────────────────────────
  static Future<void> envoyerPhotoBytes(
      Uint8List bytes, String filename, String? legende) async {
    final user = AuthService.currentUser;
    if (user == null) return;

    final profil = await AuthService.getProfil(user.uid);
    final langueAuteur = profil?['langue'] ?? 'fr';
    final nomAuteur = profil?['nom'] ?? 'Agriculteur';

    // ✅ Upload via putData (compatible Web)
    final ref = _storage.ref().child(
        'forum/${DateTime.now().millisecondsSinceEpoch}_$filename');
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();

    Map<String, String> traductions = {};
    if (legende != null && legende.isNotEmpty) {
      traductions = await _traduireDansToutes(legende, langueAuteur);
    }

    await _db.collection('forum').add({
      'uid': user.uid,
      'nomAuteur': nomAuteur,
      'langueAuteur': langueAuteur,
      'type': 'photo',
      'contenu': url,
      'texteOriginal': legende ?? '',
      'date': FieldValue.serverTimestamp(),
      'traductions': traductions,
    });
  }

  // ─────────────────────────────────────────────
  // ENVOYER VOCAL (Android/iOS uniquement)
  // ─────────────────────────────────────────────
  static Future<void> envoyerVocal(
      File fichierAudio, String transcription) async {
    final user = AuthService.currentUser;
    if (user == null) return;

    final profil = await AuthService.getProfil(user.uid);
    final langueAuteur = profil?['langue'] ?? 'fr';
    final nomAuteur = profil?['nom'] ?? 'Agriculteur';

    final ref = _storage.ref().child(
        'forum/vocaux/${DateTime.now().millisecondsSinceEpoch}.m4a');
    await ref.putFile(fichierAudio);
    final url = await ref.getDownloadURL();

    final traductions =
        await _traduireDansToutes(transcription, langueAuteur);

    await _db.collection('forum').add({
      'uid': user.uid,
      'nomAuteur': nomAuteur,
      'langueAuteur': langueAuteur,
      'type': 'vocal',
      'contenu': url,
      'texteOriginal': transcription,
      'date': FieldValue.serverTimestamp(),
      'traductions': traductions,
    });
  }

  // ─────────────────────────────────────────────
  // TRADUCTION VIA GROQ
  // ─────────────────────────────────────────────
  static Future<Map<String, String>> _traduireDansToutes(
      String texte, String langueSource) async {
    final Map<String, String> traductions = {langueSource: texte};

    try {
      final languesCibles =
          _langues.where((l) => l != langueSource).toList();
      final nomsLangCibles =
          languesCibles.map((l) => _nomsLangues[l] ?? l).join(', ');

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
                  "Tu es un traducteur expert. Réponds UNIQUEMENT avec un objet JSON valide sans markdown ni backticks.",
            },
            {
              "role": "user",
              "content": """
Traduis ce texte de ${_nomsLangues[langueSource]} vers : $nomsLangCibles.
Texte : "$texte"
Réponds avec ce JSON exact :
{"en":"...","fr":"...","ha":"...","dje":"...","ar":"...","ff":"...","tmh":"..."}
""",
            },
          ],
          "temperature": 0.3,
          "max_tokens": 1024,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content =
            data['choices'][0]['message']['content'] as String;
        final jsonResult = jsonDecode(content) as Map<String, dynamic>;
        jsonResult.forEach((key, value) {
          traductions[key] = value.toString();
        });
      }
    } catch (e) {
      // Garde la langue originale en fallback
    }

    return traductions;
  }

  // ─────────────────────────────────────────────
  // TRADUCTION POUR UNE LANGUE
  // ─────────────────────────────────────────────
  static String getTraduction(Message message, String langueVoulue) {
    if (message.traductions.containsKey(langueVoulue)) {
      return message.traductions[langueVoulue]!;
    }
    return message.type == 'texte'
        ? message.contenu
        : (message.texteOriginal ?? '');
  }

  // ─────────────────────────────────────────────
  // SUPPRIMER MESSAGE
  // ─────────────────────────────────────────────
  static Future<void> supprimerMessage(String messageId) async {
    await _db.collection('forum').doc(messageId).delete();
  }
}