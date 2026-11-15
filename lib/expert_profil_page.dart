// lib/expert_profil_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ExpertProfilPage extends StatefulWidget {
  const ExpertProfilPage({super.key});

  @override
  State<ExpertProfilPage> createState() => _ExpertProfilPageState();
}

class _ExpertProfilPageState extends State<ExpertProfilPage> {
  final _nom          = TextEditingController();
  final _specialite   = TextEditingController();
  final _description  = TextEditingController();
  final _telephone    = TextEditingController();
  final _pays         = TextEditingController(text: 'Niger');

  final List<String> _languesSelectionnees = ['fr'];
  bool _disponible = true;
  bool _isLoading  = false;
  bool _estExpert  = false;

  final Map<String, String> _languesDispo = {
    'fr':  '🇫🇷 Français',
    'en':  '🇬🇧 English',
    'ha':  '🇳🇬 Haoussa',
    'dje': '🇳🇪 Zarma',
    'ar':  '🇸🇦 Arabe',
    'ff':  '🇬🇳 Fulfulde',
    'tmh': '🇲🇱 Tamasheq',
  };

  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _chargerProfil();
  }

  Future<void> _chargerProfil() async {
    if (_uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('experts')
        .doc(_uid)
        .get();
    if (doc.exists) {
      final d = doc.data()!;
      setState(() {
        _estExpert = true;
        _nom.text         = d['nom']        ?? '';
        _specialite.text  = d['specialite'] ?? '';
        _description.text = d['description'] ?? '';
        _telephone.text   = d['telephone']  ?? '';
        _pays.text        = d['pays']       ?? 'Niger';
        _disponible       = d['disponible'] ?? true;
        _languesSelectionnees.clear();
        _languesSelectionnees.addAll(
            List<String>.from(d['langues'] ?? ['fr']));
      });
    }
  }

  Future<void> _sauvegarder() async {
    if (_uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Vous devez être connecté."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_nom.text.isEmpty || _specialite.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Remplissez le nom et la spécialité."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    await FirebaseFirestore.instance
        .collection('experts')
        .doc(_uid)
        .set({
      'nom':              _nom.text.trim(),
      'specialite':       _specialite.text.trim(),
      'description':      _description.text.trim(),
      'telephone':        _telephone.text.trim(),
      'pays':             _pays.text.trim(),
      'langues':          _languesSelectionnees,
      'disponible':       _disponible,
      'photo_url':        '',
      'note_moyenne':     _estExpert ? null : 0.0,
      'nb_consultations': _estExpert ? null : 0,
      'uid':              _uid,
    }, SetOptions(merge: true));

    setState(() { _isLoading = false; _estExpert = true; });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_estExpert
              ? "Profil mis à jour ✅"
              : "Vous êtes maintenant inscrit comme expert ! ✅"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_estExpert ? "Mon profil expert" : "Devenir expert",
            style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // En-tête
            if (!_estExpert)
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("🤝 Rejoignez le réseau d'experts",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    SizedBox(height: 8),
                    Text(
                      "En tant qu'expert agronome, vous aidez les agriculteurs "
                      "à identifier et traiter les maladies de leurs plantes. "
                      "Répondez en moins de 24h pour maintenir votre statut.",
                      style: TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ],
                ),
              ),

            // Disponibilité (si déjà expert)
            if (_estExpert) ...[
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _disponible ? Colors.green[50] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _disponible
                        ? Colors.green.shade300
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _disponible ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _disponible
                            ? "Vous êtes disponible pour des consultations"
                            : "Vous êtes marqué comme indisponible",
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    Switch(
                      value: _disponible,
                      onChanged: (v) => setState(() => _disponible = v),
                      activeColor: Colors.green,
                    ),
                  ],
                ),
              ),
            ],

            _champ(_nom, "Nom complet *", Icons.person),
            _champ(_specialite, "Spécialité *", Icons.school,
                hint: "ex: Phytopathologie, Agronomie générale..."),
            _champ(_description, "Description", Icons.info_outline,
                maxLines: 3,
                hint: "Décrivez votre expérience et expertise..."),
            _champ(_telephone, "Téléphone (optionnel)", Icons.phone,
                type: TextInputType.phone),
            _champ(_pays, "Pays", Icons.flag),

            const SizedBox(height: 16),

            // Langues
            const Text("Langues parlées *",
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _languesDispo.entries.map((e) {
                final sel = _languesSelectionnees.contains(e.key);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (sel) {
                      if (_languesSelectionnees.length > 1) {
                        _languesSelectionnees.remove(e.key);
                      }
                    } else {
                      _languesSelectionnees.add(e.key);
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? Colors.green : Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel
                            ? Colors.green
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(e.value,
                        style: TextStyle(
                            color: sel ? Colors.white : Colors.grey[700],
                            fontSize: 13)),
                  ),
                );
              }).toList(),
            ),

            // Disponibilité (si nouvel expert)
            if (!_estExpert) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text("Disponible maintenant"),
                subtitle: const Text(
                    "Les agriculteurs pourront vous contacter",
                    style: TextStyle(fontSize: 12)),
                value: _disponible,
                onChanged: (v) => setState(() => _disponible = v),
                activeColor: Colors.green,
                contentPadding: EdgeInsets.zero,
              ),
            ],

            const SizedBox(height: 24),

            // Bouton sauvegarder
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _sauvegarder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(
                        color: Colors.white)
                    : Text(
                        _estExpert
                            ? "Mettre à jour mon profil"
                            : "S'inscrire comme expert",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _champ(
    TextEditingController c,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType? type,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.green),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Colors.green, width: 2),
          ),
        ),
      ),
    );
  }
}