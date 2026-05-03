import csv
import json
import os
import re
from html import unescape


INPUT_FILE = "/Users/dannyc/Documents/Apps/Brave Cow/brave_cows_app/tools/data_raw/All Decks Text.txt"
OUTPUT_FILE = "/Users/dannyc/Documents/Apps/Brave Cow/brave_cows_app/assets/lists/anki_cards.txt"
EDITABLE_CSV_FILE = "/Users/dannyc/Documents/Apps/Brave Cow/brave_cows_app/assets/lists/anki_cards_editable.csv"


def clean_html_text(text):
    text = re.sub(r"<[^>]+>", "", text)
    text = unescape(text)
    text = text.replace("&nbsp;", " ")
    return re.sub(r"\s+", " ", text).strip()


def extract_text_block(html_block, font_size, *, require_ex=False, exclude_ex=False):
    pattern = rf'<div[^>]*font-size:{font_size}px[^>]*>(.*?)</div>'
    for match in re.finditer(pattern, html_block, re.DOTALL | re.IGNORECASE):
        text = clean_html_text(match.group(1))
        if require_ex and not text.lower().startswith('ex:'):
            continue
        if exclude_ex and text.lower().startswith('ex:'):
            continue
        return text
    return ''


def extract_first_match(pattern, html_block, *, flags=0):
    match = re.search(pattern, html_block, flags)
    if not match:
        return ''
    return clean_html_text(match.group(1))


def parse_anki_export(file_path):
    cards = []

    with open(file_path, 'r', encoding='utf-8', newline='') as file:
        reader = csv.reader(file, delimiter='\t', quotechar='"', doublequote=True)
        for row in reader:
            if not row or row[0].startswith('#'):
                continue
            if len(row) < 2:
                continue

            english_html = row[0]
            chinese_html = row[1]

            english_word = extract_text_block(english_html, 24)
            if 'ex:' in english_word.lower():
                english_word = english_word.split('ex:')[0].strip()

            english_example = extract_text_block(english_html, 16, require_ex=True)
            if english_example.lower().startswith('ex:'):
                english_example = english_example[3:].strip()

            chinese_word = extract_text_block(chinese_html, 24)
            if not chinese_word:
                chinese_word = extract_first_match(r'<b[^>]*>(.*?)</b>', chinese_html, flags=re.DOTALL)

            pinyin = extract_text_block(chinese_html, 16, exclude_ex=True)

            chinese_example = extract_text_block(chinese_html, 16, require_ex=True)
            if chinese_example.lower().startswith('ex:'):
                chinese_example = chinese_example[3:].strip()

            if chinese_word:
                cards.append([
                    chinese_word,
                    english_word,
                    pinyin,
                    english_example,
                    chinese_example,
                ])

    return cards


def load_editable_cards(file_path):
    cards = []

    with open(file_path, 'r', encoding='utf-8', newline='') as file:
        reader = csv.DictReader(file)
        for row in reader:
            if not row:
                continue
            chinese_word = (row.get('chinese') or '').strip()
            if not chinese_word:
                continue
            cards.append([
                chinese_word,
                (row.get('english') or '').strip(),
                (row.get('pinyin') or '').strip(),
                (row.get('example_en') or '').strip(),
                (row.get('example_zh') or '').strip(),
            ])

    return cards


def write_outputs(cards, output_file, editable_csv_file):
    os.makedirs(os.path.dirname(output_file), exist_ok=True)

    with open(output_file, 'w', encoding='utf-8') as file:
        for card in cards:
            escaped_card = [value.replace('|', '\\|') for value in card]
            file.write('|'.join(escaped_card) + '\n')

    with open(editable_csv_file, 'w', encoding='utf-8', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(['chinese', 'english', 'pinyin', 'example_en', 'example_zh'])
        writer.writerows(cards)

    json_file = output_file.replace('.txt', '.json')
    json_cards = [
        {
            'chinese': card[0],
            'english': card[1],
            'pinyin': card[2],
            'example_en': card[3],
            'example_zh': card[4],
        }
        for card in cards
    ]
    with open(json_file, 'w', encoding='utf-8') as file:
        json.dump(json_cards, file, ensure_ascii=False, indent=2)


def print_preview(cards, limit=10):
    preview_cards = cards[:limit]
    if not preview_cards:
        return

    headers = ['chinese', 'english', 'pinyin']
    rows = [headers] + [[card[0], card[1], card[2]] for card in preview_cards]
    widths = [0, 0, 0]
    for row in rows:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))

    def format_row(row):
        return ' | '.join(cell.ljust(widths[index]) for index, cell in enumerate(row))

    print('\nPreview:')
    print(format_row(headers))
    print('-+-'.join('-' * width for width in widths))
    for card in preview_cards:
        print(format_row([card[0], card[1], card[2]]))


if __name__ == '__main__':
    try:
        import argparse

        parser = argparse.ArgumentParser()
        parser.add_argument('--rebuild-from-raw', action='store_true')
        args = parser.parse_args()

        if os.path.exists(EDITABLE_CSV_FILE) and not args.rebuild_from_raw:
            print(f'Loading editable cards: {EDITABLE_CSV_FILE}')
            cards = load_editable_cards(EDITABLE_CSV_FILE)
            print(f'Loaded {len(cards)} cards from editable CSV')
        else:
            print(f'Parsing: {INPUT_FILE}')
            cards = parse_anki_export(INPUT_FILE)
            print(f'Parsed {len(cards)} cards')

        if not cards:
            raise RuntimeError('No cards were parsed')

        write_outputs(cards, OUTPUT_FILE, EDITABLE_CSV_FILE)
        print(f'Saved {len(cards)} cards to: {OUTPUT_FILE}')
        print(f'Saved editable CSV to: {EDITABLE_CSV_FILE}')
        print(f'Saved JSON to: {OUTPUT_FILE.replace(".txt", ".json")}')

        print_preview(cards, limit=10)
    except FileNotFoundError:
        print(f'File not found: {INPUT_FILE}')
    except Exception as error:
        print(f'Error: {error}')
        import traceback
        traceback.print_exc()