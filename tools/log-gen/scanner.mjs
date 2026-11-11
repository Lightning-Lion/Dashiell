// Source scanning: mask comments/strings, then find LogEvents.<name>( call sites.

/**
 * Replace comments and string literals with spaces while preserving every
 * newline and character offset. This keeps line/column math exact.
 *
 * Template literals are masked as a whole. A call inside `${...}` is not a
 * supported event site; put the event call in normal code.
 */
export function maskSource(text) {
  const out = new Array(text.length);
  let state = 'code';
  let i = 0;
  while (i < text.length) {
    const c = text[i];
    const n = text[i + 1];
    if (state === 'line') {
      if (c === '\n' || c === '\r') {
        out[i] = c;
        state = 'code';
      } else {
        out[i] = ' ';
      }
      i++;
      continue;
    }
    if (state === 'block') {
      if (c === '*' && n === '/') {
        out[i] = ' ';
        out[i + 1] = ' ';
        i += 2;
        state = 'code';
        continue;
      }
      out[i] = (c === '\n' || c === '\r') ? c : ' ';
      i++;
      continue;
    }
    if (state === 'single' || state === 'double' || state === 'template') {
      const quote = state === 'single' ? "'" : state === 'double' ? '"' : '`';
      if (c === '\\') {
        out[i] = ' ';
        if (i + 1 < text.length) {
          out[i + 1] = (text[i + 1] === '\n' || text[i + 1] === '\r') ? text[i + 1] : ' ';
        }
        i += 2;
        continue;
      }
      if (c === quote) {
        out[i] = ' ';
        state = 'code';
        i++;
        continue;
      }
      if ((c === '\n' || c === '\r') && state !== 'template') {
        // Defensive: an unterminated single/double string must not mask the rest.
        out[i] = c;
        state = 'code';
        i++;
        continue;
      }
      out[i] = (c === '\n' || c === '\r') ? c : ' ';
      i++;
      continue;
    }
    // code
    if (c === '/' && n === '/') {
      out[i] = ' ';
      out[i + 1] = ' ';
      i += 2;
      state = 'line';
      continue;
    }
    if (c === '/' && n === '*') {
      out[i] = ' ';
      out[i + 1] = ' ';
      i += 2;
      state = 'block';
      continue;
    }
    if (c === "'") {
      out[i] = ' ';
      i++;
      state = 'single';
      continue;
    }
    if (c === '"') {
      out[i] = ' ';
      i++;
      state = 'double';
      continue;
    }
    if (c === '`') {
      out[i] = ' ';
      i++;
      state = 'template';
      continue;
    }
    out[i] = c;
    i++;
  }
  return out.join('');
}

/** 1-based line/column for a character offset. */
export function positionAt(text, offset) {
  let line = 1;
  let lineStart = 0;
  for (let i = 0; i < offset && i < text.length; i++) {
    if (text[i] === '\n') {
      line++;
      lineStart = i + 1;
    }
  }
  return { line, column: offset - lineStart + 1 };
}

/**
 * Find every LogEvents.<name>( occurrence in masked source.
 * Returns { calls, unknown }.
 */
export function scanCalls(masked, file, eventNames) {
  const known = new Set(eventNames);
  const calls = [];
  const unknown = [];
  const re = /\bLogEvents\s*\.\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*\(/g;
  let match;
  while ((match = re.exec(masked)) !== null) {
    const before = match.index === 0 ? '' : masked[match.index - 1];
    if (before === '.' || /[A-Za-z0-9_$]/.test(before)) {
      continue;
    }
    const name = match[1];
    const pos = positionAt(masked, match.index);
    const site = {
      event: name,
      file,
      line: pos.line,
      column: pos.column,
      offset: match.index,
    };
    if (known.has(name)) {
      calls.push(site);
    } else {
      unknown.push(site);
    }
  }
  return { calls, unknown };
}
