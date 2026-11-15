import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'auth_service.dart';
import 'forum_service.dart';
import 'login_page.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const Map<String, Map<String, String>> languesInfo = {
  'fr':  {'nom': 'Français',  'drapeau': '🇫🇷'},
  'en':  {'nom': 'English',   'drapeau': '🇬🇧'},
  'ha':  {'nom': 'Haoussa',   'drapeau': '🇳🇬'},
  'dje': {'nom': 'Zarma',     'drapeau': '🇳🇪'},
  'ar':  {'nom': 'العربية',   'drapeau': '🇸🇦'},
  'ff':  {'nom': 'Fulfulde',  'drapeau': '🇬🇳'},
  'tmh': {'nom': 'Tamasheq', 'drapeau': '🇲🇱'},
};

class ForumPage extends StatefulWidget {
  const ForumPage({super.key});

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  final TextEditingController _texteController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  final FlutterTts _tts = FlutterTts();

  bool _isEnvoi = false;
  bool _isEnregistrement = false;
  String _langueAffichage = 'fr';
  Map<String, dynamic>? _profil;

  // ✅ Vérification plateforme pour les fonctionnalités natives
  bool get _supportsAudio => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool get _supportsCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _chargerProfil();
  }

  @override
  void dispose() {
    _texteController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _recorder.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _chargerProfil() async {
    final user = AuthService.currentUser;
    if (user != null) {
      final profil = await AuthService.getProfil(user.uid);
      if (mounted) {
        setState(() {
          _profil = profil;
          _langueAffichage = profil?['langue'] ?? 'fr';
        });
      }
    }
  }

  // ─────────────────────────────────────────────
  // ENVOYER MESSAGE TEXTE
  // ─────────────────────────────────────────────
  Future<void> _envoyerTexte() async {
    final texte = _texteController.text.trim();
    if (texte.isEmpty) return;

    setState(() => _isEnvoi = true);
    _texteController.clear();

    try {
      await ForumService.envoyerTexte(texte);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur envoi : $e"),
              backgroundColor: Colors.red),
        );
      }
    }

    setState(() => _isEnvoi = false);
    _scrollerBas();
  }

  // ─────────────────────────────────────────────
  // ENVOYER PHOTO
  // ─────────────────────────────────────────────
  Future<void> _envoyerPhoto() async {
    // ✅ Sur Web : utiliser galerie uniquement
    final ImageSource source = kIsWeb
        ? ImageSource.gallery
        : ImageSource.gallery;

    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        imageQuality: 70, // ✅ Réduire la taille pour l'upload
        maxWidth: 1024,
      );
      if (photo == null) return;

      final legende = await _demanderLegende();
      setState(() => _isEnvoi = true);

      if (kIsWeb) {
        // ✅ Sur Web : lire les bytes directement
        final bytes = await photo.readAsBytes();
        await ForumService.envoyerPhotoBytes(
            bytes, photo.name, legende);
      } else {
        // ✅ Sur Android/iOS : utiliser File
        await ForumService.envoyerPhoto(File(photo.path), legende);
      }

      setState(() => _isEnvoi = false);
      _scrollerBas();
    } catch (e) {
      setState(() => _isEnvoi = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur photo : $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _demanderLegende() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Ajouter une légende ?"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
              hintText: "Décrivez ce que vous voyez..."),
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text("Ignorer")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text("Envoyer",
                  style: TextStyle(color: Colors.green))),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // ENREGISTREMENT VOCAL
  // ─────────────────────────────────────────────
  Future<void> _toggleEnregistrement() async {
    // ✅ Vocal non supporté sur Web
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "L'enregistrement vocal nécessite l'application Android."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isEnregistrement) {
      // Arrêter l'enregistrement
      final path = await _recorder.stop();
      setState(() => _isEnregistrement = false);

      if (path != null) {
        final transcription = await _demanderTranscription();
        if (transcription != null && transcription.isNotEmpty) {
          setState(() => _isEnvoi = true);
          try {
            await ForumService.envoyerVocal(File(path), transcription);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Erreur vocal : $e"),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
          setState(() => _isEnvoi = false);
          _scrollerBas();
        }
      }
    } else {
      // ✅ Vérifier la permission
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "Permission microphone refusée. Activez-la dans les paramètres."),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      try {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/vocal_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc, // ✅ Meilleure compatibilité
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: path,
        );
        setState(() => _isEnregistrement = true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Impossible de démarrer l'enregistrement : $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<String?> _demanderTranscription() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Que dites-vous ?"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Tapez ce que vous avez dit pour que les autres agriculteurs puissent le lire dans leur langue.",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                  hintText: "Transcription du message vocal..."),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text("Annuler")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text("Confirmer",
                  style: TextStyle(color: Colors.green))),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // LECTURE TTS
  // ─────────────────────────────────────────────
  Future<void> _lireMessage(Message message) async {
    if (kIsWeb) return; // TTS limité sur Web
    final texte = ForumService.getTraduction(message, _langueAffichage);
    if (texte.isEmpty) return;
    await _tts.setLanguage(_getTtsCode(_langueAffichage));
    await _tts.setSpeechRate(0.45);
    await _tts.speak(texte);
  }

  String _getTtsCode(String langue) {
    switch (langue) {
      case 'fr': return 'fr-FR';
      case 'en': return 'en-US';
      case 'ar': return 'ar';
      default: return 'fr-FR';
    }
  }

  Future<void> _lireAudio(String url) async {
    await _audioPlayer.stop();
    await _audioPlayer.play(UrlSource(url));
  }

  void _scrollerBas() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _deconnecter() async {
    await AuthService.deconnecter();
    if (mounted) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const LoginPage()));
    }
  }

  // ─────────────────────────────────────────────
  // INTERFACE
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Forum Agriculteurs 🌾",
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        actions: [
          // Sélecteur langue
          PopupMenuButton<String>(
            icon: Text(languesInfo[_langueAffichage]?['drapeau'] ?? '🌍',
                style: const TextStyle(fontSize: 22)),
            tooltip: "Langue d'affichage",
            onSelected: (code) => setState(() => _langueAffichage = code),
            itemBuilder: (_) => languesInfo.entries.map((e) {
              return PopupMenuItem(
                value: e.key,
                child: Row(
                  children: [
                    Text(e.value['drapeau']!,
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text(e.value['nom']!),
                    if (e.key == _langueAffichage) ...[
                      const Spacer(),
                      const Icon(Icons.check, color: Colors.green, size: 18),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
          // Menu profil
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle, color: Colors.white),
            onSelected: (value) {
              if (value == 'logout') _deconnecter();
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(_profil?['nom'] ?? 'Mon compte',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: 18),
                    SizedBox(width: 8),
                    Text("Se déconnecter",
                        style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Bandeau info Web ──
          if (kIsWeb)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              color: Colors.orange[50],
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Photo disponible sur Web. Vocal et TTS nécessitent l'app Android.",
                      style:
                          TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          // ── Bandeau langue ──
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            color: Colors.green[50],
            child: Row(
              children: [
                const Icon(Icons.translate, color: Colors.green, size: 16),
                const SizedBox(width: 6),
                Text(
                  "Affichage en : ${languesInfo[_langueAffichage]?['drapeau']} ${languesInfo[_langueAffichage]?['nom']}",
                  style:
                      const TextStyle(color: Colors.green, fontSize: 13),
                ),
              ],
            ),
          ),

          // ── Messages ──
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: ForumService.getMessages(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: Colors.green));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.forum,
                            size: 60, color: Colors.grey[300]),
                        const SizedBox(height: 12),
                        Text("Soyez le premier à partager !",
                            style: TextStyle(color: Colors.grey[400])),
                      ],
                    ),
                  );
                }
                final messages = snapshot.data!;
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (_, i) => _buildMessage(messages[i]),
                );
              },
            ),
          ),

          // ── Zone de saisie ──
          _buildZoneSaisie(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // BULLE DE MESSAGE
  // ─────────────────────────────────────────────
  Widget _buildMessage(Message message) {
    final estMoi = message.uid == AuthService.currentUser?.uid;
    final texteAffiche =
        ForumService.getTraduction(message, _langueAffichage);
    final drapeau =
        languesInfo[message.langueAuteur]?['drapeau'] ?? '🌍';

    return Align(
      alignment: estMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: estMoi ? Colors.green[100] : Colors.white,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight:
                estMoi ? const Radius.circular(0) : null,
            bottomLeft:
                !estMoi ? const Radius.circular(0) : null,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!estMoi)
                Row(
                  children: [
                    Text(drapeau),
                    const SizedBox(width: 4),
                    Text(message.nomAuteur,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                            fontSize: 13)),
                  ],
                ),

              const SizedBox(height: 4),

              if (message.type == 'texte')
                Text(texteAffiche,
                    style: const TextStyle(fontSize: 15))
              else if (message.type == 'photo') ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(message.contenu,
                      height: 180, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                            height: 100,
                            color: Colors.grey[200],
                            child: const Icon(Icons.broken_image,
                                color: Colors.grey),
                          )),
                ),
                if (texteAffiche.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(texteAffiche,
                      style: const TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic)),
                ],
              ] else if (message.type == 'vocal') ...[
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.play_circle_filled,
                          color: Colors.green, size: 36),
                      onPressed: () => _lireAudio(message.contenu),
                    ),
                    const Text("Message vocal",
                        style:
                            TextStyle(fontStyle: FontStyle.italic)),
                  ],
                ),
                if (texteAffiche.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text("📝 $texteAffiche",
                      style: const TextStyle(fontSize: 13)),
                ],
              ],

              const SizedBox(height: 6),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formaterDate(message.date),
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500])),
                  Row(
                    children: [
                      if (!kIsWeb &&
                          (message.type != 'vocal' ||
                              texteAffiche.isNotEmpty))
                        InkWell(
                          onTap: () => _lireMessage(message),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.volume_up,
                                color: Colors.green, size: 18),
                          ),
                        ),
                      if (estMoi) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => ForumService.supprimerMessage(
                              message.id),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.delete_outline,
                                color: Colors.red, size: 18),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // ZONE DE SAISIE
  // ─────────────────────────────────────────────
  Widget _buildZoneSaisie() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ✅ Bouton photo (disponible partout)
          IconButton(
            icon: const Icon(Icons.photo, color: Colors.green),
            onPressed: _isEnvoi ? null : _envoyerPhoto,
            tooltip: "Envoyer une photo",
          ),

          // ✅ Bouton vocal (Android/iOS uniquement)
          Tooltip(
            message: kIsWeb
                ? "Vocal disponible sur Android uniquement"
                : _isEnregistrement
                    ? "Arrêter l'enregistrement"
                    : "Envoyer un vocal",
            child: IconButton(
              icon: Icon(
                _isEnregistrement ? Icons.stop_circle : Icons.mic,
                color: kIsWeb
                    ? Colors.grey
                    : _isEnregistrement
                        ? Colors.red
                        : Colors.green,
                size: 28,
              ),
              onPressed: _isEnvoi ? null : _toggleEnregistrement,
            ),
          ),

          // Champ texte
          Expanded(
            child: TextField(
              controller: _texteController,
              maxLines: null,
              decoration: InputDecoration(
                hintText: _isEnregistrement
                    ? "🎙️ Enregistrement en cours..."
                    : "Votre message...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
              enabled: !_isEnregistrement,
            ),
          ),

          const SizedBox(width: 8),

          _isEnvoi
              ? const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                      color: Colors.green, strokeWidth: 2))
              : IconButton(
                  icon: const Icon(Icons.send,
                      color: Colors.green, size: 28),
                  onPressed: _envoyerTexte,
                  tooltip: "Envoyer",
                ),
        ],
      ),
    );
  }

  String _formaterDate(Timestamp timestamp) {
    final dt = timestamp.toDate();
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }
}