import { withSupabase } from "npm:@supabase/server@^1";

import type { Database } from "../_shared/database.types.ts";

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function randomCodePart(
  length = 10,
): string {
  const bytes = crypto.getRandomValues(
    new Uint8Array(length),
  );

  let result = "";

  for (const byte of bytes) {
    result += CODE_ALPHABET[
      byte % CODE_ALPHABET.length
    ];
  }

  return result;
}

function cleanPart(
  value: string,
): string {
  return value
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "")
    .slice(0, 8);
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

export default {
  fetch: withSupabase<Database>(
    {
      auth: "user",
    },
    async (
      req,
      ctx,
    ) => {
      try {
        const userId = ctx.userClaims?.id;

        if (!userId) {
          return Response.json(
            {
              success: false,
              message: "Session utilisateur invalide.",
            },
            {
              status: 401,
            },
          );
        }

        // -----------------------------------------
        // VERIFY ADMIN
        // -----------------------------------------

        const {
          data: admin,
          error: adminError,
        } = await ctx.supabaseAdmin
          .from("admin_users")
          .select(
            "id, role, is_active",
          )
          .eq(
            "auth_user_id",
            userId,
          )
          .maybeSingle();

        if (
          adminError ||
          !admin ||
          !admin.is_active
        ) {
          return Response.json(
            {
              success: false,
              message: "Accès administrateur refusé.",
            },
            {
              status: 403,
            },
          );
        }

        // -----------------------------------------
        // BODY
        // -----------------------------------------

        const body = await req.json();

        const submissionId = typeof body?.submissionId ===
            "string"
          ? body.submissionId
          : "";

        if (!submissionId) {
          return Response.json(
            {
              success: false,
              message: "Propriétaire manquant.",
            },
            {
              status: 400,
            },
          );
        }

        // -----------------------------------------
        // READ OWNER
        // -----------------------------------------

        const {
          data: submission,
          error: submissionError,
        } = await ctx.supabaseAdmin
          .from(
            "owner_submissions",
          )
          .select(
            `
                            id,
                            building_code,
                            apartment_number,
                            first_name,
                            last_name,
                            whatsapp,
                            status
                            `,
          )
          .eq(
            "id",
            submissionId,
          )
          .maybeSingle();

        if (
          submissionError ||
          !submission
        ) {
          return Response.json(
            {
              success: false,
              message: "Propriétaire introuvable.",
            },
            {
              status: 404,
            },
          );
        }

        // -----------------------------------------
        // GENERATE RAW CODE
        // -----------------------------------------

        const block = cleanPart(
          submission.building_code,
        );

        const apartment = cleanPart(
          submission.apartment_number,
        );

        const random = randomCodePart(10);

        const activationCode = `MG-${block}${apartment}-${random}`;

        // -----------------------------------------
        // HASH WITH SERVER SECRET
        // -----------------------------------------

        const pepper = Deno.env.get(
          "OWNER_ACTIVATION_CODE_PEPPER",
        );

        if (!pepper) {
          console.error(
            "OWNER_ACTIVATION_CODE_PEPPER missing",
          );

          return Response.json(
            {
              success: false,
              message: "Configuration serveur incomplète.",
            },
            {
              status: 500,
            },
          );
        }

        const codeHash = await hmacSha256(
          activationCode,
          pepper,
        );

        // -----------------------------------------
        // EXPIRES IN 30 DAYS
        // -----------------------------------------

        const expiresAt = new Date(
          Date.now() +
            30 *
              24 *
              60 *
              60 *
              1000,
        )
          .toISOString();

        // -----------------------------------------
        // ATOMIC DATABASE OPERATION
        // -----------------------------------------

        const {
          data: result,
          error: rpcError,
        } = await ctx.supabase
          .rpc(
            "admin_validate_owner_submission",
            {
              p_submission_id: submissionId,

              p_code_hash: codeHash,

              p_expires_at: expiresAt,
            },
          );

        if (rpcError) {
          console.error(
            "Validation RPC error:",
            rpcError,
          );

          return Response.json(
            {
              success: false,
              message: rpcError.message,
            },
            {
              status: 400,
            },
          );
        }

        // -----------------------------------------
        // RETURN RAW CODE ONCE
        // -----------------------------------------

        return Response.json(
          {
            success: true,

            activationCode,

            expiresAt,

            owner: {
              firstName: submission.first_name,

              lastName: submission.last_name,

              building: submission.building_code,

              apartment: submission.apartment_number,

              whatsapp: submission.whatsapp,
            },

            result,
          },
        );
      } catch (error) {
        console.error(
          "admin-generate-owner-code:",
          error,
        );

        return Response.json(
          {
            success: false,

            message: "Erreur interne lors de la validation.",
          },
          {
            status: 500,
          },
        );
      }
    },
  ),
};
