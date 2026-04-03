import { createEffect, createResource, createSignal, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { EmptyStateCard } from "@/components/composite/EmptyStateCard";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import { StatusPill } from "@/components/primitives/StatusPill";
import {
  checkoutBranch,
  createWorktree,
  createBranch,
  deleteBranch,
  listBranches,
  listWorktrees,
  openRepository,
  removeWorktree
} from "@/lib/backend/commands";

interface BranchesPageProps {
  embedded?: boolean;
}

export function BranchesPage(props: BranchesPageProps = {}) {
  const repository = useRepositoryContext();
  const [repositoryPath, setRepositoryPath] = createSignal(repository.activeRepositoryPath() ?? "");
  const [activeRepo, setActiveRepo] = createSignal<string | null>(repository.activeRepositoryPath());
  const [openError, setOpenError] = createSignal<string | null>(null);
  const [actionError, setActionError] = createSignal<string | null>(null);
  const [actionMessage, setActionMessage] = createSignal<string | null>(null);
  const [newBranchName, setNewBranchName] = createSignal("");
  const [fromRef, setFromRef] = createSignal("");
  const [worktreePath, setWorktreePath] = createSignal("");
  const [worktreeBranch, setWorktreeBranch] = createSignal("");
  const [worktreeStartPoint, setWorktreeStartPoint] = createSignal("");
  const [worktreeForceRemove, setWorktreeForceRemove] = createSignal(false);
  const [actionRunning, setActionRunning] = createSignal(false);

  createEffect(() => {
    const sharedPath = repository.activeRepositoryPath();
    if (!sharedPath || sharedPath === activeRepo()) {
      return;
    }

    setActiveRepo(sharedPath);
    setRepositoryPath(sharedPath);
  });

  const [branchesResult, { refetch: refetchBranches }] = createResource(activeRepo, async (path) => {
    if (!path) {
      return null;
    }
    return listBranches(path);
  });

  const [worktreesResult, { refetch: refetchWorktrees }] = createResource(activeRepo, async (path) => {
    if (!path) {
      return null;
    }
    return listWorktrees(path);
  });

  createEffect(() => {
    const branches = branchesResult.latest;
    if (!branches || !branches.ok) {
      return;
    }

    const current = branches.data.currentBranch ?? branches.data.branches[0]?.name;
    if (!current) {
      return;
    }

    if (!worktreeStartPoint().trim()) {
      setWorktreeStartPoint(current);
    }
  });

  const onOpenRepository = async () => {
    const path = repositoryPath().trim();
    setOpenError(null);
    setActionError(null);
    setActionMessage(null);

    if (!path) {
      setOpenError("Repository path is required.");
      return;
    }

    const result = await openRepository(path);
    if (!result.ok) {
      setOpenError(result.error.message);
      return;
    }

    setActiveRepo(result.data.repositoryPath);
    repository.setActiveRepositoryPath(result.data.repositoryPath);
    void refetchBranches();
    void refetchWorktrees();
  };

  const onCreateBranch = async () => {
    const repo = activeRepo();
    if (!repo) {
      return;
    }

    const branchName = newBranchName().trim();
    if (!branchName) {
      setActionError("Branch name is required.");
      return;
    }

    setActionRunning(true);
    setActionError(null);
    setActionMessage(null);

    const result = await createBranch(repo, branchName, fromRef().trim() || undefined);
    setActionRunning(false);
    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setActionMessage(`Created branch ${result.data.branchName}.`);
    setNewBranchName("");
    void refetchBranches();
    void refetchWorktrees();
  };

  const onCheckoutBranch = async (branchName: string) => {
    const repo = activeRepo();
    if (!repo || actionRunning()) {
      return;
    }

    setActionRunning(true);
    setActionError(null);
    setActionMessage(null);
    const result = await checkoutBranch(repo, branchName);
    setActionRunning(false);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setActionMessage(`Checked out ${result.data.branchName}.`);
    void refetchBranches();
    void refetchWorktrees();
  };

  const onDeleteBranch = async (branchName: string) => {
    const repo = activeRepo();
    if (!repo || actionRunning()) {
      return;
    }

    setActionRunning(true);
    setActionError(null);
    setActionMessage(null);
    const result = await deleteBranch(repo, branchName, false);
    setActionRunning(false);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setActionMessage(`Deleted branch ${result.data.branchName}.`);
    void refetchBranches();
    void refetchWorktrees();
  };

  const onCreateWorktree = async () => {
    const repo = activeRepo();
    if (!repo || actionRunning()) {
      return;
    }

    const path = worktreePath().trim();
    const branch = worktreeBranch().trim();
    if (!path || !branch) {
      setActionError("Worktree path and branch are required.");
      return;
    }

    setActionRunning(true);
    setActionError(null);
    setActionMessage(null);

    const result = await createWorktree(repo, path, branch, worktreeStartPoint().trim() || undefined);
    setActionRunning(false);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setActionMessage(`Created worktree at ${result.data.worktreePath}.`);
    setWorktreePath("");
    setWorktreeBranch("");
    void refetchBranches();
    void refetchWorktrees();
  };

  const onRemoveWorktree = async (path: string) => {
    const repo = activeRepo();
    if (!repo || actionRunning()) {
      return;
    }

    const normalizePath = (value: string) => value.replace(/\\/g, "/").toLowerCase();
    if (normalizePath(path) === normalizePath(repo)) {
      setActionError("Primary worktree cannot be removed from this view.");
      return;
    }

    setActionRunning(true);
    setActionError(null);
    setActionMessage(null);

    const result = await removeWorktree(repo, path, worktreeForceRemove());
    setActionRunning(false);

    if (!result.ok) {
      setActionError(result.error.message);
      return;
    }

    setActionMessage(`Removed worktree ${result.data.worktreePath}.`);
    void refetchBranches();
    void refetchWorktrees();
  };

  return (
    <div class={`feature-page ${props.embedded ? "is-embedded" : ""}`}>
      <Show when={!props.embedded}>
        <>
          <header class="feature-header">
            <div class="feature-header-main">
              <h1 class="feature-title">Branches</h1>
            </div>
            <div class="feature-header-meta">
              <span class="feature-meta-pill">{activeRepo() ? "Repository connected" : "No repository"}</span>
              <span class="feature-meta-pill">
                {branchesResult.latest?.ok ? `${branchesResult.latest.data.branches.length} branches` : "No branch snapshot"}
              </span>
            </div>
          </header>

          <section class="feature-toolbar">
            <input
              class="path-input"
              placeholder="C:/dev/your-repository"
              value={repositoryPath()}
              onInput={(event) => setRepositoryPath(event.currentTarget.value)}
            />
            <button class="primary-btn" onClick={() => void onOpenRepository()}>
              Open Repository
            </button>
          </section>
        </>
      </Show>

      <Show when={!activeRepo()}>
        <EmptyStateCard
          title="Open a repository"
          body="Select a local path."
        />
      </Show>

      <Show when={openError()}>
        {(message) => <ErrorStateCard title="Cannot open repository" body={message()} />}
      </Show>

      <Show when={branchesResult.loading}>
        <LoadingStateSkeleton />
      </Show>

      <Show when={branchesResult.latest?.ok && branchesResult.latest.data}>
        <section class="state-card">
          <h3>Branch Management</h3>
          <p>Current branch: {branchesResult.latest?.ok ? (branchesResult.latest.data.currentBranch ?? "detached") : "detached"}</p>

          <div class="branch-create-grid">
            <input
              class="path-input"
              placeholder="New branch name"
              value={newBranchName()}
              onInput={(event) => setNewBranchName(event.currentTarget.value)}
            />
            <input
              class="path-input"
              placeholder="Start point (optional)"
              value={fromRef()}
              onInput={(event) => setFromRef(event.currentTarget.value)}
            />
            <button class="primary-btn" disabled={actionRunning()} onClick={() => void onCreateBranch()}>
              {actionRunning() ? "Running..." : "Create Branch"}
            </button>
          </div>

          <ul class="branch-list">
            {branchesResult.latest?.ok &&
              branchesResult.latest.data.branches.map((branch) => (
                <li class="branch-row">
                  <div class="branch-summary">
                    <span class="file-path">{branch.name}</span>
                    <div class="status-tags">
                      <Show when={branch.current}>
                        <StatusPill label="Current" state="staged" />
                      </Show>
                      <Show when={branch.ahead > 0 || branch.behind > 0}>
                        <StatusPill label={`Ahead ${branch.ahead} / Behind ${branch.behind}`} state="modified" />
                      </Show>
                    </div>
                    <Show when={branch.upstream}>
                      {(upstream) => <span class="branch-upstream">Upstream: {upstream()}</span>}
                    </Show>
                  </div>
                  <div class="inline-actions">
                    <button
                      class="primary-btn"
                      disabled={branch.current || actionRunning()}
                      onClick={() => void onCheckoutBranch(branch.name)}
                    >
                      Checkout
                    </button>
                    <button
                      class="primary-btn"
                      disabled={branch.current || actionRunning()}
                      onClick={() => void onDeleteBranch(branch.name)}
                    >
                      Delete
                    </button>
                  </div>
                </li>
              ))}
          </ul>
        </section>
      </Show>

      <Show when={worktreesResult.loading}>
        <LoadingStateSkeleton />
      </Show>

      <Show when={worktreesResult.latest?.ok && worktreesResult.latest.data}>
        <section class="state-card">
          <h3>Worktree Management</h3>
          <p>Parallel local checkouts.</p>

          <div class="branch-create-grid">
            <input
              class="path-input"
              placeholder="Worktree path"
              value={worktreePath()}
              onInput={(event) => setWorktreePath(event.currentTarget.value)}
            />
            <input
              class="path-input"
              placeholder="New worktree branch"
              value={worktreeBranch()}
              onInput={(event) => setWorktreeBranch(event.currentTarget.value)}
            />
            <button class="primary-btn" disabled={actionRunning()} onClick={() => void onCreateWorktree()}>
              {actionRunning() ? "Running..." : "Create Worktree"}
            </button>
          </div>

          <div class="sync-grid">
            <input
              class="path-input"
              placeholder="Start point (optional, defaults to current branch)"
              value={worktreeStartPoint()}
              onInput={(event) => setWorktreeStartPoint(event.currentTarget.value)}
            />
          </div>

          <div class="inline-actions">
            <label>
              <input
                type="checkbox"
                checked={worktreeForceRemove()}
                onChange={(event) => setWorktreeForceRemove(event.currentTarget.checked)}
              />
              Force remove
            </label>
          </div>

          <Show
            when={worktreesResult.latest?.ok && worktreesResult.latest.data.worktrees.length > 0}
            fallback={<p>No worktrees.</p>}
          >
            <ul class="branch-list">
              {(worktreesResult.latest?.ok ? worktreesResult.latest.data.worktrees : []).map((worktree) => (
                <li class="branch-row">
                  <div class="branch-summary">
                    <span class="file-path">{worktree.path}</span>
                    <div class="status-tags">
                      <Show when={worktree.branch}>
                        {(branch) => <StatusPill label={`Branch ${branch()}`} state="modified" />}
                      </Show>
                      <Show when={worktree.detached}>
                        <StatusPill label="Detached" state="unstaged" />
                      </Show>
                      <Show when={worktree.locked}>
                        <StatusPill label="Locked" state="conflicted" />
                      </Show>
                      <Show when={worktree.prunable}>
                        <StatusPill label="Prunable" state="deleted" />
                      </Show>
                    </div>
                    <Show when={worktree.head}>
                      {(head) => <span class="branch-upstream">HEAD: {head()}</span>}
                    </Show>
                  </div>
                  <div class="inline-actions">
                    <button
                      class="primary-btn"
                      disabled={actionRunning()}
                      onClick={() => void onRemoveWorktree(worktree.path)}
                    >
                      Remove
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          </Show>
        </section>
      </Show>

      <Show when={branchesResult.latest && !branchesResult.latest.ok}>
        <ErrorStateCard
          title="Branch lookup failed"
          body={branchesResult.latest && !branchesResult.latest.ok ? branchesResult.latest.error.message : "Unknown error"}
        />
      </Show>

      <Show when={worktreesResult.latest && !worktreesResult.latest.ok}>
        <ErrorStateCard
          title="Worktree lookup failed"
          body={worktreesResult.latest && !worktreesResult.latest.ok ? worktreesResult.latest.error.message : "Unknown error"}
        />
      </Show>

      <Show when={actionMessage()}>
        {(message) => (
          <section class="state-card">
            <p>{message()}</p>
          </section>
        )}
      </Show>

      <Show when={actionError()}>
        {(message) => <ErrorStateCard title="Branch action failed" body={message()} />}
      </Show>
    </div>
  );
}
