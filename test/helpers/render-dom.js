import { renderProjection } from "../../src/projections.js";

// The stub DOM `src/projections.js` renders into. It is sized to exactly what
// the renderer touches while building Intimate day columns and radial-family
// SVG (createElement/createElementNS, style, dataset, classList, append/
// replaceChildren) and no further -- real enough to run `renderProjection` end
// to end and inspect the elements it actually produced, so tests over it are
// behavioral rather than assertions about source text.
//
// It lives here rather than inside one test file because more than one suite
// needs to render a lens: the lens-behaviour checks and the coordinate-law
// acceptance test both do, and a second copy of a DOM stub is a second set of
// silent divergences in what "the DOM does" means.
export function createRenderStubDom() {
  class StubElement {
    constructor(tag) {
      this.tagName = String(tag).toUpperCase();
      this.className = "";
      this.textContent = "";
      this.dataset = {};
      this.children = [];
      this.parentElement = null;
      this.attributes = new Map();
      this.clientHeight = 900;
      const node = this;
      this.style = {
        setProperty(name, value) { this[name] = String(value); },
        getPropertyValue(name) { return this[name] ?? ""; }
      };
      this.classList = {
        add(cls) { node.className = node.className ? `${node.className} ${cls}` : cls; }
      };
    }

    append(...nodes) {
      for (const n of nodes) { n.parentElement = this; this.children.push(n); }
    }

    replaceChildren(...nodes) {
      this.children = [];
      this.append(...nodes);
    }

    setAttribute(name, value) {
      this.attributes.set(name, String(value));
      // svgElement() sets the SVG "class" attribute via setAttribute rather
      // than the className property element() gives HTML nodes -- mirror the
      // way a real DOM keeps className and the class attribute in sync, so
      // classList.add and an attribute-set class both land where findByClass
      // reads.
      if (name === "class") this.className = String(value);
    }

    getAttribute(name) { return this.attributes.get(name) ?? null; }

    descendants() {
      return this.children.flatMap((child) => [child, ...child.descendants()]);
    }
  }
  const documentStub = {
    createElement: (tag) => new StubElement(tag),
    createElementNS: (_ns, tag) => new StubElement(tag)
  };
  return { StubElement, documentStub };
}

// Runs renderProjection with the document global stubbed for exactly the
// duration of the call, and always restores it -- a leaked stub `document`
// would corrupt every test that runs after this one in the same process.
export function renderWithStubDom(context) {
  const { StubElement, documentStub } = createRenderStubDom();
  const previousDocument = globalThis.document;
  globalThis.document = documentStub;
  const target = new StubElement("div");
  try {
    renderProjection(target, context);
    return target;
  } finally {
    globalThis.document = previousDocument;
  }
}

export function findByClass(root, className) {
  return root.descendants().filter((node) => String(node.className).split(/\s+/).includes(className));
}
