import { createMemo, createSignal } from "solid-js";

type RenderMode = "dom" | "canvas";

interface DiffShellProps {
  filePath?: string;
  diffText?: string;
}

const RENDER_POLICY = {
  canvasLineThreshold: 1600,
  canvasCharThreshold: 100000
} as const;

function detectLineKind(line: string): "added" | "deleted" | "hunk" | "meta" | "context" {
  if (line.startsWith("@@")) {
    return "hunk";
  }
  if (line.startsWith("+") && !line.startsWith("+++")) {
    return "added";
  }
  if (line.startsWith("-") && !line.startsWith("---")) {
    return "deleted";
  }
  if (line.startsWith("diff --git") || line.startsWith("index ") || line.startsWith("---") || line.startsWith("+++")) {
    return "meta";
  }
  return "context";
}

function pickDefaultMode(text: string): RenderMode {
  const lineCount = text.split("\n").length;
  const charCount = text.length;
  if (lineCount > RENDER_POLICY.canvasLineThreshold || charCount > RENDER_POLICY.canvasCharThreshold) {
    return "canvas";
  }
  return "dom";
}

export function DiffShell(props: DiffShellProps) {
  const [searchTerm, setSearchTerm] = createSignal("");

  const normalizedDiff = createMemo(() => props.diffText ?? "");
  const defaultMode = createMemo(() => pickDefaultMode(normalizedDiff()));
  const [mode, setMode] = createSignal<RenderMode>(defaultMode());

  const parsedLines = createMemo(() =>
    normalizedDiff()
      .split("\n")
      .map((line, index) => ({
        line,
        kind: detectLineKind(line),
        number: index + 1
      }))
  );

  const visibleLines = createMemo(() => {
    const needle = searchTerm().trim().toLowerCase();
    if (!needle) {
      return parsedLines();
    }
    return parsedLines().filter((entry) => entry.line.toLowerCase().includes(needle));
  });

  return (
    <section class="diff-shell" data-render-mode={mode()}>
      <header class="diff-header">
        <h2>Diff {props.filePath ? `- ${props.filePath}` : ""}</h2>
        <div class="diff-controls">
          <button class={`mode-toggle ${mode() === "dom" ? "is-active" : ""}`} onClick={() => setMode("dom")}>
            DOM
          </button>
          <button
            class={`mode-toggle ${mode() === "canvas" ? "is-active" : ""}`}
            onClick={() => setMode("canvas")}
          >
            Canvas
          </button>
          <input
            class="diff-search"
            placeholder="Search in diff"
            aria-label="Search in diff"
            value={searchTerm()}
            onInput={(event) => setSearchTerm(event.currentTarget.value)}
          />
        </div>
      </header>
      <div class="diff-viewport">
        {normalizedDiff().trim().length === 0 ? (
          <div class="diff-viewport-dom">Select a changed file to load diff output.</div>
        ) : mode() === "dom" ? (
          <div class="diff-viewport-dom">
            {visibleLines().map((entry) => (
              <div class={`diff-line diff-line-${entry.kind}`}>
                <span class="diff-line-number">{entry.number}</span>
                <span class="diff-line-text">{entry.line || " "}</span>
              </div>
            ))}
          </div>
        ) : (
          <div class="diff-viewport-canvas">
            Canvas mode policy selected for large diff ({parsedLines().length} lines). DOM fallback remains available.
          </div>
        )}
      </div>
    </section>
  );
}
