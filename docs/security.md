# Sécurité — Espace Propriétaires Mirador Golf 1

Ce document reflète l'état réel du code au 2026-08-20 (Sprint 1 — UI Foundation + Frontend Security Hardening), tel que vérifié par lecture complète des migrations SQL, des Edge Functions et du frontend (pas un plan théorique). Aucun secret n'est présent dans ce document ni dans le dépôt.

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

Re-vérifié intégralement pendant le Sprint 1 (28+21 = 50 sites `.innerHTML =` dans `admin.html`/`espace-proprietaire.html`, un par un) : `escapeHtml()` échappe en fait les 5 caractères `& < > " '` (pas seulement `& < >`), donc protège aussi les interpolations en contexte d'attribut (`title="${escapeHtml(x)}"`), pas seulement en contexte texte. Zéro `outerHTML`/`insertAdjacentHTML`/`document.write` dans ces deux fichiers. Les rares interpolations non passées par `escapeHtml()` sont soit des littéraux fixes, soit des valeurs numériques déjà bornées (`Math.max(0, Math.min(100, ...))` pour les barres de résultat de vote), soit le résultat d'un `switch`/table de correspondance sur un ensemble fixe de statuts connus (jamais la donnée brute elle-même) — vérifié fonction par fonction, pas supposé.

## Autorisation frontend — vérifié en second passage (Sprint 1)

Rappel : le frontend n'est jamais la barrière de sécurité réelle (voir « Autorisation » plus haut — RLS/RPC `security definer` font foi). Ce qui suit vérifie que le frontend échoue *fermé* (fail-closed) quand même, pour l'UX et en défense en profondeur :

- `admin.html` : `requireAdmin()` — pas de session → redirection `admin-login.html` ; session présente mais absente d'`admin_users`/`is_active = false`/erreur → `signOut()` puis redirection. Le premier chargement de données (`loadOwners()`) appelle `await requireAdmin()` et retourne avant toute requête Supabase si `null` — aucune donnée ne peut atteindre le DOM avant que la vérification admin ait réussi, puisque le rendu est uniquement le résultat de cette même requête gardée.
- `espace-proprietaire.html` : `loadOwnerSpace()` distingue explicitement trois cas — pas de session → redirection `connexion.html` ; **erreur réseau/Supabase pendant la lecture de session → aucun accès accordé, mais aucune déconnexion non plus** (message d'erreur affiché, la session existante n'est pas détruite par une simple coupure réseau) ; compte propriétaire introuvable ou `status !== "active"` → `signOut({scope:"local"})` puis redirection. Conforme à l'exigence « erreur réseau pendant auth ⇒ pas d'accès accordé par défaut ».
- Déconnexion (`espace-proprietaire.html`) : désactive le bouton, appelle `OneSignal.logout()` (évite qu'une notification push parte vers le mauvais compte après déconnexion) puis `supabaseClient.auth.signOut({scope:"local"})`. L'application n'étant pas une SPA, chaque page est un rechargement complet : aucun état JS d'un utilisateur précédent ne peut survivre visuellement à une navigation vers `connexion.html`/`admin-login.html`.
- Aucun `localStorage` référencé directement par le code applicatif (seul le SDK Supabase l'utilise en interne via `storageKey`, un par contexte admin/propriétaire — voir plus haut). `sessionStorage` n'est utilisé que par le flux d'inscription pré-compte (`access.js`/`inscription.js`) pour un jeton de session temporaire, un numéro de lot et une expiration — jamais un mot de passe, toujours effacé après usage ou expiration.
- Seul usage de paramètre d'URL dans tout le frontend : `?section=` lu par `espace-proprietaire.html` (`requestedOwnerSection()`), validé contre une liste blanche de sections connues avant utilisation — pas de redirection ouverte, pas d'injection possible via ce paramètre.

## Content Security Policy (Sprint 1)

Chaque page HTML porte désormais un `<meta http-equiv="Content-Security-Policy-Report-Only">` adapté aux ressources qu'elle charge réellement (audité fichier par fichier : scripts externes, connexions réseau, présence de `<script>` inline). Volontairement en **Report-Only**, pas en mode bloquant :

- Ce sprint n'avait accès à aucun navigateur automatisé pour vérifier qu'une politique bloquante ne casse rien (voir « Tests navigateur non exécutés » dans le rapport de sprint). Une politique bloquante mal calibrée sur `admin.html`/`espace-proprietaire.html` (ex. un hôte de script oublié) romprait silencieusement la connexion pour tous les utilisateurs — un risque jugé disproportionné sans moyen de le vérifier avant mise en ligne.
- Report-Only ne bloque jamais rien ; les violations restent visibles dans la console DevTools. Passage en mode bloquant recommandé : ouvrir chaque page dans un vrai navigateur, confirmer zéro violation en console, puis remplacer `Content-Security-Policy-Report-Only` par `Content-Security-Policy` (un seul mot par page).

Politique cible par famille de page (allowlist minimale observée) :

| Page(s) | `script-src` | `connect-src` en plus de `'self'` |
|---|---|---|
| `index.html`, `confidentialite.html`, `confirmation.html` | `'self'` (zéro `<script>` sur ces pages) | — |
| `inscription.html` | `'self'` (scripts externes uniquement) | Supabase |
| `collecte.html` | `'self' 'unsafe-inline'` | Supabase |
| `admin-login.html`, `connexion.html`, `admin.html` | `'self' https://cdn.jsdelivr.net 'unsafe-inline'` | Supabase |
| `espace-proprietaire.html` | + `https://cdn.onesignal.com` | + OneSignal |

`'unsafe-inline'` reste nécessaire pour `script-src`/`style-src` sur les pages à logique inline (`admin.html`, `espace-proprietaire.html`, `connexion.html`, `admin-login.html`, `collecte.html` : c'est là que vit l'essentiel de l'application, voir « Frontend » dans `docs/architecture.md`) — ni nonce (nécessiterait un serveur générant une valeur par requête, incompatible avec un hébergement statique GitHub Pages) ni hash (trop fragile : casserait à chaque modification du bloc inline) n'est réaliste ici sans une extraction complète de ces fichiers vers des `.js` externes, un chantier hors du périmètre de ce sprint (risque de régression disproportionné pour un gain de durcissement marginal tant que `escapeHtml()` reste appliqué partout — voir ci-dessus).

`frame-ancestors` (protection anti-clickjacking) n'est **pas** dans ces balises meta : cette directive n'est honorée par les navigateurs que via un en-tête HTTP réel, jamais via `<meta http-equiv>`. GitHub Pages (hébergement statique) ne permet pas d'ajouter d'en-têtes HTTP personnalisés sans infrastructure supplémentaire (proxy, Cloudflare Worker, etc.) — documenté ici comme limite d'hébergement, pas comme oubli. Un `X-Frame-Options` aurait la même limite. Recommandation de suite : si le clickjacking devient une préoccupation concrète, migrer vers un hébergeur/CDN capable d'en-têtes personnalisés.

Hôtes externes utilisés par le frontend (exhaustif, vérifié par recherche répertoire entier) : `cdn.jsdelivr.net` (SDK `@supabase/supabase-js@2`, non figé à une version exacte — `integrity` (SRI) non ajouté pour cette raison : figer une version exacte casserait la mise à jour automatique des correctifs, et un hash SRI sur une balise `@2` flottante casserait le chargement du script à la prochaine publication de patch par jsdelivr ; figer une version précise avant d'ajouter SRI est une amélioration de sécurité légitime mais un changement de dépendance à part entière, non fait ce sprint sans moyen de vérifier son comportement en navigateur réel), `hanbgkefeqgstnsaapel.supabase.co` (Auth/Postgres/Storage/Functions), `cdn.onesignal.com` (SDK push, `espace-proprietaire.html` uniquement).

## Feedback d'erreur d'authentification

`admin-login.html` et `connexion.html` (formulaire de connexion) affichaient auparavant `error.message` brut renvoyé par le SDK Supabase Auth pour tout cas autre que l'exact message `"Invalid login credentials"` — un message provider (limite de débit, texte interne, etc.) aurait pu s'afficher tel quel à l'utilisateur. Corrigé : une liste blanche d'issues connues est mappée vers un message français sûr ; tout le reste tombe sur un message générique unique. Le message personnalisé « ce compte n'est pas autorisé à accéder à l'administration » (admin) et « impossible de créer la session » (propriétaire) restent affichés tels quels — ce sont des messages applicatifs déjà rédigés pour l'utilisateur final, marqués explicitement comme sûrs plutôt que filtrés par erreur. Le flux d'activation de compte (`connexion.html`) affiche déjà uniquement des messages provenant de l'Edge Function `activate-owner-account`, qui ne renvoie que des chaînes françaises rédigées à la main (`jsonError(...)` avec des littéraux fixes, jamais une erreur brute) — vérifié dans `supabase/functions/activate-owner-account/index.ts`, aucun changement nécessaire de ce côté.

## Limites connues (P3 — pas de blocage)

- `validate-access-code`, `submit-registration` et les tables `access_codes`/`registration_sessions`/`owners`/`apartments` forment un flux d'inscription antérieur, remplacé depuis par `owner_submissions` → `owner_accounts`. Ces tables n'ont aucune politique RLS ni grant vers `anon`/`authenticated` — elles sont inertes, pas exploitables, mais constituent du code mort à clarifier.
- Aucune limitation de débit applicative dédiée sur la rédemption de code d'activation au-delà de l'entropie du code lui-même (~50 bits).
- `notification_deliveries` (contient des destinataires email/téléphone) n'a pas de politique RLS explicite pour les propriétaires — l'isolation vient de l'absence de politique (RLS refuse par défaut), ce qui est correct aujourd'hui mais plus fragile qu'un filtre explicite si une future migration ajoutait par erreur une politique trop permissive.
- `assets/js/supabase-client.js` isole les sessions en comparant le nom de fichier exact (`admin.html`/`admin-login.html`) ; les fichiers vides `admin/dashboard.html` et `admin/login.html` (non utilisés, non reliés) tomberaient sur la mauvaise storageKey s'ils étaient un jour remplis sans corriger cette vérification.

## Gestion des secrets

Tous les secrets serveur (Brevo, OneSignal REST, clé du gateway WhatsApp, `service_role`, pepper d'activation) sont lus exclusivement via variables d'environnement (`Deno.env.get(...)` / `process.env.*`), jamais codés en dur. Le seul secret local (`services/whatsapp-gateway/.env`) est correctement exclu par `.gitignore` et n'a jamais été commité. Les clés publiques Supabase (`sb_publishable_...`) et l'App ID OneSignal sont volontairement publiques par conception — elles ne protègent rien à elles seules, la protection réelle est RLS/RPC côté serveur.
