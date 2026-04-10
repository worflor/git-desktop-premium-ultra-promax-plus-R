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
  | "clear"
  | "chevron-right"
  | "tag";

const stroke = {
  fill: "none",
  stroke: "currentColor",
  "stroke-width": 1.8,
  "stroke-linecap": "round",
  "stroke-linejoin": "round"
} as const;

export const iconRegistry: Record<IconName, () => JSX.Element> = {
  "app-logo": () => (
    <g fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d="M4 4h8v8h-8z" opacity="0.4" />
      <path d="M6 6h4v4h-4z" />
      <path d="M4 4l2 2M12 4l-2 2M4 12l2-2M12 12l-2-2" />
      <path d="M8 2v12M2 8h12" stroke-dasharray="0.5 1.5" stroke-opacity="0.3" />
    </g>
  ),
  changes: () => (
    <>
      <path {...stroke} d="M3 4h10" class="changes-l1" />
      <path {...stroke} d="M3 8h10" class="changes-l2" />
      <path {...stroke} d="M3 12h6" class="changes-l3" />
      <path {...stroke} d="M12 10v4" class="changes-v" />
      <path {...stroke} d="M10 12h4" class="changes-h" />
    </>
  ),
  history: () => (
    <>
      <path {...stroke} d="M3 8a5 5 0 1 0 9.2 -2.5" class="history-arc" />
      <path {...stroke} d="M3 4v4h4" class="history-arr" />
      <path {...stroke} d="M8 5v3l2 2" class="history-clk" />
    </>
  ),
  branches: () => (
    <>
      <circle {...stroke} cx="4" cy="4" r="2" class="branch-c1" />
      <circle {...stroke} cx="12" cy="4" r="2" class="branch-c2" />
      <circle {...stroke} cx="8" cy="12" r="2" class="branch-c3" />
      <path {...stroke} d="M6 4h4" class="branch-p1" />
      <path {...stroke} d="M8 6v4" class="branch-p2" />
    </>
  ),
  sync: () => (
    <>
      <path {...stroke} d="M12.5 5.5l2-2-2-2v2h-9" class="sync-p1" />
      <path {...stroke} d="M3.5 10.5l-2 2 2 2v-2h9" class="sync-p2" />
    </>
  ),
  settings: () => (
    <>
      <circle {...stroke} cx="8" cy="8" r="1.5" class="settings-core" />
      <path {...stroke} d="M4 8a4 4 0 118 0 4 4 0 01-8 0" class="settings-r1" stroke-dasharray="12 13" />
      <path {...stroke} d="M2 8a6 6 0 1112 0 6 6 0 01-12 0" class="settings-r2" stroke-dasharray="18 20" />
    </>
  ),
  "git-branch": () => (
    <>
      <path {...stroke} d="M4 3.5v9" />
      <circle {...stroke} cx="4" cy="3.5" r="1.5" />
      <circle {...stroke} cx="4" cy="12.5" r="1.5" />
      <path {...stroke} d="M5.5 4h4a2 2 0 012 2v1.2" />
      <circle {...stroke} cx="11.5" cy="8.8" r="1.5" />
    </>
  ),
  "status-conflict": () => (
    <>
      <path {...stroke} d="M8 2.5l5.2 9H2.8z" />
      <path {...stroke} d="M8 6v2.8" />
      <path {...stroke} d="M8 11.2h.01" />
    </>
  ),
  plus: () => (
    <>
      <path {...stroke} d="M8 3v10" class="plus-p1" />
      <path {...stroke} d="M3 8h10" class="plus-p2" />
    </>
  ),
  sort: () => (
    <>
      <path {...stroke} d="M5 3.5v9" />
      <path {...stroke} d="M3.7 4.8L5 3.5l1.3 1.3" />
      <path {...stroke} d="M3.7 11.2L5 12.5l1.3-1.3" />
      <path {...stroke} d="M8 4h4.5" />
      <path {...stroke} d="M8 8h3.2" />
      <path {...stroke} d="M8 12h4.5" />
    </>
  ),
  clear: () => (
    <g class="icon-clear">
      <path {...stroke} d="M5 4h6" class="clear-lid" />
      <path {...stroke} d="M6.5 4v-1h3v1" class="clear-handle" />
      <path {...stroke} d="M5.5 4v8c0 .8.7 1.5 1.5 1.5h2c.8 0 1.5-.7 1.5-1.5V4" class="clear-bin" />
      <path {...stroke} d="M7 7v4M9 7v4" class="clear-lines" />
    </g>
  ),
  "chevron-right": () => (
    <>
      <path {...stroke} d="M6 4.5L9.5 8 6 11.5" />
    </>
  ),
  tag: () => (
    <>
      <path {...stroke} d="M2.5 2.5h5.8l5.2 5.2-5.5 5.5-5.5-5.5z" class="tag-body" />
      <circle cx="5.5" cy="5.5" r="1" fill="currentColor" opacity="0.6" class="tag-dot" />
    </>
  )
};
