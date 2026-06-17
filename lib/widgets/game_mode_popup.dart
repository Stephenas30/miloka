import 'package:flutter/material.dart';
import '../screens/game_screen.dart';

class GameModePopup extends StatefulWidget {
  final String mode;
  final VoidCallback? onClosePopup;

  const GameModePopup({super.key, required this.mode, this.onClosePopup});

  @override
  State<GameModePopup> createState() => _GameModePopupState();
}

class _GameModePopupState extends State<GameModePopup> {
  final _formKey = GlobalKey<FormState>();

  // Contrôleurs pour les champs
  final TextEditingController adversaireController = TextEditingController();
  final TextEditingController montantController = TextEditingController();
  final TextEditingController tableController = TextEditingController();
  final TextEditingController partenaireController = TextEditingController();

  String? difficulte;
  String? modeIA;

  @override
  Widget build(BuildContext context) {
    Widget content;

    switch (widget.mode) {
      case "1 vs 1":
        content = Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: adversaireController,
                decoration: const InputDecoration(labelText: "ID adversaire"),
                validator: (value) =>
                    value == null || value.isEmpty ? "Champ requis" : null,
              ),
              TextFormField(
                controller: montantController,
                decoration: const InputDecoration(labelText: "Montant misé"),
                keyboardType: TextInputType.number,
                validator: (value) =>
                    value == null || value.isEmpty ? "Champ requis" : null,
              ),
            ],
          ),
        );
        break;

      case "Classique":
        content = Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: tableController,
                decoration: const InputDecoration(labelText: "ID table"),
                validator: (value) =>
                    value == null || value.isEmpty ? "Champ requis" : null,
              ),
              TextFormField(
                controller: partenaireController,
                decoration: const InputDecoration(labelText: "ID partenaire"),
                validator: (value) =>
                    value == null || value.isEmpty ? "Champ requis" : null,
              ),
              TextFormField(
                controller: montantController,
                decoration: const InputDecoration(labelText: "Montant misé"),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        );
        break;

      case "Contre IA":
        content = Column(
          children: [
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Difficulté"),
              items: const [
                DropdownMenuItem(value: "Facile", child: Text("Facile")),
                DropdownMenuItem(value: "Moyen", child: Text("Moyen")),
                DropdownMenuItem(value: "Difficile", child: Text("Difficile")),
              ],
              onChanged: (val) => setState(() => difficulte = val),
              validator: (val) =>
                  val == null ? "Choisis une difficulté" : null,
            ),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: "Mode"),
              items: const [
                DropdownMenuItem(value: "Duel", child: Text("Duel (1v1)")),
                DropdownMenuItem(value: "Classique", child: Text("Classique (2v2)")),
              ],
              onChanged: (val) => setState(() => modeIA = val),
              validator: (val) => val == null ? "Choisis un mode" : null,
            ),
          ],
        );
        break;

      default:
        content = const Text("Pas de formulaire pour ce mode");
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 260,
        height: 380,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              widget.mode,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(child: SingleChildScrollView(child: content)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onClosePopup?.call();
                  },
                  child: const Text("Fermer"),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState?.validate() ?? true) {
                      if (widget.mode == "Contre IA") {
                        Navigator.pop(context); // ferme le popup
                        widget.onClosePopup?.call();

                        // Redirection vers la page de jeu
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const GameScreen()),
                        );
                      } else {
                        // Ici tu lances la logique du jeu
                        // Exemple : Navigator.push vers la page de jeu
                        print("Mode: ${widget.mode}");
                        print("Adversaire: ${adversaireController.text}");
                        print("Montant: ${montantController.text}");
                        print("ID table: ${tableController.text}");
                        print("ID partenaire: ${partenaireController.text}");
                        print("Difficulté: $difficulte");
                        print("Mode IA: $modeIA");
                        Navigator.pop(context);
                        widget.onClosePopup?.call();
                      }
                    }
                  },
                  child: Text(widget.mode == "En ligne" ? "Créer" : "Jouer"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
