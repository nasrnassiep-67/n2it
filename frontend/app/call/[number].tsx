import Icon from "@react-native-vector-icons/material-design-icons";
import * as Haptics from "expo-haptics";
import { LinearGradient } from "expo-linear-gradient";
import { useLocalSearchParams, useRouter } from "expo-router";
import { useEffect, useRef, useState } from "react";
import { Platform, Pressable, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { formatDuration, initials } from "@/src/utils/format";
import { makeStyles, useTheme } from "@/src/theme";

type Phase = "dialing" | "connected" | "ended";

export default function CallScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const styles = useStyles();
  const { colors } = useTheme();
  const { number, name } = useLocalSearchParams<{ number: string; name?: string }>();

  const [phase, setPhase] = useState<Phase>("dialing");
  const [sec, setSec] = useState(0);
  const [mute, setMute] = useState(false);
  const [speaker, setSpeaker] = useState(false);
  const [hold, setHold] = useState(false);
  const [showPad, setShowPad] = useState(false);
  const [padInput, setPadInput] = useState("");
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // simulate connect after 1.8s
  useEffect(() => {
    const t = setTimeout(() => setPhase("connected"), 1800);
    return () => clearTimeout(t);
  }, []);

  useEffect(() => {
    if (phase === "connected" && !hold) {
      timerRef.current = setInterval(() => setSec((s) => s + 1), 1000);
      return () => {
        if (timerRef.current) clearInterval(timerRef.current);
      };
    }
    if (timerRef.current) clearInterval(timerRef.current);
    return () => {};
  }, [phase, hold]);

  const hapticEnd = () => {
    if (Platform.OS !== "web") Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy).catch(() => {});
  };
  const hapticTap = () => {
    if (Platform.OS !== "web") Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});
  };

  const endCall = () => {
    hapticEnd();
    setPhase("ended");
    if (timerRef.current) clearInterval(timerRef.current);
    setTimeout(() => router.back(), 350);
  };

  const displayName = name || "Unknown";

  return (
    <View style={styles.root} testID="call-screen">
      <LinearGradient
        colors={[colors.surfaceTertiary, colors.surface, "#000"]}
        locations={[0, 0.4, 1]}
        style={{ position: "absolute", inset: 0 }}
      />
      <View style={[styles.top, { paddingTop: insets.top + 20 }]}>
        <View style={styles.avatarWrap}>
          <View style={styles.avatarBig}>
            <Text style={styles.avatarInitials}>{initials(displayName)}</Text>
          </View>
          {phase === "dialing" && <View style={styles.ring} />}
        </View>
        <Text style={styles.name} numberOfLines={1}>
          {displayName}
        </Text>
        <Text style={styles.number} numberOfLines={1}>
          {number}
        </Text>
        <Text
          style={[
            styles.statusText,
            {
              color:
                phase === "connected"
                  ? colors.success
                  : phase === "ended"
                    ? colors.error
                    : colors.muted,
            },
          ]}
          testID="call-status"
        >
          {phase === "dialing" && "Dialing…"}
          {phase === "connected" && (hold ? "On hold" : formatDuration(sec) || "0:00")}
          {phase === "ended" && "Call ended"}
        </Text>
      </View>

      {showPad ? (
        <View style={styles.inlinePad} testID="in-call-pad">
          <Text style={styles.inlinePadDisplay}>{padInput || " "}</Text>
          <View style={styles.inlinePadKeys}>
            {["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"].map((k) => (
              <Pressable
                key={k}
                onPress={() => {
                  hapticTap();
                  setPadInput((v) => v + k);
                }}
                style={styles.inlineKey}
                testID={`in-call-key-${k}`}
              >
                <Text style={styles.inlineKeyLabel}>{k}</Text>
              </Pressable>
            ))}
          </View>
          <Pressable
            onPress={() => setShowPad(false)}
            style={styles.hidePadBtn}
            testID="hide-pad-button"
          >
            <Text style={styles.hidePadText}>Hide keypad</Text>
          </Pressable>
        </View>
      ) : (
        <View style={styles.controls}>
          <ControlBtn
            icon={mute ? "microphone-off" : "microphone"}
            label="Mute"
            active={mute}
            onPress={() => {
              hapticTap();
              setMute((v) => !v);
            }}
            testID="btn-mute"
          />
          <ControlBtn
            icon="dialpad"
            label="Keypad"
            onPress={() => {
              hapticTap();
              setShowPad(true);
            }}
            testID="btn-keypad"
          />
          <ControlBtn
            icon={speaker ? "volume-high" : "volume-medium"}
            label="Speaker"
            active={speaker}
            onPress={() => {
              hapticTap();
              setSpeaker((v) => !v);
            }}
            testID="btn-speaker"
          />
          <ControlBtn icon="phone-plus" label="Add call" onPress={hapticTap} testID="btn-add" />
          <ControlBtn
            icon={hold ? "play" : "pause"}
            label={hold ? "Resume" : "Hold"}
            active={hold}
            onPress={() => {
              hapticTap();
              setHold((v) => !v);
            }}
            testID="btn-hold"
          />
          <ControlBtn icon="phone-forward" label="Transfer" onPress={hapticTap} testID="btn-transfer" />
        </View>
      )}

      <View style={[styles.endWrap, { paddingBottom: insets.bottom + 24 }]}>
        <Pressable
          onPress={endCall}
          style={({ pressed }) => [styles.endBtn, pressed && { transform: [{ scale: 0.96 }] }]}
          testID="end-call-button"
        >
          <Icon name="phone-hangup" size={32} color={colors.onError} />
        </Pressable>
      </View>
    </View>
  );
}

function ControlBtn({
  icon,
  label,
  active,
  onPress,
  testID,
}: {
  icon: string;
  label: string;
  active?: boolean;
  onPress: () => void;
  testID?: string;
}) {
  const styles = useStyles();
  const { colors } = useTheme();
  return (
    <View style={styles.ctrlCell}>
      <Pressable
        onPress={onPress}
        style={({ pressed }) => [
          styles.ctrlBtn,
          active && { backgroundColor: colors.onSurface },
          pressed && { opacity: 0.8 },
        ]}
        testID={testID}
      >
        <Icon
          name={icon as any}
          size={28}
          color={active ? colors.surface : colors.onSurface}
        />
      </Pressable>
      <Text style={styles.ctrlLabel}>{label}</Text>
    </View>
  );
}

const useStyles = makeStyles((c) => ({
  root: { flex: 1, backgroundColor: c.surface },
  top: { alignItems: "center", paddingHorizontal: 24, gap: 8 },
  avatarWrap: { width: 128, height: 128, alignItems: "center", justifyContent: "center", marginBottom: 20 },
  avatarBig: {
    width: 112,
    height: 112,
    borderRadius: 56,
    backgroundColor: c.surfaceTertiary,
    alignItems: "center",
    justifyContent: "center",
  },
  avatarInitials: { color: c.onSurface, fontSize: 36, fontWeight: "700" },
  ring: {
    position: "absolute",
    width: 128,
    height: 128,
    borderRadius: 64,
    borderWidth: 2,
    borderColor: c.brand,
    opacity: 0.5,
  },
  name: { color: c.onSurface, fontSize: 28, fontWeight: "700" },
  number: { color: c.muted, fontSize: 15 },
  statusText: { fontSize: 14, marginTop: 6, fontWeight: "600" },
  controls: {
    flex: 1,
    flexDirection: "row",
    flexWrap: "wrap",
    paddingHorizontal: 24,
    marginTop: 36,
    rowGap: 24,
    columnGap: 0,
    justifyContent: "space-between",
  },
  ctrlCell: { width: "30%", alignItems: "center", gap: 8 },
  ctrlBtn: {
    width: 72,
    height: 72,
    borderRadius: 36,
    backgroundColor: c.surfaceSecondary,
    borderWidth: 1,
    borderColor: c.border,
    alignItems: "center",
    justifyContent: "center",
  },
  ctrlLabel: { color: c.onSurface, fontSize: 12 },
  inlinePad: { flex: 1, paddingHorizontal: 24, marginTop: 24 },
  inlinePadDisplay: {
    color: c.onSurface,
    fontSize: 28,
    textAlign: "center",
    letterSpacing: 2,
    marginBottom: 12,
    minHeight: 36,
  },
  inlinePadKeys: {
    flexDirection: "row",
    flexWrap: "wrap",
    justifyContent: "space-between",
    rowGap: 12,
  },
  inlineKey: {
    width: "30%",
    aspectRatio: 1.4,
    maxHeight: 60,
    borderRadius: 999,
    backgroundColor: c.surfaceTertiary,
    alignItems: "center",
    justifyContent: "center",
  },
  inlineKeyLabel: { color: c.onSurface, fontSize: 26 },
  hidePadBtn: { alignSelf: "center", marginTop: 16, padding: 10 },
  hidePadText: { color: c.brand, fontSize: 14, fontWeight: "600" },
  endWrap: { alignItems: "center", marginTop: 12 },
  endBtn: {
    width: 72,
    height: 72,
    borderRadius: 36,
    backgroundColor: c.error,
    alignItems: "center",
    justifyContent: "center",
    shadowColor: c.error,
    shadowOpacity: 0.4,
    shadowRadius: 16,
    shadowOffset: { width: 0, height: 4 },
  },
}));
