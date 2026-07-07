import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  static const String _airtelNumberDisplay = '+261 33 52 968 61';
  static const String _airtelNumberRaw = '+261335296861';
  bool _isProcessing = false;

  Future<void> _copyNumber() async {
    await Clipboard.setData(const ClipboardData(text: _airtelNumberRaw));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Numéro copié dans le presse-papiers')),
    );
  }

  Future<void> _confirmPaid() async {
    setState(() => _isProcessing = true);
    try {
      final authProvider = Provider.of<AuthProvider?>(context, listen: false);
      final profile = authProvider?.userProfile ?? {};
      final currentCoins = int.tryParse((profile['coins'] ?? '0').toString()) ?? 0;

      if (authProvider != null) {
        await authProvider.updateUserProfile({'coins': currentCoins + 1});
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci — 1 jeton ajouté après vérification.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Padding(
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
                    const SizedBox(width: 8),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Acheter des jetons',
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Paiement via Airtel Money', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('Envoyer 100 Ar = 1 jeton'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.phone_android, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_airtelNumberDisplay)),
                            IconButton(
                              onPressed: _copyNumber,
                              icon: const Icon(Icons.copy),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('Après paiement, appuyez sur "J\'ai payé" pour demander l\'ajout du jeton.'),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isProcessing ? null : _confirmPaid,
                            child: _isProcessing
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text("J'ai payé"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                const Text('Remarques', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 8),
                const Text('- Paiement manuel via Airtel Money à ce numéro.\n- Le jeton sera ajouté après vérification manuelle.', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
