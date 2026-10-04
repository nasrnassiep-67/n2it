import Icon from "@react-native-vector-icons/material-design-icons";
import { Image } from "expo-image";
import { useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { FlatList, Pressable, ScrollView, SectionList, Text, TextInput, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";

import { CONTACTS, type Contact } from "@/src/data/mockData";
import { initials } from "@/src/utils/format";
import { makeStyles, useTheme } from "@/src/theme";

export default function Contacts() {
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const styles = useStyles();
  const { colors } = useTheme();
  const [q, setQ] = useState("");

  const favorites = CONTACTS.filter((c) => c.favorite);

  const sections = useMemo(() => {
    const filtered = CONTACTS.filter((c) =>
      q.trim() === ""
        ? true
        : c.name.toLowerCase().includes(q.toLowerCase()) ||
          c.numbers.some((n) => n.number.includes(q)),
    );
    const grouped: Record<string, Contact[]> = {};
    filtered.forEach((c) => {
      const letter = c.name[0].toUpperCase();
      grouped[letter] = grouped[letter] || [];
      grouped[letter].push(c);
    });
    return Object.keys(grouped)
      .sort()
      .map((letter) => ({ title: letter, data: grouped[letter] }));
  }, [q]);

  const callContact = (c: Contact) => {
    const n = c.numbers[0];
    router.push({ pathname: "/call/[number]", params: { number: n.number, name: c.name } });
  };

  return (
    <View style={[styles.root, { paddingTop: insets.top }]} testID="contacts-screen">
      <View style={styles.header}>
        <Text style={styles.title}>Contacts</Text>
        <Pressable style={styles.addBtn} hitSlop={10} testID="contacts-add-button">
          <Icon name="plus" size={24} color={colors.brand} />
        </Pressable>
      </View>

      <View style={styles.searchWrap}>
        <Icon name="magnify" size={18} color={colors.muted} />
        <TextInput
          value={q}
          onChangeText={setQ}
          placeholder="Search contacts"
          placeholderTextColor={colors.muted}
          style={styles.search}
          testID="contacts-search-input"
        />
        {q ? (
          <Pressable onPress={() => setQ("")} hitSlop={10}>
            <Icon name="close-circle" size={18} color={colors.muted} />
          </Pressable>
        ) : null}
      </View>

      {q === "" && (
        <View style={{ marginTop: 8 }}>
          <Text style={styles.sectionLabel}>Favorites</Text>
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            contentContainerStyle={styles.favRow}
          >
            {favorites.map((c) => (
              <Pressable
                key={c.id}
                onPress={() => callContact(c)}
                style={styles.favItem}
                testID={`favorite-${c.id}`}
              >
                {c.avatarUrl ? (
                  <Image source={{ uri: c.avatarUrl }} style={styles.favAvatar} contentFit="cover" />
                ) : (
                  <View style={[styles.favAvatar, styles.favPlaceholder]}>
                    <Text style={styles.favInitials}>{initials(c.name)}</Text>
                  </View>
                )}
                <Text style={styles.favName} numberOfLines={1}>
                  {c.name.split(" ")[0]}
                </Text>
              </Pressable>
            ))}
          </ScrollView>
        </View>
      )}

      <SectionList
        sections={sections}
        keyExtractor={(i) => i.id}
        contentContainerStyle={{ paddingBottom: 24 }}
        stickySectionHeadersEnabled={false}
        renderSectionHeader={({ section }) => (
          <Text style={styles.sectionHeader}>{section.title}</Text>
        )}
        ItemSeparatorComponent={() => <View style={styles.sep} />}
        renderItem={({ item }) => (
          <Pressable
            onPress={() => callContact(item)}
            style={({ pressed }) => [styles.row, pressed && { backgroundColor: colors.surfaceSecondary }]}
            testID={`contact-row-${item.id}`}
          >
            {item.avatarUrl ? (
              <Image source={{ uri: item.avatarUrl }} style={styles.avatar} contentFit="cover" />
            ) : (
              <View style={[styles.avatar, styles.avatarPlaceholder]}>
                <Text style={styles.avatarInitials}>{initials(item.name)}</Text>
              </View>
            )}
            <View style={{ flex: 1, marginLeft: 12 }}>
              <Text style={styles.name}>{item.name}</Text>
              <Text style={styles.sub}>{item.numbers.map((n) => n.number).join(" • ")}</Text>
            </View>
            <Icon name="phone" size={20} color={colors.brand} />
          </Pressable>
        )}
        ListEmptyComponent={
          <View style={styles.empty} testID="contacts-empty">
            <Icon name="account-off-outline" size={48} color={colors.muted} />
            <Text style={styles.emptyText}>No contacts found</Text>
          </View>
        }
      />
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
  },
  title: { color: c.onSurface, fontSize: 28, fontWeight: "800" },
  addBtn: { padding: 6 },
  searchWrap: {
    marginHorizontal: 16,
    marginTop: 12,
    backgroundColor: c.surfaceSecondary,
    borderRadius: 12,
    paddingHorizontal: 12,
    height: 44,
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
    borderWidth: 1,
    borderColor: c.border,
  },
  search: { flex: 1, color: c.onSurface, fontSize: 15, paddingVertical: 0 },
  sectionLabel: {
    color: c.muted,
    fontSize: 12,
    letterSpacing: 1.5,
    textTransform: "uppercase",
    paddingHorizontal: 16,
    marginBottom: 8,
    marginTop: 4,
  },
  favRow: { paddingHorizontal: 16, gap: 16, paddingBottom: 12 },
  favItem: { width: 68, alignItems: "center", gap: 6 },
  favAvatar: { width: 56, height: 56, borderRadius: 28, backgroundColor: c.surfaceTertiary },
  favPlaceholder: { alignItems: "center", justifyContent: "center" },
  favInitials: { color: c.onSurface, fontSize: 16, fontWeight: "700" },
  favName: { color: c.onSurface, fontSize: 12 },
  sectionHeader: {
    color: c.muted,
    fontSize: 13,
    fontWeight: "700",
    paddingHorizontal: 16,
    paddingTop: 12,
    paddingBottom: 6,
    backgroundColor: c.surface,
  },
  sep: { height: 0.5, backgroundColor: c.divider, marginLeft: 72 },
  row: { flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 12 },
  avatar: { width: 44, height: 44, borderRadius: 22, backgroundColor: c.surfaceTertiary },
  avatarPlaceholder: { alignItems: "center", justifyContent: "center" },
  avatarInitials: { color: c.onSurface, fontSize: 14, fontWeight: "700" },
  name: { color: c.onSurface, fontSize: 16, fontWeight: "600" },
  sub: { color: c.muted, fontSize: 12, marginTop: 2 },
  empty: { alignItems: "center", justifyContent: "center", gap: 10, paddingTop: 48 },
  emptyText: { color: c.muted, fontSize: 14 },
}));
