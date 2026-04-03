import { Show } from "solid-js";
import { Icon } from "@/components/icons/Icon";
import type { IconName } from "@/components/icons/registry/iconRegistry";

interface EmptyStateCardProps {
  title: string;
  body: string;
  icon?: IconName;
}

export function EmptyStateCard(props: EmptyStateCardProps) {
  return (
    <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 40px 20px; text-align: center; gap: 8px;">
      <Show when={props.icon}>
        <Icon name={props.icon!} size={24} tone="muted" style="margin-bottom: 8px; opacity: 0.5;" />
      </Show>
      <h3 style="margin: 0; font-size: 13px; color: var(--text-strong); font-weight: 500;">{props.title}</h3>
      <p style="margin: 0; font-size: 12px; color: var(--text-muted);">{props.body}</p>
    </div>
  );
}
