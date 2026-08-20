# Sécurité — Espace Propriétaires Mirador Golf 1

Ce document reflète l'état réel du code au 2026-08-19, tel que vérifié par lecture complète des migrations SQL, des Edge Functions et du frontend (pas un plan théorique). Aucun secret n'est présent dans ce document ni dans le dépôt.

## Modèle d'authentification

- Deux populations distinctes, toutes deux authentifiées par Supabase Auth réel (`auth.users`), jamais par un rôle que le client peut s'attribuer :
  - **Propriétaires** : liés via `owner_accounts.auth_user_id`. Connexion par téléphone + mot de passe (email interne synthétique dérivé du numéro, jamais un vrai email de contact).
  - **Admins** : liés via `admin_users.auth_user_id`, connexion email + mot de passe classique.
- Les deux sessions sont isolées dans le navigateur via deux `storageKey` Supabase distincts (`assets/js/supabase-client.js`), sur la base du nom de fichier (`admin.html` / `admin-login.html`).
- L'activation d'un compte propriétaire se fait par code à usage unique, haché (HMAC-SHA256 avec pepper serveur) avant stockage — le code en clair n'est jamais persisté. Expiration et usage unique appliqués côté serveur, verrouillage de ligne (`for update`) pour empêcher une double activation concurrente.

## Autorisation

- `is_admin()` est l'unique source de vérité pour les droits admin, dérivée uniquement de la table `admin_users` (aucune écriture possible par un client authentifié — seul `service_role` peut modifier cette table).
- Chaque politique RLS et chaque RPC réservés à l'admin appellent explicitly `is_admin()` côté serveur. Le contrôle côté interface (`admin.html`) n'est qu'un confort UX ; la vraie barrière est en base.
- Aucune RPC propriétaire n'accepte d'identifiant de propriétaire fourni par le client à des fins d'autorisation — l'identité est systématiquement dérivée de `auth.uid()` côté serveur.

## Isolation des données propriétaires

Vérifiée table par table (comptes, lots, réunions, votes, syndic, annonces, documents, notifications, préférences) : aucune politique RLS `using (true)` n'existe pour le rôle `authenticated`, et chaque politique scope explicitement sur `owner_accounts.auth_user_id = auth.uid()`. Aucun chemin IDOR trouvé lors de l'audit.

Les documents privés sont protégés à deux niveaux : la table de métadonnées ET le bucket Storage lui-même (`storage.objects`), donc même une URL de fichier devinée reste bloquée par RLS si le document n'est pas ciblé au propriétaire.

## Fonctions `security definer`

Toutes les fonctions `security definer` du projet fixent `set search_path = ''`, sans exception — protection systématique contre l'injection de search_path. Les RPC réservées au worker (`service_*`) vérifient en plus explicitement `auth.role() = 'service_role'` en début de fonction.

## Edge Functions

Chaque fonction a un mode d'authentification adapté à son usage :

- `admin-generate-owner-code` : JWT vérifié + re-vérification du statut admin côté serveur.
- `activate-owner-account` : accessible sans session (nécessaire pour créer un compte) mais protégée par la clé d'activation hachée.
- `process-notification-deliveries` : protégée par un secret partagé (`x-worker-secret`), appelée uniquement par le cron interne — jamais exposée publiquement de fait.
- `submit-registration` / `validate-access-code` : accessibles sans session par conception, mais dépendent d'un flux (`registration_sessions`) actuellement non alimenté par aucune fonction du dépôt — voir « Limites connues » ci-dessous.

## XSS / injection

Toute donnée issue de la base insérée dans `innerHTML` (propriétaires, réunions, votes, syndic, annonces, documents, notifications) passe systématiquement par un helper `escapeHtml()`. Aucune interpolation non échappée trouvée dans `admin.html` ni `espace-proprietaire.html`. Aucun accès base de données par concaténation SQL brute — tout passe par le client Supabase paramétré ou des fonctions PL/pgSQL à paramètres nommés.

## Limites connues (P3 — pas de blocage)

- `validate-access-code`, `submit-registration` et les tables `access_codes`/`registration_sessions`/`owners`/`apartments` forment un flux d'inscription antérieur, remplacé depuis par `owner_submissions` → `owner_accounts`. Ces tables n'ont aucune politique RLS ni grant vers `anon`/`authenticated` — elles sont inertes, pas exploitables, mais constituent du code mort à clarifier.
- Aucune limitation de débit applicative dédiée sur la rédemption de code d'activation au-delà de l'entropie du code lui-même (~50 bits).
- `notification_deliveries` (contient des destinataires email/téléphone) n'a pas de politique RLS explicite pour les propriétaires — l'isolation vient de l'absence de politique (RLS refuse par défaut), ce qui est correct aujourd'hui mais plus fragile qu'un filtre explicite si une future migration ajoutait par erreur une politique trop permissive.
- `assets/js/supabase-client.js` isole les sessions en comparant le nom de fichier exact (`admin.html`/`admin-login.html`) ; les fichiers vides `admin/dashboard.html` et `admin/login.html` (non utilisés, non reliés) tomberaient sur la mauvaise storageKey s'ils étaient un jour remplis sans corriger cette vérification.

## Gestion des secrets

Tous les secrets serveur (Brevo, OneSignal REST, clé du gateway WhatsApp, `service_role`, pepper d'activation) sont lus exclusivement via variables d'environnement (`Deno.env.get(...)` / `process.env.*`), jamais codés en dur. Le seul secret local (`services/whatsapp-gateway/.env`) est correctement exclu par `.gitignore` et n'a jamais été commité. Les clés publiques Supabase (`sb_publishable_...`) et l'App ID OneSignal sont volontairement publiques par conception — elles ne protègent rien à elles seules, la protection réelle est RLS/RPC côté serveur.
