import React from "react";

/** Item de navegação da sidebar. Ativo: barra accent + ícone na cor de marca. */
export function NavItem({ icon, label, active, collapsed, onClick }) {
  return (
    <button
      type="button"
      onClick={onClick}
      title={collapsed ? label : undefined}
      aria-current={active ? "page" : undefined}
      style={{
        display: "flex", alignItems: "center", gap: "var(--space-3)",
        height: "var(--nav-item-h)", padding: `0 ${collapsed ? "24px" : "20px"}`,
        font: `400 13px/1 var(--font-body)`,
        fontWeight: active ? 500 : 400,
        color: active ? "var(--text-primary)" : "var(--text-muted)",
        boxShadow: active ? "inset 2px 0 0 var(--accent)" : "none",
        transition: "color var(--dur-fast) var(--ease-out)"
      }}
    >
      <span style={{ flex: "none", display: "flex", color: active ? "var(--accent)" : "currentColor", opacity: active ? 1 : .5 }}>{icon}</span>
      {!collapsed && <span>{label}</span>}
    </button>
  );
}
