#!/bin/sh
# Clone nerves_livebook at the commit used for the measurements and apply the
# port to Nerves 2 (v2 branch) + this system (path dep) + boot_tools.
# Afterwards: BENCH_APP=nerves_livebook ../variant.sh <label> 5 -- BOOT_MODE=interactive ...
set -e
cd "$(dirname "$0")/.."
[ -d nerves_livebook ] || git clone https://github.com/nerves-livebook/nerves_livebook.git
cd nerves_livebook
git checkout 7e11b91
git apply ../livebook/nerves_livebook-nerves2-boot-tools.patch
echo "nerves_livebook ready in bench/nerves_livebook"
