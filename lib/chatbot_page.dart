import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

enum Expediteur { utilisateur, assistant, systeme }

class MessageChat {
  final String contenu;
  final Expediteur expediteur;
  final DateTime horodatage;
  final bool enChargement;

  const MessageChat({
    required this.contenu,
    required this.expediteur,
    required this.horodatage,
    this.enChargement = false,
  });
}

// ─────────────────────────────────────────────
// SUGGESTIONS RAPIDES PAR LANGUE
// ─────────────────────────────────────────────
const Map<String, List<String>> _suggestionsParLangue = {
  'fr': [
    'Ma tomate jaunit, que faire ?',
    'Comment traiter la rouille du maïs ?',
    'Quand planter les oignons ?',
    'Mes feuilles ont des taches noires',
    'Quel engrais pour le mil ?',
  ],
  'en': [
    'My tomato is yellowing, what to do?',
    'How to treat corn rust?',
    'When to plant onions?',
    'My leaves have black spots',
    'What fertilizer for millet?',
  ],
  'ha': [
    'Ganyen tumatina yana rawaya, me zan yi?',
    'Yadda ake magance tsatsa?',
    'Yaushe ake shuka albasa?',
  ],
  'dje': ['Tomate boro gaa si, maa ga ni ?', 'Maïs hareyboro maa ga wane ?'],
  'ar': [
    'أوراق الطماطم تصفر، ماذا أفعل؟',
    'كيف أعالج صدأ الذرة؟',
    'متى أزرع البصل؟',
  ],
};
const Map<String, String> _localeSTT = {
  'fr': 'fr_FR',
  'en': 'en_US',
  'ha': 'ha_NG',
  'dje': 'fr_FR', // fallback
  'ar': 'ar_SA',
  'ff': 'fr_FR', // fallback
  'tmh': 'fr_FR', // fallback
};

// ═════════════════════════════════════════════
// PAGE CHATBOT
// ═════════════════════════════════════════════
class ChatbotPage extends StatefulWidget {
  final String codeLangue; // ex: 'fr', 'en', 'ha'
  final String nomLangue; // ex: 'Français'
  final String drapeauLangue;

  const ChatbotPage({
    super.key,
    required this.codeLangue,
    required this.nomLangue,
    required this.drapeauLangue,
  });

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage>
    with TickerProviderStateMixin {
  final List<MessageChat> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  // Groq
  static const String _groqApiKey =
      "ANCIENNE_CLE_API_GROQ"; // Remplacez par votre clé API Groq
  final List<Map<String, String>> _historique = []; // contexte Groq
  bool _enChargement = false;

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  Process? _espeakProcess;

  // STT
  final stt.SpeechToText _sttEngine = stt.SpeechToText();
  bool _sttDisponible = false;
  bool _ecoute = false;
  String _textePartiel = '';

  @override
  void initState() {
    super.initState();
    _initTts();
    _initStt();
    _ajouterMessageBienvenue();
  }

  @override
  void dispose() {
    _tts.stop();
    _sttEngine.stop();
    _espeakProcess?.kill();
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────
  // INIT TTS
  // ─────────────────────────────────────────
  Future<void> _initTts() async {
    if (kIsWeb || Platform.isLinux) return;
    await _tts.setLanguage(widget.codeLangue);
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  // ─────────────────────────────────────────
  // INIT STT
  // ─────────────────────────────────────────
  Future<void> _initStt() async {
    if (kIsWeb) {
      // Sur Web, speech_to_text peut fonctionner via l'API Web Speech
      _sttDisponible = await _sttEngine.initialize(
        onError: (_) => setState(() => _ecoute = false),
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            setState(() {
              _ecoute = false;
            });
            if (_textePartiel.isNotEmpty) {
              _controller.text = _textePartiel;
              _textePartiel = '';
            }
          }
        },
      );
    } else {
      try {
        _sttDisponible = await _sttEngine.initialize(
          onError: (_) => setState(() => _ecoute = false),
          onStatus: (s) {
            if (s == 'done' || s == 'notListening') {
              setState(() {
                _ecoute = false;
              });
              if (_textePartiel.isNotEmpty) {
                _controller.text = _textePartiel;
                _textePartiel = '';
              }
            }
          },
        );
      } catch (_) {
        _sttDisponible = false;
      }
    }
    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────
  // MESSAGE DE BIENVENUE
  // ─────────────────────────────────────────
  void _ajouterMessageBienvenue() {
    const bienvenues = {
      'fr':
          '👋 Bonjour ! Je suis votre assistant agricole. Posez-moi vos questions sur vos cultures, maladies, traitements ou conseils de saison. Je réponds en **Français**.',
      'en':
          '👋 Hello! I am your agricultural assistant. Ask me about your crops, diseases, treatments or seasonal advice. I answer in **English**.',
      'ha':
          '👋 Sannu! Ni ne mataimakiyar noma. Tambaye ni game da amfanin gonarku, cututtuka, ko magani. Zan amsa da **Haoussa**.',
      'dje':
          '👋 Ni nga fo ! Ni ga i danga gaa mana nooŋ. I ga n hãy mana baani wane ra. Ni ga amsa **Zarma** daŋ.',
      'ar':
          '👋 مرحباً! أنا مساعدك الزراعي. اسألني عن محاصيلك والأمراض والعلاجات. سأجيب باللغة **العربية**.',
      'ff':
          '👋 Jam waali! Mi yimɓe mawnirɗe maa. Mbaylaago am ko lesdi e ko dañi. Mi jaabatoo e **Fulfulde**.',
      'tmh':
          '👋 Azul! Nekk d-amdan-nnek n tegrewt. Aɣ-i awal γef iɣsan nnk. Ad k-rreɣ s **Tamasheq**.',
    };
    final texte = bienvenues[widget.codeLangue] ?? bienvenues['fr']!;
    _ajouterMessage(texte, Expediteur.assistant);

    // Initialiser le contexte Groq
    _historique.add({'role': 'system', 'content': _systemPrompt});
  }

  String get _systemPrompt =>
      '''
Tu es un assistant agricole expert et bienveillant, spécialisé dans l'agriculture en Afrique de l'Ouest (Niger, Nigeria, Mali, Sénégal...).

Tes domaines d'expertise :
- Maladies des plantes (symptômes, diagnostic, traitement)
- Cultures locales : mil, sorgho, niébé, arachide, maïs, tomate, oignon, vigne, pommier
- Traitements phytosanitaires (produits, dosages, moments d'application)
- Irrigation, fertilisation, rotation des cultures
- Météo et impact sur les cultures
- Conseils de saison et calendrier cultural

Règles importantes :
- Réponds TOUJOURS et UNIQUEMENT en ${widget.nomLangue}
- Sois concis, pratique et accessible pour un agriculteur non expert
- Utilise des émojis pour rendre la réponse plus lisible (🌿 🌾 💊 ⚠️ ✅)
- Si la question est hors sujet agricole, rappelle gentiment ton domaine
- Structure tes réponses avec des points clés quand c'est long
''';

  void _ajouterMessage(
    String contenu,
    Expediteur expediteur, {
    bool enChargement = false,
  }) {
    setState(() {
      _messages.add(
        MessageChat(
          contenu: contenu,
          expediteur: expediteur,
          horodatage: DateTime.now(),
          enChargement: enChargement,
        ),
      );
    });
    _scrollerVersLeBas();
  }

  void _scrollerVersLeBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─────────────────────────────────────────
  // ENVOI MESSAGE À GROQ
  // ─────────────────────────────────────────
  Future<void> _envoyerMessage(String texte) async {
    if (texte.trim().isEmpty || _enChargement) return;

    final question = texte.trim();
    _controller.clear();

    // Ajouter message utilisateur
    _ajouterMessage(question, Expediteur.utilisateur);

    // Bulle de chargement "..."
    setState(() {
      _enChargement = true;
    });
    _ajouterMessage('', Expediteur.assistant, enChargement: true);

    // Ajouter au contexte
    _historique.add({'role': 'user', 'content': question});

    try {
      final response = await http
          .post(
            Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_groqApiKey',
            },
            body: jsonEncode({
              'model': 'llama-3.3-70b-versatile',
              'messages': _historique,
              'temperature': 0.7,
              'max_tokens': 800,
            }),
          )
          .timeout(const Duration(seconds: 20));

      // Supprimer la bulle de chargement
      setState(() {
        _messages.removeWhere((m) => m.enChargement);
        _enChargement = false;
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final reponse = data['choices'][0]['message']['content'] as String;

        // Ajouter la réponse au contexte
        _historique.add({'role': 'assistant', 'content': reponse});

        _ajouterMessage(reponse, Expediteur.assistant);

        // Lire la réponse automatiquement
        await _lireTexte(reponse);
      } else {
        _ajouterMessage(
          '❌ Erreur de connexion. Vérifiez votre internet.',
          Expediteur.systeme,
        );
      }
    } catch (e) {
      setState(() {
        _messages.removeWhere((m) => m.enChargement);
        _enChargement = false;
      });
      _ajouterMessage(
        '❌ Impossible de contacter l\'assistant. Réessayez.',
        Expediteur.systeme,
      );
    }
  }

  // ─────────────────────────────────────────
  // TTS — LIRE UNE RÉPONSE
  // ─────────────────────────────────────────
  Future<void> _lireTexte(String texte) async {
    // Nettoyer le markdown pour la lecture
    final propre = texte
        .replaceAll(RegExp(r'#{1,6}\s*'), '')
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1')
        .replaceAll(RegExp(r'[🌿🌾💊⚠️✅👋📅🛡️]'), '')
        .replaceAll(RegExp(r'\n{2,}'), '. ')
        .trim();

    if (!kIsWeb && Platform.isLinux) {
      _espeakProcess?.kill();
      setState(() => _isSpeaking = true);
      try {
        _espeakProcess = await Process.start('espeak-ng', [
          '-v',
          widget.codeLangue == 'ar' ? 'ar' : 'fr',
          '-s',
          '150',
          '-p',
          '50',
          propre,
        ]);
        _espeakProcess!.exitCode.then((_) {
          if (mounted) setState(() => _isSpeaking = false);
        });
      } catch (_) {
        if (mounted) setState(() => _isSpeaking = false);
      }
    } else if (!kIsWeb) {
      await _tts.setLanguage(widget.codeLangue);
      setState(() => _isSpeaking = true);
      await _tts.speak(propre);
    }
  }

  Future<void> _arreterLecture() async {
    _espeakProcess?.kill();
    _espeakProcess = null;
    await _tts.stop();
    setState(() => _isSpeaking = false);
  }

  // ─────────────────────────────────────────
  // STT — RECONNAISSANCE VOCALE
  // ─────────────────────────────────────────
  Future<void> _toggleEcoute() async {
    if (_ecoute) {
      await _sttEngine.stop();
      setState(() => _ecoute = false);
      return;
    }

    if (!_sttDisponible) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reconnaissance vocale non disponible sur cet appareil.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final locale = _localeSTT[widget.codeLangue] ?? 'fr_FR';

    setState(() {
      _ecoute = true;
      _textePartiel = '';
    });

    await _sttEngine.listen(
      localeId: locale,
      onResult: (result) {
        setState(() {
          _textePartiel = result.recognizedWords;
          _controller.text = _textePartiel;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        });
        if (result.finalResult && _textePartiel.isNotEmpty) {
          setState(() => _ecoute = false);
          _envoyerMessage(_textePartiel);
          _textePartiel = '';
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      cancelOnError: true,
    );
  }

  // ─────────────────────────────────────────
  // EFFACER LA CONVERSATION
  // ─────────────────────────────────────────
  void _effacerConversation() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Effacer la conversation ?'),
        content: const Text('Tout l\'historique sera supprimé.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _messages.clear();
                _historique.clear();
              });
              _ajouterMessageBienvenue();
            },
            child: const Text('Effacer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final suggestions =
        _suggestionsParLangue[widget.codeLangue] ??
        _suggestionsParLangue['fr']!;

    return Scaffold(
      backgroundColor: const Color(0xFFECF3EC),
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Text('🌾', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assistant Agricole',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4ADE80),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.drapeauLangue} ${widget.nomLangue}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_isSpeaking)
            IconButton(
              icon: const Icon(Icons.volume_off),
              onPressed: _arreterLecture,
              tooltip: 'Arrêter lecture',
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _effacerConversation,
            tooltip: 'Effacer conversation',
          ),
        ],
      ),

      body: Column(
        children: [
          // ── Suggestions rapides ──────────────
          if (_messages.length <= 1)
            _SuggestionsRapides(
              suggestions: suggestions,
              onTap: _envoyerMessage,
            ),

          // ── Liste de messages ────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final msg = _messages[i];
                // Afficher la date si premier message ou jour différent
                final afficherDate =
                    i == 0 ||
                    !_memJour(_messages[i - 1].horodatage, msg.horodatage);
                return Column(
                  children: [
                    if (afficherDate) _LabelDate(date: msg.horodatage),
                    _BulleMessage(message: msg),
                  ],
                );
              },
            ),
          ),

          // ── Zone de saisie ───────────────────
          _ZoneSaisie(
            controller: _controller,
            ecoute: _ecoute,
            enChargement: _enChargement,
            sttDispo: _sttDisponible,
            onEnvoyer: () => _envoyerMessage(_controller.text),
            onToggleVoix: _toggleEcoute,
          ),
        ],
      ),
    );
  }

  bool _memJour(DateTime a, DateTime b) =>
      a.day == b.day && a.month == b.month && a.year == b.year;
}

// ═════════════════════════════════════════════
// WIDGET SUGGESTIONS RAPIDES
// ═════════════════════════════════════════════
class _SuggestionsRapides extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onTap;

  const _SuggestionsRapides({required this.suggestions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              '💡 Questions fréquentes',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => onTap(suggestions[i]),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    suggestions[i],
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.green.shade800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// WIDGET BULLE DE MESSAGE
// ═════════════════════════════════════════════
class _BulleMessage extends StatelessWidget {
  final MessageChat message;
  const _BulleMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final estUtilisateur = message.expediteur == Expediteur.utilisateur;
    final estSysteme = message.expediteur == Expediteur.systeme;

    // Message système (erreurs)
    if (estSysteme) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Text(
            message.contenu,
            style: TextStyle(fontSize: 13, color: Colors.red.shade700),
          ),
        ),
      );
    }

    return Align(
      alignment: estUtilisateur ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: estUtilisateur ? 60 : 0,
          right: estUtilisateur ? 0 : 60,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Avatar assistant
            if (!estUtilisateur) ...[
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: 6, bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('🌾', style: TextStyle(fontSize: 14)),
                ),
              ),
            ],

            // Bulle
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: estUtilisateur ? Colors.green.shade600 : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(estUtilisateur ? 18 : 4),
                    bottomRight: Radius.circular(estUtilisateur ? 4 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: message.enChargement
                    ? const _AnimationEllipsis()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Texte du message
                          Text(
                            message.contenu,
                            style: TextStyle(
                              fontSize: 14,
                              color: estUtilisateur
                                  ? Colors.white
                                  : Colors.black87,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Horodatage
                          Text(
                            '${message.horodatage.hour.toString().padLeft(2, '0')}:'
                            '${message.horodatage.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 10,
                              color: estUtilisateur
                                  ? Colors.white70
                                  : Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            // Avatar utilisateur
            if (estUtilisateur) ...[
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(left: 6, bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.person, size: 18, color: Colors.green),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// ANIMATION "..." EN CHARGEMENT
// ═════════════════════════════════════════════
class _AnimationEllipsis extends StatefulWidget {
  const _AnimationEllipsis();

  @override
  State<_AnimationEllipsis> createState() => _AnimationEllipsisState();
}

class _AnimationEllipsisState extends State<_AnimationEllipsis>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  int _points = 0;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 600),
          )
          ..addListener(() {
            setState(() => _points = (_ctrl.value * 3).floor());
          })
          ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: i <= _points ? Colors.green.shade600 : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// LABEL DATE
// ═════════════════════════════════════════════
class _LabelDate extends StatelessWidget {
  final DateTime date;
  const _LabelDate({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (date.day == now.day && date.month == now.month) {
      label = "Aujourd'hui";
    } else {
      label =
          "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════
// ZONE DE SAISIE (texte + micro + envoi)
// ═════════════════════════════════════════════
class _ZoneSaisie extends StatefulWidget {
  final TextEditingController controller;
  final bool ecoute;
  final bool enChargement;
  final bool sttDispo;
  final VoidCallback onEnvoyer;
  final VoidCallback onToggleVoix;

  const _ZoneSaisie({
    required this.controller,
    required this.ecoute,
    required this.enChargement,
    required this.sttDispo,
    required this.onEnvoyer,
    required this.onToggleVoix,
  });

  @override
  State<_ZoneSaisie> createState() => _ZoneSaisieState();
}

class _ZoneSaisieState extends State<_ZoneSaisie> {
  bool _aduTexte = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() {
      setState(() => _aduTexte = widget.controller.text.isNotEmpty);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      child: Row(
        children: [
          // ── Bouton micro ──────────────────────
          if (widget.sttDispo)
            GestureDetector(
              onTap: widget.onToggleVoix,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.ecoute ? Colors.red : Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.ecoute ? Icons.mic : Icons.mic_none,
                  color: widget.ecoute ? Colors.white : Colors.green,
                  size: 22,
                ),
              ),
            ),

          if (widget.sttDispo) const SizedBox(width: 8),

          // ── Champ texte ───────────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: widget.ecoute
                      ? Colors.red.shade200
                      : Colors.grey.shade300,
                ),
              ),
              child: TextField(
                controller: widget.controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: widget.ecoute
                      ? '🎙️ Parlez maintenant...'
                      : 'Posez votre question...',
                  hintStyle: TextStyle(
                    color: widget.ecoute
                        ? Colors.red.shade300
                        : Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => widget.onEnvoyer(),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Bouton envoi ──────────────────────
          GestureDetector(
            onTap: widget.enChargement ? null : widget.onEnvoyer,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _aduTexte && !widget.enChargement
                    ? Colors.green.shade600
                    : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: widget.enChargement
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
