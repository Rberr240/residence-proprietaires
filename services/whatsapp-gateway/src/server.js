import 'dotenv/config';

import express from 'express';
import qrcode from 'qrcode-terminal';
import pino from 'pino';

import makeWASocket, {
  Browsers,
  DisconnectReason,
  useMultiFileAuthState
} from '@whiskeysockets/baileys';

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || '127.0.0.1';

const API_KEY = process.env.WHATSAPP_GATEWAY_API_KEY;
const SESSION_DIR = process.env.WA_SESSION_DIR || '.wa-auth';

if (!API_KEY || API_KEY.length < 32) {
  console.error(
    '❌ WHATSAPP_GATEWAY_API_KEY absent ou trop courte dans .env'
  );
  process.exit(1);
}

const logger = pino({
  level: process.env.LOG_LEVEL || 'info'
});

const app = express();

app.disable('x-powered-by');
app.use(express.json({ limit: '64kb' }));

let sock = null;
let whatsappState = 'starting';
let lastConnectionError = null;
let reconnectTimer = null;

/**
 * Normalise un numéro.
 *
 * Exemples Maroc :
 * 0612345678     -> 212612345678
 * 0712345678     -> 212712345678
 * +212612345678  -> 212612345678
 * 00212612345678 -> 212612345678
 */
function normalizePhoneNumber(value) {
  if (typeof value !== 'string' && typeof value !== 'number') {
    throw new Error('Numéro WhatsApp invalide');
  }

  let number = String(value).trim();

  number = number.replace(/[^\d+]/g, '');

  if (number.startsWith('+')) {
    number = number.slice(1);
  }

  if (number.startsWith('00')) {
    number = number.slice(2);
  }

  // Numéro marocain local.
  if (number.startsWith('0')) {
    number = `212${number.slice(1)}`;
  }

  number = number.replace(/\D/g, '');

  if (number.length < 8 || number.length > 15) {
    throw new Error('Format de numéro WhatsApp invalide');
  }

  return number;
}

function apiKeyMiddleware(req, res, next) {
  const provided = req.header('x-api-key');

  if (!provided || provided !== API_KEY) {
    return res.status(401).json({
      ok: false,
      error: 'unauthorized'
    });
  }

  next();
}

function scheduleReconnect() {
  if (reconnectTimer) {
    return;
  }

  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;

    startWhatsApp().catch((error) => {
      logger.error(
        { err: error },
        'WhatsApp reconnect failed'
      );

      scheduleReconnect();
    });
  }, 5000);
}

async function startWhatsApp() {
  whatsappState = 'connecting';
  lastConnectionError = null;

  const { state, saveCreds } =
    await useMultiFileAuthState(SESSION_DIR);

  const newSock = makeWASocket({
    auth: state,

    browser: Browsers.windows(
      'Mirador Golf 1 Notifications'
    ),

    logger,

    markOnlineOnConnect: false,

    syncFullHistory: false
  });

  sock = newSock;

  newSock.ev.on('creds.update', saveCreds);

  newSock.ev.on(
    'connection.update',
    async (update) => {
      const {
        connection,
        lastDisconnect,
        qr
      } = update;

      if (qr) {
        console.log('');
        console.log(
          '================================================'
        );
        console.log(
          '📱 SCANNE CE QR CODE AVEC WHATSAPP'
        );
        console.log(
          'WhatsApp → Appareils connectés → Connecter'
        );
        console.log(
          '================================================'
        );
        console.log('');

        qrcode.generate(qr, {
          small: true
        });
      }

      if (connection === 'open') {
        whatsappState = 'connected';
        lastConnectionError = null;

        logger.info(
          {
            user: newSock.user?.id || null
          },
          'WhatsApp connected'
        );

        console.log('');
        console.log(
          '✅ WHATSAPP CONNECTÉ — MIRADOR GOLF 1'
        );
        console.log('');
      }

      if (connection === 'close') {
        whatsappState = 'disconnected';

        const statusCode =
          lastDisconnect?.error?.output?.statusCode ??
          lastDisconnect?.error?.statusCode ??
          null;

        const message =
          lastDisconnect?.error?.message ??
          'WhatsApp connection closed';

        lastConnectionError = message;

        logger.warn(
          {
            statusCode,
            error: message
          },
          'WhatsApp disconnected'
        );

        sock = null;

        if (
          statusCode === DisconnectReason.loggedOut
        ) {
          whatsappState = 'logged_out';

          console.error(
            '❌ Session WhatsApp déconnectée.'
          );

          console.error(
            'Supprime .wa-auth puis relance pour refaire l’appairage.'
          );

          return;
        }

        scheduleReconnect();
      }
    }
  );
}

/**
 * Endpoint public local de santé.
 * Pas besoin de clé : aucune donnée sensible.
 */
app.get('/health', (req, res) => {
  res.json({
    ok: true,
    service: 'mirador-golf-whatsapp-gateway',
    whatsapp: {
      state: whatsappState,
      connected:
        whatsappState === 'connected',
      user: sock?.user?.id || null,
      lastError: lastConnectionError
    }
  });
});

/**
 * Endpoint d'envoi.
 *
 * Header obligatoire :
 * x-api-key: ...
 *
 * JSON :
 * {
 *   "to": "0612345678",
 *   "message": "Bonjour"
 * }
 */
app.post(
  '/send',
  apiKeyMiddleware,
  async (req, res) => {
    try {
      if (
        whatsappState !== 'connected' ||
        !sock
      ) {
        return res.status(503).json({
          ok: false,
          error: 'whatsapp_not_connected',
          state: whatsappState
        });
      }

      const { to, message } = req.body || {};

      if (
        typeof message !== 'string' ||
        !message.trim()
      ) {
        return res.status(400).json({
          ok: false,
          error: 'message_required'
        });
      }

      if (message.length > 4000) {
        return res.status(400).json({
          ok: false,
          error: 'message_too_long'
        });
      }

      const number =
        normalizePhoneNumber(to);

      const jid =
        `${number}@s.whatsapp.net`;

      logger.info(
        {
          jid
        },
        'Sending WhatsApp notification'
      );

      const sent =
        await sock.sendMessage(
          jid,
          {
            text: message.trim()
          }
        );

      const messageId =
        sent?.key?.id || null;

      logger.info(
        {
          jid,
          messageId
        },
        'WhatsApp notification sent'
      );

      return res.status(200).json({
        ok: true,
        provider: 'baileys',
        channel: 'whatsapp',
        destination: number,
        provider_message_id: messageId
      });
    } catch (error) {
      logger.error(
        {
          err: error
        },
        'WhatsApp send failed'
      );

      return res.status(500).json({
        ok: false,
        error: 'send_failed',
        message:
          error instanceof Error
            ? error.message
            : 'Unknown error'
      });
    }
  }
);

const server = app.listen(
  PORT,
  HOST,
  () => {
    console.log('');
    console.log(
      '=============================================='
    );
    console.log(
      ' MIRADOR GOLF 1 — WHATSAPP GATEWAY V2'
    );
    console.log(
      '=============================================='
    );
    console.log(
      `API : http://${HOST}:${PORT}`
    );
    console.log(
      `Health : http://${HOST}:${PORT}/health`
    );
    console.log('');
  }
);

startWhatsApp().catch((error) => {
  whatsappState = 'error';
  lastConnectionError = error.message;

  logger.error(
    { err: error },
    'Initial WhatsApp connection failed'
  );

  scheduleReconnect();
});

function shutdown(signal) {
  console.log(
    `\n${signal} reçu — arrêt du gateway...`
  );

  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
  }

  try {
    sock?.end?.(
      new Error('Gateway shutdown')
    );
  } catch {
    // Ignore shutdown errors.
  }

  server.close(() => {
    process.exit(0);
  });

  setTimeout(() => {
    process.exit(1);
  }, 5000).unref();
}

process.on('SIGINT', () =>
  shutdown('SIGINT')
);

process.on('SIGTERM', () =>
  shutdown('SIGTERM')
);