import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'database_helper.dart';

class HistoriquePage extends StatefulWidget {
  const HistoriquePage({super.key});

  @override
  State<HistoriquePage> createState() => _HistoriquePageState();
}

class _HistoriquePageState extends State<HistoriquePage> {
  List<Analyse> _analyses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _chargerHistorique();
  }

  Future<void> _chargerHistorique() async {
    setState(() => _isLoading = true);
    try {
      final analyses = await DatabaseHelper.instance.getAllAnalyses();
      setState(() {
        _analyses = analyses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur chargement : $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _supprimerAnalyse(Analyse analyse) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer cette analyse ?"),
        content: const Text("Cette action est irréversible."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer",
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && analyse.id != null) {
      await DatabaseHelper.instance.deleteAnalyse(analyse.id!);
      await _chargerHistorique();
    }
  }

  Future<void> _viderHistorique() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Vider tout l'historique ?"),
        content: const Text(
            "Toutes les analyses seront supprimées. Cette action est irréversible."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Tout supprimer",
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseHelper.instance.deleteAll();
      await _chargerHistorique();
    }
  }

  void _voirDetail(Analyse analyse) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailAnalysePage(analyse: analyse)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Historique des analyses",
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_analyses.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.white),
              tooltip: "Vider l'historique",
              onPressed: _viderHistorique,
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _chargerHistorique,
            tooltip: "Rafraîchir",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.green))
          : _analyses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 80, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text("Aucune analyse enregistrée",
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey[500])),
                      const SizedBox(height: 8),
                      Text("Analysez une plante pour commencer",
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[400])),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // ── Compteur ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      color: Colors.green[50],
                      child: Row(
                        children: [
                          const Icon(Icons.analytics,
                              color: Colors.green, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            "${_analyses.length} analyse(s) enregistrée(s)",
                            style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w500),
                          ),
                          const Spacer(),
                          // ✅ Badge Firestore
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.cloud_done,
                                    color: Colors.blue, size: 14),
                                SizedBox(width: 4),
                                Text("Synchronisé",
                                    style: TextStyle(
                                        color: Colors.blue, fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Liste ──
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _analyses.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          return _buildCard(_analyses[index]);
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildCard(Analyse analyse) {
    // ✅ Sur Web : utiliser imageUrl, sur mobile : imagePath local
    final bool aImageLocale = !kIsWeb &&
        analyse.imagePath.isNotEmpty &&
        File(analyse.imagePath).existsSync();
    final bool aImageUrl = analyse.imageUrl.isNotEmpty;

    return GestureDetector(
      onTap: () => _voirDetail(analyse),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: analyse.estSain
                ? Colors.green.shade200
                : Colors.red.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Miniature image ──
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: aImageLocale
                  ? Image.file(File(analyse.imagePath),
                      width: 90, height: 90, fit: BoxFit.cover)
                  : aImageUrl
                      ? Image.network(analyse.imageUrl,
                          width: 90, height: 90, fit: BoxFit.cover)
                      : Container(
                          width: 90,
                          height: 90,
                          color: Colors.grey[200],
                          child: const Icon(Icons.image_not_supported,
                              color: Colors.grey),
                        ),
            ),

            // ── Infos ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          analyse.estSain
                              ? Icons.check_circle
                              : Icons.warning_rounded,
                          color: analyse.estSain ? Colors.green : Colors.red,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            analyse.maladie,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(analyse.confianceAffichee,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(analyse.langue,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                        const Spacer(),
                        Text(analyse.date,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                    // ✅ Indicateur GPS
                    if (analyse.latitude != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: Colors.green, size: 12),
                          const SizedBox(width: 2),
                          Text(
                            "${analyse.latitude!.toStringAsFixed(4)}, ${analyse.longitude!.toStringAsFixed(4)}",
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Bouton supprimer ──
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.red, size: 20),
              onPressed: () => _supprimerAnalyse(analyse),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PAGE DÉTAIL D'UNE ANALYSE
// ─────────────────────────────────────────────
class DetailAnalysePage extends StatelessWidget {
  final Analyse analyse;

  const DetailAnalysePage({super.key, required this.analyse});

  @override
  Widget build(BuildContext context) {
    final bool aImageLocale = !kIsWeb &&
        analyse.imagePath.isNotEmpty &&
        File(analyse.imagePath).existsSync();
    final bool aImageUrl = analyse.imageUrl.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Détail de l'analyse",
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Image ──
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: aImageLocale
                  ? Image.file(File(analyse.imagePath),
                      width: double.infinity, height: 250, fit: BoxFit.cover)
                  : aImageUrl
                      ? Image.network(analyse.imageUrl,
                          width: double.infinity,
                          height: 250,
                          fit: BoxFit.cover)
                      : Container(
                          height: 250,
                          width: double.infinity,
                          color: Colors.grey[200],
                          child: const Center(
                            child: Text("Image non disponible",
                                style: TextStyle(color: Colors.grey)),
                          ),
                        ),
            ),

            const SizedBox(height: 16),

            // ── Résultat ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: analyse.estSain ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: analyse.estSain ? Colors.green : Colors.red),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        analyse.estSain
                            ? Icons.check_circle
                            : Icons.warning_rounded,
                        color: analyse.estSain ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(analyse.maladie,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(analyse.confianceAffichee,
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(
                    "Langue : ${analyse.langue}  •  ${analyse.date}",
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  // GPS
                  if (analyse.latitude != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: Colors.green, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          "GPS : ${analyse.latitude!.toStringAsFixed(5)}, ${analyse.longitude!.toStringAsFixed(5)}",
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Top 3 ──
            if (analyse.top3.isNotEmpty) ...[
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
                    Text(analyse.top3,
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Conseils ──
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
                  const Row(
                    children: [
                      Icon(Icons.medical_information, color: Colors.amber),
                      SizedBox(width: 8),
                      Text("Conseils de traitement",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          )),
                    ],
                  ),
                  const Divider(),
                  MarkdownBody(
                    data: analyse.conseils,
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

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}