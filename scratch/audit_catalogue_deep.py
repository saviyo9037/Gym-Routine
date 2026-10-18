import json
import os
import re

demos = json.load(open('assets/exercise_demonstrations.json', encoding='utf-8'))
mismatches = []
for k, v in demos.items():
    source = v.get('mapped_model_source', '')
    if k.lower() != source.lower():
        mismatches.append((k, source, v.get('muscle_group', '')))

print(f"Total exercises in demonstrations.json: {len(demos)}")
print(f"Total exercises where exercise name != mapped_model_source: {len(mismatches)}")
print("\n=== Breakdown of Reused/Approximate Video Sources ===")
for k, src, mg in mismatches:
    print(f"  [{mg:20}] '{k}'  -->  Source: '{src}'")

# Check which sources are used more than once
source_counts = {}
for k, v in demos.items():
    s = v.get('mapped_model_source', '')
    source_counts[s] = source_counts.get(s, 0) + 1

multis = {s: c for s, c in source_counts.items() if c > 1}
print(f"\nTotal video sources reused for multiple exercises: {len(multis)}")
for s, c in sorted(multis.items(), key=lambda x: -x[1]):
    exs = [k for k, v in demos.items() if v.get('mapped_model_source') == s]
    print(f"  Source '{s}' used {c} times for:")
    for e in exs:
        print(f"     - {e}")
