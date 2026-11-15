// lib/produit_phyto_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────
// MODÈLE PRODUIT PHYTOSANITAIRE
// ─────────────────────────────────────────────
class ProduitPhyto {
  final String  id;
  final String  nom;
  final String  fabricant;
  final String  type;           // Fongicide, Insecticide, Bactéricide, Herbicide
  final String  matiere_active; // Substance active
  final List<String> maladiesCibles;  // maladies que ce produit traite
  final List<String> cultures;        // cultures compatibles
  final String  dosage;         // ex: "2ml/L d'eau"
  final String  modeEmploi;     // instructions d'application
  final String  precautions;    // EPI, délai avant récolte, etc.
  final double  prixMoyen;      // en FCFA
  final bool    disponibleNiger;
  final List<String> pointsVente; // lieux de vente
  final String  imageUrl;       // photo du produit
  final String  couleur;        // pour affichage UI : 'rouge', 'bleu', 'vert', 'orange'

  ProduitPhyto({
    required this.id,
    required this.nom,
    required this.fabricant,
    required this.type,
    required this.matiere_active,
    required this.maladiesCibles,
    required this.cultures,
    required this.dosage,
    required this.modeEmploi,
    required this.precautions,
    required this.prixMoyen,
    required this.disponibleNiger,
    required this.pointsVente,
    this.imageUrl = '',
    this.couleur  = 'vert',
  });

  factory ProduitPhyto.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ProduitPhyto(
      id:               doc.id,
      nom:              d['nom']           ?? '',
      fabricant:        d['fabricant']     ?? '',
      type:             d['type']          ?? '',
      matiere_active:   d['matiere_active'] ?? '',
      maladiesCibles:   List<String>.from(d['maladies_cibles'] ?? []),
      cultures:         List<String>.from(d['cultures']        ?? []),
      dosage:           d['dosage']        ?? '',
      modeEmploi:       d['mode_emploi']   ?? '',
      precautions:      d['precautions']   ?? '',
      prixMoyen:        (d['prix_moyen'] as num?)?.toDouble() ?? 0,
      disponibleNiger:  d['disponible_niger'] ?? true,
      pointsVente:      List<String>.from(d['points_vente'] ?? []),
      imageUrl:         d['image_url']     ?? '',
      couleur:          d['couleur']       ?? 'vert',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'nom':              nom,
    'fabricant':        fabricant,
    'type':             type,
    'matiere_active':   matiere_active,
    'maladies_cibles':  maladiesCibles,
    'cultures':         cultures,
    'dosage':           dosage,
    'mode_emploi':      modeEmploi,
    'precautions':      precautions,
    'prix_moyen':       prixMoyen,
    'disponible_niger': disponibleNiger,
    'points_vente':     pointsVente,
    'image_url':        imageUrl,
    'couleur':          couleur,
  };

  // ✅ Couleur selon le type de produit
  static Map<String, dynamic> couleurType(String type) {
    switch (type.toLowerCase()) {
      case 'fongicide':
        return {'bg': 0xFFE3F2FD, 'text': 0xFF1565C0, 'icon': 0xFF1E88E5};
      case 'insecticide':
        return {'bg': 0xFFFCE4EC, 'text': 0xFFC62828, 'icon': 0xFFE53935};
      case 'bactéricide':
      case 'bactericide':
        return {'bg': 0xFFF3E5F5, 'text': 0xFF6A1B9A, 'icon': 0xFF8E24AA};
      case 'herbicide':
        return {'bg': 0xFFE8F5E9, 'text': 0xFF2E7D32, 'icon': 0xFF43A047};
      default:
        return {'bg': 0xFFFFF8E1, 'text': 0xFFF57F17, 'icon': 0xFFFFB300};
    }
  }
}s