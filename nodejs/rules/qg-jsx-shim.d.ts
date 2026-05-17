// QG -- ambient JSX shim (tamper-resistance / robustness).
//
// When the target project did NOT install React/React Native types
// (@types/react, etc.) in node_modules, QG's strict `tsc` spits
// TS7026 ("no interface 'JSX.IntrinsicElements' exists") / TS2875 on
// EVERY JSX tag -- hundreds of phantom errors that mask real type
// errors. This shim declares a permissive JSX.IntrinsicElements ONLY as
// a global fallback: if the project provides @types/react, React's real
// types take precedence (same namespace, the project's declaration wins
// in module resolution). The shim does NOT loosen the strictness of the
// dev's TS code -- it only prevents JSX-without-types noise. Real type
// errors (string -> number, implicit any param, etc.) are still caught.

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
