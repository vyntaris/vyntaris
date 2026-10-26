#!/usr/bin/env python3
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

TOOL = os.environ.get("DOC_INDEX") or str(pathlib.Path(__file__).resolve().parent.parent / "rust/target/release/vyntaris-doc-index")
home = pathlib.Path(tempfile.mkdtemp())
env = dict(os.environ, HOME=str(home), XDG_CACHE_HOME=str(home / ".cache"), XDG_CONFIG_HOME=str(home / ".config"))
docs = home / "Documents"
docs.mkdir()
fails = 0

def check(what, ok):
    global fails
    print(("   ok    " if ok else "   FAIL  ") + what)
    fails += not ok

def run(*args):
    return subprocess.run([TOOL, *args], capture_output=True, text=True, env=env).stdout

def found(words):
    return [pathlib.Path(l.split("\t")[0]).name for l in run("search", words).splitlines()]

def zipped(name, parts):
    with zipfile.ZipFile(docs / name, "w") as z:
        for part, xml in parts.items():
            z.writestr(part, xml)

zipped("report.docx", {"word/document.xml": "<w:document><w:body><w:p><w:r><w:t>Quarterly revenue grew in Belgrade</w:t></w:r></w:p></w:body></w:document>"})
zipped("budget.xlsx", {"xl/sharedStrings.xml": "<sst><si><t>Marketing</t></si><si><t>Zanzibar expenses</t></si></sst>"})
zipped("talk.pptx", {"ppt/slides/slide1.xml": "<p:sld><a:p><a:r><a:t>Roadmap for the giraffe project</a:t></a:r></a:p></p:sld>"})
zipped("notes.odt", {"content.xml": "<office:document-content><text:p>Čačak meeting about přílišné things</text:p></office:document-content>"})
(docs / "plain.md").write_text("# Shopping\nbuy pomegranates\n")
stream = b"BT /F1 12 Tf 72 720 Td (Invoice for the walrus sanctuary) Tj ET"
objs = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Length %d >>\nstream\n" % len(stream) + stream + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"]
pdf, offsets = b"%PDF-1.4\n", []
for i, o in enumerate(objs, 1):
    offsets.append(len(pdf))
    pdf += b"%d 0 obj\n" % i + o + b"\nendobj\n"
xref = len(pdf)
pdf += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1) + b"".join(b"%010d 00000 n \n" % o for o in offsets)
pdf += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, xref)
(docs / "invoice.pdf").write_bytes(pdf)
(docs / "broken.docx").write_bytes(b"not a zip at all")
(docs / ".hidden.txt").write_text("secret walrus")
(docs / "node_modules").mkdir()
(docs / "node_modules" / "x.md").write_text("pomegranates in node_modules")

print(":: every kind of document, by what's in it")
out = run("index")
check("it reads them all, and a damaged one doesn't stop it", out.startswith("7 documents read"))
check("Word", found("quarterly revenue") == ["report.docx"])
check("Excel", found("zanzibar") == ["budget.xlsx"])
check("PowerPoint", found("giraffe") == ["talk.pptx"])
check("OpenDocument, without the accents", found("cacak") == ["notes.odt"])
if shutil.which("pdftotext"):
    check("PDF", found("walrus") == ["invoice.pdf"])
else:
    print("   (no pdftotext here: PDF skipped)")
check("plain text", found("pomegranates") == ["plain.md"])
check("the last word as it's typed", found("quarterly rev") == ["report.docx"])
check("by name too", found("budget") == ["budget.xlsx"])
check("hidden files and node_modules left out", "x.md" not in found("pomegranates") and ".hidden.txt" not in found("secret"))
check("nothing for nothing", found("xylophonequartz") == [])

print(":: kept up to date")
check("nothing changed: nothing read", run("index").startswith("0 documents read"))
(docs / "plain.md").write_text("# Shopping\nbuy quinces\n")
(docs / "budget.xlsx").unlink()
out = run("index")
check("a changed one read again, a gone one dropped", out.startswith("1 documents read, 1 gone"))
check("… its new words found", found("quinces") == ["plain.md"] and found("pomegranates") == [])
check("… the gone one not", found("zanzibar") == [])
check("stats", "6 documents" in run("stats"))

print(":: a spreadsheet's first sheet, as a table (Quick Look)")
zipped("grid.xlsx", {
    "xl/sharedStrings.xml": "<sst><si><t>Name</t></si><si><t>Total</t></si><si><r><t>Ana </t></r><r><t>&amp; Co</t></r></si></sst>",
    "xl/worksheets/sheet1.xml": '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>'
                                '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="C2"><f>B2*2</f><v>42</v></c></row></sheetData></worksheet>'})
zipped("grid.ods", {"content.xml": '<office:document-content><table:table table:name="S"><table:table-row>'
                                   '<table:table-cell><text:p>x</text:p></table:table-cell><table:table-cell table:number-columns-repeated="2"><text:p>y</text:p></table:table-cell>'
                                   '<table:table-cell table:number-columns-repeated="1000"/></table:table-row></table:table></office:document-content>'})
(docs / "grid.csv").write_text('a,"b, c",d\n1,2,3\n')
check("xlsx: shared strings, empty columns kept, formulas by their value", run("table", str(docs / "grid.xlsx")) == "Name\t\tTotal\nAna & Co\t\t42\n")
check("ods: repeated cells, and the sheet's empty end left out", run("table", str(docs / "grid.ods")) == "x\ty\ty\n")
check("csv: quoted commas", run("table", str(docs / "grid.csv")) == "a\tb, c\td\n1\t2\t3\n")

shutil.rmtree(home)
print()
print("doc-index: all checks passed" if fails == 0 else f"doc-index: {fails} failed")
sys.exit(1 if fails else 0)
