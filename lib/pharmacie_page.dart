// lib/pharmacie_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'produit_phyto_model.dart';

class PharmaciePage extends StatefulWidget {
  /// Si fourni, filtre automatiquement les produits pour cette maladie
  final String? maladieCible;
  final String? cultureCible;

  const PharmaciePage({
    super.key,
    this.maladieCible,
    this.cultureCible,
  });

  @override
  State<PharmaciePage> createState() => _PharmaciePageState();
}

class _PharmaciePageState extends State<PharmaciePage> {
  final TextEditingController _searchController = TextEditingController();

  List<ProduitPhyto> _tousProduits  = [];
  List<ProduitPhyto> _produitsFiltres = [];
  bool  _isLoading   = true;
  String _filtreType  = 'Tous';
  bool  _seulementNiger = true;

  final List<String> _types = [
    'Tous', 'Fongicide', 'Insecticide', 'Bactéricide', 'Herbicide'
  ];

  @override
  void initState() {
    super.initState();
    _chargerProduits();
    _searchController.addListener(_filtrer);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // CHARGEMENT FIRESTORE
  // ─────────────────────────────────────────────
  Future<void> _chargerProduits() async {
    setState(() => _isLoading = true);
    try {
      Query query = FirebaseFirestore.instance.collection('produits_phyto');

      // Filtre Niger si activé
      if (_seulementNiger) {
        query = query.where('disponible_niger', isEqualTo: true);
      }

      final snapshot = await query.get();
      _tousProduits = snapshot.docs
          .map((doc) => ProduitPhyto.fromFirestore(doc))
          .toList();

      _filtrer();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur chargement : $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  // ─────────────────────────────────────────────
  // FILTRAGE
  // ─────────────────────────────────────────────
  void _filtrer() {
    final recherche = _searchController.text.toLowerCase().trim();

    setState(() {
      _produitsFiltres = _tousProduits.where((p) {
        // Filtre type
        if (_filtreType != 'Tous' &&
            p.type.toLowerCase() != _filtreType.toLowerCase()) {
          return false;
        }

        // Filtre maladie cible (depuis le diagnostic)
        if (widget.maladieCible != null) {
          final malCible = widget.maladieCible!.toLowerCase();
          final matchMaladie = p.maladiesCibles.any(
            (m) => m.toLowerCase().contains(malCible) ||
                   malCible.contains(m.toLowerCase().split('—').last.trim()),
          );
          if (!matchMaladie) return false;
        }

        // Filtre culture cible
        if (widget.cultureCible != null) {
          final culCible = widget.cultureCible!.toLowerCase();
          final matchCulture = p.cultures.any(
            (c) => c.toLowerCase().contains(culCible) ||
                   culCible.contains(c.toLowerCase()),
          );
          if (!matchCulture) return false;
        }

        // Filtre recherche texte
        if (recherche.isNotEmpty) {
          return p.nom.toLowerCase().contains(recherche) ||
              p.fabricant.toLowerCase().contains(recherche) ||
              p.type.toLowerCase().contains(recherche) ||
              p.maladiesCibles.any((m) => m.toLowerCase().contains(recherche)) ||
              p.cultures.any((c) => c.toLowerCase().contains(recherche));
        }

        return true;
      }).toList();

      // Trier : produits avec maladie cible en premier
      if (widget.maladieCible != null) {
        _produitsFiltres.sort((a, b) {
          final aMatch = a.maladiesCibles.any(
            (m) => m.toLowerCase().contains(
                widget.maladieCible!.toLowerCase()),
          );
          final bMatch = b.maladiesCibles.any(
            (m) => m.toLowerCase().contains(
                widget.maladieCible!.toLowerCase()),
          );
          if (aMatch && !bMatch) return -1;
          if (!aMatch && bMatch) return 1;
          return a.prixMoyen.compareTo(b.prixMoyen);
        });
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
        title: const Text("💊 Pharmacie agricole",
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Toggle Niger uniquement
          Row(
            children: [
              const Text("Niger",
                  style: TextStyle(color: Colors.white, fontSize: 12)),
              Switch(
                value: _seulementNiger,
                onChanged: (v) {
                  setState(() => _seulementNiger = v);
                  _chargerProduits();
                },
                activeColor: Colors.white,
                activeTrackColor: Colors.green[300],
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [

          // ── Bandeau maladie cible ──
          if (widget.maladieCible != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              color: Colors.green[50],
              child: Row(
                children: [
                  const Icon(Icons.filter_alt,
                      color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Produits recommandés pour : ${widget.maladieCible}",
                      style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                          fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // ── Barre de recherche ──
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Rechercher un produit, une maladie...",
                prefixIcon:
                    const Icon(Icons.search, color: Colors.green),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filtrer();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.green.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Colors.green, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
          ),

          // ── Filtres par type ──
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _types.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final type = _types[i];
                final selected = _filtreType == type;
                return GestureDetector(
                  onTap: () {
                    setState(() => _filtreType = type);
                    _filtrer();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected ? Colors.green : Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? Colors.green
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      type,
                      style: TextStyle(
                        color:
                            selected ? Colors.white : Colors.grey[700],
                        fontSize: 13,
                        fontWeight: selected
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

          // ── Compteur résultats ──
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    "${_produitsFiltres.length} produit(s) trouvé(s)",
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  // Bouton ajouter produit (admin)
                  TextButton.icon(
                    onPressed: _ajouterProduit,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text("Ajouter", style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                        foregroundColor: Colors.green),
                  ),
                ],
              ),
            ),

          // ── Liste des produits ──
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.green))
                : _produitsFiltres.isEmpty
                    ? _buildVide()
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _produitsFiltres.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _buildCarteProduit(_produitsFiltres[i]),
                      ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // CARTE PRODUIT
  // ─────────────────────────────────────────────
  Widget _buildCarteProduit(ProduitPhyto p) {
    final couleurs = ProduitPhyto.couleurType(p.type);
    final bgColor  = Color(couleurs['bg'] as int);
    final txtColor = Color(couleurs['text'] as int);

    return GestureDetector(
      onTap: () => _voirDetail(p),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // En-tête
              Row(
                children: [
                  // Badge type
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(p.type,
                        style: TextStyle(
                            color: txtColor,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.nom,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis),
                  ),
                  // Prix
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "${p.prixMoyen.toStringAsFixed(0)} FCFA",
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green),
                      ),
                      const Text("prix moy.",
                          style:
                              TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Fabricant + matière active
              Text("${p.fabricant} · ${p.matiere_active}",
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),

              const SizedBox(height: 8),

              // Dosage
              Row(
                children: [
                  const Icon(Icons.science_outlined,
                      size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(p.dosage,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.blue)),
                ],
              ),

              const SizedBox(height: 8),

              // Maladies cibles
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: p.maladiesCibles.take(3).map((m) {
                  final isMatch = widget.maladieCible != null &&
                      m.toLowerCase().contains(
                          widget.maladieCible!.toLowerCase());
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isMatch
                          ? Colors.green[50]
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isMatch
                            ? Colors.green.shade300
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(m,
                        style: TextStyle(
                            fontSize: 10,
                            color: isMatch ? Colors.green : Colors.grey[700],
                            fontWeight: isMatch
                                ? FontWeight.bold
                                : FontWeight.normal)),
                  );
                }).toList(),
              ),

              const SizedBox(height: 10),

              // Points de vente + disponibilité
              Row(
                children: [
                  const Icon(Icons.store, size: 14, color: Colors.orange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      p.pointsVente.isNotEmpty
                          ? p.pointsVente.first
                          : "Disponible en pharmacie agricole",
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (p.disponibleNiger)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text("🇳🇪 Niger",
                          style: TextStyle(
                              fontSize: 10, color: Colors.green)),
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
  // PAGE VIDE
  // ─────────────────────────────────────────────
  Widget _buildVide() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.medication_outlined, size: 70, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            widget.maladieCible != null
                ? "Aucun produit trouvé pour\n${widget.maladieCible}"
                : "Aucun produit trouvé",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey[500]),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _ajouterProduit,
            icon: const Icon(Icons.add),
            label: const Text("Ajouter le premier produit"),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // VOIR DÉTAIL
  // ─────────────────────────────────────────────
  void _voirDetail(ProduitPhyto p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, controller) => _DetailProduit(
            produit: p, scrollController: controller),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // AJOUTER PRODUIT (formulaire admin)
  // ─────────────────────────────────────────────
  void _ajouterProduit() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FormulaireAjoutProduit(
        onAjoute: () {
          Navigator.pop(context);
          _chargerProduits();
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════
// DÉTAIL D'UN PRODUIT
// ═════════════════════════════════════════════
class _DetailProduit extends StatelessWidget {
  final ProduitPhyto      produit;
  final ScrollController  scrollController;

  const _DetailProduit({
    required this.produit,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final couleurs = ProduitPhyto.couleurType(produit.type);
    final bgColor  = Color(couleurs['bg'] as int);
    final txtColor = Color(couleurs['text'] as int);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(20),
      children: [

        // Poignée
        Center(
          child: Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),

        // En-tête
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: bgColor, borderRadius: BorderRadius.circular(8)),
              child: Text(produit.type,
                  style: TextStyle(
                      color: txtColor, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(produit.nom,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ],
        ),

        const SizedBox(height: 6),
        Text("${produit.fabricant} · ${produit.matiere_active}",
            style: TextStyle(color: Colors.grey[600], fontSize: 13)),

        const SizedBox(height: 16),

        // Prix
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.payments_outlined,
                  color: Colors.green, size: 24),
              const SizedBox(width: 8),
              Text(
                "${produit.prixMoyen.toStringAsFixed(0)} FCFA",
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green),
              ),
              const Text(" / unité",
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Sections
        _Section(titre: "💉 Dosage recommandé",       contenu: produit.dosage),
        _Section(titre: "📋 Mode d'emploi",           contenu: produit.modeEmploi),
        _Section(titre: "⚠️ Précautions de sécurité", contenu: produit.precautions),

        // Maladies cibles
        const SizedBox(height: 12),
        const Text("🎯 Maladies traitées",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: produit.maladiesCibles.map((m) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(m,
                style: const TextStyle(
                    fontSize: 12, color: Colors.red)),
          )).toList(),
        ),

        const SizedBox(height: 16),

        // Cultures compatibles
        const Text("🌿 Cultures compatibles",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: produit.cultures.map((c) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Text(c,
                style: const TextStyle(
                    fontSize: 12, color: Colors.green)),
          )).toList(),
        ),

        const SizedBox(height: 16),

        // Points de vente
        const Text("📍 Points de vente",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        ...produit.pointsVente.map((pv) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              const Icon(Icons.store_mall_directory,
                  color: Colors.orange, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(pv,
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
        )),

        const SizedBox(height: 30),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String titre;
  final String contenu;
  const _Section({required this.titre, required this.contenu});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(contenu,
                style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════
// FORMULAIRE AJOUT PRODUIT
// ═════════════════════════════════════════════
class _FormulaireAjoutProduit extends StatefulWidget {
  final VoidCallback onAjoute;
  const _FormulaireAjoutProduit({required this.onAjoute});

  @override
  State<_FormulaireAjoutProduit> createState() =>
      _FormulaireAjoutProduitState();
}

class _FormulaireAjoutProduitState
    extends State<_FormulaireAjoutProduit> {
  final _nom            = TextEditingController();
  final _fabricant      = TextEditingController();
  final _matiereActive  = TextEditingController();
  final _dosage         = TextEditingController();
  final _modeEmploi     = TextEditingController();
  final _precautions    = TextEditingController();
  final _prix           = TextEditingController();
  final _maladies       = TextEditingController();
  final _cultures       = TextEditingController();
  final _pointsVente    = TextEditingController();

  String _type = 'Fongicide';
  bool   _niger = true;
  bool   _isEnvoi = false;

  final List<String> _types = [
    'Fongicide', 'Insecticide', 'Bactéricide', 'Herbicide', 'Autre'
  ];

  Future<void> _sauvegarder() async {
    if (_nom.text.isEmpty || _dosage.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Remplissez au moins le nom et le dosage."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isEnvoi = true);

    try {
      await FirebaseFirestore.instance.collection('produits_phyto').add({
        'nom':              _nom.text.trim(),
        'fabricant':        _fabricant.text.trim(),
        'type':             _type,
        'matiere_active':   _matiereActive.text.trim(),
        'dosage':           _dosage.text.trim(),
        'mode_emploi':      _modeEmploi.text.trim(),
        'precautions':      _precautions.text.trim(),
        'prix_moyen':       double.tryParse(_prix.text) ?? 0,
        'maladies_cibles':  _maladies.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'cultures':         _cultures.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'points_vente':     _pointsVente.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        'disponible_niger': _niger,
        'image_url':        '',
        'couleur':          'vert',
      });

      widget.onAjoute();
    } catch (e) {
      setState(() => _isEnvoi = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur : $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _champ(TextEditingController c, String label,
      {int maxLines = 1, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.green),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Ajouter un produit",
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            _champ(_nom, "Nom du produit *"),
            _champ(_fabricant, "Fabricant"),
            _champ(_matiereActive, "Matière active"),

            // Type
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                value: _type,
                decoration: InputDecoration(
                  labelText: "Type de produit",
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: _types.map((t) =>
                    DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _type = v ?? 'Fongicide'),
              ),
            ),

            _champ(_dosage, "Dosage recommandé *"),
            _champ(_modeEmploi, "Mode d'emploi", maxLines: 3),
            _champ(_precautions, "Précautions", maxLines: 2),
            _champ(_prix, "Prix moyen (FCFA)",
                type: TextInputType.number),
            _champ(_maladies,
                "Maladies cibles (séparées par des virgules)"),
            _champ(_cultures,
                "Cultures compatibles (séparées par des virgules)"),
            _champ(_pointsVente,
                "Points de vente (séparés par des virgules)", maxLines: 2),

            // Niger
            SwitchListTile(
              title: const Text("Disponible au Niger"),
              value: _niger,
              onChanged: (v) => setState(() => _niger = v),
              activeColor: Colors.green,
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 8),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isEnvoi ? null : _sauvegarder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isEnvoi
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Sauvegarder",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}