import { supabase } from '@/lib/supabase';

export type OwnerAccount = {
  id: string;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  phone_e164: string | null;
  whatsapp: string | null;
  email: string | null;
  status: string;
};

export type OwnerUnit = {
  id: string;
  building_code: string | null;
  apartment_number: string | null;
  is_primary: boolean;
};

export async function getActiveOwnerAccount(
  authUserId: string
): Promise<{ owner: OwnerAccount | null; error: Error | null }> {
  const { data, error } = await supabase
    .from('owner_accounts')
    .select(
      'id, first_name, last_name, phone, phone_e164, whatsapp, email, status'
    )
    .eq('auth_user_id', authUserId)
    .maybeSingle();

  if (error) {
    return { owner: null, error };
  }

  return { owner: data, error: null };
}

export async function getOwnerUnits(
  ownerAccountId: string
): Promise<{ units: OwnerUnit[]; error: Error | null }> {
  const { data, error } = await supabase
    .from('owner_account_units')
    .select('id, building_code, apartment_number, is_primary')
    .eq('owner_account_id', ownerAccountId)
    .order('is_primary', { ascending: false })
    .order('building_code', { ascending: true })
    .order('apartment_number', { ascending: true });

  if (error) {
    return { units: [], error };
  }

  return { units: data ?? [], error: null };
}

export function getPrimaryUnit(units: OwnerUnit[]): OwnerUnit | null {
  return units.find((unit) => unit.is_primary) ?? units[0] ?? null;
}
