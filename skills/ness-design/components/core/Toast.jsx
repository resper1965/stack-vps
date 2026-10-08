import React from "react";

/**
 * Toast com Desfazer — o par obrigatório da gravação imediata.
 * A mensagem também deve ser escrita numa região .ness-live permanente.
 */
export function Toast({ message, onUndo, undoLabel = "Desfazer" }) {
  if (!message) return null;
  return (
    <div style={{
      position: "fixed", left: "var(--space-7)", bottom: "var(--space-7)", zIndex: 10,
      display: "flex", alignItems: "center", gap: "var(--space-3)",
      padding: "12px 16px", background: "var(--surface-raised)",
      borderLeft: "2px solid var(--accent)",
      font: "400 12.5px/1 var(--font-body)", color: "var(--text-primary)",
      animation: "ness-rise var(--dur-normal) var(--ease-out)"
    }}>
      {message}
      {onUndo && (
        <button type="button" onClick={onUndo} style={{ font: "500 12.5px/1 var(--font-body)", color: "var(--accent)" }}>
          {undoLabel}
        </button>
      )}
    </div>
  );
}
