import { render } from "solid-js/web";
import { Navigate, Route, Router, type RouteSectionProps } from "@solidjs/router";
import { App } from "@/app/App";
import { AppShellFrame } from "@/app/layout/AppShellFrame";
import { WorkspacePage } from "@/features/workspace/WorkspacePage";
import "@/styles/tokens.css";
import "@/styles/globals.css";
import "@/styles/motion.css";

const root = document.getElementById("root");

if (!root) {
  throw new Error("App root element not found.");
}

function AppRoot(props: RouteSectionProps) {
  return (
    <App>
      <AppShellFrame>{props.children}</AppShellFrame>
    </App>
  );
}

render(() => (
  <Router root={AppRoot}>
    <Route path="/" component={() => <Navigate href="/changes" />} />
    <Route path="/changes" component={WorkspacePage} />
    <Route path="/history" component={WorkspacePage} />
    <Route path="/branches" component={WorkspacePage} />
    <Route path="/sync" component={WorkspacePage} />
    <Route path="/settings" component={() => <Navigate href="/changes?panel=settings" />} />
    <Route path="/*rest" component={() => <Navigate href="/changes" />} />
  </Router>
), root);