//! ArkTS code-emission tree. Nodes own structure; the writer alone owns indentation/braces.
//! Architecture inspired by TurboTrans PbNodeTree, independently implemented in Rust.
#[derive(Debug, Clone)]
pub struct JSONImportNode {
    pub names: Vec<String>,
    pub from: String,
}
#[derive(Debug, Clone)]
pub struct JSONPropertyNode {
    pub name: String,
    pub type_name: String,
}
#[derive(Debug, Clone)]
pub struct JSONParameterNode {
    pub name: String,
    pub type_name: String,
}
#[derive(Debug, Clone)]
pub enum JSONStatementNode {
    Const {
        name: String,
        type_name: Option<String>,
        value: String,
    },
    Expression(String),
    Return(String),
    If {
        condition: String,
        body: Vec<JSONStatementNode>,
    },
    For {
        header: String,
        body: Vec<JSONStatementNode>,
    },
}
#[derive(Debug, Clone)]
pub struct JSONFunNode {
    pub name: String,
    pub private: bool,
    pub is_static: bool,
    pub parameters: Vec<JSONParameterNode>,
    // None identifies a constructor, which has no explicit return annotation.
    pub return_type: Option<String>,
    pub body: Vec<JSONStatementNode>,
}
#[derive(Debug, Clone)]
pub struct JSONClassNode {
    pub name: String,
    pub properties: Vec<JSONPropertyNode>,
    pub functions: Vec<JSONFunNode>,
}
#[derive(Debug, Clone)]
pub struct JSONFileNode {
    pub comments: Vec<String>,
    pub imports: Vec<JSONImportNode>,
    pub classes: Vec<JSONClassNode>,
}
struct Writer {
    text: String,
    depth: usize,
}
impl Writer {
    fn line(&mut self, line: &str) {
        if !line.is_empty() {
            self.text.push_str(&"  ".repeat(self.depth));
        }
        self.text.push_str(line);
        self.text.push('\n');
    }
    fn block(&mut self, header: &str, body: &[JSONStatementNode]) {
        self.line(&format!("{header} {{"));
        self.depth += 1;
        for node in body {
            self.statement(node);
        }
        self.depth -= 1;
        self.line("}");
    }
    fn statement(&mut self, node: &JSONStatementNode) {
        match node {
            JSONStatementNode::Const {
                name,
                type_name,
                value,
            } => {
                let ty = type_name
                    .as_ref()
                    .map(|t| format!(": {t}"))
                    .unwrap_or_default();
                self.line(&format!("const {name}{ty} = {value};"));
            }
            JSONStatementNode::Expression(text) => self.line(&format!("{text};")),
            JSONStatementNode::Return(text) => self.line(&format!("return {text};")),
            JSONStatementNode::If { condition, body } => {
                self.block(&format!("if ({condition})"), body)
            }
            JSONStatementNode::For { header, body } => self.block(&format!("for ({header})"), body),
        }
    }
}
impl JSONFileNode {
    pub fn render(&self) -> String {
        let mut w = Writer {
            text: String::new(),
            depth: 0,
        };
        for comment in &self.comments {
            w.line(&format!("// {comment}"));
        }
        for import in &self.imports {
            w.line(&format!(
                "import {{ {} }} from '{}';",
                import.names.join(", "),
                import.from
            ));
        }
        for class in &self.classes {
            w.line("");
            w.line(&format!("export class {} {{", class.name));
            w.depth += 1;
            for property in &class.properties {
                w.line(&format!("{}: {};", property.name, property.type_name));
            }
            for fun in &class.functions {
                w.line("");
                let params = fun
                    .parameters
                    .iter()
                    .map(|p| format!("{}: {}", p.name, p.type_name))
                    .collect::<Vec<_>>()
                    .join(", ");
                let ret = fun
                    .return_type
                    .as_ref()
                    .map(|r| format!(": {r}"))
                    .unwrap_or_default();
                let header = format!(
                    "{}{}{}({params}){ret}",
                    if fun.private { "private " } else { "" },
                    if fun.is_static { "static " } else { "" },
                    fun.name
                );
                w.block(&header, &fun.body);
            }
            w.depth -= 1;
            w.line("}");
        }
        w.text
    }
}
