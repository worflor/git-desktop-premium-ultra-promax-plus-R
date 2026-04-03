interface KeyboardShortcutHintProps {
  keys: string;
}

export function KeyboardShortcutHint(props: KeyboardShortcutHintProps) {
  return <kbd class="shortcut-hint">{props.keys}</kbd>;
}
