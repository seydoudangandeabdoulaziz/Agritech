import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'forum_page.dart';

// Langues disponibles pour le profil
const List<Map<String, String>> languesProfil = [
  {'code': 'fr',  'nom': 'Français',  'drapeau': '🇫🇷'},
  {'code': 'en',  'nom': 'English',   'drapeau': '🇬🇧'},
  {'code': 'ha',  'nom': 'Haoussa',   'drapeau': '🇳🇬'},
  {'code': 'dje', 'nom': 'Zarma',     'drapeau': '🇳🇪'},
  {'code': 'ar',  'nom': 'العربية',   'drapeau': '🇸🇦'},
  {'code': 'ff',  'nom': 'Fulfulde',  'drapeau': '🇬🇳'},
  {'code': 'tmh', 'nom': 'Tamasheq', 'drapeau': '🇲🇱'},
];

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Connexion
  final _emailConnexion = TextEditingController();
  final _mdpConnexion = TextEditingController();

  // Inscription
  final _nomInscription = TextEditingController();
  final _emailInscription = TextEditingController();
  final _mdpInscription = TextEditingController();
  final _paysInscription = TextEditingController();
  String _langueSelectionnee = 'fr';

  bool _isLoading = false;
  bool _mdpVisible = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() => _erreur = null));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailConnexion.dispose();
    _mdpConnexion.dispose();
    _nomInscription.dispose();
    _emailInscription.dispose();
    _mdpInscription.dispose();
    _paysInscription.dispose();
    super.dispose();
  }

  Future<void> _connecter() async {
    if (_emailConnexion.text.isEmpty || _mdpConnexion.text.isEmpty) {
      setState(() => _erreur = "Remplissez tous les champs.");
      return;
    }
    setState(() { _isLoading = true; _erreur = null; });
    final erreur = await AuthService.connecter(
      email: _emailConnexion.text.trim(),
      motDePasse: _mdpConnexion.text,
    );
    if (mounted) {
      setState(() { _isLoading = false; _erreur = erreur; });
      if (erreur == null) _allerAuForum();
    }
  }

  Future<void> _inscrire() async {
    if (_nomInscription.text.isEmpty ||
        _emailInscription.text.isEmpty ||
        _mdpInscription.text.isEmpty) {
      setState(() => _erreur = "Remplissez tous les champs obligatoires.");
      return;
    }
    setState(() { _isLoading = true; _erreur = null; });
    final erreur = await AuthService.inscrire(
      email: _emailInscription.text.trim(),
      motDePasse: _mdpInscription.text,
      nom: _nomInscription.text.trim(),
      langue: _langueSelectionnee,
      pays: _paysInscription.text.trim(),
    );
    if (mounted) {
      setState(() { _isLoading = false; _erreur = erreur; });
      if (erreur == null) _allerAuForum();
    }
  }

 void _allerAuForum() {
  // ✅ Revenir à la page principale ET ouvrir le forum
  Navigator.pop(context); // Ferme le login
  Navigator.push(context,
      MaterialPageRoute(builder: (_) => const ForumPage()));
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green[50],
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 30),

              // ── Logo ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.eco, size: 60, color: Colors.white),
              ),

              const SizedBox(height: 16),
              const Text("AgriTech 🌿",
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
              const Text("Communauté des agriculteurs",
                  style: TextStyle(color: Colors.grey, fontSize: 14)),

              const SizedBox(height: 32),

              // ── Onglets Connexion / Inscription ──
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    TabBar(
                      controller: _tabController,
                      labelColor: Colors.green,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.green,
                      tabs: const [
                        Tab(text: "Connexion"),
                        Tab(text: "Inscription"),
                      ],
                    ),
                    const Divider(height: 1),
                    SizedBox(
                      height: _tabController.index == 0 ? 280 : 480,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildConnexion(),
                          _buildInscription(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Erreur ──
              if (_erreur != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_erreur!,
                              style: const TextStyle(color: Colors.red))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // ── Formulaire Connexion ──
  Widget _buildConnexion() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _champ(controller: _emailConnexion,
              label: "Email", icon: Icons.email),
          const SizedBox(height: 14),
          _champ(controller: _mdpConnexion,
              label: "Mot de passe", icon: Icons.lock,
              estMotDePasse: true),
          const SizedBox(height: 24),
          _boutonAction("Se connecter", _connecter),
        ],
      ),
    );
  }

  // ── Formulaire Inscription ──
  Widget _buildInscription() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _champ(controller: _nomInscription,
              label: "Nom complet *", icon: Icons.person),
          const SizedBox(height: 12),
          _champ(controller: _emailInscription,
              label: "Email *", icon: Icons.email),
          const SizedBox(height: 12),
          _champ(controller: _mdpInscription,
              label: "Mot de passe *", icon: Icons.lock,
              estMotDePasse: true),
          const SizedBox(height: 12),
          _champ(controller: _paysInscription,
              label: "Pays (optionnel)", icon: Icons.flag),
          const SizedBox(height: 12),

          // ── Sélecteur de langue ──
          DropdownButtonFormField<String>(
            initialValue: _langueSelectionnee,
            decoration: InputDecoration(
              labelText: "Votre langue",
              prefixIcon: const Icon(Icons.language, color: Colors.green),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.green),
              ),
            ),
            items: languesProfil.map((l) {
              return DropdownMenuItem(
                value: l['code'],
                child: Text("${l['drapeau']} ${l['nom']}"),
              );
            }).toList(),
            onChanged: (val) =>
                setState(() => _langueSelectionnee = val ?? 'fr'),
          ),

          const SizedBox(height: 20),
          _boutonAction("S'inscrire", _inscrire),
        ],
      ),
    );
  }

  Widget _champ({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool estMotDePasse = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: estMotDePasse && !_mdpVisible,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.green),
        suffixIcon: estMotDePasse
            ? IconButton(
                icon: Icon(
                    _mdpVisible ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey),
                onPressed: () => setState(() => _mdpVisible = !_mdpVisible),
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.green),
        ),
      ),
    );
  }

  Widget _boutonAction(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
      ),
    );
  }
}