import { useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

import * as Crypto from 'expo-crypto';

import { supabase } from '../lib/supabase';

function normalizeMoroccoPhone(value: string) {
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

async function buildInternalLoginEmail(phoneE164: string) {
  const digest = await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    `mirador-golf-1:${phoneE164}`
  );

  return `owner-${digest.slice(0, 40)}@auth.mirador-golf.invalid`;
}

export default function LoginScreen() {
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);

  async function handleLogin() {
    const normalizedPhone = normalizeMoroccoPhone(phone);

    if (!normalizedPhone) {
      Alert.alert(
        'Téléphone invalide',
        'Saisissez un numéro marocain valide, par exemple 06XXXXXXXX.'
      );
      return;
    }

    if (!password) {
      Alert.alert(
        'Mot de passe requis',
        'Veuillez saisir votre mot de passe.'
      );
      return;
    }

    try {
      setLoading(true);

      const loginEmail =
        await buildInternalLoginEmail(normalizedPhone);

      const { error } =
        await supabase.auth.signInWithPassword({
          email: loginEmail,
          password,
        });

      if (error) {
        Alert.alert(
          'Connexion impossible',
          'Téléphone ou mot de passe incorrect.'
        );
        return;
      }

      Alert.alert(
        'Connexion réussie',
        'Bienvenue dans MIRADOR Golf.'
      );
    } catch {
      Alert.alert(
        'Erreur',
        'Une erreur inattendue est survenue.'
      );
    } finally {
      setLoading(false);
    }
  }

  return (
    <KeyboardAvoidingView
      style={styles.page}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <View style={styles.card}>
        <View style={styles.logo}>
          <Text style={styles.logoText}>MG</Text>
        </View>

        <Text style={styles.brand}>MIRADOR GOLF 1</Text>

        <Text style={styles.title}>
          Espace propriétaire
        </Text>

        <Text style={styles.subtitle}>
          Connectez-vous avec votre numéro de téléphone.
        </Text>

        <Text style={styles.label}>
          Numéro de téléphone
        </Text>

        <TextInput
          value={phone}
          onChangeText={setPhone}
          placeholder="06 XX XX XX XX"
          keyboardType="phone-pad"
          textContentType="telephoneNumber"
          editable={!loading}
          style={styles.input}
        />

        <Text style={styles.label}>
          Mot de passe
        </Text>

        <TextInput
          value={password}
          onChangeText={setPassword}
          placeholder="Votre mot de passe"
          secureTextEntry
          textContentType="password"
          editable={!loading}
          style={styles.input}
          onSubmitEditing={handleLogin}
        />

        <Pressable
          onPress={handleLogin}
          disabled={loading}
          style={[
            styles.button,
            loading && styles.buttonDisabled,
          ]}
        >
          {loading ? (
            <ActivityIndicator color="#ffffff" />
          ) : (
            <Text style={styles.buttonText}>
              Se connecter
            </Text>
          )}
        </Pressable>

        <Text style={styles.security}>
          Connexion sécurisée • MIRADOR Golf
        </Text>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  page: {
    flex: 1,
    justifyContent: 'center',
    padding: 22,
    backgroundColor: '#0b3028',
  },
  card: {
    padding: 26,
    borderRadius: 22,
    backgroundColor: '#ffffff',
  },
  logo: {
    width: 56,
    height: 56,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 16,
    backgroundColor: '#174b3d',
    marginBottom: 16,
  },
  logoText: {
    color: '#ffffff',
    fontWeight: '900',
    fontSize: 18,
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
    fontSize: 29,
  },
  subtitle: {
    marginTop: 8,
    marginBottom: 28,
    color: '#6b7c75',
    fontSize: 14,
  },
  label: {
    marginBottom: 7,
    color: '#344a42',
    fontSize: 13,
    fontWeight: '700',
  },
  input: {
    minHeight: 52,
    marginBottom: 18,
    paddingHorizontal: 14,
    borderWidth: 1,
    borderColor: '#d9e3df',
    borderRadius: 11,
    color: '#16352b',
    backgroundColor: '#ffffff',
    fontSize: 15,
  },
  button: {
    minHeight: 54,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 11,
    backgroundColor: '#174b3d',
  },
  buttonDisabled: {
    opacity: 0.55,
  },
  buttonText: {
    color: '#ffffff',
    fontWeight: '800',
    fontSize: 15,
  },
  security: {
    marginTop: 22,
    textAlign: 'center',
    color: '#85938e',
    fontSize: 11,
  },
});