import { Navigate, Route } from "@solidjs/router";
import { AppShellFrame } from "@/app/layout/AppShellFrame";
import { WorkspacePage } from "@/features/workspace/WorkspacePage";

export function AppRoutes() {
  return (
    <Route path="/" component={AppShellFrame}>
      <Route path="/" component={() => <Navigate href="/changes" />} />
      <Route path="/changes" component={WorkspacePage} />
      <Route path="/history" component={WorkspacePage} />
      <Route path="/branches" component={WorkspacePage} />
      <Route path="/sync" component={() => <Navigate href="/changes?panel=sync" />} />
      <Route path="/settings" component={() => <Navigate href="/changes?panel=settings" />} />
    </Route>
  );
}
