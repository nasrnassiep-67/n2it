import Icon from "@react-native-vector-icons/material-design-icons";
import { Image } from "expo-image";
import { useRouter } from "expo-router";
import { useState } from "react";
import { FlatList, Pressable, ScrollView, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { RECENTS, type CallDirection, type RecentCall } from "@/src/data/mockData";
import { formatDuration, formatRelative, initials } from "@/src/utils/format";
import { makeStyles, useTheme } from "@/src/theme";

type Filter = "all" | "missed";

const FILTERS: { key: Filter; label: string }[] = [
  { key: "all", label: "All" },
  { key: "missed", label: "Missed" },
];

export default function Recents() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const styles = useStyles();
  const { colors } = useTheme();
  const [filter, setFilter] = useState<Filter>("all");

  const data = filter === "missed" ? RECENTS.filter((r) => r.direction === "missed") : RECENTS;

  return (
    <View style={[styles.root, { paddingTop: insets.top }]} testID="recents-screen">
      <View style={styles.header}>
        <Text style={styles.title}>Recents</Text>
        <Pressable style={styles.editBtn} testID="recents-edit-button">
          <Text style={styles.editText}>Edit</Text>
        </Pressable>
      </View>

      <View style={styles.chipRowWrap}>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chipRow}
        >
          {FILTERS.map((f) => {
            const active = f.key === filter;
            return (
              <Pressable
                key={f.key}
                onPress={() => setFilter(f.key)}
                style={[styles.chip, active && styles.chipActive]}
                testID={`recents-filter-${f.key}`}
              >
                <Text style={[styles.chipText, active && styles.chipTextActive]}>{f.label}</Text>
              </Pressable>
            );
          })}
        </ScrollView>
      </View>

      {data.length === 0 ? (
        <View style={styles.empty} testID="recents-empty">
          <Icon name="phone-missed" size={48} color={colors.muted} />
          <Text style={styles.emptyText}>No recent calls</Text>
        </View>
      ) : (
        <FlatList
          data={data}
          keyExtractor={(i) => i.id}
          contentContainerStyle={{ paddingBottom: 24 }}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
          renderItem={({ item }) => (
            <RecentRow
              item={item}
              onPress={() =>
                router.push({ pathname: "/call/[number]", params: { number: item.number, name: item.name } })
              }
            />
          )}
        />
      )}
    </View>
  );
}

function RecentRow({ item, onPress }: { item: RecentCall; onPress: () => void }) {
  const styles = useStyles();
  const { colors } = useTheme();
  const missed = item.direction === "missed";
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.surfaceSecondary }]}
      testID={`recent-row-${item.id}`}
    >
      {item.avatarUrl ? (
        <Image source={{ uri: item.avatarUrl }} style={styles.avatar} contentFit="cover" />
      ) : (
        <View style={[styles.avatar, styles.avatarPlaceholder]}>
          <Text style={styles.avatarInitials}>{initials(item.name)}</Text>
        </View>
      )}
      <View style={{ flex: 1, marginLeft: 12 }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
          <DirectionIcon direction={item.direction} />
          <Text
            numberOfLines={1}
            style={[styles.name, { color: missed ? colors.error : colors.onSurface }]}
          >
            {item.name}
          </Text>
        </View>
        <Text style={styles.sub}>
          {item.number}
          {item.durationSec ? ` • ${formatDuration(item.durationSec)}` : ""}
        </Text>
      </View>
      <Text style={styles.time}>{formatRelative(item.timestamp)}</Text>
      <Pressable
        onPress={onPress}
        hitSlop={10}
        style={styles.infoBtn}
        testID={`recent-call-${item.id}`}
      >
        <Icon name="information-outline" size={22} color={colors.brand} />
      </Pressable>
    </Pressable>
  );
}

function DirectionIcon({ direction }: { direction: CallDirection }) {
  const { colors } = useTheme();
  if (direction === "missed") return <Icon name="phone-missed" size={14} color={colors.error} />;
  if (direction === "incoming") return <Icon name="phone-incoming" size={14} color={colors.success} />;
  return <Icon name="phone-outgoing" size={14} color={colors.muted} />;
}

const useStyles = makeStyles((c) => ({
  root: { flex: 1, backgroundColor: c.surface },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 16,
    paddingTop: 8,
    paddingBottom: 4,
  },
  title: { color: c.onSurface, fontSize: 28, fontWeight: "800" },
  editBtn: { padding: 6 },
  editText: { color: c.brand, fontSize: 15, fontWeight: "600" },
  chipRowWrap: { height: 56, justifyContent: "center" },
  chipRow: { gap: 8, paddingHorizontal: 16, alignItems: "center" },
  chip: {
    flexShrink: 0,
    height: 36,
    paddingHorizontal: 16,
    borderRadius: 999,
    backgroundColor: c.surfaceSecondary,
    borderWidth: 1,
    borderColor: c.border,
    alignItems: "center",
    justifyContent: "center",
  },
  chipActive: { backgroundColor: c.brandTertiary, borderColor: c.brand },
  chipText: { color: c.onSurfaceSecondary, fontSize: 13, fontWeight: "600" },
  chipTextActive: { color: c.onBrandTertiary },
  sep: { height: 0.5, backgroundColor: c.divider, marginLeft: 76 },
  row: {
    flexDirection: "row",
    alignItems: "center",
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  avatar: { width: 44, height: 44, borderRadius: 22, backgroundColor: c.surfaceTertiary },
  avatarPlaceholder: { alignItems: "center", justifyContent: "center" },
  avatarInitials: { color: c.onSurface, fontSize: 14, fontWeight: "700" },
  name: { fontSize: 16, fontWeight: "600", flexShrink: 1 },
  sub: { color: c.muted, fontSize: 12, marginTop: 2 },
  time: { color: c.muted, fontSize: 12, marginRight: 6 },
  infoBtn: { padding: 6 },
  empty: { flex: 1, alignItems: "center", justifyContent: "center", gap: 10 },
  emptyText: { color: c.muted, fontSize: 14 },
}));
