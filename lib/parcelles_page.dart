// lib/parcelles_page.dart
// Liste des parcelles, création, affichage QR code, scan

import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'parcelle_helper.dart';
import 'parcelle_detail_page.dart';

const List<String> _cultures = [
  'Tomate', 'Maïs', 'Mil', 'Sorgho', 'Niébé',
  'Arachide', 'Oignon', 'Pommier', 'Vigne', 'Autre',
];

class ParcellesPage extends StatefulWidget {
  const ParcellesPage({super.key});
  @override
  State<ParcellesPage> createState() => _ParcellesPageState();
}

class _ParcellesPageState extends State<ParcellesPage> {
  List<Parcelle> _parcelles  = [];
  bool           _chargement = true;

  @override
  void initState() { super.initState(); _charger(); }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    final p = await ParcelleHelper.instance.getAllParcelles();
    setState(() { _parcelles = p; _chargement = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F0),
      appBar: AppBar(
        title: const Text('Mes Parcelles', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scanner un QR code',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const _PageScanner())),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _charger),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final r = await Navigator.push<bool>(context,
              MaterialPageRoute(builder: (_) => const _FormulaireCreationParcelle()));
          if (r == true) _charger();
        },
        backgroundColor: Colors.green.shade700,
        icon: const Icon(Icons.add_location_alt, color: Colors.white),
        label: const Text('Nouvelle parcelle',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : _parcelles.isEmpty
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.landscape, size: 80, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    Text('Aucune parcelle', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('Créez votre première parcelle pour générer un QR code',
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        textAlign: TextAlign.center),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _charger,
                  color: Colors.green,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _parcelles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _CarteParcelle(
                      parcelle: _parcelles[i],
                      onTap: () async {
                        await Navigator.push(context,
                            MaterialPageRoute(builder: (_) =>
                                ParcelleDetailPage(parcelle: _parcelles[i])));
                        _charger();
                      },
                      onSupprimer: () async {
                        await ParcelleHelper.instance.deleteParcelle(_parcelles[i].id!);
                        _charger();
                      },
                    ),
                  ),
                ),
    );
  }
}

// ── Carte parcelle ──────────────────────────────────────────────────────────
class _CarteParcelle extends StatelessWidget {
  final Parcelle parcelle;
  final VoidCallback onTap;
  final VoidCallback onSupprimer;
  const _CarteParcelle({required this.parcelle, required this.onTap, required this.onSupprimer});

  static const Map<String, Color> _couleurs = {
    'Tomate': Color(0xFFFF7043), 'Maïs': Color(0xFFFDD835),
    'Mil': Color(0xFFFFB300), 'Vigne': Color(0xFF8E24AA), 'Pommier': Color(0xFFE53935),
  };

  @override
  Widget build(BuildContext context) {
    final couleur = _couleurs[parcelle.culture] ?? Colors.green;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          // Vignette photo/couleur
          ClipRRect(
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
            child: (parcelle.photoPath != null && !kIsWeb)
                ? Image.file(File(parcelle.photoPath!), width: 90, height: 110, fit: BoxFit.cover)
                : Container(
                    width: 90, height: 110,
                    color: couleur.withValues(alpha: 0.15),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.grass, color: couleur, size: 32),
                      const SizedBox(height: 4),
                      Text(parcelle.culture, style: TextStyle(fontSize: 11, color: couleur, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ]),
                  ),
          ),
          // Infos
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(parcelle.nom, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(children: [Icon(Icons.eco, size: 13, color: couleur), const SizedBox(width: 4), Text(parcelle.culture, style: TextStyle(fontSize: 12, color: couleur))]),
                if (parcelle.superficie != null)
                  Row(children: [const Icon(Icons.straighten, size: 13, color: Colors.grey), const SizedBox(width: 4), Text('${parcelle.superficie!.toStringAsFixed(2)} ha', style: const TextStyle(fontSize: 12, color: Colors.grey))]),
                if (parcelle.latitude != null)
                  Row(children: [const Icon(Icons.location_on, size: 13, color: Colors.blue), const SizedBox(width: 4), Expanded(child: Text('${parcelle.latitude!.toStringAsFixed(3)}, ${parcelle.longitude!.toStringAsFixed(3)}', style: const TextStyle(fontSize: 11, color: Colors.blue), overflow: TextOverflow.ellipsis))]),
                const SizedBox(height: 4),
                Text(parcelle.dateCreation, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ),
          ),
          // Actions
          Column(children: [
            IconButton(
              icon: Icon(Icons.qr_code_2, color: Colors.green.shade700, size: 28),
              onPressed: () => showDialog(context: context, builder: (_) => _DialogQRCode(parcelle: parcelle)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
              onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(
                title: const Text('Supprimer ?'),
                content: Text('"${parcelle.nom}" sera supprimée.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
                  TextButton(onPressed: () { Navigator.pop(context); onSupprimer(); }, child: const Text('Supprimer', style: TextStyle(color: Colors.red))),
                ],
              )),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Dialogue QR Code ────────────────────────────────────────────────────────
class _DialogQRCode extends StatefulWidget {
  final Parcelle parcelle;
  const _DialogQRCode({required this.parcelle});
  @override
  State<_DialogQRCode> createState() => _DialogQRCodeState();
}

class _DialogQRCodeState extends State<_DialogQRCode> {
  final GlobalKey _qrKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.qr_code_2, color: Colors.green.shade700, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.parcelle.nom, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(widget.parcelle.culture, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ])),
          ]),
          const SizedBox(height: 20),
          RepaintBoundary(
            key: _qrKey,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(children: [
                QrImageView(
                  data: widget.parcelle.qrData,
                  version: QrVersions.auto,
                  size: 200,
                  backgroundColor: Colors.white,
                  eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.green.shade800),
                  dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.green.shade900),
                ),
                const SizedBox(height: 8),
                Text(widget.parcelle.nom, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(widget.parcelle.culture, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
            child: const Row(children: [
              Icon(Icons.info_outline, size: 16, color: Colors.blue),
              SizedBox(width: 8),
              Expanded(child: Text('Collez sur le piquet de la parcelle. Scannez pour accéder à son historique.', style: TextStyle(fontSize: 12, color: Colors.blue))),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(
              onPressed: () => _telecharger(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
              icon: const Icon(Icons.download, color: Colors.white),
              label: const Text('Télécharger', style: TextStyle(color: Colors.white)),
            )),
          ]),
        ]),
      ),
    );
  }

  Future<void> _telecharger(BuildContext context) async {
    try {
      final boundary = _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      if (!kIsWeb && Platform.isAndroid) {
        final dir  = Directory('/storage/emulated/0/Pictures');
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final file = File('${dir.path}/QR_${widget.parcelle.nom}_${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(bytes);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sauvegardé : ${file.path}'), backgroundColor: Colors.green));
      } else {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Faites une capture d\'écran pour sauvegarder.'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red));
    }
  }
}

// ── Scanner QR ──────────────────────────────────────────────────────────────
class _PageScanner extends StatefulWidget {
  const _PageScanner();
  @override
  State<_PageScanner> createState() => _PageScannerState();
}

class _PageScannerState extends State<_PageScanner> {
  bool _traite = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scanner', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) async {
            if (_traite) return;
            final raw = capture.barcodes.firstOrNull?.rawValue;
            if (raw == null) return;
            setState(() => _traite = true);
            await _traiterQR(raw);
          },
        ),
        Center(
          child: Container(
            width: 250, height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.green, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          bottom: 60, left: 0, right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: const Text('Pointez vers le QR code de la parcelle',
                  style: TextStyle(color: Colors.white, fontSize: 14), textAlign: TextAlign.center),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _traiterQR(String raw) async {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['type'] != 'agritech_parcelle') {
        _erreur('QR code non reconnu.'); return;
      }
      final parcelle = await ParcelleHelper.instance.getParcelleByUid(data['uid']);
      if (!mounted) return;
      if (parcelle == null) {
        _erreur('Parcelle "${data['nom']}" introuvable sur cet appareil.'); return;
      }
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => ParcelleDetailPage(parcelle: parcelle)));
    } catch (_) {
      _erreur('QR code invalide.');
    }
  }

  void _erreur(String msg) {
    if (!mounted) return;
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Erreur'),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () { Navigator.pop(context); setState(() => _traite = false); }, child: const Text('Réessayer')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
      ],
    ));
  }
}

// ── Formulaire création ─────────────────────────────────────────────────────
class _FormulaireCreationParcelle extends StatefulWidget {
  const _FormulaireCreationParcelle();
  @override
  State<_FormulaireCreationParcelle> createState() => _FormulaireCreationParcelleState();
}

class _FormulaireCreationParcelleState extends State<_FormulaireCreationParcelle> {
  final _formKey        = GlobalKey<FormState>();
  final _nomCtrl        = TextEditingController();
  final _superficieCtrl = TextEditingController();
  final _notesCtrl      = TextEditingController();
  String     _culture        = _cultures.first;
  Uint8List? _photoBytes;
  String?    _photoPath;
  double?    _latitude;
  double?    _longitude;
  bool       _gpsEnCours     = false;
  bool       _enregistrement = false;

  @override
  void dispose() {
    _nomCtrl.dispose(); _superficieCtrl.dispose(); _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _prendrePhoto() async {
    final src = await showModalBottomSheet<ImageSource>(context: context, builder: (_) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Caméra'), onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galerie'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ]));
    if (src == null) return;
    final file = await ImagePicker().pickImage(source: src, imageQuality: 70);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() { _photoBytes = bytes; _photoPath = file.path; });
  }

  Future<void> _obtenirGPS() async {
    setState(() => _gpsEnCours = true);
    try {
      if (!await geo.Geolocator.isLocationServiceEnabled()) throw Exception('GPS désactivé');
      geo.LocationPermission p = await geo.Geolocator.checkPermission();
      if (p == geo.LocationPermission.denied) { p = await geo.Geolocator.requestPermission(); }
      if (p == geo.LocationPermission.denied || p == geo.LocationPermission.deniedForever) throw Exception('Permission refusée');
      final pos = await geo.Geolocator.getCurrentPosition(desiredAccuracy: geo.LocationAccuracy.medium, timeLimit: const Duration(seconds: 10));
      setState(() { _latitude = pos.latitude; _longitude = pos.longitude; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GPS : $e'), backgroundColor: Colors.orange));
    } finally { setState(() => _gpsEnCours = false); }
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _enregistrement = true);
    final now = DateTime.now();
    final p = Parcelle(
      uid: ParcelleHelper.genererUid(),
      nom: _nomCtrl.text.trim(),
      culture: _culture,
      superficie: double.tryParse(_superficieCtrl.text),
      latitude: _latitude, longitude: _longitude,
      photoPath: _photoPath,
      dateCreation: "${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year}",
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    await ParcelleHelper.instance.insertParcelle(p);
    setState(() => _enregistrement = false);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F0),
      appBar: AppBar(title: const Text('Nouvelle parcelle', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(children: [
            // Photo
            GestureDetector(
              onTap: _prendrePhoto,
              child: Container(
                height: 180, width: double.infinity,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.shade200, width: 2)),
                child: _photoBytes != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(_photoBytes!, fit: BoxFit.cover, width: double.infinity))
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_photo_alternate, size: 48, color: Colors.green.shade300),
                        const SizedBox(height: 8),
                        Text('Ajouter une photo', style: TextStyle(color: Colors.green.shade400)),
                      ]),
              ),
            ),
            const SizedBox(height: 16),
            // Nom
            TextFormField(
              controller: _nomCtrl,
              validator: (v) => v!.trim().isEmpty ? 'Requis' : null,
              decoration: InputDecoration(labelText: 'Nom de la parcelle *', hintText: 'Ex: Champ Nord', prefixIcon: const Icon(Icons.landscape), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300))),
            ),
            const SizedBox(height: 12),
            // Culture
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _culture, isExpanded: true,
                  items: _cultures.map((c) => DropdownMenuItem(value: c, child: Row(children: [const Icon(Icons.eco, size: 18, color: Colors.green), const SizedBox(width: 10), Text(c)]))).toList(),
                  onChanged: (v) => setState(() => _culture = v!),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Superficie
            TextFormField(
              controller: _superficieCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Superficie (ha)', hintText: 'Ex: 0.5', prefixIcon: const Icon(Icons.straighten), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300))),
            ),
            const SizedBox(height: 12),
            // GPS
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _latitude != null ? Colors.blue.shade200 : Colors.grey.shade300)),
              child: Row(children: [
                Icon(Icons.location_on, color: _latitude != null ? Colors.blue : Colors.grey),
                const SizedBox(width: 10),
                Expanded(child: _latitude != null
                    ? Text('${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}', style: const TextStyle(color: Colors.blue, fontSize: 13))
                    : const Text('Localisation non capturée', style: TextStyle(color: Colors.grey))),
                _gpsEnCours
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton.icon(onPressed: _obtenirGPS, icon: const Icon(Icons.my_location, size: 16), label: Text(_latitude != null ? 'Recapturer' : 'Capturer')),
              ]),
            ),
            const SizedBox(height: 12),
            // Notes
            TextFormField(
              controller: _notesCtrl, maxLines: 3,
              decoration: InputDecoration(labelText: 'Notes (optionnel)', hintText: 'Sol argileux, irrigation...', prefixIcon: const Icon(Icons.notes), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300))),
            ),
            const SizedBox(height: 24),
            // Bouton
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _enregistrement ? null : _enregistrer,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: _enregistrement ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, color: Colors.white),
                label: Text(_enregistrement ? 'Enregistrement...' : 'Enregistrer la parcelle', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 30),
          ]),
        ),
      ),
    );
  }
}