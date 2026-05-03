#!/usr/bin/env python3
"""
Simple builder script to create a packaged SQLite DB for Hanzi data.

Usage:
  python3 tools/build_hanzi_db.py \
    --cedict tools/data_raw/cedict_1_0_ts_utf-8_mdbg.txt \
    --freq tools/data_raw/subtlexch_char_freq.tsv \
    --confusables tools/data_raw/wiktionary_confusables.txt \
    --out assets/db/hanzi.sqlite

The script is intentionally conservative — it creates a small SQLite DB with tables:
  - dictionary(id, traditional, simplified, pinyin, definitions)
  - freq(char, frequency)
  - confusables(group_id, chars)

It does not attempt heavy normalization; treat this as a starting point.
"""
import argparse
import sqlite3
import os
import gzip
import sys


def open_text(path):
    if path is None:
        return None
    if path.endswith('.gz'):
        return gzip.open(path, 'rt', encoding='utf-8')
    return open(path, 'r', encoding='utf-8')


def parse_cedict(path, cur):
    if not path:
        return 0
    count = 0
    with open_text(path) as f:
        for ln in f:
            ln = ln.strip()
            if not ln or ln.startswith('#'):
                continue
            # Format: Traditional Simplified [pinyin] /definition1/definition2/
            try:
                trad_simp, rest = ln.split(' ', 1)
                # Actually cedict has: trad simplified [pinyin] /defs/
                parts = ln.split()
                trad = parts[0]
                simp = parts[1]
                # Extract pinyin inside [ ]
                pinyin = ''
                defs = ''
                if '[' in ln and ']' in ln:
                    pinyin = ln[ln.index('[')+1:ln.index(']')]
                    defs_part = ln[ln.index(']')+1:].strip()
                else:
                    # fallback
                    defs_part = ' '.join(parts[2:])
                defs = defs_part.strip()
                # strip leading slashes if present
                if defs.startswith('/') and defs.endswith('/'):
                    defs = defs[1:-1]
                cur.execute(
                    'INSERT INTO dictionary(traditional, simplified, pinyin, definitions) VALUES(?,?,?,?)',
                    (trad, simp, pinyin, defs)
                )
                count += 1
            except Exception:
                # best effort; skip malformed lines
                continue
    return count


def parse_freq(path, cur):
    if not path:
        return 0

    # if a directory was passed, try to pick a likely file inside it
    if os.path.isdir(path):
        candidates = [f for f in os.listdir(path) if f.lower().endswith(('.tsv', '.csv', '.txt', '.xlsx'))]
        if not candidates:
            return 0
        path = os.path.join(path, candidates[0])

    # Handle Excel .xlsx files using openpyxl if available
    if path.lower().endswith('.xlsx'):
        try:
            import openpyxl
            wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
            ws = wb.active
            count = 0
            for row in ws.iter_rows(values_only=True):
                if not row:
                    continue
                # naive: find first single-character string in the row
                char = None
                freq = None
                for cell in row:
                    if isinstance(cell, str) and len(cell.strip()) == 1:
                        char = cell.strip()
                        break
                # try to locate a numeric frequency in the row (from the end)
                for cell in reversed(row):
                    if isinstance(cell, (int, float)):
                        freq = float(cell)
                        break
                    if isinstance(cell, str):
                        try:
                            freq = float(cell.replace(',', ''))
                            break
                        except Exception:
                            continue
                if char:
                    cur.execute('INSERT INTO freq(char, frequency) VALUES(?,?)', (char, freq if freq is not None else 0.0))
                    count += 1
            return count
        except Exception as e:
            print('openpyxl not available or failed to read xlsx:', e)
            # fallthrough to text parsing

    # Try reading as text with several common encodings
    encodings_to_try = ['utf-8', 'latin-1', 'gb18030']
    last_exc = None
    for enc in encodings_to_try:
        try:
            with open(path, 'r', encoding=enc) as f:
                count = 0
                for ln in f:
                    ln = ln.strip()
                    if not ln:
                        continue
                    parts = ln.split()
                    char = None
                    freq = None
                    for p in parts:
                        if len(p) == 1:
                            char = p
                            break
                    for p in reversed(parts):
                        try:
                            freq = float(p.replace(',', ''))
                            break
                        except Exception:
                            continue
                    if char:
                        cur.execute('INSERT INTO freq(char, frequency) VALUES(?,?)', (char, freq if freq is not None else 0.0))
                        count += 1
                return count
        except Exception as e:
            last_exc = e
            continue

    print('Failed to read frequency file:', last_exc)
    return 0


def parse_confusables(path, cur):
    if not path:
        return 0
    count = 0
    gid = 0
    with open_text(path) as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            # Each non-empty line treated as a group
            gid += 1
            cur.execute('INSERT INTO confusables(group_id, chars) VALUES(?,?)', (gid, ln))
            count += 1
    return count


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cedict', help='Path to CC-CEDICT text file (utf-8)')
    ap.add_argument('--freq', help='Path to character frequency file (tsv/csv)')
    ap.add_argument('--confusables', help='Path to confusables text file')
    ap.add_argument('--out', default='assets/db/hanzi.sqlite', help='Output SQLite path')
    ap.add_argument('--force', action='store_true')
    args = ap.parse_args()

    outdir = os.path.dirname(args.out)
    if outdir and not os.path.exists(outdir):
        os.makedirs(outdir, exist_ok=True)

    if os.path.exists(args.out) and not args.force:
        print('Output exists:', args.out)
        print('Use --force to overwrite')
        sys.exit(0)

    conn = sqlite3.connect(args.out)
    cur = conn.cursor()

    cur.execute('''
        CREATE TABLE IF NOT EXISTS dictionary (
            id INTEGER PRIMARY KEY,
            traditional TEXT,
            simplified TEXT,
            pinyin TEXT,
            definitions TEXT
        )
    ''')

    cur.execute('''
        CREATE TABLE IF NOT EXISTS freq (
            id INTEGER PRIMARY KEY,
            char TEXT,
            frequency REAL
        )
    ''')

    cur.execute('''
        CREATE TABLE IF NOT EXISTS confusables (
            id INTEGER PRIMARY KEY,
            group_id INTEGER,
            chars TEXT
        )
    ''')

    print('Parsing CC-CEDICT...')
    n1 = parse_cedict(args.cedict, cur)
    print('Dictionary entries:', n1)

    print('Parsing frequency...')
    n2 = parse_freq(args.freq, cur)
    print('Freq entries:', n2)

    # Confusables are optional — skip if not provided or file missing
    if args.confusables and os.path.exists(args.confusables):
        print('Parsing confusables...')
        n3 = parse_confusables(args.confusables, cur)
        print('Confusable groups:', n3)
    else:
        print('Skipping confusables (not provided or file missing)')
        n3 = 0

    # Indexes for performance
    cur.execute('CREATE INDEX IF NOT EXISTS idx_dictionary_trad ON dictionary(traditional)')
    cur.execute('CREATE INDEX IF NOT EXISTS idx_dictionary_simp ON dictionary(simplified)')
    cur.execute('CREATE INDEX IF NOT EXISTS idx_dictionary_pinyin ON dictionary(pinyin)')
    cur.execute('CREATE INDEX IF NOT EXISTS idx_freq_char ON freq(char)')

    # FTS for fast search
    cur.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS dictionary_fts USING fts5(
            traditional,
            simplified,
            pinyin,
            content="dictionary",
            content_rowid="id"
        )
    ''')
    cur.execute('INSERT INTO dictionary_fts(dictionary_fts) VALUES(\'rebuild\')')

    conn.commit()
    conn.close()
    print('Wrote', args.out)

if __name__ == '__main__':
    main()
