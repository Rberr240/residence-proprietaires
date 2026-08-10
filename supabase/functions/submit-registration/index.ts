import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import type { Database } from "../_shared/database.types.ts";

const encoder = new TextEncoder();

type RegistrationResult = {
  success?: boolean;
  reason?: string;
  owner_id?: string;
  apartment_id?: string;
};

async function hmacSha256Hex(
  value: string,
  secret: string,
): Promise<string> {
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

  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function cleanOptional(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const cleaned = value.trim();

  return cleaned.length > 0 ? cleaned : null;
}

export default {
  fetch: withSupabase<Database>(
    { auth: "publishable" },
    async (req, ctx) => {
      if (req.method !== "POST") {
        return Response.json(
          {
            success: false,
            message: "Method not allowed",
          },
          {
            status: 405,
          },
        );
      }

      const sessionPepper = Deno.env.get(
        "REGISTRATION_SESSION_PEPPER",
      );

      if (!sessionPepper) {
        console.error(
          "REGISTRATION_SESSION_PEPPER is missing.",
        );

        return Response.json(
          {
            success: false,
            message: "Service temporairement indisponible.",
          },
          {
            status: 500,
          },
        );
      }

      let body: Record<string, unknown>;

      try {
        body = await req.json();
      } catch {
        return Response.json(
          {
            success: false,
            message: "Données invalides.",
          },
          {
            status: 400,
          },
        );
      }

      const sessionToken = typeof body.sessionToken === "string"
        ? body.sessionToken.trim().toLowerCase()
        : "";

      if (!/^[0-9a-f]{64}$/.test(sessionToken)) {
        return Response.json(
          {
            success: false,
            message: "Session invalide ou expirée.",
          },
          {
            status: 400,
          },
        );
      }

      const firstName = typeof body.firstName === "string"
        ? body.firstName.trim()
        : "";

      const lastName = typeof body.lastName === "string"
        ? body.lastName.trim()
        : "";

      const phone = typeof body.phone === "string" ? body.phone.trim() : "";

      const whatsapp = cleanOptional(body.whatsapp);
      const email = cleanOptional(body.email);
      const consent = body.consent === true;

      const tokenHash = await hmacSha256Hex(
        sessionToken,
        sessionPepper,
      );

      const { data, error } = await ctx.supabaseAdmin.rpc(
        "register_owner_with_session",
        {
          p_token_hash: tokenHash,
          p_first_name: firstName,
          p_last_name: lastName,
          p_phone: phone,
          p_whatsapp: whatsapp ?? undefined,
          p_email: email ?? undefined,
          p_consent: consent,
        },
      );

      if (error) {
        console.error(
          "Owner registration RPC failed:",
          error.message,
        );

        return Response.json(
          {
            success: false,
            message: "Service temporairement indisponible.",
          },
          {
            status: 500,
          },
        );
      }

      const result = data as RegistrationResult | null;

      if (!result?.success) {
        return Response.json(
          {
            success: false,
            message: result?.reason === "consent_required"
              ? "Le consentement est obligatoire."
              : "Session invalide, expirée ou déjà utilisée.",
          },
          {
            status: 400,
            headers: {
              "Cache-Control": "no-store",
            },
          },
        );
      }

      return Response.json(
        {
          success: true,
          message: "Inscription enregistrée.",
        },
        {
          status: 200,
          headers: {
            "Cache-Control": "no-store",
          },
        },
      );
    },
  ),
};
