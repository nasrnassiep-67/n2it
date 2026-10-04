import { Image } from "expo-image";
import { LinearGradient } from "expo-linear-gradient";
import { useRouter } from "expo-router";
import { useState } from "react";
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { SIGN_IN_BG } from "@/src/data/mockData";
import { useSession } from "@/src/store/session";
import { makeStyles, useTheme } from "@/src/theme";

export default function SignIn() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const styles = useStyles();
  const { colors } = useTheme();
  const { signIn } = useSession();

  const [companyCode, setCompanyCode] = useState("");
  const [extension, setExtension] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const server = companyCode ? `${companyCode.toLowerCase().trim()}.voip.n2it.co.za` : "<code>.voip.n2it.co.za";

  const handleSignIn = async () => {
    setError(null);
    if (!companyCode.trim() || !extension.trim() || !password.trim()) {
      setError("Please fill in company code, extension and password.");
      return;
    }
    setLoading(true);
    // simulate SIP REGISTER
    await new Promise((r) => setTimeout(r, 800));
    await signIn(companyCode.trim().toLowerCase(), extension.trim());
    setLoading(false);
    router.replace("/(tabs)");
  };

  return (
    <View style={styles.root} testID="sign-in-screen">
      <Image source={{ uri: SIGN_IN_BG }} style={styles.bg} contentFit="cover" />
      <LinearGradient
        colors={["rgba(18,18,18,0.6)", "rgba(18,18,18,0.95)", "#121212"]}
        locations={[0, 0.5, 1]}
        style={styles.scrim}
      />
      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === "ios" ? "padding" : "height"}
      >
        <ScrollView
          contentContainerStyle={[
            styles.scroll,
            { paddingTop: insets.top + 48, paddingBottom: insets.bottom + 24 },
          ]}
          keyboardShouldPersistTaps="handled"
        >
          <View style={styles.brandRow}>
            <View style={styles.logoDot} />
            <Text style={styles.brandText}>N2IT PHONE</Text>
          </View>
          <Text style={styles.heading}>Sign in to your extension</Text>
          <Text style={styles.sub}>Connect to {server}</Text>

          <View style={styles.form}>
            <Field
              label="Company code"
              value={companyCode}
              onChangeText={setCompanyCode}
              placeholder="n2it"
              autoCapitalize="none"
              testID="input-company-code"
            />
            <Field
              label="Extension"
              value={extension}
              onChangeText={setExtension}
              placeholder="1021"
              keyboardType="number-pad"
              testID="input-extension"
            />
            <Field
              label="Password"
              value={password}
              onChangeText={setPassword}
              placeholder="••••••••"
              secureTextEntry
              testID="input-password"
            />

            {error ? (
              <Text style={styles.error} testID="sign-in-error">{error}</Text>
            ) : null}

            <Pressable
              onPress={handleSignIn}
              disabled={loading}
              style={({ pressed }) => [styles.cta, pressed && { opacity: 0.9 }]}
              testID="sign-in-button"
            >
              {loading ? (
                <ActivityIndicator color={colors.onBrandPrimary} />
              ) : (
                <Text style={styles.ctaText}>Sign in</Text>
              )}
            </Pressable>

            <Text style={styles.hint}>
              Tip: any company code and extension works in this demo build.
            </Text>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </View>
  );
}

function Field(props: React.ComponentProps<typeof TextInput> & { label: string }) {
  const styles = useStyles();
  const { colors } = useTheme();
  const { label, ...rest } = props;
  return (
    <View style={styles.field}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <TextInput
        {...rest}
        placeholderTextColor={colors.muted}
        style={styles.input}
      />
    </View>
  );
}

const useStyles = makeStyles((c) => ({
  root: { flex: 1, backgroundColor: c.surface },
  bg: { ...StyleSheetAbs(), opacity: 0.5 },
  scrim: { ...StyleSheetAbs() },
  scroll: { paddingHorizontal: 24, flexGrow: 1, justifyContent: "flex-start" },
  brandRow: { flexDirection: "row", alignItems: "center", gap: 10, marginBottom: 32 },
  logoDot: { width: 14, height: 14, borderRadius: 7, backgroundColor: c.brand },
  brandText: { color: c.onSurface, fontSize: 14, letterSpacing: 2, fontWeight: "700" },
  heading: { color: c.onSurface, fontSize: 32, fontWeight: "800", marginBottom: 8 },
  sub: { color: c.muted, fontSize: 14, marginBottom: 28 },
  form: { gap: 14 },
  field: { gap: 6 },
  fieldLabel: { color: c.muted, fontSize: 12, letterSpacing: 1, textTransform: "uppercase" },
  input: {
    backgroundColor: c.surfaceSecondary,
    borderWidth: 1,
    borderColor: c.border,
    color: c.onSurface,
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderRadius: 12,
    fontSize: 16,
  },
  error: { color: c.error, fontSize: 13 },
  cta: {
    marginTop: 10,
    backgroundColor: c.brandPrimary,
    paddingVertical: 16,
    borderRadius: 999,
    alignItems: "center",
  },
  ctaText: { color: c.onBrandPrimary, fontSize: 16, fontWeight: "700", letterSpacing: 0.5 },
  hint: { color: c.muted, fontSize: 12, textAlign: "center", marginTop: 12 },
}));

function StyleSheetAbs() {
  return { position: "absolute" as const, top: 0, left: 0, right: 0, bottom: 0 };
}
