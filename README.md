# eggd_cgp-purple

[PURPLE](https://github.com/hartwigmedical/hmftools/tree/master/purple) (Hartwig Medical Foundation, v4.4-beta.12) tumour-only purity/ploidy and copy-number fitter,
packaged as a DNAnexus app for the [`eggd_atlas_cnv`](https://github.com/eastgenomics/eggd_atlas_cnv)
somatic CNV workflow. Extended beyond the legacy app with a **max-ploidy cap** and **typed scalar
outputs** so downstream CNVkit can be fed purity/ploidy directly.

## Inputs

All reference files must be **GRCh38**. Note the chr-prefix convention per input: `gc_profile` uses
chr-prefixed contigs; `target_regions_bed` and `ref_fasta` use non-chr contigs.

| Input | Type | Required | Description |
|---|---|---|---|
| `sample_id` | `string` | Yes | Sample identifier (alphanumeric, `.`, `_`, `-`) |
| `purple_jar` | `file` | Yes | PURPLE JAR |
| `amber_tar` | `file` | Yes | AMBER output tar (`.amber.tar.gz`) |
| `cobalt_tar` | `file` | Yes | COBALT output tar (`.cobalt.tar.gz`) |
| `somatic_vcf` | `file` | No | SAGE somatic VCF (`.vcf.gz`) — improves purity anchoring; must be paired with `somatic_vcf_tbi` |
| `somatic_vcf_tbi` | `file` | No | Index for `somatic_vcf` (`.tbi`); must be paired with `somatic_vcf` |
| `gc_profile` | `file` | Yes | GC profile (`GC_profile.1000bp.38.cnp`) — chr-prefixed GRCh38 |
| `target_regions_bed` | `file` | Yes | Target regions BED — non-chr GRCh38 |
| `ref_fasta` | `file` | Yes | Reference FASTA (`.fasta.gz`) — non-chr GRCh38 |
| `ref_fai` | `file` | Yes | Reference FASTA index (`.fasta.gz.fai`) |
| `ensembl_data` | `file` | Yes | Ensembl data archive (`ensembl_data.tar.gz`) — GRCh38 |
| `max_ploidy` | `int` | No | Hard `-max_ploidy` cap. Mutually exclusive with `ploidy_cap_purity_threshold`. |
| `ploidy_cap_purity_threshold` | `float` | No | Run unbounded first; re-run with `-max_ploidy ploidy_cap_value` if fitted purity < threshold. Mutually exclusive with `max_ploidy`. |
| `ploidy_cap_value` | `int` | No | The `-max_ploidy` applied in the conditional re-run (default: `2`). |

## Outputs

- `purple_tar` — `file` — PURPLE output directory (`.purple.tar.gz`); includes AMBER BAF for the downstream IGV plotter
- `purity_tsv` — `file` — `*.purple.purity.tsv` — purity/ploidy summary
- `purity_range_tsv` — `file` — `*.purple.purity.range.tsv` — purity landscape
- `plots_tar` — `file` *(optional)* — PURPLE chart PNGs (`.tar.gz`)
- `cnv_somatic_tsv` — `file` — `*.purple.cnv.somatic.tsv` — segment-level CN calls
- `cnv_gene_tsv` — `file` — `*.purple.cnv.gene.tsv` — gene-level CN calls
- `purity` — `float` — Fitted purity (final pass)
- `ploidy` — `int` — Rounded ploidy, minimum 1 (final pass)
- `sample_sex` — `string` — `male` / `female` / `unknown`

## Ploidy cap
`max_ploidy` = hard `-max_ploidy`. `ploidy_cap_purity_threshold` = run unbounded, then re-run once
with `-max_ploidy ploidy_cap_value` (default 2) if fitted purity < threshold. Mutually exclusive;
decided by the bundled `atlas/ploidy_gate.py`.
