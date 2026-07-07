import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.profile});

  final Map<String, dynamic>? profile;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _usernameController;
  late String _avatarUrl;
  late int _coins;
  bool _isSaving = false;
  bool _isSigningOut = false;
  bool _isPickingImage = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile ?? context.read<AuthProvider>().userProfile ?? {};
    _usernameController = TextEditingController(text: (profile['username'] ?? profile['full_name'] ?? '').toString());
    _avatarUrl = (profile['avatar_url'] ?? '').toString();
    _coins = int.tryParse((profile['coins'] ?? '0').toString()) ?? 0;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (!mounted) return;

    setState(() => _isPickingImage = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        requestFullMetadata: false,
      );

      if (picked != null && picked.path.isNotEmpty) {
        setState(() {
          _avatarUrl = picked.path;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo sélectionnée. Appuie sur Enregistrer pour la sauvegarder.')),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune image sélectionnée')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de sélectionner une image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      final authProvider = Provider.of<AuthProvider?>(context, listen: false);
      final localAvatarPath = _avatarUrl.isNotEmpty && !_avatarUrl.startsWith('http') ? _avatarUrl : null;

      if (authProvider != null) {
        await authProvider.updateUserProfile({
          'username': _usernameController.text.trim(),
          'avatar_url': _avatarUrl,
          'coins': _coins,
        }, localAvatarPath: localAvatarPath);
      } else {
        setState(() {
          _avatarUrl = _avatarUrl;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil mis à jour')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la mise à jour')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _signOut() async {
    if (!mounted) return;
    setState(() => _isSigningOut = true);

    try {
      final authProvider = Provider.of<AuthProvider?>(context, listen: false);
      await authProvider?.signOut();

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la déconnexion : $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider?>(context);
    final profile = widget.profile ?? authProvider?.userProfile ?? {};
    final fullName = (profile['full_name'] ?? profile['username'] ?? 'Joueur').toString();
    final email = (profile['email'] ?? '').toString();
    final username = (profile['username'] ?? fullName).toString();
    final avatarUrl = _avatarUrl.isNotEmpty ? _avatarUrl : null;

    final belotePlayed = int.tryParse((profile['belote_played'] ?? '0').toString()) ?? 0;
    final beloteWins = int.tryParse((profile['belote_wins'] ?? '0').toString()) ?? 0;
    final beloteLosses = int.tryParse((profile['belote_losses'] ?? '0').toString()) ?? 0;
    final ludoPlayed = int.tryParse((profile['ludo_played'] ?? '0').toString()) ?? 0;
    final ludoWins = int.tryParse((profile['ludo_wins'] ?? '0').toString()) ?? 0;
    final ludoLosses = int.tryParse((profile['ludo_losses'] ?? '0').toString()) ?? 0;

    final totalGames = belotePlayed + ludoPlayed;
    final totalWins = beloteWins + ludoWins;
    final beloteLevel = int.tryParse((profile['belote_level'] ?? '1').toString()) ?? 1;
    final beloteXp = int.tryParse((profile['belote_xp'] ?? '0').toString()) ?? 0;
    final beloteXpProgress = int.tryParse((profile['belote_xp_progress'] ?? '0').toString()) ?? 0;
    final ludoLevel = int.tryParse((profile['ludo_level'] ?? '1').toString()) ?? 1;
    final ludoXp = int.tryParse((profile['ludo_xp'] ?? '0').toString()) ?? 0;
    final ludoXpProgress = int.tryParse((profile['ludo_xp_progress'] ?? '0').toString()) ?? 0;
    final badges = ((profile['badges'] ?? '') as String)
        .split(',')
        .where((item) => item.isNotEmpty)
        .toList();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: Navigator.of(context).canPop() ? () => Navigator.of(context).pop() : null,
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isSigningOut ? null : _signOut,
                      icon: _isSigningOut
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.logout),
                      label: Text(_isSigningOut ? 'Déconnexion...' : 'Déconnexion'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Profil',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Jetons : $_coins',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.white70,
                            backgroundImage: avatarUrl != null && avatarUrl.startsWith('http')
                                ? NetworkImage(avatarUrl)
                                : (avatarUrl != null ? FileImage(File(avatarUrl)) : null) as ImageProvider<Object>?,
                            child: avatarUrl == null
                                ? const Icon(Icons.person, size: 50, color: Colors.blueGrey)
                                : null,
                          ),
                          GestureDetector(
                            onTap: _isPickingImage ? null : _pickImage,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: _isPickingImage
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@$username',
                        style: const TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        email,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Informations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Nom d’utilisateur',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.monetization_on, color: Colors.amber),
                            const SizedBox(width: 8),
                            const Text('Jetons :'),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                initialValue: _coins.toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onChanged: (value) {
                                  setState(() => _coins = int.tryParse(value) ?? 0);
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.emoji_events, color: Colors.amber),
                            const SizedBox(width: 8),
                            const Text('Niveau & progression', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Belote', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text('Niv. $beloteLevel • $beloteXp XP', style: const TextStyle(color: Colors.blueGrey)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: LinearProgressIndicator(
                            value: (beloteXp / 1000).clamp(0.0, 1.0),
                            minHeight: 10,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Belote : $beloteXpProgress XP jusqu’au prochain palier', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Ludo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text('Niv. $ludoLevel • $ludoXp XP', style: const TextStyle(color: Colors.blueGrey)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: LinearProgressIndicator(
                            value: (ludoXp / 1000).clamp(0.0, 1.0),
                            minHeight: 10,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('Ludo : $ludoXpProgress XP jusqu’au prochain palier', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (badges.contains('FirstWin')) _buildBadge('Première victoire', Icons.emoji_events),
                            if (badges.contains('Starter')) _buildBadge('Débutant confirmé', Icons.sports_esports),
                            if (badges.contains('RisingStar')) _buildBadge('Étoile montante', Icons.star),
                            if (badges.contains('Legend')) _buildBadge('Légende', Icons.auto_awesome),
                            if (badges.isEmpty) const Text('Aucun badge débloqué pour le moment'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Statistiques par jeu', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildGameStats('Belote', belotePlayed, beloteWins, beloteLosses),
                const SizedBox(height: 12),
                _buildGameStats('Ludo', ludoPlayed, ludoWins, ludoLosses),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Succès', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _buildAchievement('Première victoire', totalWins >= 1, Icons.emoji_events),
                        _buildAchievement('5 parties jouées', totalGames >= 5, Icons.sports_esports),
                        _buildAchievement('Maître des jetons', _coins >= 100, Icons.monetization_on),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Activité récente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _buildRecentActivity('Partie Belote terminée', 'Victoire • il y a 2h'),
                        _buildRecentActivity('Nouveau username défini', 'il y a 1 jour'),
                        _buildRecentActivity('Réception de 50 jetons', 'il y a 2 jours'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveProfile,
                    icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                    label: Text(_isSaving ? 'Enregistrement...' : 'Enregistrer'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameStats(String gameName, int played, int wins, int losses) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(gameName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                _statChip('Jouées', played),
                const SizedBox(width: 8),
                _statChip('Victoires', wins),
                const SizedBox(width: 8),
                _statChip('Défaites', losses),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievement(String title, bool unlocked, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: unlocked ? Colors.amber : Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(color: unlocked ? Colors.black : Colors.grey))),
          Icon(unlocked ? Icons.check_circle : Icons.lock, color: unlocked ? Colors.green : Colors.grey),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.deepPurple),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.deepPurple)),
        ],
      ),
    );
  }

  Widget _buildRecentActivity(String title, String subtitle) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.history)),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }

  Widget _statChip(String label, int value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Text(value.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
