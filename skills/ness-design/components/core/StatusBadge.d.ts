import * as React from "react";

/**
 * Estado de um registro em lista ou detalhe.
 *
 * @startingPoint section="Core" subtitle="Status sem borda, tinta sobre tinta" viewport="700x110"
 */
export interface StatusBadgeProps {
  /** ok: implementado/aprovado · warn: parcial/pendente · bad: gap/rejeitado · info: em análise · neutral: n/a */
  tone?: "ok" | "warn" | "bad" | "info" | "neutral";
  /** Rótulo em português. Nunca a chave interna do banco. */
  children?: React.ReactNode;
}

export declare function StatusBadge(props: StatusBadgeProps): JSX.Element;
