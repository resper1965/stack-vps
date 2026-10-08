import * as React from "react";

/**
 * Banda de título fixa do conteúdo. Sem subtítulo: contexto de tenant vive no
 * seletor da sidebar e contexto de registro é a primeira linha do conteúdo.
 *
 * @startingPoint section="Shell" subtitle="Banda de título fixa com ações" viewport="700x120"
 */
export interface PageHeaderProps {
  /** Nome da tela: "SoA", "Riscos", "Dashboard". Nunca o nome do cliente. */
  title: string;
  /** Botões alinhados à direita; no máximo uma ação primária. */
  actions?: React.ReactNode;
}

export declare function PageHeader(props: PageHeaderProps): JSX.Element;
