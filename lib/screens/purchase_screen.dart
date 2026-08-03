import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  static const String _airtelNumberDisplay = '+261 33 52 968 61';
  static const String _airtelNumberRaw = '+261335296861';

  final _purchaseRefController = TextEditingController();
  final _withdrawAmountController = TextEditingController();
  final _withdrawPhoneController = TextEditingController();

  @override
  void dispose() {
    _purchaseRefController.dispose();
    _withdrawAmountController.dispose();
    _withdrawPhoneController.dispose();
    super.dispose();
  }

  Future<void> _copyNumber() async {
    await Clipboard.setData(const ClipboardData(text: _airtelNumberRaw));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Numéro copié dans le presse-papiers')),
    );
  }

  Future<void> _showPurchaseDialog() async {
    _purchaseRefController.clear();
    final ref = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Référence du paiement'),
        content: TextField(
          controller: _purchaseRefController,
          decoration: const InputDecoration(
            hintText: 'Entrez la référence du transfert',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, _purchaseRefController.text),
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
    if (ref == null || ref.trim().isEmpty) return;
    await _submitPurchase(ref.trim());
  }

  Future<void> _submitPurchase(String reference) async {
    final authProvider = Provider.of<AuthProvider?>(context, listen: false);
    final userId = authProvider?.currentUser?.id;
    if (userId == null) return;

    try {
      await Supabase.instance.client.from('transaction_requests').insert({
        'user_id': userId,
        'type': 'purchase',
        'amount': 1,
        'reference': reference,
        'status': 'pending',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande envoyée — vérification manuelle en cours.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  Future<void> _showWithdrawalDialog() async {
    final authProvider = Provider.of<AuthProvider?>(context, listen: false);
    final coins =
        int.tryParse((authProvider?.userProfile?['coins'] ?? '0').toString()) ?? 0;

    final formKey = GlobalKey<FormState>();
    _withdrawAmountController.clear();
    _withdrawPhoneController.clear();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => Form(
        key: formKey,
        child: AlertDialog(
          title: const Text('Demande de retrait'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Jetons disponibles : $coins'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _withdrawAmountController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de jetons',
                  hintText: 'Montant à retirer',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  final amount = int.tryParse(value ?? '');
                  if (amount == null || amount <= 0) return 'Montant invalide';
                  if (amount > coins) return 'Montant supérieur au solde';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _withdrawPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Numéro de réception',
                  hintText: 'Numéro où recevoir',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Numéro requis';
                  return null;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, {
                    'amount': _withdrawAmountController.text,
                    'phone': _withdrawPhoneController.text,
                  });
                }
              },
              child: const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final amount = int.tryParse(result['amount'] ?? '');
    final phone = result['phone'] ?? '';
    if (amount == null || amount <= 0) return;
    await _submitWithdrawal(amount, phone);
  }

  Future<void> _submitWithdrawal(int amount, String phone) async {
    final authProvider = Provider.of<AuthProvider?>(context, listen: false);
    final userId = authProvider?.currentUser?.id;
    if (userId == null) return;

    try {
      await Supabase.instance.client.from('transaction_requests').insert({
        'user_id': userId,
        'type': 'withdrawal',
        'amount': amount,
        'reference': phone,
        'status': 'pending',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande de retrait envoyée.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider?>(context);
    final coins =
        int.tryParse((authProvider?.userProfile?['coins'] ?? '0').toString()) ?? 0;

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
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: Navigator.of(context).canPop() ? () => Navigator.of(context).pop() : null,
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
                          const SizedBox(width: 6),
                          Text('$coins', style: const TextStyle(color: Colors.white, fontSize: 14)),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              authProvider?.refreshProfile();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Jetons mis à jour'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: const Icon(Icons.refresh, color: Colors.white70, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Acheter des jetons',
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Paiement via Airtel Money', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                const Text('Envoyer 500 Ar = 1 jeton'),
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
                                const Text('Après paiement, appuyez sur "J\'ai payé" pour saisir la référence du transfert.'),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _showPurchaseDialog,
                                    child: const Text("J'ai payé"),
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

                        const SizedBox(height: 24),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 16),

                        const Text('Demander un retrait',
                            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Retirer vos jetons', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Text('Solde disponible : $coins jeton(s)'),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: coins > 0 ? _showWithdrawalDialog : null,
                                    icon: const Icon(Icons.arrow_upward),
                                    label: const Text('Demander un retrait'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
