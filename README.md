# 🎮 Miloka

## 🚀 Présentation
**Miloka** est une application Flutter regroupant plusieurs jeux classiques et populaires :
- **Belote** (avec distribution animée, système d’appel, contre IA ou en ligne)
- **Rami**
- **Billard**
- **Ludo**

L’application propose une expérience multi‑joueurs (local, IA, en ligne) avec un système de **création de compte** et de **gestion des utilisateurs** pour suivre les parties, scores et classements.

---

## 🛠️ Technologies utilisées
- **Flutter** (UI multiplateforme)
- **Dart** (logique applicative)
- **flutter_svg** (affichage des cartes au format SVG)
- **Provider / Riverpod** (gestion d’état)
- **Firebase / Supabase** (authentification et base de données en ligne)
- **n8n** (automatisation de workflows, ex. création d’email, notifications)
- **WordPress API** (optionnel pour gestion des comptes et intégration web)

---

## 📂 Structure du projet
```
lib/
 ├── main.dart                # Point d'entrée
 ├── screens/                 # Pages principales (GameScreen, HomeScreen, Login, etc.)
 ├── game/                    # Logique des jeux
 │    ├── deck.dart           # Gestion du paquet de cartes
 │    ├── call_system.dart    # Système d'appel (Belote)
 │    └── ...
 ├── models/                  # Modèles (CardModel, Player, User, etc.)
 ├── services/                # Authentification, API, email
 │    ├── auth_service.dart
 │    └── email_service.dart
 ├── widgets/                 # Composants réutilisables (CallPopup, GameChoiceCard)
assets/
 └── images/
      └── card/               # Cartes SVG (carreau-9.svg, coeur-A.svg, dos.svg, etc.)
```

---

## ⚙️ Installation
1. Cloner le projet :
   ```bash
   git clone https://github.com/ton-compte/miloka.git
   cd miloka
   ```
2. Installer les dépendances :
   ```bash
   flutter pub get
   ```
3. Lancer l’application :
   ```bash
   flutter run
   ```

---

## 🎮 Fonctionnalités principales
- **Accueil** : choix du jeu (Belote, Rami, Billard, Ludo…).
- **Belote** :
  - Distribution animée des cartes (3 puis 2, sens inverse des aiguilles d’une montre).
  - Système d’appel avec popup interactif.
  - Modes : 1v1, 2v2, tournoi, contre IA, en ligne.
- **Rami** : logique de jeu en cours de développement.
- **Billard / Ludo** : placeholders avec règles à implémenter.
- **IA** : niveaux de difficulté (facile, moyen, difficile).
- **En ligne** : matchmaking + mise en jeu (si backend activé).

---

## 👤 Gestion des comptes et authentification
- **Création de compte** : identifiant, mot de passe, email.
- **Validation email** : envoi d’un code de confirmation ou lien d’activation.
- **Connexion / déconnexion**.
- **Mot de passe oublié** : récupération via email.
- **Activation automatique** : déclenchement de workflows (ex. création d’adresse email via n8n).
- **Redirection** : accès aux pages protégées uniquement après connexion.

### 🔒 Sécurité
- Mot de passe : minimum 12 caractères, majuscule, minuscule, chiffre.
- Validation email obligatoire.
- Stockage sécurisé (hash + salt).
- Limitation des tentatives de connexion.

---

## 📦 Dépendances principales
```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_svg: ^2.0.9
  provider: ^6.0.5   # ou riverpod
  firebase_core: ^2.0.0
  firebase_auth: ^4.0.0
  supabase_flutter: ^1.0.0
```

---

## 🧑‍💻 Contribution
1. Forker le projet.
2. Créer une branche :
   ```bash
   git checkout -b feature/ma-fonctionnalite
   ```
3. Commit et push :
   ```bash
   git commit -m "Ajout de la fonctionnalité X"
   git push origin feature/ma-fonctionnalite
   ```
4. Ouvrir une Pull Request.

---

## 📝 Roadmap
- [x] Distribution animée des cartes en Belote.  
- [x] Système d’appel avec popup en Belote.  
- [ ] Création de compte avec validation email.  
- [ ] Implémentation complète du Rami.  
- [ ] Ajout du Billard.  
- [ ] Ajout du Ludo.  
- [ ] Mode en ligne avec matchmaking.  
- [ ] Sauvegarde des scores et classements.  
- [ ] Authentification sociale (Google, Facebook).  

---

## ⚖️ Licence
Projet **Miloka** sous licence MIT. Libre à l’utilisation et à la modification.