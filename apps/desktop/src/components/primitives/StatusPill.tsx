interface StatusPillProps {
  label: string;
  state?: "added" | "modified" | "deleted" | "conflicted" | "staged" | "unstaged";
}

export function StatusPill(props: StatusPillProps) {
  const state = props.state ?? "unstaged";
  return <span class={`status-pill state-${state}`}>{props.label}</span>;
}
