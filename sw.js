// Importe le SDK OneSignal dans CE service worker plutôt que de laisser
// OneSignalSDKWorker.js s'enregistrer séparément : deux service workers
// ne peuvent pas contrôler la même scope (site root) sans que le second
// enregistrement n'écrase le premier. C'est le pattern d'intégration
// recommandé par OneSignal pour un site ayant déjà son propre service
// worker. Sans danger tant que ONESIGNAL_APP_ID est vide (assets/js/config.js) :
// OneSignal.init() n'est alors jamais appelé (voir espace-proprietaire.html,
// initOneSignal()), donc ce SDK reste inerte.
importScripts(
  "https://cdn.onesignal.com/sdks/web/v16/OneSignalSDKWorker.js",
);

// Service worker minimal — App Shell public uniquement.
//
// Ne met JAMAIS en cache :
//   - tout ce qui n'est pas same-origin (Supabase API/Auth/Storage,
//     Edge Functions, OneSignal, WhatsApp gateway) ;
//   - les pages privées (admin.html, admin-login.html,
//     espace-proprietaire.html) puisqu'elles dépendent d'une session
//     Supabase vivante et peuvent afficher des données personnelles ;
//   - toute requête qui n'est pas un GET.
//
// Stratégie :
//   - pages HTML publiques : "network-first" (le réseau fait toujours
//     foi quand il est disponible, donc collecte.html ne peut jamais
//     rester bloqué sur une ancienne version pendant des semaines ;
//     le cache ne sert que de repli hors-ligne) ;
//   - CSS/JS/icônes : "stale-while-revalidate" (réponse immédiate
//     depuis le cache si présente, mise à jour silencieuse en fond).
//
// Versionnement : changer CACHE_VERSION invalide et remplace tout
// l'ancien cache au prochain déploiement (voir activate ci-dessous).

const CACHE_VERSION = "v1";
const CACHE_NAME = `mirador-golf-static-${CACHE_VERSION}`;

const PRECACHE_URLS = [
  "./index.html",
  "./collecte.html",
  "./confirmation.html",
  "./confidentialite.html",
  "./connexion.html",
  "./inscription.html",
  "./manifest.webmanifest",
  "./assets/css/style.css",
  "./assets/css/form.css",
  "./assets/css/app.css",
  "./assets/js/config.js",
  "./assets/js/supabase-client.js",
  "./assets/js/validation.js",
  "./assets/js/inscription.js",
  "./assets/icons/icon-192.png",
  "./assets/icons/icon-512.png",
];

const PRIVATE_PAGE_RE = /\/(admin|admin-login|espace-proprietaire)\.html$/;

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE_URLS))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) =>
        Promise.all(
          names
            .filter(
              (name) =>
                name.startsWith("mirador-golf-static-") &&
                name !== CACHE_NAME,
            )
            .map((name) => caches.delete(name)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;

  if (request.method !== "GET") {
    return;
  }

  const url = new URL(request.url);

  // Jamais d'interception cross-origin (Supabase, OneSignal, etc.) :
  // on laisse le navigateur gérer la requête normalement.
  if (url.origin !== self.location.origin) {
    return;
  }

  // Jamais de cache pour les pages privées / authentifiées.
  if (PRIVATE_PAGE_RE.test(url.pathname)) {
    return;
  }

  const isNavigation =
    request.mode === "navigate" || request.destination === "document";

  if (isNavigation) {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
          return response;
        })
        .catch(() => caches.match(request)),
    );
    return;
  }

  if (["style", "script", "image", "font"].includes(request.destination)) {
    event.respondWith(
      caches.match(request).then((cached) => {
        const network = fetch(request)
          .then((response) => {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
            return response;
          })
          .catch(() => cached);

        return cached || network;
      }),
    );
  }
});
