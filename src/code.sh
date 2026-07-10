#!/bin/bash
# eggd_cgp-purple v1.0.0 — PURPLE 4.4-beta.12 tumour-only purity/ploidy/CN
# Extended from cgp-purple app with:
#   - optional max-ploidy cap (STATIC / CONDITIONAL two-pass, via bundled ploidy_gate.py)
#   - typed scalar outputs purity(float)/ploidy(int)/sample_sex(string) for stage linking
#   - standalone cnv_somatic_tsv / cnv_gene_tsv file outputs (were only inside purple_tar)
# PURPLE tool flags are FROZEN; the only added flag is -max_ploidy from the cap decision.
set -euxo pipefail

ATLAS=/home/dnanexus/atlas

# ── verify_deps: confirm execDepends are present ─────────────────────────────
verify_deps() {
    echo "[setup] Verifying deps (execDepends: java/samtools/tabix/jq/R/circos)..."
    java     -version  2>&1 | sed -n '1p'
    samtools --version 2>&1 | sed -n '1p'
    bgzip    --version 2>&1 | sed -n '1p'
    jq       --version 2>&1 | sed -n '1p'
    python3  --version 2>&1 | sed -n '1p'
    Rscript  --version 2>&1 | sed -n '1p'
    circos   --version 2>&1 | sed -n '1p' || echo "circos: $(which circos 2>/dev/null || echo not found)"
}

# ── download_inputs: parallel dx download with pid check ─────────────────────
download_inputs() {
    echo "[1/7] Downloading inputs..."
    local pids=()

    dx download "${purple_jar}"          -o purple.jar                & pids+=($!)
    dx download "${amber_tar}"           -o amber.tar.gz              & pids+=($!)
    dx download "${cobalt_tar}"          -o cobalt.tar.gz             & pids+=($!)
    dx download "${gc_profile}"          -o GC_profile.1000bp.38.cnp  & pids+=($!)
    dx download "${target_regions_bed}"  -o target_regions.bed        & pids+=($!)
    dx download "${ref_fasta}"           -o ref.fasta.gz              & pids+=($!)
    dx download "${ref_fai}"             -o ref.fasta.gz.fai          & pids+=($!)
    dx download "${ensembl_data}"        -o ensembl_data.tar.gz       & pids+=($!)

    SOMATIC_ARG=""
    if [[ -n "${somatic_vcf:-}" ]]; then
        dx download "${somatic_vcf}"     -o somatic.vcf.gz     & pids+=($!)
        dx download "${somatic_vcf_tbi}" -o somatic.vcf.gz.tbi & pids+=($!)
        SOMATIC_ARG="-somatic_vcf somatic.vcf.gz"
        echo "  Somatic VCF provided — will anchor purity"
    fi

    for pid in "${pids[@]}"; do wait "$pid"; done
    echo "  All downloads complete."
}

# ── prepare_inputs: unpack tars, decompress ref, locate AMBER/COBALT/ensembl dirs ──
prepare_inputs() {
    echo "[2/7] Preparing inputs..."
    tar --no-same-owner -xzf amber.tar.gz
    tar --no-same-owner -xzf cobalt.tar.gz

    AMBER_DIR=$(find . -maxdepth 2 -name "*.amber.baf.tsv.gz" -printf "%h\n" | head -1)
    COBALT_DIR=$(find . -maxdepth 2 -name "*.cobalt.ratio.tsv.gz" -printf "%h\n" | head -1)
    [[ -n "${AMBER_DIR}"  ]] || { echo "ERROR: AMBER dir not found in tar"  >&2; exit 1; }
    [[ -n "${COBALT_DIR}" ]] || { echo "ERROR: COBALT dir not found in tar" >&2; exit 1; }
    # Guard: AMBER/COBALT dirs must be a proper subdirectory — if they resolve to '.' the
    # later 'tar ${AMBER_DIR}/' would bundle the entire working directory into purple_tar.
    [[ "${AMBER_DIR}"  == "." ]] && { echo "ERROR: AMBER baf found at working-dir root — unexpected tar layout; expected a named subdirectory" >&2; exit 1; }
    [[ "${COBALT_DIR}" == "." ]] && { echo "ERROR: COBALT ratio found at working-dir root — unexpected tar layout" >&2; exit 1; }
    echo "  AMBER dir:  ${AMBER_DIR}"
    echo "  COBALT dir: ${COBALT_DIR}"

    echo "Decompressing reference FASTA..."
    bgzip -d -c ref.fasta.gz > ref.fasta
    samtools faidx ref.fasta

    tar --no-same-owner -xzf ensembl_data.tar.gz
    ENSEMBL_DIR=$(find . -maxdepth 2 -name "ensembl_gene_data.csv" -printf "%h\n" | head -1)
    [[ -n "${ENSEMBL_DIR}" ]] || { echo "ERROR: ensembl_gene_data.csv not found" >&2; exit 1; }
    echo "  Ensembl dir: ${ENSEMBL_DIR}"
}

# ── resolve_ploidy_cap: call ploidy_gate.decide() and export shell vars ───────
# Sets FIRST_ARGS_JSON, FIRST_ARGS (array), CONDITIONAL (yes|no), MODE (none|static|conditional).
#
# Python is used here — not merely to read $max_ploidy — but to run decide(), which:
#   1. validates mutual exclusivity of max_ploidy / ploidy_cap_purity_threshold,
#   2. selects the cap mode (NONE / STATIC / CONDITIONAL),
#   3. builds the PURPLE first-pass arg list as a JSON array.
# This logic is unit-tested in tests/test_ploidy_gate.py; keeping it in Python
# means the tests cover the same code that runs in production.
#
# CONDITIONAL is a field on the PloidyDecision dataclass returned by decide():
# True when ploidy_cap_purity_threshold is supplied (CONDITIONAL mode), False otherwise.
# It is printed as "CONDITIONAL=yes|no" and captured into the shell via eval.
resolve_ploidy_cap() {
    echo "[3/7] Resolving ploidy-cap decision..."
    local eval_output
    eval_output=$(
        max_ploidy="${max_ploidy:-}" \
        ploidy_cap_purity_threshold="${ploidy_cap_purity_threshold:-}" \
        ploidy_cap_value="${ploidy_cap_value:-2}" \
        python3 - "$ATLAS" <<'PY'
import sys, os, json
sys.path.insert(0, sys.argv[1])
from ploidy_gate import decide
d = decide(
    max_ploidy=(int(os.environ["max_ploidy"]) if os.environ.get("max_ploidy") else None),
    threshold=(float(os.environ["ploidy_cap_purity_threshold"]) if os.environ.get("ploidy_cap_purity_threshold") else None),
    cap_value=int(os.environ.get("ploidy_cap_value", "2")),
)
print("FIRST_ARGS_JSON=" + json.dumps(json.dumps(d.first_pass_args)))  # quoted JSON string
print("CONDITIONAL=" + ("yes" if d.conditional else "no"))
print("MODE=" + d.mode.value)
PY
    )
    eval "$eval_output"
    echo "  mode=${MODE}  conditional=${CONDITIONAL}  first_pass_args=${FIRST_ARGS_JSON}"
    mapfile -t FIRST_ARGS < <(jq -r '.[]' <<<"$FIRST_ARGS_JSON")
}

# ── run_purple: single PURPLE invocation; "$@" = extra args (may be empty) ───
# JVM heap is derived from available RAM, leaving ~2 GiB headroom for the OS.
run_purple() {
    local heap_mb
    heap_mb=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1024 - 2048 ))
    (( heap_mb >= 1024 )) || heap_mb=1024

    java -Xmx${heap_mb}m -jar purple.jar \
        -tumor              "${sample_id}" \
        -amber              "${AMBER_DIR}" \
        -cobalt             "${COBALT_DIR}" \
        -target_regions_bed target_regions.bed \
        -gc_profile         GC_profile.1000bp.38.cnp \
        -ensembl_data_dir   "${ENSEMBL_DIR}" \
        -ref_genome         ref.fasta \
        -ref_genome_version 38 \
        ${SOMATIC_ARG} \
        "$@" \
        -output_dir         "${WORK}/"
}

# ── run_purple_passes: first pass (±cap args) + optional conditional second pass ──
run_purple_passes() {
    WORK="purple_out"       # PURPLE output dir; kept separate from the amber/cobalt extract dirs
                            # so the conditional rm -rf never deletes AMBER/COBALT inputs.
    PTSV="${WORK}/${sample_id}.purple.purity.tsv"
    RANGE_TSV="${WORK}/${sample_id}.purple.purity.range.tsv"

    echo "[4/7] Running PURPLE (pass 1)..."
    rm -rf "${WORK}"; mkdir -p "${WORK}"
    run_purple "${FIRST_ARGS[@]}"
    [[ -s "${PTSV}" ]]      || { echo "ERROR: PURPLE purity TSV missing after pass 1" >&2; exit 1; }
    [[ -s "${RANGE_TSV}" ]] || { echo "ERROR: PURPLE range TSV missing after pass 1"  >&2; exit 1; }

    if [ "$CONDITIONAL" = "yes" ]; then
        local purity need
        purity=$(python3 -c "import sys;sys.path.insert(0,'$ATLAS');from purity import read_purity_ploidy as r;print(r('$PTSV').purity)")
        need=$(python3 -c "print('yes' if float('$purity') < float('${ploidy_cap_purity_threshold:-}') else 'no')")
        echo "  pass-1 purity=${purity} threshold=${ploidy_cap_purity_threshold:-} -> rerun=${need}"
        if [ "$need" = "yes" ]; then
            echo "[4b/7] Purity below threshold — re-running PURPLE with -max_ploidy ${ploidy_cap_value:-2} (pass 2)..."
            rm -rf "${WORK}"; mkdir -p "${WORK}"
            run_purple -max_ploidy "${ploidy_cap_value:-2}"
            [[ -s "${PTSV}" ]]      || { echo "ERROR: PURPLE purity TSV missing after pass 2"       >&2; exit 1; }
            [[ -s "${RANGE_TSV}" ]] || { echo "ERROR: PURPLE purity range TSV missing after pass 2" >&2; exit 1; }
        fi
    fi
}

# ── parse_scalars: read final purity.tsv → FPUR, FPLO, FSEX ──────────────────
parse_scalars() {
    echo "[5/7] Final purity result:"
    cat "${PTSV}"
    ls -lh "${WORK}/"

    local scalars_json
    scalars_json=$(python3 - "$ATLAS" "$PTSV" <<'PY'
import sys, json
sys.path.insert(0, sys.argv[1])
from purity import read_purity_ploidy
f = read_purity_ploidy(sys.argv[2])
sex = f.sample_sex if f.sample_sex in ("male", "female") else "unknown"
print(json.dumps({"purity": f.purity, "ploidy": f.ploidy_int(), "sex": sex}))
PY
)
    FPUR=$(jq -r '.purity' <<<"$scalars_json")
    FPLO=$(jq -r '.ploidy' <<<"$scalars_json")
    FSEX=$(jq -r '.sex'    <<<"$scalars_json")
    echo "  emitting purity=${FPUR} ploidy=${FPLO} sample_sex=${FSEX}"
}

# ── collect_charts: bundle PURPLE chart PNGs (non-fatal if absent) ────────────
collect_charts() {
    mapfile -t -d '' PLOT_FILES < <(find "${WORK}/" -name "*.png" -print0 2>/dev/null)
    if [ "${#PLOT_FILES[@]}" -gt 0 ]; then
        tar --no-same-owner -czf "${sample_id}.purple.plots.tar.gz" "${PLOT_FILES[@]}"
        HAVE_PLOTS=true
    else
        echo "  No chart PNGs generated (non-fatal)"
        HAVE_PLOTS=false
    fi
}

# ── upload_outputs: dx upload all outputs and emit job-util bindings ──────────
upload_outputs() {
    echo "[6/7] Uploading..."
    # purple_tar bundles AMBER BAF for the downstream IGV plotter:
    # copy PURPLE outputs into the AMBER extract dir, which already holds *.amber.baf.tsv.gz.
    cp -a "${WORK}/." "${AMBER_DIR}/"
    tar --no-same-owner -czf "${sample_id}.purple.tar.gz" "${AMBER_DIR}/"

    dx-jobutil-add-output purple_tar       "$(dx upload "${sample_id}.purple.tar.gz" --brief)" --class=file
    dx-jobutil-add-output purity_tsv       "$(dx upload "${PTSV}"      --brief)"               --class=file
    dx-jobutil-add-output purity_range_tsv "$(dx upload "${RANGE_TSV}" --brief)"               --class=file
    if [ "${HAVE_PLOTS}" = "true" ]; then
        dx-jobutil-add-output plots_tar "$(dx upload "${sample_id}.purple.plots.tar.gz" --brief)" --class=file
    fi

    # Standalone CNV call TSVs — always exist (header-only fallback if PURPLE omitted them).
    # Headers below match PURPLE 4.4's *.purple.cnv.somatic.tsv / *.purple.cnv.gene.tsv columns.
    local CNV_SOMATIC="${WORK}/${sample_id}.purple.cnv.somatic.tsv"
    local CNV_GENE="${WORK}/${sample_id}.purple.cnv.gene.tsv"
    [ -f "${CNV_SOMATIC}" ] || printf 'chromosome\tstart\tend\tcopyNumber\tbafCount\tobservedBAF\tbaf\tsegmentStartSupport\tsegmentEndSupport\tmethod\tdepthWindowCount\tgcContent\tminStart\tmaxStart\tminorAlleleCopyNumber\tmajorAlleleCopyNumber\n' > "${CNV_SOMATIC}"
    [ -f "${CNV_GENE}" ]    || printf 'chromosome\tstart\tend\tgene\tminCopyNumber\tmaxCopyNumber\tsomaticRegions\ttranscriptId\tisCanonical\tchromosomeBand\tminRegions\tminRegionStart\tminRegionEnd\tminRegionStartSupport\tminRegionEndSupport\tminRegionMethod\tminMinorAlleleCopyNumber\tdepthWindowCount\n' > "${CNV_GENE}"
    dx-jobutil-add-output cnv_somatic_tsv "$(dx upload "${CNV_SOMATIC}" --brief)" --class=file
    dx-jobutil-add-output cnv_gene_tsv    "$(dx upload "${CNV_GENE}"    --brief)" --class=file

    # Typed scalar outputs (the only way purity/ploidy/sex reach downstream stages).
    dx-jobutil-add-output purity     "${FPUR}" --class=float
    dx-jobutil-add-output ploidy     "${FPLO}" --class=int
    dx-jobutil-add-output sample_sex "${FSEX}" --class=string
}

main() {
    echo "====================================================="
    echo " eggd_cgp-purple: PURPLE purity/ploidy/CN"
    echo " Sample  : ${sample_id}"
    echo "====================================================="

    # ── Pre-flight checks ────────────────────────────────────────────────────
    case "${sample_id}" in
        *[!A-Za-z0-9._-]* | "" | .* | -* ) echo "ERROR: unsafe sample_id '${sample_id}'" >&2; exit 1 ;;
    esac

    if { [[ -n "${somatic_vcf:-}" ]] && [[ -z "${somatic_vcf_tbi:-}" ]]; } || \
       { [[ -z "${somatic_vcf:-}" ]] && [[ -n "${somatic_vcf_tbi:-}" ]]; }; then
        echo "ERROR: somatic_vcf and somatic_vcf_tbi must be supplied together (or neither)" >&2; exit 1
    fi

    verify_deps
    download_inputs
    prepare_inputs
    resolve_ploidy_cap
    run_purple_passes
    parse_scalars
    collect_charts
    upload_outputs

    echo "[7/7] Done."
    echo "====================================================="
    echo " eggd_cgp-purple DONE: ${sample_id}"
    echo "   purity=${FPUR}  ploidy=${FPLO}  sample_sex=${FSEX}"
    echo "====================================================="
}
