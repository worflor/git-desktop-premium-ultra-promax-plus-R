import type { JSX } from "solid-js";
import { LayoutPreferencesProvider } from "@/app/layout/LayoutPreferencesContext";
import { RepositoryProvider } from "@/app/repository/RepositoryContext";

interface AppProps {
  children?: JSX.Element;
}

export function App(props: AppProps) {
  return (
    <RepositoryProvider>
      <LayoutPreferencesProvider>
        {props.children}
      </LayoutPreferencesProvider>
    </RepositoryProvider>
  );
}
