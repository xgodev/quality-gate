// QG -- shim ambiente de JSX (tamper-resistance / robustez).
//
// Quando o projeto-alvo NAO instalou tipos de React/React Native
// (@types/react, etc.) no node_modules, o `tsc` strict do QG cospe
// TS7026 ("no interface 'JSX.IntrinsicElements' exists") / TS2875 em
// CADA tag JSX -- centenas de erros fantasma que mascaram erros de tipo
// reais. Este shim declara um JSX.IntrinsicElements permissivo SO como
// fallback global: se o projeto fornece @types/react, os tipos reais do
// React tem precedencia (mesma namespace, declaracao do projeto vence
// em resolucao de modulo). O shim NAO afrouxa strictness do codigo TS
// do dev -- so impede ruido de JSX sem tipos. Erros de tipo reais
// (string -> number, param implicito any, etc.) continuam sendo pegos.

declare namespace JSX {
  interface IntrinsicElements {
    [elemName: string]: any;
  }
  interface ElementClass {
    render?: any;
  }
  interface ElementAttributesProperty {
    props: any;
  }
  interface ElementChildrenAttribute {
    children: any;
  }
}

declare module "react/jsx-runtime" {
  export const jsx: any;
  export const jsxs: any;
  export const Fragment: any;
}

declare module "react/jsx-dev-runtime" {
  export const jsxDEV: any;
  export const Fragment: any;
}
