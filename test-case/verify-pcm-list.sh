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
IFS=':' read -ra tplg_array <<< "$tplg"

# Validate and collect accessible topologies
valid_tplg_list=()
for single_tplg in "${tplg_array[@]}"; do
    single_tplg="${single_tplg## }"  # Trim leading space
    single_tplg="${single_tplg%% }"  # Trim trailing space
    [[ -z "$single_tplg" ]] && continue
    
    tplg_path=$(func_lib_get_tplg_path "$single_tplg") && \
        valid_tplg_list+=("$tplg_path") || \
        dlogw "Topology not found: $single_tplg (skipping)"
done

[ ${#valid_tplg_list[@]} -eq 0 ] && die "No available topology for this test case"

# Join topologies with comma for sof-tplgreader.py
tplg_files=$(IFS=,; echo "${valid_tplg_list[*]}")

dlogi "Processing ${#valid_tplg_list[@]} topology file(s): ${valid_tplg_list[*]}"

setup_kernel_check_point

# sof-tplgreader.py handles multiple files natively
tplg_str=$(sof-tplgreader.py "$tplg_files" -d id pcm type -o)

# Deduplicate pipelines when using multiple topologies
# Same pipeline (id + pcm + type) can appear in multiple topology files
if [ ${#valid_tplg_list[@]} -gt 1 ]; then
    tplg_str=$(echo "$tplg_str" | sort -u)
    dlogi "Deduplicated pipelines from ${#valid_tplg_list[@]} topology files"
fi

pcm_str=$(sof-dump-status.py -i "${SOFCARD:-0}")

dlogc "Processed ${#valid_tplg_list[@]} topology file(s): ${valid_tplg_list[*]}"
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
