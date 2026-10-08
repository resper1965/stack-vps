import React from "react";

/**
 * Botão — primário (preenchimento BlueDot), secundário (hairline) e perigo.
 * O preenchimento ciano leva tinta escura: branco sobre #00ADE8 dá 2.6:1.
 */
export function Button({ variant = "secondary", size = "md", disabled, disabledReason, icon, children, onClick, ...rest }) {
  const h = size === "sm" ? "var(--control-h-sm)" : "var(--control-h)";
  const base = {
    display: "inline-flex", alignItems: "center", justifyContent: "center", gap: "var(--space-2)",
    height: h, padding: `0 ${size === "sm" ? "12px" : "14px"}`,
    font: "500 12px/1 var(--font-body)", whiteSpace: "nowrap",
    borderRadius: "var(--radius)", border: "1px solid transparent",
    transition: "border-color var(--dur-fast) var(--ease-out), background var(--dur-fast) var(--ease-out)"
  };
  const variants = {
    primary: { background: "var(--accent)", color: "var(--accent-ink)" },
    secondary: { border: "1px solid var(--border-hairline)", color: "var(--text-secondary)" },
    ghost: { color: "var(--text-muted)" },
    danger: { border: "1px solid var(--border-hairline)", color: "var(--ness-bad)" }
  };
  const off = disabled
    ? { border: "1px solid var(--border-hairline)", background: "none", color: "var(--text-faint)", cursor: "not-allowed" }
    : null;

  return (
    <button
      type="button"
      onClick={disabled ? undefined : onClick}
      aria-disabled={disabled || undefined}
      title={disabled ? disabledReason : rest.title}
      style={{ ...base, ...variants[variant], ...off }}
      {...rest}
    >
      {icon}
      {children}
    </button>
  );
}
