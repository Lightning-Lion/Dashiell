//! Schema front end. Emit validated descriptors, never ArkTS source.
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum JSONScalarType {
    String,
    Number,
    Boolean,
}
impl JSONScalarType {
    pub fn name(&self) -> &'static str {
        match self {
            Self::String => "string",
            Self::Number => "number",
            Self::Boolean => "boolean",
        }
    }
}
#[derive(Debug, Clone)]
pub enum JSONTypeDescriptor {
    Scalar(JSONScalarType),
    Union(Vec<JSONScalarType>),
    Object(String),
    Array(Box<JSONValueDescriptor>),
}
#[derive(Debug, Clone)]
pub struct JSONValueDescriptor {
    pub kind: JSONTypeDescriptor,
    pub nullable: bool,
    pub min_length: Option<u64>,
    pub integer: bool,
    pub safe_integer: bool,
}
#[derive(Debug, Clone)]
pub struct JSONFieldDescriptor {
    pub json_name: String,
    pub output_name: String,
    pub required: bool,
    pub value: JSONValueDescriptor,
}
#[derive(Debug, Clone)]
pub struct JSONObjectDescriptor {
    pub name: String,
    pub fields: Vec<JSONFieldDescriptor>,
}
#[derive(Debug, Clone)]
pub struct JSONRootDescriptor {
    pub name: String,
    pub value: JSONValueDescriptor,
}
#[derive(Debug, Clone)]
pub struct JSONFileDescriptor {
    pub name: String,
    pub objects: Vec<JSONObjectDescriptor>,
    pub roots: Vec<JSONRootDescriptor>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RawFile {
    schema_version: u32,
    name: String,
    #[serde(default)]
    models: BTreeMap<String, RawValue>,
    #[serde(default)]
    roots: BTreeMap<String, RawValue>,
}
#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RawValue {
    #[serde(rename = "type")]
    kind: Option<RawType>,
    #[serde(rename = "ref")]
    reference: Option<String>,
    nullable: Option<bool>,
    output_name: Option<String>,
    properties: Option<BTreeMap<String, RawValue>>,
    required: Option<Vec<String>>,
    unknown_fields: Option<String>,
    items: Option<Box<RawValue>>,
    min_length: Option<u64>,
    integer: Option<bool>,
    safe_integer: Option<bool>,
}
#[derive(Clone, Deserialize)]
#[serde(untagged)]
enum RawType {
    Single(String),
    Union(Vec<String>),
}
fn error(at: &str, message: &str) -> String {
    format!("Schema {at}: {message}")
}
fn ensure(ok: bool, at: &str, message: &str) -> Result<(), String> {
    if ok { Ok(()) } else { Err(error(at, message)) }
}
fn identifier(s: &str, at: &str) -> Result<(), String> {
    const RESERVED: &str = "constructor prototype __proto__ class interface extends implements static private public protected new return default function var let const enum export import null undefined true false this super namespace package readonly abstract declare delete in instanceof typeof void with yield await switch case break continue for while do if else try catch finally throw arguments eval";
    let mut chars = s.chars();
    let valid = chars
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic() || c == '_')
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
        && !RESERVED.split_whitespace().any(|x| x == s);
    ensure(valid, at, "invalid/reserved output identifier")
}

struct Builder {
    names: BTreeSet<String>,
    objects: Vec<JSONObjectDescriptor>,
    inline_id: usize,
}
impl Builder {
    fn object(&mut self, name: String, raw: &RawValue, at: &str) -> Result<(), String> {
        ensure(
            matches!(&raw.kind, Some(RawType::Single(t)) if t == "object"),
            at,
            "model must be an object",
        )?;
        ensure(
            raw.reference.is_none()
                && raw.items.is_none()
                && raw.min_length.is_none()
                && raw.integer.is_none()
                && raw.safe_integer.is_none(),
            at,
            "invalid object constraint",
        )?;
        ensure(
            raw.unknown_fields.as_deref().is_none_or(|s| s == "strip"),
            at,
            "v1 only supports unknownFields=strip",
        )?;
        let props = raw
            .properties
            .as_ref()
            .ok_or_else(|| error(at, "missing properties"))?;
        let required = raw.required.clone().unwrap_or_default();
        let unique: BTreeSet<_> = required.iter().collect();
        ensure(
            unique.len() == required.len() && required.iter().all(|s| props.contains_key(s)),
            at,
            "required must list distinct existing fields",
        )?;
        let mut fields = vec![];
        let mut outputs = BTreeSet::new();
        for (json_name, raw_field) in props {
            let field_at = format!("{at}.properties.{json_name}");
            let output_name = raw_field
                .output_name
                .clone()
                .unwrap_or_else(|| json_name.clone());
            identifier(&output_name, &field_at)?;
            ensure(
                outputs.insert(output_name.clone()),
                &field_at,
                "duplicate outputName",
            )?;
            fields.push(JSONFieldDescriptor {
                json_name: json_name.clone(),
                output_name,
                required: required.contains(json_name),
                value: self.value(raw_field, &field_at)?,
            });
        }
        self.objects.push(JSONObjectDescriptor { name, fields });
        Ok(())
    }
    fn value(&mut self, raw: &RawValue, at: &str) -> Result<JSONValueDescriptor, String> {
        let nullable = raw.nullable.unwrap_or(false);
        let descriptor = |kind| JSONValueDescriptor {
            kind,
            nullable,
            min_length: raw.min_length,
            integer: raw.integer.unwrap_or(false),
            safe_integer: raw.safe_integer.unwrap_or(false),
        };
        if let Some(reference) = &raw.reference {
            ensure(
                raw.kind.is_none() && self.names.contains(reference),
                at,
                "unknown or ambiguous ref",
            )?;
            ensure(
                raw.properties.is_none()
                    && raw.required.is_none()
                    && raw.unknown_fields.is_none()
                    && raw.items.is_none()
                    && raw.min_length.is_none()
                    && raw.integer.is_none()
                    && raw.safe_integer.is_none(),
                at,
                "constraints are not allowed on ref",
            )?;
            return Ok(descriptor(JSONTypeDescriptor::Object(reference.clone())));
        }
        if matches!(&raw.kind, Some(RawType::Single(t)) if t == "object") {
            let name = loop {
                self.inline_id += 1;
                let name = format!("Inline{}", self.inline_id);
                if self.names.insert(name.clone()) {
                    break name;
                }
            };
            self.object(name.clone(), raw, at)?;
            return Ok(descriptor(JSONTypeDescriptor::Object(name)));
        }
        ensure(
            raw.properties.is_none() && raw.required.is_none() && raw.unknown_fields.is_none(),
            at,
            "object keywords on non-object",
        )?;
        if matches!(&raw.kind, Some(RawType::Single(t)) if t == "array") {
            ensure(
                raw.min_length.is_none() && raw.integer.is_none() && raw.safe_integer.is_none(),
                at,
                "invalid array constraint",
            )?;
            let item = raw
                .items
                .as_ref()
                .ok_or_else(|| error(at, "array requires items"))?;
            ensure(
                item.output_name.is_none(),
                at,
                "array items cannot have outputName",
            )?;
            return Ok(descriptor(JSONTypeDescriptor::Array(Box::new(
                self.value(item, &format!("{at}.items"))?,
            ))));
        }
        ensure(raw.items.is_none(), at, "items on non-array")?;
        let types = match &raw.kind {
            Some(RawType::Single(t)) => vec![t.clone()],
            Some(RawType::Union(types)) => types.clone(),
            None => return Err(error(at, "missing type or ref")),
        };
        ensure(
            !types.is_empty() && types.iter().collect::<BTreeSet<_>>().len() == types.len(),
            at,
            "empty or duplicate union members",
        )?;
        let scalars: Vec<JSONScalarType> = types
            .iter()
            .map(|t| match t.as_str() {
                "string" => Ok(JSONScalarType::String),
                "number" => Ok(JSONScalarType::Number),
                "boolean" => Ok(JSONScalarType::Boolean),
                _ => Err(error(at, "unsupported type (unions must contain scalars)")),
            })
            .collect::<Result<_, _>>()?;
        ensure(
            raw.min_length.is_none()
                || (types.iter().any(|t| t == "string")
                    && raw.min_length.unwrap() <= 9_007_199_254_740_991),
            at,
            "invalid minLength",
        )?;
        ensure(
            (raw.integer.is_none() && raw.safe_integer.is_none())
                || types.iter().any(|t| t == "number"),
            at,
            "number constraint on non-number",
        )?;
        let kind = if scalars.len() == 1 {
            JSONTypeDescriptor::Scalar(scalars[0].clone())
        } else {
            JSONTypeDescriptor::Union(scalars)
        };
        Ok(descriptor(kind))
    }
}
impl JSONFileDescriptor {
    pub fn parse(text: &str) -> Result<Self, String> {
        let raw: RawFile = serde_json::from_value(crate::schema_json::parse(text)?)
            .map_err(|e| format!("Invalid schema JSON: {e}"))?;
        ensure(raw.schema_version == 1, "$", "schemaVersion must be 1")?;
        identifier(&raw.name, "$.name")?;
        ensure(
            !raw.models.is_empty() || !raw.roots.is_empty(),
            "$.models",
            "at least one model or root required",
        )?;
        for name in raw.models.keys() {
            identifier(name, "$.models")?;
            let emitted_name = format!("{}{name}", raw.name);
            ensure(
                !["DecodeContext", "DecodeResult", "JsonNode"].contains(&emitted_name.as_str())
                    && name != "Schema",
                name,
                "model name collides with generated decoder/runtime",
            )?;
        }
        let mut builder = Builder {
            names: raw.models.keys().cloned().collect(),
            objects: vec![],
            inline_id: 0,
        };
        for (name, model) in &raw.models {
            ensure(
                model.nullable.is_none() && model.output_name.is_none(),
                name,
                "top-level model cannot have nullable/outputName",
            )?;
            builder.object(name.clone(), model, name)?;
        }
        let mut roots = vec![];
        for (name, value) in &raw.roots {
            identifier(name, "$.roots")?;
            ensure(
                !raw.models.contains_key(name),
                name,
                "root name collides with model entrypoint",
            )?;
            ensure(
                value.output_name.is_none(),
                name,
                "root cannot have outputName",
            )?;
            roots.push(JSONRootDescriptor {
                name: name.clone(),
                value: builder.value(value, name)?,
            });
        }
        // Inline object names also become decoder methods; root names must not collide.
        for root in &roots {
            ensure(
                !builder.objects.iter().any(|o| o.name == root.name),
                &root.name,
                "root name collides with inline model",
            )?;
        }
        builder.objects.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(Self {
            name: raw.name,
            objects: builder.objects,
            roots,
        })
    }
}
