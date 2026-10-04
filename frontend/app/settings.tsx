import Icon from "@react-native-vector-icons/material-design-icons";
import { useRouter } from "expo-router";
import { Pressable, ScrollView, Switch, Text, TextInput, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { useSession } from "@/src/store/session";
import { makeStyles, useTheme } from "@/src/theme";

const TRANSPORTS = ["UDP", "TCP", "TLS"] as const;

export default function Settings() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const styles = useStyles();
  const { colors } = useTheme();
  const { session, settings, updateSettings, signOut } = useSession();

  const handleSignOut = async () => {
    await signOut();
    router.replace("/sign-in");
  };

  return (
    <View style={[styles.root, { paddingTop: insets.top + 8 }]} testID="settings-screen">
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} hitSlop={10} testID="settings-close-button">
          <Icon name="close" size={26} color={colors.onSurface} />
        </Pressable>
        <Text style={styles.title}>Settings</Text>
        <View style={{ width: 26 }} />
      </View>

      <ScrollView contentContainerStyle={{ paddingBottom: insets.bottom + 32 }}>
        <Section label="Account">
          <Row label="Company" value={session?.companyCode ?? "—"} />
          <Row label="Extension" value={session?.extension ?? "—"} />
          <Row label="Server" value={session?.server ?? "—"} />
          <Row label="Status" value="Registered" valueColor={colors.success} />
        </Section>

        <Section label="SIP Transport">
          <View style={styles.segment}>
            {TRANSPORTS.map((t) => {
              const active = settings.transport === t;
              return (
                <Pressable
                  key={t}
                  onPress={() => updateSettings({ transport: t })}
                  style={[styles.segmentItem, active && styles.segmentActive]}
                  testID={`transport-${t}`}
                >
                  <Text style={[styles.segmentText, active && styles.segmentTextActive]}>{t}</Text>
                </Pressable>
              );
            })}
          </View>
          <InputRow
            label="Port"
            value={settings.port}
            onChangeText={(v) => updateSettings({ port: v })}
            keyboardType="number-pad"
            testID="input-port"
          />
          <SwitchRow
            label="SRTP (encrypt media)"
            value={settings.srtp}
            onValueChange={(v) => updateSettings({ srtp: v })}
            testID="switch-srtp"
          />
        </Section>

        <Section label="Voicemail">
          <InputRow
            label="Voicemail number"
            value={settings.voicemailNumber}
            onChangeText={(v) => updateSettings({ voicemailNumber: v })}
            testID="input-voicemail"
          />
        </Section>

        <Section label="Push gateway">
          <InputRow
            label="Host"
            value={settings.pushGateway}
            onChangeText={(v) => updateSettings({ pushGateway: v })}
            autoCapitalize="none"
            testID="input-push-gateway"
          />
          <Text style={styles.hint}>
            Enables background incoming calls via APNs VoIP push. Requires PBX hook on /notify.
          </Text>
        </Section>

        <Pressable onPress={handleSignOut} style={styles.signOut} testID="sign-out-button">
          <Icon name="logout" size={18} color={colors.error} />
          <Text style={styles.signOutText}>Sign out</Text>
        </Pressable>

        <Text style={styles.version}>N2IT Phone v1.0 (demo build)</Text>
      </ScrollView>
    </View>
  );
}

function Section({ label, children }: { label: string; children: React.ReactNode }) {
  const styles = useStyles();
  return (
    <View style={styles.section}>
      <Text style={styles.sectionLabel}>{label}</Text>
      <View style={styles.sectionCard}>{children}</View>
    </View>
  );
}

function Row({ label, value, valueColor }: { label: string; value: string; valueColor?: string }) {
  const styles = useStyles();
  const { colors } = useTheme();
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={[styles.rowValue, { color: valueColor ?? colors.onSurface }]}>{value}</Text>
    </View>
  );
}

function InputRow(props: React.ComponentProps<typeof TextInput> & { label: string }) {
  const styles = useStyles();
  const { colors } = useTheme();
  const { label, ...rest } = props;
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <TextInput {...rest} placeholderTextColor={colors.muted} style={styles.inlineInput} />
    </View>
  );
}

function SwitchRow({
  label,
  value,
  onValueChange,
  testID,
}: {
  label: string;
  value: boolean;
  onValueChange: (v: boolean) => void;
  testID?: string;
}) {
  const styles = useStyles();
  const { colors } = useTheme();
  return (
    <View style={styles.row}>
      <Text style={styles.rowLabel}>{label}</Text>
      <Switch
        value={value}
        onValueChange={onValueChange}
        trackColor={{ true: colors.brandPrimary, false: colors.border }}
        thumbColor={colors.onSurface}
        testID={testID}
      />
    </View>
  );
}

const useStyles = makeStyles((c) => ({
  root: { flex: 1, backgroundColor: c.surface, paddingHorizontal: 16 },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    marginBottom: 16,
  },
  title: { color: c.onSurface, fontSize: 20, fontWeight: "800" },
  section: { marginBottom: 20 },
  sectionLabel: {
    color: c.muted,
    fontSize: 12,
    letterSpacing: 1.5,
    textTransform: "uppercase",
    marginBottom: 8,
    paddingHorizontal: 4,
  },
  sectionCard: {
    backgroundColor: c.surfaceSecondary,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: c.border,
    overflow: "hidden",
  },
  row: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 16,
    paddingVertical: 14,
    borderBottomWidth: 0.5,
    borderBottomColor: c.divider,
    minHeight: 48,
  },
  rowLabel: { color: c.onSurfaceSecondary, fontSize: 14 },
  rowValue: { fontSize: 14, maxWidth: "60%", textAlign: "right" },
  inlineInput: {
    color: c.onSurface,
    fontSize: 14,
    textAlign: "right",
    flex: 1,
    marginLeft: 20,
    paddingVertical: 0,
  },
  segment: {
    flexDirection: "row",
    padding: 4,
    gap: 4,
    backgroundColor: c.surfaceTertiary,
    margin: 12,
    borderRadius: 10,
  },
  segmentItem: { flex: 1, paddingVertical: 8, alignItems: "center", borderRadius: 8 },
  segmentActive: { backgroundColor: c.brandPrimary },
  segmentText: { color: c.muted, fontSize: 13, fontWeight: "600" },
  segmentTextActive: { color: c.onBrandPrimary },
  hint: { color: c.muted, fontSize: 11, paddingHorizontal: 16, paddingBottom: 12 },
  signOut: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    backgroundColor: c.surfaceSecondary,
    paddingVertical: 14,
    borderRadius: 12,
    marginTop: 8,
    borderWidth: 1,
    borderColor: c.border,
  },
  signOutText: { color: c.error, fontSize: 15, fontWeight: "600" },
  version: { color: c.muted, fontSize: 11, textAlign: "center", marginTop: 20 },
}));
