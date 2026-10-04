import { useMemo } from "react";
import { Appearance, StyleSheet, useColorScheme } from "react-native";

export type ColorScheme = "light" | "dark";

const dark = {
  surface: "#121212",
  onSurface: "#F5F5F5",
  surfaceSecondary: "#1E1E1E",
  onSurfaceSecondary: "#E5E5E5",
  surfaceTertiary: "#2D2D2D",
  onSurfaceTertiary: "#D4D4D4",
  surfaceInverse: "#FAFAFA",
  onSurfaceInverse: "#121212",
  muted: "#737373",

  brand: "#F97316",
  onBrand: "#FFFFFF",
  brandPrimary: "#EA580C",
  onBrandPrimary: "#FFFFFF",
  brandSecondary: "#C2410C",
  onBrandSecondary: "#FFFFFF",
  brandTertiary: "#431407",
  onBrandTertiary: "#FED7AA",

  success: "#22C55E",
  onSuccess: "#FFFFFF",
  warning: "#EAB308",
  onWarning: "#121212",
  error: "#EF4444",
  onError: "#FFFFFF",
  info: "#A8A29E",
  onInfo: "#121212",

  border: "#2D2D2D",
  borderStrong: "#404040",
  divider: "#262626",
};

export type ThemeColors = typeof dark;

export const defaultScheme = "dark" satisfies ColorScheme;

export const themes: { light?: ThemeColors; dark: ThemeColors } = { dark };

export function setColorScheme(scheme: ColorScheme | null) {
  Appearance.setColorScheme?.(scheme ?? "unspecified");
}

setColorScheme?.(themes.light ? null : defaultScheme);

export function useTheme(): { scheme: ColorScheme; colors: ThemeColors } {
  const system = useColorScheme();
  const scheme: ColorScheme = (system && themes[system as ColorScheme]) ? (system as ColorScheme) : defaultScheme;
  return { scheme, colors: (themes[scheme] ?? themes.dark) as ThemeColors };
}

export const colors = dark;

export function makeStyles<T extends StyleSheet.NamedStyles<T> | StyleSheet.NamedStyles<any>>(
  factory: (colors: ThemeColors) => T & StyleSheet.NamedStyles<any>,
): () => T {
  return function useStyles(): T {
    const { colors } = useTheme();
    return useMemo(() => StyleSheet.create(factory(colors)), [colors]);
  };
}

export const spacing = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24, "2xl": 32, "3xl": 48 } as const;
export const radius = { sm: 6, md: 12, lg: 20, pill: 999 } as const;
