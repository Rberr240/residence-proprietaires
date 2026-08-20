# Architecture — Espace Propriétaires Mirador Golf 1

Ce document décrit l'architecture réelle du dépôt telle qu'implémentée dans le code (source de vérité), pas un plan théorique.

## Vue d'ensemble

```
Frontend statique (HTML/CSS/JS vanilla)
   │  déployé sur GitHub Pages, sous /residence-proprietaires/
   ↓
Supabase Auth (deux sessions isolées : propriétaire / admin)
   ↓
Postgres (RLS + RPC "security definer")
   ↓
Triggers métier (réunions, votes, syndic, annonces, documents)
   ↓
notification_events → owner_notifications → notification_deliveries
   ↓
Edge Function process-notification-deliveries (cron, 1x/min)
   ├── Email      → Brevo (API transactionnelle)
   ├── WhatsApp   → gateway Baileys auto-hébergé (services/whatsapp-gateway)
   └── Push Web   → OneSignal (External ID = owner_account_id)
```

Il n'y a pas de serveur d'application : toute la logique métier vit dans Postgres (fonctions `security definer`, triggers, RLS) ou dans les Edge Functions Deno. Le frontend n'est qu'un client de l'API Supabase.

## Frontend

- HTML/CSS/JavaScript vanilla, sans framework ni bundler.
- Pages principales à la racine : `index.html`, `inscription.html`, `collecte.html`, `confirmation.html`, `connexion.html`, `confidentialite.html`, `espace-proprietaire.html`, `admin-login.html`, `admin.html`, `admin/login.html`, `admin/dashboard.html`.
- `espace-proprietaire.html` et `admin.html` concentrent l'essentiel de la logique applicative (CSS et JS inline, plusieurs milliers de lignes) : dashboard, réunions, votes, syndic, annonces, documents, notifications, préférences.
- Scripts partagés dans `assets/js/` : `config.js` (constantes publiques), `supabase-client.js` (client Supabase, storage key différent admin/propriétaire), `admin-auth.js`, `dashboard.js`, `validation.js`, `access.js`, `inscription.js`.
- Aucun processus de build : les fichiers sont servis tels quels par GitHub Pages.
- Déployé en *project site* GitHub Pages, donc sous un sous-chemin (`/residence-proprietaires/`), pas à la racine du domaine. Le code qui dépend du chemin de déploiement (ex. scope du service worker OneSignal) le calcule dynamiquement depuis `window.location.pathname` plutôt que de le coder en dur, pour rester correct en cas de changement de nom de dépôt ou d'ajout d'un domaine personnalisé.

## Authentification

- Supabase Auth, avec deux `storageKey` distincts (`mirador-golf-owner-auth-v2` / `mirador-golf-admin-auth-v2`) pour isoler les sessions propriétaire et admin dans le même navigateur (`assets/js/supabase-client.js`).
- Propriétaires : inscription publique → validation admin → génération d'un code d'activation à usage unique → activation (création du compte `auth.users` + liaison à `owner_accounts`).
- Admin : compte admin séparé, statut vérifié côté serveur via `is_admin()` (fonction SQL), jamais uniquement côté client.
- Toute autorisation sensible (isolation propriétaire, droits admin) est appliquée via RLS et des fonctions RPC `security definer`, pas seulement par l'interface.

## Base de données (Supabase Postgres)

Toutes les migrations vivent dans `supabase/migrations/`, appliquées dans l'ordre de leur horodatage. Domaines couverts :

- `owner_accounts`, `owner_account_units`, `owner_activation_codes` — comptes propriétaires et activation.
- `meetings`, `meeting_responses` (V2) — réunions et présences.
- `residence_votes`, `residence_vote_options`, `residence_vote_eligibility`, `owner_vote_ballots` — votes, avec éligibilité figée à la publication.
- `syndic_charge_calls`, `syndic_unit_charges`, `syndic_payments`, `syndic_payment_allocations` — appels de fonds et paiements.
- `residence_announcements`, `residence_announcement_targets` — annonces ciblées (tous / bâtiment / lot).
- `residence_documents`, `residence_document_targets` — documents privés, bucket Storage non public, RLS répliquée sur `storage.objects`.
- `notification_events`, `owner_notifications`, `owner_notification_preferences`, `notification_deliveries`, `notification_delivery_attempts`, `notification_provider_events` — pipeline de notifications multi-canal (voir plus bas).

Règles de convention du projet :

- Toute correction de schéma passe par une **nouvelle** migration ; les migrations déjà appliquées ne sont jamais modifiées.
- Les fonctions `security definer` fixent systématiquement `set search_path = ''` pour éviter l'injection de search_path.
- Les opérations « publier / clôturer / annuler / extourner » verrouillent la ligne concernée (`for update`) avant de vérifier et changer son état.

## Pipeline de notifications

Une notification suit toujours le même chemin :

1. Un événement métier (réunion publiée, vote publié, appel de fonds publié, annonce publiée, document publié, paiement syndic confirmé/extourné) déclenche un trigger SQL.
2. Le trigger appelle `ensure_notification_event()` (idempotent via `event_key` unique) puis insère une ligne par destinataire dans `owner_notifications`.
3. Un trigger sur `owner_notifications` (`prepare_notification_deliveries()`) crée, pour chaque canal externe activé par le propriétaire (email / whatsapp / push), une ligne dans `notification_deliveries`.
4. L'Edge Function `process-notification-deliveries` (appelée par un cron Supabase toutes les minutes) réclame un lot de livraisons en attente via `service_claim_notification_deliveries()` (`FOR UPDATE SKIP LOCKED`, sûr en cas d'invocations concurrentes), les envoie au provider correspondant, puis finalise via `service_finish_notification_delivery()`.
5. Les livraisons bloquées trop longtemps sont automatiquement remises en file par `service_requeue_stale_notification_deliveries()`.

Canaux :

- **In-app** : toujours actif pour un compte actif, table `owner_notifications` (lu/non lu, RLS par propriétaire).
- **Email** : provider Brevo, HTML échappé, destinataire = email du propriétaire.
- **WhatsApp** : gateway Baileys auto-hébergé (`services/whatsapp-gateway`), authentifié par clé API + limitation de débit (token bucket), numéro normalisé (repli whatsapp → phone_e164 → phone).
- **Push Web** : OneSignal, adressé par « External ID » = `owner_account_id` (pas de table d'abonnement locale : OneSignal est lui-même l'annuaire d'abonnements). Le contenu des notifications syndic (montants) est remplacé par un message générique pour ce canal spécifiquement, le détail restant accessible dans l'espace propriétaire authentifié.

## Gateway WhatsApp (`services/whatsapp-gateway`)

Service Node.js/Express autonome, basé sur Baileys (protocole WhatsApp Web), avec :

- authentification par clé API (comparaison en temps constant),
- limitation de débit par token bucket (60 jetons, recharge 20/min),
- reconnexion automatique,
- journalisation avec rédaction des identifiants (JID/LID/numéros) hors du logger applicatif, logger Baileys interne totalement silencieux.

Composant considéré stable (9 tests unitaires, tous verts) — ne pas le modifier sans raison directement liée à un bug qu'il cause.

## Services externes

| Service | Rôle | Où |
|---|---|---|
| Supabase | Auth, Postgres, Storage, Edge Functions, cron | Toute la base + `supabase/functions/*` |
| Brevo | Envoi d'emails transactionnels | `process-notification-deliveries` (secret serveur) |
| OneSignal | Push Web | `assets/js/config.js` (App ID public) + `process-notification-deliveries` (clé REST serveur) |
| WhatsApp (via Baileys) | Messages WhatsApp | `services/whatsapp-gateway`, appelé par `process-notification-deliveries` |
| GitHub Pages | Hébergement du frontend statique | Racine du dépôt |

## CI

`.github/workflows/ci.yml` exécute à chaque push/PR sur `app-v2`/`main` :

- les tests du gateway WhatsApp (`npm test`),
- la vérification syntaxique de tout le JavaScript (fichiers `assets/js/*.js` et blocs `<script>` inline de toutes les pages HTML suivies),
- `deno check` sur chaque Edge Function.

Aucune étape de déploiement automatique n'est incluse.
