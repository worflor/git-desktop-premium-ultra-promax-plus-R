interface StatusPillProps {
  label: string;
  state: "added" | "modified" | "deleted" | "conflicted" | "staged" | "unstaged";
}

export function StatusPill(props: StatusPillProps) {
  return (
    <span class={`status-pill state-${props.state}`}>
      {props.label}
    </span>
  );
}
