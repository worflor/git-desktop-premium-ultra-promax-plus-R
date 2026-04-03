import { createEffect, createResource, createSignal, onCleanup, Show } from "solid-js";
import { useRepositoryContext } from "@/app/repository/RepositoryContext";
import { ErrorStateCard } from "@/components/composite/ErrorStateCard";
import { LoadingStateSkeleton } from "@/components/composite/LoadingStateSkeleton";
import {
  abortConflictResolution,
  cancelAiDiffReviewJob,
  closePullRequest,
  closeLocalIssue,
  continueConflictResolution,
  createPullRequest,
  createLocalIssue,
  fetchRemote,
  getConflictState,
  getAiDiffReviewJob,
  getAuthStatus,
  getGitCapabilities,
  getRepositoryIntegrationMatrix,
  getRepositoryAuthStatus,
  listBranches,
  listAiProviders,
  listForgeAdapters,
  listIssueProviders,
  listLocalIssues,
  listPullRequestProviders,
  listPullRequests,
  markPullRequestReady,
  mergePullRequest,
  pullRemote,
  pushRemote,
  reopenPullRequest,
  reopenLocalIssue,
  startAiDiffReviewJob
} from "@/lib/backend/commands";

interface SyncPageProps {
  embedded?: boolean;
}

export function SyncPage(props: SyncPageProps = {}) {
  const repository = useRepositoryContext();
  const [capabilities] = createResource(() => getGitCapabilities());
  const [auth] = createResource(() => getAuthStatus());
  const [adapters] = createResource(() => listForgeAdapters());
  const [providers, { refetch: refetchProviders }] = createResource(() => listAiProviders());

  const [repositoryPath, setRepositoryPath] = createSignal(repository.activeRepositoryPath() ?? "");
  const [remote, setRemote] = createSignal("origin");
  const [branch, setBranch] = createSignal("");
  const [pullWithRebase, setPullWithRebase] = createSignal(false);
  const [syncOutput, setSyncOutput] = createSignal<string | null>(null);
  const [syncError, setSyncError] = createSignal<string | null>(null);
  const [reviewProviderId, setReviewProviderId] = createSignal("codex");
  const [reviewPrompt, setReviewPrompt] = createSignal("Review diff.");
  const [reviewScopePath, setReviewScopePath] = createSignal("");
  const [syncRunning, setSyncRunning] = createSignal(false);
  const [reviewRunning, setReviewRunning] = createSignal(false);
  const [reviewJobId, setReviewJobId] = createSignal<string | null>(null);
  const [localIssueTitle, setLocalIssueTitle] = createSignal("");
  const [localIssueBody, setLocalIssueBody] = createSignal("");
  const [issueProviderId, setIssueProviderId] = createSignal("");
  const [localIssueError, setLocalIssueError] = createSignal<string | null>(null);
  const [localIssueRunning, setLocalIssueRunning] = createSignal(false);
  const [issueActionTarget, setIssueActionTarget] = createSignal<string | null>(null);
  const [pullRequestProviderId, setPullRequestProviderId] = createSignal("");
  const [pullRequestTitle, setPullRequestTitle] = createSignal("");
  const [pullRequestDescription, setPullRequestDescription] = createSignal("");
  const [pullRequestSourceBranch, setPullRequestSourceBranch] = createSignal("");
  const [pullRequestTargetBranch, setPullRequestTargetBranch] = createSignal("");
  const [pullRequestDraft, setPullRequestDraft] = createSignal(true);
  const [deleteSourceOnMerge, setDeleteSourceOnMerge] = createSignal(false);
  const [pullRequestError, setPullRequestError] = createSignal<string | null>(null);
  const [pullRequestRunning, setPullRequestRunning] = createSignal(false);
  const [pullRequestActionTarget, setPullRequestActionTarget] = createSignal<string | null>(null);
  const [conflictActionRunning, setConflictActionRunning] = createSignal(false);
  const [conflictActionError, setConflictActionError] = createSignal<string | null>(null);

  createEffect(() => {
    const sharedPath = repository.activeRepositoryPath();
    if (!sharedPath || sharedPath === repositoryPath()) {
      return;
    }
    setRepositoryPath(sharedPath);
  });

  const [repoAuth] = createResource(
    () => {
      const path = repositoryPath().trim();
      return path.length > 0 ? path : null;
    },
    async (path) => getRepositoryAuthStatus(path)
  );

  const [integrationMatrix, { refetch: refetchIntegrationMatrix }] = createResource(
    () => {
      const path = repositoryPath().trim();
      return path.length > 0 ? path : null;
    },
    async (path) => getRepositoryIntegrationMatrix(path)
  );

  const [conflictState, { refetch: refetchConflictState }] = createResource(
    () => {
      const path = repositoryPath().trim();
      return path.length > 0 ? path : null;
    },
    async (path) => getConflictState(path)
  );

  const [issueProviders, { refetch: refetchIssueProviders }] = createResource(
    () => {
      const path = repositoryPath().trim();
      return path.length > 0 ? path : null;
    },
    async (path) => listIssueProviders(path)
  );

  const [localIssues, { refetch: refetchLocalIssues }] = createResource(
    () => {
      const path = repositoryPath().trim();
      const provider = issueProviderId().trim();
      if (!path) {
        return null;
      }

      return {
        path,
        provider: provider.length > 0 ? provider : undefined
      };
    },
    async (input) => listLocalIssues(input.path, input.provider)
  );

  const [pullRequestProviders, { refetch: refetchPullRequestProviders }] = createResource(
    () => {
      const path = repositoryPath().trim();
      return path.length > 0 ? path : null;
    },
    async (path) => listPullRequestProviders(path)
  );

  const [pullRequests, { refetch: refetchPullRequests }] = createResource(
    () => {
      const path = repositoryPath().trim();
      const provider = pullRequestProviderId().trim();
      if (!path) {
        return null;
      }

      return {
        path,
        provider: provider.length > 0 ? provider : undefined
      };
    },
    async (input) => listPullRequests(input.path, input.provider)
  );

  const [pullRequestBranches] = createResource(
    () => {
      const path = repositoryPath().trim();
      return path.length > 0 ? path : null;
    },
    async (path) => listBranches(path)
  );

  createEffect(() => {
    const result = issueProviders.latest;
    if (!result || !result.ok) {
      return;
    }

    const current = issueProviderId().trim();
    if (!current) {
      setIssueProviderId(result.data.defaultProviderId);
      return;
    }

    const exists = result.data.providers.some((provider) => provider.id === current);
    if (!exists) {
      setIssueProviderId(result.data.defaultProviderId);
    }
  });

  createEffect(() => {
    const result = pullRequestProviders.latest;
    if (!result || !result.ok) {
      return;
    }

    const current = pullRequestProviderId().trim();
    if (!current) {
      setPullRequestProviderId(result.data.defaultProviderId);
      return;
    }

    const exists = result.data.providers.some((provider) => provider.id === current);
    if (!exists) {
      setPullRequestProviderId(result.data.defaultProviderId);
    }
  });

  createEffect(() => {
    const result = pullRequestBranches.latest;
    if (!result || !result.ok || result.data.branches.length === 0) {
      return;
    }

    const branchNames = result.data.branches.map((branch) => branch.name);
    const currentBranch = result.data.currentBranch ?? branchNames[0] ?? "";

    if (!pullRequestSourceBranch().trim() && currentBranch) {
      setPullRequestSourceBranch(currentBranch);
    }

    if (!pullRequestTargetBranch().trim()) {
      const source = pullRequestSourceBranch().trim() || currentBranch;
      const preferredTargets = ["main", "master", "develop", "dev", "trunk"];
      const preferred = preferredTargets.find((name) => name !== source && branchNames.includes(name));
      const fallback = branchNames.find((name) => name !== source);
      const target = preferred ?? fallback ?? source;
      if (target) {
        setPullRequestTargetBranch(target);
      }
    }
  });

  const capabilitiesError = () =>
    capabilities.latest && !capabilities.latest.ok ? capabilities.latest.error.message : null;

  const authError = () => (auth.latest && !auth.latest.ok ? auth.latest.error.message : null);

  const adaptersError = () =>
    adapters.latest && !adapters.latest.ok ? adapters.latest.error.message : null;

  const integrationError = () =>
    integrationMatrix.latest && !integrationMatrix.latest.ok ? integrationMatrix.latest.error.message : null;

  const issueProvidersError = () =>
    issueProviders.latest && !issueProviders.latest.ok ? issueProviders.latest.error.message : null;

  const conflictStateError = () =>
    conflictState.latest && !conflictState.latest.ok ? conflictState.latest.error.message : null;

  const localIssuesError = () =>
    localIssues.latest && !localIssues.latest.ok ? localIssues.latest.error.message : null;

  const pullRequestProvidersError = () =>
    pullRequestProviders.latest && !pullRequestProviders.latest.ok
      ? pullRequestProviders.latest.error.message
      : null;

  const pullRequestsError = () =>
    pullRequests.latest && !pullRequests.latest.ok ? pullRequests.latest.error.message : null;

  const pullRequestBranchesError = () =>
    pullRequestBranches.latest && !pullRequestBranches.latest.ok
      ? pullRequestBranches.latest.error.message
      : null;

  const integrationData = () =>
    integrationMatrix.latest && integrationMatrix.latest.ok ? integrationMatrix.latest.data : null;

  const selectedConflictOperation = () =>
    conflictState.latest && conflictState.latest.ok ? conflictState.latest.data.operation : undefined;

  const selectedIssueProvider = () => {
    const result = issueProviders.latest;
    if (!result || !result.ok) {
      return null;
    }

    return result.data.providers.find((provider) => provider.id === issueProviderId()) ?? null;
  };

  const issueProviderAvailable = () => selectedIssueProvider()?.available ?? true;

  const selectedPullRequestProvider = () => {
    const result = pullRequestProviders.latest;
    if (!result || !result.ok) {
      return null;
    }

    return result.data.providers.find((provider) => provider.id === pullRequestProviderId()) ?? null;
  };

  const pullRequestProviderAvailable = () => selectedPullRequestProvider()?.available ?? true;

  const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

  const formatIssueTimestamp = (value: string) => {
    const trimmed = value.trim();

    const parsed = new Date(trimmed);
    if (!Number.isNaN(parsed.getTime())) {
      return parsed.toLocaleString();
    }

    // Legacy local metadata used epoch seconds before ISO-8601 normalization.
    if (/^\d+$/.test(trimmed)) {
      const epoch = Number.parseInt(trimmed, 10);
      if (Number.isFinite(epoch)) {
        return new Date(epoch * 1000).toLocaleString();
      }
    }

    return trimmed;
  };

  const runSync = async (operation: "fetch" | "pull" | "push") => {
    const path = repositoryPath().trim();
    if (!path) {
      setSyncError("Repository path is required for sync operations.");
      return;
    }

    repository.setActiveRepositoryPath(path);

    setSyncError(null);
    setSyncOutput(null);
    setSyncRunning(true);

    const remoteName = remote().trim();
    const branchName = branch().trim();
    const result =
      operation === "fetch"
        ? await fetchRemote(path, remoteName || undefined, true)
        : operation === "pull"
          ? await pullRemote(path, remoteName || undefined, branchName || undefined, pullWithRebase())
          : await pushRemote(path, remoteName || undefined, branchName || undefined, false);

    setSyncRunning(false);

    if (!result.ok) {
      setSyncError(result.error.message);
      void refetchConflictState();
      return;
    }

    setSyncOutput(result.data.output || `${operation} completed`);
    void refetchIntegrationMatrix();
    void refetchIssueProviders();
    void refetchPullRequestProviders();
    void refetchConflictState();
  };

  const onConflictAction = async (action: "continue" | "abort") => {
    const path = repositoryPath().trim();
    if (!path) {
      setConflictActionError("Repository path is required for conflict actions.");
      return;
    }

    repository.setActiveRepositoryPath(path);
    setConflictActionError(null);
    setConflictActionRunning(true);

    const operation = selectedConflictOperation();
    const result =
      action === "continue"
        ? await continueConflictResolution(path, operation)
        : await abortConflictResolution(path, operation);

    setConflictActionRunning(false);

    if (!result.ok) {
      setConflictActionError(result.error.message);
      void refetchConflictState();
      return;
    }

    setSyncOutput((current) => `${current ?? ""}\nConflict ${result.data.action}: ${result.data.operation}\n${result.data.output}\n`);
    void refetchConflictState();
  };

  const pollReviewJob = async (jobId: string) => {
    while (reviewJobId() === jobId) {
      const result = await getAiDiffReviewJob(jobId);
      if (!result.ok) {
        setReviewRunning(false);
        setReviewJobId(null);
        setSyncError(result.error.message);
        break;
      }

      const job = result.data;
      setSyncOutput(job.output);

      if (job.done) {
        setReviewRunning(false);
        setReviewJobId(null);
        if (job.status === "failed") {
          setSyncError(job.error ?? "AI review job failed.");
        }
        break;
      }

      await sleep(600);
    }
  };

  const onRunReview = async () => {
    const path = repositoryPath().trim();
    if (!path) {
      setSyncError("Repository path is required for AI review.");
      return;
    }

    repository.setActiveRepositoryPath(path);

    if (reviewRunning()) {
      return;
    }

    setSyncError(null);
    setSyncOutput(null);
    const diffScopePath = reviewScopePath().trim();
    const result = await startAiDiffReviewJob(
      reviewProviderId(),
      path,
      reviewPrompt(),
      diffScopePath.length > 0 ? diffScopePath : undefined
    );

    if (!result.ok) {
      setSyncError(result.error.message);
      return;
    }

    setReviewRunning(true);
    setReviewJobId(result.data.jobId);
    setSyncOutput("AI review job started...\n");
    void pollReviewJob(result.data.jobId);
  };

  const onCancelReview = async () => {
    const jobId = reviewJobId();
    if (!jobId) {
      return;
    }

    const result = await cancelAiDiffReviewJob(jobId);
    if (!result.ok) {
      setSyncError(result.error.message);
      return;
    }

    if (result.data.canceled) {
      setSyncOutput((current) => `${current ?? ""}\nCancel requested...\n`);
    }

    setReviewRunning(false);
    setReviewJobId(null);
  };

  const onCreateLocalIssue = async () => {
    const path = repositoryPath().trim();
    if (!path) {
      setLocalIssueError("Repository path is required for local issues.");
      return;
    }

    const title = localIssueTitle().trim();
    if (!title) {
      setLocalIssueError("Issue title is required.");
      return;
    }

    if (!issueProviderAvailable()) {
      setLocalIssueError("Selected issue provider is unavailable.");
      return;
    }

    const providerId = issueProviderId().trim() || undefined;

    repository.setActiveRepositoryPath(path);
    setLocalIssueError(null);
    setLocalIssueRunning(true);

    const result = await createLocalIssue(path, providerId, title, localIssueBody().trim());
    setLocalIssueRunning(false);

    if (!result.ok) {
      setLocalIssueError(result.error.message);
      return;
    }

    setLocalIssueTitle("");
    setLocalIssueBody("");
    setSyncOutput((current) => `${current ?? ""}\nLocal issue created: ${result.data.issue.id}\n`);
    void refetchLocalIssues();
  };

  const onToggleLocalIssueState = async (issueId: string, currentState: string) => {
    const path = repositoryPath().trim();
    if (!path) {
      setLocalIssueError("Repository path is required for local issues.");
      return;
    }

    if (!issueProviderAvailable()) {
      setLocalIssueError("Selected issue provider is unavailable.");
      return;
    }

    const providerId = issueProviderId().trim() || undefined;

    repository.setActiveRepositoryPath(path);
    setLocalIssueError(null);
    setIssueActionTarget(issueId);

    const result =
      currentState.toLowerCase() === "closed"
        ? await reopenLocalIssue(path, providerId, issueId)
        : await closeLocalIssue(path, providerId, issueId);

    setIssueActionTarget(null);

    if (!result.ok) {
      setLocalIssueError(result.error.message);
      return;
    }

    setSyncOutput((current) => `${current ?? ""}\nLocal issue ${result.data.operation}: ${result.data.issue.id}\n`);
    void refetchLocalIssues();
  };

  const onCreatePullRequest = async () => {
    const path = repositoryPath().trim();
    if (!path) {
      setPullRequestError("Repository path is required for pull requests.");
      return;
    }

    const title = pullRequestTitle().trim();
    if (!title) {
      setPullRequestError("Pull request title is required.");
      return;
    }

    const source = pullRequestSourceBranch().trim();
    const target = pullRequestTargetBranch().trim();
    if (!source || !target) {
      setPullRequestError("Source and target branches are required.");
      return;
    }

    if (source === target) {
      setPullRequestError("Source and target branches must differ.");
      return;
    }

    if (!pullRequestProviderAvailable()) {
      setPullRequestError("Selected pull request provider is unavailable.");
      return;
    }

    const providerId = pullRequestProviderId().trim() || undefined;

    repository.setActiveRepositoryPath(path);
    setPullRequestError(null);
    setPullRequestRunning(true);

    const result = await createPullRequest(
      path,
      providerId,
      title,
      pullRequestDescription().trim(),
      source,
      target,
      pullRequestDraft()
    );

    setPullRequestRunning(false);

    if (!result.ok) {
      setPullRequestError(result.error.message);
      return;
    }

    setPullRequestTitle("");
    setPullRequestDescription("");
    setPullRequestDraft(true);
    setSyncOutput((current) => `${current ?? ""}\nPull request created: ${result.data.pullRequest.id}\n`);
    void refetchPullRequests();
  };

  const onOperatePullRequest = async (
    operation: "close" | "reopen" | "ready" | "merge",
    pullRequestId: string
  ) => {
    const path = repositoryPath().trim();
    if (!path) {
      setPullRequestError("Repository path is required for pull requests.");
      return;
    }

    if (!pullRequestProviderAvailable()) {
      setPullRequestError("Selected pull request provider is unavailable.");
      return;
    }

    const providerId = pullRequestProviderId().trim() || undefined;

    repository.setActiveRepositoryPath(path);
    setPullRequestError(null);
    setPullRequestActionTarget(pullRequestId);

    const result =
      operation === "close"
        ? await closePullRequest(path, providerId, pullRequestId)
        : operation === "reopen"
          ? await reopenPullRequest(path, providerId, pullRequestId)
          : operation === "ready"
            ? await markPullRequestReady(path, providerId, pullRequestId)
            : await mergePullRequest(path, providerId, pullRequestId, deleteSourceOnMerge());

    setPullRequestActionTarget(null);

    if (!result.ok) {
      setPullRequestError(result.error.message);
      return;
    }

    setSyncOutput(
      (current) => `${current ?? ""}\nPull request ${result.data.operation}: ${result.data.pullRequest.id}\n`
    );
    void refetchPullRequests();
    void refetchConflictState();
  };

  onCleanup(() => {
    const jobId = reviewJobId();
    if (jobId) {
      void cancelAiDiffReviewJob(jobId);
    }
  });

  return (
    <div class={`feature-page ${props.embedded ? "is-embedded" : ""}`}>
      <Show when={!props.embedded}>
        <header class="feature-header">
          <div class="feature-header-main">
            <h1 class="feature-title">Sync</h1>
          </div>
          <div class="feature-header-meta">
            <span class="feature-meta-pill">
              {repositoryPath().trim().length > 0 ? "Connected" : "Set repo"}
            </span>
            <span class="feature-meta-pill">Remote {remote().trim() || "origin"}</span>
          </div>
        </header>
      </Show>

      <Show when={capabilities.loading || auth.loading || adapters.loading}>
        <LoadingStateSkeleton />
      </Show>

      <Show when={!props.embedded && capabilities.latest?.ok && auth.latest?.ok && adapters.latest?.ok}>
        <section class="info-grid">
          <article class="state-card">
            <h3>Git Capabilities</h3>
            <p>Installed: {String(capabilities.latest?.ok && capabilities.latest.data.gitInstalled)}</p>
            <p>Version: {capabilities.latest?.ok ? (capabilities.latest.data.gitVersion ?? "unknown") : "unknown"}</p>
          </article>
          <article class="state-card">
            <h3>Auth Diagnostics</h3>
            <p>SSH Agent: {String(auth.latest?.ok && auth.latest.data.sshAgentAvailable)}</p>
            <p>Helper Configured: {String(auth.latest?.ok && auth.latest.data.credentialHelperConfigured)}</p>
            <Show when={repoAuth.latest?.ok && repoAuth.latest.data.remoteDiagnostics.length > 0}>
              <ul>
                {repoAuth.latest?.ok && repoAuth.latest.data.remoteDiagnostics.map((diagnostic) => (
                  <li>
                    {diagnostic.remote} ({diagnostic.protocol}): {diagnostic.guidance}
                  </li>
                ))}
              </ul>
            </Show>
          </article>
          <article class="state-card">
            <h3>Forge Adapters</h3>
            <ul>
              {adapters.latest?.ok && adapters.latest.data.adapters.map((adapter) => <li>{adapter.id}: {adapter.available ? "available" : "missing"}</li>)}
            </ul>
          </article>
          <article class="state-card">
            <div class="sync-card-header">
              <h3>Repository Integration</h3>
              <Show when={!props.embedded}>
                <button class="primary-btn" onClick={() => void refetchIntegrationMatrix()} disabled={integrationMatrix.loading}>
                  Refresh
                </button>
              </Show>
            </div>
            <Show when={repositoryPath().trim().length > 0} fallback={<p>Set repo path.</p>}>
              <Show when={integrationData()} fallback={<p>{integrationMatrix.loading ? "Loading..." : "No data."}</p>}>
                {(matrix) => (
                  <>
                    <p>Offline ready: {String(matrix().offlineReady)}</p>
                    <p>Remotes detected: {matrix().remotes.length}</p>
                    <p>Local features: {matrix().localFeatures.join(", ")}</p>
                    <Show when={matrix().remotes.length > 0}>
                      <ul class="integration-list">
                        {matrix().remotes.map((remoteInfo) => (
                          <li class="integration-row">
                            <div>
                              <strong>{remoteInfo.remote}</strong> ({remoteInfo.hostKind})
                            </div>
                            <div>Adapter: {remoteInfo.adapterId ?? "none"} ({remoteInfo.adapterAvailable ? "available" : "unavailable"})</div>
                            <div>Offline support: {String(remoteInfo.offlineSupported)}</div>
                            <div>Capabilities: {remoteInfo.capabilitySummary.join(", ")}</div>
                          </li>
                        ))}
                      </ul>
                    </Show>
                  </>
                )}
              </Show>
            </Show>
          </article>
        </section>
      </Show>

      <Show when={capabilitiesError()}>
        {(message) => <ErrorStateCard title="Capabilities check failed" body={message()} />}
      </Show>

      <Show when={authError()}>
        {(message) => <ErrorStateCard title="Auth diagnostics failed" body={message()} />}
      </Show>

      <Show when={adaptersError()}>
        {(message) => <ErrorStateCard title="Forge adapter lookup failed" body={message()} />}
      </Show>

      <Show when={integrationError()}>
        {(message) => <ErrorStateCard title="Repository integration lookup failed" body={message()} />}
      </Show>

      <Show when={issueProvidersError()}>
        {(message) => <ErrorStateCard title="Issue provider discovery failed" body={message()} />}
      </Show>

      <Show when={conflictStateError()}>
        {(message) => <ErrorStateCard title="Conflict state lookup failed" body={message()} />}
      </Show>

      <Show when={localIssuesError()}>
        {(message) => <ErrorStateCard title="Local issues lookup failed" body={message()} />}
      </Show>

      <Show when={pullRequestProvidersError()}>
        {(message) => <ErrorStateCard title="Pull request provider discovery failed" body={message()} />}
      </Show>

      <Show when={pullRequestsError()}>
        {(message) => <ErrorStateCard title="Pull request lookup failed" body={message()} />}
      </Show>

      <Show when={pullRequestBranchesError()}>
        {(message) => <ErrorStateCard title="Branch lookup for pull requests failed" body={message()} />}
      </Show>

      <section class="state-card">
        <h3>Sync Controls</h3>
        <div class="sync-grid">
          <Show when={!props.embedded || repositoryPath().trim().length === 0}>
            <input
              class="path-input"
              placeholder="C:/dev/your-repository"
              value={repositoryPath()}
              onInput={(event) => setRepositoryPath(event.currentTarget.value)}
            />
          </Show>
          <input
            class="path-input"
            placeholder="Remote (default origin)"
            value={remote()}
            onInput={(event) => setRemote(event.currentTarget.value)}
          />
          <input
            class="path-input"
            placeholder="Branch (optional)"
            value={branch()}
            onInput={(event) => setBranch(event.currentTarget.value)}
          />
        </div>
        <div class="inline-actions">
          <button class="primary-btn" onClick={() => void runSync("fetch")} disabled={syncRunning()}>
            {syncRunning() ? "Running..." : "Fetch"}
          </button>
          <button class="primary-btn" onClick={() => void runSync("pull")} disabled={syncRunning()}>
            Pull
          </button>
          <button class="primary-btn" onClick={() => void runSync("push")} disabled={syncRunning()}>
            Push
          </button>
          <label>
            <input
              type="checkbox"
              checked={pullWithRebase()}
              onChange={(event) => setPullWithRebase(event.currentTarget.checked)}
            />
            Pull with rebase
          </label>
        </div>
      </section>

      <section class="state-card">
        <div class="sync-card-header">
          <h3>Conflict Resolution</h3>
          <Show when={!props.embedded}>
            <button class="primary-btn" onClick={() => void refetchConflictState()} disabled={conflictState.loading}>
              Refresh
            </button>
          </Show>
        </div>

        <Show when={repositoryPath().trim().length > 0} fallback={<p>Set repo path.</p>}>
          <Show when={conflictState.loading}>
            <p>Checking conflict state...</p>
          </Show>

          <Show when={conflictActionError()}>
            {(message) => <p class="inline-error">{message()}</p>}
          </Show>

          <Show when={conflictState.latest?.ok && !conflictState.latest.data.inConflict}>
            <p>No active merge/rebase/cherry-pick/revert conflicts detected.</p>
          </Show>

          <Show when={conflictState.latest?.ok && conflictState.latest.data.inConflict}>
            <>
              <p>
                Active operation: {conflictState.latest?.ok ? conflictState.latest.data.operation ?? "unknown" : "unknown"}
              </p>

              <Show when={conflictState.latest?.ok && conflictState.latest.data.conflictedFiles.length > 0}>
                <ul class="issue-list">
                  {(conflictState.latest?.ok ? conflictState.latest.data.conflictedFiles : []).map((path) => (
                    <li class="integration-row">{path}</li>
                  ))}
                </ul>
              </Show>

              <Show when={conflictState.latest?.ok && conflictState.latest.data.guidance.length > 0}>
                <ul>
                  {(conflictState.latest?.ok ? conflictState.latest.data.guidance : []).map((line) => (
                    <li>{line}</li>
                  ))}
                </ul>
              </Show>

              <div class="inline-actions">
                <button
                  class="primary-btn"
                  onClick={() => void onConflictAction("continue")}
                  disabled={conflictActionRunning()}
                >
                  {conflictActionRunning() ? "Working..." : "Continue"}
                </button>
                <button
                  class="primary-btn"
                  onClick={() => void onConflictAction("abort")}
                  disabled={conflictActionRunning()}
                >
                  Abort
                </button>
              </div>
            </>
          </Show>
        </Show>
      </section>

      <section class="state-card">
        <div class="sync-card-header">
          <h3>Issues</h3>
          <Show when={!props.embedded}>
            <button
              class="primary-btn"
              onClick={() => {
                void refetchIssueProviders();
                void refetchLocalIssues();
              }}
              disabled={localIssues.loading || issueProviders.loading}
            >
              Refresh
            </button>
          </Show>
        </div>
        <Show when={repositoryPath().trim().length > 0} fallback={<p>Set repo path.</p>}>
          <Show when={issueProviders.latest?.ok && issueProviders.latest.data.providers.length > 0}>
            <div class="sync-grid">
              <select
                class="path-input"
                value={issueProviderId()}
                onChange={(event) => setIssueProviderId(event.currentTarget.value)}
              >
                {issueProviders.latest?.ok &&
                  issueProviders.latest.data.providers.map((provider) => (
                    <option value={provider.id}>
                      {provider.displayName} ({provider.mode}) {provider.available ? "" : "- unavailable"}
                    </option>
                  ))}
              </select>
            </div>
          </Show>

          <Show when={selectedIssueProvider()}>
            {(provider) => (
              <p class="issue-meta">
                Provider: {provider().displayName}
                {provider().guidance ? ` - ${provider().guidance}` : ""}
              </p>
            )}
          </Show>

          <div class="sync-grid">
            <input
              class="path-input"
              placeholder="Issue title"
              value={localIssueTitle()}
              onInput={(event) => setLocalIssueTitle(event.currentTarget.value)}
            />
            <textarea
              class="path-input"
              rows={3}
              placeholder="Issue details (optional)"
              value={localIssueBody()}
              onInput={(event) => setLocalIssueBody(event.currentTarget.value)}
            />
          </div>
          <div class="inline-actions">
            <button
              class="primary-btn"
              onClick={() => void onCreateLocalIssue()}
              disabled={localIssueRunning() || !issueProviderAvailable()}
            >
              {localIssueRunning() ? "Creating..." : "Create Issue"}
            </button>
          </div>

          <Show when={localIssueError()}>
            {(message) => <p class="inline-error">{message()}</p>}
          </Show>

          <Show when={localIssues.loading}>
            <p>Loading...</p>
          </Show>

          <Show when={!issueProviderAvailable()}>
            <p class="inline-error">Selected provider is unavailable in this local-first phase. Switch to Local Offline Issues.</p>
          </Show>

          <Show
            when={localIssues.latest?.ok && localIssues.latest.data.issues.length > 0}
            fallback={<p>No issues.</p>}
          >
            <ul class="issue-list">
              {(localIssues.latest?.ok ? localIssues.latest.data.issues : []).map((issue) => {
                const normalized = issue.state.toLowerCase();
                const closed = normalized === "closed";
                const activeAction = issueActionTarget() === issue.id;

                return (
                  <li class="issue-row">
                    <div class="issue-main">
                      <div class="issue-title-row">
                        <strong>{issue.title}</strong>
                        <span class={`status-pill ${closed ? "state-deleted" : "state-staged"}`}>{issue.state}</span>
                      </div>
                      <p class="issue-meta">{issue.id} - updated {formatIssueTimestamp(issue.updatedAt)}</p>
                      <Show when={issue.body.trim().length > 0}>
                        <p>{issue.body}</p>
                      </Show>
                    </div>
                    <button
                      class="primary-btn"
                      onClick={() => void onToggleLocalIssueState(issue.id, issue.state)}
                      disabled={activeAction || !issueProviderAvailable()}
                    >
                      {activeAction ? "Working..." : closed ? "Reopen" : "Close"}
                    </button>
                  </li>
                );
              })}
            </ul>
          </Show>
        </Show>
      </section>

      <section class="state-card">
        <div class="sync-card-header">
          <h3>Pull Requests</h3>
          <Show when={!props.embedded}>
            <button
              class="primary-btn"
              onClick={() => {
                void refetchPullRequestProviders();
                void refetchPullRequests();
              }}
              disabled={pullRequests.loading || pullRequestProviders.loading}
            >
              Refresh
            </button>
          </Show>
        </div>

        <Show when={repositoryPath().trim().length > 0} fallback={<p>Set repo path.</p>}>
          <Show when={pullRequestProviders.latest?.ok && pullRequestProviders.latest.data.providers.length > 0}>
            <div class="sync-grid">
              <select
                class="path-input"
                value={pullRequestProviderId()}
                onChange={(event) => setPullRequestProviderId(event.currentTarget.value)}
              >
                {pullRequestProviders.latest?.ok &&
                  pullRequestProviders.latest.data.providers.map((provider) => (
                    <option value={provider.id}>
                      {provider.displayName} ({provider.mode}) {provider.available ? "" : "- unavailable"}
                    </option>
                  ))}
              </select>
            </div>
          </Show>

          <Show when={selectedPullRequestProvider()}>
            {(provider) => (
              <p class="issue-meta">
                Provider: {provider().displayName}
                {provider().guidance ? ` - ${provider().guidance}` : ""}
              </p>
            )}
          </Show>

          <div class="sync-grid">
            <input
              class="path-input"
              placeholder="Pull request title"
              value={pullRequestTitle()}
              onInput={(event) => setPullRequestTitle(event.currentTarget.value)}
            />
            <textarea
              class="path-input"
              rows={3}
              placeholder="Description (optional)"
              value={pullRequestDescription()}
              onInput={(event) => setPullRequestDescription(event.currentTarget.value)}
            />
            <div class="branch-create-grid">
              <select
                class="path-input"
                value={pullRequestSourceBranch()}
                onChange={(event) => setPullRequestSourceBranch(event.currentTarget.value)}
              >
                {(pullRequestBranches.latest?.ok ? pullRequestBranches.latest.data.branches : []).map((branchInfo) => (
                  <option value={branchInfo.name}>{branchInfo.name}</option>
                ))}
              </select>
              <select
                class="path-input"
                value={pullRequestTargetBranch()}
                onChange={(event) => setPullRequestTargetBranch(event.currentTarget.value)}
              >
                {(pullRequestBranches.latest?.ok ? pullRequestBranches.latest.data.branches : []).map((branchInfo) => (
                  <option value={branchInfo.name}>{branchInfo.name}</option>
                ))}
              </select>
              <button
                class="primary-btn"
                onClick={() => void onCreatePullRequest()}
                disabled={pullRequestRunning() || !pullRequestProviderAvailable()}
              >
                {pullRequestRunning() ? "Creating..." : "Create Pull Request"}
              </button>
            </div>
          </div>

          <div class="inline-actions">
            <label>
              <input
                type="checkbox"
                checked={pullRequestDraft()}
                onChange={(event) => setPullRequestDraft(event.currentTarget.checked)}
              />
              Draft
            </label>
            <label>
              <input
                type="checkbox"
                checked={deleteSourceOnMerge()}
                onChange={(event) => setDeleteSourceOnMerge(event.currentTarget.checked)}
              />
              Delete source on merge
            </label>
          </div>

          <Show when={pullRequestError()}>
            {(message) => <p class="inline-error">{message()}</p>}
          </Show>

          <Show when={pullRequests.loading}>
            <p>Loading pull requests...</p>
          </Show>

          <Show when={!pullRequestProviderAvailable()}>
            <p class="inline-error">Selected provider is unavailable in this local-first phase. Switch to Local Pull Requests.</p>
          </Show>

          <Show
            when={pullRequests.latest?.ok && pullRequests.latest.data.pullRequests.length > 0}
            fallback={<p>No pull requests.</p>}
          >
            <ul class="issue-list">
              {(pullRequests.latest?.ok ? pullRequests.latest.data.pullRequests : []).map((pullRequest) => {
                const normalizedState = pullRequest.state.toLowerCase();
                const isOpen = normalizedState === "open";
                const isClosed = normalizedState === "closed";
                const isMerged = normalizedState === "merged";
                const activeAction = pullRequestActionTarget() === pullRequest.id;
                const badgeClass = isMerged
                  ? "state-staged"
                  : isClosed
                    ? "state-deleted"
                    : pullRequest.draft
                      ? "state-unstaged"
                      : "state-modified";

                return (
                  <li class="issue-row">
                    <div class="issue-main">
                      <div class="issue-title-row">
                        <strong>{pullRequest.title}</strong>
                        <span class={`status-pill ${badgeClass}`}>
                          {pullRequest.state} {pullRequest.draft ? "(draft)" : ""}
                        </span>
                      </div>
                      <p class="issue-meta">
                        {pullRequest.id} - {pullRequest.sourceBranch} to {pullRequest.targetBranch} - updated{" "}
                        {formatIssueTimestamp(pullRequest.updatedAt)}
                      </p>
                      <Show when={pullRequest.description.trim().length > 0}>
                        <p>{pullRequest.description}</p>
                      </Show>
                      <Show when={pullRequest.mergeCommitHash}>
                        {(commitHash) => <p class="issue-meta">Merge commit: {commitHash()}</p>}
                      </Show>
                    </div>
                    <div class="inline-actions">
                      <Show when={isOpen && pullRequest.draft}>
                        <button
                          class="primary-btn"
                          onClick={() => void onOperatePullRequest("ready", pullRequest.id)}
                          disabled={activeAction || !pullRequestProviderAvailable()}
                        >
                          Ready
                        </button>
                      </Show>
                      <Show when={isOpen && !pullRequest.draft}>
                        <button
                          class="primary-btn"
                          onClick={() => void onOperatePullRequest("merge", pullRequest.id)}
                          disabled={activeAction || !pullRequestProviderAvailable()}
                        >
                          Merge
                        </button>
                      </Show>
                      <Show when={isOpen}>
                        <button
                          class="primary-btn"
                          onClick={() => void onOperatePullRequest("close", pullRequest.id)}
                          disabled={activeAction || !pullRequestProviderAvailable()}
                        >
                          Close
                        </button>
                      </Show>
                      <Show when={isClosed}>
                        <button
                          class="primary-btn"
                          onClick={() => void onOperatePullRequest("reopen", pullRequest.id)}
                          disabled={activeAction || !pullRequestProviderAvailable()}
                        >
                          Reopen
                        </button>
                      </Show>
                    </div>
                  </li>
                );
              })}
            </ul>
          </Show>
        </Show>
      </section>

      <section class="state-card">
        <h3>AI Diff Review</h3>
        <div class="sync-grid">
          <select class="path-input" value={reviewProviderId()} onChange={(event) => setReviewProviderId(event.currentTarget.value)}>
            {(providers.latest?.ok ? providers.latest.data.providers : []).map((provider) => (
              <option value={provider.id}>
                {provider.id} ({provider.available ? "available" : "missing"})
              </option>
            ))}
          </select>
          <input
            class="path-input"
            placeholder="Scope path (optional)"
            value={reviewScopePath()}
            onInput={(event) => setReviewScopePath(event.currentTarget.value)}
          />
          <Show when={!props.embedded}>
            <button class="primary-btn" onClick={() => void refetchProviders()}>
              Refresh Providers
            </button>
          </Show>
        </div>
        <textarea
          class="path-input"
          rows={3}
          value={reviewPrompt()}
          onInput={(event) => setReviewPrompt(event.currentTarget.value)}
        />
        <div class="inline-actions">
          <button class="primary-btn" onClick={() => void onRunReview()} disabled={reviewRunning()}>
            {reviewRunning() ? "Running Review..." : "Run Review"}
          </button>
          <button class="primary-btn" onClick={() => void onCancelReview()} disabled={!reviewRunning()}>
            Cancel Review
          </button>
        </div>
      </section>

      <Show when={syncOutput()}>
        {(message) => <section class="state-card"><pre class="sync-output">{message()}</pre></section>}
      </Show>

      <Show when={syncError()}>
        {(message) => <ErrorStateCard title="Sync operation failed" body={message()} />}
      </Show>
    </div>
  );
}
