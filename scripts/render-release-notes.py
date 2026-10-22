#!/usr/bin/env python3
"""Render the changelog's headings/lists as self-contained Sparkle HTML.

Keep the Markdown text separately for the GitHub Release body. No remote
resources or executable markup from the changelog are included in the HTML.
"""
import html
from pathlib import Path
import re
import sys

version, stem = sys.argv[1:]
text = Path('CHANGELOG.md').read_text()
marker = f'## [{version}]'
if marker not in text:
    marker = '## [Unreleased]'
notes = text.split(marker, 1)[1].split('\n## [', 1)[0].strip()
if notes.startswith('- '):
    notes = notes.split('\n', 1)[-1].strip()
notes = notes or f'SmarterShot {version}'
Path(stem + '.txt').write_text(notes)

def inline(value):
    value = html.escape(value)
    value = re.sub(r'`([^`]+)`', r'<code>\1</code>', value)
    return re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', value)

blocks = []
kind = None
buffer = []
list_open = False

def flush():
    global kind, buffer
    if buffer:
        tag = 'li' if kind == 'li' else 'p'
        blocks.append(f'<{tag}>{inline(" ".join(buffer))}</{tag}>')
    kind = None
    buffer = []

def close_list():
    global list_open
    if list_open:
        blocks.append('</ul>')
        list_open = False

for line in notes.splitlines():
    stripped = line.strip()
    if stripped.startswith('### '):
        flush(); close_list()
        blocks.append(f'<h3>{inline(stripped[4:])}</h3>')
    elif stripped.startswith('- '):
        flush()
        if not list_open:
            blocks.append('<ul>'); list_open = True
        kind = 'li'; buffer = [stripped[2:]]
    elif not stripped:
        flush(); close_list()
    else:
        if kind is None:
            close_list(); kind = 'p'
        buffer.append(stripped)
flush(); close_list()

output = '''<!doctype html><html><head><meta charset="utf-8">
<meta name="color-scheme" content="light dark">
<style>body{font:13px/1.5 -apple-system,BlinkMacSystemFont,sans-serif;margin:16px}
h3{font-size:14px;margin:18px 0 8px}h3:first-child{margin-top:0}
ul{padding-left:20px;margin:0 0 14px}li{margin:0 0 7px}code{font-size:12px}</style>
</head><body>''' + '\n'.join(blocks) + '</body></html>\n'
Path(stem + '.html').write_text(output)
