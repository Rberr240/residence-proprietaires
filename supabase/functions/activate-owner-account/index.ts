import { withSupabase } from "npm:@supabase/server@^1";

import type { Database } from "../_shared/database.types.ts";

function normalizeActivationCode(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.trim().toUpperCase().replace(/\s+/g, "");
}

function normalizeMoroccoPhone(value: string): string | null {
  let digits = value.replace(/\D/g, "");

  if (digits.startsWith("00")) digits = digits.slice(2);

  if (
    digits.startsWith("212") &&
    digits.length === 12 &&
    (digits.startsWith("2126") || digits.startsWith("2127"))
  ) {
    return `+${digits}`;
  }

  if (
    digits.length === 10 &&
    (digits.startsWith("06") || digits.startsWith("07"))
  ) {
    return `+212${digits.slice(1)}`;
  }

  if (
    digits.length === 9 &&
    (digits.startsWith("6") || digits.startsWith("7"))
  ) {
    return `+212${digits}`;
  }

  return null;
}

async function hmacSha256(value: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(value),
  );

  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );

  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function buildInternalLoginEmail(phoneE164: string): Promise<string> {
  const digest = await sha256Hex(`mirador-golf-1:${phoneE164}`);
  return `owner-${digest.slice(0, 40)}@auth.mirador-golf.invalid`;
}

function jsonError(message: string, status = 400): Response {
  return Response.json(
    { success: false, message },
    { status },
  );
}

export default {
  fetch: withSupabase<Database>(
    { auth: "publishable" },
    async (req, ctx) => {
      let createdAuthUserId: string | null = null;

      try {
        if (req.method !== "POST") {
          return jsonError("Méthode non autorisée.", 405);
        }

        let body: {
          activationCode?: unknown;
          password?: unknown;
        };

        try {
          body = await req.json();
        } catch {
          return jsonError("Requête invalide.", 400);
        }

        const activationCode = normalizeActivationCode(body?.activationCode);

        const password = typeof body?.password === "string"
          ? body.password
          : "";

        if (
          activationCode.length < 10 ||
          activationCode.length > 40 ||
          !activationCode.startsWith("MG-")
        ) {
          return jsonError("Code d'activation invalide.");
        }

        if (password.length < 8) {
          return jsonError(
            "Le mot de passe doit contenir au moins 8 caractères.",
          );
        }

        if (password.length > 72) {
          return jsonError("Le mot de passe est trop long.");
        }

        if (!/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) {
          return jsonError(
            "Le mot de passe doit contenir au moins une lettre et un chiffre.",
          );
        }

        const pepper = Deno.env.get("OWNER_ACTIVATION_CODE_PEPPER");

        if (!pepper) {
          console.error("OWNER_ACTIVATION_CODE_PEPPER missing");
          return jsonError("Configuration serveur incomplète.", 500);
        }

        const codeHash = await hmacSha256(
          activationCode,
          pepper,
        );

        const {
          data: code,
          error: codeError,
        } = await ctx.supabaseAdmin
          .from("owner_activation_codes")
          .select(
            `
            id,
            owner_account_id,
            expires_at,
            used_at,
            revoked_at
            `,
          )
          .eq("code_hash", codeHash)
          .maybeSingle();

        if (codeError || !code) {
          if (codeError) {
            console.error(
              "Activation code lookup failed:",
              codeError.message,
            );
          }

          return jsonError("Code d'activation invalide.", 401);
        }

        if (code.revoked_at) {
          return jsonError(
            "Ce code d'activation a été révoqué.",
            401,
          );
        }

        if (code.used_at) {
          return jsonError(
            "Ce code d'activation a déjà été utilisé.",
            401,
          );
        }

        if (new Date(code.expires_at).getTime() <= Date.now()) {
          return jsonError(
            "Ce code d'activation a expiré.",
            401,
          );
        }

        const {
          data: owner,
          error: ownerError,
        } = await ctx.supabaseAdmin
          .from("owner_accounts")
          .select(
            `
            id,
            auth_user_id,
            first_name,
            last_name,
            phone,
            whatsapp,
            status
            `,
          )
          .eq("id", code.owner_account_id)
          .maybeSingle();

        if (ownerError || !owner) {
          if (ownerError) {
            console.error("Owner lookup failed:", ownerError.message);
          }

          return jsonError(
            "Compte propriétaire introuvable.",
            404,
          );
        }

        if (owner.status === "active" || owner.auth_user_id) {
          return jsonError(
            "Ce compte propriétaire est déjà activé. Utilisez la page de connexion.",
            409,
          );
        }

        const phoneE164 = normalizeMoroccoPhone(owner.phone);

        if (!phoneE164) {
          console.error("Invalid owner phone:", owner.id);

          return jsonError(
            "Le numéro de téléphone associé à ce propriétaire est invalide. Contactez l'administration.",
            400,
          );
        }

        const loginEmail = await buildInternalLoginEmail(phoneE164);

        const {
          data: authData,
          error: authError,
        } = await ctx.supabaseAdmin
          .auth
          .admin
          .createUser({
            email: loginEmail,
            password,
            email_confirm: true,
            user_metadata: {
              owner_account_id: owner.id,
              first_name: owner.first_name,
              last_name: owner.last_name,
              phone_e164: phoneE164,
            },
          });

        if (authError || !authData.user) {
          console.error(
            "Auth user creation failed:",
            authError?.message,
          );

          const authMessage = authError?.message?.toLowerCase() || "";

          const duplicate = authMessage.includes("already") ||
            authMessage.includes("registered") ||
            authMessage.includes("exists");

          return jsonError(
            duplicate
              ? "Un compte existe déjà avec ce numéro de téléphone. Contactez l'administration."
              : "Impossible de créer le compte propriétaire.",
            duplicate ? 409 : 500,
          );
        }

        createdAuthUserId = authData.user.id;

        const {
          data: activationResult,
          error: activationError,
        } = await ctx.supabaseAdmin
          .rpc(
            "complete_owner_activation",
            {
              p_owner_account_id: owner.id,
              p_activation_code_id: code.id,
              p_auth_user_id: authData.user.id,
              p_phone_e164: phoneE164,
            },
          );

        if (activationError) {
          console.error(
            "Activation RPC failed:",
            activationError.message,
          );

          try {
            await ctx.supabaseAdmin
              .auth
              .admin
              .deleteUser(authData.user.id);
          } catch (cleanupError) {
            console.error(
              "Auth cleanup failed:",
              cleanupError,
            );
          }

          createdAuthUserId = null;

          return jsonError(
            activationError.message ||
              "Impossible de finaliser l'activation.",
            400,
          );
        }

        createdAuthUserId = null;

        return Response.json(
          {
            success: true,
            message: "Compte activé avec succès.",

            /*
             * Identifiant technique Supabase Auth.
             * Le frontend l'utilise sans l'afficher.
             */
            loginEmail,

            phone: phoneE164,

            owner: {
              firstName: owner.first_name,
              lastName: owner.last_name,
            },

            activation: activationResult,
          },
          { status: 200 },
        );
      } catch (error) {
        console.error(
          "activate-owner-account:",
          error,
        );

        if (createdAuthUserId) {
          try {
            await ctx.supabaseAdmin
              .auth
              .admin
              .deleteUser(createdAuthUserId);
          } catch (cleanupError) {
            console.error(
              "Emergency cleanup failed:",
              cleanupError,
            );
          }
        }

        return jsonError(
          "Erreur interne lors de l'activation du compte.",
          500,
        );
      }
    },
  ),
};
