import { useRepositoryContext } from "@/app/repository/RepositoryContext";

function toProjectName(value: string): string {
  const parts = value.replace(/\\/g, "/").split("/").filter(Boolean);
  return parts[parts.length - 1] ?? value;
}

export function TitlebarStrip() {
  const repository = useRepositoryContext();
  const projectName = () => {
    const path = repository.activeRepositoryPath();
    if (!path) {
      return "No project";
    }
    return toProjectName(path);
  };

  return (
    <header class="titlebar-strip" data-tauri-drag-region>
      <div class="workspace-identity">
        <span class="workspace-name" title={repository.activeRepositoryPath() ?? ""}>
          {projectName()}
        </span>
      </div>
      <div class="titlebar-status">
        <span class="status-dot" aria-hidden="true" />
      </div>
    </header>
  );
}
