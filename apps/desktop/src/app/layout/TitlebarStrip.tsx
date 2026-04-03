import { useRepositoryContext } from "@/app/repository/RepositoryContext";

export function TitlebarStrip() {
  const repository = useRepositoryContext();

  const projectName = () => {
    const path = repository.activeRepositoryPath();
    if (!path) return "";
    const parts = path.replace(/\\/g, "/").split("/").filter(Boolean);
    return parts[parts.length - 1] ?? path;
  };

  return (
    <header class="titlebar-strip" data-tauri-drag-region>
      <div class="workspace-identity">
        <span class="workspace-name" title={repository.activeRepositoryPath() ?? ""}>
          {projectName() || "Git Desktop"}
        </span>
      </div>
      <div class="titlebar-status">
        <span class="status-dot" aria-hidden="true" />
      </div>
    </header>
  );
}
