import type { JSX } from "solid-js";

export type IconName =
  | "app-logo"
  | "changes"
  | "history"
  | "branches"
  | "sync"
  | "settings"
  | "git-branch"
  | "status-conflict"
  | "plus"
  | "sort"
  | "chevron-right";

const stroke = {
  fill: "none",
  stroke: "currentColor",
  "stroke-width": 1.8,
  "stroke-linecap": "round",
  "stroke-linejoin": "round"
} as const;

export const iconRegistry: Record<IconName, JSX.Element> = {
  "app-logo": (
    <>
      <path {...stroke} d="M3 5.5L8 2l5 3.5v5L8 14l-5-3.5z" />
      <path {...stroke} d="M8 2v12" />
      <path {...stroke} d="M3 5.5l5 3 5-3" />
    </>
  ),
  changes: (
    <>
      <path {...stroke} d="M3 4h10" />
      <path {...stroke} d="M3 8h10" />
      <path {...stroke} d="M3 12h6" />
      <path {...stroke} d="M12 10v4" />
      <path {...stroke} d="M10 12h4" />
    </>
  ),
  history: (
    <>
      <path {...stroke} d="M3.5 8a4.5 4.5 0 108.3-2.3" />
      <path {...stroke} d="M3.5 4.5v3.5H7" />
      <path {...stroke} d="M8 5.5v2.8l2 1.2" />
    </>
  ),
  branches: (
    <>
      <circle {...stroke} cx="4" cy="4" r="1.5" />
      <circle {...stroke} cx="12" cy="4" r="1.5" />
      <circle {...stroke} cx="8" cy="12" r="1.5" />
      <path {...stroke} d="M5.5 4h5" />
      <path {...stroke} d="M8 5.5v5" />
    </>
  ),
  sync: (
    <>
      <path {...stroke} d="M12 5V2l2.5 2.5L12 7V5H6" />
      <path {...stroke} d="M4 11v3L1.5 11.5 4 9v2h6" />
    </>
  ),
  settings: (
    <>
      <circle {...stroke} cx="8" cy="8" r="2.4" />
      <path {...stroke} d="M8 2.5v1.4M8 12.1v1.4M2.5 8h1.4M12.1 8h1.4M3.9 3.9l1 1M11.1 11.1l1 1M3.9 12.1l1-1M11.1 4.9l1-1" />
    </>
  ),
  "git-branch": (
    <>
      <path {...stroke} d="M4 3.5v9" />
      <circle {...stroke} cx="4" cy="3.5" r="1.5" />
      <circle {...stroke} cx="4" cy="12.5" r="1.5" />
      <path {...stroke} d="M5.5 4h4a2 2 0 012 2v1.2" />
      <circle {...stroke} cx="11.5" cy="8.8" r="1.5" />
    </>
  ),
  "status-conflict": (
    <>
      <path {...stroke} d="M8 2.5l5.2 9H2.8z" />
      <path {...stroke} d="M8 6v2.8" />
      <path {...stroke} d="M8 11.2h.01" />
    </>
  ),
  plus: (
    <>
      <path {...stroke} d="M8 3.5v9" />
      <path {...stroke} d="M3.5 8h9" />
    </>
  ),
  sort: (
    <>
      <path {...stroke} d="M5 3.5v9" />
      <path {...stroke} d="M3.7 4.8L5 3.5l1.3 1.3" />
      <path {...stroke} d="M3.7 11.2L5 12.5l1.3-1.3" />
      <path {...stroke} d="M8 4h4.5" />
      <path {...stroke} d="M8 8h3.2" />
      <path {...stroke} d="M8 12h4.5" />
    </>
  ),
  "chevron-right": (
    <>
      <path {...stroke} d="M6 4.5L9.5 8 6 11.5" />
    </>
  )
};
