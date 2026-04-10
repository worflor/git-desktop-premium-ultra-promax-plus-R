import { createSignal, For, Show } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import type { CommitSearchResultData } from "@/lib/backend/dtos";
import { searchCommitsByMessage, searchCommitsByCode, searchCommitsByFile } from "@/lib/backend/commands";
import { formatCommitDate } from "@/lib/ui/date";

interface SearchPanelProps {
  onClose: () => void;
}

type SearchScope = "messages" | "code" | "files";

function detectScope(query: string): SearchScope {
  const trimmed = query.trim();
  if (trimmed.startsWith("S:")) return "code";
  if (trimmed.includes("/") || /\.\w{1,6}$/.test(trimmed)) return "files";
  return "messages";
}

function scopeLabel(scope: SearchScope): string {
  switch (scope) {
    case "messages": return "searching commit messages";
    case "code": return "searching code changes (pickaxe)";
    case "files": return "searching file history";
  }
}

export function SearchPanel(props: SearchPanelProps) {
  const repository = useRepositoryContext();
  const navigate = useNavigate();
  const [query, setQuery] = createSignal("");
  const [results, setResults] = createSignal<CommitSearchResultData[]>([]);
  const [loading, setLoading] = createSignal(false);
  const [searched, setSearched] = createSignal(false);

  let debounceTimer: ReturnType<typeof setTimeout> | null = null;

  const activeRepo = () => repository.activeRepositoryPath();

  const detectedScope = () => detectScope(query());

  const executeSearch = async (searchQuery: string) => {
    const repo = activeRepo();
    if (!repo || !searchQuery.trim()) {
      setResults([]);
      setSearched(false);
      return;
    }

    setLoading(true);
    setSearched(true);

    const scope = detectScope(searchQuery);
    let effectiveQuery = searchQuery.trim();

    let result;
    if (scope === "code") {
      effectiveQuery = effectiveQuery.replace(/^S:/, "").trim();
      result = await searchCommitsByCode(repo, effectiveQuery);
    } else if (scope === "files") {
      result = await searchCommitsByFile(repo, effectiveQuery);
    } else {
      result = await searchCommitsByMessage(repo, effectiveQuery);
    }

    setLoading(false);

    if (result.ok) {
      setResults(result.data.results);
    } else {
      setResults([]);
    }
  };

  const onInput = (value: string) => {
    setQuery(value);
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      void executeSearch(value);
    }, 300);
  };

  const onSelectResult = (commitHash: string) => {
    props.onClose();
    void navigate(`/history?commit=${commitHash}`);
  };

  return (
    <>
      <header class="settings-slide-header">
        <h2 id="search-panel-title" style="font-size: 14px; font-weight: 600;">Search</h2>
        <button type="button" class="settings-slide-close hyper-reactive" onClick={props.onClose}>
          Close
        </button>
      </header>
      <div class="settings-slide-body" style="display: flex; flex-direction: column; gap: 12px;">
        <input
          class="path-input"
          placeholder="Search commits..."
          style="width: 100%; font-size: 13px; padding: 8px 12px;"
          value={query()}
          onInput={(e) => onInput(e.currentTarget.value)}
          onKeyDown={(e) => {
            if (e.key === "Escape") props.onClose();
          }}
          ref={(el) => requestAnimationFrame(() => el.focus())}
        />
        <Show when={query().trim()}>
          <div style="font-size: 10px; color: var(--text-muted); opacity: 0.7;">
            {scopeLabel(detectedScope())}
          </div>
        </Show>

        <Show when={loading()}>
          <div style="padding: 20px; text-align: center; font-size: 12px; color: var(--text-muted);">
            Searching...
          </div>
        </Show>

        <Show when={!loading() && searched() && results().length === 0}>
          <div style="padding: 20px; text-align: center; font-size: 12px; color: var(--text-muted); opacity: 0.7;">
            No results
          </div>
        </Show>

        <Show when={!loading() && results().length > 0}>
          <ul style="margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; gap: 2px; overflow-y: auto; flex: 1;">
            <For each={results()}>
              {(entry) => (
                <li>
                  <button
                    type="button"
                    style="width: 100%; text-align: left; padding: 8px 10px; background: transparent; border: none; border-radius: 6px; cursor: pointer; display: flex; flex-direction: column; gap: 3px; transition: background 100ms; color: inherit;"
                    onMouseEnter={(e) => { e.currentTarget.style.background = "rgba(var(--chrome-border-rgb), 0.06)"; }}
                    onMouseLeave={(e) => { e.currentTarget.style.background = "transparent"; }}
                    onClick={() => onSelectResult(entry.commitHash)}
                  >
                    <div style="display: flex; justify-content: space-between; align-items: baseline; font-size: 10px;">
                      <span style="font-family: var(--font-mono); font-weight: 600; color: var(--text-muted);">
                        {entry.shortHash}
                      </span>
                      <span style="font-size: 10px; color: var(--text-muted); opacity: 0.7;">
                        {formatCommitDate(entry.authoredAt)}
                      </span>
                    </div>
                    <div style="font-size: 12px; color: var(--text-normal); white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">
                      {entry.subject}
                    </div>
                    <div style="font-size: 10px; color: var(--text-muted); opacity: 0.7;">
                      {entry.authorName}
                    </div>
                  </button>
                </li>
              )}
            </For>
          </ul>
        </Show>
      </div>
    </>
  );
}
