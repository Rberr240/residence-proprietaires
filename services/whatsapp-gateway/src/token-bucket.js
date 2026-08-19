import { performance } from 'node:perf_hooks';

/**
 * Token bucket minimal, en mémoire, sans dépendance externe.
 *
 * Recharge continue calculée à la demande (pas de setInterval),
 * sur une horloge monotone injectable pour les tests.
 */
export function createTokenBucket({
  capacity,
  refillPerMinute,
  now = () => performance.now()
}) {
  if (!Number.isFinite(capacity) || capacity <= 0) {
    throw new Error(
      'capacity must be a finite positive number'
    );
  }

  if (
    !Number.isFinite(refillPerMinute) ||
    refillPerMinute <= 0
  ) {
    throw new Error(
      'refillPerMinute must be a finite positive number'
    );
  }

  const refillPerSecond = refillPerMinute / 60;

  let tokens = capacity;
  let lastRefill = now();

  function consume() {
    const current = now();

    // Horloge monotone : un recul de l'horloge injectée ne doit
    // jamais ajouter ni retirer de jetons.
    const elapsedSeconds = Math.max(
      0,
      (current - lastRefill) / 1000
    );

    tokens = Math.min(
      capacity,
      tokens + elapsedSeconds * refillPerSecond
    );

    lastRefill = current;

    if (tokens >= 1) {
      tokens -= 1;

      return { allowed: true };
    }

    const missingTokens = 1 - tokens;

    const retryAfterSeconds = Math.max(
      1,
      Math.ceil(missingTokens / refillPerSecond)
    );

    return {
      allowed: false,
      retryAfterSeconds
    };
  }

  return { consume };
}
