#!/bin/bash
# render_user_guide.sh — docs/USER_GUIDE.md -> docs/USER_GUIDE.pdf (one command).
# Pipeline: python-markdown (installed into analysis/.venv on demand) builds a
# self-contained styled HTML (docs/USER_GUIDE.html), then headless Chrome
# prints it to PDF. Re-run after every edit of USER_GUIDE.md.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PY="$REPO/analysis/.venv/bin/python"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

[ -x "$PY" ] || { echo "analysis/.venv missing — create it first (README)"; exit 1; }
"$PY" -c "import markdown" 2>/dev/null || "$REPO/analysis/.venv/bin/pip" install -q markdown

"$PY" - "$REPO/docs/USER_GUIDE.md" "$REPO/docs/USER_GUIDE.html" <<'EOF'
import sys, markdown
src, dst = sys.argv[1], sys.argv[2]
body = markdown.markdown(open(src).read(), extensions=["tables", "fenced_code", "toc"])
style = """
body { font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;
       font-size: 11pt; line-height: 1.45; color: #1a1a1a;
       max-width: 46em; margin: 2em auto; padding: 0 1.5em; }
h1 { font-size: 20pt; border-bottom: 2px solid #444; padding-bottom: .2em; }
h2 { font-size: 15pt; margin-top: 1.6em; border-bottom: 1px solid #bbb; padding-bottom: .15em; }
h3 { font-size: 12pt; margin-top: 1.2em; }
code { font-family: 'SF Mono', Menlo, monospace; font-size: 9.5pt;
       background: #f2f2f2; padding: .08em .3em; border-radius: 3px; }
pre { background: #f6f6f6; border: 1px solid #ddd; border-radius: 4px;
      padding: .7em .9em; overflow-x: auto; }
pre code { background: none; padding: 0; }
table { border-collapse: collapse; margin: .8em 0; font-size: 10pt; }
th, td { border: 1px solid #ccc; padding: .3em .6em; text-align: left; }
th { background: #eee; }
blockquote { border-left: 3px solid #999; margin-left: 0; padding-left: 1em; color: #444; }
@media print { body { max-width: none; margin: 0; }
               h2 { page-break-after: avoid; } pre, table { page-break-inside: avoid; } }
"""
open(dst, "w").write(
    f"<!doctype html><html><head><meta charset='utf-8'>"
    f"<title>slice-ephys-mapping User Guide</title><style>{style}</style></head>"
    f"<body>{body}</body></html>")
print(f"wrote {dst}")
EOF

"$CHROME" --headless --disable-gpu \
  --no-pdf-header-footer \
  --print-to-pdf="$REPO/docs/USER_GUIDE.pdf" \
  "file://$REPO/docs/USER_GUIDE.html" 2>/dev/null
echo "wrote $REPO/docs/USER_GUIDE.pdf"
