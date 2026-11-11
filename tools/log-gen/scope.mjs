// Lightweight scope parser for ArkTS classes/structs and methods.
//
// It is not a full AST. It tracks brace depth and recognizes class/struct
// headers plus method headers at class-body depth. Comments and strings must
// already be masked (see scanner.mjs). This is enough for call-site attribution
// and is covered by tests; explicit class/method overrides in the event catalog
// handle unusual formatting.

const CONTROL = new Set([
  'if', 'for', 'while', 'switch', 'catch', 'function', 'return', 'new', 'else',
  'do', 'try', 'finally', 'with', 'ForEach', 'LazyForEach', 'Repeat', 'then',
]);

const DECORATOR = String.raw`(?:@[A-Za-z_$][A-Za-z0-9_$]*(?:\([^)]*\))?\s*)*`;
const MODIFIER = String.raw`(?:(?:public|private|protected|static|async|readonly|override|abstract|declare|export)\s+)*`;
const CLASS_RE = new RegExp(
  String.raw`(?:^|\n)\s*${DECORATOR}(?:export\s+)?(?:default\s+)?(?:abstract\s+)?(class|struct)\s+([A-Za-z_$][A-Za-z0-9_$]*)`,
);
const METHOD_RE = new RegExp(
  String.raw`(?:^|\n)\s*${DECORATOR}${MODIFIER}(?:get\s+|set\s+)?([A-Za-z_$][A-Za-z0-9_$]*)\s*(?:<[^<>{}]*>)?\s*\(`,
);

export function parseScopes(masked) {
  const classes = [];
  const methods = [];
  const classStack = [];
  let depth = 0;
  let currentClass = null;
  let buffer = '';
  let paren = 0;
  let bracket = 0;

  const openClass = (name, open) => {
    const entry = { name, open, close: masked.length, bodyDepth: depth + 1 };
    classes.push(entry);
    classStack.push(entry);
    currentClass = entry;
  };
  const openMethod = (name, open) => {
    const entry = {
      name,
      className: currentClass === null ? '' : currentClass.name,
      open,
      close: masked.length,
      bodyDepth: depth + 1,
    };
    methods.push(entry);
  };
  const closeScopes = (at) => {
    for (const method of methods) {
      if (method.close === masked.length && method.bodyDepth > depth) {
        method.close = at;
      }
    }
    while (classStack.length > 0 && classStack[classStack.length - 1].bodyDepth > depth) {
      const cls = classStack.pop();
      cls.close = at;
    }
    currentClass = classStack.length === 0 ? null : classStack[classStack.length - 1];
  };

  for (let i = 0; i < masked.length; i++) {
    const c = masked[i];
    if (c === '{') {
      const classMatch = CLASS_RE.exec(buffer);
      if (classMatch !== null) {
        openClass(classMatch[2], i);
      } else if (currentClass !== null && depth === currentClass.bodyDepth) {
        const methodName = matchMethod(buffer);
        if (methodName !== '') {
          openMethod(methodName, i);
        }
      } else if (currentClass === null && depth === 0) {
        const fn = matchTopLevelFunction(buffer);
        if (fn !== '') {
          openMethod(fn, i);
        }
      }
      depth++;
      buffer = '';
      paren = 0;
      bracket = 0;
      continue;
    }
    if (c === '}') {
      depth--;
      closeScopes(i);
      buffer = '';
      paren = 0;
      bracket = 0;
      continue;
    }
    if (c === ';') {
      if (paren === 0 && bracket === 0 &&
        (depth === 0 || (currentClass !== null && depth === currentClass.bodyDepth))) {
        buffer = '';
      }
      continue;
    }
    if (c === '(') {
      paren++;
    } else if (c === ')') {
      paren = paren > 0 ? paren - 1 : 0;
    } else if (c === '[') {
      bracket++;
    } else if (c === ']') {
      bracket = bracket > 0 ? bracket - 1 : 0;
    }
    if (buffer.length < 4000) {
      buffer += c;
    }
  }
  closeScopes(masked.length);
  return { classes, methods };
}

export function scopeAt(classes, methods, offset) {
  let cls = null;
  for (const item of classes) {
    if (offset > item.open && offset < item.close) {
      if (cls === null || item.open > cls.open) {
        cls = item;
      }
    }
  }
  let method = null;
  for (const item of methods) {
    if (offset > item.open && offset < item.close) {
      if (method === null || item.open > method.open) {
        method = item;
      }
    }
  }
  let className = cls === null ? '' : cls.name;
  let methodName = method === null ? '' : method.name;
  if (method !== null && method.className !== '') {
    className = method.className;
  }
  return { className, methodName };
}

export function detectScope(masked, offset) {
  const parsed = parseScopes(masked);
  return scopeAt(parsed.classes, parsed.methods, offset);
}

function matchMethod(header) {
  const text = header.trim();
  if (text === '') {
    return '';
  }
  const lastParen = text.lastIndexOf(')');
  const lastArrow = text.lastIndexOf('=>');
  if (lastArrow > lastParen) {
    return '';
  }
  const m = METHOD_RE.exec(text);
  if (m === null) {
    return '';
  }
  const name = m[1];
  if (CONTROL.has(name)) {
    return '';
  }
  return name;
}

function matchTopLevelFunction(header) {
  const m = /(?:^|\n)\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*\(/.exec(header);
  return m === null ? '' : m[1];
}
