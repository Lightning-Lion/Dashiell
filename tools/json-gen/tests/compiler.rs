use dashiell_json_gen::{descriptor::*, generator::generate, node::*};
fn parse(models: &str) -> Result<JSONFileDescriptor, String> {
    JSONFileDescriptor::parse(&format!(
        r#"{{"schemaVersion":1,"name":"Test","models":{models}}}"#
    ))
}
#[test]
fn describes_nested_objects_and_object_and_string_arrays() {
    let file = parse(r#"{"Root":{"type":"object","required":["groups"],"properties":{"groups":{"type":"array","items":{"type":"object","required":["tags"],"properties":{"tags":{"type":"array","items":{"type":"string"}}}}}}}}"#).unwrap();
    let root = file.objects.iter().find(|o| o.name == "Root").unwrap();
    assert!(root.fields[0].required);
    let JSONTypeDescriptor::Array(item) = &root.fields[0].value.kind else {
        panic!()
    };
    let JSONTypeDescriptor::Object(name) = &item.kind else {
        panic!()
    };
    let nested = file.objects.iter().find(|o| &o.name == name).unwrap();
    let JSONTypeDescriptor::Array(item) = &nested.fields[0].value.kind else {
        panic!()
    };
    assert!(matches!(
        item.kind,
        JSONTypeDescriptor::Scalar(JSONScalarType::String)
    ));
}
#[test]
fn descriptor_retains_wire_name_optional_nullable_and_constraints() {
    let file = parse(r#"{"Root":{"type":"object","properties":{"wire_name":{"type":["number","string"],"nullable":true,"safeInteger":true,"outputName":"value"}}}}"#).unwrap();
    let field = &file.objects[0].fields[0];
    assert_eq!(field.json_name, "wire_name");
    assert_eq!(field.output_name, "value");
    assert!(!field.required && field.value.nullable && field.value.safe_integer);
    assert!(matches!(field.value.kind, JSONTypeDescriptor::Union(_)));
}
#[test]
fn rejects_unsupported_keywords_instead_of_silently_ignoring_them() {
    for field in [
        r#"{"type":"string","default":"x"}"#,
        r#"{"type":"string","pattern":"x"}"#,
        r#"{"type":"string","typo":true}"#,
    ] {
        assert!(
            parse(&format!(
                r#"{{"Root":{{"type":"object","properties":{{"value":{field}}}}}}}"#
            ))
            .is_err()
        );
    }
}
#[test]
fn rejects_unknown_refs_and_ambiguous_constraints() {
    for field in [
        r#"{"ref":"Missing"}"#,
        r#"{"ref":"Root","type":"string"}"#,
        r#"{"ref":"Root","minLength":1}"#,
    ] {
        assert!(
            parse(&format!(
                r#"{{"Root":{{"type":"object","properties":{{"value":{field}}}}}}}"#
            ))
            .is_err()
        );
    }
}
#[test]
fn rejects_bad_required_and_duplicate_output_names() {
    assert!(parse(r#"{"Root":{"type":"object","required":["nope"],"properties":{}}}"#).is_err());
    assert!(parse(r#"{"Root":{"type":"object","required":["v","v"],"properties":{"v":{"type":"string"}}}}"#).is_err());
    assert!(parse(r#"{"Root":{"type":"object","properties":{"a":{"type":"string","outputName":"v"},"b":{"type":"string","outputName":"v"}}}}"#).is_err());
}
#[test]
fn rejects_bad_unions_and_numeric_rules() {
    for field in [
        r#"{"type":[]}"#,
        r#"{"type":["number","number"]}"#,
        r#"{"type":["array","string"]}"#,
        r#"{"type":"string","integer":true}"#,
        r#"{"type":"number","minLength":2}"#,
        r#"{"type":"array"}"#,
    ] {
        assert!(
            parse(&format!(
                r#"{{"Root":{{"type":"object","properties":{{"v":{field}}}}}}}"#
            ))
            .is_err()
        );
    }
}
#[test]
fn rejects_identifier_injection_but_permits_renamed_wire_keys() {
    assert!(parse(r#"{"Root":{"type":"object","properties":{"v":{"type":"string","outputName":"x; evil()"}}}}"#).is_err());
    assert!(parse(r#"{"Root":{"type":"object","properties":{"v":{"type":"string","outputName":"constructor"}}}}"#).is_err());
    assert!(parse(r#"{"Root":{"type":"object","properties":{"wire.dot[0]":{"type":"string","outputName":"safe"}}}}"#).is_ok());
}
#[test]
fn node_tree_has_real_classes_functions_and_loops() {
    let source = r#"{"schemaVersion":1,"name":"Test","models":{"Root":{"type":"object","properties":{"tags":{"type":"array","items":{"type":"string"}}}}}}"#;
    let descriptor = JSONFileDescriptor::parse(source).unwrap();
    let files = generate(&descriptor, source);
    assert_eq!(files.len(), 2);
    assert_eq!(files[0].tree.classes[0].name, "TestRoot");
    assert_eq!(files[0].tree.classes[0].functions[0].name, "constructor");
    assert!(files[1].tree.classes[0].functions.iter().any(|f| {
        f.body
            .iter()
            .any(|s| matches!(s, JSONStatementNode::For { .. }))
    }));
    let rendered = files[1].tree.render();
    assert!(rendered.contains("node.element(index)"));
    assert!(rendered.contains("new TestRoot("));
    assert!(!rendered.contains("as TestRoot"));
    assert!(!rendered.contains("eval("));
}
#[test]
fn self_references_generate_bounded_decoders() {
    let source = r#"{"schemaVersion":1,"name":"Test","models":{"Root":{"type":"object","properties":{"child":{"ref":"Root"}}}}}"#;
    let files = generate(&JSONFileDescriptor::parse(source).unwrap(), source);
    let code = files[1].tree.render();
    assert!(code.contains("withinDepth(context)"));
    assert!(code.contains("return TestSchema.decodeRoot(node, context)"));
}
#[test]
fn generation_is_deterministic() {
    let source = include_str!("../../../schemas/douyin.schema.json");
    let descriptor = JSONFileDescriptor::parse(source).unwrap();
    let render = || {
        generate(&descriptor, source)
            .into_iter()
            .map(|f| f.tree.render())
            .collect::<Vec<_>>()
    };
    assert_eq!(render(), render());
}
#[test]
fn tree_writer_owns_braces_indentation_and_return_annotations() {
    let file = JSONFileNode {
        comments: vec![],
        imports: vec![],
        classes: vec![JSONClassNode {
            name: "Example".into(),
            properties: vec![],
            functions: vec![JSONFunNode {
                name: "ok".into(),
                private: true,
                is_static: true,
                parameters: vec![],
                return_type: Some("boolean".into()),
                body: vec![
                    JSONStatementNode::If {
                        condition: "true".into(),
                        body: vec![JSONStatementNode::Return("true".into())],
                    },
                    JSONStatementNode::Return("false".into()),
                ],
            }],
        }],
    };
    assert_eq!(
        file.render(),
        "\nexport class Example {\n\n  private static ok(): boolean {\n    if (true) {\n      return true;\n    }\n    return false;\n  }\n}\n"
    );
}
#[test]
fn rejects_duplicate_keys_and_null_schema_settings() {
    assert!(
        parse(r#"{"Root":{"type":"object","properties":{"v":{"type":"string","nullable":null}}}}"#)
            .is_err()
    );
    assert!(parse(r#"{"Root":{"type":"object","properties":{"v":{"type":"string"},"v":{"type":"number"}}}}"#).is_err());
    assert!(
        parse(
            r#"{"Root":{"type":"object","properties":{}},"Root":{"type":"object","properties":{}}}"#
        )
        .is_err()
    );
}
#[test]
fn rejects_generated_symbol_collisions() {
    assert!(parse(r#"{"Schema":{"type":"object","properties":{}}}"#).is_err());
    assert!(JSONFileDescriptor::parse(r#"{"schemaVersion":1,"name":"Json","models":{"Node":{"type":"object","properties":{}}}}"#).is_err());
}
#[test]
fn root_array_and_nullable_scalar_have_real_descriptors() {
    let source = r#"{"schemaVersion":1,"name":"Local","roots":{"Ids":{"type":"array","items":{"type":"string"}},"Flag":{"type":"boolean","nullable":true}}}"#;
    let file = JSONFileDescriptor::parse(source).unwrap();
    assert!(file.objects.is_empty());
    assert_eq!(file.roots.len(), 2);
    assert!(matches!(
        file.roots[1].value.kind,
        JSONTypeDescriptor::Array(_)
    ));
    let output = generate(&file, source)[1].tree.render();
    assert!(output.contains("DecodeResult<Array<string>>"));
    assert!(output.contains("DecodeResult<boolean | null>"));
    assert!(!output.contains("import {  }"));
}
#[test]
fn rejects_root_entrypoint_collisions() {
    assert!(JSONFileDescriptor::parse(r#"{"schemaVersion":1,"name":"Test","models":{"Same":{"type":"object","properties":{}}},"roots":{"Same":{"type":"string"}}}"#).is_err());
}
#[test]
fn contextual_type_property_is_legal_for_json_models() {
    let file = parse(r#"{"Media":{"type":"object","required":["type"],"properties":{"type":{"type":"number"}}}}"#).unwrap();
    assert_eq!(file.objects[0].fields[0].output_name, "type");
}
