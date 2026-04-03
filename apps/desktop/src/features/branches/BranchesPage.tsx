import { createResource, createSignal, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import { Icon } from "@/components/icons/Icon";
import { createBranch, listBranches, checkoutBranch } from "@/lib/backend/commands";

interface BranchesPageProps {
  embedded?: boolean;
}

export function BranchesPage(props: BranchesPageProps = {}) {
  const repository = useRepositoryContext();
  const [newBranchName, setNewBranchName] = createSignal("");
  const [actionError, setActionError] = createSignal<string | null>(null);
  const [actionRunning, setActionRunning] = createSignal(false);

  const activeRepo = () => repository.activeRepositoryPath();

  const [branchesResult, { refetch }] = createResource(activeRepo, async (path) => {
    if (!path) {
      return null;
    }
    return listBranches(path);
  });

  const onCreateBranch = async () => {
    const repo = activeRepo();
    const branchName = newBranchName().trim();
    if (!repo || !branchName) return;

    setActionError(null);
    setActionRunning(true);
    const result = await createBranch(repo, branchName, "HEAD");
    setActionRunning(false);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setNewBranchName("");
    void refetch();
  };

  const onCheckoutBranch = async (branchName: string) => {
    const repo = activeRepo();
    if (!repo) return;

    setActionError(null);
    setActionRunning(true);
    const result = await checkoutBranch(repo, branchName);
    setActionRunning(false);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    void refetch();
  };

  return (
    <div class={`feature-page ${props.embedded ? "is-embedded" : ""}`}>
      <span class="section-summary">Manage repository branches</span>

      <Show when={branchesResult.loading}>
        <LoadingStateSkeleton />
      </Show>

      <Show when={branchesResult.latest && !branchesResult.latest.ok}>
        <ErrorStateCard
          title="Branch lookup failed"
          body={branchesResult.latest && !branchesResult.latest.ok ? branchesResult.latest.error.message : "Unknown error"}
        />
      </Show>

      <Show when={branchesResult.latest?.ok}>
        <section class="state-card">
          <div class="branch-create-grid">
            <input
              class="path-input"
              placeholder="New branch name"
              value={newBranchName()}
              onInput={(event) => setNewBranchName(event.currentTarget.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  void onCreateBranch();
                }
              }}
            />
            <button
              class="primary-btn"
              style="display: flex; align-items: center; justify-content: center; width: 32px; padding: 0;"
              disabled={!newBranchName() || actionRunning()}
              onClick={() => void onCreateBranch()}
              title="Create branch"
            >
              <Icon name="plus" size={16} />
            </button>
          </div>

          <Show when={actionError()}>
            {(message) => <div style="margin-bottom: 8px;"><ErrorStateCard title="Action failed" body={message()} /></div>}
          </Show>

          <ul class="branch-list">
            {branchesResult.latest?.ok &&
              branchesResult.latest.data.branches.map((branch) => (
                <li class="branch-row">
                  <div class="branch-summary">
                    <div style="display: flex; align-items: center; gap: 8px;">
                      <Icon name="git-branch" size={12} tone={branch.current ? "accent" : "muted"} />
                      <strong style={branch.current ? "color: var(--text-strong)" : "color: var(--text-normal)"}>
                        {branch.name}
                      </strong>
                    </div>
                    <Show when={branch.upstream}>
                      <span class="branch-upstream">Tracking: {branch.upstream}</span>
                    </Show>
                  </div>
                  <button
                    class="primary-btn"
                    disabled={branch.current || actionRunning()}
                    onClick={() => void onCheckoutBranch(branch.name)}
                  >
                    {branch.current ? "Checked Out" : "Checkout"}
                  </button>
                </li>
              ))}
          </ul>
        </section>
      </Show>
    </div>
  );
}
