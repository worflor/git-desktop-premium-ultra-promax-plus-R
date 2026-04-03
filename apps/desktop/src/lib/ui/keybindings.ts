export type KeybindingProfile = "classic" | "compact";

export interface KeybindingProfileOption {
  id: KeybindingProfile;
  label: string;
  description: string;
}

export interface NavigationBinding {
  route: string;
  label: string;
  keys: string;
}

export interface NavigationHotkeyResolution {
  route?: string;
  consumed: boolean;
  awaitingPrefix: boolean;
}

const CLASSIC_NAVIGATION_BINDINGS: NavigationBinding[] = [
  { route: "/changes", label: "Changes", keys: "G C" },
  { route: "/history", label: "History", keys: "G H" },
  { route: "/branches", label: "Branches", keys: "G B" },
  { route: "/sync", label: "Sync", keys: "G S" },
  { route: "/settings", label: "Settings", keys: "G ," }
];

const COMPACT_NAVIGATION_BINDINGS: NavigationBinding[] = [
  { route: "/changes", label: "Changes", keys: "1" },
  { route: "/history", label: "History", keys: "2" },
  { route: "/branches", label: "Branches", keys: "3" },
  { route: "/sync", label: "Sync", keys: "4" },
  { route: "/settings", label: "Settings", keys: "5" }
];

const CLASSIC_SUFFIX_TO_ROUTE: Record<string, string> = {
  c: "/changes",
  h: "/history",
  b: "/branches",
  s: "/sync",
  ",": "/settings"
};

const COMPACT_KEY_TO_ROUTE: Record<string, string> = {
  "1": "/changes",
  "2": "/history",
  "3": "/branches",
  "4": "/sync",
  "5": "/settings"
};

export const KEYBINDING_PROFILE_OPTIONS: KeybindingProfileOption[] = [
  {
    id: "classic",
    label: "Classic Chords",
    description: "Git-style two-key navigation (G then route key)."
  },
  {
    id: "compact",
    label: "Compact Number Row",
    description: "Single-stroke navigation (1-5)."
  }
];

export function normalizeKeybindingProfile(value: string): KeybindingProfile {
  const normalized = value.trim().toLowerCase();
  return normalized === "compact" ? "compact" : "classic";
}

export function getNavigationBindings(profileInput: KeybindingProfile | string): NavigationBinding[] {
  const profile = normalizeKeybindingProfile(profileInput);
  return profile === "compact" ? COMPACT_NAVIGATION_BINDINGS : CLASSIC_NAVIGATION_BINDINGS;
}

export function getRouteShortcutHint(profileInput: KeybindingProfile | string, route: string): string {
  const binding = getNavigationBindings(profileInput).find((candidate) => candidate.route === route);
  return binding?.keys ?? "-";
}

export function resolveNavigationHotkey(
  profileInput: KeybindingProfile | string,
  keyInput: string,
  awaitingPrefix: boolean
): NavigationHotkeyResolution {
  const profile = normalizeKeybindingProfile(profileInput);
  const key = keyInput.toLowerCase();

  if (profile === "compact") {
    const route = COMPACT_KEY_TO_ROUTE[key];
    if (route) {
      return {
        route,
        consumed: true,
        awaitingPrefix: false
      };
    }

    return {
      consumed: false,
      awaitingPrefix: false
    };
  }

  if (awaitingPrefix) {
    if (key === "escape") {
      return {
        consumed: true,
        awaitingPrefix: false
      };
    }

    const route = CLASSIC_SUFFIX_TO_ROUTE[key];
    if (route) {
      return {
        route,
        consumed: true,
        awaitingPrefix: false
      };
    }

    if (key === "g") {
      return {
        consumed: true,
        awaitingPrefix: true
      };
    }

    return {
      consumed: false,
      awaitingPrefix: false
    };
  }

  if (key === "g") {
    return {
      consumed: true,
      awaitingPrefix: true
    };
  }

  return {
    consumed: false,
    awaitingPrefix: false
  };
}
