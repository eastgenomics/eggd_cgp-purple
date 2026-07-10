# Changelog

## 1.0.0
Initial app release. Converted **and extended** from the `cnv-backbone-purple-atlas` `cgp-purple`
**applet** into a versioned, namespaced DNAnexus **app** (`org-emee_1`, `aws:eu-central-1`) for the
`eggd_atlas_cnv` somatic CNV workflow.

Extensions beyond a straight conversion:
- **Max-ploidy cap.** New optional inputs `max_ploidy` (static `-max_ploidy`) OR
  `ploidy_cap_purity_threshold` (+ `ploidy_cap_value`, default 2). CONDITIONAL mode runs PURPLE
  unbounded, reads the fitted purity, and re-runs **once** with `-max_ploidy ploidy_cap_value` if
  purity < threshold. The two inputs are mutually exclusive. Decision logic is the bundled,
  unit-tested pure-Python helper `atlas/ploidy_gate.py` (+ `atlas/purity.py`).
- **Typed scalar outputs** `purity` (float), `ploidy` (int, rounded ≥1), `sample_sex` (string) for
  direct stage-linking into CNVkit (a native workflow cannot parse a scalar out of a file).
- **Standalone CN-call outputs** `cnv_somatic_tsv` / `cnv_gene_tsv` (previously only inside
  `purple_tar`), with a header-only fallback so they always exist.
- Explicit `timeoutPolicy` (6 h); `jq` added to `execDepends`.

Bug fixes made during eggd_atlas_cnv end-to-end validation:
- PURPLE output directory set to `purple_out` (distinct from the AMBER/COBALT extract dir) so the
  two-pass re-run's `rm -rf` never deletes the inputs.
- `purple_tar` now bundles the AMBER BAF (`cp` PURPLE outputs into the AMBER extract dir before
  tarring) — the IGV plotter reads `*.amber.baf.tsv.gz` from the tar.
