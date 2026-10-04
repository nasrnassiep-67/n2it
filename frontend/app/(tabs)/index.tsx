import Icon from "@react-native-vector-icons/material-design-icons";
import * as Haptics from "expo-haptics";
import { useRouter } from "expo-router";
import { useState } from "react";
import { Platform, Pressable, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { useSession } from "@/src/store/session";
import { makeStyles, useTheme } from "@/src/theme";

const KEYS: { label: string; sub?: string }[] = [
  { label: "1", sub: " " },
  { label: "2", sub: "ABC" },
  { label: "3", sub: "DEF" },
  { label: "4", sub: "GHI" },
  { label: "5", sub: "JKL" },
  { label: "6", sub: "MNO" },
  { label: "7", sub: "PQRS" },
  { label: "8", sub: "TUV" },
  { label: "9", sub: "WXYZ" },
  { label: "*", sub: "" },
  { label: "0", sub: "+" },
  { label: "#", sub: "" },
];

export default function Keypad() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const styles = useStyles();
  const { colors } = useTheme();
  const { session } = useSession();
  const [input, setInput] = useState("");

  const haptic = (style: Haptics.ImpactFeedbackStyle = Haptics.ImpactFeedbackStyle.Light) => {
    if (Platform.OS !== "web") Haptics.impactAsync(style).catch(() => {});
  };

  const press = (k: string) => {
    haptic();
    setInput((v) => (v.length < 20 ? v + k : v));
  };
  const back = () => {
    haptic();
    setInput((v) => v.slice(0, -1));
  };
  const longBack = () => {
    haptic(Haptics.ImpactFeedbackStyle.Medium);
    setInput("");
  };
  const call = () => {
    if (!input) return;
    haptic(Haptics.ImpactFeedbackStyle.Medium);
    router.push({ pathname: "/call/[number]", params: { number: input, name: "" } });
  };

  return (
    <View style={[styles.root, { paddingTop: insets.top }]} testID="keypad-screen">
      <View style={styles.header}>
        <View style={styles.statusPill}>
          <View style={[styles.statusDot, { backgroundColor: session ? colors.success : colors.error }]} />
          <Text style={styles.statusText} testID="registration-status">
            {session ? `${session.extension} • Registered` : "Not registered"}
          </Text>
        </View>
        <Pressable
          onPress={() => router.push("/settings")}
          hitSlop={10}
          style={styles.iconBtn}
          testID="open-settings-button"
        >
          <Icon name="cog-outline" size={24} color={colors.onSurface} />
        </Pressable>
      </View>

      <View style={styles.displayWrap}>
        <Text
          style={styles.display}
          numberOfLines={1}
          adjustsFontSizeToFit
          testID="keypad-display"
        >
          {input || " "}
        </Text>
        {input ? (
          <Text style={styles.subDisplay}>Tap call to dial</Text>
        ) : (
          <Text style={styles.subDisplay}>Enter a number or extension</Text>
        )}
      </View>

      <View style={styles.pad}>
        {KEYS.map((k) => (
          <Pressable
            key={k.label}
            onPress={() => press(k.label)}
            onLongPress={k.label === "0" ? () => press("+") : undefined}
            style={({ pressed }) => [styles.key, pressed && styles.keyPressed]}
            testID={`key-${k.label}`}
          >
            <Text style={styles.keyLabel}>{k.label}</Text>
            {k.sub ? <Text style={styles.keySub}>{k.sub}</Text> : null}
          </Pressable>
        ))}
      </View>

      <View style={styles.actions}>
        <View style={styles.sideBtn} />
        <Pressable
          onPress={call}
          disabled={!input}
          style={({ pressed }) => [
            styles.callBtn,
            !input && { opacity: 0.4 },
            pressed && { transform: [{ scale: 0.96 }] },
          ]}
          testID="call-button"
        >
          <Icon name="phone" size={30} color={colors.onSuccess} />
        </Pressable>
        <Pressable
          onPress={back}
          onLongPress={longBack}
          disabled={!input}
          style={({ pressed }) => [styles.sideBtn, pressed && { opacity: 0.6 }]}
          testID="backspace-button"
        >
          {input ? <Icon name="backspace-outline" size={26} color={colors.onSurface} /> : null}
        </Pressable>
      </View>
    </View>
  );
}

const useStyles = makeStyles((c) => ({
  root: { flex: 1, backgroundColor: c.surface, paddingHorizontal: 16 },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingVertical: 10,
  },
  statusPill: {
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    backgroundColor: c.surfaceSecondary,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 999,
    borderWidth: 0.5,
    borderColor: c.border,
  },
  statusDot: { width: 8, height: 8, borderRadius: 4 },
  statusText: { color: c.onSurfaceSecondary, fontSize: 12, fontWeight: "600" },
  iconBtn: { padding: 6 },
  displayWrap: { paddingVertical: 20, alignItems: "center", minHeight: 100, justifyContent: "center" },
  display: { color: c.onSurface, fontSize: 44, fontWeight: "300", letterSpacing: 2 },
  subDisplay: { color: c.muted, fontSize: 12, marginTop: 6 },
  pad: {
    flexDirection: "row",
    flexWrap: "wrap",
    justifyContent: "space-between",
    rowGap: 16,
    paddingHorizontal: 8,
    marginTop: 8,
  },
  key: {
    width: "30%",
    aspectRatio: 1,
    maxHeight: 76,
    borderRadius: 999,
    backgroundColor: c.surfaceTertiary,
    alignItems: "center",
    justifyContent: "center",
  },
  keyPressed: { backgroundColor: c.borderStrong, transform: [{ scale: 0.96 }] },
  keyLabel: { color: c.onSurface, fontSize: 30, fontWeight: "400" },
  keySub: { color: c.muted, fontSize: 10, letterSpacing: 2, marginTop: 2 },
  actions: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 24,
    marginTop: 20,
    marginBottom: 8,
  },
  sideBtn: { width: 60, height: 60, alignItems: "center", justifyContent: "center" },
  callBtn: {
    width: 72,
    height: 72,
    borderRadius: 999,
    backgroundColor: c.success,
    alignItems: "center",
    justifyContent: "center",
    shadowColor: c.success,
    shadowOpacity: 0.4,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 4 },
  },
}));
