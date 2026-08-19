import test from 'node:test';
import assert from 'node:assert/strict';

import { createTokenBucket } from '../src/token-bucket.js';

function makeClock(startMs = 0) {
  let current = startMs;

  return {
    now: () => current,
    advance(ms) {
      current += ms;
    },
    set(ms) {
      current = ms;
    }
  };
}

test('les 60 premiers appels sont autorisés', () => {
  const clock = makeClock();
  const bucket = createTokenBucket({
    capacity: 60,
    refillPerMinute: 20,
    now: clock.now
  });

  for (let i = 0; i < 60; i += 1) {
    const result = bucket.consume();
    assert.equal(result.allowed, true, `appel ${i + 1} devrait être autorisé`);
  }
});

test('le 61e appel est refusé', () => {
  const clock = makeClock();
  const bucket = createTokenBucket({
    capacity: 60,
    refillPerMinute: 20,
    now: clock.now
  });

  for (let i = 0; i < 60; i += 1) {
    bucket.consume();
  }

  const result = bucket.consume();

  assert.equal(result.allowed, false);
  assert.equal(typeof result.retryAfterSeconds, 'number');
});

test('bucket vide : Retry-After vaut 3 secondes avec une recharge de 20/minute', () => {
  const clock = makeClock();
  const bucket = createTokenBucket({
    capacity: 60,
    refillPerMinute: 20,
    now: clock.now
  });

  for (let i = 0; i < 60; i += 1) {
    bucket.consume();
  }

  const result = bucket.consume();

  assert.equal(result.allowed, false);
  assert.equal(result.retryAfterSeconds, 3);
});

test('après 3 secondes, exactement un nouveau jeton est disponible', () => {
  const clock = makeClock();
  const bucket = createTokenBucket({
    capacity: 60,
    refillPerMinute: 20,
    now: clock.now
  });

  for (let i = 0; i < 60; i += 1) {
    bucket.consume();
  }

  clock.advance(3000);

  const first = bucket.consume();
  assert.equal(first.allowed, true);

  const second = bucket.consume();
  assert.equal(second.allowed, false);
});

test('après 60 secondes, 20 jetons sont rechargés', () => {
  const clock = makeClock();
  const bucket = createTokenBucket({
    capacity: 60,
    refillPerMinute: 20,
    now: clock.now
  });

  for (let i = 0; i < 60; i += 1) {
    bucket.consume();
  }

  clock.advance(60_000);

  for (let i = 0; i < 20; i += 1) {
    const result = bucket.consume();
    assert.equal(result.allowed, true, `jeton rechargé ${i + 1} devrait être autorisé`);
  }

  const overflow = bucket.consume();
  assert.equal(overflow.allowed, false);
});

test('une longue période d\'inactivité ne dépasse jamais la capacité maximale de 60', () => {
  const clock = makeClock();
  const bucket = createTokenBucket({
    capacity: 60,
    refillPerMinute: 20,
    now: clock.now
  });

  bucket.consume();

  clock.advance(1000 * 60 * 60 * 24 * 365);

  let allowedCount = 0;

  for (let i = 0; i < 61; i += 1) {
    const result = bucket.consume();
    if (result.allowed) {
      allowedCount += 1;
    }
  }

  assert.equal(allowedCount, 60);
});

test('un recul de l\'horloge n\'ajoute ni ne retire incorrectement de jetons', () => {
  const clock = makeClock(10_000);
  const bucket = createTokenBucket({
    capacity: 60,
    refillPerMinute: 20,
    now: clock.now
  });

  for (let i = 0; i < 60; i += 1) {
    bucket.consume();
  }

  clock.set(0);

  const result = bucket.consume();

  assert.equal(result.allowed, false);
  assert.equal(result.retryAfterSeconds, 3);
});

test('une capacité nulle, négative ou non finie est refusée', () => {
  assert.throws(() =>
    createTokenBucket({ capacity: 0, refillPerMinute: 20 })
  );
  assert.throws(() =>
    createTokenBucket({ capacity: -1, refillPerMinute: 20 })
  );
  assert.throws(() =>
    createTokenBucket({ capacity: Infinity, refillPerMinute: 20 })
  );
  assert.throws(() =>
    createTokenBucket({ capacity: NaN, refillPerMinute: 20 })
  );
});

test('une recharge nulle, négative ou non finie est refusée', () => {
  assert.throws(() =>
    createTokenBucket({ capacity: 60, refillPerMinute: 0 })
  );
  assert.throws(() =>
    createTokenBucket({ capacity: 60, refillPerMinute: -1 })
  );
  assert.throws(() =>
    createTokenBucket({ capacity: 60, refillPerMinute: Infinity })
  );
  assert.throws(() =>
    createTokenBucket({ capacity: 60, refillPerMinute: NaN })
  );
});
