"""Generate factual item-ID categories from the pinned item_basic.sql (argument 1)."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
groups = {
    'materials': 'SMITHING GOLDSMITHING CLOTHCRAFT LEATHERCRAFT BONECRAFT WOODWORKING ALCHEMY ALCHEMY_2',
    'fish': 'FISH', 'furniture': 'FURNISHINGS',
    'food': 'MEAT_EGGS SEAFOOD VEGETABLES SOUPS BREADS_RICE SWEETS DRINKS INGREDIENTS',
    'medicines': 'MEDICINES', 'crystals': 'CRYSTALS',
    'scrolls': 'WHITE_MAGIC BLACK_MAGIC SUMMONING NINJUTSU SONGS GEOMANCER DICE',
    'tools': 'CARDS NINJA_TOOLS', 'pet': 'PET_ITEMS AUTOMATON',
    'fishing': 'FISHING_GEAR',
}
lookup = {name: key for key, names in groups.items() for name in names.split()}
ids = {key: [] for key in groups}
for line in Path(sys.argv[1]).read_text(encoding='utf-8').splitlines():
    match = re.fullmatch(r"INSERT INTO `item_basic` VALUES \((\d+),.*,@(\w+),\d+\);", line)
    if match and match[2] in lookup:
        ids[lookup[match[2]]].append(int(match[1]))
assert len(ids['fish']) > 50 and len(ids['materials']) > 500
out = ['-- Generated factual ID/category lookup. See third_party/categories.md.', 'local result={};']
for key, values in ids.items():
    for i in range(0, len(values), 40):
        out.append('for _,id in ipairs({' + ','.join(map(str, values[i:i+40])) + "}) do result[id]='" + key + "' end")
out.append('return result;')
(ROOT/'category_data.lua').write_text('\n'.join(out)+'\n', encoding='utf-8')
print(f'Generated {sum(map(len, ids.values()))} item categories.')
