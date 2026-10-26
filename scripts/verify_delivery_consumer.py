#!/usr/bin/env python3
"""Consume an actual private source ZIP; never substitutes for moon package."""
import argparse
import csv
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import zipfile
import xml.etree.ElementTree as ET


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def unpack(archive, destination, prefix=""):
    """Reject aliases/links and bound extraction before creating any files."""
    with zipfile.ZipFile(archive) as z:
        names = set()
        entries = []
        if sum(i.file_size for i in z.infolist()) > 256 * 1024 * 1024:
            raise ValueError("source archive exceeds private extraction budget")
        for item in z.infolist():
            name = item.filename
            parts = PurePosixPath(name).parts
            if (name.startswith("/") or "\\" in name or ":" in name
                    or any(p in (".", "..") for p in parts)
                    or name != "/".join(parts) + ("/" if item.is_dir() else "")
                    or name in names or stat.S_ISLNK(item.external_attr >> 16)):
                raise ValueError("unsafe source archive member")
            names.add(name)
            if not name.startswith(prefix):
                raise ValueError("unexpected source archive prefix")
            relative = name[len(prefix):]
            if relative and not item.is_dir():
                entries.append((relative, z.read(item)))
    destination.mkdir(parents=True, exist_ok=False)
    for name, data in entries:
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)


MAIN = r'''
extern "js" fn put_bytes(name : String, data : Bytes) -> Unit =
  #| (n,d) => require('node:fs').writeFileSync(require('node:path').join(process.env.CONSUMER_OUTPUT,n),d)

extern "js" fn put_text(name : String, data : String) -> Unit =
  #| (n,d) => require('node:fs').writeFileSync(require('node:path').join(process.env.CONSUMER_OUTPUT,n),d,'utf8')

extern "js" fn fail() -> Unit =
  #| () => process.exit(1)

fn main {
  try {
    put_bytes("readme.ods", report())
    let book = @ods.Workbook::new()
    let sheet = book.add_sheet("互操作😀")
    sheet.set_row(0, 0, [
      @ods.Cell::new(Text("描述")), @ods.Cell::new(Text("内容")),
      @ods.Cell::new(Text("显式空")), @ods.Cell::new(Text("空字符串")),
    ])
    sheet.set_row(1, 0, [
      @ods.Cell::new(Text("你好😀")), @ods.Cell::new(Text("comma,\"quote\"\nsecond")),
      @ods.Cell::new(Empty), @ods.Cell::new(Text("")),
    ])
    sheet.set_row(2, 0, [
      @ods.Cell::new(Text("=1+2")), @ods.Cell::new(Text("  spaced ")),
      @ods.Cell::new(Text("tail")), @ods.Cell::new(Number(-2.5)),
    ])
    let bytes = book.to_ods()
    put_bytes("edge.ods", bytes)
    let imported = @ods.read_ods(bytes, allow_formatting_loss=true).workbook()
    let result = imported.sheet(0).unwrap()
    assert_eq(result.get(1, 2).unwrap().value(), Empty)
    assert_eq(result.get(1, 3).unwrap().value(), Text(""))
    assert_eq(result.get(1, 0).unwrap().value(), Text("你好😀"))
    assert_eq(imported.sheet(99) is None, true)
    put_text("api.csv", result.to_csv())
    println("DELIVERY_CONSUMER_JS_OK")
  } catch {
    error => { println(error); fail() }
  }
}
'''

EXPECTED = [
    ["描述", "内容", "显式空", "空字符串"],
    ["你好😀", 'comma,"quote"\nsecond', "", ""],
    ["=1+2", "  spaced ", "tail", "-2.5"],
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--sdk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    archive, sdk = args.archive.resolve(), args.sdk.resolve()
    before = sha(archive)
    report = {"status": "FAIL", "scope": "actual private source ZIP, explicit local workspace paths and bundled declared flate; NOT official moon package or registry installation", "input_archive_sha256": before, "steps": []}
    env = {"PATH": str(sdk / "bin") + ":" + str(Path(shutil.which("node")).parent) + ":/usr/bin:/bin", "LANG": "C.UTF-8", "MOON_HOME": str(out / "moon-state"), "MOON_TOOLCHAIN_ROOT": str(sdk)}
    env["CONSUMER_OUTPUT"] = str(out / "generated")
    report["environment"] = env

    def run(name, command, cwd, extra=None, expected_exit=0):
        p = subprocess.run([str(x) for x in command], cwd=cwd, env={**env, **(extra or {})}, capture_output=True, text=True, timeout=180)
        (out / (name + ".stdout.txt")).write_text(p.stdout)
        (out / (name + ".stderr.txt")).write_text(p.stderr)
        report["steps"].append({"name": name, "command": [str(x) for x in command], "cwd": str(cwd), "configuration": extra or {}, "exit_code": p.returncode, "expected_exit": expected_exit})
        if p.returncode != expected_exit:
            raise RuntimeError(name + " unexpected exit; see logs")
        return p

    try:
        workspace = out / "workspace"
        candidate, consumer = workspace / "candidate", workspace / "consumer"
        unpack(archive, candidate, "MoonODS/")
        state = json.loads((candidate / "SOURCE_STATE.json").read_text())
        report["source_commit"] = state["head"]
        for name, digest in state["files_sha256"].items():
            if sha(candidate / name) != digest:
                raise ValueError("source manifest mismatch: " + name)
        report["archive_manifest_hash_count"] = len(state["files_sha256"])
        forbidden = {".git", ".mooncakes", ".aws", ".ssh", ".codex", ".env", "credentials.json"}
        forbidden_paths = [str(p.relative_to(candidate)) for p in candidate.rglob("*") if p.name in forbidden]
        if forbidden_paths:
            raise ValueError("unexpected active cache or credential path")
        report["forbidden_paths"] = forbidden_paths
        report["source_archive_scope"] = "Source, necessary fixtures and current dependency; no Git history or historical audit evidence"
        report["formal_package_contents"] = "NOT RUN: source-archive consumption is not official moon package or registry installation"
        # Dependency provenance comes only from the consumed archive's lock and bytes.
        lock = json.loads((candidate / "DEPENDENCIES.lock.json").read_text())
        flate = lock["flate"]
        dep_archive = candidate / flate["archive"]
        if sha(dep_archive) != flate["sha256"]:
            raise ValueError("bundled flate checksum mismatch")
        unpack(dep_archive, workspace / "flate")
        report["declared_dependency"] = {k: flate[k] for k in ("module", "version", "archive", "sha256")}
        consumer.mkdir()
        (consumer / "moon.mod").write_text('name = "delivery-audit/consumer"\nversion = "0.1.0"\npreferred_target = "js"\nimport { "sundaysebasidian-byte/moonods@0.2.0" }\n')
        (consumer / "moon.pkg").write_text('import { "sundaysebasidian-byte/moonods" @ods }\noptions("is-main": true)\n')
        readme = (candidate / "README.md").read_text()
        examples = []
        for block in re.findall(r"```(?:mbt|moonbit)\n(.*?)```", readme, re.S):
            declaration = re.search(r"(?m)^fn (report|make_report)\(\)", block)
            if declaration:
                examples.append((block, declaration[1]))
        if len(examples) != 1:
            raise ValueError("expected exactly one README public report API example")
        example, function = examples[0]
        main = example + MAIN.replace("report()", function + "()")
        report["readme_example_function"] = function
        report["readme_example_sha256"] = hashlib.sha256(example.encode()).hexdigest()
        (consumer / "main.mbt").write_text(main)
        (out / "consumer-main.mbt").write_text(main)
        (out / "generated").mkdir()
        (candidate / "moon.work").unlink(missing_ok=True)
        (workspace / "moon.work").write_text('members = ["candidate", "consumer", "flate"]\n')
        report["workspace_adjustment"] = "Only extracted candidate's single-module moon.work replaced by explicit three-member local workspace. No original working-tree files are used; no .mooncakes, registry metadata, or shared dependency cache seeded. --frozen does not prove offline installation."
        run("versions", [sdk / "bin/moon", "version", "--all"], consumer)
        run("readme-api-js", [sdk / "bin/moon", "run", "--frozen", "--target", "js", "--deny-warn", "-j", "1", "."], consumer)
        with (out / "generated/api.csv").open(newline="") as stream:
            rows = list(csv.reader(stream))
        if rows != EXPECTED:
            raise ValueError("API CSV independent oracle mismatch")
        with zipfile.ZipFile(out / "generated/edge.ods") as ods:
            if ods.testzip() is not None or ods.namelist()[0] != "mimetype":
                raise ValueError("independent ODS ZIP oracle mismatch")
            xml = ET.fromstring(ods.read("content.xml"))
        ns = {"table": "urn:oasis:names:tc:opendocument:xmlns:table:1.0", "office": "urn:oasis:names:tc:opendocument:xmlns:office:1.0"}
        table_rows = xml.findall(".//table:table-row", ns)
        cells = table_rows[1].findall("table:table-cell", ns)
        value_type = "{" + ns["office"] + "}value-type"
        if cells[2].get(value_type) is not None or cells[3].get(value_type) != "string":
            raise ValueError("independent Empty/Text-empty ODS oracle mismatch")
        report["independent_ods_oracle"] = "PASS: ZIP CRC/order, XML; Empty has no value type and empty Text has string type"
        run("build-documentation-cli", [sdk / "bin/moon", "build", "--frozen", "examples/ods_tool", "--target", "js", "--deny-warn", "-j", "1"], candidate)
        # Multiple workspace members namespace build outputs by module name.
        cli = workspace / "_build/js/debug/build/sundaysebasidian-byte/moonods/examples/ods_tool/ods_tool.js"
        source = out / "generated/edge.ods"
        source_before = sha(source)
        config = {"ODS_INPUT": str(source), "ODS_ACCEPT_LOSS": "1", "ODS_CSV": str(out / "generated/cli.csv")}
        run("ods-to-csv-cli", ["node", cli], candidate, config)
        with (out / "generated/cli.csv").open(newline="") as stream:
            actual = list(csv.reader(stream))
        if actual != EXPECTED:
            raise ValueError("CLI CSV independent oracle mismatch")
        cases = out / "negative"
        cases.mkdir()
        for name in ["bad-zip", "missing-content", "wrong-sheet", "output-directory", "same-path"]:
            case = cases / name
            case.mkdir()
            inp, csv_out, ods_out = case / "input.ods", case / "output.csv", case / "output.ods"
            inp.write_bytes(source.read_bytes())
            csv_out.write_bytes(b"PREVIOUS CSV\n")
            ods_out.write_bytes(b"PREVIOUS ODS\n")
            if name == "bad-zip":
                inp.write_bytes(b"not a ZIP: bounded negative input")
            if name == "missing-content":
                with zipfile.ZipFile(source) as original, zipfile.ZipFile(inp, "w") as bad:
                    for item in original.infolist():
                        if item.filename != "content.xml":
                            bad.writestr(item, original.read(item))
            current = {"ODS_INPUT": str(inp), "ODS_ACCEPT_LOSS": "1", "ODS_CSV": str(csv_out), "ODS_OUTPUT": str(ods_out)}
            if name == "wrong-sheet":
                current["ODS_SET"] = "99,1,0,8.5"
            if name == "output-directory":
                ods_out.unlink()
                ods_out.mkdir()
            if name == "same-path":
                current["ODS_CSV"] = str(inp)
            existing = {str(p): sha(p) for p in case.iterdir() if p.is_file()}
            run("reject-" + name, ["node", cli], candidate, current, expected_exit=1)
            if any(sha(Path(n)) != digest for n, digest in existing.items()):
                raise ValueError(name + " changed a prior input/output")
            if list(case.glob(".moonods-*.tmp")):
                raise ValueError(name + " left temporary files")
        report["input_ods_sha256"] = source_before
        report["input_ods_unchanged"] = sha(source) == source_before
        report["input_archive_unchanged"] = sha(archive) == before
        if not report["input_ods_unchanged"] or not report["input_archive_unchanged"]:
            raise ValueError("consumed input changed")
        report["independent_csv_oracle"] = "PASS: Unicode, quote, comma, embedded LF, Empty/Text empty -> empty CSV fields, spaces, formula-like Text, typed negative number"
        report["generated_sha256"] = {p.name: sha(p) for p in sorted((out / "generated").iterdir())}
        report["status"] = "PASS"
        report["formal_packaging"] = "NOT RUN: this verifier consumes source archives only"
        report["registry_installation"] = "NOT RUN"
        report["wasm_excel_full_suite"] = "NOT RUN"
        report["cli_path"] = str(cli)
    except Exception as error:
        report["error"] = str(error)
    (out / "consumer.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
