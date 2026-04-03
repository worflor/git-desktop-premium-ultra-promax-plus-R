import type { JSX } from "solid-js";
import { iconRegistry, type IconName } from "@/components/icons/registry/iconRegistry";

interface IconProps {
  name: IconName;
  size?: 12 | 16 | 20 | 24;
  tone?: "normal" | "muted" | "accent" | "danger";
  title?: string;
  class?: string;
  style?: string | JSX.CSSProperties;
}

export function Icon(props: IconProps): JSX.Element {
  const size = () => props.size ?? 16;
  const toneClass = () => `icon-tone-${props.tone ?? "normal"}`;

  return (
    <svg
      class={`icon ${toneClass()} ${props.class ?? ""}`.trim()}
      width={size()}
      height={size()}
      viewBox="0 0 16 16"
      shape-rendering="geometricPrecision"
      vector-effect="non-scaling-stroke"
      aria-hidden={props.title ? undefined : true}
      role={props.title ? "img" : "presentation"}
    >
      {props.title && <title>{props.title}</title>}
      {iconRegistry[props.name]}
    </svg>
  );
}
