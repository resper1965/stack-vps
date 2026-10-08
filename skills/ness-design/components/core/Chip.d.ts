import * as React from "react";

/**
 * Faceta de filtro, acumulável. Ativo mostra `×` porque remover é a ação esperada.
 *
 * @startingPoint section="Core" subtitle="Faceta de filtro com contagem" viewport="700x120"
 */
export interface ChipProps {
  active?: boolean;
  /** Contagem do recorte. Exibir quando conhecida — evita o clique que leva ao vazio. */
  count?: number;
  children?: React.ReactNode;
  onClick?: () => void;
}

export declare function Chip(props: ChipProps): JSX.Element;
