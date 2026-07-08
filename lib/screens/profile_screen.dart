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

  Widget _buildRecentActivity(String title, String subtitle) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.history)),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}
