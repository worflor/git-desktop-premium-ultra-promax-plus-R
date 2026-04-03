import { Icon } from "@/components/icons/Icon";

interface ErrorStateCardProps {
  title: string;
  body: string;
}

export function ErrorStateCard(props: ErrorStateCardProps) {
  return (
    <div style="background: rgba(var(--danger-panel-start-rgb), 0.7); border: 1px solid rgba(var(--danger-rgb), 0.3); border-radius: 6px; padding: 10px; display: flex; gap: 10px;">
      <Icon name="status-conflict" size={16} tone="danger" style="flex-shrink: 0; margin-top: 2px;" />
      <div style="display: flex; flex-direction: column; gap: 4px;">
        <h3 style="margin: 0; font-size: 12px; color: var(--danger-copy-strong); font-weight: 600;">{props.title}</h3>
        <p style="margin: 0; font-size: 11px; color: var(--danger-copy-muted);">{props.body}</p>
      </div>
    </div>
  );
}
