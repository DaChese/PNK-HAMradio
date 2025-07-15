#!/usr/bin/env python3
import json, os
from googletrans import Translator, LANGUAGES

# load your codes
with open('languages.json', encoding='utf-8') as f:
    langs = [e['code'] for e in json.load(f)['languages']]

# load English template
with open('en.json', encoding='utf-8') as f:
    en_data = json.load(f)

translator = Translator()

for code in langs:
    if code == 'en':
        continue
    if code not in LANGUAGES:
        print(f"⚠️  Skipping unsupported code: {code}")
        continue

    out = {}
    for key, text in en_data.items():
        # skip non-string or empty values
        if not isinstance(text, str) or text.strip() == "":
            out[key] = ""
            continue

        try:
            translated = translator.translate(text, dest=code).text
            out[key] = translated
        except Exception as e:
            print(f"  • Error translating '{key}' → {code}: {e}")
            out[key] = ""

    # write the stub
    with open(f'{code}.json', 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"✅  Translated stub created: {code}.json")

