import React from "react";

/** Chip de faceta — filtro acumulável. Ativo assume a cor de marca. */
export function Chip({ active, count, children, onClick, ...rest }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={!!active}
      style={{
        display: "inline-flex", alignItems: "center", gap: "var(--space-2)",
        height: "var(--control-h-sm)", padding: "0 12px",
        font: "400 12px/1 var(--font-body)", whiteSpace: "nowrap",
        border: `1px solid ${active ? "var(--accent)" : "var(--border-hairline)"}`,
        color: active ? "#7fd6f6" : "var(--text-muted)",
        background: active ? "var(--ness-bluedot-tint)" : "transparent",
        borderRadius: "var(--radius)",
        transition: "border-color var(--dur-fast) var(--ease-out)"
      }}
      {...rest}
    >
      {children}
      {count !== undefined && (
        <span style={{ font: "400 10px/1 var(--font-mono)", color: "var(--text-faint)" }}>{count}</span>
      )}
      {active && <span aria-hidden="true" style={{ color: "inherit" }}>×</span>}
    </button>
  );
}
