import React from "react";

/**
 * Banda de título fixa. Mesma altura da banda da marca — as duas fecham na
 * mesma hairline. O título nomeia a TELA, nunca o cliente.
 */
export function PageHeader({ title, actions }) {
  return (
    <header style={{
      position: "sticky", top: 0, zIndex: 4,
      height: "var(--shell-header-h)", flex: "none",
      display: "flex", alignItems: "center", gap: "var(--space-4)",
      padding: `0 ${"var(--space-7)"}`,
      background: "var(--surface-page)",
      borderBottom: "1px solid var(--border-hairline)"
    }}>
      <h1 style={{
        margin: 0, flex: 1, minWidth: 0,
        font: "var(--type-h1)", letterSpacing: "var(--tracking-title)"
      }}>{title}</h1>
      {actions}
    </header>
  );
}
