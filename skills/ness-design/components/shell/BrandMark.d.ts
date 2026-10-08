import * as React from "react";

/**
 * Marca de um produto da família (`n.iso`, `n.priv`, `n.risk`). O ponto interno
 * é sempre BlueDot, em qualquer fundo.
 *
 * @startingPoint section="Shell" subtitle="Marca do produto com BlueDot" viewport="700x110"
 */
export interface BrandMarkProps {
  /** Nome em caixa baixa com o ponto interno: "n.iso". */
  product?: string;
  /** Tamanho em px. 22 no shell, 24+ em autenticação. */
  size?: number;
}

export declare function BrandMark(props: BrandMarkProps): JSX.Element;
