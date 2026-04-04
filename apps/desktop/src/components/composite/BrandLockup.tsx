import { HypercubeLogo } from "@/components/icons/HypercubeLogo";

interface BrandLockupProps {
  class?: string;
}

export function BrandLockup(props: BrandLockupProps) {
  return (
    <div class={`sidebar-brand-lockup ${props.class ?? ""}`}>
      <HypercubeLogo size={24} class="brand-lockup-icon" />
      <div class="sidebar-wordmark">
        <span class="sidebar-wordmark-main">Git</span>
        <span class="sidebar-wordmark-stage">Dev</span>
      </div>
    </div>
  );
}
