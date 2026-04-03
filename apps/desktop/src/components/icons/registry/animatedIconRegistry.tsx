import type { IconName } from "@/components/icons/registry/iconRegistry";

export type AnimatedIconName = "sync-running" | "ai-streaming" | "conflict-alert" | "success-complete";

export interface AnimatedIconDefinition {
  baseIcon: IconName;
  animationClass: string;
}

export const animatedIconRegistry: Record<AnimatedIconName, AnimatedIconDefinition> = {
  "sync-running": {
    baseIcon: "sync",
    animationClass: "ani-sync-spin"
  },
  "ai-streaming": {
    baseIcon: "changes",
    animationClass: "ani-ai-pulse"
  },
  "conflict-alert": {
    baseIcon: "status-conflict",
    animationClass: "ani-conflict-alert"
  },
  "success-complete": {
    baseIcon: "app-logo",
    animationClass: "ani-success-pop"
  }
};
