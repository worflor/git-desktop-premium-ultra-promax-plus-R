import { Icon } from "@/components/icons/Icon";
import {
  animatedIconRegistry,
  type AnimatedIconName
} from "@/components/icons/registry/animatedIconRegistry";

interface AnimatedIconProps {
  name: AnimatedIconName;
  intensity?: "low" | "medium" | "high";
  loop?: boolean;
  reducedMotion?: boolean;
  title?: string;
}

export function AnimatedIcon(props: AnimatedIconProps) {
  const definition = () => animatedIconRegistry[props.name];
  const intensity = () => `ani-intensity-${props.intensity ?? "medium"}`;
  const loopClass = () => (props.loop === false ? "ani-once" : "ani-loop");
  const reduceClass = () => (props.reducedMotion ? "ani-reduced-motion" : "");

  return (
    <Icon
      name={definition().baseIcon}
      title={props.title}
      class={`animated-icon ${definition().animationClass} ${intensity()} ${loopClass()} ${reduceClass()}`.trim()}
    />
  );
}
