import Icon from "@react-native-vector-icons/material-design-icons";
import { LinearGradient } from "expo-linear-gradient";
import { useRouter } from "expo-router";
import { Pressable, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { initials } from "@/src/utils/format";
import { makeStyles, useTheme } from "@/src/theme";

// Demo "incoming call" screen (not wired to any real SIP push).
export default function Incoming() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const styles = useStyles();
  const { colors } = useTheme();

  const callerName = "Nasr Patel";
  const callerNumber = "1021";

  return (
    <View style={styles.root} testID="incoming-screen">
      <LinearGradient
        colors={[colors.surfaceTertiary, colors.surface, "#000"]}
        locations={[0, 0.5, 1]}
        style={{ position: "absolute", inset: 0 }}
      />
      <View style={[styles.top, { paddingTop: insets.top + 60 }]}>
        <Text style={styles.label}>N2IT Phone — incoming call</Text>
        <View style={styles.avatar}>
          <Text style={styles.avatarInitials}>{initials(callerName)}</Text>
        </View>
        <Text style={styles.name}>{callerName}</Text>
        <Text style={styles.number}>{callerNumber}</Text>
      </View>

      <View style={[styles.actions, { paddingBottom: insets.bottom + 32 }]}>
        <View style={styles.actionCell}>
          <Pressable
            onPress={() => router.back()}
            style={[styles.actionBtn, { backgroundColor: colors.error }]}
            testID="decline-button"
          >
            <Icon name="phone-hangup" size={30} color={colors.onError} />
          </Pressable>
          <Text style={styles.actionLabel}>Decline</Text>
        </View>
        <View style={styles.actionCell}>
          <Pressable
            onPress={() =>
              router.replace({ pathname: "/call/[number]", params: { number: callerNumber, name: callerName } })
            }
            style={[styles.actionBtn, { backgroundColor: colors.success }]}
            testID="accept-button"
          >
            <Icon name="phone" size={30} color={colors.onSuccess} />
          </Pressable>
          <Text style={styles.actionLabel}>Accept</Text>
        </View>
      </View>
    </View>
  );
}

const useStyles = makeStyles((c) => ({
  root: { flex: 1, backgroundColor: c.surface },
  top: { alignItems: "center", paddingHorizontal: 24, flex: 1 },
  label: { color: c.muted, fontSize: 12, letterSpacing: 2, textTransform: "uppercase", marginBottom: 20 },
  avatar: {
    width: 128,
    height: 128,
    borderRadius: 64,
    backgroundColor: c.surfaceTertiary,
    alignItems: "center",
    justifyContent: "center",
    marginBottom: 24,
  },
  avatarInitials: { color: c.onSurface, fontSize: 44, fontWeight: "700" },
  name: { color: c.onSurface, fontSize: 32, fontWeight: "700" },
  number: { color: c.muted, fontSize: 16, marginTop: 4 },
  actions: {
    flexDirection: "row",
    justifyContent: "space-around",
    paddingHorizontal: 40,
  },
  actionCell: { alignItems: "center", gap: 10 },
  actionBtn: {
    width: 76,
    height: 76,
    borderRadius: 38,
    alignItems: "center",
    justifyContent: "center",
  },
  actionLabel: { color: c.onSurface, fontSize: 13, fontWeight: "600" },
}));
