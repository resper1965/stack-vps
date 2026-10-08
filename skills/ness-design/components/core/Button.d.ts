import * as React from "react";

/**
 * Ação da interface. O primário é o único objeto sólido da tela.
 *
 * @startingPoint section="Core" subtitle="Primário, secundário, ghost e perigo" viewport="700x150"
 */
export interface ButtonProps {
  /** primary: preenchimento BlueDot com tinta escura. danger: ação destrutiva, só texto vermelho. */
  variant?: "primary" | "secondary" | "ghost" | "danger";
  /** md = 34px (padrão) · sm = 30px, para barra de lote */
  size?: "md" | "sm";
  /** Desabilitado mantém o botão visível e exige `disabledReason` — o usuário precisa saber por quê. */
  disabled?: boolean;
  /** Motivo exibido em title quando desabilitado. Obrigatório na prática. */
  disabledReason?: string;
  /** Ícone Lucide (stroke 1.5, 14–16px) à esquerda do rótulo. */
  icon?: React.ReactNode;
  children?: React.ReactNode;
  onClick?: () => void;
}

export declare function Button(props: ButtonProps): JSX.Element;
