import { createContext, createSignal, useContext, type Accessor, type ParentProps } from "solid-js";

interface RepositoryContextValue {
  activeRepositoryPath: Accessor<string | null>;
  setActiveRepositoryPath: (path: string | null) => void;
}

const RepositoryContext = createContext<RepositoryContextValue>();

export function RepositoryProvider(props: ParentProps) {
  const [activeRepositoryPath, setActiveRepositoryPath] = createSignal<string | null>(null);

  return (
    <RepositoryContext.Provider
      value={{
        activeRepositoryPath,
        setActiveRepositoryPath
      }}
    >
      {props.children}
    </RepositoryContext.Provider>
  );
}

export function useRepositoryContext(): RepositoryContextValue {
  const context = useContext(RepositoryContext);
  if (!context) {
    throw new Error("Repository context is unavailable.");
  }
  return context;
}
