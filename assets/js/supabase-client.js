(() => {
  const path =
    window.location.pathname
      .toLowerCase();
  const isAdminContext =
    path.endsWith(
      "/admin.html"
    ) ||
    path.endsWith(
      "/admin-login.html"
    );
  const authStorageKey =
    isAdminContext
      ? "mirador-golf-admin-auth-v2"
      : "mirador-golf-owner-auth-v2";
  const client =
    window.supabase.createClient(
      SUPABASE_URL,
      SUPABASE_PUBLISHABLE_KEY,
      {
        auth: {
          storageKey:
            authStorageKey,
          persistSession:
            true,
          autoRefreshToken:
            true,
          detectSessionInUrl:
            true,
        },
      }
    );
  window.supabaseClient =
    client;
})();
