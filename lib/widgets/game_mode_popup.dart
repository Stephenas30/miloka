import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../screens/classic_team_lobby_screen.dart';
import '../screens/game_screen.dart';
import '../service/team_lobby_service.dart';

class GameModePopup extends StatefulWidget {
  final String mode;
  final VoidCallback? onClosePopup;

  const GameModePopup({super.key, required this.mode, this.onClosePopup});

  @override
  State<GameModePopup> createState() => _GameModePopupState();
}

class _GameModePopupState extends State<GameModePopup> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController adversaireController = TextEditingController();
  final TextEditingController montantController = TextEditingController();
  final TextEditingController teamIdController = TextEditingController();

  String? difficulte;
  String? modeIA;
  String? errorMessage;

  final TeamLobbyService _teamLobbyService = TeamLobbyService();

  Future<void> _createTeam() async {
    final authProvider = Provider.of<AuthProvider?>(context, listen: false);
    final currentUser = authProvider?.currentUser;
    final profile = authProvider?.userProfile ?? {};

    if (currentUser == null) {
      setState(() {
        errorMessage = 'Connecte-toi pour créer une équipe.';
      });
      return;
    }

    try {
      final teamId = await _teamLobbyService.createTeam(currentUser.id, profile);
      Navigator.pop(context);
      widget.onClosePopup?.call();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClassicTeamLobbyScreen(teamId: teamId, isHost: true),
        ),
      );
    } catch (e) {
      setState(() {
        errorMessage = 'Erreur : ${e.toString()}';
      });
    }
  }

  Future<void> _joinTeam() async {
    final authProvider = Provider.of<AuthProvider?>(context, listen: false);
    final currentUser = authProvider?.currentUser;
    final profile = authProvider?.userProfile ?? {};
    final teamId = teamIdController.text.trim();

    if (currentUser == null) {
      setState(() {
        errorMessage = 'Connecte-toi pour rejoindre une équipe.';
      });
      return;
    }

    if (teamId.isEmpty) {
      setState(() {
        errorMessage = 'Entre l’ID de l’équipe.';
      });
      return;
    }

    final team = await _teamLobbyService.getTeam(teamId);
    if (team == null) {
      setState(() {
        errorMessage = 'Aucune équipe trouvée avec cet ID.';
      });
      return;
    }

    if (team['host_id'] == currentUser.id) {
      setState(() {
        errorMessage = 'Tu es déjà l’hôte de cette équipe.';
      });
      return;
    }

    try {
      final joined = await _teamLobbyService.joinTeam(teamId, currentUser.id, profile);
      if (!joined) {
        setState(() {
          errorMessage = 'Impossible de rejoindre, l\'équipe est peut-être déjà complète.';
        });
        return;
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Erreur : ${e.toString()}';
      });
      return;
    }

    Navigator.pop(context);
    widget.onClosePopup?.call();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClassicTeamLobbyScreen(teamId: teamId, isHost: false),
      ),
    );
  }

  @override
  void dispose() {
    adversaireController.dispose();
    montantController.dispose();
    teamIdController.dispose();
    super.dispose();
  }

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
        content = Column(
          children: [
            TextFormField(
              controller: teamIdController,
              decoration: const InputDecoration(labelText: "ID Équipe"),
            ),
            const SizedBox(height: 16),
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _joinTeam,
                    child: const Text('Joindre'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _createTeam,
                    child: const Text('Créer'),
                  ),
                ),
              ],
            ),
          ],
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
        width: 280,
        height: 260,
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
            const SizedBox(height: 12),
            if (widget.mode != "Classique")
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
                          Navigator.pop(context);
                          widget.onClosePopup?.call();
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const GameScreen()),
                          );
                        } else {
                          print("Mode: ${widget.mode}");
                          print("Adversaire: ${adversaireController.text}");
                          print("Montant: ${montantController.text}");
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
