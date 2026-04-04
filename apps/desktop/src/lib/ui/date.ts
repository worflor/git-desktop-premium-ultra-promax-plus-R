/**
 * Utility for formatting commit dates in a human-readable way.
 */

export type DateFormat = "relative" | "absolute";

/**
 * Formats a date string (ISO 8601) into a relative time string (e.g., "2m ago")
 * or a friendly absolute format if it's too old.
 */
export function formatCommitDate(isoString: string, mode: DateFormat = "relative"): string {
  if (!isoString) return "";
  
  const date = new Date(isoString);
  if (isNaN(date.getTime())) return isoString;

  if (mode === "absolute") {
    return date.toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
    });
  }

  const now = new Date();
  const diffInSeconds = Math.floor((now.getTime() - date.getTime()) / 1000);

  if (diffInSeconds < 60) {
    return "just now";
  }

  const diffInMinutes = Math.floor(diffInSeconds / 60);
  if (diffInMinutes < 60) {
    return `${diffInMinutes}m ago`;
  }

  const diffInHours = Math.floor(diffInMinutes / 60);
  if (diffInHours < 24) {
    return `${diffInHours}h ago`;
  }

  const diffInDays = Math.floor(diffInHours / 24);
  if (diffInDays < 7) {
    if (diffInDays === 1) return "yesterday";
    return `${diffInDays}d ago`;
  }

  // Fallback to absolute date for older commits even in relative mode
  return date.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: date.getFullYear() !== now.getFullYear() ? "numeric" : undefined,
  });
}

/**
 * Returns a full detailed string for tooltips.
 */
export function formatFullDate(isoString: string): string {
  if (!isoString) return "";
  const date = new Date(isoString);
  if (isNaN(date.getTime())) return isoString;
  const iso = date.toISOString();
  return (iso.split(".")[0] || iso).replace("T", " ");
}
