// Event-catalog schema validation. No external dependencies.
// Mirrors the "validate everything before emitting" rule used by Dashiell json-gen.

const RESERVED = new Set([
  'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger', 'default',
  'delete', 'do', 'else', 'enum', 'export', 'extends', 'false', 'finally', 'for',
  'function', 'if', 'import', 'in', 'instanceof', 'let', 'new', 'null', 'return',
  'super', 'switch', 'this', 'throw', 'true', 'try', 'typeof', 'var', 'void',
  'while', 'with', 'as', 'implements', 'interface', 'package', 'private',
  'protected', 'public', 'static', 'yield', 'constructor', 'error', 'fields',
]);

const LEVELS = new Set(['TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL']);
const TYPES = new Set(['string', 'number', 'boolean', 'json']);

export function parseCatalog(text) {
  let raw;
  try {
    raw = JSON.parse(text);
  } catch (e) {
    throw new Error(`events JSON parse failed: ${e.message}`);
  }
  return validateCatalog(raw);
}

export function validateCatalog(raw) {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new Error('events root must be an object');
  }
  if (raw.schemaVersion !== 1) {
    throw new Error(`unsupported events schemaVersion: ${String(raw.schemaVersion)} (expected 1)`);
  }
  if (!Array.isArray(raw.events) || raw.events.length === 0) {
    throw new Error('events must be a non-empty array');
  }
  const names = new Set();
  const events = raw.events.map((value, index) => {
    const where = `events[${index}]`;
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error(`${where} must be an object`);
    }
    const name = requireString(value.name, `${where}.name`);
    if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(name)) {
      throw new Error(`${where}.name is not a valid ArkTS identifier: ${name}`);
    }
    if (RESERVED.has(name)) {
      throw new Error(`${where}.name is reserved: ${name}`);
    }
    if (names.has(name)) {
      throw new Error(`${where}.name is duplicated: ${name}`);
    }
    names.add(name);

    const tag = requireString(value.tag, `${where}.tag`);
    if (Buffer.byteLength(tag, 'utf8') > 31) {
      throw new Error(`${where}.tag exceeds 31 UTF-8 bytes (hilog limit): ${tag}`);
    }
    const level = requireString(value.level, `${where}.level`).toUpperCase();
    if (!LEVELS.has(level)) {
      throw new Error(`${where}.level must be one of ${Array.from(LEVELS).join(', ')}`);
    }
    const zh = requireString(value.zh, `${where}.zh`);
    const en = requireString(value.en, `${where}.en`);
    const error = value.error === undefined ? true : requireBoolean(value.error, `${where}.error`);
    const className = optionalString(value.class, `${where}.class`);
    const methodName = optionalString(value.method, `${where}.method`);

    const fields = (value.fields === undefined ? [] : value.fields).map((field, fieldIndex) => {
      const fwhere = `${where}.fields[${fieldIndex}]`;
      if (field === null || typeof field !== 'object' || Array.isArray(field)) {
        throw new Error(`${fwhere} must be an object`);
      }
      const fieldName = requireString(field.name, `${fwhere}.name`);
      if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(fieldName)) {
        throw new Error(`${fwhere}.name is not a valid ArkTS identifier: ${fieldName}`);
      }
      if (RESERVED.has(fieldName)) {
        throw new Error(`${fwhere}.name is reserved: ${fieldName}`);
      }
      const type = requireString(field.type, `${fwhere}.type`);
      if (!TYPES.has(type)) {
        throw new Error(`${fwhere}.type must be one of ${Array.from(TYPES).join(', ')}`);
      }
      const required = field.required === undefined ? true : requireBoolean(field.required, `${fwhere}.required`);
      const fieldZh = optionalString(field.zh, `${fwhere}.zh`);
      const fieldEn = optionalString(field.en, `${fwhere}.en`);
      return { name: fieldName, type, required, zh: fieldZh, en: fieldEn };
    });
    const fieldNames = new Set();
    for (const field of fields) {
      if (fieldNames.has(field.name)) {
        throw new Error(`${where}.fields has duplicate name: ${field.name}`);
      }
      fieldNames.add(field.name);
    }

    return {
      name,
      tag,
      level,
      zh,
      en,
      error,
      class: className,
      method: methodName,
      fields,
    };
  });
  events.sort((a, b) => a.name.localeCompare(b.name));
  return { schemaVersion: 1, events };
}

function requireString(value, where) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`${where} must be a non-empty string`);
  }
  return value;
}

function optionalString(value, where) {
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value !== 'string') {
    throw new Error(`${where} must be a string when present`);
  }
  return value.trim();
}

function requireBoolean(value, where) {
  if (typeof value !== 'boolean') {
    throw new Error(`${where} must be a boolean`);
  }
  return value;
}
