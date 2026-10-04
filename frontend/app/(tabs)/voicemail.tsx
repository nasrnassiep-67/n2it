import Icon from "@react-native-vector-icons/material-design-icons";
import { Image } from "expo-image";
import { useRouter } from "expo-router";
import { useState } from "react";
import { FlatList, Pressable, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { VOICEMAILS, type Voicemail } from "@/src/data/mockData";
import { useSession } from "@/src/store/session";
import { formatDuration, formatRelative, initials } from "@/src/utils/format";
import { makeStyles, useTheme } from "@/src/theme";

export default function VoicemailScreen() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const styles = useStyles();
  const { colors } = useTheme();
  const { settings } = useSession();
  const [expanded, setExpanded] = useState<string | null>(null);
  const [playing, setPlaying] = useState<string | null>(null);

  const callNumber = (num: string, name = "") => {
    router.push({ pathname: "/call/[number]", params: { number: num, name } });
  };

  return (
    <View style={[styles.root, { paddingTop: insets.top }]} testID="voicemail-screen">
      <View style={styles.header}>
        <Text style={styles.title}>Voicemail</Text>
        <Pressable
          style={styles.callVmBtn}
          onPress={() => callNumber(settings.voicemailNumber, "Voicemail")}
          testID="call-voicemail-button"
        >
          <Icon name="phone" size={14} color={colors.onBrandPrimary} />
          <Text style={styles.callVmText}>Call voicemail</Text>
        </Pressable>
      </View>

      {VOICEMAILS.length === 0 ? (
        <View style={styles.empty} testID="voicemail-empty">
          <Icon name="voicemail" size={48} color={colors.muted} />
          <Text style={styles.emptyText}>No new voicemails</Text>
        </View>
      ) : (
        <FlatList
          data={VOICEMAILS}
          keyExtractor={(i) => i.id}
          contentContainerStyle={{ paddingBottom: 24, paddingTop: 8 }}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          renderItem={({ item }) => (
            <VoicemailRow
              item={item}
              expanded={expanded === item.id}
              playing={playing === item.id}
              onToggle={() => setExpanded((e) => (e === item.id ? null : item.id))}
              onPlayToggle={() => setPlaying((p) => (p === item.id ? null : item.id))}
              onCall={() => callNumber(item.number, item.name)}
            />
          )}
        />
      )}
    </View>
  );
}

function VoicemailRow({
  item,
  expanded,
  playing,
  onToggle,
  onPlayToggle,
  onCall,
}: {
  item: Voicemail;
  expanded: boolean;
  playing: boolean;
  onToggle: () => void;
  onPlayToggle: () => void;
  onCall: () => void;
}) {
  const styles = useStyles();
  const { colors } = useTheme();
  return (
    <View>
      <Pressable
        onPress={onToggle}
        style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.surfaceSecondary }]}
        testID={`voicemail-row-${item.id}`}
      >
        {!item.heard ? <View style={styles.unreadDot} /> : <View style={{ width: 8 }} />}
        {item.avatarUrl ? (
          <Image source={{ uri: item.avatarUrl }} style={styles.avatar} contentFit="cover" />
        ) : (
          <View style={[styles.avatar, styles.avatarPlaceholder]}>
            <Text style={styles.avatarInitials}>{initials(item.name)}</Text>
          </View>
        )}
        <View style={{ flex: 1, marginLeft: 12 }}>
          <Text style={styles.name}>{item.name}</Text>
          <Text style={styles.sub}>
            {item.number} • {formatRelative(item.timestamp)}
          </Text>
        </View>
        <Text style={styles.dur}>{formatDuration(item.durationSec)}</Text>
      </Pressable>
      {expanded && (
        <View style={styles.playerBar}>
          <Pressable onPress={onPlayToggle} style={styles.playBtn} testID={`voicemail-play-${item.id}`}>
            <Icon name={playing ? "pause" : "play"} size={22} color={colors.onBrandPrimary} />
          </Pressable>
          <View style={styles.slider}>
            <View style={[styles.sliderFill, { width: playing ? "60%" : "0%" }]} />
          </View>
          <Pressable onPress={onCall} style={styles.callBtn} testID={`voicemail-callback-${item.id}`}>
            <Icon name="phone" size={20} color={colors.success} />
          </Pressable>
        </View>
      )}
    </View>
  );
}

const useStyles = makeStyles((c) => ({
  root: { flex: 1, backgroundColor: c.surface },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 12,
  },
  title: { color: c.onSurface, fontSize: 28, fontWeight: "800" },
  callVmBtn: {
    flexDirection: "row",
    alignItems: "center",
    gap: 6,
    backgroundColor: c.brandPrimary,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 999,
  },
  callVmText: { color: c.onBrandPrimary, fontSize: 13, fontWeight: "600" },
  sep: { height: 0.5, backgroundColor: c.divider, marginLeft: 76 },
  row: { flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 12 },
  unreadDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: c.brand, marginRight: 8 },
  avatar: { width: 44, height: 44, borderRadius: 22, backgroundColor: c.surfaceTertiary },
  avatarPlaceholder: { alignItems: "center", justifyContent: "center" },
  avatarInitials: { color: c.onSurface, fontSize: 14, fontWeight: "700" },
  name: { color: c.onSurface, fontSize: 16, fontWeight: "600" },
  sub: { color: c.muted, fontSize: 12, marginTop: 2 },
  dur: { color: c.muted, fontSize: 12 },
  playerBar: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    paddingHorizontal: 24,
    paddingBottom: 14,
    paddingTop: 4,
    backgroundColor: c.surfaceSecondary,
  },
  playBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: c.brandPrimary,
    alignItems: "center",
    justifyContent: "center",
  },
  slider: { flex: 1, height: 3, backgroundColor: c.border, borderRadius: 2, overflow: "hidden" },
  sliderFill: { height: "100%", backgroundColor: c.brand },
  callBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: c.success,
    alignItems: "center",
    justifyContent: "center",
  },
  empty: { flex: 1, alignItems: "center", justifyContent: "center", gap: 10 },
  emptyText: { color: c.muted, fontSize: 14 },
}));
