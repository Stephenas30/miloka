# Configuration Supabase - Guide Complet

## 🔧 Étapes de Configuration

### 1. **Tables Supabase à Créer**

**Table `users`** - Pour stocker les profils utilisateurs :
```sql
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  username TEXT UNIQUE,
  coins INTEGER NOT NULL DEFAULT 0,
  is_connected BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Ajouter des permissions RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Permettre aux utilisateurs de lire leur propre profil
CREATE POLICY "Users can read their own profile"
  ON users FOR SELECT
  USING (auth.uid() = id);

-- Permettre aux utilisateurs de mettre à jour leur profil
CREATE POLICY "Users can update their own profile"
  ON users FOR UPDATE
  USING (auth.uid() = id);

-- Permettre aux utilisateurs de créer leur profil
CREATE POLICY "Users can create their profile"
  ON users FOR INSERT
  WITH CHECK (auth.uid() = id);
```

---

### 2. **Créer le bucket d’avatars**

Dans le dashboard Supabase, va dans Storage puis crée un bucket nommé `avatars` avec accès public.

Ensuite exécute ce SQL pour autoriser les uploads depuis l’app :
```sql
create policy "Allow public read access"
on storage.objects for select
using (bucket_id = 'avatars');

create policy "Allow authenticated uploads"
on storage.objects for insert
with check (bucket_id = 'avatars' and auth.uid() is not null);

create policy "Allow authenticated updates"
on storage.objects for update
using (bucket_id = 'avatars' and auth.uid() is not null);
```

---

### 3. **Configuration Google OAuth dans Supabase**

1. Accède à [Google Cloud Console](https://console.cloud.google.com/)
2. Crée un nouveau projet ou sélectionne un existant
3. Active **Google+ API**
4. Crée des **Identifiants OAuth 2.0** :
   - Type : **Application web**
   - URIs autorisés :
     ```
     https://ttbhevnvmmizkiuwvvcf.supabase.co/auth/v1/callback
     http://localhost:3000/auth/v1/callback
     ```
   - Origines autorisées :
     ```
     https://ttbhevnvmmizkiuwvvcf.supabase.co
     http://localhost:3000
     ```

5. Copie le **Client ID** et **Client Secret**

6. Dans Supabase Dashboard → **Authentication** → **Providers** → **Google** :
   - Colle le **Client ID**
   - Colle le **Client Secret**
   - Active le provider
   - Sauvegarde

---

### 3. **Configuration Android (Google Sign-In)**

Ajoute à `android/app/build.gradle` :
```gradle
dependencies {
    // ... autres dépendances
    implementation 'com.google.android.gms:play-services-auth:21.0.0'
}
```

Crée/Mets à jour `android/app/src/main/AndroidManifest.xml` :
```xml
<manifest ...>
    <uses-permission android:name="android.permission.INTERNET" />
    
    <application ...>
        <!-- ... autres configuration -->
    </application>
</manifest>
```

**Obtenir le SHA-1 Fingerprint** (nécessaire pour Google OAuth) :
```bash
./gradlew signingReport
# ou sur Windows
gradlew.bat signingReport
```

Ajoute à [Google Cloud Console](https://console.cloud.google.com/) :
1. **Credentials** → Sélectionne ta clé OAuth Web
2. **Authorized JavaScript origins** → Ajoute :
   ```
   https://ttbhevnvmmizkiuwvvcf.supabase.co
   ```

---

### 4. **Configuration iOS (Google Sign-In)**

Ajoute à `ios/Podfile` :
```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
```

Crée/Mets à jour `ios/Runner/Info.plist` :
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.YOUR_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

Remplace `YOUR_CLIENT_ID` par l'ID de la console Google.

---

### 5. **Dépendances Flutter Ajoutées**

✅ `supabase_flutter: ^2.15.4`
✅ `google_sign_in: ^6.2.1`
✅ `provider: ^6.1.2`

---

### 6. **Fichiers Créés/Modifiés**

#### Créés :
- `lib/service/supabase_service.dart` - Gestion Supabase
- `lib/providers/auth_provider.dart` - Provider authentification
- `lib/screens/register_screen.dart` - Écran d'inscription (template)

#### Modifiés :
- `lib/main.dart` - Initialisation Supabase + Provider
- `lib/screens/login_screen.dart` - Connexion Google
- `pubspec.yaml` - Ajout dépendances

---

### 7. **Configuration de l'App (Identifiants)**

Tes identifiants sont déjà configurés dans `lib/service/supabase_service.dart` :
```dart
url: 'https://ttbhevnvmmizkiuwvvcf.supabase.co',
anonKey: 'sb_publishable_Bjf9EbegNic7EV4gY6Efpg_WEOZiRoh',
```

---

### 8. **Prochaines Étapes**

1. **Crée la table `users` dans Supabase** (SQL ci-dessus)
2. **Configure Google OAuth** (étapes 2-4)
3. **Exécute** :
   ```bash
   flutter pub get
   flutter run
   ```
4. **Teste la connexion Google**

---

### 9. **Dépannage**

**Erreur: "Google Sign-In annulé"**
→ Vérifie que Google OAuth est correctement configuré

**Erreur: "Token introuvable"**
→ Vérifie les paramètres Google Cloud Console

**Erreur: "Table users introuvable"**
→ Crée la table avec le SQL fourni plus haut

---

### 10. **Structure des Données Supabase**

**Table `users`** :
```
id (UUID, PK)
email (TEXT, UNIQUE)
full_name (TEXT)
avatar_url (TEXT)
username (TEXT)
coins (INTEGER, DEFAULT 0)
is_connected (BOOLEAN, DEFAULT false)
created_at (TIMESTAMP)
updated_at (TIMESTAMP)
```

**Table `amis`** (amis / demandes d'ami) :
```sql
CREATE TABLE amis (
  id_user UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id_ami UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending',  -- 'pending' ou 'accepted'
  send_partie TEXT DEFAULT NULL,           -- état des invitations de jeu
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  PRIMARY KEY (id_user, id_ami)
);
```

---

### 11. **Migration : Ajout de la colonne `status` (juillet 2026)**

Si la table `amis` existe déjà sans la colonne `status`, exécute cette commande SQL dans l'éditeur SQL de Supabase :

```sql
-- 1. Ajouter la colonne (sans default pour que les lignes existantes soient NULL)
ALTER TABLE amis ADD COLUMN status TEXT;

-- 2. Les amitiés mutuelles (deux lignes réciproques) → 'accepted'
UPDATE amis SET status = 'accepted'
WHERE (id_user, id_ami) IN (
    SELECT a.id_user, a.id_ami FROM amis a
    INNER JOIN amis b ON a.id_user = b.id_ami AND a.id_ami = b.id_user
);

-- 3. Les demandes unidirectionnelles (pas encore acceptées) → 'pending'
UPDATE amis SET status = 'pending' WHERE status IS NULL;

-- 4. Rendre la colonne obligatoire avec une valeur par défaut
ALTER TABLE amis ALTER COLUMN status SET NOT NULL;
ALTER TABLE amis ALTER COLUMN status SET DEFAULT 'pending';
```

---

**C'est prêt ! 🎉**
