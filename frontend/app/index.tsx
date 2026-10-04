import { Redirect } from "expo-router";
import { useEffect, useState } from "react";
import { ActivityIndicator, View } from "react-native";
import AsyncStorage from "@react-native-async-storage/async-storage";

import { colors } from "@/src/theme";

export default function Index() {
  const [state, setState] = useState<"loading" | "in" | "out">("loading");

  useEffect(() => {
    AsyncStorage.getItem("n2it:session").then((v) => {
      setState(v ? "in" : "out");
    });
  }, []);

  if (state === "loading") {
    return (
      <View
        testID="splash-container"
        style={{ flex: 1, backgroundColor: colors.surface, alignItems: "center", justifyContent: "center" }}
      >
        <ActivityIndicator color={colors.brand} />
      </View>
    );
  }

  return <Redirect href={state === "in" ? "/(tabs)" : "/sign-in"} />;
}
