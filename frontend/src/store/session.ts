import AsyncStorage from "@react-native-async-storage/async-storage";
import { useEffect, useState } from "react";

const KEY = "n2it:session";
const SETTINGS_KEY = "n2it:settings";

export type Session = {
  companyCode: string;
  extension: string;
  // password NOT stored in plain text in a real app; this is a demo
  server: string; // e.g. n2it.voip.n2it.co.za
  signedInAt: number;
};

export type SipSettings = {
  transport: "UDP" | "TCP" | "TLS";
  port: string;
  voicemailNumber: string;
  pushGateway: string;
  srtp: boolean;
};

export const DEFAULT_SETTINGS: SipSettings = {
  transport: "UDP",
  port: "5060",
  voicemailNumber: "*97",
  pushGateway: "push.voip.n2it.co.za",
  srtp: false,
};

type Listener = () => void;
let currentSession: Session | null = null;
let currentSettings: SipSettings = DEFAULT_SETTINGS;
let listeners: Listener[] = [];
let hydrated = false;

async function hydrate() {
  if (hydrated) return;
  hydrated = true;
  try {
    const s = await AsyncStorage.getItem(KEY);
    const st = await AsyncStorage.getItem(SETTINGS_KEY);
    if (s) currentSession = JSON.parse(s);
    if (st) currentSettings = { ...DEFAULT_SETTINGS, ...JSON.parse(st) };
    listeners.forEach((l) => l());
  } catch {}
}

export function useSession() {
  const [, setTick] = useState(0);
  useEffect(() => {
    const l = () => setTick((t) => t + 1);
    listeners.push(l);
    hydrate();
    return () => {
      listeners = listeners.filter((x) => x !== l);
    };
  }, []);
  return {
    session: currentSession,
    settings: currentSettings,
    hydrated,
    signIn: async (companyCode: string, extension: string) => {
      const sess: Session = {
        companyCode,
        extension,
        server: `${companyCode}.voip.n2it.co.za`,
        signedInAt: Date.now(),
      };
      currentSession = sess;
      await AsyncStorage.setItem(KEY, JSON.stringify(sess));
      listeners.forEach((l) => l());
    },
    signOut: async () => {
      currentSession = null;
      await AsyncStorage.removeItem(KEY);
      listeners.forEach((l) => l());
    },
    updateSettings: async (patch: Partial<SipSettings>) => {
      currentSettings = { ...currentSettings, ...patch };
      await AsyncStorage.setItem(SETTINGS_KEY, JSON.stringify(currentSettings));
      listeners.forEach((l) => l());
    },
  };
}
