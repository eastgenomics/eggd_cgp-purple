# eggd_cgp-purple

PURPLE (Hartwig Medical Foundation, v4.4-beta.12) tumour-only purity/ploidy and copy-number fitter,
packaged as a DNAnexus app for the [`eggd_atlas_cnv`](https://github.com/eastgenomics/eggd_atlas_cnv)
somatic CNV workflow. Extended beyond the legacy applet with a **max-ploidy cap** and **typed scalar
outputs** so downstream CNVkit can be fed purity/ploidy directly.

## Inputs (summary)
`sample_id`, `purple_jar`, `amber_tar`, `cobalt_tar`, `somatic_vcf`(+tbi, optional), `gc_profile`,
`target_regions_bed`, `ref_fasta`/`ref_fai`, `ensembl_data`, and the ploidy-cap controls
`max_ploidy` | `ploidy_cap_purity_threshold` (+ `ploidy_cap_value`).

## Outputs
`purple_tar`, `purity_tsv`, `purity_range_tsv`, `plots_tar`, `cnv_somatic_tsv`, `cnv_gene_tsv`, and
scalars `purity` (float), `ploidy` (int), `sample_sex` (string).

## Ploidy cap
`max_ploidy` = hard `-max_ploidy`. `ploidy_cap_purity_threshold` = run unbounded, then re-run once
with `-max_ploidy ploidy_cap_value` (default 2) if fitted purity < threshold. Mutually exclusive;
decided by the bundled `atlas/ploidy_gate.py`.

## Notes
- Instance `mem2_ssd1_v2_x4`; timeout 6 h. Deps via `execDepends` (java, samtools, tabix, jq, R, circos).
- `purple_tar` bundles the AMBER BAF for the downstream IGV plotter.
