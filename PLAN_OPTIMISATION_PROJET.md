# Plan d'optimisation du projet Miloka

## Objectif
Améliorer la qualité, la maintenabilité, la stabilité et la scalabilité du projet Flutter/Supabase afin de passer d'un MVP fonctionnel à un produit plus robuste, plus propre et plus facile à faire évoluer.

---

## 1. Audit général du projet

### À faire
- Faire un inventaire complet des écrans, services, modèles et flux critiques.
- Identifier les fonctionnalités réellement terminées, en cours et inachevées.
- Repérer les dépendances inutiles ou redondantes.
- Identifier les points de complexité élevée dans les écrans.
- Vérifier les flux d'authentification, d'invitations, de realtime et de profil utilisateur.

### Livrables
- Liste des modules stabilisés vs non stabilisés.
- Cartographie des flux métier critiques.
- Liste des fichiers à refactoriser en priorité.

### Priorité
Haute

---

## 2. Stabiliser l'authentification

### Problèmes à traiter
- Auth logic dispersée entre plusieurs fichiers.
- Connexion / inscription / profil utilisateur non centralisés.
- Risque de divergence entre provider, service et Supabase.
- Gestion d'erreurs parfois insuffisante.

### À faire
- Centraliser l'auth dans un service unique et clair.
- Séparer la logique métier de la logique d'affichage.
- Standardiser les erreurs utilisateur (ex: "Email invalide", "Connexion échouée").
- Vérifier la gestion des sessions persistantes.
- Nettoyer les print() de debug.
- Ajouter des mécanismes de retry pour les erreurs réseau.

### Fichiers concernés
- lib/providers/auth_provider.dart
- lib/service/auth_service.dart
- lib/service/supabase_service.dart
- lib/screens/login_screen.dart
- lib/screens/register_screen.dart

### Priorité
Très haute

---

## 3. Refactoriser la structure des écrans

### Problèmes à traiter
- Certains écrans, notamment la home, deviennent trop lourds.
- La logique de navigation, realtime, notifications et invitations est mélangée.
- Le code risque de devenir difficile à maintenir.

### À faire
- Séparer les écrans des services métier.
- Créer des classes de contrôle ou viewmodels pour les écrans complexes.
- Décomposer les écrans en composants plus petits et réutilisables.
- Simplifier les widgets surchargés.
- Regrouper les flux de notifications / realtime dans un module cohérent.

### Fichiers concernés
- lib/screens/home_screen.dart
- lib/screens/ludo_screen.dart
- lib/screens/fanorona/
- lib/screens/private_game_lobby_screen.dart
- lib/screens/classic_team_lobby_screen.dart

### Priorité
Très haute

---

## 4. Nettoyer et sécuriser le realtime / Supabase

### Problèmes à traiter
- Multiples abonnements à des canaux différents.
- Risque de doublons de listeners.
- Logique métier dispersée dans les écrans.
- Difficulté de debug sur les changements d'état.

### À faire
- Centraliser la gestion des channels Supabase dans un service dédié.
- Créer un système de gestion des abonnements unique.
- Vérifier les délais, les callbacks, les erreurs et les cleanup.
- Ajouter une méthode de désabonnement propre lors de la fermeture d'écran.
- S’assurer que les payloads sont bien validés avant traitement.

### Fichiers concernés
- lib/service/supabase_service.dart
- lib/service/team_lobby_service.dart
- lib/service/ludo_multiplayer_service.dart
- lib/service/private_match_service.dart
- lib/screens/home_screen.dart

### Priorité
Très haute

---

## 5. Améliorer la gestion des erreurs et des états

### Problèmes à traiter
- Gestion de l'erreur peu uniforme.
- Certaines exceptions remontent brutales à l'UI.
- Risque de messages inutilisables pour l'utilisateur.
- Certaines branches n'ont pas de fallback clair.

### À faire
- Introduire un système d'erreurs standardisé.
- Transformer les erreurs techniques en messages utilisateur intelligibles.
- Créer des états de chargement, succès, échec, vide et réessai.
- Ajouter de la robustesse pour les cas réseau indisponible.
- Vérifier les conséquences d'un échec de Supabase ou d'un payload incomplet.

### Priorité
Haute

---

## 6. Renforcer les tests

### Problèmes à traiter
- Les tests existent, mais il faut les valider et les étendre.
- Le projet semble avoir besoin de couverture sur les flux critiques.

### À faire
- Vérifier les tests déjà présents dans le dossier test/.
- Ajouter des tests unitaires sur :
  - logique d'authentification
  - logique jeu
  - invitation / ami / match
  - services Supabase wrappers
- Ajouter des tests widget sur les écrans principaux.
- Ajouter des tests de non-régression sur les flux critiques.

### Fichiers concernés
- test/fanorona_engine_test.dart
- test/ludo_engine_test.dart
- test/widget_test.dart

### Priorité
Haute

---

## 7. Nettoyer le code et supprimer les défauts de qualité

### À faire
- Supprimer les print() de production qui ne servent plus.
- Vérifier les TODO / commentaires obsolètes.
- Supprimer le code mort ou les méthodes inutilisées.
- Harmoniser le style de code et les conventions de nommage.
- Vérifier les imports non utilisés.
- Standardiser les noms anglais/français pour éviter le mélange.

### Priorité
Moyenne

---

## 8. Optimiser les performances

### À faire
- Vérifier les images lourdes et leur cache.
- Limiter les rebuilds inutiles via Provider / état local mieux géré.
- Réduire le nombre d'abonnements actifs en même temps.
- Vérifier l'usage des listes longues dans les écrans de lobby, amis, invitations.
- Optimiser la navigation lors des changements de state.
- Vérifier la consommation mémoire sur écrans complexes.

### Priorité
Moyenne

---

## 9. Clarifier la roadmap produit

### À faire
- Séparer le backlog en :
  - MVP stable
  - fonctionnalités complémentaires
  - jeux à finaliser
  - mode en ligne
  - scores / classements
  - côté social
- Définir ce qui doit être fini avant une beta test.
- Définir ce qui est “nice to have” pour plus tard.

### Priorité
Haute

---

## 10. Préparer la version “production”

### À faire
- Vérifier les variables d'environnement, clés et secrets.
- Sécuriser les accès Supabase.
- Vérifier les permissions RLS côté base.
- Faire une revue des privilèges utilisateur et table access.
- Tester les flux sur Android/iOS/Web selon le besoin.
- Faire une passe QA globale sur les écrans critiques.

### Priorité
Très haute

---

## Priorisation recommandée

### Semaine 1
- Audit des flux critiques
- Auth / session / profil
- Refactorisation de la home et écrans lourds
- Nettoyage des logs et erreurs

### Semaine 2
- Realtime / channels / notifications
- Tests unitaires et widget
- Stabilisation des lobby / invitations / jeux multi

### Semaine 3
- Performance et UX
- QA des flux plus importants
- Version beta / validation fonctionnelle

### Semaine 4+
- Finaliser les jeux incomplets
- Mise en place d'un vrai backlog produit
- Optimisation continue et stabilité sur le long terme

---

## Checklist de validation finale

Avant de considérer le projet comme “propre et prêt”, vérifier que :
- [ ] l'authentification est stable et centralisée
- [ ] les écrans lourds ont été refactorisés
- [ ] les listeners realtime ne se dupliquent pas
- [ ] les erreurs sont gérées proprement
- [ ] les tests critiques passent
- [ ] les logs de debug sont retirés
- [ ] les fonctionnalités clés ont été testées manuellement
- [ ] la structure du projet est lisible et maintenable
- [ ] le backlog produit est clair
- [ ] les données sensibles et l'accès Supabase sont sécurisés

---

## Conclusion
Le projet a une bonne base technique et une vision claire, mais il doit maintenant passer du statut “MVP intéressant” au statut “application stable et maintenable”. La priorité absolue est de clarifier la structure du code, centraliser l’auth et les flux temps réel, puis de sécuriser les tests et la QA.

Ce document doit servir de base de suivi. À chaque étape, on pourra cocher les tâches terminées et mettre à jour la roadmap au fur et à mesure.
