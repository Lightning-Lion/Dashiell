//! Fail closed on duplicate schema keys and explicit null configuration values.
//! `nullable: true` describes JSON null; null is not itself a valid schema setting in v1.
use serde::{
    Deserialize, Deserializer,
    de::{self, MapAccess, SeqAccess, Visitor},
};
use serde_json::{Map, Number, Value};
use std::fmt;
struct StrictSchemaValue(Value);
impl<'de> Deserialize<'de> for StrictSchemaValue {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct SchemaVisitor;
        impl<'de> Visitor<'de> for SchemaVisitor {
            type Value = StrictSchemaValue;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("schema JSON without duplicate keys or null settings")
            }
            fn visit_bool<E: de::Error>(self, value: bool) -> Result<Self::Value, E> {
                Ok(StrictSchemaValue(Value::Bool(value)))
            }
            fn visit_i64<E: de::Error>(self, value: i64) -> Result<Self::Value, E> {
                Ok(StrictSchemaValue(Value::Number(value.into())))
            }
            fn visit_u64<E: de::Error>(self, value: u64) -> Result<Self::Value, E> {
                Ok(StrictSchemaValue(Value::Number(value.into())))
            }
            fn visit_f64<E: de::Error>(self, value: f64) -> Result<Self::Value, E> {
                Number::from_f64(value)
                    .map(|n| StrictSchemaValue(Value::Number(n)))
                    .ok_or_else(|| E::custom("non-finite schema number"))
            }
            fn visit_str<E: de::Error>(self, value: &str) -> Result<Self::Value, E> {
                Ok(StrictSchemaValue(Value::String(value.into())))
            }
            fn visit_string<E: de::Error>(self, value: String) -> Result<Self::Value, E> {
                Ok(StrictSchemaValue(Value::String(value)))
            }
            fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
                let mut values = Vec::new();
                while let Some(StrictSchemaValue(value)) = seq.next_element()? {
                    values.push(value);
                }
                Ok(StrictSchemaValue(Value::Array(values)))
            }
            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
                let mut values = Map::new();
                while let Some((key, StrictSchemaValue(value))) =
                    map.next_entry::<String, StrictSchemaValue>()?
                {
                    if values.contains_key(&key) {
                        return Err(de::Error::custom(format!("duplicate schema key: {key}")));
                    }
                    values.insert(key, value);
                }
                Ok(StrictSchemaValue(Value::Object(values)))
            }
        }
        deserializer.deserialize_any(SchemaVisitor)
    }
}
pub(crate) fn parse(text: &str) -> Result<Value, String> {
    serde_json::from_str::<StrictSchemaValue>(text)
        .map(|v| v.0)
        .map_err(|e| format!("Invalid schema JSON: {e}"))
}
