export type CallDirection = "incoming" | "outgoing" | "missed";

export type RecentCall = {
  id: string;
  name: string;
  number: string;
  direction: CallDirection;
  timestamp: number; // ms
  durationSec: number;
  avatarUrl?: string;
};

export type Contact = {
  id: string;
  name: string;
  numbers: { label: string; number: string }[];
  favorite: boolean;
  avatarUrl?: string;
};

export type Voicemail = {
  id: string;
  name: string;
  number: string;
  timestamp: number;
  durationSec: number;
  heard: boolean;
  avatarUrl?: string;
};

const AV1 = "https://images.unsplash.com/photo-1560250097-0b93528c311a?crop=entropy&cs=srgb&fm=jpg&ixid=M3w4NjA1NTJ8MHwxfHNlYXJjaHwxfHxidXNpbmVzcyUyMHBlcnNvbiUyMHByb2Zlc3Npb25hbCUyMGhlYWRzaG90fGVufDB8fHx8MTc5MTEwODQ4NXww&ixlib=rb-4.1.0&q=85";
const AV2 = "https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?crop=entropy&cs=srgb&fm=jpg&ixid=M3w4NjA1NTJ8MHwxfHNlYXJjaHwzfHxidXNpbmVzcyUyMHBlcnNvbiUyMHByb2Zlc3Npb25hbCUyMGhlYWRzaG90fGVufDB8fHx8MTc5MTEwODQ4NXww&ixlib=rb-4.1.0&q=85";
const AV3 = "https://images.unsplash.com/photo-1573497019940-1c28c88b4f3e?crop=entropy&cs=srgb&fm=jpg&ixid=M3w4NjA1NTJ8MHwxfHNlYXJjaHwyfHxidXNpbmVzcyUyMHBlcnNvbiUyMHByb2Zlc3Npb25hbCUyMGhlYWRzaG90fGVufDB8fHx8MTc5MTEwODQ4NXww&ixlib=rb-4.1.0&q=85";

const now = Date.now();
const hours = (h: number) => h * 60 * 60 * 1000;
const mins = (m: number) => m * 60 * 1000;

export const SIGN_IN_BG =
  "https://images.unsplash.com/photo-1510507024924-fc3847d49ae2?crop=entropy&cs=srgb&fm=jpg&ixid=M3w4NTYxODh8MHwxfHNlYXJjaHwxfHxtb2Rlcm4lMjBvZmZpY2UlMjBidWlsZGluZyUyMGFyY2hpdGVjdHVyYWwlMjBwaG90b2dyYXBoeSUyMGRhcmt8ZW58MHx8fGJsYWNrfDE3OTExMDg0ODV8MA&ixlib=rb-4.1.0&q=85";

export const RECENTS: RecentCall[] = [
  { id: "r1", name: "Nasr Patel", number: "1021", direction: "missed", timestamp: now - mins(12), durationSec: 0, avatarUrl: AV1 },
  { id: "r2", name: "Front Desk", number: "1000", direction: "outgoing", timestamp: now - mins(45), durationSec: 128 },
  { id: "r3", name: "Sarah Khan", number: "1042", direction: "incoming", timestamp: now - hours(2), durationSec: 342, avatarUrl: AV2 },
  { id: "r4", name: "Unknown", number: "+27 82 555 0199", direction: "missed", timestamp: now - hours(3), durationSec: 0 },
  { id: "r5", name: "Amira Botha", number: "1013", direction: "outgoing", timestamp: now - hours(5), durationSec: 54, avatarUrl: AV3 },
  { id: "r6", name: "Voicemail", number: "*97", direction: "outgoing", timestamp: now - hours(26), durationSec: 42 },
  { id: "r7", name: "Dev PBX", number: "1100", direction: "incoming", timestamp: now - hours(28), durationSec: 220 },
  { id: "r8", name: "Nasr Patel", number: "1021", direction: "missed", timestamp: now - hours(50), durationSec: 0, avatarUrl: AV1 },
];

export const CONTACTS: Contact[] = [
  { id: "c1", name: "Amira Botha", favorite: true, numbers: [{ label: "ext", number: "1013" }, { label: "mobile", number: "+27 82 555 0101" }], avatarUrl: AV3 },
  { id: "c2", name: "Dev PBX", favorite: true, numbers: [{ label: "ext", number: "1100" }] },
  { id: "c3", name: "Front Desk", favorite: true, numbers: [{ label: "ext", number: "1000" }] },
  { id: "c4", name: "Jamal Essa", favorite: false, numbers: [{ label: "ext", number: "1077" }] },
  { id: "c5", name: "Lerato Mokoena", favorite: false, numbers: [{ label: "ext", number: "1055" }] },
  { id: "c6", name: "Nasr Patel", favorite: true, numbers: [{ label: "ext", number: "1021" }, { label: "mobile", number: "+27 82 555 0188" }], avatarUrl: AV1 },
  { id: "c7", name: "Sarah Khan", favorite: false, numbers: [{ label: "ext", number: "1042" }], avatarUrl: AV2 },
  { id: "c8", name: "Thabo Dlamini", favorite: false, numbers: [{ label: "ext", number: "1066" }] },
  { id: "c9", name: "Zanele Mahlangu", favorite: false, numbers: [{ label: "ext", number: "1088" }] },
];

export const VOICEMAILS: Voicemail[] = [
  { id: "v1", name: "Nasr Patel", number: "1021", timestamp: now - mins(20), durationSec: 24, heard: false, avatarUrl: AV1 },
  { id: "v2", name: "Unknown", number: "+27 82 555 0199", timestamp: now - hours(4), durationSec: 48, heard: false },
  { id: "v3", name: "Sarah Khan", number: "1042", timestamp: now - hours(28), durationSec: 12, heard: true, avatarUrl: AV2 },
];
