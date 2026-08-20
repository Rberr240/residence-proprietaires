# Espace Propriétaires — Résidence Mirador Golf 1

Application web privée destinée aux propriétaires de la résidence Mirador Golf 1.

## Fonctionnalités

Espace propriétaire :

- activation de compte par code unique à usage unique ;
- consultation et mise à jour du profil et des lots associés ;
- réunions : consultation, réponse de présence, disponibilité ;
- votes : consultation, participation, résultats ;
- syndic : appels de fonds, historique des paiements ;
- annonces et documents privés ciblés (résidence / bâtiment / lot) ;
- notifications in-app, email (Brevo), WhatsApp et push web (OneSignal), avec préférences par canal.

Espace administrateur :

- gestion des propriétaires et validation des inscriptions ;
- gestion des réunions, votes, appels de fonds et paiements syndic ;
- gestion des annonces et documents ;
- statistiques de notifications.

Voir [docs/architecture.md](docs/architecture.md) pour le détail du pipeline de notifications et [docs/security.md](docs/security.md) pour le modèle de sécurité.

## Technologies

- HTML / CSS / JavaScript (sans framework ni build)
- GitHub Pages (déployé sous `/residence-proprietaires/`)
- Supabase (Auth, Postgres, RLS, Edge Functions Deno, cron)
- Brevo (email transactionnel), OneSignal (push web), gateway WhatsApp auto-hébergée (Baileys)

## Développement

Aucune étape de build n'est nécessaire pour le frontend : les fichiers HTML sont servis tels quels.

- Tests du gateway WhatsApp : `cd services/whatsapp-gateway && npm test`
- Vérification de type des Edge Functions : `deno check` dans chaque dossier `supabase/functions/*`
- CI : voir `.github/workflows/ci.yml` (tests WhatsApp, syntaxe JavaScript, `deno check`)