import { createClient } from "npm:@supabase/supabase-js@2";

type Delivery = {
  id: string;
  owner_notification_id: string;
  channel: "email" | "whatsapp" | "push";
  provider: string;
  destination: string;
  status: string;
  attempt_count: number;
  max_attempts: number;
};

type NotificationEvent = {
  id: string;
  title: string;
  body: string;
  category: string;
  priority: "normal" | "high" | "urgent";
  action_section: string | null;
  action_entity_id: string | null;
  metadata: Record<string, unknown> | null;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";

const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";

const WORKER_SECRET = Deno.env.get("NOTIFICATION_WORKER_SECRET") ?? "";

const PUBLIC_APP_URL = (
  Deno.env.get("PUBLIC_APP_URL") ??
    "https://rberr240.github.io/residence-proprietaires/"
).replace(/\/+$/, "");

// ============================================================
// EMAIL — BREVO
// ============================================================

const BREVO_API_KEY = Deno.env.get("BREVO_API_KEY") ?? "";

const BREVO_SENDER_NAME = Deno.env.get("BREVO_SENDER_NAME") ??
  "Résidence Mirador Golf 1";

const BREVO_SENDER_EMAIL = Deno.env.get("BREVO_SENDER_EMAIL") ?? "";

// ============================================================
// WHATSAPP — BAILEYS GATEWAY
// ============================================================

const WHATSAPP_GATEWAY_URL = (
  Deno.env.get("WHATSAPP_GATEWAY_URL") ?? ""
).replace(/\/+$/, "");

const WHATSAPP_GATEWAY_API_KEY =
  Deno.env.get("WHATSAPP_GATEWAY_API_KEY") ?? "";

// ============================================================
// PUSH — ONESIGNAL
// ============================================================

const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID") ?? "";

const ONESIGNAL_API_KEY = Deno.env.get("ONESIGNAL_API_KEY") ?? "";

// Catégories dont le corps peut contenir des données sensibles
// (montants syndic). Le push transite par un provider tiers
// (OneSignal) : on y affiche un message générique et on renvoie
// vers l'espace propriétaire authentifié pour le détail. Le titre
// de ces événements ne contient déjà aucun montant (voir la
// migration create_notifications_v2.sql), seul le corps l'exige.
const PUSH_GENERIC_BODY_CATEGORIES = new Set([
  "syndic",
]);

const PUSH_GENERIC_BODY_FALLBACK =
  "Une nouvelle information est disponible dans votre espace MIRADOR.";

function pushNotificationBody(
  event: NotificationEvent,
): string {
  if (
    PUSH_GENERIC_BODY_CATEGORIES.has(
      event.category,
    )
  ) {
    return PUSH_GENERIC_BODY_FALLBACK;
  }

  return event.body;
}

const DEFAULT_BATCH_SIZE = 20;
const MAX_BATCH_SIZE = 100;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error(
    "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY manquant.",
  );
}

const supabaseAdmin = createClient(
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY,
  {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  },
);

function jsonResponse(
  body: unknown,
  status = 200,
): Response {
  return new Response(
    JSON.stringify(body),
    {
      status,
      headers: {
        "content-type": "application/json; charset=utf-8",
        "cache-control": "no-store",
      },
    },
  );
}

function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function truncate(
  value: unknown,
  maxLength: number,
): string {
  const text = String(value ?? "").trim();

  if (text.length <= maxLength) {
    return text;
  }

  return `${
    text.slice(
      0,
      maxLength - 1,
    )
  }…`;
}

function normalizeWhatsAppNumber(
  rawValue: string,
): string {
  let value = rawValue
    .trim()
    .replace(
      /^whatsapp:/i,
      "",
    )
    .replace(
      /[^\d+]/g,
      "",
    );

  if (
    value.startsWith("00")
  ) {
    value = `+${value.slice(2)}`;
  }

  if (
    value.startsWith("0")
  ) {
    value = `+212${value.slice(1)}`;
  } else if (
    value.startsWith("212")
  ) {
    value = `+${value}`;
  }

  if (
    !value.startsWith("+")
  ) {
    value = `+${value}`;
  }

  if (
    !/^\+\d{8,15}$/.test(
      value,
    )
  ) {
    throw new Error(
      "Numéro WhatsApp invalide.",
    );
  }

  return value;
}

function actionUrl(
  event: NotificationEvent,
): string {
  const url = new URL(
    `${PUBLIC_APP_URL}/espace-proprietaire.html`,
  );

  if (
    event.action_section
  ) {
    url.searchParams.set(
      "section",
      event.action_section,
    );
  }

  if (
    event.action_entity_id
  ) {
    url.searchParams.set(
      "entity",
      event.action_entity_id,
    );
  }

  return url.toString();
}

function nextAttemptAt(
  attemptCount: number,
): string {
  const minutes = Math.min(
    60,
    Math.max(
      2,
      2 ** Math.max(
        1,
        attemptCount,
      ),
    ),
  );

  return new Date(
    Date.now() +
      minutes *
        60 *
        1000,
  ).toISOString();
}

async function fetchNotificationEvent(
  delivery: Delivery,
): Promise<NotificationEvent> {
  const {
    data: ownerNotification,
    error: ownerNotificationError,
  } = await supabaseAdmin
    .from(
      "owner_notifications",
    )
    .select(
      "id,event_id,owner_account_id",
    )
    .eq(
      "id",
      delivery.owner_notification_id,
    )
    .single();

  if (
    ownerNotificationError ||
    !ownerNotification
  ) {
    throw new Error(
      ownerNotificationError?.message ??
        "Notification propriétaire introuvable.",
    );
  }

  const {
    data: event,
    error: eventError,
  } = await supabaseAdmin
    .from(
      "notification_events",
    )
    .select(
      `
        id,
        title,
        body,
        category,
        priority,
        action_section,
        action_entity_id,
        metadata
        `,
    )
    .eq(
      "id",
      ownerNotification.event_id,
    )
    .single();

  if (
    eventError ||
    !event
  ) {
    throw new Error(
      eventError?.message ??
        "Événement de notification introuvable.",
    );
  }

  return event as NotificationEvent;
}

// ============================================================
// EMAIL — BREVO TRANSACTIONAL API
// ============================================================

async function sendEmail(
  delivery: Delivery,
  event: NotificationEvent,
): Promise<string> {
  if (
    !BREVO_API_KEY
  ) {
    throw new Error(
      "BREVO_API_KEY non configurée.",
    );
  }

  if (
    !BREVO_SENDER_EMAIL
  ) {
    throw new Error(
      "BREVO_SENDER_EMAIL non configuré.",
    );
  }

  const portalUrl = actionUrl(
    event,
  );

  const html = `
    <!doctype html>
    <html lang="fr">
      <body
        style="
          margin:0;
          padding:0;
          background:#f4f7f5;
          font-family:Arial,sans-serif;
          color:#123d32;
        "
      >
        <div
          style="
            max-width:620px;
            margin:0 auto;
            padding:30px 18px;
          "
        >
          <div
            style="
              background:#ffffff;
              border:1px solid #e1e9e5;
              border-radius:16px;
              overflow:hidden;
            "
          >
            <div
              style="
                padding:20px 24px;
                background:#123d32;
                color:#ffffff;
              "
            >
              <strong
                style="
                  font-size:18px;
                "
              >
                ${
    escapeHtml(
      BREVO_SENDER_NAME,
    )
  }
              </strong>
            </div>

            <div
              style="
                padding:26px 24px;
              "
            >
              <h1
                style="
                  margin:0 0 14px;
                  font-size:22px;
                  line-height:1.3;
                "
              >
                ${
    escapeHtml(
      event.title,
    )
  }
              </h1>

              <p
                style="
                  margin:0;
                  color:#51685f;
                  line-height:1.65;
                  font-size:15px;
                "
              >
                ${
    escapeHtml(
      event.body,
    )
  }
              </p>

              <a
                href="${
    escapeHtml(
      portalUrl,
    )
  }"
                style="
                  display:inline-block;
                  margin-top:22px;
                  padding:12px 18px;
                  border-radius:10px;
                  background:#17614e;
                  color:#ffffff;
                  text-decoration:none;
                  font-weight:700;
                "
              >
                Ouvrir mon espace propriétaire
              </a>
            </div>

            <div
              style="
                padding:15px 24px;
                border-top:1px solid #edf1ef;
                color:#7a8c84;
                font-size:12px;
              "
            >
              Message transactionnel de la résidence
              Mirador Golf 1.
            </div>
          </div>
        </div>
      </body>
    </html>
  `;

  const response = await fetch(
    "https://api.brevo.com/v3/smtp/email",
    {
      method: "POST",

      headers: {
        accept: "application/json",

        "api-key": BREVO_API_KEY,

        "content-type": "application/json",
      },

      body: JSON.stringify({
        sender: {
          name: BREVO_SENDER_NAME,

          email: BREVO_SENDER_EMAIL,
        },

        to: [
          {
            email: delivery.destination,
          },
        ],

        subject: truncate(
          event.title,
          180,
        ),

        htmlContent: html,

        tags: [
          "mirador-golf-1",
          "transactional-notification",
        ],

        // Déduplication assistée par le provider (best-effort) : si
        // ce worker retente l'envoi d'une livraison déjà acceptée
        // par Brevo (ex. crash entre l'envoi et la mise à jour de
        // notification_deliveries), la même clé — dérivée de l'id
        // de livraison, stable pour toute tentative de CETTE
        // livraison — permet à Brevo de rejeter le doublon au lieu
        // de renvoyer l'email. Documentation Brevo actuelle
        // (développeurs.brevo.com, endpoint /v3/smtp/email) :
        // fenêtre de 30 minutes ; au-delà, retour au comportement
        // "au moins une fois" habituel. La clé va dans le corps
        // JSON sous "headers", pas comme en-tête HTTP.
        headers: {
          idempotencyKey: delivery.id,
        },
      }),
    },
  );

  const payload = await response
    .json()
    .catch(
      () => ({}),
    );

  if (
    !response.ok
  ) {
    // Rejeu détecté par Brevo via idempotencyKey : cette livraison a
    // déjà été acceptée par Brevo lors d'une tentative précédente
    // (ex. crash de ce worker entre l'envoi et la mise à jour de
    // notification_deliveries). Ce n'est pas un échec réel — le
    // traiter comme tel provoquerait des nouvelles tentatives qui
    // rencontreraient indéfiniment le même conflit jusqu'à
    // épuisement de max_attempts, sans jamais marquer la livraison
    // comme envoyée.
    if (
      payload?.code ===
        "duplicate_parameter"
    ) {
      return "brevo-deduplicated";
    }

    throw new Error(
      `Brevo ${response.status}: ${
        payload?.message ??
          payload?.code ??
          JSON.stringify(
            payload,
          )
      }`,
    );
  }

  if (
    !payload?.messageId
  ) {
    throw new Error(
      "Brevo n'a retourné aucun messageId.",
    );
  }

  return String(
    payload.messageId,
  );
}

// ============================================================
// WHATSAPP — BAILEYS GATEWAY
// ============================================================

async function sendWhatsApp(
  delivery: Delivery,
  event: NotificationEvent,
): Promise<string> {
  if (
    !WHATSAPP_GATEWAY_URL
  ) {
    throw new Error(
      "WHATSAPP_GATEWAY_URL non configurée.",
    );
  }

  if (
    !WHATSAPP_GATEWAY_API_KEY
  ) {
    throw new Error(
      "WHATSAPP_GATEWAY_API_KEY non configurée.",
    );
  }

  const to = normalizeWhatsAppNumber(
    delivery.destination,
  );

  const portalUrl = actionUrl(
    event,
  );

  const message = [
    `*${truncate(event.title, 120)}*`,
    truncate(event.body, 1200),
    portalUrl,
  ]
    .filter(Boolean)
    .join("\n\n");

  const response = await fetch(
    `${WHATSAPP_GATEWAY_URL}/send`,
    {
      method: "POST",

      headers: {
  "content-type": "application/json",
  "x-api-key": WHATSAPP_GATEWAY_API_KEY,
  "ngrok-skip-browser-warning": "1",
},

      body: JSON.stringify({
        to,
        message,
      }),
    },
  );

  const payload = await response
    .json()
    .catch(
      () => ({}),
    );

  if (
    !response.ok
  ) {
    throw new Error(
      `WhatsApp Gateway ${response.status}: ${
        payload?.message ??
          payload?.error ??
          JSON.stringify(
            payload,
          )
      }`,
    );
  }

  if (
    payload?.ok !== true ||
    !payload?.provider_message_id
  ) {
    throw new Error(
      "Le WhatsApp Gateway n'a retourné aucun provider_message_id.",
    );
  }

  return String(
    payload.provider_message_id,
  );
}

// ============================================================
// PUSH — ONESIGNAL
// ============================================================

async function sendPush(
  delivery: Delivery,
  event: NotificationEvent,
): Promise<{
  status:
    | "sent"
    | "skipped";
  providerMessageId:
    | string
    | null;
}> {
  if (
    !ONESIGNAL_APP_ID ||
    !ONESIGNAL_API_KEY
  ) {
    throw new Error(
      "OneSignal non configuré.",
    );
  }

  const portalUrl = actionUrl(
    event,
  );

  const pushBody = pushNotificationBody(
    event,
  );

  const response = await fetch(
    "https://api.onesignal.com/notifications?c=push",
    {
      method: "POST",

      headers: {
        authorization: `Key ${ONESIGNAL_API_KEY}`,

        "content-type": "application/json",
      },

      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,

        // Rejeu-sécurité (voir sendEmail ci-dessus) : si cette
        // livraison est retentée après avoir déjà été acceptée par
        // OneSignal, la même clé — dérivée de l'id de livraison —
        // fait renvoyer par OneSignal le résultat de l'envoi
        // d'origine au lieu de notifier une seconde fois. Fenêtre
        // garantie par OneSignal : 30 jours.
        idempotency_key: delivery.id,

        include_aliases: {
          external_id: [
            delivery.destination,
          ],
        },

        target_channel: "push",

        headings: {
          fr: truncate(
            event.title,
            80,
          ),

          en: truncate(
            event.title,
            80,
          ),
        },

        contents: {
          fr: truncate(
            pushBody,
            220,
          ),

          en: truncate(
            pushBody,
            220,
          ),
        },

        url: portalUrl,

        data: {
          section: event.action_section,

          entityId: event.action_entity_id,

          priority: event.priority,
        },
      }),
    },
  );

  const payload = await response
    .json()
    .catch(
      () => ({}),
    );

  if (
    !response.ok
  ) {
    throw new Error(
      `OneSignal ${response.status}: ${
        payload?.errors ??
          JSON.stringify(
            payload,
          )
      }`,
    );
  }

  if (
    !payload?.id
  ) {
    return {
      status: "skipped",

      providerMessageId: null,
    };
  }

  return {
    status: "sent",

    providerMessageId: String(
      payload.id,
    ),
  };
}

async function createAttempt(
  delivery: Delivery,
): Promise<
  | string
  | null
> {
  const {
    data,
    error,
  } = await supabaseAdmin
    .from(
      "notification_delivery_attempts",
    )
    .insert({
      delivery_id: delivery.id,

      attempt_number: delivery.attempt_count,

      provider: delivery.provider,

      status: "processing",

      started_at: new Date()
        .toISOString(),
    })
    .select(
      "id",
    )
    .single();

  if (
    error
  ) {
    console.error(
      "Attempt insert failed:",
      error,
    );

    return null;
  }

  return data?.id ??
    null;
}

async function finishAttempt(
  attemptId:
    | string
    | null,
  values: {
    status:
      | "sent"
      | "delivered"
      | "failed"
      | "skipped";
    httpStatus?:
      | number
      | null;
    providerMessageId?:
      | string
      | null;
    errorCode?:
      | string
      | null;
    errorMessage?:
      | string
      | null;
    responseMetadata?: Record<
      string,
      unknown
    >;
  },
): Promise<void> {
  if (
    !attemptId
  ) {
    return;
  }

  const {
    error,
  } = await supabaseAdmin
    .from(
      "notification_delivery_attempts",
    )
    .update({
      status: values.status,

      http_status: values.httpStatus ??
        null,

      provider_message_id: values.providerMessageId ??
        null,

      error_code: values.errorCode ??
        null,

      error_message: values.errorMessage ??
        null,

      response_metadata: values.responseMetadata ??
        {},

      completed_at: new Date()
        .toISOString(),
    })
    .eq(
      "id",
      attemptId,
    );

  if (
    error
  ) {
    console.error(
      "Attempt update failed:",
      error,
    );
  }
}

async function finishDelivery(
  delivery: Delivery,
  values: {
    status:
      | "sent"
      | "delivered"
      | "failed"
      | "skipped"
      | "cancelled";
    providerMessageId?:
      | string
      | null;
    lastError?:
      | string
      | null;
    nextAttemptAt?:
      | string
      | null;
  },
): Promise<void> {
  const {
    error,
  } = await supabaseAdmin
    .rpc(
      "service_finish_notification_delivery",
      {
        p_delivery_id: delivery.id,

        p_status: values.status,

        p_provider_message_id: values.providerMessageId ??
          null,

        p_last_error: values.lastError ??
          null,

        p_next_attempt_at: values.nextAttemptAt ??
          null,
      },
    );

  if (
    error
  ) {
    throw new Error(
      `Impossible de finaliser la livraison: ${error.message}`,
    );
  }
}

async function processDelivery(
  delivery: Delivery,
): Promise<{
  id: string;
  channel: string;
  status: string;
  error?: string;
}> {
  const attemptId = await createAttempt(
    delivery,
  );

  try {
    const event = await fetchNotificationEvent(
      delivery,
    );

    if (
      delivery.channel ===
        "email"
    ) {
      const providerMessageId = await sendEmail(
        delivery,
        event,
      );

      await finishAttempt(
        attemptId,
        {
          status: "sent",

          providerMessageId,
        },
      );

      await finishDelivery(
        delivery,
        {
          status: "sent",

          providerMessageId,
        },
      );

      return {
        id: delivery.id,

        channel: delivery.channel,

        status: "sent",
      };
    }

    if (
      delivery.channel ===
        "whatsapp"
    ) {
      const providerMessageId = await sendWhatsApp(
        delivery,
        event,
      );

      await finishAttempt(
        attemptId,
        {
          status: "sent",

          providerMessageId,
        },
      );

      await finishDelivery(
        delivery,
        {
          status: "sent",

          providerMessageId,
        },
      );

      return {
        id: delivery.id,

        channel: delivery.channel,

        status: "sent",
      };
    }

    if (
      delivery.channel ===
        "push"
    ) {
      const result = await sendPush(
        delivery,
        event,
      );

      await finishAttempt(
        attemptId,
        {
          status: result.status,

          providerMessageId: result.providerMessageId,
        },
      );

      await finishDelivery(
        delivery,
        {
          status: result.status,

          providerMessageId: result.providerMessageId,

          lastError: result.status ===
              "skipped"
            ? "Aucun abonnement push OneSignal trouvé."
            : null,
        },
      );

      return {
        id: delivery.id,

        channel: delivery.channel,

        status: result.status,
      };
    }

    throw new Error(
      `Canal non supporté: ${delivery.channel}`,
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(
      error,
    );

    await finishAttempt(
      attemptId,
      {
        status: "failed",

        errorMessage: message,
      },
    );

    const exhausted = delivery.attempt_count >=
      delivery.max_attempts;

    await finishDelivery(
      delivery,
      {
        status: exhausted ? "cancelled" : "failed",

        lastError: message,

        nextAttemptAt: exhausted ? null : nextAttemptAt(
          delivery.attempt_count,
        ),
      },
    );

    return {
      id: delivery.id,

      channel: delivery.channel,

      status: exhausted ? "cancelled" : "failed",

      error: message,
    };
  }
}

Deno.serve(
  async (
    request: Request,
  ) => {
    if (
      request.method !==
        "POST"
    ) {
      return jsonResponse(
        {
          error: "Méthode non autorisée.",
        },
        405,
      );
    }

    if (
      !WORKER_SECRET
    ) {
      return jsonResponse(
        {
          error: "NOTIFICATION_WORKER_SECRET non configuré.",
        },
        503,
      );
    }

    const providedSecret = request.headers.get(
      "x-worker-secret",
    ) ?? "";

    if (
      providedSecret !==
        WORKER_SECRET
    ) {
      return jsonResponse(
        {
          error: "Non autorisé.",
        },
        401,
      );
    }

    let batchSize = DEFAULT_BATCH_SIZE;

    try {
      const body = await request
        .json()
        .catch(
          () => ({}),
        );

      batchSize = Math.max(
        1,
        Math.min(
          MAX_BATCH_SIZE,
          Number(
            body?.limit ??
              DEFAULT_BATCH_SIZE,
          ) ||
            DEFAULT_BATCH_SIZE,
        ),
      );
    } catch {
      // Valeur par défaut.
    }

    const {
      error: staleError,
    } = await supabaseAdmin
      .rpc(
        "service_requeue_stale_notification_deliveries",
      );

    if (
      staleError
    ) {
      console.error(
        "Stale requeue error:",
        staleError,
      );
    }

    const {
      data: claimed,
      error: claimError,
    } = await supabaseAdmin
      .rpc(
        "service_claim_notification_deliveries",
        {
          p_limit: batchSize,
        },
      );

    if (
      claimError
    ) {
      return jsonResponse(
        {
          error: claimError.message,
        },
        500,
      );
    }

    const deliveries = (
      claimed ??
        []
    ) as Delivery[];

    if (
      deliveries.length ===
        0
    ) {
      return jsonResponse({
        success: true,

        claimed: 0,

        results: [],
      });
    }

    const results: Array<{
      id: string;
      channel: string;
      status: string;
      error?: string;
    }> = [];

    // Traitement séquentiel :
    // prévisible et plus doux pour les providers.
    for (
      const delivery of deliveries
    ) {
      results.push(
        await processDelivery(
          delivery,
        ),
      );
    }

    return jsonResponse({
      success: true,

      claimed: deliveries.length,

      results,
    });
  },
);