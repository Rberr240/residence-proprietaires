import { withSupabase } from "npm:@supabase/server@^1";

import type { Database } from "../_shared/database.types.ts";

function normalizeActivationCode(
  value: unknown,
): string {
  if (typeof value !== "string") {
    return "";
  }

  return value
    .trim()
    .toUpperCase()
    .replace(/\s+/g, "");
}

function normalizeMoroccoPhone(
  value: string,
): string | null {
  let digits = value.replace(/\D/g, "");

  if (digits.startsWith("00")) {
    digits = digits.slice(2);
  }

  /*
   * +212 6xxxxxxxx
   * 2126xxxxxxxx
   */
  if (
    digits.startsWith("212") &&
    digits.length === 12
  ) {
    return `+${digits}`;
  }

  /*
   * 06xxxxxxxx
   * 07xxxxxxxx
   */
  if (
    digits.length === 10 &&
    digits.startsWith("0")
  ) {
    return `+212${digits.slice(1)}`;
  }

  /*
   * 6xxxxxxxx
   * 7xxxxxxxx
   */
  if (
    digits.length === 9 &&
    (
      digits.startsWith("6") ||
      digits.startsWith("7")
    )
  ) {
    return `+212${digits}`;
  }

  return null;
}

async function hmacSha256(
  value: string,
  secret: string,
): Promise<string> {
  const encoder = new TextEncoder();

  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    {
      name: "HMAC",
      hash: "SHA-256",
    },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(value),
  );

  return Array
    .from(
      new Uint8Array(signature),
    )
    .map(
      (byte) =>
        byte
          .toString(16)
          .padStart(2, "0"),
    )
    .join("");
}

function jsonError(
  message: string,
  status = 400,
): Response {
  return Response.json(
    {
      success: false,
      message,
    },
    {
      status,
    },
  );
}

export default {
  fetch: withSupabase<Database>(
    {
      /*
       * Le propriétaire n'est pas encore connecté.
       * La fonction accepte donc la clé publishable
       * de notre application publique.
       */
      auth: "publishable",
    },
    async (
      req,
      ctx,
    ) => {
      let createdAuthUserId: string | null = null;

      try {
        /*
         * =========================================
         * METHOD
         * =========================================
         */

        if (req.method !== "POST") {
          return jsonError(
            "Méthode non autorisée.",
            405,
          );
        }

        /*
         * =========================================
         * BODY
         * =========================================
         */

        const body = await req.json();

        const activationCode = normalizeActivationCode(
          body?.activationCode,
        );

        const password = typeof body?.password === "string"
          ? body.password
          : "";

        /*
         * =========================================
         * VALIDATION CODE
         * =========================================
         */

        if (
          activationCode.length < 10 ||
          activationCode.length > 40
        ) {
          return jsonError(
            "Code d'activation invalide.",
          );
        }

        if (
          !activationCode.startsWith(
            "MG-",
          )
        ) {
          return jsonError(
            "Code d'activation invalide.",
          );
        }

        /*
         * =========================================
         * VALIDATION PASSWORD
         * =========================================
         */

        if (
          password.length < 8
        ) {
          return jsonError(
            "Le mot de passe doit contenir au moins 8 caractères.",
          );
        }

        if (
          password.length > 72
        ) {
          return jsonError(
            "Le mot de passe est trop long.",
          );
        }

        if (
          !/[A-Za-z]/.test(password) ||
          !/[0-9]/.test(password)
        ) {
          return jsonError(
            "Le mot de passe doit contenir au moins une lettre et un chiffre.",
          );
        }

        /*
         * =========================================
         * SERVER SECRET
         * =========================================
         */

        const pepper = Deno.env.get(
          "OWNER_ACTIVATION_CODE_PEPPER",
        );

        if (!pepper) {
          console.error(
            "OWNER_ACTIVATION_CODE_PEPPER missing",
          );

          return jsonError(
            "Configuration serveur incomplète.",
            500,
          );
        }

        /*
         * =========================================
         * HASH DU CODE
         * =========================================
         */

        const codeHash = await hmacSha256(
          activationCode,
          pepper,
        );

        /*
         * =========================================
         * RECHERCHE CODE
         * =========================================
         */

        const {
          data: code,
          error: codeError,
        } = await ctx.supabaseAdmin
          .from(
            "owner_activation_codes",
          )
          .select(
            `
                            id,
                            owner_account_id,
                            expires_at,
                            used_at,
                            revoked_at
                            `,
          )
          .eq(
            "code_hash",
            codeHash,
          )
          .maybeSingle();

        if (
          codeError ||
          !code
        ) {
          return jsonError(
            "Code d'activation invalide.",
            401,
          );
        }

        /*
         * =========================================
         * CODE UTILISABLE ?
         * =========================================
         */

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

        if (
          new Date(
            code.expires_at,
          ).getTime() <= Date.now()
        ) {
          return jsonError(
            "Ce code d'activation a expiré.",
            401,
          );
        }

        /*
         * =========================================
         * COMPTE PROPRIÉTAIRE
         * =========================================
         */

        const {
          data: owner,
          error: ownerError,
        } = await ctx.supabaseAdmin
          .from(
            "owner_accounts",
          )
          .select(
            `
                            id,
                            auth_user_id,
                            first_name,
                            last_name,
                            phone,
                            whatsapp,
                            email,
                            status
                            `,
          )
          .eq(
            "id",
            code.owner_account_id,
          )
          .maybeSingle();

        if (
          ownerError ||
          !owner
        ) {
          return jsonError(
            "Compte propriétaire introuvable.",
            404,
          );
        }

        /*
         * =========================================
         * DÉJÀ ACTIF ?
         * =========================================
         */

        if (
          owner.status === "active" ||
          owner.auth_user_id
        ) {
          return jsonError(
            "Ce compte propriétaire est déjà activé. Utilisez la page de connexion.",
            409,
          );
        }

        /*
         * =========================================
         * TELEPHONE
         * =========================================
         */

        const phoneE164 = normalizeMoroccoPhone(
          owner.phone,
        );

        if (!phoneE164) {
          console.error(
            "Invalid owner phone",
            owner.id,
          );

          return jsonError(
            "Le numéro de téléphone associé à ce propriétaire est invalide. Contactez l'administration.",
            400,
          );
        }

        /*
         * =========================================
         * CREATE SUPABASE AUTH USER
         * =========================================
         *
         * IMPORTANT :
         * aucune clé service_role n'est envoyée
         * au navigateur.
         */

        const {
          data: authData,
          error: authError,
        } = await ctx.supabaseAdmin
          .auth
          .admin
          .createUser({
            phone: phoneE164,

            password,

            phone_confirm: true,

            user_metadata: {
              owner_account_id: owner.id,

              first_name: owner.first_name,

              last_name: owner.last_name,
            },
          });

        if (
          authError ||
          !authData.user
        ) {
          console.error(
            "Auth user creation failed:",
            authError?.message,
          );

          const duplicate = authError?.message
            ?.toLowerCase()
            .includes(
              "already",
            );

          return jsonError(
            duplicate
              ? "Un compte existe déjà avec ce numéro de téléphone. Contactez l'administration."
              : "Impossible de créer le compte propriétaire.",
            duplicate ? 409 : 500,
          );
        }

        createdAuthUserId = authData.user.id;

        /*
         * =========================================
         * FINALISATION ATOMIQUE DATABASE
         * =========================================
         */

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

          /*
           * Compensation :
           * si la transaction DB échoue,
           * on supprime le compte Auth créé.
           */

          try {
            await ctx.supabaseAdmin
              .auth
              .admin
              .deleteUser(
                authData.user.id,
              );
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

        /*
         * =========================================
         * SUCCESS
         * =========================================
         */

        createdAuthUserId = null;

        return Response.json(
          {
            success: true,

            message: "Compte activé avec succès.",

            phone: phoneE164,

            owner: {
              firstName: owner.first_name,

              lastName: owner.last_name,
            },

            activation: activationResult,
          },
          {
            status: 200,
          },
        );
      } catch (error) {
        console.error(
          "activate-owner-account:",
          error,
        );

        /*
         * Dernier filet de sécurité.
         */

        if (
          createdAuthUserId
        ) {
          try {
            await ctx.supabaseAdmin
              .auth
              .admin
              .deleteUser(
                createdAuthUserId,
              );
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
