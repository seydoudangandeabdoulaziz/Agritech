import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'experts_page.dart';

class ConsultationPage extends StatefulWidget {
  final String  consultationId;
  final Expert  expert;
  final String? maladie;

  const ConsultationPage({
    super.key,
    required this.consultationId,
    required this.expert,
    this.maladie,
  });

  @override
  State<ConsultationPage> createState() => _ConsultationPageState();
}

class _ConsultationPageState extends State<ConsultationPage> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController      _scrollCtrl    = ScrollController();
  final ImagePicker           _picker        = ImagePicker();

  final String _uid = FirebaseAuth.instance.currentUser!.uid;
  bool _isEnvoi = false;

  @override
  void initState() {
    super.initState();
    // Envoyer le rapport initial automatiquement
    _envoyerRapportInitial();
  }

  @override
  void dispose() {
    _msgController.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // RAPPORT INITIAL AUTOMATIQUE
  // ─────────────────────────────────────────────
  Future<void> _envoyerRapportInitial() async {
    if (widget.maladie == null || widget.maladie!.isEmpty) return;

    // Vérifier si un rapport a déjà été envoyé
    final msgs = await FirebaseFirestore.instance
        .collection('consultations')
        .doc(widget.consultationId)
        .collection('messages')
        .where('type', isEqualTo: 'rapport')
        .limit(1)
        .get();

    if (msgs.docs.isNotEmpty) return; // Déjà envoyé

    await FirebaseFirestore.instance
        .collection('consultations')
        .doc(widget.consultationId)
        .collection('messages')
        .add({
      'uid':     _uid,
      'type':    'rapport',
      'texte':   "📋 **Rapport de diagnostic IA**\n\n"
                 "🦠 **Maladie détectée :** ${widget.maladie}\n\n"
                 "Je sollicite votre avis d'expert sur ce diagnostic.",
      'date':    FieldValue.serverTimestamp(),
      'lu':      false,
    });
  }

  // ─────────────────────────────────────────────
  // ENVOYER MESSAGE TEXTE
  // ─────────────────────────────────────────────
  Future<void> _envoyerMessage() async {
    final texte = _msgController.text.trim();
    if (texte.isEmpty) return;

    setState(() => _isEnvoi = true);
    _msgController.clear();

    await FirebaseFirestore.instance
        .collection('consultations')
        .doc(widget.consultationId)
        .collection('messages')
        .add({
      'uid':  _uid,
      'type': 'texte',
      'texte': texte,
      'date': FieldValue.serverTimestamp(),
      'lu':   false,
    });

    // Mettre à jour statut consultation
    await FirebaseFirestore.instance
        .collection('consultations')
        .doc(widget.consultationId)
        .update({'statut': 'en_cours'});

    setState(() => _isEnvoi = false);
    _scrollerBas();
  }

  // ─────────────────────────────────────────────
  // ENVOYER PHOTO
  // ─────────────────────────────────────────────
  Future<void> _envoyerPhoto() async {
    final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70);
    if (photo == null) return;

    setState(() => _isEnvoi = true);

    try {
      String url = '';
      if (!kIsWeb) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('consultations/${widget.consultationId}/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(File(photo.path));
        url = await ref.getDownloadURL();
      } else {
        final bytes = await photo.readAsBytes();
        final ref = FirebaseStorage.instance
            .ref()
            .child('consultations/${widget.consultationId}/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putData(bytes);
        url = await ref.getDownloadURL();
      }

      await FirebaseFirestore.instance
          .collection('consultations')
          .doc(widget.consultationId)
          .collection('messages')
          .add({
        'uid':       _uid,
        'type':      'photo',
        'texte':     url,
        'date':      FieldValue.serverTimestamp(),
        'lu':        false,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur : $e"),
              backgroundColor: Colors.red),
        );
      }
    }

    setState(() => _isEnvoi = false);
    _scrollerBas();
  }

  // ─────────────────────────────────────────────
  // NOTER L'EXPERT
  // ─────────────────────────────────────────────
  Future<void> _noterExpert() async {
    double note = 5;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Noter l'expert"),
        content: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Note : ${note.toInt()}/5"),
              Slider(
                value: note,
                min: 1,
                max: 5,
                divisions: 4,
                activeColor: Colors.amber,
                onChanged: (v) => setS(() => note = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < note.toInt() ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 30,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Mettre à jour la note de l'expert
              final expertRef = FirebaseFirestore.instance
                  .collection('experts')
                  .doc(widget.expert.id);
              await FirebaseFirestore.instance
                  .runTransaction((t) async {
                final snap = await t.get(expertRef);
                final ancNote =
                    (snap['note_moyenne'] as num?)?.toDouble() ?? 0;
                final nbConsult =
                    (snap['nb_consultations'] as num?)?.toInt() ?? 0;
                final nouvelleNote =
                    ((ancNote * nbConsult) + note) / (nbConsult + 1);
                t.update(expertRef, {
                  'note_moyenne':     nouvelleNote,
                  'nb_consultations': nbConsult + 1,
                });
              });

              // Clôturer la consultation
              await FirebaseFirestore.instance
                  .collection('consultations')
                  .doc(widget.consultationId)
                  .update({'statut': 'terminee'});

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Merci pour votre évaluation !"),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green),
            child: const Text("Envoyer",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _scrollerBas() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─────────────────────────────────────────────
  // INTERFACE
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.green[300],
              backgroundImage: widget.expert.photoUrl.isNotEmpty
                  ? NetworkImage(widget.expert.photoUrl)
                  : null,
              child: widget.expert.photoUrl.isEmpty
                  ? Text(
                      widget.expert.nom[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.expert.nom,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15)),
                Text(widget.expert.specialite,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          // Bouton noter et clôturer
          TextButton.icon(
            onPressed: _noterExpert,
            icon: const Icon(Icons.star, color: Colors.amber, size: 18),
            label: const Text("Terminer",
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
      body: Column(
        children: [

          // ── Bandeau délai ──
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('consultations')
                .doc(widget.consultationId)
                .snapshots(),
            builder: (_, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final data = snap.data!.data() as Map<String, dynamic>?;
              final statut = data?['statut'] ?? 'en_attente';
              final dateLimite = data?['date_limite'] as String?;

              Color bgColor;
              String message;
              if (statut == 'terminee') {
                bgColor = Colors.grey;
                message = "✅ Consultation terminée";
              } else if (statut == 'en_cours') {
                bgColor = Colors.green;
                message = "💬 En cours de consultation";
              } else {
                bgColor = Colors.orange;
                message = "⏳ En attente de réponse (délai : 24h)";
              }

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                color: bgColor.withOpacity(0.1),
                child: Text(message,
                    style: TextStyle(
                        color: bgColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              );
            },
          ),

          // ── Messages ──
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('consultations')
                  .doc(widget.consultationId)
                  .collection('messages')
                  .orderBy('date', descending: false)
                  .snapshots(),
              builder: (_, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: Colors.green));
                }

                final msgs = snap.data!.docs;
                if (msgs.isEmpty) {
                  return const Center(
                      child: Text("Envoyez votre premier message"));
                }

                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final msg =
                        msgs[i].data() as Map<String, dynamic>;
                    return _buildBulle(msg);
                  },
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
  Widget _buildBulle(Map<String, dynamic> msg) {
    final estMoi   = msg['uid'] == _uid;
    final type     = msg['type'] ?? 'texte';
    final texte    = msg['texte'] ?? '';
    final date     = msg['date'] as Timestamp?;

    // Message rapport spécial
    if (type == 'rapport') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.biotech, color: Colors.green, size: 16),
                SizedBox(width: 6),
                Text("Rapport envoyé à l'expert",
                    style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            Text(texte.replaceAll('**', ''),
                style:
                    const TextStyle(fontSize: 13, height: 1.5)),
          ],
        ),
      );
    }

    return Align(
      alignment:
          estMoi ? Alignment.centerRight : Alignment.centerLeft,
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!estMoi)
              Text(widget.expert.nom,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.green[700],
                      fontWeight: FontWeight.bold)),

            // Contenu
            if (type == 'photo')
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(texte,
                    height: 180, fit: BoxFit.cover),
              )
            else
              Text(texte, style: const TextStyle(fontSize: 14)),

            const SizedBox(height: 4),
            Text(
              date != null
                  ? "${date.toDate().hour.toString().padLeft(2, '0')}:${date.toDate().minute.toString().padLeft(2, '0')}"
                  : "",
              style: TextStyle(
                  fontSize: 10, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // ZONE DE SAISIE
  // ─────────────────────────────────────────────
  Widget _buildZoneSaisie() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 8),
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
          // Bouton photo
          IconButton(
            icon: const Icon(Icons.photo, color: Colors.green),
            onPressed: _isEnvoi ? null : _envoyerPhoto,
          ),
          // Champ texte
          Expanded(
            child: TextField(
              controller: _msgController,
              maxLines: null,
              decoration: InputDecoration(
                hintText: "Votre message...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Bouton envoyer
          _isEnvoi
              ? const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                      color: Colors.green, strokeWidth: 2))
              : IconButton(
                  icon: const Icon(Icons.send,
                      color: Colors.green, size: 28),
                  onPressed: _envoyerMessage,
                ),
        ],
      ),
    );
  }
}   ],
      ),
    );
  }
}