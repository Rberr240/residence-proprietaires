import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";
import type { Database } from "../_shared/database.types.ts";

const encoder = new TextEncoder();

const INVALID_RESPONSE = {
  valid: false,
  message: "Code d'accès invalide ou indisponible.",
};

function normalizeCode(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value
    .trim()
    .toUpperCase()
    .replace(/\s+/g, "");

  if (!/^[A-Z0-9-]{8,32}$/.test(normalized)) {
    return null;
  }

  return normalized;
}

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

function createRandomToken(): string {
  const bytes = new Uint8Array(32);

  crypto.getRandomValues(bytes);

  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => {
    setTimeout(resolve, milliseconds);
  });
}

export default {
  fetch: withSupabase<Database>(
    { auth: "publishable" },
    async (req, ctx) => {
      if (req.method !== "POST") {
        return Response.json(
          {
            error: "Method not allowed",
          },
          {
            status: 405,
          },
        );
      }

      const accessCodePepper = Deno.env.get("ACCESS_CODE_PEPPER");

      const sessionPepper = Deno.env.get("REGISTRATION_SESSION_PEPPER");

      if (!accessCodePepper || !sessionPepper) {
        console.error(
          "Required security secrets are not configured.",
        );

        return Response.json(
          {
            valid: false,
            message: "Service temporairement indisponible.",
          },
          {
            status: 500,
          },
        );
      }

      let body: unknown;

      try {
        body = await req.json();
      } catch {
        await wait(200);

        return Response.json(INVALID_RESPONSE);
      }

      const code = normalizeCode(
        (body as { code?: unknown })?.code,
      );

      if (!code) {
        await wait(200);

        return Response.json(INVALID_RESPONSE);
      }

      const codeHash = await hmacSha256Hex(
        code,
        accessCodePepper,
      );

      const { data, error } = await ctx.supabaseAdmin
        .from("access_codes")
        .select(`
          id,
          active,
          used_at,
          expires_at,
          apartment:apartments!access_codes_apartment_id_fkey (
            id,
            apartment_number,
            building:buildings!apartments_building_id_fkey (
              code,
              name
            )
          )
        `)
        .eq("code_hash", codeHash)
        .maybeSingle();

      if (error) {
        console.error(
          "Access code lookup failed:",
          error.message,
        );

        return Response.json(
          {
            valid: false,
            message: "Service temporairement indisponible.",
          },
          {
            status: 500,
          },
        );
      }

      const expired = data?.expires_at
        ? new Date(data.expires_at).getTime() <= Date.now()
        : false;

      const unavailable = !data ||
        !data.active ||
        Boolean(data.used_at) ||
        expired ||
        !data.apartment;

      if (unavailable) {
        await wait(200);

        return Response.json(INVALID_RESPONSE);
      }

      const apartment = Array.isArray(data.apartment)
        ? data.apartment[0]
        : data.apartment;

      const building = Array.isArray(apartment?.building)
        ? apartment.building[0]
        : apartment?.building;

      if (!apartment || !building) {
        console.error(
          "Valid access code has an incomplete apartment relation.",
        );

        return Response.json(
          {
            valid: false,
            message: "Service temporairement indisponible.",
          },
          {
            status: 500,
          },
        );
      }

      /*
       * Only keep the latest unconsumed registration
       * session for this access code.
       */
      const { error: cleanupError } = await ctx.supabaseAdmin
        .from("registration_sessions")
        .delete()
        .eq("access_code_id", data.id)
        .is("consumed_at", null);

      if (cleanupError) {
        console.error(
          "Registration session cleanup failed:",
          cleanupError.message,
        );

        return Response.json(
          {
            valid: false,
            message: "Service temporairement indisponible.",
          },
          {
            status: 500,
          },
        );
      }

      /*
       * 32 random bytes = 256-bit temporary token.
       *
       * The browser receives this token.
       * PostgreSQL receives ONLY its HMAC hash.
       */
      const sessionToken = createRandomToken();

      const tokenHash = await hmacSha256Hex(
        sessionToken,
        sessionPepper,
      );

      /*
       * Registration session validity:
       * 15 minutes.
       */
      const expiresAt = new Date(
        Date.now() + 15 * 60 * 1000,
      ).toISOString();

      const { error: sessionError } = await ctx.supabaseAdmin
        .from("registration_sessions")
        .insert({
          apartment_id: apartment.id,
          access_code_id: data.id,
          token_hash: tokenHash,
          expires_at: expiresAt,
        });

      if (sessionError) {
        console.error(
          "Registration session creation failed:",
          sessionError.message,
        );

        return Response.json(
          {
            valid: false,
            message: "Service temporairement indisponible.",
          },
          {
            status: 500,
          },
        );
      }

      return Response.json(
        {
          valid: true,

          sessionToken,

          expiresAt,

          apartment: {
            number: apartment.apartment_number,
            buildingCode: building.code,
            buildingName: building.name,
          },
        },
        {
          headers: {
            "Cache-Control": "no-store",
          },
        },
      );
    },
  ),
};
