#!/usr/bin/env python

""" 1.2.2-clean-text.py """


from pathlib import Path
import re
import unicodedata
import urllib.request


def load_confusables_mapping():
    confusables = Path("confusables.txt")
    mapping = {}

    if confusables.exists():
        file_content = confusables.read_text(encoding="utf-8")
    else:
        print("📞", end="")
        with urllib.request.urlopen(
            "https://www.unicode.org/Public/security/latest/confusables.txt"
        ) as response:
            file_content = response.read().decode("utf-8")
        print("...", end="")
        confusables.write_text(file_content, encoding="utf-8")
        print("✔️")

    for line in file_content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = re.split(r"\s*;\s*", line)
        if len(parts) >= 2:
            key = chr(int(parts[0], 16))
            value = "".join(chr(int(cp, 16)) for cp in parts[1].split())
            mapping[key] = value

    return mapping


def remove_accents(text):
    """Removes accents from all characters while preserving base letters."""
    return "".join(
        c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c)
    )


if __name__ == "__main__":
    cmap = load_confusables_mapping()

    text = """Héllo Wörld! 
            
            
              𝐻 𝑒𝑙𝑙𝑜"""
    print("Original:", text)

    normalized_text = unicodedata.normalize("NFKC", re.sub(r"\s+", " ", text.strip()))
    print("Normal:  ", normalized_text)

    no_accents_text = remove_accents(normalized_text)
    print("No acc:  ", no_accents_text)

    reduced_text = "".join(cmap.get(char, char) for char in no_accents_text)
    print("Reduced: ", reduced_text)
