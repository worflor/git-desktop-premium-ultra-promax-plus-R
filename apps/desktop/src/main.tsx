import { render } from "solid-js/web";
import { Navigate, Route, Router, type RouteSectionProps } from "@solidjs/router";
import { App } from "@/app/App";
import { AppShellFrame } from "@/app/layout/AppShellFrame";
import { WorkspacePage } from "@/features/workspace/WorkspacePage";
import { applyTheme } from "@/lib/ui/theme";
import "@/lib/ui/visibility"; // Install data-app-visible attribute before first render.
import "@/styles/tokens.css";
import "@/styles/globals.css";
import "@/styles/motion.css";

const root = document.getElementById("root");

if (!root) {
  throw new Error("App root element not found.");
}

const bootstrappedTheme = document.documentElement.getAttribute("data-theme");
if (bootstrappedTheme && bootstrappedTheme.trim().length > 0) {
  applyTheme(bootstrappedTheme, { deferMaterial: true, force: true });
}

function AppRoot(props: RouteSectionProps) {
  return (
    <App>
      <AppShellFrame>{props.children}</AppShellFrame>
    </App>
  );
}

render(() => (
  <>
    <Router root={AppRoot}>
      <Route path="/" component={() => <Navigate href="/changes" />} />
      <Route path="/changes" component={WorkspacePage} />
      <Route path="/history" component={WorkspacePage} />
      <Route path="/branches" component={WorkspacePage} />
      <Route path="/sync" component={() => <Navigate href="/changes?panel=sync" />} />
      <Route path="/settings" component={() => <Navigate href="/changes?panel=settings" />} />
      <Route path="/*rest" component={() => <Navigate href="/changes" />} />
    </Router>

    {/* Global Hyper-Reactive Filter Definitions */}
    <svg style="position: absolute; width: 0; height: 0; pointer-events: none;" aria-hidden="true">
      <defs>
        <filter id="hyper-prism" x="-100%" y="-100%" width="300%" height="300%">
          {/* Prismatic Higher-Dimensional Splitting */}
          <feOffset in="SourceGraphic" dx="-5" dy="0" result="off1" />
          <feFlood flood-color="var(--hyper-chromatic-1)" flood-opacity="0.45" result="color1" />
          <feComposite in="color1" in2="off1" operator="in" result="spec1" />
          
          <feOffset in="SourceGraphic" dx="5" dy="0" result="off2" />
          <feFlood flood-color="var(--hyper-chromatic-2)" flood-opacity="0.45" result="color2" />
          <feComposite in="color2" in2="off2" operator="in" result="spec2" />
          
          <feMerge>
            <feMergeNode in="spec1" />
            <feMergeNode in="spec2" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>
    </svg>
  </>
), root!);
