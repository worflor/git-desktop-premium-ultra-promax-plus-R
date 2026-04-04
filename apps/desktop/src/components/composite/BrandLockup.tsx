import { Icon } from "@/components/icons/Icon";

interface BrandLockupProps {
  class?: string;
}

export function BrandLockup(props: BrandLockupProps) {
  return (
    <div class={`sidebar-brand-lockup ${props.class ?? ""}`}>
      <Icon
        name="app-logo"
        size={20}
        title="Application"
        class="brand-lockup-icon"
        style="color: var(--text-strong);"
      />
      <div class="sidebar-wordmark">
        <span class="sidebar-wordmark-main">Git</span>
        <span class="sidebar-wordmark-stage">Dev</span>
      </div>
    </div>
  );
}
