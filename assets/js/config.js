const SUPABASE_URL = "https://hanbgkefeqgstnsaapel.supabase.co";

const SUPABASE_PUBLISHABLE_KEY =
  "sb_publishable_aRnT7C8H3EOayqPH3DMxQg_evP1QreW";

const FUNCTIONS_URL = `${SUPABASE_URL}/functions/v1`;

// Identifiant public OneSignal (Dashboard OneSignal > Settings > Keys & IDs).
// Non sensible : à ne pas confondre avec la clé REST API OneSignal, qui reste
// exclusivement dans les secrets Supabase Edge Functions côté serveur.
// Laisser vide tant que le canal Push n'est pas configuré : le frontend
// affiche alors proprement "indisponible" au lieu d'échouer silencieusement.
const ONESIGNAL_APP_ID = "";