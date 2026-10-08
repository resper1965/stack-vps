import * as React from "react";

/**
 * Destino de navegação na sidebar. Para item que é registro com estado (fase,
 * relatório numerado), use um ponto de 8px em vez de ícone: ali o glifo informa
 * progresso, não categoria.
 *
 * @startingPoint section="Shell" subtitle="Item de navegação, ativo e recolhido" viewport="700x160"
 */
export interface NavItemProps {
  /** Ícone Lucide, stroke 1.5, 16px. */
  icon?: React.ReactNode;
  label: string;
  active?: boolean;
  /** Modo trilha (72px): oculta o rótulo e move para o title. */
  collapsed?: boolean;
  onClick?: () => void;
}

export declare function NavItem(props: NavItemProps): JSX.Element;
