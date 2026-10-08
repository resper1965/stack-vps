import * as React from "react";

/**
 * Confirmação de ação com janela de desfazer (4200ms). Toda edição imediata e
 * toda ação em lote passam por aqui.
 *
 * @startingPoint section="Core" subtitle="Confirmação com desfazer" viewport="700x140"
 */
export interface ToastProps {
  /** Texto em português, no passado: "3 controles atribuídos a TI". */
  message?: string;
  /** Sem callback não há botão — mas então a ação deveria ser reversível de outro jeito. */
  onUndo?: () => void;
  undoLabel?: string;
}

export declare function Toast(props: ToastProps): JSX.Element | null;
