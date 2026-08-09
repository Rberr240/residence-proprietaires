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

      const pepper = Deno.env.get("ACCESS_CODE_PEPPER");

      if (!pepper) {
        console.error(
          "ACCESS_CODE_PEPPER is not configured.",
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
        pepper,
      );

      const { data, error } = await ctx.supabaseAdmin
        .from("access_codes")
        .select(`
          active,
          used_at,
          expires_at,
          apartment:apartments!access_codes_apartment_id_fkey (
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

      const expired = data?.expires_at &&
        new Date(data.expires_at).getTime() <= Date.now();

      const unavailable = !data ||
        !data.active ||
        Boolean(data.used_at) ||
        Boolean(expired) ||
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

      return Response.json({
        valid: true,

        apartment: {
          number: apartment.apartment_number,
          buildingCode: building.code,
          buildingName: building.name,
        },
      });
    },
  ),
};
