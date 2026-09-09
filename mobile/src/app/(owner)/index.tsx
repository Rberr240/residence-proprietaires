import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { getActiveOwnerAccount, getOwnerUnits, getPrimaryUnit } from '@/lib/owner';
import { useAuth } from '@/providers/auth-provider';

type OwnerProfile = {
  fullName: string;
  buildingCode: string | null;
  apartmentNumber: string | null;
};

export default function OwnerHomeScreen() {
  const { user, signOut } = useAuth();
  const [profile, setProfile] = useState<OwnerProfile | null>(null);
  const [profileLoading, setProfileLoading] = useState(true);
  const [profileError, setProfileError] = useState(false);

  useEffect(() => {
    let isMounted = true;

    async function loadProfile() {
      if (!user) return;

      const { owner, error: ownerError } = await getActiveOwnerAccount(user.id);

      if (!isMounted) return;

      if (ownerError || !owner) {
        setProfileError(true);
        setProfileLoading(false);
        return;
      }

      const { units } = await getOwnerUnits(owner.id);
      const primaryUnit = getPrimaryUnit(units);

      if (!isMounted) return;

      const fullName =
        `${owner.first_name ?? ''} ${owner.last_name ?? ''}`.trim() ||
        'Propriétaire';

      setProfile({
        fullName,
        buildingCode: primaryUnit?.building_code ?? null,
        apartmentNumber: primaryUnit?.apartment_number ?? null,
      });
      setProfileLoading(false);
    }

    loadProfile();

    return () => {
      isMounted = false;
    };
  }, [user]);

  return (
    <ScrollView
      style={styles.page}
      contentContainerStyle={styles.content}
    >
      <View style={styles.card}>
        <Text style={styles.brand}>MIRADOR GOLF 1</Text>
        <Text style={styles.title}>Connexion réussie</Text>
        <Text style={styles.subtitle}>Espace propriétaire</Text>

        {profileLoading ? (
          <ActivityIndicator style={styles.loader} color="#174b3d" />
        ) : profile ? (
          <View style={styles.profileBox}>
            <Text style={styles.profileName}>{profile.fullName}</Text>
            <Text style={styles.profileUnit}>
              {profile.buildingCode || profile.apartmentNumber
                ? `Bloc ${profile.buildingCode ?? '—'} · Appartement ${
                    profile.apartmentNumber ?? '—'
                  }`
                : 'Bâtiment et appartement non renseignés'}
            </Text>
          </View>
        ) : (
          <Text style={styles.profileMissing}>
            {profileError
              ? "Impossible de charger vos informations pour le moment."
              : 'Aucune information propriétaire disponible.'}
          </Text>
        )}

        <Pressable style={styles.button} onPress={() => signOut()}>
          <Text style={styles.buttonText}>Se déconnecter</Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  page: {
    flex: 1,
    backgroundColor: '#0b3028',
  },
  content: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: 22,
  },
  card: {
    padding: 26,
    borderRadius: 22,
    backgroundColor: '#ffffff',
  },
  brand: {
    color: '#30735e',
    fontWeight: '800',
    fontSize: 12,
    letterSpacing: 1.4,
  },
  title: {
    marginTop: 7,
    color: '#0b2f27',
    fontWeight: '800',
    fontSize: 26,
  },
  subtitle: {
    marginTop: 4,
    marginBottom: 20,
    color: '#6b7c75',
    fontSize: 14,
  },
  loader: {
    marginVertical: 20,
  },
  profileBox: {
    marginBottom: 24,
    padding: 16,
    borderRadius: 14,
    backgroundColor: '#f2f6f4',
  },
  profileName: {
    color: '#0b2f27',
    fontWeight: '700',
    fontSize: 17,
    marginBottom: 4,
  },
  profileUnit: {
    color: '#4b5d56',
    fontSize: 14,
  },
  profileMissing: {
    marginBottom: 24,
    color: '#6b7c75',
    fontSize: 14,
  },
  button: {
    minHeight: 54,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 11,
    backgroundColor: '#174b3d',
  },
  buttonText: {
    color: '#ffffff',
    fontWeight: '800',
    fontSize: 15,
  },
});
