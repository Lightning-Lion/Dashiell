use std::{env, fs, path::PathBuf, process};
use dashiell_json_gen::{descriptor::JSONFileDescriptor, generator::generate_with_runtime};

fn run() -> Result<(), String> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut schema = root.join("schemas/douyin.schema.json");
    let mut output = root.join("entry/src/main/ets/common/douyin/schema");
    let mut check = false;
    let mut runtime_import = "../../jsonschema/JsonDecode".to_string();
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--schema" => schema = PathBuf::from(args.next().ok_or("--schema requires path")?),
            "--out" => output = PathBuf::from(args.next().ok_or("--out requires path")?),
            "--runtime-import" => {
                runtime_import = args.next().ok_or("--runtime-import requires module path")?;
                if !runtime_import
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || "./_-@".contains(c))
                    || runtime_import.is_empty()
                {
                    return Err("Invalid runtime import".into());
                }
            }
            "--check" => check = true,
            "--help" | "-h" => {
                println!(
                    "dashiell-json-gen [--schema PATH] [--out DIRECTORY] [--runtime-import MODULE] [--check]\nDefaults to the Dashiell Douyin schema and generated directory."
                );
                return Ok(());
            }
            _ => return Err(format!("Unknown argument: {arg}")),
        }
    }
    let source = fs::read_to_string(&schema).map_err(|e| format!("{}: {e}", schema.display()))?;
    let descriptor = JSONFileDescriptor::parse(&source)?;
    // Finish validation and generation before touching outputs.
    let files: Vec<_> = generate_with_runtime(&descriptor, &source, &runtime_import)
        .into_iter()
        .map(|f| (f.name, f.tree.render()))
        .collect();
    if !check {
        fs::create_dir_all(&output).map_err(|e| e.to_string())?;
    }
    for (name, content) in files {
        let target = output.join(&name);
        if fs::read_to_string(&target).ok().as_deref() != Some(&content) {
            if check {
                return Err(format!("Stale generated file: {}", target.display()));
            }
            let temporary = target.with_extension(format!("ets.{}.tmp", process::id()));
            fs::write(&temporary, &content).map_err(|e| e.to_string())?;
            fs::rename(&temporary, &target).map_err(|e| e.to_string())?;
        }
        println!("{} {name}", if check { "Verified" } else { "Generated" });
    }
    Ok(())
}
fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        process::exit(1);
    }
}
