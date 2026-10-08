import React from "react";

const TONES = {
  ok: "var(--ness-ok)",
  warn: "var(--ness-warn)",
  bad: "var(--ness-bad)",
  info: "var(--ness-info)",
  neutral: "var(--text-muted)"
};

/** Badge de status — tinta colorida sobre 16% da própria cor, sem borda. */
export function StatusBadge({ tone = "neutral", children }) {
  const c = TONES[tone] || TONES.neutral;
  return (
    <span style={{
      display: "inline-block",
      font: "500 10px/1.7 var(--font-mono)",
      letterSpacing: ".08em", textTransform: "uppercase",
      padding: "1px 8px", borderRadius: "var(--radius)",
      color: c, background: `color-mix(in oklab, ${c} 16%, transparent)`
    }}>{children}</span>
  );
}
