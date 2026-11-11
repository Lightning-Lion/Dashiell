//! Back end: descriptors -> code-emission nodes. No schema JSON is embedded in the app.
use crate::descriptor::*;
use crate::node::*;
use sha2::{Digest, Sha256};

fn quote(s: &str) -> String {
    serde_json::to_string(s).expect("string serialization cannot fail")
}
fn ret(s: &str) -> JSONStatementNode {
    JSONStatementNode::Return(s.into())
}
fn expr(s: impl Into<String>) -> JSONStatementNode {
    JSONStatementNode::Expression(s.into())
}
fn constant(name: &str, value: impl Into<String>) -> JSONStatementNode {
    JSONStatementNode::Const {
        name: name.into(),
        type_name: None,
        value: value.into(),
    }
}
fn when(condition: impl Into<String>, body: Vec<JSONStatementNode>) -> JSONStatementNode {
    JSONStatementNode::If {
        condition: condition.into(),
        body,
    }
}
fn param(name: &str, ty: &str) -> JSONParameterNode {
    JSONParameterNode {
        name: name.into(),
        type_name: ty.into(),
    }
}
fn issue(code: &str, expected: &str) -> JSONStatementNode {
    expr(format!(
        "context.issue('{}', node, {})",
        code,
        quote(expected)
    ))
}
fn fail(condition: impl Into<String>, code: &str, expected: &str) -> JSONStatementNode {
    when(condition, vec![issue(code, expected), ret("undefined")])
}
fn function(name: String, return_type: String, body: Vec<JSONStatementNode>) -> JSONFunNode {
    JSONFunNode {
        name,
        private: false,
        is_static: true,
        parameters: vec![param("node", "JsonNode"), param("context", "DecodeContext")],
        return_type: Some(return_type),
        body,
    }
}
struct Generator<'a> {
    file: &'a JSONFileDescriptor,
    helpers: Vec<JSONFunNode>,
    next: usize,
}
impl Generator<'_> {
    fn model_name(&self, name: &str) -> String {
        format!("{}{name}", self.file.name)
    }
    fn decoder_name(&self) -> String {
        format!("{}Schema", self.file.name)
    }
    fn value_type(&self, value: &JSONValueDescriptor) -> String {
        let base = match &value.kind {
            JSONTypeDescriptor::Scalar(s) => s.name().into(),
            JSONTypeDescriptor::Union(types) => types
                .iter()
                .map(|t| t.name())
                .collect::<Vec<_>>()
                .join(" | "),
            JSONTypeDescriptor::Object(name) => self.model_name(name),
            JSONTypeDescriptor::Array(item) => format!("Array<{}>", self.value_type(item)),
        };
        format!("{base}{}", if value.nullable { " | null" } else { "" })
    }
    fn model(&self, object: &JSONObjectDescriptor) -> JSONClassNode {
        let properties: Vec<_> = object
            .fields
            .iter()
            .map(|field| JSONPropertyNode {
                name: field.output_name.clone(),
                type_name: format!(
                    "{}{}",
                    self.value_type(&field.value),
                    if field.required { "" } else { " | undefined" }
                ),
            })
            .collect();
        let constructor = JSONFunNode {
            name: "constructor".into(),
            private: false,
            is_static: false,
            return_type: None,
            parameters: properties
                .iter()
                .map(|p| param(&p.name, &p.type_name))
                .collect(),
            body: properties
                .iter()
                .map(|p| expr(format!("this.{} = {}", p.name, p.name)))
                .collect(),
        };
        JSONClassNode {
            name: self.model_name(&object.name),
            properties,
            functions: vec![constructor],
        }
    }
    fn reader(&mut self, value: &JSONValueDescriptor, required: bool) -> String {
        let name = format!("read{}", self.next);
        self.next += 1;
        let mut body = vec![
            when("context.exhausted()", vec![ret("undefined")]),
            when(
                "node.kind() === 'missing'",
                if required {
                    vec![
                        issue("MISSING_FIELD", &self.value_type(value)),
                        ret("undefined"),
                    ]
                } else {
                    vec![ret("undefined")]
                },
            ),
            when("!node.withinDepth(context)", vec![ret("undefined")]),
            when(
                "node.kind() === 'null'",
                if value.nullable {
                    vec![ret("null")]
                } else {
                    vec![
                        issue("NULL_NOT_ALLOWED", &self.value_type(value)),
                        ret("undefined"),
                    ]
                },
            ),
        ];
        match &value.kind {
            JSONTypeDescriptor::Object(reference) => body.push(ret(&format!(
                "{}.decode{reference}(node, context)",
                self.decoder_name()
            ))),
            JSONTypeDescriptor::Array(item) => {
                let item_reader = self.reader(item, true);
                body.extend([
                    fail("node.kind() !== 'array'", "TYPE_MISMATCH", "array"),
                    fail(
                        "node.length() > DecodeContext.MAX_ITEMS",
                        "LIMIT_EXCEEDED",
                        "array within item limit",
                    ),
                    constant("before", "context.issueCount()"),
                    JSONStatementNode::Const {
                        name: "items".into(),
                        type_name: Some(format!("Array<{}>", self.value_type(item))),
                        value: "[]".into(),
                    },
                    JSONStatementNode::For {
                        header:
                            "let index = 0; index < node.length() && !context.exhausted(); index++"
                                .into(),
                        body: vec![
                            constant(
                                "value",
                                format!(
                                    "{}.{item_reader}(node.element(index), context)",
                                    self.decoder_name()
                                ),
                            ),
                            when("value !== undefined", vec![expr("items.push(value)")]),
                        ],
                    },
                    ret("context.issueCount() === before ? items : undefined"),
                ]);
            }
            JSONTypeDescriptor::Scalar(scalar) => {
                self.scalars(&mut body, value, std::slice::from_ref(scalar))
            }
            JSONTypeDescriptor::Union(scalars) => self.scalars(&mut body, value, scalars),
        }
        let mut helper = function(
            name.clone(),
            format!("{} | undefined", self.value_type(value)),
            body,
        );
        helper.private = true;
        self.helpers.push(helper);
        name
    }
    fn scalars(
        &self,
        body: &mut Vec<JSONStatementNode>,
        value: &JSONValueDescriptor,
        scalars: &[JSONScalarType],
    ) {
        for scalar in scalars {
            let mut branch = vec![constant("value", format!("node.{}Value()", scalar.name()))];
            if scalar == &JSONScalarType::Number {
                let mut conditions = vec!["!Number.isFinite(value)"];
                if value.integer {
                    conditions.push("!Number.isInteger(value)");
                }
                if value.safe_integer {
                    conditions.push("!Number.isSafeInteger(value)");
                }
                branch.push(fail(
                    conditions.join(" || "),
                    "OUT_OF_RANGE",
                    if value.safe_integer {
                        "safe integer"
                    } else if value.integer {
                        "finite integer"
                    } else {
                        "finite number"
                    },
                ));
            }
            if scalar == &JSONScalarType::String
                && let Some(min) = value.min_length
            {
                branch.push(fail(
                    format!("value.length < {min}"),
                    "OUT_OF_RANGE",
                    &format!("string length >= {min}"),
                ));
            }
            branch.push(ret("value"));
            body.push(when(format!("node.kind() === '{}'", scalar.name()), branch));
        }
        body.push(issue(
            if scalars.len() > 1 {
                "UNION_MISMATCH"
            } else {
                "TYPE_MISMATCH"
            },
            &self.value_type(value),
        ));
        body.push(ret("undefined"));
    }
    fn decode(&mut self, object: &JSONObjectDescriptor) -> JSONFunNode {
        let mut body = vec![
            when(
                "context.exhausted() || !node.withinDepth(context)",
                vec![ret("undefined")],
            ),
            fail("node.kind() !== 'object'", "TYPE_MISMATCH", "object"),
            constant("before", "context.issueCount()"),
        ];
        let mut args = vec![];
        let mut guards = vec!["context.issueCount() !== before".to_string()];
        for field in &object.fields {
            let arg = format!("field{}", args.len());
            let reader = self.reader(&field.value, field.required);
            body.push(constant(
                &arg,
                format!(
                    "{}.{reader}(node.field({}), context)",
                    self.decoder_name(),
                    quote(&field.json_name)
                ),
            ));
            if field.required {
                guards.push(format!("{arg} === undefined"));
            }
            args.push(arg);
        }
        body.push(when(guards.join(" || "), vec![ret("undefined")]));
        body.push(ret(&format!(
            "new {}({})",
            self.model_name(&object.name),
            args.join(", ")
        )));
        function(
            format!("decode{}", object.name),
            format!("{} | undefined", self.model_name(&object.name)),
            body,
        )
    }
    fn root_entry(&mut self, root: &JSONRootDescriptor) -> Vec<JSONFunNode> {
        let ty = self.value_type(&root.value);
        let reader = self.reader(&root.value, true);
        let decoder = function(
            format!("decode{}", root.name),
            format!("{ty} | undefined"),
            vec![ret(&format!(
                "{}.{reader}(node, context)",
                self.decoder_name()
            ))],
        );
        let mut entry = function(
            format!("tryParse{}", root.name),
            format!("DecodeResult<{ty}>"),
            vec![
                constant(
                    "context",
                    format!("new DecodeContext('{}{}')", self.file.name, root.name),
                ),
                constant("node", "JsonNode.parse(text, context)"),
                ret(&format!(
                    "context.finish<{ty}>(node === undefined ? undefined : {}.decode{}(node, context))",
                    self.decoder_name(),
                    root.name
                )),
            ],
        );
        entry.parameters = vec![param("text", "string")];
        vec![entry, decoder]
    }
    fn entry(&self, object: &JSONObjectDescriptor) -> JSONFunNode {
        let mut node = function(
            format!("tryParse{}", object.name),
            format!("DecodeResult<{}>", self.model_name(&object.name)),
            vec![
                constant(
                    "context",
                    format!("new DecodeContext('{}')", self.model_name(&object.name)),
                ),
                constant("node", "JsonNode.parse(text, context)"),
                ret(&format!(
                    "context.finish<{}>(node === undefined ? undefined : {}.decode{}(node, context))",
                    self.model_name(&object.name),
                    self.decoder_name(),
                    object.name
                )),
            ],
        );
        node.parameters = vec![param("text", "string")];
        node
    }
}

pub struct GeneratedFile {
    pub name: String,
    pub tree: JSONFileNode,
}
pub fn generate(file: &JSONFileDescriptor, source: &str) -> Vec<GeneratedFile> {
    generate_with_runtime(file, source, "../../jsonschema/JsonDecode")
}
pub fn generate_with_runtime(
    file: &JSONFileDescriptor,
    source: &str,
    runtime_import: &str,
) -> Vec<GeneratedFile> {
    let hash = format!("{:x}", Sha256::digest(source.as_bytes()));
    let comments = vec![
        "GENERATED by Rust dashiell-json-gen v0.1.0. DO NOT EDIT.".into(),
        format!("Schema SHA-256: {hash}"),
    ];
    let mut generator = Generator {
        file,
        helpers: vec![],
        next: 0,
    };
    let models = JSONFileNode {
        comments: comments.clone(),
        imports: vec![],
        classes: file.objects.iter().map(|o| generator.model(o)).collect(),
    };
    let mut functions = vec![];
    for object in &file.objects {
        functions.push(generator.entry(object));
        functions.push(generator.decode(object));
    }
    for root in &file.roots {
        functions.extend(generator.root_entry(root));
    }
    functions.append(&mut generator.helpers);
    let mut decoders = JSONFileNode {
        comments,
        imports: vec![
            JSONImportNode {
                names: vec![
                    "DecodeContext".into(),
                    "DecodeResult".into(),
                    "JsonNode".into(),
                ],
                from: runtime_import.into(),
            },
            JSONImportNode {
                names: file
                    .objects
                    .iter()
                    .map(|o| generator.model_name(&o.name))
                    .collect(),
                from: format!("./{}Models.generated", file.name),
            },
        ],
        classes: vec![JSONClassNode {
            name: generator.decoder_name(),
            properties: vec![],
            functions,
        }],
    };
    decoders.imports.retain(|node| !node.names.is_empty());
    vec![
        GeneratedFile {
            name: format!("{}Models.generated.ets", file.name),
            tree: models,
        },
        GeneratedFile {
            name: format!("{}Decoders.generated.ets", file.name),
            tree: decoders,
        },
    ]
}
