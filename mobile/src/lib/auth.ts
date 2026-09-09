import * as Crypto from 'expo-crypto';

import { supabase } from '@/lib/supabase';

export function normalizeMoroccoPhone(value: string): string | null {
  let digits = value.replace(/\D/g, '');

  if (digits.startsWith('00212')) {
    digits = digits.slice(2);
  }

  if (digits.startsWith('212')) {
    const local = digits.slice(3);

    if (
      local.length === 9 &&
      (local.startsWith('6') || local.startsWith('7'))
    ) {
      return `+212${local}`;
    }
  }

  if (
    digits.length === 10 &&
    (digits.startsWith('06') || digits.startsWith('07'))
  ) {
    return `+212${digits.slice(1)}`;
  }

  if (
    digits.length === 9 &&
    (digits.startsWith('6') || digits.startsWith('7'))
  ) {
    return `+212${digits}`;
  }

  return null;
}

export async function buildInternalLoginEmail(phoneE164: string) {
  const digest = await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    `mirador-golf-1:${phoneE164}`
  );

  return `owner-${digest.slice(0, 40)}@auth.mirador-golf.invalid`;
}

export type SignInOwnerResult =
  | { ok: true }
  | { ok: false; reason: 'invalid-phone' | 'missing-password' | 'invalid-credentials' };

export async function signInOwner(
  phone: string,
  password: string
): Promise<SignInOwnerResult> {
  const normalizedPhone = normalizeMoroccoPhone(phone);

  if (!normalizedPhone) {
    return { ok: false, reason: 'invalid-phone' };
  }

  if (!password) {
    return { ok: false, reason: 'missing-password' };
  }

  const loginEmail = await buildInternalLoginEmail(normalizedPhone);

  const { error } = await supabase.auth.signInWithPassword({
    email: loginEmail,
    password,
  });

  if (error) {
    return { ok: false, reason: 'invalid-credentials' };
  }

  return { ok: true };
}
