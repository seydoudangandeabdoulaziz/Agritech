// lib/experts_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'consultation_page.dart';
import 'expert_profil_page.dart';

// ─────────────────────────────────────────────
// MODÈLE EXPERT
// ─────────────────────────────────────────────
class Expert {
  final String        id;
  final String        nom;
  final String        photoUrl;
  final String        specialite;
  final List<String>  langues;
  final bool          disponible;
  final double        noteMoyenne;
  final int           nbConsultations;
  final String        pays;
  final String        description;
  final String        telephone;

  Expert({
    required this.id,
    required this.nom,
    required this.photoUrl,
    required this.specialite,
    required this.langues,
    required this.disponible,
    required this.noteMoyenne,
    required this.nbConsultations,
    required this.pays,
    required this.description,
    required this.telephone,
  });

  factory Expert.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return Expert(
      id:              doc.id,
      nom:             d['nom']             ?? 'Expert',
      photoUrl:        d['photo_url']        ?? '',
      specialite:      d['specialite']       ?? 'Agronome',
      langues:         List<String>.from(d['langues'] ?? ['fr']),
      disponible:      d['disponible']       ?? false,
      noteMoyenne:     (d['note_moyenne'] as num?)?.toDouble() ?? 0.0,
      nbConsultations: (d['nb_consultations'] as num?)?.toInt() ?? 0,
      pays:            d['pays']             ?? 'Niger',
      description:     d['description']      ?? '',
      telephone:       d['telephone']        ?? '',
    );
  }
}

// ─────────────────────────────────────────────
// PAGE LISTE DES EXPERTS
// ─────────────────────────────────────────────
class ExpertsPage extends StatefulWidget {
  /// Optionnel : pré-remplir avec le diagnostic actuel
  final String? maladie;
  final String? photoUrl;
  final String? conseils;

  const ExpertsPage({
    super.key,
    this.maladie,
    this.photoUrl,
    this.conseils,
  });

  @override
  State<ExpertsPage> createState() => _ExpertsPageState();
}

class _ExpertsPageState extends State<ExpertsPage> {
  bool _seulementDisponibles = true;
  String _filtreLangue = 'Tous';

  final List<String> _langues = ['Tous', 'fr', 'en', 'ha', 'ar', 'ff'];
  final Map<String, String> _nomsLangues = {
    'Tous': '🌍 Tous',
    'fr':   '🇫🇷 Français',
    'en':   '🇬🇧 English',
    'ha':   '🇳🇬 Haoussa',
    'ar':   '🇸🇦 Arabe',
    'ff':   '🇬🇳 Fulfulde',
  };

  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🤝 Experts agronomes",
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Bouton devenir expert
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExpertProfilPage()),
            ),
            icon: const Icon(Icons.verified_user,
                color: Colors.white, size: 18),
            label: const Text("Devenir expert",
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
      body: Column(
        children: [

          // ── Bandeau diagnostic ──
          if (widget.maladie != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.green[50],
              child: Row(
                children: [
                  const Icon(Icons.biotech, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Consulter un expert pour : ${widget.maladie}",
                      style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                          fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // ── Filtres ──
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Toggle disponibles
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _seulementDisponibles
                          ? Colors.green[50]
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _seulementDisponibles
                            ? Colors.green
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _seulementDisponibles
                                ? Colors.green
                                : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text("Disponibles maintenant",
                            style: TextStyle(fontSize: 12)),
                        const Spacer(),
                        Switch(
                          value: _seulementDisponibles,
                          onChanged: (v) =>
                              setState(() => _seulementDisponibles = v),
                          activeColor: Colors.green,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Filtre langue ──
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _langues.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final l = _langues[i];
                final sel = _filtreLangue == l;
                return GestureDetector(
                  onTap: () => setState(() => _filtreLangue = l),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? Colors.green : Colors.grey[100],
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: sel
                            ? Colors.green
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      _nomsLangues[l] ?? l,
                      style: TextStyle(
                        color: sel ? Colors.white : Colors.grey[700],
                        fontSize: 12,
                        fontWeight: sel
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // ── Liste experts ──
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _buildQuery(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          color: Colors.green));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildVide();
                }

                var experts = snapshot.data!.docs
                    .map((d) => Expert.fromFirestore(d))
                    .toList();

                // Filtre langue côté client
                if (_filtreLangue != 'Tous') {
                  experts = experts
                      .where((e) => e.langues.contains(_filtreLangue))
                      .toList();
                }

                // Trier : disponibles en premier, puis par note
                experts.sort((a, b) {
                  if (a.disponible && !b.disponible) return -1;
                  if (!a.disponible && b.disponible) return 1;
                  return b.noteMoyenne.compareTo(a.noteMoyenne);
                });

                if (experts.isEmpty) return _buildVide();

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: experts.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 10),
                  itemBuilder: (_, i) =>
                      _buildCarteExpert(experts[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Stream<QuerySnapshot> _buildQuery() {
    Query q = FirebaseFirestore.instance.collection('experts');
    if (_seulementDisponibles) {
      q = q.where('disponible', isEqualTo: true);
    }
    return q.snapshots();
  }

  // ─────────────────────────────────────────────
  // CARTE EXPERT
  // ─────────────────────────────────────────────
  Widget _buildCarteExpert(Expert expert) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expert.disponible
              ? Colors.green.shade200
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.green[100],
                  backgroundImage: expert.photoUrl.isNotEmpty
                      ? NetworkImage(expert.photoUrl)
                      : null,
                  child: expert.photoUrl.isEmpty
                      ? Text(
                          expert.nom.isNotEmpty
                              ? expert.nom[0].toUpperCase()
                              : 'E',
                          style: const TextStyle(
                              fontSize: 24,
                              color: Colors.green,
                              fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                // Indicateur disponibilité
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: expert.disponible
                          ? Colors.green
                          : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 12),

            // Infos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(expert.nom,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                      ),
                      // Badge disponible
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: expert.disponible
                              ? Colors.green[50]
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          expert.disponible
                              ? "● Disponible"
                              : "○ Occupé",
                          style: TextStyle(
                            fontSize: 10,
                            color: expert.disponible
                                ? Colors.green
                                : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(expert.specialite,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  // Note et pays
                  Row(
                    children: [
                      const Icon(Icons.star,
                          color: Colors.amber, size: 14),
                      const SizedBox(width: 2),
                      Text(
                        expert.noteMoyenne > 0
                            ? expert.noteMoyenne.toStringAsFixed(1)
                            : "Nouveau",
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.location_on,
                          color: Colors.grey[400], size: 12),
                      Text(expert.pays,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[500])),
                      const SizedBox(width: 8),
                      Icon(Icons.chat_bubble_outline,
                          color: Colors.grey[400], size: 12),
                      Text(" ${expert.nbConsultations} consult.",
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Langues
                  Wrap(
                    spacing: 4,
                    children: expert.langues.map((l) {
                      const drapeaux = {
                        'fr': '🇫🇷', 'en': '🇬🇧', 'ha': '🇳🇬',
                        'ar': '🇸🇦', 'ff': '🇬🇳', 'dje': '🇳🇪',
                        'tmh': '🇲🇱',
                      };
                      return Text(drapeaux[l] ?? l,
                          style: const TextStyle(fontSize: 16));
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  // Bouton consulter
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: expert.disponible && _uid != null
                          ? () => _demarrerConsultation(expert)
                          : null,
                      icon: const Icon(Icons.chat, size: 16),
                      label: Text(
                        expert.disponible
                            ? "Consulter maintenant"
                            : "Indisponible",
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
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

  Widget _buildVide() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 70, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _seulementDisponibles
                ? "Aucun expert disponible\nen ce moment"
                : "Aucun expert inscrit",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ExpertProfilPage()),
            ),
            icon: const Icon(Icons.add),
            label: const Text("Rejoindre comme expert"),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // DÉMARRER UNE CONSULTATION
  // ─────────────────────────────────────────────
  Future<void> _demarrerConsultation(Expert expert) async {
    final uid = _uid!;

    // Vérifier si une consultation existe déjà
    final existing = await FirebaseFirestore.instance
        .collection('consultations')
        .where('agriculteur_uid', isEqualTo: uid)
        .where('expert_uid', isEqualTo: expert.id)
        .where('statut', whereIn: ['en_attente', 'en_cours'])
        .limit(1)
        .get();

    String consultationId;

    if (existing.docs.isNotEmpty) {
      consultationId = existing.docs.first.id;
    } else {
      // Créer nouvelle consultation
      final doc = await FirebaseFirestore.instance
          .collection('consultations')
          .add({
        'agriculteur_uid':  uid,
        'expert_uid':       expert.id,
        'expert_nom':       expert.nom,
        'maladie':          widget.maladie ?? '',
        'photo_url':        widget.photoUrl ?? '',
        'conseils_ia':      widget.conseils ?? '',
        'statut':           'en_attente',
        'date_creation':    FieldValue.serverTimestamp(),
        'date_limite':      DateTime.now()
            .add(const Duration(hours: 24))
            .toIso8601String(),
      });
      consultationId = doc.id;
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConsultationPage(
            consultationId: consultationId,
            expert:         expert,
            maladie:        widget.maladie,
          ),
        ),
      );
    }
  }
}