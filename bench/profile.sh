#!/bin/sh
# Write the module set loaded at IEx startup (from the latest report of LABEL)
# to profiles/NAME.mods. Usage: profile.sh LABEL NAME
R=$(ls results/runs/*-$1.report.json | tail -1)
python3 -c "import json,sys; print('\n'.join(json.load(open('$R'))['boot_modules']))" > profiles/$2.mods
wc -l profiles/$2.mods
