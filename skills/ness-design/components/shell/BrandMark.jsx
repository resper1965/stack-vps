import React from "react";

/** Marca do produto: caixa baixa, ponto interno em BlueDot. Nunca itálico. */
export function BrandMark({ product = "n.iso", size = 22 }) {
  const [head, ...rest] = product.split(".");
  return (
    <span className="ness-brand" style={{ fontSize: size }}>
      {head}<span className="dot">.</span>{rest.join(".")}
    </span>
  );
}
