#!/bin/bash

##
## Case Name: verify PCM list with tplg file
## Preconditions:
##    driver already inserted with modprobe
## Description:
##    using /proc/asound/pcm to compare with tplg content
##    Supports multiple topology files separated by colon (:) or comma (,)
## Case step:
##    1. load tplg file(s) to get pipeline list string
##    2. load /proc/asound/pcm to get pcm list string
##    3. compare string list
## Expect result:
##    pipeline list is same as pcm list
##

set -e

# source from the relative path of current folder
# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../case-lib/lib.sh"

OPT_NAME['t']='tplg'     OPT_DESC['t']='tplg file(s), separated by : or , default value is env TPLG: $''TPLG'
OPT_HAS_ARG['t']=1         OPT_VAL['t']="${TPLG:-}"

func_opt_parse_option "$@"
tplg=${OPT_VAL['t']}

start_test

# Support multiple topologies separated by colon (:) or comma (,)
# sof-tplgreader.py natively supports multiple files with comma separator
tplg="${tplg//,/:}"  # Normalize to colon first
# Parse and validate topology files
func_tplg_parse_and_validate "$tplg"
tplg_files="$TPLG_FILES"

dlogi "Processing $TPLG_COUNT topology file(s)"

setup_kernel_check_point

# Build filter options (same as pipeline.sh func_pipeline_export)
opt=""
# In no HDMI mode, exclude HDMI pipelines
[ -z "$NO_HDMI_MODE" ] || opt="$opt & ~pcm:HDMI"
# In no Bluetooth mode, exclude BT pipelines
[ -z "$NO_BT_MODE" ] || opt="$opt & ~pcm:Bluetooth"
# In no DMIC mode, exclude DMIC pipelines
[ -z "$NO_DMIC_MODE" ] || opt="$opt & ~pcm:DMIC"

# Remove leading " & " if present
opt="${opt# & }"

# Build sof-tplgreader.py command with filter
if [ -n "$opt" ]; then
    dlogi "Applying pipeline filter: $opt"
    tplg_str=$(sof-tplgreader.py "$tplg_files" -f "$opt" -d id pcm type -o)
else
    tplg_str=$(sof-tplgreader.py "$tplg_files" -d id pcm type -o)
fi

# Deduplicate and sort pipelines numerically by id
# Same pipeline (id + pcm + type) can appear in multiple topology files
# Sort format: id=X;pcm=Y;type=Z
# -t';' uses semicolon as delimiter, -k1.4 sorts by field 1 starting at char 4 (after "id=")
# -n for numeric sort, -u for unique
tplg_str=$(echo "$tplg_str" | sort -t';' -k1.4 -n -u)
if [ "$TPLG_COUNT" -gt 1 ]; then
    dlogi "Deduplicated and sorted pipelines from $TPLG_COUNT topology files"
else
    dlogi "Sorted pipelines by id"
fi

pcm_str=$(sof-dump-status.py -i "${SOFCARD:-0}")

dlogc "Processed $TPLG_COUNT topology file(s)"
dlogi "Pipeline(s) from topology file(s):"
echo "$tplg_str"
dlogc "sof-dump-status.py -i ${SOFCARD:-0}"
dlogi "Pipeline(s) from system:"
echo "$pcm_str"

if [[ "$tplg_str" != "$pcm_str" ]]; then
    dloge "Pipeline(s) from topology don't match pipeline(s) from system"
    dlogi "Dump aplay -l"
    aplay -l
    dlogi "Dump arecord -l"
    arecord -l
    sof-kernel-dump.sh > "$LOG_ROOT"/kernel.txt
    exit 1
else
    dlogi "Pipeline(s) from topology match pipeline(s) from system"
fi
exit 0
