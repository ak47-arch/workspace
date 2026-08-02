#!/usr/bin/env python3
"""Re-sort knowledge base index entries oldest→newest within each project section."""
import re
import os

WORKSPACE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INDEX_PATH = os.path.join(WORKSPACE, 'docs/knowledge/index.md')

def get_date_from_file(filepath):
    """Extract the Date field from a decision file."""
    full_path = os.path.join(WORKSPACE, 'docs/knowledge', filepath)
    file_path_clean = full_path.split('#')[0]
    try:
        with open(file_path_clean, 'r', encoding='utf-8') as f:
            for line in f:
                m = re.match(r'^\*?\*?Date\*?\*?:\s*([\d\-]+ [\d:]+)', line)
                if m:
                    return m.group(1)
    except (FileNotFoundError, IOError):
        pass
    return None

with open(INDEX_PATH, 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')

# Parse the file: header (before first ###), then sections
header_lines = []
sections = {}  # project -> {'header': line, 'entries': [(date, title, path, line)]}
current_project = None
current_entries = []
current_header = None
in_header = True

for line in lines:
    m = re.match(r'^### (.+)', line)
    if m:
        # Start a new section
        if current_project is not None:
            sections[current_project] = {'header': current_header, 'entries': current_entries}
        current_project = m.group(1).strip()
        current_header = line
        current_entries = []
        in_header = False
    elif in_header:
        header_lines.append(line)
    elif current_project is not None:
        entry_m = re.match(r'^- \[(.+)\]\((.+)\)', line)
        if entry_m:
            title = entry_m.group(1)
            path = entry_m.group(2)
            date = get_date_from_file(path)
            if date is None:
                date = '0000'  # No date found, sort to beginning
            current_entries.append((date, title, path, line))
        else:
            # Non-entry lines between sections (blank lines, separator)
            # We'll regenerate cleanly, so skip these
            pass

# Don't forget the last section
if current_project is not None:
    sections[current_project] = {'header': current_header, 'entries': current_entries}

# Sort entries within each section by date (oldest → newest)
for project in sections:
    sections[project]['entries'].sort(key=lambda x: x[0])

# Rebuild the index
output = []
output.extend(header_lines)
output.append('')  # blank line after header

first = True
for project, data in sections.items():
    if not first:
        output.append('')  # blank line between sections
    first = False
    output.append(data['header'])
    output.append('')
    for date, title, path, orig_line in data['entries']:
        output.append(f'- [{title}]({path})')

with open(INDEX_PATH, 'w', encoding='utf-8') as f:
    f.write('\n'.join(output))
    f.write('\n')

print("Index re-sorted oldest → newest within each project section.")
for project, data in sections.items():
    dates = [e[0] for e in data['entries']]
    if dates:
        print(f"  {project}: {dates[0]} → {dates[-1]} ({len(dates)} entries)")