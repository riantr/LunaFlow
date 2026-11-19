# LunaFlow analysis report — riantr/moonbit_doubleML@0.164.64

> Trace-driven (dynamic-first) control-flow, data-flow, value-range and slicing analysis for a mooncakes.io module.

## 1. Acquisition and version pinning

| Item | Value |
| --- | --- |
| Requested coordinate | `riantr/moonbit_doubleML@latest` |
| Resolved version | `0.164.64` |
| Pinning strategy | `@latest` resolved through `moon fetch` (local registry index, newest non-yanked version) and pinned to `0.164.64` for ingestion, execution and reporting |
| Source root | `./.repos/riantr/moonbit_doubleML/0.164.64` |
| Declared target | `wasm-gc` |
| Direct dependencies | moonbit-community/sqlite3@0.2.4, moonbitlang/async@0.22.7 |

## 2. Ingestion statistics

| Metric | Value |
| --- | --- |
| Source files parsed | 220 |
| Functions extracted | 2529 |
| Statements understood | 30258 |
| Statements unsupported | 281 |
| Frontend coverage | 99.0% |
| Parse issues | 0 |
| CFG functions | 600 of 2529 — the first 600 in file order; 1929 functions had no CFG and can carry no CFG finding |
| Trace events | 448001 |
| Interpreted steps | 48306 |
| Observed functions | 150 |
| Entry selection | the first 150 functions in file order (the `--max-functions` cap applies) |
| Wall time (analyzer) | 12615 ms |
| Selected level | L3 (funnel: L1 → L2 → L3) |

## 3. Proof-strength levels and funnel

The same program is analyzed at three proof strengths. Levels are cumulative: L2 adds abstract interpretation on top of L1, L3 adds contract verification on top of the escalated functions. `--funnel` runs all three and reports what each level adds.

### 3.1 Level definitions

| Level | Name | Engine | Input model | Result strength |
| --- | --- | --- | --- | --- |
| L1 | Interpreter | concrete execution on the formal interpreter | concrete boundary values (`--trials`) | observed facts; may miss unexecuted inputs and paths |
| L2 | Value | abstract interpretation over a value-set / interval domain | whole input sets (`Int` intervals, `Bool`/`String` sets, array length intervals) | exhaustive over the abstract state; may-taint and may-range alarms (false positives possible) |
| L3 | Proof-by-contract | WP-style weakest-precondition VC generation + interval decision | ACSL-style `//@ requires` / `//@ ensures` specs | `proved` / `failed` / `unknown` per verification condition; specs are mandatory |

### 3.2 Funnel

```mermaid
flowchart LR
  classDef l1 fill:#dcedc8,stroke:#33691e
  classDef l2 fill:#fff9c4,stroke:#f9a825
  classDef l3 fill:#e1bee7,stroke:#6a1b9a
  L1["L1 concrete: 245 findings"]:::l1
  L2["L2 abstract: 3316 findings, 3225 new"]:::l2
  L3["L3 contracts: 0 proved / 0 failed / 0 unknown"]:::l3
  L1 -->|"dedup, escalate"| L2
  L2 -->|"critical functions"| L3
```

| Level | Checks | New vs previous | Functions / VCs | Note |
| --- | --- | --- | --- | --- |
| L1 concrete | 245 findings | — | 150 functions | observed facts |
| L2 abstract | 3316 findings | 3225 | 1411 functions, 167271 steps | exhaustive over the input abstraction |
| L3 contracts | 0 VCs | 0 failed, 0 unknown | 682 critical functions | specs required |

### 3.3 Escalation and specification gaps

Escalated functions (have at least one L1/L2 finding or a contract): `indicator_level`, `cross_fit_apo`, `clip_vec`, `normalize_ipw`, `slice_matrix_rows`, `unique_units`, `build_row_unit_map`, `DoubleMLAPO::fit_cluster`, `kfold`, `psi_at`, `cluster_sandwich_variance`, `draw_bootstrap_weights`, `DoubleMLAPO::sensitivity_nu2_elements`, `DoubleMLAPO::sensitivity_analysis`, `irm_style_sensitivity_from_elements`, `compute_sensitivity_bias`, `DoubleMLAPO::sensitivity_analysis_cluster`, `irm_style_sensitivity_cluster_from_elements`, `DoubleMLAPOS::psi_b_row_at`, `DoubleMLAPOS::psi_a_row_at`, `DoubleMLAPOS::sandwich_se_at`, `DoubleMLAPOS::cluster_sandwich_se_at`, `DoubleMLAPOS::bias_corrected_coef_at`, `DoubleMLAPOS::bootstrap`, `DoubleMLAPOS::confint`, `DoubleMLAPOS::causal_contrast`, `DoubleMLAPOS::sensitivity_analysis`, `DoubleMLAPOS::sensitivity_analysis_cluster`, `check_sample_splitting`, `DoubleMLDIDData::new`, `cross_fit_did`, `DoubleMLDID::fit`, `generic_bootstrap_t_stat`, `DoubleMLDID::sensitivity_nu2_elements`, `DoubleMLDID::sensitivity_analysis`, `DoubleMLDID::sensitivity_analysis_cluster`, `GBLearner::fit_weighted`, `predict`, `filter_indices`, `cross_fit_irm`, `DoubleMLIRM::fit_cluster`, `DoubleMLIRM::sensitivity_nu2_elements`, `vector_subtract`, `DoubleMLIRM::sensitivity_analysis`, `DoubleMLIRM::sensitivity_analysis_cluster`, `mean`, `sample_sd`, `percentile_sorted`, `lpq_score`, `lpq_score_ipw`, `generic_bootstrap_single_psi`, `single_psi_sensitivity`, `DoubleMLLPQ::sensitivity_analysis_cluster`, `irm_style_sensitivity_cluster`, `aggregate_coef_se`, `DoubleMLAPO::new`, `DoubleMLAPO::coef`, `DoubleMLAPO::se`, `DoubleMLAPO::confint`, `DoubleMLAPO::predictions_g`, `DoubleMLAPO::predictions_m`, `DoubleMLAPO::fit`, `DoubleMLAPO::sandwich_se`, `DoubleMLAPO::cluster_sandwich_se`, `DoubleMLAPO::bias_corrected_coef`, `DoubleMLAPO::bootstrap`, `DoubleMLAPO::tune`, `DoubleMLAPOS::tune`, `DoubleMLAPOS::new`, `DoubleMLAPOS::fit`, `DoubleMLAPOS::coefs`, `DoubleMLAPOS::ses`, `DoubleMLAPOS::m_inv_1x1_at`, `DoubleMLAPOS::boot_t_stats`, `DoubleMLDID::new`, `DoubleMLDID::coef`, `DoubleMLDID::se`, `DoubleMLDID::confint`, `DoubleMLDID::bootstrap`, `DoubleMLDID::sandwich_se`, `DoubleMLDID::cluster_sandwich_se`, `DoubleMLDID::bias_corrected_coef`, `DoubleMLDID::tune`, `DoubleMLIRM::new`, `DoubleMLIRM::coef`, `DoubleMLIRM::se`, `DoubleMLIRM::confint`, `DoubleMLIRM::fit`, `DoubleMLIRM::bootstrap`, `DoubleMLIRM::tune`, `DoubleMLIRM::sandwich_se`, `DoubleMLIRM::cluster_sandwich_se`, `DoubleMLIRM::bias_corrected_coef`, `silverman_bandwidth`, `gaussian_kde`, `gaussian_kde_weighted`, `DoubleMLLPQData::new`, `DoubleMLLPQ::new`, `DoubleMLLPQ::fit`, `DoubleMLLPQ::bootstrap`, `DoubleMLLPQ::sensitivity_analysis`, `DoubleMLLPQ::confint`, `DoubleMLLPQ::coef`, `DoubleMLLPQ::se`, `DoubleMLLPQ::predictions_g0`, `DoubleMLLPQ::predictions_g1`, `DoubleMLLPQ::predictions_m`, `DoubleMLLPQ::m_inv_1x1`, `DoubleMLLPQ::sandwich_se`, `DoubleMLLPQ::cluster_sandwich_se`, `DoubleMLLPQ::bias_corrected_coef`, `DoubleMLPLR::new`, `DoubleMLPLR::coef`, `DoubleMLPLR::se`, `DoubleMLPLR::confint`, `plr_score_elements`, `DoubleMLPLR::fit`, `DoubleMLPLR::fit_cluster`, `DoubleMLPLR::bootstrap`, `DoubleMLPLR::sensitivity_analysis`, `DoubleMLPLR::sensitivity_analysis_cluster`, `DoubleMLPLR::sandwich_se`, `DoubleMLPLR::cluster_sandwich_se`, `DoubleMLPLR::bias_corrected_coef`, `DoubleMLRDDData::new`, `DoubleMLRDD::new`, `weighted_xtx_transpose`, `DoubleMLRDD::fit`, `DoubleMLRDD::coef`, `DoubleMLRDD::se`, `DoubleMLRDD::confint`, `DoubleMLRDD::leverage`, `rdd_hac_require_df`, `DoubleMLRDD::hac_se`, `DoubleMLRDD::cluster_hac_se`, `DoubleMLRDD::sensitivity_analysis`, `DoubleMLRDD::sensitivity_analysis_cluster`, `DoubleMLRDD::bootstrap`, `DoubleMLRDD::tune`, `DoubleMLRDD::bias`, `DoubleMLRDD::tau_bc`, `DoubleMLRDD::tau_bc_collapsed`, `DoubleMLRDD::tau_bc_se`, `DoubleMLRDD::bandwidth_mse`, `DoubleMLRDD::bandwidth_variance_term`, `rdd_pilot_stage`, `rdd_nn_matched_sigma4`, `nn_residual`, `rdd_rb_side`, `DoubleMLRDD::tau_bc_se_rb`, `bootstrap_indices`, `cart_fit`, `cart_leaf_value`, `RFLearner::fit_weighted`, `DoubleMLSSMData::new`, `DoubleMLSSM::new`, `DoubleMLSSM::coef`, `DoubleMLSSM::se`, `DoubleMLSSM::confint`, `DoubleMLSSM::bootstrap`, `DoubleMLSSM::tune`, `DoubleMLSSM::psi_a`, `DoubleMLSSM::psi_b`, `DoubleMLSSM::sensitivity_analysis`, `DoubleMLSSM::sensitivity_analysis_cluster`, `augment_one_col`, `filter_two_values`, `cross_fit_ssm`, `DoubleMLSSM::fit`, `DoubleMLSSM::sandwich_se`, `DoubleMLSSM::cluster_sandwich_se`, `DoubleMLSSM::bias_corrected_coef`, `DoubleMLCVAR::new`, `DoubleMLCVAR::coef`, `DoubleMLCVAR::se`, `DoubleMLCVAR::confint`, `DoubleMLCVAR::predictions_g`, `DoubleMLCVAR::predictions_m`, `DoubleMLCVAR::sensitivity_analysis`, `DoubleMLCVAR::sensitivity_analysis_cluster`, `stratified_half_split`, `cvar_ipw_score`, `solve_ipw_root`, `cvar_inner_crossfit`, `DoubleMLCVAR::fit`, `DoubleMLCVAR::tune`, `DoubleMLCVAR::bootstrap`, `DoubleMLCVAR::sandwich_se`, `DoubleMLCVAR::cluster_sandwich_se`, `DoubleMLCVAR::bias_corrected_coef`, `DoubleMLData::new`, `DoubleMLIIVMData::new`, `DoubleMLIIVM::new`, `DoubleMLIIVM::coef`, `DoubleMLIIVM::se`, `DoubleMLIIVM::confint`, `filter_by_value`, `cross_fit_iivm`, `DoubleMLIIVM::fit`, `DoubleMLIIVM::fit_cluster`, `DoubleMLIIVM::bootstrap`, `DoubleMLIIVM::tune`, `DoubleMLIIVM::sensitivity_analysis`, `DoubleMLIIVM::sensitivity_analysis_cluster`, `DoubleMLIIVM::sandwich_se`, `DoubleMLIIVM::cluster_sandwich_se`, `DoubleMLIIVM::bias_corrected_coef`, `DoubleMLBinaryData::new`, `prelim_beta_per_fold`, `lplr_score_at`, `newton_solve_score`, `DoubleMLLPLR::new`, `DoubleMLLPLR::coef`, `DoubleMLLPLR::se`, `DoubleMLLPLR::confint`, `DoubleMLLPLR::predictions_t`, `DoubleMLLPLR::predictions_m`, `DoubleMLLPLR::predictions_a`, `concat_d_x`, `DoubleMLLPLR::fit`, `DoubleMLLPLR::bootstrap`, `DoubleMLLPLR::tune`, `cross_fit_predict_inner`, `DoubleMLLPLR::sensitivity_analysis`, `DoubleMLLPLR::sensitivity_analysis_cluster`, `DoubleMLLPLR::sandwich_se`, `DoubleMLLPLR::cluster_sandwich_se`, `DoubleMLLPLR::bias_corrected_coef`, `DoubleMLPLIVData::new`, `DoubleMLPLIV::new`, `DoubleMLPLIV::coef`, `DoubleMLPLIV::se`, `DoubleMLPLIV::confint`, `DoubleMLPLIV::fit`, `DoubleMLPLIV::fit_cluster`, `DoubleMLPLIV::bootstrap`, `DoubleMLPLIV::tune`, `DoubleMLPLIV::sensitivity_analysis`, `DoubleMLPLIV::sensitivity_analysis_cluster`, `DoubleMLPLIV::sandwich_se`, `DoubleMLPLIV::cluster_sandwich_se`, `DoubleMLPLIV::bias_corrected_coef`, `DoubleMLPanelData::new`, `sort_rows_by_id_time`, `unit_means`, `est_coef_cluster`, `var_est_cluster`, `transform_panel`, `DoubleMLPLPR::new`, `DoubleMLPLPR::coef`, `DoubleMLPLPR::se`, `DoubleMLPLPR::confint`, `DoubleMLPLPR::predictions_l`, `DoubleMLPLPR::predictions_m`, `DoubleMLPLPR::sensitivity_analysis`, `DoubleMLPLPR::fit`, `DoubleMLPLPR::bootstrap`, `DoubleMLPLPR::tune`, `DoubleMLPLPR::sensitivity_analysis_cluster`, `DoubleMLPLPR::sandwich_se`, `DoubleMLPLPR::cluster_sandwich_se`, `DoubleMLPLPR::bias_corrected_coef`, `tune_score_outcome`, `tune_argmin`, `tune_score_grid`, `DoubleMLPLR::tune`, `GBClassifier::fit_weighted`, `kahan_sum`, `Fold::new`, `kfold_stratified`, `slice_vector`, `expand_unit_folds_to_rows`, `cluster_causal_param_and_se`, `cross_fit_predict`, `double_cross_fit_predict`, `RFClassifier::fit_weighted`, `DoubleMLDIDCSData::new`, `discover_groups_times`, `DoubleMLDIDCS::new`, `DoubleMLDIDCS::coef_at`, `DoubleMLDIDCS::se_at`, `DoubleMLDIDCS::group_at`, `DoubleMLDIDCS::period_at`, `DoubleMLDIDCS::cell_flat_at`, `DoubleMLDIDCS::cell_psi_a_row_at`, `DoubleMLDIDCS::cell_psi_b_row_at`, `DoubleMLDIDCS::m_inv_1x1_at`, `DoubleMLDIDCS::sandwich_se_at`, `DoubleMLDIDCS::cluster_sandwich_se_at`, `DoubleMLDIDCS::fit`, `DoubleMLDIDCS::bootstrap`, `DoubleMLDIDCS::sensitivity_analysis`, `DoubleMLDIDCS::confint`, `DoubleMLDIDCS::sensitivity_analysis_cluster`, `DoubleMLDIDCS::tune`, `cholesky`, `solve_spd`, `add_ridge`, `inv_spd`, `LinearRegression::coefficients`, `LinearRegression::fit`, `LinearRegression::xtwx_inv_diag`, `LinearRegression::covariance_diagonal`, `LinearRegression::fit_weighted`, `LinearRegression::predict`, `LinearRegression::sandwich_se_weighted`, `LinearRegression::sandwich_se`, `Matrix::zeros`, `Matrix::ones`, `Matrix::from_array`, `Matrix::copy`, `Matrix::from_rows`, `matmul`, `matvec`, `matvec_t`, `dot`, `make_irm_data`, `make_ssm_data`, `gather_rows`, `cross_fit_predict_conditional_dispatch`, `var_est`, `var_est_with_jacobian`, `count_eq`, `make_iivm_data`, `make_lplr_LZZ2020`, `make_pliv_CHS2015`, `make_plpr_CP2025`, `LogisticRegression::coefficients`, `LogisticRegression::fit`, `LogisticRegression::predict`, `LogisticRegression::predict_class`, `argsort_asc`, `romano_wolf_p_adjust`, `holm_bonferroni_p_adjust`, `bonferroni_p_adjust`, `bh_fdr_p_adjust`, `by_fdr_p_adjust`, `bh_step_up_sorted`, `tsbh_p_adjust`, `storey_m0_hat`, `tsby_p_adjust`, `array_min`, `array_max`, `outcome_indicator`, `cross_fit_conditional`, `pq_score_ipw`, `pq_score_orthogonal`, `fit_propensity`, `solve_pq`, `DoubleMLPQ::new`, `DoubleMLPQ::fit`, `DoubleMLPQ::fit_cluster`, `DoubleMLPQ::coef`, `DoubleMLPQ::se`, `DoubleMLPQ::confint`, `DoubleMLPQ::bootstrap`, `DoubleMLPQ::sensitivity_analysis`, `DoubleMLPQ::sensitivity_analysis_cluster`, `DoubleMLPQ::m_inv_1x1`, `DoubleMLPQ::sandwich_se`, `DoubleMLPQ::cluster_sandwich_se`, `DoubleMLPQ::bias_corrected_coef`, `DoubleMLPQ::tune`, `DoubleMLQTE::fit`, `DoubleMLQTE::fit_cluster`, `DoubleMLQTE::confint`, `DoubleMLQTE::bootstrap`, `DoubleMLQTE::sensitivity_analysis`, `DoubleMLQTE::sensitivity_analysis_cluster`, `DoubleMLQTE::m_inv_1x1_at`, `DoubleMLQTE::psi_row`, `DoubleMLQTE::sandwich_se_at`, `DoubleMLQTE::cluster_sandwich_se_at`, `DoubleMLQTE::bias_corrected_coef_at`, `DoubleMLQTE::joint_covariance`, `DoubleMLQTE::cluster_joint_covariance`, `DoubleMLQTE::tune`, `sandwich_variance_hc0`, `sandwich_variance_hc1`, `sandwich_variance_hc2`, `sandwich_variance_hc3`, `bias_corrected_theta`, `did_bootstrap_t_stat`, `DoubleMLDIDMulti::new`, `expand_gt_keyword`, `DoubleMLDIDMulti::coef_at_idx`, `DoubleMLDIDMulti::se_at_idx`, `did_multi_inner_cell_at_idx`, `DoubleMLDIDMulti::sandwich_se_at_idx`, `DoubleMLDIDMulti::cluster_sandwich_se_at_idx`, `DoubleMLDIDMulti::bias_corrected_coef_at_idx`, `DoubleMLDIDMulti::tune`, `DoubleMLDIDMulti::bootstrap`, `DoubleMLDIDMulti::t_stats`, `DoubleMLDIDMulti::p_values`, `DoubleMLDIDMulti::p_adjust`, `DoubleMLDIDMulti::confint`, `DoubleMLDIDMulti::aggregate_group`, `DoubleMLDIDMulti::aggregate_time`, `DoubleMLDIDMulti::aggregate_event`, `DoubleMLDIDMulti::sensitivity_analysis`, `DoubleMLDIDMulti::sensitivity_analysis_cluster`, `build_lzz2020_dgp`, `build_panel_dgp`, `DoubleMLBLP::new`, `DoubleMLBLP::fit`, `DoubleMLBLP::coef`, `DoubleMLBLP::se`, `DoubleMLBLP::n_obs`, `DoubleMLBLP::bootstrap`, `DoubleMLBLP::rss`, `DoubleMLBLP::sensitivity_analysis`, `DoubleMLBLP::sensitivity_analysis_cluster`, `DoubleMLBLP::var_y`, `DoubleMLBLP::orth_signal`, `DoubleMLBLP::basis`, `DoubleMLBLP::predictions`, `DoubleMLBLP::confint_joint`, `DoubleMLBLP::blp_hat_diagonal`, `DoubleMLBLP::leverage`, `blp_hac_require_df`, `DoubleMLBLP::hac_se`, `DoubleMLBLP::cluster_hac_se`, `policy_tree_build`, `DoubleMLPolicyTree::new`, `policy_tree_ints_to_doubles`, `policy_tree_ints_from_doubles`, `policy_tree_cache_decode`, `policy_tree_honest_leaf_se`, `DoubleMLPolicyTree::fit`, `DoubleMLPolicyTree::set_min_leaf_n`, `DoubleMLPolicyTree::predict`, `DoubleMLPolicyTree::split_feature`, `DoubleMLPolicyTree::split_value`, `DoubleMLPolicyTree::leaf_se`, `DoubleMLPolicyTree::leaf_se_reliable`, `DoubleMLPolicyTree::unreliable_leaves`, `DoubleMLPolicyTree::smallest_leaf_count`, `DoubleMLPolicyTree::policy_value`, `DoubleMLPolicyTree::policy_value_se`, `DoubleMLPolicyTree::leaf_influence`, `DoubleMLPolicyTree::leaf_psi_a`, `DoubleMLPolicyTree::sensitivity_analysis`, `DoubleMLDIDBinaryData::new`, `preprocess_did_binary`, `DoubleMLDIDBinary::new`, `DoubleMLDIDBinary::coef`, `DoubleMLDIDBinary::se`, `DoubleMLDIDBinary::confint`, `DoubleMLDIDBinary::predictions_m`, `DoubleMLDIDBinary::predictions_g0`, `DoubleMLDIDBinary::predictions_g1`, `DoubleMLDIDBinary::sandwich_se`, `DoubleMLDIDBinary::cluster_sandwich_se`, `DoubleMLDIDBinary::bias_corrected_coef`, `DoubleMLDIDBinary::psi_a_long`, `DoubleMLDIDBinary::psi_b_long`, `DoubleMLDIDBinary::inner_psi_a`, `DoubleMLDIDBinary::inner_psi_b`, `DoubleMLDIDBinary::fit`, `DoubleMLDIDBinary::bootstrap`, `DoubleMLDIDBinary::sensitivity_analysis`, `DoubleMLDIDBinary::sensitivity_analysis_cluster`, `DoubleMLDIDBinary::tune`, `stratified_kfold`, `repeated_kfold`, `matrix_predict`, `vector_add`, `vector_scale`, `vector_multiply`, `vector_divide`, `reg_fit_means`, `reg_mean_one_weights`, `enet_coordinate_descent`, `Ridge::coefficients`, `Ridge::intercept`, `Ridge::fit_weighted`, `Ridge::predict`, `Lasso::coefficients`, `Lasso::intercept`, `Lasso::fit_weighted`, `Lasso::predict`, `ElasticNet::coefficients`, `ElasticNet::intercept`, `ElasticNet::fit_weighted`, `ElasticNet::predict`, `enet_objective`, `irm_style_sensitivity`, `sensitivity_from_variance_baselines`, `empirical_quantile`, `irm_style_sensitivity_cluster_multi`, `gain_statistics`, `GainStatsSource::new`, `GainStatsSource::from_blp`, `GainStatsSource::from_blp_cv`, `GainStatsSource::from_blp_cv_repeated`, `GainStatsSource::from_blp_hc0`, `median_sorted`, `joint_sensitivity`, `make_apo_data`, `build_irm_tune_data`, `build_dgp_data`, `PSProcessorConfig::new`, `PSProcessor::adjust_ps`, `folds_to_cv_partition`, `pava`, `pool_tied_x`, `fit_isotonic`, `predict_isotonic`, `isotonic_calibrate_cv`, `cs_bin_panel_subset`, `cs_bin_crossfit_nuisance`, `fit_cs_bin_g`, `cs_bin_score_obs`, `DoubleMLDIDCSBinary::new`, `DoubleMLDIDCSBinary::coef`, `DoubleMLDIDCSBinary::se`, `DoubleMLDIDCSBinary::confint`, `DoubleMLDIDCSBinary::predictions_g_d0_t0`, `DoubleMLDIDCSBinary::predictions_g_d0_t1`, `DoubleMLDIDCSBinary::predictions_g_d1_t0`, `DoubleMLDIDCSBinary::predictions_g_d1_t1`, `DoubleMLDIDCSBinary::predictions_m`, `DoubleMLDIDCSBinary::psi_a`, `DoubleMLDIDCSBinary::psi_b`, `DoubleMLDIDCSBinary::bootstrap`, `DoubleMLDIDCSBinary::cs_bin_sensitivity_nu2_elements`, `DoubleMLDIDCSBinary::cs_bin_sensitivity_residuals`, `DoubleMLDIDCSBinary::sensitivity_analysis_cluster`, `DoubleMLDIDCSBinary::sandwich_se`, `DoubleMLDIDCSBinary::cluster_sandwich_se`, `DoubleMLDIDCSBinary::bias_corrected_coef`, `DoubleMLDIDCSBinary::tune`, `mean_at`, `make_did_CS2021`, `make_did_SZ2020`, `make_simple_rdd_dgp`, `make_plr_CCDDHNR2018`, `make_plr_turrell2018`, `aggregate_group`, `aggregate_time`, `aggregate_event`, `generic_bootstrap_ols_per_coef`, `make_irm_discrete_treatments`, `make_pliv_multiway_cluster`, `v085_int_array_eq`, `v085_dbl_array_close`, `expand_v086_psi`, `expand_v086_ref_hc0`, `expand_v087_psi`, `expand_v087_ref_hc0`, `expand_v087_ref_leverage`, `expand_v087_ssm_data`, `expand_v087_cs_binary_data`, `expand_v088_input_a`, `expand_v089_psi`, `expand_v089_ref_hc0`, `expand_v089_ref_leverage`, `expand_v089_ref_cluster`, `expand_v089_did_binary_data`, `expand_v089_apo_data`, `expand_v090_data`, `expand_v091_data`, `expand_v091_iivm_data`, `expand_v091_cluster_ids`, `expand_v091_old_accumulator`, `expand_v092_lplr_data`, `expand_v092_cluster_ids`, `expand_v093_lpq_data`, `expand_v093_cluster_ids`, `expand_v093_lpq_data_scaled`, `expand_v094_pq_data_scaled`, `expand_v094_cluster_ids`, `expand_v095_qte_data`, `expand_v095_row`, `expand_v095_cluster_ids`, `expand_v095_qte_data_wide`, `v096_dgp`, `v096_dgp_lopsided`, `v096_side_wls`, `v096_meat`, `v096_meat_leverage`, `v097_dgp`, `v097_dgp_constant_leverage`, `v097_reference`, `v097_hc_se`, `v098_dbl_array_eq_nan_aware`, `v098_dgp`, `v098_int_array_eq`, `v098_leaf_means_match_raw`, `v099_dgp`, `v099_identical`, `expand_v101_qte_data`, `expand_v101_cluster_ids`, `expand_v101_row`, `v106_build_panel`, `v106_singletons`, `v107_ssm_dgp`, `v108_dgp`, `v109_plr_data`, `v110_rdd_data`, `v115_rdd_data`, `v115_exact_quadratic`, `v116_assert_exact`, `v117_threshold_data`, `v117_xor_data`, `v117_prob_dev`, `v118_data`, `v118_weights`, `v118_mean`, `v118_clf_data`, `v120_max_abs_diff`, `v120_means`, `v120_expect`, `v120_kfold_folds`, `v120_check_ridge`, `v120_check_enet`, `v121_max_abs_diff`, `v121_expect`, `v122_expect_bool`, `v127_panel`, `v127_raw`, `v128_cs_data`, `v128_xs_data`, `v130_cs_data`, `zz_gate_y_variant`, `v1316_did_data`, `v1317_data`, `v1320_dgp`, `v1330_data`, `v1340_data`, `v1350_data`, `v1380_data`, `v1390_data`, `v1390_changed_steps`, `v1440_plr_fixture`, `v1480_corr`, `v1480_cell_fit`, `v1510_dot`, `v1510_center`, `v1510_resid_after`, `v1510_corr`, `v1550_score_gate_dgp`, `v1590_data`, `build_clustered_dgp`, `build_row_dgp`, `make_did_cs_CS2021`, `DoubleMLDIDCrossSectionData::new`, `DoubleMLDIDCrossSection::new`, `DoubleMLDIDCrossSection::psi_a`, `DoubleMLDIDCrossSection::psi_b`, `DoubleMLDIDCrossSection::predictions_g_d0_t0`, `DoubleMLDIDCrossSection::predictions_g_d0_t1`, `DoubleMLDIDCrossSection::predictions_g_d1_t0`, `DoubleMLDIDCrossSection::predictions_g_d1_t1`, `DoubleMLDIDCrossSection::predictions_m`, `DoubleMLDIDCrossSection::coef`, `DoubleMLDIDCrossSection::se`, `DoubleMLDIDCrossSection::confint`, `crossfit_nuisance`, `fit_g_subset_predict`, `norm_ppf`, `compute_score`, `DoubleMLDIDCrossSection::tune`, `DoubleMLDIDCrossSection::bootstrap`, `DoubleMLDIDCrossSection::sensitivity_analysis`, `DoubleMLDIDCrossSection::sensitivity_analysis_cluster`, `DoubleMLDIDCrossSection::sandwich_se`, `DoubleMLDIDCrossSection::cluster_sandwich_se`, `DoubleMLDIDCrossSection::bias_corrected_coef`, `build_iv_clustered_dgp`, `make_irm_confounded_data`, `make_confounded_plr_data`, `plr_iv_test_dgp`, `make_simple_plr_data`, `assert_bootstrap_t_stat_basic`, `make_irm_heterogeneous_data`, `expand_v100_psi_b_row`, `expand_v100_cluster_ids`, `expand_v100_square`, `expand_v100_didcs_cluster_ids`, `expand_v100_didmulti_cluster_ids`

Functions escalated without any contract (spec gap at L3): `DoubleMLAPO::new (apo.mbt:101)`, `DoubleMLAPO::coef (apo.mbt:196)`, `DoubleMLAPO::se (apo.mbt:207)`, `DoubleMLAPO::confint (apo.mbt:218)`, `DoubleMLAPO::predictions_g (apo.mbt:229)`, `DoubleMLAPO::predictions_m (apo.mbt:240)`, `indicator_level (apo.mbt:251)`, `cross_fit_apo (apo.mbt:275)`, `DoubleMLAPO::fit (apo.mbt:337)`, `DoubleMLAPO::fit_cluster (apo.mbt:549)`, `DoubleMLAPO::sandwich_se (apo.mbt:766)`, `DoubleMLAPO::cluster_sandwich_se (apo.mbt:799)`, `DoubleMLAPO::bias_corrected_coef (apo.mbt:858)`, `DoubleMLAPO::bootstrap (apo.mbt:895)`, `DoubleMLAPO::tune (apo.mbt:968)`, `DoubleMLAPOS::tune (apo.mbt:1024)`, `DoubleMLAPO::sensitivity_nu2_elements (apo.mbt:1094)`, `DoubleMLAPO::sensitivity_analysis (apo.mbt:1127)`, `DoubleMLAPO::sensitivity_analysis_cluster (apo.mbt:1157)`, `DoubleMLAPOS::new (apo.mbt:1282)`, `DoubleMLAPOS::fit (apo.mbt:1379)`, `DoubleMLAPOS::coefs (apo.mbt:1693)`, `DoubleMLAPOS::ses (apo.mbt:1704)`, `DoubleMLAPOS::psi_b_row_at (apo.mbt:1808)`, `DoubleMLAPOS::psi_a_row_at (apo.mbt:1838)`, `DoubleMLAPOS::m_inv_1x1_at (apo.mbt:1868)`, `DoubleMLAPOS::sandwich_se_at (apo.mbt:1919)`, `DoubleMLAPOS::cluster_sandwich_se_at (apo.mbt:1965)`, `DoubleMLAPOS::bias_corrected_coef_at (apo.mbt:2019)`, `DoubleMLAPOS::bootstrap (apo.mbt:2045)`, `DoubleMLAPOS::confint (apo.mbt:2094)`, `DoubleMLAPOS::boot_t_stats (apo.mbt:2148)`, `DoubleMLAPOS::causal_contrast (apo.mbt:2200)`, `DoubleMLAPOS::sensitivity_analysis (apo.mbt:2266)`, `DoubleMLAPOS::sensitivity_analysis_cluster (apo.mbt:2314)`, `DoubleMLDIDData::new (did.mbt:31)`, `DoubleMLDID::new (did.mbt:252)`, `DoubleMLDID::coef (did.mbt:345)`, `DoubleMLDID::se (did.mbt:356)`, `DoubleMLDID::confint (did.mbt:369)`, `cross_fit_did (did.mbt:433)`, `DoubleMLDID::fit (did.mbt:483)`, `DoubleMLDID::bootstrap (did.mbt:793)`, `DoubleMLDID::sensitivity_nu2_elements (did.mbt:873)`, `DoubleMLDID::sensitivity_analysis (did.mbt:940)`, `DoubleMLDID::sensitivity_analysis_cluster (did.mbt:975)`, `DoubleMLDID::sandwich_se (did.mbt:1027)`, `DoubleMLDID::cluster_sandwich_se (did.mbt:1057)`, `DoubleMLDID::bias_corrected_coef (did.mbt:1114)`, `DoubleMLDID::tune (did.mbt:1196)`, `GBLearner::fit_weighted (gbl.mbt:125)`, `predict (gbl.mbt:249)`, `DoubleMLIRM::new (irm.mbt:109)`, `DoubleMLIRM::coef (irm.mbt:184)`, `DoubleMLIRM::se (irm.mbt:195)`, `DoubleMLIRM::confint (irm.mbt:209)`, `filter_indices (irm.mbt:314)`, `clip_vec (irm.mbt:327)`, `cross_fit_irm (irm.mbt:352)`, `DoubleMLIRM::fit (irm.mbt:462)`, `DoubleMLIRM::fit_cluster (irm.mbt:730)`, `DoubleMLIRM::bootstrap (irm.mbt:935)`, `DoubleMLIRM::tune (irm.mbt:1014)`, `DoubleMLIRM::sensitivity_nu2_elements (irm.mbt:1089)`, `DoubleMLIRM::sensitivity_analysis (irm.mbt:1116)`, `DoubleMLIRM::sensitivity_analysis_cluster (irm.mbt:1154)`, `DoubleMLIRM::sandwich_se (irm.mbt:1197)`, `DoubleMLIRM::cluster_sandwich_se (irm.mbt:1238)`, `DoubleMLIRM::bias_corrected_coef (irm.mbt:1296)`, `silverman_bandwidth (kde.mbt:14)`, `sample_sd (kde.mbt:32)`, `percentile_sorted (kde.mbt:65)`, `gaussian_kde (kde.mbt:88)`, `gaussian_kde_weighted (kde.mbt:125)`, `DoubleMLLPQData::new (lpq.mbt:14)`, `lpq_score (lpq.mbt:37)`, `lpq_score_ipw (lpq.mbt:68)`, `DoubleMLLPQ::new (lpq.mbt:178)`, `DoubleMLLPQ::fit (lpq.mbt:236)`, `DoubleMLLPQ::bootstrap (lpq.mbt:536)`, `DoubleMLLPQ::sensitivity_analysis (lpq.mbt:580)`, `DoubleMLLPQ::sensitivity_analysis_cluster (lpq.mbt:608)`, `DoubleMLLPQ::confint (lpq.mbt:655)`, `DoubleMLLPQ::coef (lpq.mbt:677)`, `DoubleMLLPQ::se (lpq.mbt:688)`, `DoubleMLLPQ::predictions_g0 (lpq.mbt:701)`, `DoubleMLLPQ::predictions_g1 (lpq.mbt:714)`, `DoubleMLLPQ::predictions_m (lpq.mbt:727)`, `DoubleMLLPQ::m_inv_1x1 (lpq.mbt:838)`, `DoubleMLLPQ::sandwich_se (lpq.mbt:872)`, `DoubleMLLPQ::cluster_sandwich_se (lpq.mbt:911)`, `DoubleMLLPQ::bias_corrected_coef (lpq.mbt:956)`, `DoubleMLPLR::new (plr.mbt:98)`, `DoubleMLPLR::coef (plr.mbt:158)`, `DoubleMLPLR::se (plr.mbt:171)`, `DoubleMLPLR::confint (plr.mbt:187)`, `plr_score_elements (plr.mbt:348)`, `DoubleMLPLR::fit (plr.mbt:414)`, `DoubleMLPLR::fit_cluster (plr.mbt:673)`, `DoubleMLPLR::bootstrap (plr.mbt:976)`, `DoubleMLPLR::sensitivity_analysis (plr.mbt:1086)`, `DoubleMLPLR::sensitivity_analysis_cluster (plr.mbt:1129)`, `DoubleMLPLR::sandwich_se (plr.mbt:1179)`, `DoubleMLPLR::cluster_sandwich_se (plr.mbt:1214)`, `DoubleMLPLR::bias_corrected_coef (plr.mbt:1271)`, `DoubleMLRDDData::new (rdd.mbt:15)`, `DoubleMLRDD::new (rdd.mbt:160)`, `weighted_xtx_transpose (rdd.mbt:405)`, `DoubleMLRDD::fit (rdd.mbt:663)`, `DoubleMLRDD::coef (rdd.mbt:1001)`, `DoubleMLRDD::se (rdd.mbt:1012)`, `DoubleMLRDD::confint (rdd.mbt:1023)`, `DoubleMLRDD::leverage (rdd.mbt:1194)`, `rdd_hac_require_df (rdd.mbt:1261)`, `DoubleMLRDD::hac_se (rdd.mbt:1321)`, `DoubleMLRDD::cluster_hac_se (rdd.mbt:1462)`, `DoubleMLRDD::sensitivity_analysis (rdd.mbt:1556)`, `DoubleMLRDD::sensitivity_analysis_cluster (rdd.mbt:1593)`, `DoubleMLRDD::bootstrap (rdd.mbt:1720)`, `DoubleMLRDD::tune (rdd.mbt:1831)`, `DoubleMLRDD::bias (rdd.mbt:2089)`, `DoubleMLRDD::tau_bc (rdd.mbt:2228)`, `DoubleMLRDD::tau_bc_collapsed (rdd.mbt:2290)`, `DoubleMLRDD::tau_bc_se (rdd.mbt:2343)`, `DoubleMLRDD::bandwidth_mse (rdd.mbt:2414)`, `DoubleMLRDD::bandwidth_variance_term (rdd.mbt:2487)`, `rdd_pilot_stage (rdd.mbt:2580)`, `rdd_nn_matched_sigma4 (rdd.mbt:2658)`, `nn_residual (rdd.mbt:2806)`, `rdd_rb_side (rdd.mbt:2982)`, `DoubleMLRDD::tau_bc_se_rb (rdd.mbt:3199)`, `bootstrap_indices (rfl.mbt:150)`, `cart_fit (rfl.mbt:202)`, `cart_leaf_value (rfl.mbt:495)`, `RFLearner::fit_weighted (rfl.mbt:610)`, `predict (rfl.mbt:677)`, `DoubleMLSSMData::new (ssm.mbt:18)`, `DoubleMLSSM::new (ssm.mbt:152)`, `DoubleMLSSM::coef (ssm.mbt:286)`, `DoubleMLSSM::se (ssm.mbt:297)`, `DoubleMLSSM::confint (ssm.mbt:308)`, `DoubleMLSSM::bootstrap (ssm.mbt:356)`, `DoubleMLSSM::tune (ssm.mbt:438)`, `DoubleMLSSM::psi_a (ssm.mbt:469)`, `DoubleMLSSM::psi_b (ssm.mbt:480)`, `DoubleMLSSM::sensitivity_analysis (ssm.mbt:498)`, `DoubleMLSSM::sensitivity_analysis_cluster (ssm.mbt:526)`, `augment_one_col (ssm.mbt:553)`, `filter_two_values (ssm.mbt:570)`, `cross_fit_ssm (ssm.mbt:600)`, `DoubleMLSSM::fit (ssm.mbt:692)`, `DoubleMLSSM::sandwich_se (ssm.mbt:957)`, `DoubleMLSSM::cluster_sandwich_se (ssm.mbt:988)`, `DoubleMLSSM::bias_corrected_coef (ssm.mbt:1047)`, `DoubleMLCVAR::new (cvar.mbt:128)`, `DoubleMLCVAR::coef (cvar.mbt:280)`, `DoubleMLCVAR::se (cvar.mbt:292)`, `DoubleMLCVAR::confint (cvar.mbt:304)`, `DoubleMLCVAR::predictions_g (cvar.mbt:317)`, `DoubleMLCVAR::predictions_m (cvar.mbt:333)`, `DoubleMLCVAR::sensitivity_analysis (cvar.mbt:376)`, `DoubleMLCVAR::sensitivity_analysis_cluster (cvar.mbt:431)`, `stratified_half_split (cvar.mbt:465)`, `cvar_ipw_score (cvar.mbt:535)`, `solve_ipw_root (cvar.mbt:573)`, `cvar_inner_crossfit (cvar.mbt:668)`, `DoubleMLCVAR::fit (cvar.mbt:841)`, `DoubleMLCVAR::tune (cvar.mbt:1213)`, `DoubleMLCVAR::bootstrap (cvar.mbt:1265)`, `DoubleMLCVAR::sandwich_se (cvar.mbt:1328)`, `DoubleMLCVAR::cluster_sandwich_se (cvar.mbt:1356)`, `DoubleMLCVAR::bias_corrected_coef (cvar.mbt:1414)`, `DoubleMLData::new (data.mbt:42)`, `DoubleMLIIVMData::new (iivm.mbt:18)`, `DoubleMLIIVM::new (iivm.mbt:178)`, `DoubleMLIIVM::coef (iivm.mbt:292)`, `DoubleMLIIVM::se (iivm.mbt:303)`, `DoubleMLIIVM::confint (iivm.mbt:316)`, `filter_by_value (iivm.mbt:400)`, `cross_fit_iivm (iivm.mbt:434)`, `DoubleMLIIVM::fit (iivm.mbt:550)`, `DoubleMLIIVM::fit_cluster (iivm.mbt:817)`, `DoubleMLIIVM::bootstrap (iivm.mbt:1035)`, `DoubleMLIIVM::tune (iivm.mbt:1111)`, `DoubleMLIIVM::sensitivity_analysis (iivm.mbt:1156)`, `DoubleMLIIVM::sensitivity_analysis_cluster (iivm.mbt:1181)`, `DoubleMLIIVM::sandwich_se (iivm.mbt:1230)`, `DoubleMLIIVM::cluster_sandwich_se (iivm.mbt:1258)`, `DoubleMLIIVM::bias_corrected_coef (iivm.mbt:1315)`, `DoubleMLBinaryData::new (lplr.mbt:46)`, `prelim_beta_per_fold (lplr.mbt:76)`, `lplr_score_at (lplr.mbt:184)`, `newton_solve_score (lplr.mbt:236)`, `DoubleMLLPLR::new (lplr.mbt:354)`, `DoubleMLLPLR::coef (lplr.mbt:530)`, `DoubleMLLPLR::se (lplr.mbt:541)`, `DoubleMLLPLR::confint (lplr.mbt:552)`, `DoubleMLLPLR::predictions_t (lplr.mbt:565)`, `DoubleMLLPLR::predictions_m (lplr.mbt:578)`, `DoubleMLLPLR::predictions_a (lplr.mbt:593)`, `concat_d_x (lplr.mbt:608)`, `DoubleMLLPLR::fit (lplr.mbt:661)`, `DoubleMLLPLR::bootstrap (lplr.mbt:1452)`, `DoubleMLLPLR::tune (lplr.mbt:1535)`, `cross_fit_predict_inner (lplr.mbt:1618)`, `predict (lplr.mbt:1687)`, `DoubleMLLPLR::sensitivity_analysis (lplr.mbt:1750)`, `DoubleMLLPLR::sensitivity_analysis_cluster (lplr.mbt:1782)`, `DoubleMLLPLR::sandwich_se (lplr.mbt:1886)`, `DoubleMLLPLR::cluster_sandwich_se (lplr.mbt:1922)`, `DoubleMLLPLR::bias_corrected_coef (lplr.mbt:1968)`, `DoubleMLPLIVData::new (pliv.mbt:23)`, `DoubleMLPLIV::new (pliv.mbt:155)`, `DoubleMLPLIV::coef (pliv.mbt:206)`, `DoubleMLPLIV::se (pliv.mbt:217)`, `DoubleMLPLIV::confint (pliv.mbt:230)`, `DoubleMLPLIV::fit (pliv.mbt:310)`, `DoubleMLPLIV::fit_cluster (pliv.mbt:539)`, `DoubleMLPLIV::bootstrap (pliv.mbt:733)`, `DoubleMLPLIV::tune (pliv.mbt:811)`, `DoubleMLPLIV::sensitivity_analysis (pliv.mbt:875)`, `DoubleMLPLIV::sensitivity_analysis_cluster (pliv.mbt:897)`, `DoubleMLPLIV::sandwich_se (pliv.mbt:943)`, `DoubleMLPLIV::cluster_sandwich_se (pliv.mbt:971)`, `DoubleMLPLIV::bias_corrected_coef (pliv.mbt:1028)`, `DoubleMLPanelData::new (plpr.mbt:51)`, `sort_rows_by_id_time (plpr.mbt:95)`, `unit_means (plpr.mbt:116)`, `unique_units (plpr.mbt:172)`, `est_coef_cluster (plpr.mbt:198)`, `var_est_cluster (plpr.mbt:252)`, `transform_panel (plpr.mbt:319)`, `DoubleMLPLPR::new (plpr.mbt:554)`, `DoubleMLPLPR::coef (plpr.mbt:655)`, `DoubleMLPLPR::se (plpr.mbt:666)`, `DoubleMLPLPR::confint (plpr.mbt:677)`, `DoubleMLPLPR::predictions_l (plpr.mbt:690)`, `DoubleMLPLPR::predictions_m (plpr.mbt:703)`, `DoubleMLPLPR::sensitivity_analysis (plpr.mbt:763)`, `DoubleMLPLPR::fit (plpr.mbt:801)`, `DoubleMLPLPR::bootstrap (plpr.mbt:1181)`, `DoubleMLPLPR::tune (plpr.mbt:1277)`, `DoubleMLPLPR::sensitivity_analysis_cluster (plpr.mbt:1330)`, `DoubleMLPLPR::sandwich_se (plpr.mbt:1401)`, `DoubleMLPLPR::cluster_sandwich_se (plpr.mbt:1437)`, `DoubleMLPLPR::bias_corrected_coef (plpr.mbt:1495)`, `tune_score_outcome (tune.mbt:175)`, `tune_argmin (tune.mbt:215)`, `tune_score_grid (tune.mbt:278)`, `DoubleMLPLR::tune (tune.mbt:352)`, `GBClassifier::fit_weighted (gbclf.mbt:163)`, `predict (gbclf.mbt:302)`, `kahan_sum (kahan.mbt:58)`, `Fold::new (kfold.mbt:225)`, `check_sample_splitting (kfold.mbt:288)`, `kfold_stratified (kfold.mbt:346)`, `kfold (kfold.mbt:439)`, `slice_matrix_rows (kfold.mbt:487)`, `slice_vector (kfold.mbt:501)`, `expand_unit_folds_to_rows (kfold.mbt:536)`, `build_row_unit_map (kfold.mbt:584)`, `cluster_causal_param_and_se (kfold.mbt:640)`, `cross_fit_predict (kfold.mbt:675)`, `double_cross_fit_predict (kfold.mbt:731)`, `RFClassifier::fit_weighted (rfclf.mbt:148)`, `predict (rfclf.mbt:212)`, `DoubleMLDIDCSData::new (did_cs.mbt:37)`, `discover_groups_times (did_cs.mbt:85)`, `DoubleMLDIDCS::new (did_cs.mbt:322)`, `DoubleMLDIDCS::coef_at (did_cs.mbt:446)`, `DoubleMLDIDCS::se_at (did_cs.mbt:491)`, `DoubleMLDIDCS::group_at (did_cs.mbt:774)`, `DoubleMLDIDCS::period_at (did_cs.mbt:789)`, `DoubleMLDIDCS::cell_flat_at (did_cs.mbt:941)`, `DoubleMLDIDCS::cell_psi_a_row_at (did_cs.mbt:969)`, `DoubleMLDIDCS::cell_psi_b_row_at (did_cs.mbt:995)`, `DoubleMLDIDCS::m_inv_1x1_at (did_cs.mbt:1030)`, `DoubleMLDIDCS::sandwich_se_at (did_cs.mbt:1092)`, `DoubleMLDIDCS::cluster_sandwich_se_at (did_cs.mbt:1161)`, `DoubleMLDIDCS::fit (did_cs.mbt:1244)`, `DoubleMLDIDCS::bootstrap (did_cs.mbt:1871)`, `DoubleMLDIDCS::sensitivity_analysis (did_cs.mbt:1953)`, `DoubleMLDIDCS::confint (did_cs.mbt:1999)`, `DoubleMLDIDCS::sensitivity_analysis_cluster (did_cs.mbt:2071)`, `DoubleMLDIDCS::tune (did_cs.mbt:2201)`, `cholesky (linalg.mbt:12)`, `solve_spd (linalg.mbt:74)`, `add_ridge (linalg.mbt:120)`, `inv_spd (linalg.mbt:141)`, `LinearRegression::coefficients (linear.mbt:46)`, `LinearRegression::fit (linear.mbt:96)`, `LinearRegression::xtwx_inv_diag (linear.mbt:134)`, `LinearRegression::covariance_diagonal (linear.mbt:163)`, `LinearRegression::fit_weighted (linear.mbt:197)`, `LinearRegression::predict (linear.mbt:257)`, `LinearRegression::sandwich_se_weighted (linear.mbt:287)`, `LinearRegression::sandwich_se (linear.mbt:350)`, `predict (linear.mbt:438)`, `Matrix::zeros (matrix.mbt:20)`, `Matrix::ones (matrix.mbt:27)`, `Matrix::from_array (matrix.mbt:35)`, `Matrix::copy (matrix.mbt:85)`, `Matrix::from_rows (matrix.mbt:109)`, `matmul (matrix.mbt:135)`, `matvec (matrix.mbt:167)`, `matvec_t (matrix.mbt:192)`, `dot (matrix.mbt:220)`, `mean (matrix.mbt:245)`, `make_irm_data (dgp_irm.mbt:41)`, `make_ssm_data (dgp_ssm.mbt:38)`, `predict (learner.mbt:83)`, `predict (learner.mbt:132)`, `gather_rows (learner.mbt:350)`, `cross_fit_predict_conditional_dispatch (learner.mbt:383)`, `var_est (var_est.mbt:24)`, `var_est_with_jacobian (var_est.mbt:76)`, `count_eq (apo_test.mbt:22)`, `make_iivm_data (dgp_iivm.mbt:40)`, `make_lplr_LZZ2020 (dgp_lplr.mbt:37)`, `make_pliv_CHS2015 (dgp_pliv.mbt:28)`, `make_plpr_CP2025 (dgp_plpr.mbt:42)`, `LogisticRegression::coefficients (logistic.mbt:31)`, `LogisticRegression::fit (logistic.mbt:105)`, `LogisticRegression::predict (logistic.mbt:218)`, `LogisticRegression::predict_class (logistic.mbt:251)`, `argsort_asc (p_adjust.mbt:91)`, `romano_wolf_p_adjust (p_adjust.mbt:128)`, `holm_bonferroni_p_adjust (p_adjust.mbt:223)`, `bonferroni_p_adjust (p_adjust.mbt:254)`, `bh_fdr_p_adjust (p_adjust.mbt:287)`, `by_fdr_p_adjust (p_adjust.mbt:331)`, `bh_step_up_sorted (p_adjust.mbt:388)`, `tsbh_p_adjust (p_adjust.mbt:484)`, `storey_m0_hat (p_adjust.mbt:543)`, `tsby_p_adjust (p_adjust.mbt:609)`, `array_min (quantile.mbt:7)`, `array_max (quantile.mbt:26)`, `outcome_indicator (quantile.mbt:40)`, `cross_fit_conditional (quantile.mbt:77)`, `pq_score_ipw (quantile.mbt:116)`, `pq_score_orthogonal (quantile.mbt:156)`, `fit_propensity (quantile.mbt:191)`, `solve_pq (quantile.mbt:236)`, `DoubleMLPQ::new (quantile.mbt:479)`, `DoubleMLPQ::fit (quantile.mbt:536)`, `DoubleMLPQ::fit_cluster (quantile.mbt:759)`, `DoubleMLPQ::coef (quantile.mbt:913)`, `DoubleMLPQ::se (quantile.mbt:924)`, `DoubleMLPQ::confint (quantile.mbt:976)`, `DoubleMLPQ::bootstrap (quantile.mbt:1006)`, `DoubleMLPQ::sensitivity_analysis (quantile.mbt:1050)`, `DoubleMLPQ::sensitivity_analysis_cluster (quantile.mbt:1072)`, `DoubleMLPQ::m_inv_1x1 (quantile.mbt:1176)`, `DoubleMLPQ::sandwich_se (quantile.mbt:1217)`, `DoubleMLPQ::cluster_sandwich_se (quantile.mbt:1258)`, `DoubleMLPQ::bias_corrected_coef (quantile.mbt:1303)`, `DoubleMLPQ::tune (quantile.mbt:1342)`, `DoubleMLQTE::fit (quantile.mbt:1575)`, `DoubleMLQTE::fit_cluster (quantile.mbt:1848)`, `DoubleMLQTE::confint (quantile.mbt:2075)`, `DoubleMLQTE::bootstrap (quantile.mbt:2137)`, `DoubleMLQTE::sensitivity_analysis (quantile.mbt:2215)`, `DoubleMLQTE::sensitivity_analysis_cluster (quantile.mbt:2271)`, `DoubleMLQTE::m_inv_1x1_at (quantile.mbt:2442)`, `DoubleMLQTE::psi_row (quantile.mbt:2470)`, `DoubleMLQTE::sandwich_se_at (quantile.mbt:2536)`, `DoubleMLQTE::cluster_sandwich_se_at (quantile.mbt:2574)`, `DoubleMLQTE::bias_corrected_coef_at (quantile.mbt:2628)`, `DoubleMLQTE::joint_covariance (quantile.mbt:2740)`, `DoubleMLQTE::cluster_joint_covariance (quantile.mbt:2814)`, `DoubleMLQTE::tune (quantile.mbt:2901)`, `psi_at (sandwich.mbt:215)`, `sandwich_variance_hc0 (sandwich.mbt:273)`, `sandwich_variance_hc1 (sandwich.mbt:317)`, `sandwich_variance_hc2 (sandwich.mbt:366)`, `sandwich_variance_hc3 (sandwich.mbt:416)`, `cluster_sandwich_variance (sandwich.mbt:534)`, `bias_corrected_theta (sandwich.mbt:646)`, `did_bootstrap_t_stat (bootstrap.mbt:66)`, `DoubleMLDIDMulti::new (did_multi.mbt:83)`, `expand_gt_keyword (did_multi.mbt:211)`, `DoubleMLDIDMulti::coef_at_idx (did_multi.mbt:305)`, `DoubleMLDIDMulti::se_at_idx (did_multi.mbt:337)`, `did_multi_inner_cell_at_idx (did_multi.mbt:381)`, `DoubleMLDIDMulti::sandwich_se_at_idx (did_multi.mbt:459)`, `DoubleMLDIDMulti::cluster_sandwich_se_at_idx (did_multi.mbt:515)`, `DoubleMLDIDMulti::bias_corrected_coef_at_idx (did_multi.mbt:560)`, `DoubleMLDIDMulti::tune (did_multi.mbt:682)`, `DoubleMLDIDMulti::bootstrap (did_multi.mbt:732)`, `DoubleMLDIDMulti::t_stats (did_multi.mbt:826)`, `DoubleMLDIDMulti::p_values (did_multi.mbt:856)`, `DoubleMLDIDMulti::p_adjust (did_multi.mbt:942)`, `DoubleMLDIDMulti::confint (did_multi.mbt:1029)`, `draw_bootstrap_weights (did_multi.mbt:1126)`, `DoubleMLDIDMulti::aggregate_group (did_multi.mbt:1175)`, `DoubleMLDIDMulti::aggregate_time (did_multi.mbt:1196)`, `DoubleMLDIDMulti::aggregate_event (did_multi.mbt:1217)`, `DoubleMLDIDMulti::sensitivity_analysis (did_multi.mbt:1263)`, `DoubleMLDIDMulti::sensitivity_analysis_cluster (did_multi.mbt:1333)`, `build_lzz2020_dgp (lplr_test.mbt:21)`, `build_panel_dgp (plpr_test.mbt:12)`, `aggregate_coef_se (aggregator.mbt:33)`, `DoubleMLBLP::new (blp_policy.mbt:68)`, `DoubleMLBLP::fit (blp_policy.mbt:106)`, `DoubleMLBLP::coef (blp_policy.mbt:356)`, `DoubleMLBLP::se (blp_policy.mbt:367)`, `DoubleMLBLP::n_obs (blp_policy.mbt:379)`, `DoubleMLBLP::bootstrap (blp_policy.mbt:409)`, `DoubleMLBLP::rss (blp_policy.mbt:462)`, `DoubleMLBLP::sensitivity_analysis (blp_policy.mbt:498)`, `DoubleMLBLP::sensitivity_analysis_cluster (blp_policy.mbt:564)`, `DoubleMLBLP::var_y (blp_policy.mbt:620)`, `DoubleMLBLP::orth_signal (blp_policy.mbt:635)`, `DoubleMLBLP::basis (blp_policy.mbt:650)`, `DoubleMLBLP::predictions (blp_policy.mbt:670)`, `DoubleMLBLP::confint_joint (blp_policy.mbt:721)`, `DoubleMLBLP::blp_hat_diagonal (blp_policy.mbt:922)`, `DoubleMLBLP::leverage (blp_policy.mbt:958)`, `blp_hac_require_df (blp_policy.mbt:986)`, `DoubleMLBLP::hac_se (blp_policy.mbt:1032)`, `DoubleMLBLP::cluster_hac_se (blp_policy.mbt:1175)`, `policy_tree_build (blp_policy.mbt:1276)`, `DoubleMLPolicyTree::new (blp_policy.mbt:1585)`, `policy_tree_ints_to_doubles (blp_policy.mbt:1707)`, `policy_tree_ints_from_doubles (blp_policy.mbt:1721)`, `policy_tree_cache_decode (blp_policy.mbt:1782)`, `policy_tree_honest_leaf_se (blp_policy.mbt:1840)`, `DoubleMLPolicyTree::fit (blp_policy.mbt:1870)`, `DoubleMLPolicyTree::set_min_leaf_n (blp_policy.mbt:2227)`, `DoubleMLPolicyTree::predict (blp_policy.mbt:2289)`, `DoubleMLPolicyTree::split_feature (blp_policy.mbt:2307)`, `DoubleMLPolicyTree::split_value (blp_policy.mbt:2318)`, `DoubleMLPolicyTree::leaf_se (blp_policy.mbt:2408)`, `DoubleMLPolicyTree::leaf_se_reliable (blp_policy.mbt:2438)`, `DoubleMLPolicyTree::unreliable_leaves (blp_policy.mbt:2459)`, `DoubleMLPolicyTree::smallest_leaf_count (blp_policy.mbt:2483)`, `DoubleMLPolicyTree::policy_value (blp_policy.mbt:2537)`, `DoubleMLPolicyTree::policy_value_se (blp_policy.mbt:2605)`, `DoubleMLPolicyTree::leaf_influence (blp_policy.mbt:2668)`, `DoubleMLPolicyTree::leaf_psi_a (blp_policy.mbt:2709)`, `DoubleMLPolicyTree::sensitivity_analysis (blp_policy.mbt:2785)`, `DoubleMLDIDBinaryData::new (did_binary.mbt:30)`, `preprocess_did_binary (did_binary.mbt:111)`, `DoubleMLDIDBinary::new (did_binary.mbt:355)`, `DoubleMLDIDBinary::coef (did_binary.mbt:515)`, `DoubleMLDIDBinary::se (did_binary.mbt:527)`, `DoubleMLDIDBinary::confint (did_binary.mbt:541)`, `DoubleMLDIDBinary::predictions_m (did_binary.mbt:558)`, `DoubleMLDIDBinary::predictions_g0 (did_binary.mbt:572)`, `DoubleMLDIDBinary::predictions_g1 (did_binary.mbt:586)`, `DoubleMLDIDBinary::sandwich_se (did_binary.mbt:655)`, `DoubleMLDIDBinary::cluster_sandwich_se (did_binary.mbt:681)`, `DoubleMLDIDBinary::bias_corrected_coef (did_binary.mbt:703)`, `DoubleMLDIDBinary::psi_a_long (did_binary.mbt:724)`, `DoubleMLDIDBinary::psi_b_long (did_binary.mbt:744)`, `DoubleMLDIDBinary::inner_psi_a (did_binary.mbt:767)`, `DoubleMLDIDBinary::inner_psi_b (did_binary.mbt:782)`, `DoubleMLDIDBinary::fit (did_binary.mbt:806)`, `DoubleMLDIDBinary::bootstrap (did_binary.mbt:951)`, `DoubleMLDIDBinary::sensitivity_analysis (did_binary.mbt:980)`, `DoubleMLDIDBinary::sensitivity_analysis_cluster (did_binary.mbt:1000)`, `DoubleMLDIDBinary::tune (did_binary.mbt:1080)`, `stratified_kfold (resampling.mbt:19)`, `repeated_kfold (resampling.mbt:130)`, `matrix_predict (vectorized.mbt:50)`, `vector_subtract (vectorized.mbt:77)`, `vector_add (vectorized.mbt:96)`, `vector_scale (vectorized.mbt:115)`, `vector_multiply (vectorized.mbt:135)`, `vector_divide (vectorized.mbt:165)`, `reg_fit_means (regularized.mbt:119)`, `reg_mean_one_weights (regularized.mbt:152)`, `enet_coordinate_descent (regularized.mbt:200)`, `Ridge::coefficients (regularized.mbt:381)`, `Ridge::intercept (regularized.mbt:393)`, `Ridge::fit_weighted (regularized.mbt:421)`, `Ridge::predict (regularized.mbt:479)`, `predict (regularized.mbt:508)`, `Lasso::coefficients (regularized.mbt:576)`, `Lasso::intercept (regularized.mbt:588)`, `Lasso::fit_weighted (regularized.mbt:612)`, `Lasso::predict (regularized.mbt:650)`, `predict (regularized.mbt:677)`, `ElasticNet::coefficients (regularized.mbt:749)`, `ElasticNet::intercept (regularized.mbt:761)`, `ElasticNet::fit_weighted (regularized.mbt:784)`, `ElasticNet::predict (regularized.mbt:828)`, `predict (regularized.mbt:855)`, `enet_objective (regularized.mbt:879)`, `irm_style_sensitivity (sensitivity.mbt:31)`, `irm_style_sensitivity_from_elements (sensitivity.mbt:78)`, `sensitivity_from_variance_baselines (sensitivity.mbt:149)`, `irm_style_sensitivity_cluster_from_elements (sensitivity.mbt:233)`, `irm_style_sensitivity_cluster (sensitivity.mbt:317)`, `empirical_quantile (sensitivity.mbt:402)`, `irm_style_sensitivity_cluster_multi (sensitivity.mbt:448)`, `single_psi_sensitivity (sensitivity.mbt:489)`, `compute_sensitivity_bias (sensitivity.mbt:566)`, `gain_statistics (sensitivity.mbt:689)`, `GainStatsSource::new (sensitivity.mbt:859)`, `GainStatsSource::from_blp (sensitivity.mbt:905)`, `GainStatsSource::from_blp_cv (sensitivity.mbt:974)`, `GainStatsSource::from_blp_cv_repeated (sensitivity.mbt:1094)`, `GainStatsSource::from_blp_hc0 (sensitivity.mbt:1220)`, `median_sorted (sensitivity.mbt:1342)`, `joint_sensitivity (sensitivity.mbt:1516)`, `make_apo_data (v063_wbtest.mbt:16)`, `build_irm_tune_data (v065_wbtest.mbt:67)`, `build_dgp_data (v066_wbtest.mbt:21)`, `PSProcessorConfig::new (ps_processor.mbt:38)`, `PSProcessor::adjust_ps (ps_processor.mbt:248)`, `folds_to_cv_partition (ps_processor.mbt:331)`, `pava (ps_processor.mbt:440)`, `pool_tied_x (ps_processor.mbt:541)`, `fit_isotonic (ps_processor.mbt:581)`, `predict_isotonic (ps_processor.mbt:654)`, `isotonic_calibrate_cv (ps_processor.mbt:748)`, `normalize_ipw (ps_processor.mbt:910)`, `cs_bin_panel_subset (did_cs_binary.mbt:97)`, `cs_bin_crossfit_nuisance (did_cs_binary.mbt:219)`, `fit_cs_bin_g (did_cs_binary.mbt:391)`, `cs_bin_score_obs (did_cs_binary.mbt:441)`, `DoubleMLDIDCSBinary::new (did_cs_binary.mbt:718)`, `DoubleMLDIDCSBinary::coef (did_cs_binary.mbt:807)`, `DoubleMLDIDCSBinary::se (did_cs_binary.mbt:819)`, `DoubleMLDIDCSBinary::confint (did_cs_binary.mbt:832)`, `DoubleMLDIDCSBinary::predictions_g_d0_t0 (did_cs_binary.mbt:939)`, `DoubleMLDIDCSBinary::predictions_g_d0_t1 (did_cs_binary.mbt:954)`, `DoubleMLDIDCSBinary::predictions_g_d1_t0 (did_cs_binary.mbt:969)`, `DoubleMLDIDCSBinary::predictions_g_d1_t1 (did_cs_binary.mbt:984)`, `DoubleMLDIDCSBinary::predictions_m (did_cs_binary.mbt:1000)`, `DoubleMLDIDCSBinary::psi_a (did_cs_binary.mbt:1015)`, `DoubleMLDIDCSBinary::psi_b (did_cs_binary.mbt:1028)`, `DoubleMLDIDCSBinary::bootstrap (did_cs_binary.mbt:1193)`, `DoubleMLDIDCSBinary::cs_bin_sensitivity_nu2_elements (did_cs_binary.mbt:1263)`, `DoubleMLDIDCSBinary::cs_bin_sensitivity_residuals (did_cs_binary.mbt:1382)`, `DoubleMLDIDCSBinary::sensitivity_analysis_cluster (did_cs_binary.mbt:1465)`, `DoubleMLDIDCSBinary::sandwich_se (did_cs_binary.mbt:1521)`, `DoubleMLDIDCSBinary::cluster_sandwich_se (did_cs_binary.mbt:1554)`, `DoubleMLDIDCSBinary::bias_corrected_coef (did_cs_binary.mbt:1612)`, `DoubleMLDIDCSBinary::tune (did_cs_binary.mbt:1704)`, `mean_at (logistic_test.mbt:23)`, `make_did_CS2021 (dgp_did_CS2021.mbt:43)`, `make_did_SZ2020 (dgp_did_SZ2020.mbt:19)`, `make_simple_rdd_dgp (dgp_simple_rdd.mbt:42)`, `make_plr_CCDDHNR2018 (dgp_plr_CCDDHNR.mbt:45)`, `make_plr_turrell2018 (dgp_plr_turrell.mbt:20)`, `aggregate_group (did_aggregation.mbt:41)`, `aggregate_time (did_aggregation.mbt:107)`, `aggregate_event (did_aggregation.mbt:168)`, `generic_bootstrap_t_stat (bootstrap_helper.mbt:47)`, `generic_bootstrap_single_psi (bootstrap_helper.mbt:104)`, `generic_bootstrap_ols_per_coef (bootstrap_helper.mbt:165)`, `make_irm_discrete_treatments (dgp_irm_discrete.mbt:24)`, `make_pliv_multiway_cluster (dgp_pliv_cluster.mbt:35)`, `v085_int_array_eq (expand_v085_test.mbt:77)`, `v085_dbl_array_close (expand_v085_test.mbt:94)`, `expand_v086_psi (expand_v086_test.mbt:72)`, `expand_v086_ref_hc0 (expand_v086_test.mbt:96)`, `expand_v087_psi (expand_v087_test.mbt:99)`, `expand_v087_ref_hc0 (expand_v087_test.mbt:133)`, `expand_v087_ref_leverage (expand_v087_test.mbt:166)`, `expand_v087_ssm_data (expand_v087_test.mbt:207)`, `expand_v087_cs_binary_data (expand_v087_test.mbt:260)`, `expand_v088_input_a (expand_v088_test.mbt:74)`, `expand_v089_psi (expand_v089_test.mbt:86)`, `expand_v089_ref_hc0 (expand_v089_test.mbt:111)`, `expand_v089_ref_leverage (expand_v089_test.mbt:137)`, `expand_v089_ref_cluster (expand_v089_test.mbt:171)`, `expand_v089_did_binary_data (expand_v089_test.mbt:222)`, `expand_v089_apo_data (expand_v089_test.mbt:273)`, `expand_v090_data (expand_v090_test.mbt:85)`, `expand_v091_data (expand_v091_test.mbt:92)`, `expand_v091_iivm_data (expand_v091_test.mbt:119)`, `expand_v091_cluster_ids (expand_v091_test.mbt:166)`, `expand_v091_old_accumulator (expand_v091_test.mbt:183)`, `expand_v092_lplr_data (expand_v092_test.mbt:74)`, `expand_v092_cluster_ids (expand_v092_test.mbt:135)`, `expand_v093_lpq_data (expand_v093_test.mbt:83)`, `expand_v093_cluster_ids (expand_v093_test.mbt:132)`, `expand_v093_lpq_data_scaled (expand_v093_test.mbt:381)`, `expand_v094_pq_data_scaled (expand_v094_test.mbt:82)`, `expand_v094_cluster_ids (expand_v094_test.mbt:126)`, `expand_v095_qte_data (expand_v095_test.mbt:105)`, `expand_v095_row (expand_v095_test.mbt:159)`, `expand_v095_cluster_ids (expand_v095_test.mbt:170)`, `expand_v095_qte_data_wide (expand_v095_test.mbt:928)`, `v096_dgp (expand_v096_test.mbt:85)`, `v096_dgp_lopsided (expand_v096_test.mbt:124)`, `v096_side_wls (expand_v096_test.mbt:166)`, `v096_meat (expand_v096_test.mbt:246)`, `v096_meat_leverage (expand_v096_test.mbt:262)`, `v097_dgp (expand_v097_test.mbt:28)`, `v097_dgp_constant_leverage (expand_v097_test.mbt:50)`, `v097_reference (expand_v097_test.mbt:79)`, `v097_hc_se (expand_v097_test.mbt:160)`, `v098_dbl_array_eq_nan_aware (expand_v098_test.mbt:121)`, `v098_dgp (expand_v098_test.mbt:172)`, `v098_int_array_eq (expand_v098_test.mbt:457)`, `v098_leaf_means_match_raw (expand_v098_test.mbt:474)`, `v099_dgp (expand_v099_test.mbt:61)`, `v099_identical (expand_v099_test.mbt:84)`, `expand_v101_qte_data (expand_v101_test.mbt:53)`, `expand_v101_cluster_ids (expand_v101_test.mbt:86)`, `expand_v101_row (expand_v101_test.mbt:99)`, `v106_build_panel (expand_v106_test.mbt:52)`, `v106_singletons (expand_v106_test.mbt:92)`, `v107_ssm_dgp (expand_v107_test.mbt:26)`, `v108_dgp (expand_v108_test.mbt:51)`, `v109_plr_data (expand_v109_test.mbt:44)`, `v110_rdd_data (expand_v110_test.mbt:45)`, `v115_rdd_data (expand_v115_test.mbt:76)`, `v115_exact_quadratic (expand_v115_test.mbt:335)`, `v116_assert_exact (expand_v116_test.mbt:134)`, `v117_threshold_data (expand_v117_test.mbt:39)`, `v117_xor_data (expand_v117_test.mbt:54)`, `v117_prob_dev (expand_v117_test.mbt:82)`, `v118_data (expand_v118_test.mbt:70)`, `v118_weights (expand_v118_test.mbt:84)`, `v118_mean (expand_v118_test.mbt:94)`, `v118_clf_data (expand_v118_test.mbt:114)`, `v120_max_abs_diff (expand_v120_test.mbt:54)`, `v120_means (expand_v120_test.mbt:87)`, `v120_expect (expand_v120_test.mbt:160)`, `v120_kfold_folds (expand_v120_test.mbt:6692)`, `v120_check_ridge (expand_v120_test.mbt:6717)`, `v120_check_enet (expand_v120_test.mbt:6749)`, `v121_max_abs_diff (expand_v121_test.mbt:50)`, `v121_expect (expand_v121_test.mbt:72)`, `v122_expect_bool (expand_v122_test.mbt:257)`, `v127_panel (expand_v127_test.mbt:40)`, `v127_raw (expand_v127_test.mbt:85)`, `v128_cs_data (expand_v128_test.mbt:31)`, `v128_xs_data (expand_v128_test.mbt:404)`, `v130_cs_data (expand_v130_test.mbt:36)`, `zz_gate_y_variant (expand_v130_test.mbt:485)`, `v1316_did_data (expand_v131_test.mbt:18)`, `v1317_data (expand_v131_test.mbt:177)`, `v1320_dgp (expand_v132_test.mbt:43)`, `v1330_data (expand_v133_test.mbt:37)`, `v1340_data (expand_v134_test.mbt:49)`, `v1350_data (expand_v135_test.mbt:42)`, `v1380_data (expand_v138_test.mbt:99)`, `v1390_data (expand_v139_test.mbt:78)`, `v1390_changed_steps (expand_v139_test.mbt:102)`, `v1440_plr_fixture (expand_v144_test.mbt:22)`, `v1480_corr (expand_v148_test.mbt:57)`, `v1480_cell_fit (expand_v148_test.mbt:87)`, `v1510_dot (expand_v151_test.mbt:41)`, `v1510_center (expand_v151_test.mbt:50)`, `v1510_resid_after (expand_v151_test.mbt:79)`, `v1510_corr (expand_v151_test.mbt:250)`, `v1550_score_gate_dgp (expand_v155_test.mbt:36)`, `v1590_data (expand_v159_test.mbt:131)`, `build_clustered_dgp (plr_cluster_test.mbt:10)`, `build_row_dgp (plr_cluster_test.mbt:57)`, `make_did_cs_CS2021 (dgp_did_cs_CS2021.mbt:56)`, `DoubleMLDIDCrossSectionData::new (did_cross_section.mbt:35)`, `DoubleMLDIDCrossSection::new (did_cross_section.mbt:188)`, `DoubleMLDIDCrossSection::psi_a (did_cross_section.mbt:252)`, `DoubleMLDIDCrossSection::psi_b (did_cross_section.mbt:286)`, `DoubleMLDIDCrossSection::predictions_g_d0_t0 (did_cross_section.mbt:301)`, `DoubleMLDIDCrossSection::predictions_g_d0_t1 (did_cross_section.mbt:316)`, `DoubleMLDIDCrossSection::predictions_g_d1_t0 (did_cross_section.mbt:331)`, `DoubleMLDIDCrossSection::predictions_g_d1_t1 (did_cross_section.mbt:346)`, `DoubleMLDIDCrossSection::predictions_m (did_cross_section.mbt:363)`, `DoubleMLDIDCrossSection::coef (did_cross_section.mbt:377)`, `DoubleMLDIDCrossSection::se (did_cross_section.mbt:389)`, `DoubleMLDIDCrossSection::confint (did_cross_section.mbt:451)`, `crossfit_nuisance (did_cross_section.mbt:519)`, `fit_g_subset_predict (did_cross_section.mbt:630)`, `norm_ppf (did_cross_section.mbt:711)`, `compute_score (did_cross_section.mbt:738)`, `DoubleMLDIDCrossSection::tune (did_cross_section.mbt:1143)`, `DoubleMLDIDCrossSection::bootstrap (did_cross_section.mbt:1191)`, `DoubleMLDIDCrossSection::sensitivity_analysis (did_cross_section.mbt:1291)`, `DoubleMLDIDCrossSection::sensitivity_analysis_cluster (did_cross_section.mbt:1323)`, `DoubleMLDIDCrossSection::sandwich_se (did_cross_section.mbt:1400)`, `DoubleMLDIDCrossSection::cluster_sandwich_se (did_cross_section.mbt:1436)`, `DoubleMLDIDCrossSection::bias_corrected_coef (did_cross_section.mbt:1510)`, `build_iv_clustered_dgp (pliv_cluster_test.mbt:10)`, `make_irm_confounded_data (dgp_irm_confounded.mbt:30)`, `make_confounded_plr_data (dgp_plr_confounded.mbt:25)`, `plr_iv_test_dgp (plr_iv_type_wbtest.mbt:41)`, `make_simple_plr_data (bootstrap_v061_wbtest.mbt:19)`, `assert_bootstrap_t_stat_basic (bootstrap_v061_wbtest.mbt:42)`, `make_irm_heterogeneous_data (dgp_irm_heterogeneous.mbt:31)`, `expand_v100_psi_b_row (expand_v100_apos_test.mbt:124)`, `expand_v100_cluster_ids (expand_v100_apos_test.mbt:139)`, `expand_v100_square (expand_v100_apos_test.mbt:697)`, `expand_v100_didcs_cluster_ids (expand_v100_didcs_test.mbt:247)`, `expand_v100_didmulti_cluster_ids (expand_v100_didmulti_test.mbt:239)`

## 4. Control-flow analysis

CFG nodes are built from the parsed statement tree; execution paths come from the concrete-execution trace engine. Dead/unreachable detection is static; path coverage and budget findings are dynamic. See `docs/design.md` §5 for the mapping rules.

### 4.1 CFG diagrams (top 8 by cyclomatic complexity)

#### `DoubleMLDIDCS::fit` (did_cs.mbt)

_Diagram omitted: 269 nodes exceeds the readability cap (90). Findings for this function are listed below._

#### `transform_panel` (plpr.mbt)

_Diagram omitted: 138 nodes exceeds the readability cap (90). Findings for this function are listed below._

#### `rdd_rb_side` (rdd.mbt)

_Diagram omitted: 122 nodes exceeds the readability cap (90). Findings for this function are listed below._

#### `DoubleMLPLPR::fit` (plpr.mbt)

_Diagram omitted: 151 nodes exceeds the readability cap (90). Findings for this function are listed below._

#### `kfold_stratified` (kfold.mbt)

```mermaid
flowchart TD
  classDef entryNode fill:#dcedc8,stroke:#33691e,stroke-width:2px
  classDef exitNode fill:#ffcdd2,stroke:#b71c1c,stroke-width:2px
  classDef branchNode fill:#fff9c4,stroke:#f9a825
  classDef loopNode fill:#e1bee7,stroke:#6a1b9a
  classDef mergeNode fill:#eceff1,stroke:#607d8b
  classDef deadNode fill:#eeeeee,stroke:#9e9e9e
  classDef stmtNode fill:#e3f2fd,stroke:#1565c0
  n0(["entry kfold_stratified"]):::entryNode
  n1(["exit"]):::exitNode
  n2["require(n #gt; 0)"]:::stmtNode
  n3["require(strata.length() == n)"]:::stmtNode
  n4["require(n_folds #gt; 0)"]:::stmtNode
  n5["require(n_folds #lt;= n)"]:::stmtNode
  n6["let by_stratum : Array[(String, Array[Int32])] =[]"]:::stmtNode
  n7["for-init 0"]:::stmtNode
  n8{{"for (i #lt; n)"}}:::loopNode
  n9["let key = strata[i].to_string()"]:::stmtNode
  n10["let mut found = false"]:::stmtNode
  n11["for-init 0"]:::stmtNode
  n12{{"for (j #lt; by_stratum.length())"}}:::loopNode
  n13{"if (by_stratum[j].0 == key)"}:::branchNode
  n14["by_stratum[j].1. push(i"]:::stmtNode
  n15[""]:::stmtNode
  n16["found = true"]:::stmtNode
  n17["break"]:::stmtNode
  n18("merge"):::mergeNode
  n19("after-loop"):::mergeNode
  n20{"if !found"}:::branchNode
  n21["by_stratum.push((key,[i]))"]:::stmtNode
  n22("merge"):::mergeNode
  n23("after-loop"):::mergeNode
  n24["let stratum_perm : Array[(String, Array[Int32])] =[]"]:::stmtNode
  n25["for-init 0"]:::stmtNode
  n26{{"for (k_idx #lt; by_stratum.length())"}}:::loopNode
  n27["let key = by_stratum[k_idx].0"]:::stmtNode
  n28["let arr = by_stratum[k_idx].1"]:::stmtNode
  n29["let sub_seed = seed + k_idx * 31337"]:::stmtNode
  n30["let bytes = seed_to_bytes(sub_seed)"]:::stmtNode
  n31["let rng = @random.Rand::chacha8(seed = Bytes::from_array(bytes))"]:::stmtNode
  n32["let perm : Array[Int32] = Array::makei(arr.length(), fn(i) { i})"]:::stmtNode
  n33["for-init (perm.length() - 1)"]:::stmtNode
  n34{{"for (i #gt; 0)"}}:::loopNode
  n35["let j = rng.int(limit = i + 1)"]:::stmtNode
  n36["perm.swap(i, j)"]:::stmtNode
  n37("after-loop"):::mergeNode
  n38["let shuffled : Array[Int32] = Array::make(arr.length(), 0)"]:::stmtNode
  n39["for-init 0"]:::stmtNode
  n40{{"for (i #lt; perm.length())"}}:::loopNode
  n41["shuffled[i] = arr[perm[i]]"]:::stmtNode
  n42("after-loop"):::mergeNode
  n43["stratum_perm.push((key, shuffled))"]:::stmtNode
  n44("after-loop"):::mergeNode
  n45["let folds : Array[Fold] =[]"]:::stmtNode
  n46["for-init 0"]:::stmtNode
  n47{{"for (f #lt; n_folds)"}}:::loopNode
  n48["let test_idx : Array[Int32] =[]"]:::stmtNode
  n49["let train_idx : Array[Int32] =[]"]:::stmtNode
  n50["for-init 0"]:::stmtNode
  n51{{"for (k_idx #lt; stratum_perm.length())"}}:::loopNode
  n52["let arr = stratum_perm[k_idx].1"]:::stmtNode
  n53{"if (arr.length() #gt;= n_folds)"}:::branchNode
  n54["let base = arr.length() / n_folds"]:::stmtNode
  n55["let rem = arr.length() - base * n_folds"]:::stmtNode
  n56["let test_size = if f #lt; rem { base + 1} else { base}"]:::stmtNode
  n57["let offset = f * base +(if f #lt; rem { f} else { rem})"]:::stmtNode
  n58["for-init 0"]:::stmtNode
  n59{{"for (k #lt; test_size)"}}:::loopNode
  n60["test_idx.push(arr[offset + k])"]:::stmtNode
  n61("after-loop"):::mergeNode
  n62["for-init 0"]:::stmtNode
  n63{{"for (k #lt; arr.length())"}}:::loopNode
  n64{"if ((k #lt; offset) &#124;&#124; (k #gt;= (offset + test_size)))"}:::branchNode
  n65["train_idx.push(arr[k])"]:::stmtNode
  n66("merge"):::mergeNode
  n67("after-loop"):::mergeNode
  n68{"if (f == 0)"}:::branchNode
  n69["for-init 0"]:::stmtNode
  n70{{"for (k #lt; arr.length())"}}:::loopNode
  n71["test_idx.push(arr[k])"]:::stmtNode
  n72("after-loop"):::mergeNode
  n73["for-init 0"]:::stmtNode
  n74{{"for (k #lt; arr.length())"}}:::loopNode
  n75["train_idx.push(arr[k])"]:::stmtNode
  n76("after-loop"):::mergeNode
  n77("merge"):::mergeNode
  n78("merge"):::mergeNode
  n79("after-loop"):::mergeNode
  n80["folds.push(Fold::new(train_idx, test_idx))"]:::stmtNode
  n81("after-loop"):::mergeNode
  n82["folds"]:::stmtNode
  n0 --> n2
  n2 --> n3
  n3 --> n4
  n4 --> n5
  n5 --> n6
  n6 --> n7
  n7 --> n8
  n9 --> n10
  n10 --> n11
  n11 --> n12
  n14 --> n15
  n15 --> n16
  n16 --> n17
  n13 -->|true| n14
  n13 -->|false| n18
  n12 -->|true| n13
  n17 -.->|back| n12
  n12 -->|false| n19
  n19 --> n20
  n20 -->|true| n21
  n21 --> n22
  n20 -->|false| n22
  n8 -->|true| n9
  n21 -.->|back| n8
  n8 -->|false| n23
  n23 --> n24
  n24 --> n25
  n25 --> n26
  n27 --> n28
  n28 --> n29
  n29 --> n30
  n30 --> n31
  n31 --> n32
  n32 --> n33
  n33 --> n34
  n35 --> n36
  n34 -->|true| n35
  n36 -.->|back| n34
  n34 -->|false| n37
  n37 --> n38
  n38 --> n39
  n39 --> n40
  n40 -->|true| n41
  n41 -.->|back| n40
  n40 -->|false| n42
  n42 --> n43
  n26 -->|true| n27
  n43 -.->|back| n26
  n26 -->|false| n44
  n44 --> n45
  n45 --> n46
  n46 --> n47
  n48 --> n49
  n49 --> n50
  n50 --> n51
  n52 --> n53
  n54 --> n55
  n55 --> n56
  n56 --> n57
  n57 --> n58
  n58 --> n59
  n59 -->|true| n60
  n60 -.->|back| n59
  n59 -->|false| n61
  n61 --> n62
  n62 --> n63
  n64 -->|true| n65
  n65 --> n66
  n64 -->|false| n66
  n63 -->|true| n64
  n65 -.->|back| n63
  n63 -->|false| n67
  n69 --> n70
  n70 -->|true| n71
  n71 -.->|back| n70
  n70 -->|false| n72
  n73 --> n74
  n74 -->|true| n75
  n75 -.->|back| n74
  n74 -->|false| n76
  n68 -->|true| n69
  n68 -->|false| n73
  n72 --> n77
  n76 --> n77
  n53 -->|true| n54
  n53 -->|false| n68
  n67 --> n78
  n77 --> n78
  n51 -->|true| n52
  n51 -.->|back| n51
  n51 -->|false| n79
  n79 --> n80
  n47 -->|true| n48
  n80 -.->|back| n47
  n47 -->|false| n81
  n81 --> n82
  n82 --> n1
```

#### `DoubleMLDID::fit` (did.mbt)

_Diagram omitted: 98 nodes exceeds the readability cap (90). Findings for this function are listed below._

#### `cart_leaf_value` (rfl.mbt)

```mermaid
flowchart TD
  classDef entryNode fill:#dcedc8,stroke:#33691e,stroke-width:2px
  classDef exitNode fill:#ffcdd2,stroke:#b71c1c,stroke-width:2px
  classDef branchNode fill:#fff9c4,stroke:#f9a825
  classDef loopNode fill:#e1bee7,stroke:#6a1b9a
  classDef mergeNode fill:#eceff1,stroke:#607d8b
  classDef deadNode fill:#eeeeee,stroke:#9e9e9e
  classDef stmtNode fill:#e3f2fd,stroke:#1565c0
  n0(["entry cart_leaf_value"]):::entryNode
  n1(["exit"]):::exitNode
  n2["let n = sample_idx.length()"]:::stmtNode
  n3{"if (n == 0)"}:::branchNode
  n4["return 0"]:::stmtNode
  n5("merge"):::mergeNode
  n6["let weighted = w.length() #gt; 0"]:::stmtNode
  n7["let mut s = 0.0"]:::stmtNode
  n8{"if !weighted"}:::branchNode
  n9["for-init 0"]:::stmtNode
  n10{{"for (i #lt; n)"}}:::loopNode
  n11["s = s + y[sample_idx[i]]"]:::stmtNode
  n12("after-loop"):::mergeNode
  n13{"if (hess.length() == 0)"}:::branchNode
  n14["return (s / n.to_double())"]:::stmtNode
  n15("merge"):::mergeNode
  n16["let mut sw = 0.0"]:::stmtNode
  n17["for-init 0"]:::stmtNode
  n18{{"for (i #lt; n)"}}:::loopNode
  n19["let row = sample_idx[i]"]:::stmtNode
  n20["let wi = w[row]"]:::stmtNode
  n21["s = s + wi * y[row]"]:::stmtNode
  n22["sw = sw + wi"]:::stmtNode
  n23("after-loop"):::mergeNode
  n24{"if (hess.length() == 0)"}:::branchNode
  n25{"if (sw == 0)"}:::branchNode
  n26["return 0"]:::stmtNode
  n27("merge"):::mergeNode
  n28["return (s / sw)"]:::stmtNode
  n29("merge"):::mergeNode
  n30["let mut h = 0.0"]:::stmtNode
  n31["for-init 0"]:::stmtNode
  n32{{"for (i #lt; n)"}}:::loopNode
  n33["h = h + w[sample_idx[i]] * hess[sample_idx[i]]"]:::stmtNode
  n34("after-loop"):::mergeNode
  n35{"if (h == 0)"}:::branchNode
  n36["return 0"]:::stmtNode
  n37("merge"):::mergeNode
  n38["return (s / h)"]:::stmtNode
  n39("merge"):::mergeNode
  n40["let mut h = 0.0"]:::stmtNode
  n41["for-init 0"]:::stmtNode
  n42{{"for (i #lt; n)"}}:::loopNode
  n43["h = h + hess[sample_idx[i]]"]:::stmtNode
  n44("after-loop"):::mergeNode
  n45{"if (h == 0)"}:::branchNode
  n46["return 0"]:::stmtNode
  n47("merge"):::mergeNode
  n48["s / h"]:::stmtNode
  n0 --> n2
  n2 --> n3
  n4 --> n1
  n3 -->|true| n4
  n3 -->|false| n5
  n5 --> n6
  n6 --> n7
  n7 --> n8
  n9 --> n10
  n10 -->|true| n11
  n11 -.->|back| n10
  n10 -->|false| n12
  n12 --> n13
  n14 --> n1
  n13 -->|true| n14
  n13 -->|false| n15
  n16 --> n17
  n17 --> n18
  n19 --> n20
  n20 --> n21
  n21 --> n22
  n18 -->|true| n19
  n22 -.->|back| n18
  n18 -->|false| n23
  n23 --> n24
  n26 --> n1
  n25 -->|true| n26
  n25 -->|false| n27
  n27 --> n28
  n28 --> n1
  n24 -->|true| n25
  n24 -->|false| n29
  n29 --> n30
  n30 --> n31
  n31 --> n32
  n32 -->|true| n33
  n33 -.->|back| n32
  n32 -->|false| n34
  n34 --> n35
  n36 --> n1
  n35 -->|true| n36
  n35 -->|false| n37
  n37 --> n38
  n38 --> n1
  n8 -->|true| n9
  n8 -->|false| n16
  n15 --> n39
  n39 --> n40
  n40 --> n41
  n41 --> n42
  n42 -->|true| n43
  n43 -.->|back| n42
  n42 -->|false| n44
  n44 --> n45
  n46 --> n1
  n45 -->|true| n46
  n45 -->|false| n47
  n47 --> n48
  n48 --> n1
```

#### `GBClassifier::fit_weighted` (gbclf.mbt)

```mermaid
flowchart TD
  classDef entryNode fill:#dcedc8,stroke:#33691e,stroke-width:2px
  classDef exitNode fill:#ffcdd2,stroke:#b71c1c,stroke-width:2px
  classDef branchNode fill:#fff9c4,stroke:#f9a825
  classDef loopNode fill:#e1bee7,stroke:#6a1b9a
  classDef mergeNode fill:#eceff1,stroke:#607d8b
  classDef deadNode fill:#eeeeee,stroke:#9e9e9e
  classDef stmtNode fill:#e3f2fd,stroke:#1565c0
  n0(["entry GBClassifier::fit_weighted"]):::entryNode
  n1(["exit"]):::exitNode
  n2["require(x.nrows == y.length())"]:::stmtNode
  n3["require(self.n_trees #gt;= 1)"]:::stmtNode
  n4["require(self.max_depth #gt;= 0)"]:::stmtNode
  n5["require(self.min_samples_leaf #gt;= 1)"]:::stmtNode
  n6["require(self.learning_rate #gt; 0.0 && self.learning_rate #lt;= 1.0)"]:::stmtNode
  n7["require(self.subsample #gt; 0.0 && self.subsample #lt;= 1.0)"]:::stmtNode
  n8["require(w_is_unweighted(w) &#124;&#124; w.length() == x.nrows)"]:::stmtNode
  n9["for-init 0"]:::stmtNode
  n10{{"for (i #lt; y.length())"}}:::loopNode
  n11["require(y[i] == 0.0 &#124;&#124; y[i] == 1.0)"]:::stmtNode
  n12("after-loop"):::mergeNode
  n13["for-init 0"]:::stmtNode
  n14{{"for (i #lt; w.length())"}}:::loopNode
  n15["require(w[i] #gt;= 0.0)"]:::stmtNode
  n16("after-loop"):::mergeNode
  n17["let n_obs = x.nrows"]:::stmtNode
  n18["let eps = 1.0e-9"]:::stmtNode
  n19["let mut sum_y = 0.0"]:::stmtNode
  n20["for-init 0"]:::stmtNode
  n21{{"for (i #lt; n_obs)"}}:::loopNode
  n22["sum_y = sum_y + y[i]"]:::stmtNode
  n23("after-loop"):::mergeNode
  n24["let raw_p = sum_y / n_obs.to_double()"]:::stmtNode
  n25["let base_rate = if raw_p #lt; eps { eps} else if raw_p #gt; 1.0 - eps { 1.0 - eps} else..."]:::stmtNode
  n26["let initial = @math.ln(base_rate /(1.0 - base_rate))"]:::stmtNode
  n27["let current_pred : Array[Double] = Array::make(n_obs, initial)"]:::stmtNode
  n28["let trees : Array[CART] =[]"]:::stmtNode
  n29["for-init 0"]:::stmtNode
  n30{{"for (r #lt; self.n_trees)"}}:::loopNode
  n31["let neg_grad : Array[Double] = Array::make(n_obs, 0.0)"]:::stmtNode
  n32["let hess : Array[Double] = Array::make(n_obs, 0.0)"]:::stmtNode
  n33["for-init 0"]:::stmtNode
  n34{{"for (i #lt; n_obs)"}}:::loopNode
  n35["let p = sigmoid(current_pred[i])"]:::stmtNode
  n36["neg_grad[i] = y[i] - p"]:::stmtNode
  n37["hess[i] = p *(1.0 - p)"]:::stmtNode
  n38("after-loop"):::mergeNode
  n39["let sample_idx : Array[Int32] = if self.subsample #lt; 1.0 { let n_sub =(n_obs.to_doubl..."]:::stmtNode
  n40["let x_sub : Matrix = { nrows : sample_idx.length(), ncols : x.ncols, data : Array::make..."]:::stmtNode
  n41["for-init 0"]:::stmtNode
  n42{{"for (j #lt; sample_idx.length())"}}:::loopNode
  n43["for-init 0"]:::stmtNode
  n44{{"for (k #lt; x.ncols)"}}:::loopNode
  n45["x_sub.data[j * x.ncols + k] = x.data[sample_idx[j] * x.ncols + k]"]:::stmtNode
  n46("after-loop"):::mergeNode
  n47("after-loop"):::mergeNode
  n48["let y_sub : Array[Double] = Array::make(sample_idx.length(), 0.0)"]:::stmtNode
  n49["for-init 0"]:::stmtNode
  n50{{"for (j #lt; sample_idx.length())"}}:::loopNode
  n51["y_sub[j] = neg_grad[sample_idx[j]]"]:::stmtNode
  n52("after-loop"):::mergeNode
  n53["let hess_sub : Array[Double] = Array::make(sample_idx.length(), 0.0)"]:::stmtNode
  n54["for-init 0"]:::stmtNode
  n55{{"for (j #lt; sample_idx.length())"}}:::loopNode
  n56["hess_sub[j] = hess[sample_idx[j]]"]:::stmtNode
  n57("after-loop"):::mergeNode
  n58["let w_sub : Array[Double] = Array::make(sample_idx.length(), 0.0)"]:::stmtNode
  n59["for-init 0"]:::stmtNode
  n60{{"for (j #lt; sample_idx.length())"}}:::loopNode
  n61["w_sub[j] = if w_is_unweighted(w) { 0.0} else { w[sample_idx[j]]}"]:::stmtNode
  n62("after-loop"):::mergeNode
  n63["let w_eff = if w_is_unweighted(w) {[]} else { w_sub}"]:::stmtNode
  n64["let feature_rng = chacha8_rng(self.bootstrap_seed + self.n_trees + r)"]:::stmtNode
  n65["let tree = cart_fit( x_sub, y_sub, Array::makei(sample_idx.length(), fn(j) { j}), 0, se..."]:::stmtNode
  n66["trees.push(tree)"]:::stmtNode
  n67["for-init 0"]:::stmtNode
  n68{{"for (i #lt; n_obs)"}}:::loopNode
  n69["current_pred[i] = current_pred[i] + self.learning_rate * cart_predict(tree, x, i)"]:::stmtNode
  n70("after-loop"):::mergeNode
  n71("after-loop"):::mergeNode
  n72["{ .. self, initial, base_rate, trees,}"]:::stmtNode
  n0 --> n2
  n2 --> n3
  n3 --> n4
  n4 --> n5
  n5 --> n6
  n6 --> n7
  n7 --> n8
  n8 --> n9
  n9 --> n10
  n10 -->|true| n11
  n11 -.->|back| n10
  n10 -->|false| n12
  n12 --> n13
  n13 --> n14
  n14 -->|true| n15
  n15 -.->|back| n14
  n14 -->|false| n16
  n16 --> n17
  n17 --> n18
  n18 --> n19
  n19 --> n20
  n20 --> n21
  n21 -->|true| n22
  n22 -.->|back| n21
  n21 -->|false| n23
  n23 --> n24
  n24 --> n25
  n25 --> n26
  n26 --> n27
  n27 --> n28
  n28 --> n29
  n29 --> n30
  n31 --> n32
  n32 --> n33
  n33 --> n34
  n35 --> n36
  n36 --> n37
  n34 -->|true| n35
  n37 -.->|back| n34
  n34 -->|false| n38
  n38 --> n39
  n39 --> n40
  n40 --> n41
  n41 --> n42
  n43 --> n44
  n44 -->|true| n45
  n45 -.->|back| n44
  n44 -->|false| n46
  n42 -->|true| n43
  n42 -.->|back| n42
  n42 -->|false| n47
  n47 --> n48
  n48 --> n49
  n49 --> n50
  n50 -->|true| n51
  n51 -.->|back| n50
  n50 -->|false| n52
  n52 --> n53
  n53 --> n54
  n54 --> n55
  n55 -->|true| n56
  n56 -.->|back| n55
  n55 -->|false| n57
  n57 --> n58
  n58 --> n59
  n59 --> n60
  n60 -->|true| n61
  n61 -.->|back| n60
  n60 -->|false| n62
  n62 --> n63
  n63 --> n64
  n64 --> n65
  n65 --> n66
  n66 --> n67
  n67 --> n68
  n68 -->|true| n69
  n69 -.->|back| n68
  n68 -->|false| n70
  n30 -->|true| n31
  n30 -.->|back| n30
  n30 -->|false| n71
  n71 --> n72
  n72 --> n1
```

### 4.2 CFG findings

| Rule | Severity | Function | Location | Message | Method | Confidence |
| --- | --- | --- | --- | --- | --- | --- |
| BUDGET-EXCEEDED | warning | slice_matrix_rows | kfold.mbt:496 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | kfold | kfold.mbt:468 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | draw_bootstrap_weights | did_multi.mbt:1154 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | kfold | kfold.mbt:474 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | kfold | kfold.mbt:474 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | DoubleMLAPOS::confint | apo.mbt:2127 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | DoubleMLAPOS::causal_contrast | apo.mbt:2250 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | DoubleMLDID::fit | did.mbt:611 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | kfold | kfold.mbt:474 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | GBLearner::fit_weighted | gbl.mbt:188 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | kfold | kfold.mbt:474 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | draw_bootstrap_weights | did_multi.mbt:1154 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | kfold | kfold.mbt:474 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |
| BUDGET-EXCEEDED | warning | kfold | kfold.mbt:468 | execution budget exhausted; loop may be non-terminating or inputs too large | dynamic | 0.6 |

### 4.3 Static vs dynamic attribution

| Signal | Method | What a hit means | Known limitation |
| --- | --- | --- | --- |
| Unreachable statement | static | no CFG predecessor; often after `return`/`break` | parser gaps can hide real predecessors |
| Infinite loop | static + dynamic | constant-true condition without break, or iteration cap reached | loops whose exit depends on unmodelled calls are reported as *budget*, not proven infinite |
| Uncovered code | dynamic (coverage import) | zero hits in the observed test suite | absence of execution is not proof of dead code |

## 5. Data flow, taint and the memory layout

Sources are entry-function parameters (and `@env.args` when the frontend sees it); propagation follows recorded definitions and the variables read by each statement; sinks are array-index expressions and allocation sizes. The graph below is the *observed* propagation, not a may-analysis over all inputs.

```mermaid
flowchart LR
  classDef src fill:#ffcdd2,stroke:#b71c1c,stroke-width:2px
  classDef step fill:#fff9c4,stroke:#f9a825
  classDef sink fill:#c8e6c9,stroke:#1b5e20,stroke-width:2px
  t0["source: data"]:::src
  t1["source: treatment_level~"]:::src
  t2["source: n_folds~"]:::src
  t3["source: n_rep~"]:::src
  t4["source: seed~"]:::src
  t5["source: propensity_clip~"]:::src
  t6["source: normalize_ipw~"]:::src
  t7["source: ps_processor_config~"]:::src
  t8["source: ml_g~"]:::src
  t9["source: ml_m~"]:::src
  t10["source: data"]:::src
  t11["source: treatment_level~"]:::src
  t12["source: n_folds~"]:::src
  t13["source: n_rep~"]:::src
  t14["source: seed~"]:::src
  t15["source: propensity_clip~"]:::src
  t16["source: normalize_ipw~"]:::src
  t17["source: ps_processor_config~"]:::src
  t18["source: ml_g~"]:::src
  t19["source: ml_m~"]:::src
  t20["source: data"]:::src
  t21["source: treatment_level~"]:::src
  t22["source: n_folds~"]:::src
  t23["source: n_rep~"]:::src
  t24["source: seed~"]:::src
  t25["source: propensity_clip~"]:::src
  t26["source: normalize_ipw~"]:::src
  t27["source: ps_processor_config~"]:::src
  t28["source: ml_g~"]:::src
  t29["source: ml_m~"]:::src
  t30["source: data"]:::src
  t31["source: treatment_level~"]:::src
  t32["source: n_folds~"]:::src
  t33["source: n_rep~"]:::src
  t34["source: seed~"]:::src
  t35["source: propensity_clip~"]:::src
  t36["source: normalize_ipw~"]:::src
  t37["source: ps_processor_config~"]:::src
  t38["source: ml_g~"]:::src
  t39["source: ml_m~"]:::src
```

### 5.1 Taint sinks

| Rule | Severity | Function | Location | Message | Method | Confidence |
| --- | --- | --- | --- | --- | --- | --- |
| TAINT-ALLOC | error | indicator_level | apo.mbt:252 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | cross_fit_apo | apo.mbt:286 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | cross_fit_apo | apo.mbt:287 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | clip_vec | irm.mbt:329 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | clip_vec | irm.mbt:331 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | normalize_ipw | ps_processor.mbt:927 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | normalize_ipw | ps_processor.mbt:929 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | normalize_ipw | ps_processor.mbt:935 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | normalize_ipw | ps_processor.mbt:936 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | normalize_ipw | ps_processor.mbt:940 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | normalize_ipw | ps_processor.mbt:942 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | normalize_ipw | ps_processor.mbt:943 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | slice_matrix_rows | kfold.mbt:493 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | slice_matrix_rows | kfold.mbt:491 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | unique_units | plpr.mbt:175 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | build_row_unit_map | kfold.mbt:590 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | build_row_unit_map | kfold.mbt:592 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPO::fit_cluster | apo.mbt:576 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPO::fit_cluster | apo.mbt:579 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPO::fit_cluster | apo.mbt:580 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPO::fit_cluster | apo.mbt:581 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPO::fit_cluster | apo.mbt:582 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | psi_at | sandwich.mbt:224 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | psi_at | sandwich.mbt:226 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cluster_sandwich_variance | sandwich.mbt:550 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | cluster_sandwich_variance | sandwich.mbt:559 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | cluster_sandwich_variance | sandwich.mbt:560 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cluster_sandwich_variance | sandwich.mbt:562 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cluster_sandwich_variance | sandwich.mbt:563 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cluster_sandwich_variance | sandwich.mbt:564 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cluster_sandwich_variance | sandwich.mbt:569 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX-RANGE | warning | cluster_sandwich_variance | sandwich.mbt:582 | untrusted input determines an array index; the observed index was inside the array, so no out-of-bounds access was witnessed | dynamic+symbolic | 0.5 |
| TAINT-ALLOC | error | draw_bootstrap_weights | did_multi.mbt:1132 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | kfold | kfold.mbt:466 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1100 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1102 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1111 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1112 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1114 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1117 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1119 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1121 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPO::sensitivity_analysis | apo.mbt:1135 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPO::sensitivity_analysis | apo.mbt:1137 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_from_elements | sensitivity.mbt:94 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_from_elements | sensitivity.mbt:95 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | irm_style_sensitivity_from_elements | sensitivity.mbt:99 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | irm_style_sensitivity_from_elements | sensitivity.mbt:100 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_from_elements | sensitivity.mbt:103 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_from_elements | sensitivity.mbt:104 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_from_elements | sensitivity.mbt:112 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_from_elements | sensitivity.mbt:113 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | compute_sensitivity_bias | sensitivity.mbt:580 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPO::sensitivity_analysis_cluster | apo.mbt:1167 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPO::sensitivity_analysis_cluster | apo.mbt:1169 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:253 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:254 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:260 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:261 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:262 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:265 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:266 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:267 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:268 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:269 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:273 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:274 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:275 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:276 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:283 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:284 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:285 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:290 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:291 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:294 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:295 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:299 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster_from_elements | sensitivity.mbt:300 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPOS::psi_b_row_at | apo.mbt:1822 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPOS::psi_b_row_at | apo.mbt:1825 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPOS::psi_a_row_at | apo.mbt:1850 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPOS::sandwich_se_at | apo.mbt:1930 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPOS::cluster_sandwich_se_at | apo.mbt:1977 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPOS::bias_corrected_coef_at | apo.mbt:2028 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPOS::bootstrap | apo.mbt:2058 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPOS::confint | apo.mbt:2108 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPOS::confint | apo.mbt:2116 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPOS::confint | apo.mbt:2120 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLAPOS::confint | apo.mbt:2121 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX-RANGE | warning | DoubleMLAPOS::causal_contrast | apo.mbt:2217 | untrusted input determines an array index; the observed index was inside the array, so no out-of-bounds access was witnessed | dynamic+symbolic | 0.5 |
| TAINT-INDEX | error | DoubleMLAPOS::causal_contrast | apo.mbt:2220 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPOS::sensitivity_analysis | apo.mbt:2273 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLAPOS::sensitivity_analysis_cluster | apo.mbt:2322 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | check_sample_splitting | kfold.mbt:300 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | check_sample_splitting | kfold.mbt:312 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX-RANGE | warning | DoubleMLDIDData::new | did.mbt:55 | untrusted input determines an array index; the observed index was inside the array, so no out-of-bounds access was witnessed | dynamic+symbolic | 0.5 |
| TAINT-ALLOC | error | cross_fit_did | did.mbt:443 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | cross_fit_did | did.mbt:444 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | cross_fit_did | did.mbt:445 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cross_fit_did | did.mbt:456 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cross_fit_did | did.mbt:457 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cross_fit_did | did.mbt:465 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cross_fit_did | did.mbt:466 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cross_fit_did | did.mbt:473 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cross_fit_did | did.mbt:474 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:553 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:554 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:555 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLDID::fit | did.mbt:606 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLDID::fit | did.mbt:607 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLDID::fit | did.mbt:608 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | generic_bootstrap_t_stat | bootstrap_helper.mbt:74 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLDID::sensitivity_nu2_elements | did.mbt:885 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLDID::sensitivity_nu2_elements | did.mbt:886 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLDID::sensitivity_nu2_elements | did.mbt:893 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLDID::sensitivity_nu2_elements | did.mbt:894 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLDID::sensitivity_nu2_elements | did.mbt:896 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLDID::sensitivity_nu2_elements | did.mbt:897 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLDID::sensitivity_nu2_elements | did.mbt:924 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLDID::sensitivity_nu2_elements | did.mbt:926 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLDID::sensitivity_analysis | did.mbt:950 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLDID::sensitivity_analysis | did.mbt:952 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLDID::sensitivity_analysis_cluster | did.mbt:987 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLDID::sensitivity_analysis_cluster | did.mbt:989 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | GBLearner::fit_weighted | gbl.mbt:146 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | GBLearner::fit_weighted | gbl.mbt:150 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | GBLearner::fit_weighted | gbl.mbt:154 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | GBLearner::fit_weighted | gbl.mbt:156 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | GBLearner::fit_weighted | gbl.mbt:185 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX-RANGE | warning | GBLearner::fit_weighted | gbl.mbt:140 | untrusted input determines an array index; the observed index was inside the array, so no out-of-bounds access was witnessed | dynamic+symbolic | 0.5 |
| TAINT-ALLOC | error | predict | gbl.mbt:251 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | filter_indices | irm.mbt:317 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | cross_fit_irm | irm.mbt:363 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | cross_fit_irm | irm.mbt:364 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | cross_fit_irm | irm.mbt:365 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cross_fit_irm | irm.mbt:384 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cross_fit_irm | irm.mbt:385 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cross_fit_irm | irm.mbt:399 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cross_fit_irm | irm.mbt:400 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cross_fit_irm | irm.mbt:408 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | cross_fit_irm | irm.mbt:409 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLIRM::fit_cluster | irm.mbt:760 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:762 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:763 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:764 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:765 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:766 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:767 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLIRM::sensitivity_nu2_elements | irm.mbt:1097 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLIRM::sensitivity_nu2_elements | irm.mbt:1098 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLIRM::sensitivity_nu2_elements | irm.mbt:1100 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLIRM::sensitivity_nu2_elements | irm.mbt:1101 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLIRM::sensitivity_nu2_elements | irm.mbt:1108 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLIRM::sensitivity_nu2_elements | irm.mbt:1110 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | vector_subtract | vectorized.mbt:81 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | vector_subtract | vectorized.mbt:83 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLIRM::sensitivity_analysis | irm.mbt:1132 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLIRM::sensitivity_analysis | irm.mbt:1134 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLIRM::sensitivity_analysis_cluster | irm.mbt:1170 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLIRM::sensitivity_analysis_cluster | irm.mbt:1172 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX-RANGE | warning | mean | matrix.mbt:252 | untrusted input determines an array index; the observed index was inside the array, so no out-of-bounds access was witnessed | dynamic+symbolic | 0.5 |
| TAINT-INDEX-RANGE | warning | sample_sd | kde.mbt:40 | untrusted input determines an array index; the observed index was inside the array, so no out-of-bounds access was witnessed | dynamic+symbolic | 0.5 |
| TAINT-INDEX | error | percentile_sorted | kde.mbt:77 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | lpq_score | lpq.mbt:48 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | lpq_score | lpq.mbt:51 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | lpq_score | lpq.mbt:52 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | lpq_score | lpq.mbt:53 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | lpq_score | lpq.mbt:54 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | lpq_score_ipw | lpq.mbt:77 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | lpq_score_ipw | lpq.mbt:81 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | lpq_score_ipw | lpq.mbt:82 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | generic_bootstrap_single_psi | bootstrap_helper.mbt:113 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | single_psi_sensitivity | sensitivity.mbt:503 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | single_psi_sensitivity | sensitivity.mbt:504 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | single_psi_sensitivity | sensitivity.mbt:510 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | single_psi_sensitivity | sensitivity.mbt:514 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | single_psi_sensitivity | sensitivity.mbt:515 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | single_psi_sensitivity | sensitivity.mbt:517 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | single_psi_sensitivity | sensitivity.mbt:518 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLLPQ::sensitivity_analysis_cluster | lpq.mbt:622 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | DoubleMLLPQ::sensitivity_analysis_cluster | lpq.mbt:625 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | DoubleMLLPQ::sensitivity_analysis_cluster | lpq.mbt:627 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:339 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:340 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | irm_style_sensitivity_cluster | sensitivity.mbt:346 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | irm_style_sensitivity_cluster | sensitivity.mbt:347 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:350 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:351 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:352 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:353 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:357 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:358 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:359 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:366 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:367 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | irm_style_sensitivity_cluster | sensitivity.mbt:375 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | irm_style_sensitivity_cluster | sensitivity.mbt:376 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:378 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | irm_style_sensitivity_cluster | sensitivity.mbt:379 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | aggregate_coef_se | aggregator.mbt:53 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |
| TAINT-ALLOC | error | aggregate_coef_se | aggregator.mbt:55 | tainted value controls an allocation size | dynamic+symbolic | 0.8 |
| TAINT-INDEX | error | aggregate_coef_se | aggregator.mbt:60 | tainted value reaches an array index / buffer offset | dynamic+symbolic | 0.8 |

### 5.2 L2 abstract findings (may-analysis)

Abstract interpretation joins all paths and widens loops, so these alarms are *may* properties: a hit means the abstract state cannot exclude the defect, not that a concrete input was observed. Two rules keep the may-analysis from crying wolf. A branch that is unreachable in ONE iteration of a loop is not reported, because the loop's state changes between the iterations. And a tainted index is only claimed when the container is known to be an array: the analyzer cannot see the type of a struct's field, and a Map's key is not an offset that untrusted input chose.

**Scope.** The abstract layer analysed 1411 of 1411 — every function the abstract layer can analyse, in 167271 steps.

| Family | Findings |
| --- | ---: |
| RANGE-VIOLATION | 1403 |
| TAINT-ALLOC | 869 |
| TAINT-INDEX | 236 |
| UNSUPPORTED | 20 |

| Rule | Severity | Function | Location | Message | Method | Confidence |
| --- | --- | --- | --- | --- | --- | --- |
| RANGE-VIOLATION | warning | DoubleMLAPO::new | apo.mbt:116 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::new | apo.mbt:117 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::new | apo.mbt:118 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::new | apo.mbt:119 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::new | apo.mbt:120 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::coef | apo.mbt:198 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::se | apo.mbt:209 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::confint | apo.mbt:220 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::predictions_g | apo.mbt:231 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::predictions_m | apo.mbt:242 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | indicator_level | apo.mbt:252 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | cross_fit_apo | apo.mbt:286 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | cross_fit_apo | apo.mbt:287 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::fit | apo.mbt:409 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::fit | apo.mbt:410 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::fit | apo.mbt:413 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::fit | apo.mbt:475 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::fit_cluster | apo.mbt:556 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::fit_cluster | apo.mbt:562 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::fit_cluster | apo.mbt:579 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::fit_cluster | apo.mbt:580 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::fit_cluster | apo.mbt:581 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::fit_cluster | apo.mbt:582 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::fit_cluster | apo.mbt:648 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::fit_cluster | apo.mbt:649 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::sandwich_se | apo.mbt:771 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::sandwich_se | apo.mbt:773 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::sandwich_se | apo.mbt:776 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::sandwich_se | apo.mbt:779 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::cluster_sandwich_se | apo.mbt:804 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::cluster_sandwich_se | apo.mbt:806 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::cluster_sandwich_se | apo.mbt:807 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::cluster_sandwich_se | apo.mbt:810 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::cluster_sandwich_se | apo.mbt:819 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::bias_corrected_coef | apo.mbt:860 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::bootstrap | apo.mbt:902 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::bootstrap | apo.mbt:903 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::bootstrap | apo.mbt:906 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::tune | apo.mbt:976 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::tune | apo.mbt:977 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::tune | apo.mbt:986 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::tune | apo.mbt:1032 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::tune | apo.mbt:1033 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::tune | apo.mbt:1034 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1097 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1100 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1111 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1112 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1119 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::sensitivity_analysis | apo.mbt:1132 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::sensitivity_analysis | apo.mbt:1135 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::sensitivity_analysis_cluster | apo.mbt:1163 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPO::sensitivity_analysis_cluster | apo.mbt:1166 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPO::sensitivity_analysis_cluster | apo.mbt:1167 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::new | apo.mbt:1304 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::new | apo.mbt:1305 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::new | apo.mbt:1306 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::new | apo.mbt:1307 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::new | apo.mbt:1308 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::new | apo.mbt:1309 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::fit | apo.mbt:1391 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::coefs | apo.mbt:1695 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::ses | apo.mbt:1706 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::psi_b_row_at | apo.mbt:1814 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::psi_b_row_at | apo.mbt:1815 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::psi_b_row_at | apo.mbt:1816 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::psi_b_row_at | apo.mbt:1817 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::psi_b_row_at | apo.mbt:1818 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::psi_b_row_at | apo.mbt:1820 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::psi_b_row_at | apo.mbt:1821 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPOS::psi_b_row_at | apo.mbt:1822 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::psi_a_row_at | apo.mbt:1844 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::psi_a_row_at | apo.mbt:1845 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::psi_a_row_at | apo.mbt:1846 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::psi_a_row_at | apo.mbt:1848 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::psi_a_row_at | apo.mbt:1849 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPOS::psi_a_row_at | apo.mbt:1850 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::m_inv_1x1_at | apo.mbt:1875 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::sandwich_se_at | apo.mbt:1925 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::sandwich_se_at | apo.mbt:1932 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::cluster_sandwich_se_at | apo.mbt:1971 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::cluster_sandwich_se_at | apo.mbt:1974 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::cluster_sandwich_se_at | apo.mbt:1981 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::bias_corrected_coef_at | apo.mbt:2024 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::bias_corrected_coef_at | apo.mbt:2025 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::bias_corrected_coef_at | apo.mbt:2026 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::bias_corrected_coef_at | apo.mbt:2027 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::bootstrap | apo.mbt:2052 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::bootstrap | apo.mbt:2053 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::bootstrap | apo.mbt:2056 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPOS::bootstrap | apo.mbt:2058 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::confint | apo.mbt:2100 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::confint | apo.mbt:2101 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::confint | apo.mbt:2103 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPOS::confint | apo.mbt:2108 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPOS::confint | apo.mbt:2116 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-INDEX | error | DoubleMLAPOS::confint | apo.mbt:2132 | tainted value may reach an array index / buffer offset | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::boot_t_stats | apo.mbt:2150 | assertion may fail on some inputs | L2-abstract | 0.6 |
| UNSUPPORTED | info | DoubleMLAPOS::causal_contrast | apo.mbt:2227 | tainted value may reach abort/panic | L2-abstract | 0.5 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::sensitivity_analysis | apo.mbt:2271 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPOS::sensitivity_analysis | apo.mbt:2273 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLAPOS::sensitivity_analysis_cluster | apo.mbt:2320 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLAPOS::sensitivity_analysis_cluster | apo.mbt:2322 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDIDData::new | did.mbt:40 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDIDData::new | did.mbt:46 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::new | did.mbt:277 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::new | did.mbt:278 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::new | did.mbt:279 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::new | did.mbt:280 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::new | did.mbt:281 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::new | did.mbt:282 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::new | did.mbt:284 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::coef | did.mbt:347 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::se | did.mbt:358 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::confint | did.mbt:375 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::confint | did.mbt:376 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | cross_fit_did | did.mbt:443 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | cross_fit_did | did.mbt:444 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | cross_fit_did | did.mbt:445 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:553 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:554 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:555 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:612 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:613 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:614 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:649 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:650 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:651 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::fit | did.mbt:656 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::bootstrap | did.mbt:800 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::bootstrap | did.mbt:801 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::bootstrap | did.mbt:804 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::sensitivity_nu2_elements | did.mbt:876 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::sensitivity_nu2_elements | did.mbt:880 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::sensitivity_nu2_elements | did.mbt:893 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::sensitivity_nu2_elements | did.mbt:894 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::sensitivity_nu2_elements | did.mbt:924 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::sensitivity_analysis | did.mbt:945 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::sensitivity_analysis | did.mbt:950 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::sensitivity_analysis_cluster | did.mbt:981 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::sensitivity_analysis_cluster | did.mbt:986 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLDID::sensitivity_analysis_cluster | did.mbt:987 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::sandwich_se | did.mbt:1032 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::sandwich_se | did.mbt:1036 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::sandwich_se | did.mbt:1039 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::cluster_sandwich_se | did.mbt:1062 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::cluster_sandwich_se | did.mbt:1064 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::cluster_sandwich_se | did.mbt:1067 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::cluster_sandwich_se | did.mbt:1076 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::bias_corrected_coef | did.mbt:1116 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::tune | did.mbt:1204 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLDID::tune | did.mbt:1205 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | GBLearner::fit_weighted | gbl.mbt:132 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | GBLearner::fit_weighted | gbl.mbt:133 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | GBLearner::fit_weighted | gbl.mbt:134 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | GBLearner::fit_weighted | gbl.mbt:135 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | GBLearner::fit_weighted | gbl.mbt:136 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | GBLearner::fit_weighted | gbl.mbt:137 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | GBLearner::fit_weighted | gbl.mbt:138 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | GBLearner::fit_weighted | gbl.mbt:140 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | GBLearner::fit_weighted | gbl.mbt:150 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | GBLearner::fit_weighted | gbl.mbt:154 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | predict | gbl.mbt:251 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::new | irm.mbt:122 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::new | irm.mbt:123 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::new | irm.mbt:124 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::new | irm.mbt:125 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::new | irm.mbt:126 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::coef | irm.mbt:186 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::se | irm.mbt:197 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::confint | irm.mbt:215 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::confint | irm.mbt:216 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-INDEX | error | filter_indices | irm.mbt:317 | tainted value may reach an array index / buffer offset | L2-abstract | 0.6 |
| TAINT-ALLOC | error | clip_vec | irm.mbt:329 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | cross_fit_irm | irm.mbt:363 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | cross_fit_irm | irm.mbt:364 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | cross_fit_irm | irm.mbt:365 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-INDEX | error | cross_fit_irm | irm.mbt:375 | tainted value may reach an array index / buffer offset | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | cross_fit_irm | irm.mbt:379 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-INDEX | error | cross_fit_irm | irm.mbt:390 | tainted value may reach an array index / buffer offset | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | cross_fit_irm | irm.mbt:394 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::fit | irm.mbt:469 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit | irm.mbt:551 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit | irm.mbt:552 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit | irm.mbt:554 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit | irm.mbt:555 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit | irm.mbt:556 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit | irm.mbt:557 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit | irm.mbt:616 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit | irm.mbt:617 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit | irm.mbt:639 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit | irm.mbt:640 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::fit_cluster | irm.mbt:737 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::fit_cluster | irm.mbt:743 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:762 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:763 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:764 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:765 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:766 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:767 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:850 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::fit_cluster | irm.mbt:851 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::bootstrap | irm.mbt:942 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::bootstrap | irm.mbt:943 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::bootstrap | irm.mbt:946 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::tune | irm.mbt:1022 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::tune | irm.mbt:1023 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::tune | irm.mbt:1024 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::sensitivity_nu2_elements | irm.mbt:1092 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::sensitivity_nu2_elements | irm.mbt:1096 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::sensitivity_nu2_elements | irm.mbt:1097 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::sensitivity_nu2_elements | irm.mbt:1098 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::sensitivity_nu2_elements | irm.mbt:1108 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::sensitivity_analysis | irm.mbt:1121 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::sensitivity_analysis | irm.mbt:1132 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::sensitivity_analysis_cluster | irm.mbt:1160 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::sensitivity_analysis_cluster | irm.mbt:1165 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLIRM::sensitivity_analysis_cluster | irm.mbt:1170 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::sandwich_se | irm.mbt:1202 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::sandwich_se | irm.mbt:1213 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::sandwich_se | irm.mbt:1221 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::cluster_sandwich_se | irm.mbt:1243 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::cluster_sandwich_se | irm.mbt:1245 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::cluster_sandwich_se | irm.mbt:1248 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::cluster_sandwich_se | irm.mbt:1257 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLIRM::bias_corrected_coef | irm.mbt:1298 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | silverman_bandwidth | kde.mbt:17 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-INDEX | error | percentile_sorted | kde.mbt:77 | tainted value may reach an array index / buffer offset | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | gaussian_kde | kde.mbt:91 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | gaussian_kde | kde.mbt:92 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | gaussian_kde_weighted | kde.mbt:133 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | gaussian_kde_weighted | kde.mbt:134 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | gaussian_kde_weighted | kde.mbt:135 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQData::new | lpq.mbt:21 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQData::new | lpq.mbt:22 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQData::new | lpq.mbt:23 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | lpq_score | lpq.mbt:48 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | lpq_score_ipw | lpq.mbt:77 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::new | lpq.mbt:188 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::new | lpq.mbt:189 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::new | lpq.mbt:190 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::new | lpq.mbt:191 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::fit | lpq.mbt:239 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLLPQ::fit | lpq.mbt:284 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLLPQ::fit | lpq.mbt:304 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLLPQ::fit | lpq.mbt:305 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLLPQ::fit | lpq.mbt:418 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLLPQ::fit | lpq.mbt:465 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::bootstrap | lpq.mbt:543 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::bootstrap | lpq.mbt:544 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::bootstrap | lpq.mbt:547 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::sensitivity_analysis | lpq.mbt:585 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::sensitivity_analysis_cluster | lpq.mbt:614 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::sensitivity_analysis_cluster | lpq.mbt:616 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLLPQ::sensitivity_analysis_cluster | lpq.mbt:625 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::confint | lpq.mbt:661 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::confint | lpq.mbt:662 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::coef | lpq.mbt:679 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::se | lpq.mbt:690 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::predictions_g0 | lpq.mbt:703 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::predictions_g1 | lpq.mbt:716 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::predictions_m | lpq.mbt:729 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::m_inv_1x1 | lpq.mbt:840 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::m_inv_1x1 | lpq.mbt:841 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::m_inv_1x1 | lpq.mbt:842 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::m_inv_1x1 | lpq.mbt:844 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::sandwich_se | lpq.mbt:887 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::cluster_sandwich_se | lpq.mbt:918 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::cluster_sandwich_se | lpq.mbt:926 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLLPQ::bias_corrected_coef | lpq.mbt:958 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::new | plr.mbt:107 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::new | plr.mbt:108 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::new | plr.mbt:109 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::coef | plr.mbt:160 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::se | plr.mbt:173 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::confint | plr.mbt:193 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::confint | plr.mbt:194 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | plr_score_elements | plr.mbt:355 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | plr_score_elements | plr.mbt:355 | allocation size may be negative | L2-abstract | 0.9 |
| TAINT-ALLOC | error | plr_score_elements | plr.mbt:356 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | plr_score_elements | plr.mbt:356 | allocation size may be negative | L2-abstract | 0.9 |
| RANGE-VIOLATION | warning | DoubleMLPLR::fit | plr.mbt:423 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::fit | plr.mbt:424 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::fit | plr.mbt:431 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLPLR::fit | plr.mbt:517 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLPLR::fit | plr.mbt:518 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLPLR::fit | plr.mbt:520 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLPLR::fit | plr.mbt:521 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::fit_cluster | plr.mbt:682 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::fit_cluster | plr.mbt:688 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::fit_cluster | plr.mbt:695 | assertion may fail on some inputs | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLPLR::fit_cluster | plr.mbt:716 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLPLR::fit_cluster | plr.mbt:717 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLPLR::fit_cluster | plr.mbt:718 | tainted value may control an allocation size | L2-abstract | 0.6 |
| TAINT-ALLOC | error | DoubleMLPLR::fit_cluster | plr.mbt:719 | tainted value may control an allocation size | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::bootstrap | plr.mbt:983 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::bootstrap | plr.mbt:984 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::bootstrap | plr.mbt:987 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::sensitivity_analysis | plr.mbt:1091 | assertion may fail on some inputs | L2-abstract | 0.6 |
| RANGE-VIOLATION | warning | DoubleMLPLR::sensitivity_analysis_cluster | plr.mbt:1135 | assertion may fail on some inputs | L2-abstract | 0.6 |
| ... | ... | ... | ... | (truncated at 300 of 2528 rows) | ... | ... |

_This table shows the first 300 of 2528 findings, in the order the analysis produced them. The count table above is the whole set, family by family, and every finding -- the 2228 not shown here among them -- is in the report's `_findings.jsonl` sidecar._


### 5.3 EVA findings (evolved value analysis)

The evolved value analysis rides on the same fixpoint and asks the second question about a value: not *what is its range* but *what happens when it is used*. These are the memory-safety and undefined-behaviour classes, mapped onto what MoonBit actually does — MoonBit's integer arithmetic WRAPS instead of trapping, so an overflow here is a silent wrong value and not a crash.

The index class is proved by the interval the abstract domain already computes — the array's length and the index's range are both known, so the comparison covers the whole input abstraction — and it is filed here because an index is a value USED to address storage.

| Family | Findings |
| --- | ---: |
| INDEX-OOB | 684 |
| INTEGER-OVERFLOW | 90 |
| DIVISION-BY-ZERO | 14 |

| Rule | Severity | Function | Location | Message | Method | Confidence |
| --- | --- | --- | --- | --- | --- | --- |
| INDEX-OOB | error | DoubleMLAPO::fit | apo.mbt:456 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLAPO::fit | apo.mbt:457 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLAPO::fit_cluster | apo.mbt:652 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1117 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLAPO::sensitivity_nu2_elements | apo.mbt:1121 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::fit | did.mbt:606 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::fit | did.mbt:607 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::fit | did.mbt:608 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::fit | did.mbt:616 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::fit | did.mbt:617 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::fit | did.mbt:618 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::fit | did.mbt:669 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::fit | did.mbt:675 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::fit | did.mbt:702 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::fit | did.mbt:703 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::fit | did.mbt:712 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::fit | did.mbt:713 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDID::sensitivity_nu2_elements | did.mbt:926 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | GBLearner::fit_weighted | gbl.mbt:146 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | GBLearner::fit_weighted | gbl.mbt:156 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | GBLearner::fit_weighted | gbl.mbt:216 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | predict | gbl.mbt:258 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | clip_vec | irm.mbt:331 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLIRM::fit_cluster | irm.mbt:855 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLIRM::fit_cluster | irm.mbt:861 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLIRM::sensitivity_nu2_elements | irm.mbt:1110 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | sample_sd | kde.mbt:40 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | percentile_sorted | kde.mbt:71 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | gaussian_kde | kde.mbt:97 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | gaussian_kde_weighted | kde.mbt:140 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | gaussian_kde_weighted | kde.mbt:141 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | lpq_score | lpq.mbt:51 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | lpq_score | lpq.mbt:52 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | lpq_score | lpq.mbt:53 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | lpq_score | lpq.mbt:54 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | lpq_score_ipw | lpq.mbt:81 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | lpq_score_ipw | lpq.mbt:82 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | plr_score_elements | plr.mbt:364 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | plr_score_elements | plr.mbt:365 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | plr_score_elements | plr.mbt:370 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | plr_score_elements | plr.mbt:371 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLPLR::sensitivity_analysis_cluster | plr.mbt:1161 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLPLR::sensitivity_analysis_cluster | plr.mbt:1162 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | weighted_xtx_transpose | rdd.mbt:413 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLRDD::cluster_hac_se | rdd.mbt:1482 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLRDD::cluster_hac_se | rdd.mbt:1483 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLRDD::cluster_hac_se | rdd.mbt:1484 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLRDD::cluster_hac_se | rdd.mbt:1492 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLRDD::cluster_hac_se | rdd.mbt:1501 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLRDD::cluster_hac_se | rdd.mbt:1510 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_nn_matched_sigma4 | rdd.mbt:2692 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_nn_matched_sigma4 | rdd.mbt:2697 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_nn_matched_sigma4 | rdd.mbt:2703 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_nn_matched_sigma4 | rdd.mbt:2724 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_nn_matched_sigma4 | rdd.mbt:2725 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_nn_matched_sigma4 | rdd.mbt:2729 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_nn_matched_sigma4 | rdd.mbt:2730 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | nn_residual | rdd.mbt:2826 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | nn_residual | rdd.mbt:2841 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | nn_residual | rdd.mbt:2842 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | nn_residual | rdd.mbt:2849 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | nn_residual | rdd.mbt:2850 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | nn_residual | rdd.mbt:2871 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | nn_residual | rdd.mbt:2872 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3039 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3041 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3050 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3056 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3058 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3060 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3076 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3078 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3082 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3084 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3086 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3101 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3102 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3109 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3141 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3143 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | rdd_rb_side | rdd.mbt:3147 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cart_fit | rfl.mbt:232 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cart_fit | rfl.mbt:237 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cart_fit | rfl.mbt:240 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cart_leaf_value | rfl.mbt:510 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cart_leaf_value | rfl.mbt:520 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cart_leaf_value | rfl.mbt:533 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cart_leaf_value | rfl.mbt:542 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | augment_one_col | ssm.mbt:561 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLSSM::fit | ssm.mbt:811 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLSSM::fit | ssm.mbt:812 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLSSM::fit | ssm.mbt:813 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLSSM::fit | ssm.mbt:814 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLSSM::fit | ssm.mbt:831 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLSSM::fit | ssm.mbt:832 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLSSM::fit | ssm.mbt:833 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLSSM::fit | ssm.mbt:834 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLSSM::fit | ssm.mbt:856 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLCVAR::sensitivity_analysis | cvar.mbt:415 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cvar_ipw_score | cvar.mbt:548 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cvar_ipw_score | cvar.mbt:551 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | solve_ipw_root | cvar.mbt:580 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | solve_ipw_root | cvar.mbt:581 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLIIVM::fit_cluster | iivm.mbt:953 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLIIVM::fit_cluster | iivm.mbt:955 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLIIVM::fit_cluster | iivm.mbt:956 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLIIVM::fit_cluster | iivm.mbt:959 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | prelim_beta_per_fold | lplr.mbt:95 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | lplr_score_at | lplr.mbt:199 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | lplr_score_at | lplr.mbt:200 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | newton_solve_score | lplr.mbt:252 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | newton_solve_score | lplr.mbt:253 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | concat_d_x | lplr.mbt:613 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cross_fit_predict_inner | lplr.mbt:1629 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | unit_means | plpr.mbt:123 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | unit_means | plpr.mbt:138 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | unit_means | plpr.mbt:149 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | est_coef_cluster | plpr.mbt:209 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | var_est_cluster | plpr.mbt:269 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | var_est_cluster | plpr.mbt:281 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | var_est_cluster | plpr.mbt:282 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | transform_panel | plpr.mbt:336 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | transform_panel | plpr.mbt:339 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | transform_panel | plpr.mbt:348 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | transform_panel | plpr.mbt:454 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | transform_panel | plpr.mbt:455 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | transform_panel | plpr.mbt:463 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | tune_score_outcome | tune.mbt:191 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | tune_argmin | tune.mbt:217 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | GBClassifier::fit_weighted | gbclf.mbt:189 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | GBClassifier::fit_weighted | gbclf.mbt:208 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | GBClassifier::fit_weighted | gbclf.mbt:209 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | GBClassifier::fit_weighted | gbclf.mbt:273 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | check_sample_splitting | kfold.mbt:294 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | check_sample_splitting | kfold.mbt:312 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | kfold_stratified | kfold.mbt:368 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| DIVISION-BY-ZERO | error | kfold | kfold.mbt:458 | the divisor may be zero, and the runtime turns that into a panic | L2-EVA | 0.7 |
| INDEX-OOB | error | slice_matrix_rows | kfold.mbt:491 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | expand_unit_folds_to_rows | kfold.mbt:557 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | build_row_unit_map | kfold.mbt:592 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | build_row_unit_map | kfold.mbt:595 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cluster_causal_param_and_se | kfold.mbt:654 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | discover_groups_times | did_cs.mbt:91 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | discover_groups_times | did_cs.mbt:93 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | discover_groups_times | did_cs.mbt:94 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | discover_groups_times | did_cs.mbt:116 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | discover_groups_times | did_cs.mbt:118 | abstract interval proves the index is out of bounds | L2-EVA | 0.95 |
| INDEX-OOB | error | discover_groups_times | did_cs.mbt:123 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | discover_groups_times | did_cs.mbt:125 | abstract interval proves the index is out of bounds | L2-EVA | 0.95 |
| INDEX-OOB | error | DoubleMLDIDCS::fit | did_cs.mbt:1487 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDIDCS::fit | did_cs.mbt:1509 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | solve_spd | linalg.mbt:83 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | LinearRegression::fit_weighted | linear.mbt:220 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | LinearRegression::fit_weighted | linear.mbt:222 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | LinearRegression::sandwich_se_weighted | linear.mbt:318 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | LinearRegression::sandwich_se_weighted | linear.mbt:319 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | LinearRegression::sandwich_se | linear.mbt:379 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INTEGER-OVERFLOW | error | Matrix::zeros | matrix.mbt:21 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INTEGER-OVERFLOW | error | Matrix::ones | matrix.mbt:28 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INTEGER-OVERFLOW | error | Matrix::from_array | matrix.mbt:41 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INDEX-OOB | error | Matrix::from_rows | matrix.mbt:113 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | Matrix::from_rows | matrix.mbt:116 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | matvec | matrix.mbt:175 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | matvec_t | matrix.mbt:200 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | dot | matrix.mbt:226 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INTEGER-OVERFLOW | error | make_irm_data | dgp_irm.mbt:49 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INTEGER-OVERFLOW | error | make_irm_data | dgp_irm.mbt:51 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INDEX-OOB | error | make_irm_data | dgp_irm.mbt:71 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_irm_data | dgp_irm.mbt:99 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_irm_data | dgp_irm.mbt:100 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_irm_data | dgp_irm.mbt:106 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INTEGER-OVERFLOW | error | make_ssm_data | dgp_ssm.mbt:46 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INTEGER-OVERFLOW | error | make_ssm_data | dgp_ssm.mbt:48 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INDEX-OOB | error | make_ssm_data | dgp_ssm.mbt:68 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_ssm_data | dgp_ssm.mbt:97 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_ssm_data | dgp_ssm.mbt:98 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_ssm_data | dgp_ssm.mbt:105 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | var_est | var_est.mbt:43 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | var_est_with_jacobian | var_est.mbt:84 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INTEGER-OVERFLOW | error | make_iivm_data | dgp_iivm.mbt:50 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INTEGER-OVERFLOW | error | make_iivm_data | dgp_iivm.mbt:52 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INDEX-OOB | error | make_iivm_data | dgp_iivm.mbt:72 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_iivm_data | dgp_iivm.mbt:106 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_iivm_data | dgp_iivm.mbt:108 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_iivm_data | dgp_iivm.mbt:112 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_lplr_LZZ2020 | dgp_lplr.mbt:59 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_lplr_LZZ2020 | dgp_lplr.mbt:63 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_lplr_LZZ2020 | dgp_lplr.mbt:64 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_lplr_LZZ2020 | dgp_lplr.mbt:65 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_lplr_LZZ2020 | dgp_lplr.mbt:72 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_lplr_LZZ2020 | dgp_lplr.mbt:73 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_lplr_LZZ2020 | dgp_lplr.mbt:74 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_lplr_LZZ2020 | dgp_lplr.mbt:75 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_lplr_LZZ2020 | dgp_lplr.mbt:76 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_lplr_LZZ2020 | dgp_lplr.mbt:77 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_lplr_LZZ2020 | dgp_lplr.mbt:84 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INTEGER-OVERFLOW | error | make_pliv_CHS2015 | dgp_pliv.mbt:36 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INTEGER-OVERFLOW | error | make_pliv_CHS2015 | dgp_pliv.mbt:38 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INDEX-OOB | error | make_pliv_CHS2015 | dgp_pliv.mbt:58 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_pliv_CHS2015 | dgp_pliv.mbt:88 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_pliv_CHS2015 | dgp_pliv.mbt:89 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_pliv_CHS2015 | dgp_pliv.mbt:90 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_pliv_CHS2015 | dgp_pliv.mbt:93 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INTEGER-OVERFLOW | error | make_plpr_CP2025 | dgp_plpr.mbt:53 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INTEGER-OVERFLOW | error | make_plpr_CP2025 | dgp_plpr.mbt:55 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INDEX-OOB | error | make_plpr_CP2025 | dgp_plpr.mbt:74 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_plpr_CP2025 | dgp_plpr.mbt:120 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_plpr_CP2025 | dgp_plpr.mbt:121 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_plpr_CP2025 | dgp_plpr.mbt:124 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_plpr_CP2025 | dgp_plpr.mbt:128 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_plpr_CP2025 | dgp_plpr.mbt:131 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_plpr_CP2025 | dgp_plpr.mbt:132 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | make_plpr_CP2025 | dgp_plpr.mbt:136 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | LogisticRegression::fit | logistic.mbt:168 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | LogisticRegression::fit | logistic.mbt:174 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | LogisticRegression::fit | logistic.mbt:185 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | LogisticRegression::fit | logistic.mbt:194 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | argsort_asc | p_adjust.mbt:99 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | argsort_asc | p_adjust.mbt:100 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | argsort_asc | p_adjust.mbt:101 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| DIVISION-BY-ZERO | error | romano_wolf_p_adjust | p_adjust.mbt:135 | the divisor may be zero, and the runtime turns that into a panic | L2-EVA | 0.7 |
| INDEX-OOB | error | romano_wolf_p_adjust | p_adjust.mbt:145 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | romano_wolf_p_adjust | p_adjust.mbt:152 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | romano_wolf_p_adjust | p_adjust.mbt:153 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | romano_wolf_p_adjust | p_adjust.mbt:154 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | romano_wolf_p_adjust | p_adjust.mbt:176 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | romano_wolf_p_adjust | p_adjust.mbt:183 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | romano_wolf_p_adjust | p_adjust.mbt:197 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | romano_wolf_p_adjust | p_adjust.mbt:198 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | romano_wolf_p_adjust | p_adjust.mbt:204 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | holm_bonferroni_p_adjust | p_adjust.mbt:239 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | holm_bonferroni_p_adjust | p_adjust.mbt:240 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | holm_bonferroni_p_adjust | p_adjust.mbt:246 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | bonferroni_p_adjust | p_adjust.mbt:258 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | bh_fdr_p_adjust | p_adjust.mbt:303 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | bh_fdr_p_adjust | p_adjust.mbt:304 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | bh_fdr_p_adjust | p_adjust.mbt:310 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | by_fdr_p_adjust | p_adjust.mbt:351 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | by_fdr_p_adjust | p_adjust.mbt:352 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | by_fdr_p_adjust | p_adjust.mbt:358 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | bh_step_up_sorted | p_adjust.mbt:399 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | bh_step_up_sorted | p_adjust.mbt:402 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | bh_step_up_sorted | p_adjust.mbt:411 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | bh_step_up_sorted | p_adjust.mbt:412 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | tsbh_p_adjust | p_adjust.mbt:519 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | storey_m0_hat | p_adjust.mbt:548 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | tsby_p_adjust | p_adjust.mbt:633 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | tsby_p_adjust | p_adjust.mbt:639 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | tsby_p_adjust | p_adjust.mbt:640 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | tsby_p_adjust | p_adjust.mbt:646 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | array_min | quantile.mbt:11 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | array_max | quantile.mbt:30 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | pq_score_ipw | quantile.mbt:127 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | pq_score_orthogonal | quantile.mbt:167 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLQTE::fit_cluster | quantile.mbt:1934 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLQTE::cluster_joint_covariance | quantile.mbt:2827 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLQTE::cluster_joint_covariance | quantile.mbt:2828 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLQTE::cluster_joint_covariance | quantile.mbt:2829 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLQTE::cluster_joint_covariance | quantile.mbt:2838 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLQTE::cluster_joint_covariance | quantile.mbt:2853 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | psi_at | sandwich.mbt:226 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | sandwich_variance_hc0 | sandwich.mbt:291 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | sandwich_variance_hc2 | sandwich.mbt:390 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | sandwich_variance_hc3 | sandwich.mbt:438 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cluster_sandwich_variance | sandwich.mbt:550 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cluster_sandwich_variance | sandwich.mbt:562 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cluster_sandwich_variance | sandwich.mbt:563 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cluster_sandwich_variance | sandwich.mbt:569 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | cluster_sandwich_variance | sandwich.mbt:582 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INTEGER-OVERFLOW | error | did_bootstrap_t_stat | bootstrap.mbt:74 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INDEX-OOB | error | did_bootstrap_t_stat | bootstrap.mbt:79 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | did_bootstrap_t_stat | bootstrap.mbt:90 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | did_bootstrap_t_stat | bootstrap.mbt:91 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | expand_gt_keyword | did_multi.mbt:222 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | expand_gt_keyword | did_multi.mbt:233 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLDIDMulti::bootstrap | did_multi.mbt:794 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INTEGER-OVERFLOW | error | draw_bootstrap_weights | did_multi.mbt:1132 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INDEX-OOB | error | build_lzz2020_dgp | lplr_test.mbt:44 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | build_lzz2020_dgp | lplr_test.mbt:49 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | build_lzz2020_dgp | lplr_test.mbt:50 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | build_lzz2020_dgp | lplr_test.mbt:51 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | build_lzz2020_dgp | lplr_test.mbt:61 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | build_lzz2020_dgp | lplr_test.mbt:62 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | build_lzz2020_dgp | lplr_test.mbt:63 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | build_lzz2020_dgp | lplr_test.mbt:64 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | build_lzz2020_dgp | lplr_test.mbt:65 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | build_lzz2020_dgp | lplr_test.mbt:66 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | build_lzz2020_dgp | lplr_test.mbt:73 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INTEGER-OVERFLOW | error | build_panel_dgp | plpr_test.mbt:21 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INTEGER-OVERFLOW | error | build_panel_dgp | plpr_test.mbt:22 | the result may leave the range of its integer type, and MoonBit wraps it silently | L2-EVA | 0.7 |
| INDEX-OOB | error | build_panel_dgp | plpr_test.mbt:42 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | aggregate_coef_se | aggregator.mbt:46 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | aggregate_coef_se | aggregator.mbt:57 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | aggregate_coef_se | aggregator.mbt:60 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLBLP::hac_se | blp_policy.mbt:1128 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLBLP::cluster_hac_se | blp_policy.mbt:1187 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLBLP::cluster_hac_se | blp_policy.mbt:1188 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLBLP::cluster_hac_se | blp_policy.mbt:1189 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLBLP::cluster_hac_se | blp_policy.mbt:1218 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| INDEX-OOB | error | DoubleMLBLP::cluster_hac_se | blp_policy.mbt:1222 | index may be out of bounds on some inputs | L2-EVA | 0.6 |
| ... | ... | ... | ... | (truncated at 300 of 788 rows) | ... | ... |

_This table shows the first 300 of 788 findings, in the order the analysis produced them. The count table above is the whole set, family by family, and every finding -- the 488 not shown here among them -- is in the report's `_findings.jsonl` sidecar._


### 5.4 The global region

MoonBit resolves top-level bindings by DEPENDENCY, not by file order: a global may read a global declared later in the file. The analyzer evaluates the global region once, in dependency order, outside the trials -- so a global's value does not depend on the input the analyzer happened to sample.

A top-level binding is IMMUTABLE in MoonBit: `let mut` at the top level is a parse error, so a global is a constant of the module. The analyzer still leaves a global unknown when the module assigns to it, because the analyzer does not compile the target and cannot know that the assignment is an error.

| Global | Type | Value | Location | State |
| --- | --- | --- | --- | --- |
| `V120_TOL` | Double | 1 | expand_v120_test.mbt:6683 | resolved in dependency order |
| `N_ENET_CASES` | Int32 | 5 | expand_v120_test.mbt:6676 | resolved in dependency order |
| `N_RIDGE_CASES` | Int32 | 3 | expand_v120_test.mbt:6672 | resolved in dependency order |
| `V120_MAX_ITER` | Int32 | 1000000 | expand_v120_test.mbt:6686 | resolved in dependency order |
| `g_cross_fit_count` | Ref[Int32] | ? | quantile.mbt:61 | resolved in dependency order |
| `TUNE_SCORE_FAIL_SENTINEL` | Double | 1.0000000000000002e+300 | tune.mbt:432 | resolved in dependency order |


### 5.5 Where the allocations live

MoonBit has no addresses: there is no pointer type, no address arithmetic and no address space, so a hardware memory model -- frames at fixed addresses, a heap, MMIO registers -- has nothing to model here. What there IS to model is placement. A **global** binding lives in the module's global region. An allocation that does not **escape** the function that made it could live in that function's frame. An allocation that **escapes** -- returned, stored into another object, handed to a call the analyzer cannot see into -- outlives the frame, so it is heap-allocated. A value from **outside** the analysed module has a region the analyzer cannot name.

The classification is STATIC: it is computed over the AST, so it does not depend on which inputs a run sampled.

Allocation sites: 1219 — HEAP 655, FRAME 564.

| Allocation | Kind | Region | Location | Why |
| --- | --- | --- | --- | --- |
| indicator_level | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:252 | returned as the last expression of the function, so it outlives the frame |
| cross_fit_apo | Array.make | **FRAME** — frame (does not escape) | apo.mbt:286 | bound to the local g and never leaves the frame |
| cross_fit_apo | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:287 | passed to a call the analyzer cannot see into, so it may outlive the frame |
| DoubleMLAPO::fit | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:409 | stored into another object, so it outlives the frame |
| DoubleMLAPO::fit | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:410 | stored into another object, so it outlives the frame |
| DoubleMLAPO::fit | Array.make | **FRAME** — frame (does not escape) | apo.mbt:413 | bound to the local fold_ids and never leaves the frame |
| DoubleMLAPO::fit | Array.make | **FRAME** — frame (does not escape) | apo.mbt:475 | bound to the local pa and never leaves the frame |
| DoubleMLAPO::fit_cluster | Array.make | **FRAME** — frame (does not escape) | apo.mbt:579 | bound to the local coefs and never leaves the frame |
| DoubleMLAPO::fit_cluster | Array.make | **FRAME** — frame (does not escape) | apo.mbt:580 | bound to the local ses and never leaves the frame |
| DoubleMLAPO::fit_cluster | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:581 | stored into another object, so it outlives the frame |
| DoubleMLAPO::fit_cluster | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:582 | stored into another object, so it outlives the frame |
| DoubleMLAPO::fit_cluster | Array.make | **FRAME** — frame (does not escape) | apo.mbt:606 | bound to the local pa and never leaves the frame |
| DoubleMLAPO::fit_cluster | Array.make | **FRAME** — frame (does not escape) | apo.mbt:607 | bound to the local pb and never leaves the frame |
| DoubleMLAPO::fit_cluster | Array.make | **FRAME** — frame (does not escape) | apo.mbt:648 | bound to the local pa and never leaves the frame |
| DoubleMLAPO::fit_cluster | Array.make | **FRAME** — frame (does not escape) | apo.mbt:649 | bound to the local pb and never leaves the frame |
| DoubleMLAPO::bootstrap | Array.make | **FRAME** — frame (does not escape) | apo.mbt:930 | bound to the local boot_t_stat_zero and never leaves the frame |
| DoubleMLAPO::bootstrap | array literal | **FRAME** — frame (does not escape) | apo.mbt:940 | bound to the local se_flat and never leaves the frame |
| DoubleMLAPO::sensitivity_nu2_elements | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:1100 | stored into another object, so it outlives the frame |
| DoubleMLAPO::sensitivity_nu2_elements | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:1111 | stored into another object, so it outlives the frame |
| DoubleMLAPO::sensitivity_nu2_elements | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:1112 | stored into another object, so it outlives the frame |
| DoubleMLAPO::sensitivity_nu2_elements | Array.make | **FRAME** — frame (does not escape) | apo.mbt:1119 | bound to the local nu2_score_element and never leaves the frame |
| DoubleMLAPO::sensitivity_analysis | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:1135 | passed to a call the analyzer cannot see into, so it may outlive the frame |
| DoubleMLAPO::sensitivity_analysis_cluster | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:1167 | passed to a call the analyzer cannot see into, so it may outlive the frame |
| DoubleMLAPOS::psi_b_row_at | Array.make | **FRAME** — frame (does not escape) | apo.mbt:1822 | bound to the local row and never leaves the frame |
| DoubleMLAPOS::bootstrap | Array.make | **FRAME** — frame (does not escape) | apo.mbt:2058 | bound to the local per_level and never leaves the frame |
| DoubleMLAPOS::confint | Array.make | **FRAME** — frame (does not escape) | apo.mbt:2108 | bound to the local out and never leaves the frame |
| DoubleMLAPOS::confint | Array.make | **FRAME** — frame (does not escape) | apo.mbt:2116 | bound to the local max_t_arr and never leaves the frame |
| DoubleMLAPOS::causal_contrast | array literal | **HEAP** — heap (escapes the frame) | apo.mbt:2215 | passed to a call the analyzer cannot see into, so it may outlive the frame |
| DoubleMLAPOS::causal_contrast | array literal | **HEAP** — heap (escapes the frame) | apo.mbt:2234 | returned as the last expression of the function, so it outlives the frame |
| DoubleMLAPOS::causal_contrast | array literal | **HEAP** — heap (escapes the frame) | apo.mbt:2237 | passed to a call the analyzer cannot see into, so it may outlive the frame |
| DoubleMLAPOS::sensitivity_analysis | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:2273 | returned as the last expression of the function, so it outlives the frame |
| DoubleMLAPOS::sensitivity_analysis_cluster | Array.make | **HEAP** — heap (escapes the frame) | apo.mbt:2322 | returned as the last expression of the function, so it outlives the frame |
| cross_fit_did | Array.make | **FRAME** — frame (does not escape) | did.mbt:443 | bound to the local g0 and never leaves the frame |
| cross_fit_did | Array.make | **FRAME** — frame (does not escape) | did.mbt:444 | bound to the local g1 and never leaves the frame |
| cross_fit_did | Array.make | **FRAME** — frame (does not escape) | did.mbt:445 | bound to the local m and never leaves the frame |
| DoubleMLDID::fit | Array.make | **HEAP** — heap (escapes the frame) | did.mbt:553 | stored into another object, so it outlives the frame |
| DoubleMLDID::fit | Array.make | **HEAP** — heap (escapes the frame) | did.mbt:554 | stored into another object, so it outlives the frame |
| DoubleMLDID::fit | Array.make | **HEAP** — heap (escapes the frame) | did.mbt:555 | stored into another object, so it outlives the frame |
| DoubleMLDID::fit | array literal | **FRAME** — frame (does not escape) | did.mbt:556 | bound to the local fold_ids and never leaves the frame |
| DoubleMLDID::fit | Array.make | **HEAP** — heap (escapes the frame) | did.mbt:612 | stored into another object, so it outlives the frame |

_Showing the first 40 of 1219 allocation sites._


#### 5.5.1 A collection that only grows

MoonBit's type system makes the MEMORY-LEAK class inexpressible in safe code: there is no `free`, and every allocation is the garbage collector's business. One shape survives that, and this check reports it. A **module-level** collection -- a top-level `let`, which lives for as long as the module does -- that is only ever **added** to: nothing in the module ever removes an element from it, and nothing ever replaces it with a fresh one; and that is added to inside a **loop whose trip count the analyzer cannot bound**. The loop can run any number of times, every iteration adds an element, and nothing ever takes one away, so the collection grows without bound.

What is NOT claimed: a collection filled once at start-up, or once per call -- the analyzer cannot see how often the module is called; a collection that is trimmed somewhere; and a **local** collection, which dies with the function that made it.

_No collection grows without bound._


### 5.6 Layout stability: does the conclusion depend on the run?

_The stability self-check was not run._ Pass `--stability` to re-sample the analysis and compare the findings.


### 5.7 The foreign address space

MoonBit has no pointer type, no address arithmetic and no address space: nothing in the language IS an address. The C boundary is where an address appears, and it appears on the **other** side of it. There are two spaces here, and the analysis is about the boundary between them: the **MoonBit** space (the reference-counted heap, the global region, the frame) and the **foreign** space (what the C code owns, plus the payload of an `#external` object).

Every claim below rests on a measurement against the toolchain, not on a reading of a document. `extern "C" fn name(args) -> Ret = "c_symbol"` is the only C form and the `= "c_symbol"` part is required; the wasm backend REJECTS `extern "C"` (E4156) and native REJECTS a module import, so the two forms are not interchangeable; a `String` crosses as `uint16_t *` and a `Bytes` as `uint8_t *`, so the C side receives the ADDRESS of a MoonBit heap object while the scalars cross by value; the toolchain refuses a pointer-typed parameter without an ownership annotation (E0055) and says the current default will change; and the toolchain does NOT enforce that annotation and does NOT notice two declarations claiming the same C symbol with different signatures -- those last two are this analyzer's own checks.

_This module declares no foreign function._ There is no C boundary to model, and no address space on the other side of it.


### 5.8 Concurrency: the tasks and the shared state

MoonBit tasks do **NOT** run MoonBit code on several OS threads. That was measured, not assumed: a spin-lock whose spin loop contains no `await` HANGS -- the spinner printed its marker and the second task never printed at all, because it never got to run. The runtime's thread pool (`max_worker_count = 1024` by default) executes the BLOCKING I/O; the coroutine waits on the event-loop thread.

So a task yields ONLY at an await point, and an await point is where another task may run. That makes the defect class here **interleaving sensitivity**, not a thread-level data race: a read-modify-write with no await inside it loses nothing (measured: 8 tasks x 200 000 increments = exactly 1 600 000 counted), while a read-AWAIT-write over a shared `Ref[Int]` lost 21 000 of 24 000 updates -- the SAME interleaving every run. The space is finite and reproducible, so a conflict can be FOUND rather than waited for.

_This module spawns no task._ There is no concurrency to model: no closure is handed to a spawn API.


### 5.9 IPC and buffers: the reads that can come back short

MoonBit's own IPC -- sockets, pipes and process stdio -- goes through the core's `BinaryReader` and `BinaryWriter` traits, and those traits have a contract. The defect classes here are the ways a program can break that contract, and every one of them was MEASURED against the core rather than read off a documentation page:

- **A read can come back SHORT.** `read_into(dst)` returns the number of bytes it read, and that number can be smaller than the buffer. Measured: a 16-byte buffer pre-filled with `0xFF`, a pipe with 3 bytes in it, one `read_into` -> returned **3**, and the buffer afterwards was `61 62 63 FF FF FF ... FF`. The bytes past the count were never written: they still held what the buffer held before. The count is the only thing that says so, and a program that discards it cannot tell a short read from a full one.
- **The offset is the caller's job.** Measured: `read_into(buf, offset=8)` returned 3 and wrote at `buf[8..11]`; `buf[0..8)` was untouched. Nothing advances the offset for you.
- **EOF is zero.** Measured: at the end of the stream `read_into` returns **0** and `read()` returns **None**. So 0 is both "no progress" and "the stream ended", and a loop that discards the count cannot tell them apart.
- **A peeked view goes stale.** The core says it outright -- "the caller of `peek` MUST NOT use the returned slice after any other `BinaryReader` operation is invoked on the same reader" -- because the reader keeps ONE buffer and reuses it. Measured: peeked `61 62 63`; after two `read()` calls the SAME view read `78 79 7A`.
- **A pending write is not a snapshot.** Measured: a 4-byte buffer of 'A' handed to `write`, then overwritten with 'B' while the write was still pending -> the reader received `42 42 42 42`, the 'B's, not the 'A's that were in the buffer when the write was issued.
- **A `peek` is a view only when the value is used AS ONE.** `peek` is a common name -- a parser has one and it returns a token -- so the name alone cannot decide. The analyzer requires evidence: the value is passed to a `BytesView` parameter, handed to the core's writer, or copied with a method only a view has. A peek whose result is only matched on is not a view, and is not reported.

One thing the measurement REFUSED to support: `write` is **exhaustive**. It loops until every byte has been handed over -- measured, 5 bytes written and read 2 at a time -> 5 bytes in 3 reads -- so there is no partial-write defect at the `write` level, and this model does not claim one.

#### 5.9.1 The calls on the readers and writers

_No call on a reader or a writer._

#### 5.9.2 The views that went stale

_No stale view._

#### 5.9.3 The buffers two sides write

_No shared buffer._

#### 5.9.4 What this model does NOT cover

The model is sound about what it reports and silent about the rest, so here is exactly what it does not model:

- **A reader the analyzer does not recognise by name.** The analyzer matches the METHOD NAME, because it does not infer types: a reader of your own with a method called `read_into` is treated as the core's reader. A reader with a different method name is not seen at all.
- **A peek whose use as a view is invisible.** A `peek` is only treated as a view when the analyzer can SEE the value used as one -- passed to a `BytesView` parameter, handed to the core's writer, or copied with a method only a view has. A value that is only matched on is not a view. That is deliberate: the analyzer's own source has FOUR `peek` results that are only matched on, and matching the name alone reported them THIRTEEN times.
- **A length that comes from the stream.** A length read off the wire and used to size an allocation is a real defect, and it is not judged here: the taint families (§5.4) are where a source has to be declared for that to be checkable. This model judges the LENGTH ARGUMENT AT THE C BOUNDARY (§5.7), not a length that came in over the socket.
- **A buffer reached through a field, a container or an array.** The shared buffers are the ones a task body CAPTURES by name. A buffer stored in a struct field or in a collection is not tracked.
- **A use of a view that was copied.** `to_owned()` makes a copy, and a copy is not a view: the model only reports the view itself.
- **A count that is used but an offset that is not advanced.** `read_into(buf, offset=k)` does not move `k` for you (measured). The model reports a DISCARDED count; a count that is used but an offset that is not advanced is not judged.
- **The C side of a socket.** What arrives is whatever the peer sent. §5.7 says the same about the other side of a C boundary.

_No findings._

## 6. Value ranges

Ranges are the union of concrete samples across synthesized input trials. They are *observed* intervals, not abstract-interpretation fixpoints: a missing input can hide a wider interval.

### 6.1 Per-program-point observations

Every definition event is keyed by function, source line and variable, so a value can be inspected at the exact program point that produced it (the full stream is in the JSONL trace).

| Function | Line | Variable | Observed values |
| --- | --- | --- | --- |
| iqr | 51 | n | 0, 1, 3, 2 |
| iqr | 57 | q1 | 0, () |
| iqr | 58 | q3 | 0, () |
| mean | 249 | s | 0 |
| mean | 250 | c | 0 |
| mean | 252 | y | 0, 1.5 |
| mean | 253 | t | 0, 1.5, 3, 4.5, 6, 7.5 |
| mean | 254 | c | 0 |
| mean | 255 | s | 0, 1.5, 3, 4.5, 6, 7.5 |
| kfold | 455 | j | ? |
| psi_at | 223 | n | ? |
| iqr | 55 | sorted | [0], [0, 1.5, -2], [1.5, 0] |
| kfold | 451 | rng | ? |
| kfold | 459 | rem | ? |
| predict | 250 | n | ? |
| clip_vec | 328 | n | ?, 0 |
| clip_vec | 331 | x | ? |
| kfold | 453 | perm | ? |
| kfold | 458 | base | ? |
| lpq_score | 51 | a | ? |
| norm_cdf | 688 | t | ? |
| psi_at | 224 | psi | ? |
| sample_sd | 33 | n | 0, 1, 3, 2 |
| sample_sd | 37 | m | () |
| sample_sd | 40 | d | ? |
| kfold | 450 | bytes | () |
| kfold | 460 | folds | [] |
| lpq_score | 50 | iy | ? |
| norm_cdf | 682 | b1 | 0.31938153 |
| norm_cdf | 683 | b2 | -0.356563782 |
| norm_cdf | 684 | b3 | 1.781477937 |
| norm_cdf | 685 | b4 | -1.821255978 |
| norm_cdf | 686 | b5 | 1.330274429 |
| norm_ppf | 714 | lo | -8 |
| norm_ppf | 715 | hi | 8 |
| norm_ppf | 721 | lo | 0 |
| norm_ppf | 723 | hi | 0 |
| predict | 251 | out | ? |
| clip_vec | 329 | out | ?, [] |
| kfold | 461 | offset | 0 |
| kfold | 475 | offset | ? |
| lpq_score | 48 | out | ? |
| norm_cdf | 689 | phi | ? |
| norm_ppf | 716 | mid | 0 |
| norm_ppf | 718 | mid | 0 |
| sample_sd | 38 | acc | 0 |
| sample_sd | 41 | acc | ? |
| gaussian_kde | 90 | n | 0 |
| norm_cdf | 690 | poly | ? |
| kfold | 464 | test_idx | [] |
| lpq_score_ipw | 80 | w | ? |
| norm_cdf | 687 | abs_x | ? |
| seed_to_bytes | 38 | b | ? |
| unique_units | 175 | g | ? |
| cross_fit_apo | 285 | n | ? |
| cross_fit_apo | 286 | g | ? |
| cross_fit_apo | 287 | m | ? |
| cross_fit_apo | 293 | p | () |
| cross_fit_did | 445 | m | ? |
| cross_fit_did | 452 | p | () |
| cross_fit_did | 461 | p | () |
| cross_fit_did | 469 | p | () |
| cross_fit_irm | 365 | m | ? |
| gaussian_kde | 95 | acc | 0 |
| kfold | 463 | test_size | ? |
| kfold | 468 | train_idx | [] |
| lpq_score_ipw | 79 | iy | ? |
| norm_cdf | 681 | p_coef | 0.2316419 |
| normalize_ipw | 914 | n | ? |
| predict | 252 | n_trees | ? |
| seed_to_bytes | 26 | b0 | ? |
| seed_to_bytes | 27 | b1 | ? |
| seed_to_bytes | 28 | b2 | ? |
| seed_to_bytes | 29 | b3 | ? |
| cross_fit_apo | 289 | tr | ? |
| cross_fit_apo | 290 | te | ? |
| cross_fit_apo | 291 | tg | () |
| cross_fit_did | 443 | g0 | ? |
| cross_fit_did | 444 | g1 | ? |
| cross_fit_irm | 363 | g0 | ? |
| cross_fit_irm | 364 | g1 | ? |
| cross_fit_irm | 380 | p0 | () |
| cross_fit_irm | 395 | p1 | () |
| cross_fit_irm | 404 | pm | () |
| filter_indices | 316 | i | 0 |
| lpq_score_ipw | 77 | out | ? |
| norm_cdf | 691 | phi_pos | ? |
| norm_ppf | 719 | cdf_mid | () |
| normalize_ipw | 929 | om | ? |
| normalize_ipw | 942 | w1 | ? |
| normalize_ipw | 943 | w0 | ? |
| vector_subtract | 79 | n | ? |
| cross_fit_did | 456 | row | ? |
| cross_fit_did | 465 | row | ? |
| cross_fit_did | 473 | row | ? |
| cross_fit_irm | 384 | row | ? |
| cross_fit_irm | 399 | row | ? |
| cross_fit_irm | 408 | row | ? |
| gaussian_kde | 93 | inv_h | ?, 1, -0.6666666666666666, 0.0009765625 |
| normalize_ipw | 940 | out | ? |
| tune_score_grid | 286 | n | ? |
| unique_units | 173 | uniq | [] |
| <global> | 6683 | V120_TOL | 1 |
| DoubleMLDID::fit | 494 | n | ? |
| DoubleMLLPQ::fit | 238 | n | ? |
| aggregate_coef_se | 48 | n | 0 |
| cross_fit_apo | 288 | fold | 0, 1 |
| cross_fit_did | 446 | fold | 0 |
| cross_fit_irm | 366 | fold | 0, 1, -1 |
| filter_indices | 315 | out | [] |
| percentile_sorted | 66 | n | 1, 3, 2, 0 |
| seed_to_bytes | 30 | bytes | [] |
| unique_units | 176 | found | false |
| unique_units | 179 | found | true |
| vector_subtract | 81 | out | ? |
| DoubleMLLPQ::fit | 240 | nf | ? |
| DoubleMLLPQ::fit | 275 | tr | () |
| aggregate_coef_se | 55 | ub | [] |
| cross_fit_did | 442 | n_obs | ? |
| cross_fit_irm | 362 | n_obs | ? |
| filter_by_value | 405 | out | [] |
| indicator_level | 252 | out | [], [0], ? |
| indicator_level | 254 | out | [?] |
| percentile_sorted | 74 | lo | ? |
| percentile_sorted | 75 | hi | ? |
| slice_matrix_rows | 488 | n | ? |
| build_row_unit_map | 588 | n | ? |
| build_row_unit_map | 592 | g | ? |
| gaussian_kde | 94 | inv_norm | ?, 0.3989422804014327, -0.2659615202676218, 0.00038959207... |
| normalize_ipw | 915 | m_clip | () |
| normalize_ipw | 932 | sum_t1 | 0 |
| normalize_ipw | 933 | sum_t0 | 0 |
| normalize_ipw | 935 | sum_t1 | ? |
| normalize_ipw | 936 | sum_t0 | ? |
| silverman_bandwidth | 16 | n | 0, 1, 3, 2 |
| DoubleMLDID::fit | 501 | nrep | ? |
| normalize_ipw | 927 | om_clip | ? |
| normalize_ipw | 938 | mean_t1 | ? |
| normalize_ipw | 939 | mean_t0 | ? |
| percentile_sorted | 73 | rank | ? |
| percentile_sorted | 76 | frac | ? |
| silverman_bandwidth | 18 | sd | 0, () |
| slice_matrix_rows | 489 | out | ? |
| slice_matrix_rows | 491 | row | ? |
| <global> | 6676 | N_ENET_CASES | 5 |
| DoubleMLAPO::tune | 993 | grid | () |
| DoubleMLDID::confint | 377 | z | () |
| DoubleMLDID::fit | 555 | m_acc | ? |
| DoubleMLIRM::confint | 217 | z | () |
| DoubleMLLPQ::confint | 664 | z | ? |
| DoubleMLLPQ::fit | 276 | folds | () |
| cross_fit_did | 448 | test_idx | ? |
| cross_fit_did | 449 | train_d0 | () |
| cross_fit_did | 450 | train_d1 | () |
| cross_fit_irm | 368 | test_idx | ? |
| cross_fit_irm | 373 | train_d0 | [] |
| silverman_bandwidth | 21 | n_d | ? |
| <global> | 6672 | N_RIDGE_CASES | 3 |
| <global> | 6686 | V120_MAX_ITER | 1000000 |
| DoubleMLDID::confint | 378 | lo | ? |
| DoubleMLDID::confint | 379 | hi | ? |
| DoubleMLDID::fit | 553 | g0_acc | ? |
| DoubleMLDID::fit | 554 | g1_acc | ? |
| DoubleMLDID::tune | 1207 | grid | () |
| DoubleMLIRM::confint | 218 | lo | ? |
| DoubleMLIRM::confint | 219 | hi | ? |
| DoubleMLIRM::tune | 1031 | grid | () |
| aggregate_coef_se | 60 | ub_hat | ? |
| aggregate_coef_se | 61 | se_hat | ? |
| cross_fit_apo | 321 | m_clipped | ? |
| cross_fit_did | 447 | train_idx | ? |
| cross_fit_did | 477 | m_clipped | () |
| cross_fit_irm | 367 | train_idx | ? |
| cross_fit_irm | 428 | m_clipped | ? |
| gaussian_kde_weighted | 132 | n | 0 |
| DoubleMLAPO::bootstrap | 907 | n | ? |
| DoubleMLAPOS::confint | 2106 | z | () |
| DoubleMLAPOS::confint | 2121 | t | ? |
| DoubleMLAPOS::fit | 1392 | n_obs | ? |
| DoubleMLAPOS::tune | 1036 | grid | () |
| DoubleMLDID::fit | 515 | memoize | true |
| DoubleMLIRM::bootstrap | 947 | n | ? |
| DoubleMLLPQ::fit | 244 | memoize | ? |
| build_row_unit_map | 593 | found | false |
| build_row_unit_map | 597 | found | true |
| single_psi_sensitivity | 496 | n | ? |
| <global> | 61 | g_cross_fit_count | ? |
| DoubleMLAPO::tune | 987 | scoring | ? |
| DoubleMLAPOS::confint | 2118 | mx | 0 |
| DoubleMLAPOS::confint | 2124 | mx | ? |
| DoubleMLDID::fit | 500 | external | ? |
| DoubleMLDID::fit | 556 | fold_ids | [] |
| draw_bootstrap_weights | 1136 | w | ? |
| gaussian_kde_weighted | 138 | acc | 0 |
| silverman_bandwidth | 20 | spread | ? |
| single_psi_sensitivity | 510 | dy | ? |
| single_psi_sensitivity | 528 | rv | 1.0000000000000002e+300 |
| DoubleMLAPO::fit_cluster | 558 | n | ? |
| DoubleMLAPO::fit_cluster | 581 | g | ? |
| DoubleMLAPO::fit_cluster | 582 | m | ? |
| DoubleMLAPO::sandwich_se | 772 | n | ? |
| DoubleMLAPOS::confint | 2108 | out | ? |
| DoubleMLAPOS::fit | 1420 | memoize | true |
| DoubleMLDID::fit | 516 | data_hash | ? |
| DoubleMLDID::fit | 542 | cache_hit | true |
| DoubleMLDID::tune | 1206 | scoring | ? |
| DoubleMLIRM::fit_cluster | 739 | n | ? |
| DoubleMLIRM::fit_cluster | 766 | m | ? |
| DoubleMLIRM::tune | 1025 | scoring | ? |
| DoubleMLLPQ::fit | 245 | data_hash | ? |
| DoubleMLLPQ::fit | 264 | cache_hit | true |
| aggregate_coef_se | 53 | theta_hat | ? |
| build_row_unit_map | 589 | n_units | ? |
| check_sample_splitting | 296 | rep | 0, 1, -1 |
| compute_sensitivity_bias | 574 | n | ? |
| single_psi_sensitivity | 499 | n_d | ? |
| single_psi_sensitivity | 506 | nu2 | ? |
| tune_score_grid | 287 | folds_tune | () |
| DoubleMLAPOS::fit | 1393 | n_levels | ? |
| DoubleMLAPOS::tune | 1035 | scoring | ? |
| DoubleMLDID::sandwich_se | 1033 | n | ? |
| DoubleMLIRM::fit_cluster | 764 | g0 | ? |
| DoubleMLIRM::fit_cluster | 765 | g1 | ? |
| DoubleMLIRM::sandwich_se | 1203 | n | ? |
| build_row_unit_map | 590 | row_unit | ? |
| check_sample_splitting | 300 | seen | ? |
| cluster_sandwich_variance | 546 | n | ? |
| cluster_sandwich_variance | 550 | c | ?, 0, 1 |
| cluster_sandwich_variance | 562 | c | ?, 0, 1 |
| cluster_sandwich_variance | 584 | y | ? |
| cluster_sandwich_variance | 585 | t | ? |
| cluster_sandwich_variance | 589 | m | ? |
| cross_fit_irm | 388 | train_d1_only | [] |
| draw_bootstrap_weights | 1132 | out | ? |
| draw_bootstrap_weights | 1133 | rng | () |
| gaussian_kde_weighted | 136 | inv_h | ?, 1, -0.6666666666666666, 0.0009765625 |
| generic_bootstrap_t_stat | 71 | psi | () |
| generic_bootstrap_t_stat | 77 | n_d | ? |
| DoubleMLAPO::fit_cluster | 580 | ses | ? |
| DoubleMLAPO::sandwich_se | 774 | psi | () |
| DoubleMLAPOS::confint | 2105 | alpha | ? |
| DoubleMLAPOS::confint | 2122 | abs_t | ? |
| DoubleMLAPOS::fit | 1423 | data_hash | ? |
| DoubleMLAPOS::fit | 1459 | cache_hit | true |
| DoubleMLIRM::fit_cluster | 763 | ses | ? |
| cluster_sandwich_variance | 569 | nc | ?, 64, 0 |
| cluster_sandwich_variance | 582 | sc | ? |
| cluster_sandwich_variance | 590 | m2 | ? |
| single_psi_sensitivity | 501 | y_sum | 0 |
| single_psi_sensitivity | 504 | y_sum | ? |
| single_psi_sensitivity | 507 | y_bar | ? |
| DoubleMLAPO::fit_cluster | 559 | nrep | ? |
| DoubleMLAPO::fit_cluster | 560 | uniq | () |
| DoubleMLAPO::fit_cluster | 585 | se_r | 0 |
| DoubleMLAPOS::confint | 2115 | n_boot | ? |
| DoubleMLAPOS::fit | 1589 | next_cache | ? |
| DoubleMLDID::fit | 525 | hparams_hash | ? |
| DoubleMLDID::fit | 536 | cluster_hash | ? |
| DoubleMLDID::sandwich_se | 1034 | psi | () |
| DoubleMLIRM::fit_cluster | 740 | nrep | ? |
| DoubleMLIRM::fit_cluster | 741 | uniq | () |
| DoubleMLIRM::fit_cluster | 773 | se_r | 0 |
| DoubleMLIRM::sandwich_se | 1206 | psi | () |
| DoubleMLLPQ::fit | 252 | hparams_hash | ? |
| DoubleMLLPQ::fit | 263 | cluster_hash | ? |
| GBLearner::fit_weighted | 142 | n_obs | ? |
| GBLearner::fit_weighted | 144 | sum_y | 0 |
| GBLearner::fit_weighted | 146 | sum_y | ?, 0 |
| GBLearner::fit_weighted | 151 | trees | [] |
| GBLearner::fit_weighted | 178 | x_sub | ? |
| aggregate_coef_se | 51 | coefs_sorted | [] |
| cluster_sandwich_variance | 566 | acc | 0 |
| cluster_sandwich_variance | 587 | acc | ? |
| cluster_sandwich_variance | 591 | n_d | ? |
| generic_bootstrap_t_stat | 55 | n_obs | ? |
| generic_bootstrap_t_stat | 74 | psi_i | ? |
| single_psi_sensitivity | 513 | sigma2 | ? |
| single_psi_sensitivity | 523 | mb_sum | 0 |
| DoubleMLAPO::bootstrap | 909 | weights | () |
| DoubleMLAPO::fit_cluster | 579 | coefs | ? |
| DoubleMLAPO::sandwich_se | 777 | m_inv | ? |
| DoubleMLAPOS::bootstrap | 2060 | child | ? |
| DoubleMLDID::fit | 558 | _destructured | ? |
| DoubleMLIRM::bootstrap | 949 | weights | () |
| DoubleMLIRM::fit_cluster | 762 | coefs | ? |
| DoubleMLIRM::fit_cluster | 767 | m_raw | ? |
| check_sample_splitting | 294 | n_folds | ? |
| cluster_sandwich_variance | 583 | term | ? |
| compute_sensitivity_bias | 580 | zeros | ? |
| gaussian_kde_weighted | 137 | inv_norm | ?, 0.3989422804014327, -0.2659615202676218, 0.00038959207... |
| generic_bootstrap_single_psi | 113 | v | ? |
| generic_bootstrap_t_stat | 72 | ss_psi | 0 |
| generic_bootstrap_t_stat | 75 | ss_psi | ? |
| generic_bootstrap_t_stat | 78 | se_psi | ? |
| single_psi_sensitivity | 500 | nu2_sum | 0 |
| single_psi_sensitivity | 503 | nu2_sum | ? |
| single_psi_sensitivity | 515 | psi_nu2 | ? |
| DoubleMLAPO::sandwich_se | 775 | mean_a | 0 |
| DoubleMLAPOS::bootstrap | 2073 | booted | ? |
| DoubleMLAPOS::confint | 2107 | n_levels | ? |
| ... | ... | ... | (truncated at 300 rows) |

### 6.2 Function-level range union (L1)

| Function | Variable | Min | Max | Samples | Observed values | First site |
| --- | --- | --- | --- | --- | --- | --- |
| iqr | n | 0 | 3 | 8 | 0, 1, 3, 2 | kde.mbt:51:3 |
| iqr | q1 | 0 | 0 | 2 | 0 | kde.mbt:57:3 |
| iqr | q3 | 0 | 0 | 2 | 0 | kde.mbt:58:3 |
| mean | c | 0 | 0 | 260 | 0 | matrix.mbt:250:3 |
| mean | s | 0 | 96 | 260 | 0, 1.5, 3, 4.5, 6, 7.5, 9, 10.5, 12, 13.5, 15... | matrix.mbt:249:3 |
| mean | t | 0 | 96 | 256 | 0, 1.5, 3, 4.5, 6, 7.5, 9, 10.5, 12, 13.5, 15... | matrix.mbt:253:5 |
| mean | y | 0 | 1.5 | 256 | 0, 1.5 | matrix.mbt:252:5 |
| iqr | <ret> | 0 | 0 | 2 | 0 | kde.mbt:50:1-60:2 |
| clip_vec | n | 0 | 0 | 8 | 0 | irm.mbt:328:3 |
| norm_cdf | b1 | 0.31938153 | 0.31938153 | 1536 | 0.31938153 | did_cross_section.mbt:682:3 |
| norm_cdf | b2 | -0.356563782 | -0.356563782 | 1536 | -0.356563782 | did_cross_section.mbt:683:3 |
| norm_cdf | b3 | 1.781477937 | 1.781477937 | 1536 | 1.781477937 | did_cross_section.mbt:684:3 |
| norm_cdf | b4 | -1.821255978 | -1.821255978 | 1536 | -1.821255978 | did_cross_section.mbt:685:3 |
| norm_cdf | b5 | 1.330274429 | 1.330274429 | 1536 | 1.330274429 | did_cross_section.mbt:686:3 |
| norm_ppf | hi | 0 | 8 | 1560 | 8, 0 | did_cross_section.mbt:715:5 |
| norm_ppf | lo | -8 | 0 | 1560 | -8, 0 | did_cross_section.mbt:714:5 |
| sample_sd | n | 0 | 3 | 8 | 0, 1, 3, 2 | kde.mbt:33:3 |
| kfold | offset | 0 | 0 | 52 | 0 | kfold.mbt:461:5 |
| norm_ppf | mid | 0 | 0 | 1560 | 0 | did_cross_section.mbt:716:5 |
| sample_sd | acc | 0 | 0 | 4 | 0 | kde.mbt:38:3 |
| gaussian_kde | n | 0 | 0 | 8 | 0 | kde.mbt:90:5 |
| norm_cdf | p_coef | 0.2316419 | 0.2316419 | 1536 | 0.2316419 | did_cross_section.mbt:681:3 |
| sample_sd | <ret> | 0 | 0 | 2 | 0 | kde.mbt:32:1-44:2 |
| filter_indices | i | 0 | 0 | 4 | 0 | irm.mbt:316:3-320:4 |
| gaussian_kde | acc | 0 | 0 | 8 | 0 | kde.mbt:95:5 |
| cross_fit_apo | fold | 0 | 1 | 6 | 0, 1 | apo.mbt:288:3-312:4 |
| cross_fit_did | fold | 0 | 0 | 4 | 0 | did.mbt:446:3-476:4 |
| cross_fit_irm | fold | -1 | 1 | 12 | 0, 1, -1 | irm.mbt:366:5-411:6 |
| gaussian_kde | inv_h | -0.6666666666666666 | 1 | 6 | 1, -0.6666666666666666, 0.0009765625 | kde.mbt:93:5 |
| unique_units | found | 0 | 1 | 2032 | false, true | plpr.mbt:176:5 |
| aggregate_coef_se | n | 0 | 0 | 4 | 0 | aggregator.mbt:48:5 |
| percentile_sorted | n | 0 | 3 | 20 | 1, 3, 2, 0 | kde.mbt:66:3 |
| normalize_ipw | sum_t0 | 0 | 0 | 6 | 0 | ps_processor.mbt:933:3 |
| normalize_ipw | sum_t1 | 0 | 0 | 6 | 0 | ps_processor.mbt:932:3 |
| gaussian_kde | inv_norm | -0.2659615202676218 | 0.3989422804014327 | 6 | 0.3989422804014327, -0.2659615202676218, 0.00... | kde.mbt:94:5 |
| silverman_bandwidth | n | 0 | 3 | 4 | 0, 1, 3, 2 | kde.mbt:16:5 |
| silverman_bandwidth | sd | 0 | 0 | 2 | 0 | kde.mbt:18:5 |
| gaussian_kde_weighted | n | 0 | 0 | 8 | 0 | kde.mbt:132:5 |
| percentile_sorted | <ret> | 0 | 0 | 8 | 0 | kde.mbt:65:1-78:2 |
| DoubleMLAPOS | confint | 0 | 0 | 24 | 0 |  |
| DoubleMLDID | fit | 1 | 1 | 4 | true |  |
| build_row_unit_map | found | 0 | 1 | 2048 | false, true | kfold.mbt:593:5 |
| DoubleMLAPOS | fit | 1 | 1 | 4 | true |  |
| gaussian_kde_weighted | acc | 0 | 0 | 8 | 0 | kde.mbt:138:5 |
| single_psi_sensitivity | rv | 1.0000000000000002e+300 | 1.0000000000000002e+300 | 8 | 1.0000000000000002e+300 | sensitivity.mbt:528:3 |
| DoubleMLDID | fit | 1 | 1 | 4 | true |  |
| DoubleMLLPQ | fit | 1 | 1 | 4 | true |  |
| check_sample_splitting | rep | -1 | 1 | 48 | 0, 1, -1 | kfold.mbt:296:3-314:4 |
| DoubleMLAPOS | fit | 1 | 1 | 4 | true |  |
| cluster_sandwich_variance | c | 0 | 1 | 3072 | 0, 1 | sandwich.mbt:550:7 |
| gaussian_kde_weighted | inv_h | -0.6666666666666666 | 1 | 6 | 1, -0.6666666666666666, 0.0009765625 | kde.mbt:136:5 |
| cluster_sandwich_variance | nc | 0 | 64 | 1536 | 64, 0 | sandwich.mbt:569:7 |
| single_psi_sensitivity | y_sum | 0 | 0 | 8 | 0 | sensitivity.mbt:501:3 |
| DoubleMLAPO | fit_cluster | 0 | 0 | 8 | 0 |  |
| DoubleMLIRM | fit_cluster | 0 | 0 | 8 | 0 |  |
| GBLearner | fit_weighted | 0 | 0 | 264 | 0 |  |
| cluster_sandwich_variance | acc | 0 | 0 | 32 | 0 | sandwich.mbt:566:5 |
| single_psi_sensitivity | mb_sum | 0 | 0 | 8 | 0 | sensitivity.mbt:523:3 |
| gaussian_kde_weighted | inv_norm | -0.2659615202676218 | 0.3989422804014327 | 6 | 0.3989422804014327, -0.2659615202676218, 0.00... | kde.mbt:137:5 |
| single_psi_sensitivity | nu2_sum | 0 | 0 | 8 | 0 | sensitivity.mbt:500:3 |
| DoubleMLAPO | sandwich_se | 0 | 0 | 4 | 0 |  |
| DoubleMLDID | sandwich_se | 0 | 0 | 4 | 0 |  |
| DoubleMLIRM | sandwich_se | 0 | 0 | 4 | 0 |  |
| cluster_sandwich_variance | acc_c | 0 | 0 | 32 | 0 | sandwich.mbt:567:5 |
| generic_bootstrap_t_stat | ss_psi | 0 | 0 | 8 | 0 | bootstrap_helper.mbt:72:3 |
| DoubleMLAPO | fit_cluster | 0 | 0 | 8 | 0 |  |
| DoubleMLAPO | fit_cluster | 0 | 0 | 8 | 0 |  |
| DoubleMLIRM | fit_cluster | 0 | 0 | 8 | 0 |  |
| DoubleMLIRM | fit_cluster | 0 | 0 | 8 | 0 |  |
| irm_style_sensitivity_cluster | rv | 1.0000000000000002e+300 | 1.0000000000000002e+300 | 8 | 1.0000000000000002e+300 | sensitivity.mbt:389:3 |
| silverman_bandwidth | iqr_over_134 | 0 | 0 | 1 | 0 | kde.mbt:19:5 |
| DoubleMLAPOS | m_inv_1x1_at | 0 | 0 | 8 | 0 |  |
| cluster_sandwich_variance | max_cid | -1 | 1 | 56 | -1, 0, 1 | sandwich.mbt:548:5 |
| single_psi_sensitivity | sigma2_sum | 0 | 0 | 8 | 0 | sensitivity.mbt:508:3 |
| DoubleMLAPO | fit_cluster | 0 | 0 | 8 | false |  |
| DoubleMLIRM | fit_cluster | 0 | 0 | 8 | false |  |
| DoubleMLAPOS | causal_contrast | 0 | 1 | 768 | false, true |  |
| generic_bootstrap_single_psi | ss_psi | 0 | 0 | 8 | 0 | bootstrap_helper.mbt:111:3 |
| cluster_sandwich_variance | n_clusters | 1 | 2 | 24 | 1, 2 | sandwich.mbt:557:5 |
| irm_style_sensitivity_cluster | mb_sum | 0 | 0 | 8 | 0 | sensitivity.mbt:384:3 |
| DoubleMLAPOS | causal_contrast | 0 | 0 | 72 | 0 |  |
| DoubleMLAPOS | causal_contrast | 0 | 1.5 | 384 | 0, 1.5 |  |
| irm_style_sensitivity_cluster | max_cid | -1 | -1 | 8 | -1 | sensitivity.mbt:337:3 |
| irm_style_sensitivity_cluster | ss_psi_a | 0 | 0 | 8 | 0 | sensitivity.mbt:364:3 |
| irm_style_sensitivity_cluster | ss_resid | 0 | 0 | 8 | 0 | sensitivity.mbt:363:3 |
| irm_style_sensitivity_from_elements | rv | 1.0000000000000002e+300 | 1.0000000000000002e+300 | 24 | 1.0000000000000002e+300 | sensitivity.mbt:125:3 |
| DoubleMLAPO | cluster_sandwich_se | 0 | 0 | 8 | 0 |  |
| DoubleMLDID | cluster_sandwich_se | 0 | 0 | 8 | 0 |  |
| DoubleMLIRM | cluster_sandwich_se | 0 | 0 | 8 | 0 |  |
| irm_style_sensitivity_from_elements | nu2 | 0 | 0 | 24 | 0 | sensitivity.mbt:115:5 |
| irm_style_sensitivity_from_elements | mb_sum | 0 | 0 | 24 | 0 | sensitivity.mbt:120:3 |
| irm_style_sensitivity_from_elements | ss_nu2 | 0 | 0 | 24 | 0 | sensitivity.mbt:92:3 |
| DoubleMLDID | sensitivity_nu2_elements | 0 | 0 | 4 | 0 |  |
| irm_style_sensitivity_from_elements | ss_resid | 0 | 0 | 24 | 0 | sensitivity.mbt:91:3 |
| DoubleMLDID | sensitivity_nu2_elements | 0 | 0 | 4 | 0 |  |
| irm_style_sensitivity_cluster_from_elements | rv | 1.0000000000000002e+300 | 1.0000000000000002e+300 | 24 | 1.0000000000000002e+300 | sensitivity.mbt:312:3 |
| DoubleMLLPQ | sensitivity_analysis_cluster | 0 | 0 | 8 | 0 |  |
| irm_style_sensitivity_cluster_from_elements | ss_rr | 0 | 0 | 24 | 0 | sensitivity.mbt:281:3 |
| irm_style_sensitivity_cluster_from_elements | mb_sum | 0 | 0 | 24 | 0 | sensitivity.mbt:307:3 |
| irm_style_sensitivity_cluster_from_elements | ss_nu2 | 0 | 0 | 24 | 0 | sensitivity.mbt:280:3 |
| irm_style_sensitivity_cluster_from_elements | max_cid | -1 | -1 | 24 | -1 | sensitivity.mbt:251:3 |
| irm_style_sensitivity_cluster_from_elements | ss_resid | 0 | 0 | 24 | 0 | sensitivity.mbt:279:3 |

### 6.3 Abstract may-ranges (L2)

These intervals are the abstract interpreter's fixpoint approximation at widening, not observed samples; they cover the whole input abstraction and therefore over-approximate.

| Function | Variable | May-range | Observations |
| --- | --- | --- | --- |
| dot | c | [0, 0] | 1 |
| dot | s | [0, 0] | 1 |
| iqr | n | [0, 64] | 1 |
| mean | c | [0, 0] | 1 |
| mean | s | [0, 0] | 1 |
| pava | k | [0, 1000004] | 11 |
| pava | n | [0, 64] | 1 |
| expit | x | [-1000000, 1000000] | 1 |
| logit | p | [-1000000, 1000000] | 1 |
| pava | _i | [0, 1000001] | 12 |
| matmul | c | [0, 0] | 3 |
| matvec | c | [0, 0] | 2 |
| matvec | s | [0, 0] | 2 |
| psi_at | n | [0, 64] | 1 |
| inv_spd | s | [0, 0] | 3 |
| mean_at | s | [0, 0] | 1 |
| norm_sf | p | [0.2316419, 0.2316419] | 1 |
| norm_sf | x | [-1000000, 1000000] | 1 |
| permute | n | [-1000000, 1000000] | 1 |
| predict | s | [0, 0] | 4 |
| sigmoid | x | [-1000000, 1000000] | 1 |
| v097_xa | a | [-1000000, 1000000] | 1 |
| v097_xa | i | [-1000000, 1000000] | 1 |
| var_est | n | [0, 64] | 1 |
| cart_fit | n | [0, 64] | 1 |
| cholesky | s | [0, 0] | 2 |
| cholesky | t | [0, 0] | 3 |
| clip_vec | n | [0, 64] | 1 |
| count_eq | n | [0, 1000001] | 6 |
| exp_safe | x | [-1000000, 1000000] | 1 |
| fold_mix | h | [-1000000, 1000000] | 1 |
| fold_mix | v | [-1000000, 1000000] | 1 |
| kfold | seed | [-1000000, 1000000] | 1 |
| logit | eps~ | [-1000000, 1000000] | 1 |
| matmul | sum | [0, 0] | 3 |
| matvec_t | s | [0, 0] | 2 |
| norm_cdf | x | [-1000000, 1000000] | 1 |
| norm_ppf | p | [-1000000, 1000000] | 1 |
| norm_sf | b1 | [0.31938153, 0.31938153] | 1 |
| norm_sf | b2 | [-0.356563782, -0.356563782] | 1 |
| norm_sf | b3 | [1.781477937, 1.781477937] | 1 |
| norm_sf | b4 | [-1.821255978, -1.821255978] | 1 |
| norm_sf | b5 | [1.330274429, 1.330274429] | 1 |
| rdd_side | h | [-1000000, 1000000] | 1 |
| rdd_side | v | [0, 0] | 1 |
| sin_safe | x | [-1000000, 1000000] | 1 |
| solve_pq | q | [-1000000, 1000000] | 1 |
| v096_dgp | n | [-1000000, 1000000] | 1 |
| v097_dgp | n | [-1000000, 1000000] | 1 |
| v098_dgp | n | [-1000000, 1000000] | 1 |
| v098_dgp | p | [3, 3] | 1 |
| v099_dgp | n | [-1000000, 1000000] | 1 |
| v099_dgp | p | [-1000000, 1000000] | 1 |
| v099_dgp | s | [0, 0] | 2 |
| v108_dgp | n | [-1000000, 1000000] | 1 |
| v108_dgp | p | [-1000000, 1000000] | 1 |
| v116_dgp | n | [240, 240] | 1 |
| v116_lcg | i | [-1000000, 1000000] | 1 |
| v116_rel | a | [-1000000, 1000000] | 1 |
| v116_rel | b | [-1000000, 1000000] | 1 |
| v127_raw | n | [-1000000, 1000000] | 1 |
| variance | c | [0, 0] | 1 |
| variance | s | [0, 0] | 1 |
| clip_vec | hi | [-1000000, 1000000] | 1 |
| clip_vec | lo | [-1000000, 1000000] | 1 |
| kahan_sum | c | [0, 0] | 1 |
| kfold | n_obs | [-1000000, 1000000] | 1 |
| lpq_score | q | [-1000000, 1000000] | 1 |
| norm_cdf | b1 | [0.31938153, 0.31938153] | 1 |
| norm_cdf | b2 | [-0.356563782, -0.356563782] | 1 |
| norm_cdf | b3 | [1.781477937, 1.781477937] | 1 |
| norm_cdf | b4 | [-1.821255978, -1.821255978] | 1 |
| norm_cdf | b5 | [1.330274429, 1.330274429] | 1 |
| norm_ppf | hi | [-1000000, 1000000] | 6 |
| norm_ppf | lo | [-1000000, 1000000] | 6 |
| psi_at | coef | [-1000000, 1000000] | 1 |
| rdd_limit | h | [-1000000, 1000000] | 1 |
| rdd_limit | m | [-1000000, 1000000] | 1 |
| sample_sd | n | [0, 64] | 1 |
| solve_spd | c | [0, 0] | 4 |
| v118_data | n | [-1000000, 1000000] | 1 |
| v118_mean | s | [0, 0] | 1 |
| v1320_dgp | n | [-1000000, 1000000] | 1 |
| v1320_dgp | p | [-1000000, 1000000] | 1 |
| v1510_dot | s | [0, 0] | 1 |
| cholesky | s_c | [0, 0] | 2 |
| cholesky | t_c | [0, 0] | 3 |
| grand_mean | s | [0, 0] | 1 |
| kfold | offset | [0, 0] | 1 |
| matvec_t | s_c | [0, 0] | 2 |
| norm_ppf | mid | [-1000000, 1000000] | 6 |
| permute | seed | [-1000000, 1000000] | 1 |
| rdd_design | h | [-1000000, 1000000] | 1 |
| rdd_side | mjx | [0, 0] | 2 |
| rng_double | _ | [0, 0] | 1 |
| unit_means | n | [0, 64] | 1 |
| v097_hc_se | j | [-1000000, 1000000] | 1 |
| v097_hc_se | n | [0, 64] | 1 |
| v115_stage | n | [-1000000, 1000000] | 1 |
| v118_exact | k | [-1000000, 1000000] | 1 |
| v118_exact | n | [-1000000, 1000000] | 1 |
| v118_mean | hi | [-1000000, 1000000] | 1 |
| v118_mean | lo | [-1000000, 1000000] | 1 |
| v127_panel | n | [-2000000, 2000000] | 1 |
| v127_panel | p | [-1000000, 1000000] | 1 |
| v1317_data | n | [-1000000, 1000000] | 1 |
| v1317_data | p | [-1000000, 1000000] | 1 |
| v1330_data | n | [-1000000, 1000000] | 1 |
| v1330_data | p | [-1000000, 1000000] | 1 |
| v1340_data | n | [-1000000, 1000000] | 1 |
| v1340_data | p | [-1000000, 1000000] | 1 |
| v1350_data | n | [-1000000, 1000000] | 1 |
| v1350_data | p | [-1000000, 1000000] | 1 |
| v1380_data | n | [-1000000, 1000000] | 1 |
| v1380_data | p | [-1000000, 1000000] | 1 |
| v1390_data | n | [-1000000, 1000000] | 1 |
| v1470_mean | s | [0, 0] | 1 |
| v1480_corr | n | [0, 64] | 1 |
| v1510_mean | s | [0, 0] | 1 |
| v1510_var | ss | [0, 0] | 1 |
| v1590_data | n | [-1000000, 1000000] | 1 |
| vector_add | n | [0, 64] | 1 |
| Matrix | get | [-1000000, 1000000] | 1 |
| Matrix | get | [-1000000, 1000000] | 1 |
| Matrix | set | [-1000000, 1000000] | 1 |
| Matrix | set | [-1000000, 1000000] | 1 |
| Matrix | set | [-1000000, 1000000] | 1 |
| argsort_asc | j | [0, 1] | 6 |
| argsort_asc | n | [0, 64] | 1 |
| cart_fit | mtry | [-1000000, 1000000] | 1 |
| gather_rows | p | [-1000000, 1000000] | 1 |
| kahan_sum | sum | [0, 0] | 1 |
| kfold | n_folds | [-1000000, 1000000] | 1 |
| nn_residual | e | [0, 1000005] | 18 |
| nn_residual | m | [-1000000, 1000001] | 3 |
| nn_residual | n | [0, 64] | 1 |
| nn_residual | s | [0, 1000001] | 3 |
| pava | cur_size | [1, 1] | 6 |
| pava | last_idx | [0, 0] | 10 |
| pool_tied_x | i | [0, 1000000] | 7 |
| pool_tied_x | j | [1, 1000005] | 36 |
| pool_tied_x | n | [0, 64] | 1 |
| rdd_rb_side | b | [-1000000, 1000000] | 1 |
| rdd_rb_side | h | [-1000000, 1000000] | 1 |
| rdd_rb_side | n | [0, 6] | 1 |
| rdd_rb_side | p | [-1000000, 1000000] | 1 |
| rdd_rb_side | q | [-1000000, 1000000] | 1 |
| rdd_rb_side | s | [0, 0] | 2 |
| rdd_side | data | [-1000000, 1000000] | 1 |
| rdd_side | quad | [0, 0] | 2 |
| rdd_side | side | [-1000000, 1000000] | 1 |
| rng_double2 | i | [-1000000, 1000000] | 1 |
| sample_sd | acc | [0, 0] | 1 |
| solve_pq | clip | [-1000000, 1000000] | 1 |
| solve_pq | data | [-1000000, 1000000] | 1 |
| solve_pq | seed | [-1000000, 1000000] | 1 |
| v096_meat | acc | [0, 0] | 1 |
| v097_hc0_se | j | [-1000000, 1000000] | 1 |
| v099_dgp | seed | [-1000000, 1000000] | 1 |
| v108_dgp | seed | [-1000000, 1000000] | 1 |
| v116_lcg | salt | [-1000000, 1000000] | 1 |
| v127_panel | x0 | [0, 0] | 2 |
| v130_fit | data | [-1000000, 1000000] | 1 |
| v1470_rel | got | [-1000000, 1000000] | 1 |
| v1480_corr | sx | [0, 0] | 1 |
| v1480_corr | sy | [0, 0] | 1 |
| v1480_rel | got | [-1000000, 1000000] | 1 |
| v1490_rel | got | [-1000000, 1000000] | 1 |
| var_est | gamma | [0, 0] | 1 |
| cart_fit | depth | [-1000000, 1000000] | 1 |
| fit_isotonic | k | [0, 1000004] | 11 |
| fit_isotonic | m | [0, 1000001] | 12 |
| fit_isotonic | n | [0, 64] | 1 |
| fold_mix_int | h | [-1000000, 1000000] | 1 |
| fold_mix_int | v | [-1000000, 1000000] | 1 |
| gaussian_kde | h | [-1000000, 1000000] | 1 |
| gaussian_kde | n | [0, 64] | 1 |
| gaussian_kde | x | [-1000000, 1000000] | 1 |
| lpq_score | comp | [-1000000, 1000000] | 1 |
| lpq_score | data | [-1000000, 1000000] | 1 |
| lpq_score | sign | [-1000000, 1000000] | 1 |
| nn_residual | i0 | [0, 1000001] | 4 |
| pq_score_ipw | q | [-1000000, 1000000] | 1 |
| rdd_hc0_term | e | [-1000000, 1000000] | 1 |
| rdd_hc0_term | m | [-1000000, 1000000] | 1 |
| rdd_hc0_term | w | [-1000000, 1000000] | 1 |
| rdd_limit | side | [-1000000, 1000000] | 1 |
| rdd_rb_side | ai | [0, 0] | 2 |
| rdd_rb_side | kp | [-999999, 1000001] | 1 |
| rdd_rb_side | kq | [-999999, 1000001] | 1 |
| rdd_rb_side | pw | [1, 1] | 2 |
| row_unit_max | m | [0, 0] | 1 |
| tune_argmin | bi | [0, 1] | 5 |
| v084_apo_dgp | n | [400, 400] | 1 |
| v084_apo_dgp | p | [3, 3] | 1 |
| v097_hc_se | acc | [0, 0] | 1 |
| v097_hc_se | mjx | [0, 0] | 2 |
| v097_hc_se | pow | [-1000000, 1000000] | 1 |
| v107_ssm_dgp | n | [-1000000, 1000000] | 1 |
| v107_ssm_dgp | p | [-1000000, 1000000] | 1 |
| v107_ssm_fit | n | [-1000000, 1000000] | 1 |
| v107_ssm_fit | p | [-1000000, 1000000] | 1 |
| v118_weights | k | [-1000000, 1000000] | 1 |
| v118_weights | n | [-1000000, 1000000] | 1 |
| v120_close | tol | [-1000000, 1000000] | 1 |
| v124_pq_data | n | [500, 500] | 1 |
| v127_panel | row | [0, 0] | 3 |
| v128_cs_data | n | [-9000000, 9000000] | 1 |
| v128_cs_data | p | [-1000000, 1000000] | 1 |
| v128_xs_data | n | [-1000000, 1000000] | 1 |
| v128_xs_data | p | [-1000000, 1000000] | 1 |
| v130_cs_data | n | [-9000000, 9000000] | 1 |
| v130_cs_data | p | [-1000000, 1000000] | 1 |
| v1317_apo | data | [-1000000, 1000000] | 1 |
| v1317_data | lin | [0, 0] | 2 |
| v1317_irm | data | [-1000000, 1000000] | 1 |
| v1320_dgp | seed | [-1000000, 1000000] | 1 |
| v1470_rel | want | [-1000000, 1000000] | 1 |
| v1480_corr | sxx | [0, 0] | 1 |
| v1480_corr | sxy | [0, 0] | 1 |
| v1480_corr | syy | [0, 0] | 1 |
| v1480_rel | want | [-1000000, 1000000] | 1 |
| v1490_rel | want | [-1000000, 1000000] | 1 |
| v1510_corr | saa | [0, 0] | 1 |
| v1510_corr | sab | [0, 0] | 1 |
| v1510_corr | sbb | [0, 0] | 1 |
| v1520_fit | seed | [-1000000, 1000000] | 1 |
| vector_scale | n | [0, 64] | 1 |
| vector_scale | s | [-1000000, 1000000] | 1 |
| Lasso | new | [-1000000, 1000000] | 1 |
| build_row_dgp | n | [-2147483648, 2147483647] | 1 |
| build_row_dgp | p | [3, 3] | 1 |
| compute_score | n | [0, 64] | 1 |
| count_eq | target | [-1000000, 1000000] | 1 |
| default_5fold | i | [0, 1000001] | 6 |
| default_5fold | j | [0, 1000001] | 18 |
| default_5fold | k | [5, 5] | 1 |
| default_5fold | n | [-1000000, 1000000] | 1 |
| lplr_score_at | n | [0, 64] | 1 |
| lpq_score | theta | [-1000000, 1000000] | 1 |
| lpq_score_ipw | q | [-1000000, 1000000] | 1 |
| make_apo_data | n | [-1000000, 1000000] | 1 |
| make_apo_data | p | [2, 2] | 1 |
| make_irm_data | j | [-1, 0] | 18 |
| make_irm_data | s | [0, 0] | 3 |
| make_ssm_data | j | [-1, 0] | 18 |
| make_ssm_data | s | [0, 0] | 3 |
| median_sorted | n | [0, 64] | 1 |
| nn_residual | s_y | [0, 0] | 2 |
| norm_cdf | p_coef | [0.2316419, 0.2316419] | 1 |
| normalize_ipw | n | [0, 64] | 1 |
| range_indices | n | [-1000000, 1000000] | 1 |
| rdd_design | data | [-1000000, 1000000] | 1 |
| rdd_design | side | [-1000000, 1000000] | 1 |
| rdd_limit | order | [-1000000, 1000000] | 1 |
| rdd_rb_side | v00 | [0, 0] | 1 |
| rdd_side | cutoff | [-1000000, 1000000] | 1 |
| rdd_side | order~ | [-1000000, 1000000] | 1 |
| rdd_weight_at | h | [-1000000, 1000000] | 1 |
| rdd_weight_at | u | [-1000000, 1000000] | 1 |
| storey_m0_hat | n | [0, 64] | 1 |
| tsbh_p_adjust | n | [0, 64] | 1 |
| tsby_p_adjust | c | [0, 0] | 1 |
| tsby_p_adjust | k | [-2, 62] | 2 |
| tsby_p_adjust | n | [0, 64] | 1 |
| v096_rel_diff | a | [-1000000, 1000000] | 1 |
| v096_rel_diff | b | [-1000000, 1000000] | 1 |
| v096_side_wls | h | [-1000000, 1000000] | 1 |
| v096_side_wls | n | [0, 6] | 1 |
| v097_rel_diff | a | [-1000000, 1000000] | 1 |
| v097_rel_diff | b | [-1000000, 1000000] | 1 |
| v109_plr_data | n | [-1000000, 1000000] | 1 |
| v109_plr_data | p | [-1000000, 1000000] | 1 |
| v110_rdd_data | n | [-1000000, 1000000] | 1 |
| v115_rdd_data | n | [-1000000, 1000000] | 1 |
| v117_prob_dev | s | [0, 0] | 1 |
| v117_xor_data | n | [-1000000, 1000000] | 1 |
| v118_clf_data | n | [-1000000, 1000000] | 1 |
| v120_means | yacc | [0, 0] | 1 |
| v122_irm_data | n | [300, 300] | 1 |
| v123_ssm_data | n | [400, 400] | 1 |
| v124_lpq_data | n | [500, 500] | 1 |
| v124_qte_data | n | [500, 500] | 1 |
| v127_panel | seed | [-1000000, 1000000] | 1 |
| v1317_data | seed | [-1000000, 1000000] | 1 |
| v1330_data | seed | [-1000000, 1000000] | 1 |
| v1340_data | seed | [-1000000, 1000000] | 1 |
| v1350_data | seed | [-1000000, 1000000] | 1 |
| v1380_data | seed | [-1000000, 1000000] | 1 |
| v1390_data | seed | [-1000000, 1000000] | 1 |
| v1440_plr_fit | n | [-1000000, 1000000] | 1 |
| v1470_cells | c00 | [0, 1000001] | 6 |
| v1470_cells | c01 | [0, 1000001] | 6 |
| v1470_cells | c10 | [0, 1000001] | 6 |
| v1470_cells | c11 | [0, 1000001] | 6 |
| v1590_data | seed | [-1000000, 1000000] | 1 |
| var_est | gamma_c | [0, 0] | 1 |
| vector_divide | n | [0, 64] | 1 |
| add_ridge | lambda | [-1000000, 1000000] | 1 |
| build_dgp_data | n | [-1000000, 1000000] | 1 |
| build_dgp_data | p | [-1000000, 1000000] | 1 |
| cart_predict | row | [-1000000, 1000000] | 1 |
| chacha8_rng | seed | [-1000000, 1000000] | 1 |
| cvar_ipw_score | n | [0, 64] | 1 |
| gaussian_kde | acc | [0, 0] | 1 |
| make_iivm_data | j | [-1, 0] | 18 |
| make_iivm_data | s | [0, 0] | 3 |
| matrix_predict | c | [0, 0] | 2 |
| matrix_predict | s | [-1000000, 1000000] | 2 |
| pool_tied_x | size | [-999999, 1000000] | 6 |
| rdd_hc0_term | wi2 | [-1000000000000, 1000000000000] | 1 |
| rdd_rb_side | data | [-1000000, 1000000] | 1 |
| rdd_rb_side | ls_a | [0, 0] | 1 |
| rdd_rb_side | side | [-1000000, 1000000] | 1 |
| rdd_rb_side | xibc | [0, 0] | 1 |
| rdd_xi_bc_pair | b | [-1000000, 1000000] | 1 |
| rdd_xi_bc_pair | m | [-1000000, 1000000] | 1 |
| rdd_xi_bc_pair | p | [-1000000, 1000000] | 1 |
| rdd_xi_bc_pair | q | [-1000000, 1000000] | 1 |
| solve_pq | n_folds | [-1000000, 1000000] | 1 |
| v096_side_wls | mg | [0, 0] | 4 |
| v096_side_wls | mj | [0, 0] | 2 |
| v097_dgp | p_basis | [2, 2] | 1 |
| v098_rel_close | a | [-1000000, 1000000] | 1 |
| v098_rel_close | b | [-1000000, 1000000] | 1 |
| v098_sample_sd | n | [0, 64] | 1 |
| v107_plpr_data | n | [240, 240] | 1 |
| v107_plpr_data | p | [2, 2] | 1 |
| v115_stage | theta | [-1000000, 1000000] | 1 |
| v117_accuracy | ok | [0, 1000001] | 6 |
| v120_means | total | [0, 0] | 1 |
| v123_iivm_data | n | [400, 400] | 1 |
| v127_panel | slope | [-1000000, 1000000] | 1 |
| v128_cs_data | row | [0, 0] | 3 |
| v128_cs_fit | data | [-1000000, 1000000] | 1 |
| v130_cs_data | row | [0, 0] | 3 |
| v1316_did_data | n | [-1000000, 1000000] | 1 |
| v1316_did_data | p | [-1000000, 1000000] | 1 |
| v1380_data | slope | [-1000000, 1000000] | 1 |
| v1380_data | theta | [-1000000, 1000000] | 1 |
| v1450_lplr_fit | n | [-1000000, 1000000] | 1 |
| v1470_all | fitted | [-1000000, 1000000] | 1 |
| Lasso | new | [-1000000, 1000000] | 1 |
| Ridge | new | [-1000000, 1000000] | 1 |
| aggregate_group | w | [1, 1] | 10 |
| bh_fdr_p_adjust | k | [-2, 62] | 2 |
| bh_fdr_p_adjust | n | [0, 64] | 1 |
| build_panel_dgp | _ | [0, 2147483647] | 1 |
| build_panel_dgp | n | [-2147483648, 2147483647] | 1 |
| build_panel_dgp | p | [2, 2] | 1 |
| build_row_dgp | row | [0, 0] | 3 |
| by_fdr_p_adjust | c | [0, 0] | 1 |
| by_fdr_p_adjust | k | [-2, 62] | 2 |
| by_fdr_p_adjust | n | [0, 64] | 1 |
| cart_leaf_value | h | [0, 0] | 2 |
| cart_leaf_value | n | [0, 64] | 1 |
| cart_leaf_value | s | [0, 0] | 1 |
| default_5fold | rem | [0, 999999] | 1 |
| expand_v092_fit | n | [-1000000, 1000000] | 1 |
| expand_v093_fit | n | [-1000000, 1000000] | 1 |
| expand_v094_fit | n | [-1000000, 1000000] | 1 |
| expand_v095_fit | n | [-1000000, 1000000] | 1 |
| expand_v095_row | j | [-1000000, 1000000] | 1 |
| expand_v095_row | m | [-1000000, 1000000] | 1 |
| expand_v095_row | n | [-1000000, 1000000] | 1 |
| expand_v101_row | j | [-1000000, 1000000] | 1 |
| expand_v101_row | m | [-1000000, 1000000] | 1 |
| expand_v101_row | n | [-1000000, 1000000] | 1 |
| expand_v102_fit | n | [-1000000, 1000000] | 1 |
| fold_mix_double | h | [-1000000, 1000000] | 1 |
| fold_mix_double | v | [-1000000, 1000000] | 1 |
| make_did_CS2021 | j | [-1, 0] | 18 |
| make_did_CS2021 | s | [0, 0] | 3 |
| make_did_SZ2020 | j | [-1, 0] | 18 |
| make_did_SZ2020 | s | [0, 0] | 3 |
| make_iivm_data | xb | [0, 0] | 2 |
| make_irm_data | acc | [-700000, 700000] | 18 |
| make_ssm_data | acc | [-700000, 700000] | 18 |
| plr_iv_test_dgp | n | [-1000000, 1000000] | 1 |
| rdd_design | cutoff | [-1000000, 1000000] | 1 |
| rdd_design | order~ | [-1000000, 1000000] | 1 |
| rdd_pilot_stage | m | [-1000000, 1000000] | 1 |
| transform_panel | c | [0, 1000001] | 12 |
| transform_panel | k | [0, 1000000] | 7 |
| tune_score_grid | n | [0, 64] | 1 |
| v084_apo_dgp | seed | [-1000000, 1000000] | 1 |
| v085_policy_dgp | n | [300, 300] | 1 |
| v085_policy_dgp | p | [2, 2] | 1 |
| v098_sample_sd | ss | [0, 0] | 1 |
| v106_singletons | n | [-1000000, 1000000] | 1 |
| v107_ssm_fit | seed | [-1000000, 1000000] | 1 |
| v107_ssm_fit_ml | n | [-1000000, 1000000] | 1 |
| v107_ssm_fit_ml | p | [-1000000, 1000000] | 1 |
| v109_drawn_reps | n | [-1000000, 1000000] | 1 |
| v120_close | actual | [-1000000, 1000000] | 1 |
| v126_clip_of | clip | [-1000000, 1000000] | 1 |
| v128_cs_data | seed | [-1000000, 1000000] | 1 |
| v128_xs_data | seed | [-1000000, 1000000] | 1 |
| v130_cs_data | seed | [-1000000, 1000000] | 1 |
| v1470_cells | other | [0, 1000001] | 6 |
| v1480_cell_fit | mc | [0, 0] | 1 |
| v1480_cell_fit | mg | [0, 0] | 1 |
| v1480_cell_fit | yv | [0, 0] | 1 |
| var_est_cluster | m | [0, 1000001] | 12 |
| var_est_cluster | s | [0, 0] | 3 |
| vector_multiply | n | [0, 64] | 1 |
| vector_subtract | n | [0, 64] | 1 |
| Matrix | identity | [-1000000, 1000000] | 1 |
| Matrix | ones | [-1000000, 1000000] | 1 |
| Matrix | ones | [-1000000, 1000000] | 1 |
| cart_fit | max_depth | [-1000000, 1000000] | 1 |
| cart_leaf_value | sw | [0, 0] | 1 |
| cs_bin_score_obs | n | [0, 64] | 1 |
| cvar_ipw_score | acc | [0, 0] | 1 |
| default_5fold | base | [-200000, 200000] | 1 |
| enet_objective | l1n | [0, 0] | 1 |
| enet_objective | l2n | [0, 0] | 1 |
| enet_objective | rss | [0, 0] | 1 |
| expand_v090_data | n | [-1000000, 1000000] | 1 |
| expand_v090_data | p | [-1000000, 1000000] | 1 |
| expand_v091_data | n | [-1000000, 1000000] | 1 |
| expand_v091_data | p | [-1000000, 1000000] | 1 |
| expand_v100_flat | f | [-1000000, 1000000] | 1 |
| expand_v100_flat | g | [-1000000, 1000000] | 1 |
| expand_v100_flat | t | [-1000000, 1000000] | 1 |
| fill_normal_pool | i | [0, 1000002] | 6 |
| fit_cs_bin_g | sub_n | [0, 1000001] | 6 |
| kfold_stratified | n | [-1000000, 1000000] | 1 |
| lpq_score_ipw | comp | [-1000000, 1000000] | 1 |
| lpq_score_ipw | data | [-1000000, 1000000] | 1 |
| lpq_score_ipw | sign | [-1000000, 1000000] | 1 |
| make_apo_data | seed | [-1000000, 1000000] | 1 |
| make_iivm_data | acc | [-700000, 700000] | 18 |
| make_irm_data | seed | [-1000000, 1000000] | 1 |
| make_plpr_CP2025 | j | [-1, 0] | 18 |
| make_plpr_CP2025 | s | [0, 0] | 3 |
| make_ssm_data | seed | [-1000000, 1000000] | 1 |
| pq_score_ipw | theta | [-1000000, 1000000] | 1 |
| predict_isotonic | j | [0, 1000001] | 12 |
| rdd_rb_side | cutoff | [-1000000, 1000000] | 1 |
| rdd_side_offsets | h | [-1000000, 1000000] | 1 |
| rdd_side_offsets | m | [-1000000, 1000000] | 1 |
| reg_fit_means | wsum | [0, 0] | 1 |
| reg_fit_means | yacc | [0, 0] | 1 |
| seed_to_bytes | seed | [-1000000, 1000000] | 1 |
| solve_pq | treatment | [-1000000, 1000000] | 1 |
| stratified_kfold | i | [0, 1000000] | 3 |
| stratified_kfold | j | [1, 1000005] | 12 |
| v096_side_wls | pred | [0, 0] | 2 |
| v096_side_wls | quad | [0, 0] | 2 |
| v096_side_wls | side | [-1000000, 1000000] | 1 |
| v097_reference | acc | [0, 0] | 7 |
| v098_rel_close | tol | [-1000000, 1000000] | 1 |
| v098_sample_sd | sum | [0, 0] | 1 |
| v106_build_panel | n | [-2147483648, 2147483647] | 1 |
| v106_build_panel | p | [3, 3] | 1 |
| v107_plpr_data | row | [0, 0] | 3 |
| v109_plr_data | seed | [-1000000, 1000000] | 1 |
| v120_kfold_folds | k | [-1000000, 1000000] | 1 |
| v120_kfold_folds | n | [-1000000, 1000000] | 1 |
| v127_panel | n_units | [-1000000, 1000000] | 1 |
| v1316_did_data | lin | [0, 0] | 2 |
| v1316_did_fit | data | [-1000000, 1000000] | 1 |
| v1440_plr_fit | seed | [-1000000, 1000000] | 1 |
| v1470_cells | fitted | [-1000000, 1000000] | 1 |
| v1480_cell_fit | cnt | [0, 1000001] | 6 |
| var_est_cluster | sd | [0, 0] | 3 |
| vector_divide | eps~ | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | fit | [0, 0] | 12 |
| DoubleMLPQ | se | [-1000000, 1000000] | 1 |
| Matrix | zeros | [-1000000, 1000000] | 1 |
| Matrix | zeros | [-1000000, 1000000] | 1 |
| RDDKernel | weight | [-1000000, 1000000] | 1 |
| RDDKernel | weight | [-1000000, 1000000] | 1 |
| aggregate_coef_se | n | [0, 64] | 1 |
| aggregate_event | n_e | [0, 0] | 1 |
| aggregate_time | flat | [0, 0] | 4 |
| bh_step_up_sorted | k | [-2, 62] | 2 |
| bh_step_up_sorted | n | [0, 64] | 1 |
| build_dgp_data | seed | [-1000000, 1000000] | 1 |
| build_lzz2020_dgp | n | [-1000000, 1000000] | 1 |
| build_lzz2020_dgp | p | [6, 6] | 1 |
| build_panel_dgp | row | [0, 0] | 3 |
| cart_fit | best_score | [1.0000000000000002e+300, 1.0000000000000002e+300] | 1 |
| cart_fit | left_count | [1, 1] | 3 |
| default_5fold | start | [0, 0] | 1 |
| est_coef_cluster | fa | [0, 0] | 2 |
| est_coef_cluster | fb | [0, 0] | 2 |
| est_coef_cluster | sa | [0, 0] | 1 |
| est_coef_cluster | sb | [0, 0] | 1 |
| expand_v086_close | x | [-1000000, 1000000] | 1 |
| expand_v086_close | y | [-1000000, 1000000] | 1 |
| expand_v087_close | x | [-1000000, 1000000] | 1 |
| expand_v087_close | y | [-1000000, 1000000] | 1 |
| expand_v088_close | x | [-1000000, 1000000] | 1 |
| expand_v088_close | y | [-1000000, 1000000] | 1 |
| expand_v089_close | x | [-1000000, 1000000] | 1 |
| expand_v089_close | y | [-1000000, 1000000] | 1 |
| expand_v090_close | x | [-1000000, 1000000] | 1 |
| expand_v090_close | y | [-1000000, 1000000] | 1 |
| expand_v091_close | x | [-1000000, 1000000] | 1 |
| expand_v091_close | y | [-1000000, 1000000] | 1 |
| expand_v092_close | x | [-1000000, 1000000] | 1 |
| expand_v092_close | y | [-1000000, 1000000] | 1 |
| expand_v093_close | x | [-1000000, 1000000] | 1 |
| expand_v093_close | y | [-1000000, 1000000] | 1 |
| expand_v094_close | x | [-1000000, 1000000] | 1 |
| expand_v094_close | y | [-1000000, 1000000] | 1 |
| expand_v095_close | x | [-1000000, 1000000] | 1 |
| expand_v095_close | y | [-1000000, 1000000] | 1 |
| expand_v100_close | x | [-1000000, 1000000] | 1 |
| expand_v100_close | y | [-1000000, 1000000] | 1 |
| expand_v101_close | x | [-1000000, 1000000] | 1 |
| expand_v101_close | y | [-1000000, 1000000] | 1 |
| expand_v102_fit | att | [-1000000, 1000000] | 1 |
| fit_propensity | clip | [-1000000, 1000000] | 1 |
| fold_mix_double | acc | [-1000000, 1000000] | 1 |
| joint_sensitivity | k | [0, 64] | 1 |
| joint_sensitivity | z | [1.959963984540054, 1.959963984540054] | 1 |
| lplr_score_at | theta | [-1000000, 1000000] | 1 |
| lpq_score_ipw | theta | [-1000000, 1000000] | 1 |
| make_did_CS2021 | acc | [-700000, 700000] | 18 |
| make_did_CS2021 | idx | [0, 0] | 3 |
| make_did_SZ2020 | acc | [-700000, 700000] | 18 |
| make_did_SZ2020 | idx | [0, 0] | 3 |
| make_iivm_data | seed | [-1000000, 1000000] | 1 |
| make_irm_data | dim_x | [-1000000, 1000000] | 1 |
| make_irm_data | idx_a | [0, 0] | 3 |
| make_irm_data | idx_b | [1, 1] | 3 |
| make_irm_data | n_obs | [-1000000, 1000000] | 1 |
| make_irm_data | theta | [-1000000, 1000000] | 1 |
| make_lplr_LZZ2020 | n | [-1000000, 1000000] | 1 |
| make_lplr_LZZ2020 | p | [6, 6] | 1 |
| make_pliv_CHS2015 | j | [-1, 0] | 18 |
| make_pliv_CHS2015 | s | [0, 0] | 3 |
| make_pliv_data | seed | [-1000000, 1000000] | 1 |
| make_ssm_data | dim_x | [-1000000, 1000000] | 1 |
| make_ssm_data | idx_a | [0, 0] | 3 |
| make_ssm_data | idx_b | [1, 1] | 3 |
| make_ssm_data | n_obs | [-1000000, 1000000] | 1 |
| make_ssm_data | theta | [-1000000, 1000000] | 1 |
| matrix_predict | bias | [-1000000, 1000000] | 1 |
| percentile_sorted | n | [0, 64] | 1 |
| percentile_sorted | p | [-1000000, 1000000] | 1 |
| policy_tree_build | n | [0, 64] | 1 |
| rdd_rb_side | nnmatch | [-1000000, 1000000] | 1 |
| slice_matrix_rows | n | [0, 64] | 1 |
| storey_m0_hat | alpha | [0.05, 0.05] | 1 |
| transform_panel | end | [0, 1000004] | 36 |
| tsbh_p_adjust | alpha | [0.05, 0.05] | 1 |
| v096_dgp_lopsided | n | [-1000000, 1000000] | 1 |
| v096_side_wls | ridge | [-1000000, 1000000] | 1 |
| v107_ssm_dgp | theta0 | [-1000000, 1000000] | 1 |
| v110_rdd_data | theta | [-1000000, 1000000] | 1 |
| v115_rdd_data | theta | [-1000000, 1000000] | 1 |
| v120_close | expected | [-1000000, 1000000] | 1 |
| v122_extreme_data | n | [300, 300] | 1 |
| v126_extreme_data | n | [600, 600] | 1 |
| v127_panel_fit | data | [-1000000, 1000000] | 1 |
| v1316_did_data | seed | [-1000000, 1000000] | 1 |
| v1390_pq_coefs | data | [-1000000, 1000000] | 1 |
| v1440_plr_fixture | n | [-1000000, 1000000] | 1 |
| v1440_plr_fixture | p | [-1000000, 1000000] | 1 |
| v1450_lplr_fit | seed | [-1000000, 1000000] | 1 |
| v1510_resid_after | k | [0, 64] | 1 |
| v1510_resid_after | n | [0, 64] | 1 |
| DoubleMLAPO | se | [-1000000, 1000000] | 1 |
| DoubleMLBLP | se | [-1000000, 1000000] | 1 |
| DoubleMLDID | se | [-1000000, 1000000] | 1 |
| DoubleMLData | z | [-1000000, 1000000] | 1 |
| DoubleMLIRM | se | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | fit | [0, 0] | 12 |
| DoubleMLLPQ | se | [-1000000, 1000000] | 1 |
| DoubleMLPLR | se | [-1000000, 1000000] | 1 |
| DoubleMLPQ | fit | [-1000000, 1000000] | 1 |
| DoubleMLPQ | new | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bias | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bias | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bias | [-1000000, 1000000] | 1 |
| DoubleMLRDD | se | [-1000000, 1000000] | 1 |
| DoubleMLSSM | se | [-1000000, 1000000] | 1 |
| ElasticNet | new | [-1000000, 1000000] | 1 |
| GBLearner | new | [-1000000, 1000000] | 1 |
| Lasso | new | [-1000000, 1000000] | 1 |
| RFLearner | new | [-1000000, 1000000] | 1 |
| aggregate_group | flat | [0, 0] | 10 |
| aggregate_time | sum_w | [0, 0] | 2 |
| aggregate_time | total | [0, 0] | 1 |
| blp_hac_require_df | n | [-1000000, 1000000] | 1 |
| build_panel_dgp | seed | [-1000000, 1000000] | 1 |
| build_row_dgp | theta0 | [-1000000, 1000000] | 1 |
| build_row_unit_map | n | [0, 64] | 1 |
| cart_fit | right_count | [-1, 63] | 3 |
| compute_score | mean_d | [0, 0] | 1 |
| compute_score | mean_t | [0, 0] | 1 |
| cvar_ipw_score | theta | [-1000000, 1000000] | 1 |
| empirical_quantile | j | [0, 1] | 6 |
| empirical_quantile | q | [-1000000, 1000000] | 1 |
| enet_objective | alpha | [-1000000, 1000000] | 1 |
| expand_v086_psi | coef | [-1000000, 1000000] | 1 |
| expand_v087_psi | coef | [-1000000, 1000000] | 1 |
| expand_v089_psi | coef | [-1000000, 1000000] | 1 |
| expand_v102_cs_dgp | n | [-1000000, 1000000] | 1 |
| expand_v102_cs_dgp | p | [-1000000, 1000000] | 1 |
| filter_two_values | v1 | [-1000000, 1000000] | 1 |
| filter_two_values | v2 | [-1000000, 1000000] | 1 |
| fit_cs_bin_g | d_value | [-1000000, 1000000] | 1 |
| fit_cs_bin_g | n_train | [0, 64] | 1 |
| fit_cs_bin_g | t_value | [-1000000, 1000000] | 1 |
| make_did_CS2021 | seed | [-1000000, 1000000] | 1 |
| make_did_SZ2020 | seed | [-1000000, 1000000] | 1 |
| make_did_cs_CS2021 | j | [-1, 0] | 18 |
| make_did_cs_CS2021 | s | [0, 0] | 3 |
| make_iivm_data | dim_x | [-1000000, 1000000] | 1 |
| make_iivm_data | idx_a | [0, 0] | 3 |
| make_iivm_data | idx_b | [1, 1] | 3 |
| make_iivm_data | n_obs | [-1000000, 1000000] | 1 |
| make_iivm_data | theta | [-1000000, 1000000] | 1 |
| make_irm_data | half_n | [-499999, 500000] | 1 |
| make_irm_data | half_z | [-1073741823, 1073741823] | 1 |
| make_pliv_data | dim_x | [-1000000, 1000000] | 1 |
| make_pliv_data | n_obs | [-1000000, 1000000] | 1 |
| make_pliv_data | theta | [-1000000, 1000000] | 1 |
| make_plpr_CP2025 | acc | [-700000, 700000] | 18 |
| make_plpr_CP2025 | idx | [0, 0] | 3 |
| make_ssm_data | half_n | [-499999, 500000] | 1 |
| make_ssm_data | half_z | [-1073741823, 1073741823] | 1 |
| newton_solve_score | n | [0, 64] | 1 |
| newton_solve_score | s | [0, 0] | 2 |
| nn_residual | nnmatch~ | [-1000000, 1000000] | 1 |
| normalize_ipw | sum_t0 | [0, 0] | 1 |
| normalize_ipw | sum_t1 | [0, 0] | 1 |
| plr_iv_test_dgp | seed | [-1000000, 1000000] | 1 |
| plr_score_elements | n | [-1000000, 1000000] | 1 |
| policy_tree_build | bf | [-1, 0] | 3 |
| policy_tree_build | bv | [0, 0] | 1 |
| policy_tree_build | nl | [0, 1000001] | 12 |
| policy_tree_build | nr | [0, 1000001] | 12 |
| policy_tree_build | sl | [0, 0] | 2 |
| policy_tree_build | sr | [0, 0] | 2 |
| qte_post_scale | n_obs | [-1000000, 1000000] | 1 |
| quantile_test_data | n | [400, 400] | 1 |
| rdd_kernel_weights | h | [-1000000, 1000000] | 1 |
| repeated_kfold | n_obs | [-1000000, 1000000] | 1 |
| repeated_kfold | n_rep | [-1000000, 1000000] | 1 |
| storey_m0_hat | m0_hat | [1, 1] | 1 |
| transform_panel | data | [-1000000, 1000000] | 1 |
| tune_score_grid | seed | [-1000000, 1000000] | 1 |
| tune_score_outcome | n | [0, 64] | 1 |
| v085_policy_dgp | seed | [-1000000, 1000000] | 1 |
| v096_side_wls | cutoff | [-1000000, 1000000] | 1 |
| v106_build_panel | row | [0, 0] | 3 |
| v107_ssm_fit_ml | seed | [-1000000, 1000000] | 1 |
| v109_drawn_reps | seed | [-1000000, 1000000] | 1 |
| v120_rel_diff | actual | [-1000000, 1000000] | 1 |
| v125_lpq_nonlinear | n | [600, 600] | 1 |
| v128_cs_data | n_units | [-3000000, 3000000] | 1 |
| v130_cs_data | n_units | [-3000000, 3000000] | 1 |
| v1450_lplr_fit | alpha | [-1000000, 1000000] | 1 |
| v1480_cell_fit | d_val | [-1000000, 1000000] | 1 |
| v1480_cell_fit | t_val | [-1000000, 1000000] | 1 |
| v1510_resid_after | nb | [0, 1000001] | 6 |
| DoubleMLAPO | fit | [-1000000, 1000000] | 1 |
| DoubleMLAPO | new | [-1000000, 1000000] | 1 |
| DoubleMLBLP | fit | [-1000000, 1000000] | 1 |
| DoubleMLBLP | fit | [0, 0] | 1 |
| DoubleMLBLP | rss | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | se | [-1000000, 1000000] | 1 |
| DoubleMLDID | fit | [-1000000, 1000000] | 1 |
| DoubleMLDID | new | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | se | [-1000000, 1000000] | 1 |
| DoubleMLIRM | fit | [-1000000, 1000000] | 1 |
| DoubleMLIRM | new | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | se | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | fit | [0, 0] | 1 |
| DoubleMLLPQ | fit | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | new | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | se | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | se | [-1000000, 1000000] | 1 |
| DoubleMLPLR | fit | [-1000000, 1000000] | 1 |
| DoubleMLPLR | new | [-1000000, 1000000] | 1 |
| DoubleMLPQ | coef | [-1000000, 1000000] | 1 |
| DoubleMLPQ | new | [-1000000, 1000000] | 1 |
| DoubleMLPQ | tune | [-1000000, 1000000] | 1 |
| DoubleMLQTE | fit | [-1000000, 1000000] | 1 |
| DoubleMLQTE | new | [-1000000, 1000000] | 1 |
| DoubleMLQTE | ses | [-1000000, 1000000] | 1 |
| DoubleMLRDD | fit | [-1000000, 1000000] | 1 |
| DoubleMLRDD | new | [-1000000, 1000000] | 1 |
| DoubleMLSSM | fit | [-1000000, 1000000] | 1 |
| DoubleMLSSM | new | [-1000000, 1000000] | 1 |
| aggregate_group | sum_w | [-999999, 1000001] | 12 |
| aggregate_group | total | [0, 0] | 1 |
| blp_hac_require_df | p1 | [-1000000, 1000000] | 1 |
| bonferroni_p_adjust | n | [0, 64] | 1 |
| build_bootstrap_dgp | n | [960, 960] | 1 |
| build_bootstrap_dgp | p | [3, 3] | 1 |
| build_clustered_dgp | n | [-2147483648, 2147483647] | 1 |
| build_clustered_dgp | p | [3, 3] | 1 |
| build_irm_tune_data | n | [-1000000, 1000000] | 1 |
| build_irm_tune_data | p | [-1000000, 1000000] | 1 |
| build_row_dgp | n_units | [-1000000, 1000000] | 1 |
| cart_fit | best_feature | [-1, -1] | 1 |
| enet_soft_threshold | t | [-1000000, 1000000] | 1 |
| expand_v086_psi | n_obs | [-1000000, 1000000] | 1 |
| expand_v087_psi | n_obs | [-1000000, 1000000] | 1 |
| expand_v088_hc_pair | n | [-1000000, 1000000] | 1 |
| expand_v088_input_a | n | [-1000000, 1000000] | 1 |
| expand_v089_psi | n_obs | [-1000000, 1000000] | 1 |
| expand_v094_pq_data | n | [-1000000, 1000000] | 1 |
| expand_v100_apos | seed | [-1000000, 1000000] | 1 |
| indicator_level | level | [-1000000, 1000000] | 1 |
| kfold_stratified | seed | [-1000000, 1000000] | 1 |
| make_did_CS2021 | dim_x | [-1000000, 1000000] | 1 |
| make_did_CS2021 | idx_a | [0, 0] | 4 |
| make_did_CS2021 | idx_b | [1, 1] | 4 |
| make_did_CS2021 | n_obs | [-1000000, 1000000] | 1 |
| make_did_CS2021 | theta | [-1000000, 1000000] | 1 |
| make_did_SZ2020 | dim_x | [-1000000, 1000000] | 1 |
| make_did_SZ2020 | idx_a | [0, 0] | 3 |
| make_did_SZ2020 | idx_b | [1, 1] | 3 |
| make_did_SZ2020 | n_obs | [-1000000, 1000000] | 1 |
| make_did_SZ2020 | theta | [-1000000, 1000000] | 1 |
| make_iivm_data | beta_x | [0.5, 0.5] | 1 |
| make_iivm_data | beta_z | [1, 1] | 1 |
| make_iivm_data | half_n | [-499999, 500000] | 1 |
| make_iivm_data | half_z | [-1073741823, 1073741823] | 1 |
| make_pliv_CHS2015 | acc | [-700000, 700000] | 18 |
| make_plpr_CP2025 | seed | [-1000000, 1000000] | 1 |
| newton_solve_score | sd | [0, 0] | 2 |
| policy_tree_build | bnl | [0, 1000000] | 3 |
| policy_tree_build | bnr | [0, 1000000] | 3 |
| policy_tree_build | ssl | [0, 0] | 2 |
| policy_tree_build | ssr | [0, 0] | 2 |
| policy_tree_build | sum | [0, 0] | 2 |
| pq_score_orthogonal | q | [-1000000, 1000000] | 1 |
| rdd_hac_require_df | p1 | [-1000000, 1000000] | 1 |
| rdd_pilot_stage | order | [-1000000, 1000000] | 1 |
| rdd_side_offsets | side | [-1000000, 1000000] | 1 |
| silverman_bandwidth | n | [0, 64] | 1 |
| solve_pq | newton_steps | [0, 100] | 6 |
| storey_m0_hat | n_above | [0, 1000001] | 6 |
| stratified_kfold | seed | [-1000000, 1000000] | 1 |
| v098_small_leaf_dgp | n | [-1000000, 1000000] | 1 |
| v107_plpr_data | theta0 | [1, 1] | 1 |
| v109_drawn_reps | n_rep | [-1000000, 1000000] | 1 |
| v117_threshold_data | n | [-1000000, 1000000] | 1 |
| v120_check_enet | worst | [0, 0] | 1 |
| v127_panel_fit | pclip~ | [-1000000, 1000000] | 1 |
| v128_cs_fit_nrep | data | [-1000000, 1000000] | 1 |
| v1390_changed_steps | n | [0, 1000001] | 6 |
| v1440_plr_fixture | acc | [0, 0] | 2 |
| v1480_cell_fit | fitted | [-1000000, 1000000] | 1 |
| var_est_cluster | gamma | [0, 0] | 1 |
| var_est_cluster | j_hat | [0, 0] | 1 |
| DoubleMLAPO | coef | [-1000000, 1000000] | 1 |
| DoubleMLAPO | new | [-1000000, 1000000] | 1 |
| DoubleMLAPO | tune | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | fit | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | new | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | ses | [-1000000, 1000000] | 1 |
| DoubleMLBLP | coef | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | fit | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | new | [-1000000, 1000000] | 1 |
| DoubleMLDID | coef | [-1000000, 1000000] | 1 |
| DoubleMLDID | new | [-1000000, 1000000] | 1 |
| DoubleMLDID | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | fit | [0, 0] | 1 |
| DoubleMLDIDCS | fit | [0, 0] | 1 |
| DoubleMLDIDCS | fit | [0, 0] | 1 |
| DoubleMLIIVM | fit | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | new | [-1000000, 1000000] | 1 |
| DoubleMLIRM | coef | [-1000000, 1000000] | 1 |
| DoubleMLIRM | new | [-1000000, 1000000] | 1 |
| DoubleMLIRM | tune | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | fit | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | new | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | coef | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | new | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | fit | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | new | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | fit | [0, 0] | 2 |
| DoubleMLPLPR | fit | [-1000000, 1000000] | 1 |
| DoubleMLPLR | coef | [-1000000, 1000000] | 1 |
| DoubleMLPLR | new | [-1000000, 1000000] | 1 |
| DoubleMLPLR | tune | [-1000000, 1000000] | 1 |
| DoubleMLPQ | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLPQ | tune | [-1000000, 1000000] | 1 |
| DoubleMLQTE | new | [-1000000, 1000000] | 1 |
| DoubleMLQTE | tune | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bias | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bias | [-1000000, 1000000] | 1 |
| DoubleMLRDD | coef | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tune | [-1000000, 1000000] | 1 |
| DoubleMLSSM | coef | [-1000000, 1000000] | 1 |
| DoubleMLSSM | new | [-1000000, 1000000] | 1 |
| DoubleMLSSM | tune | [-1000000, 1000000] | 1 |
| ElasticNet | new | [-1000000, 1000000] | 1 |
| GainStatsSource | new | [0, 64] | 1 |
| bootstrap_indices | seed | [-1000000, 1000000] | 1 |
| build_lzz2020_dgp | need | [-7000000, 7000000] | 1 |
| build_lzz2020_dgp | seed | [-1000000, 1000000] | 1 |
| build_panel_dgp | theta0 | [-1000000, 1000000] | 1 |
| crossfit_nuisance | data | [-1000000, 1000000] | 1 |
| crossfit_nuisance | seed | [-1000000, 1000000] | 1 |
| did_bootstrap_t_stat | s | [0, 0] | 3 |
| enet_fit_tail | l1_ratio | [-1000000, 1000000] | 1 |
| enet_fit_tail | self_tol | [-1000000, 1000000] | 1 |
| expand_v086_ref_hc0 | m2 | [-1000000000000, 1000000000000] | 1 |
| expand_v087_ref_hc0 | m2 | [-1000000000000, 1000000000000] | 1 |
| expand_v087_ssm_data | n | [-1000000, 1000000] | 1 |
| expand_v087_ssm_data | p | [-1000000, 1000000] | 1 |
| expand_v089_apo_data | n | [-1000000, 1000000] | 1 |
| expand_v089_apo_data | p | [-1000000, 1000000] | 1 |
| expand_v089_ref_hc0 | m2 | [-1000000000000, 1000000000000] | 1 |
| expand_v093_lpq_data | n | [-1000000, 1000000] | 1 |
| expand_v095_qte_data | n | [-1000000, 1000000] | 1 |
| expand_v101_qte_data | n | [-1000000, 1000000] | 1 |
| expand_v101_qte_data | p | [3, 3] | 1 |
| expand_v102_cs_dgp | att | [-1000000, 1000000] | 1 |
| filter_by_value | target | [-1000000, 1000000] | 1 |
| lplr_initial_theta | den | [0, 0] | 1 |
| make_did_CS2021 | half_n | [-499999, 500000] | 1 |
| make_did_CS2021 | half_z | [-1073741823, 1073741823] | 1 |
| make_did_CS2021 | true_n | [-1000000, 1000000] | 1 |
| make_did_SZ2020 | half_a | [-249999, 250000] | 1 |
| make_did_SZ2020 | half_b | [1, 1] | 1 |
| make_did_SZ2020 | half_n | [-499999, 500000] | 1 |
| make_did_SZ2020 | half_z | [-1073741823, 1073741823] | 1 |
| make_did_SZ2020 | true_n | [-1000000, 1000000] | 1 |
| make_did_cs_CS2021 | acc | [-700000, 700000] | 18 |
| make_did_cs_CS2021 | idx | [0, 0] | 3 |
| make_lplr_LZZ2020 | half | [-3499999, 3500000] | 1 |
| make_lplr_LZZ2020 | need | [-7000000, 7000000] | 1 |
| make_lplr_LZZ2020 | seed | [-1000000, 1000000] | 1 |
| make_pliv_CHS2015 | seed | [-1000000, 1000000] | 1 |
| make_plpr_CP2025 | dim_x | [-1000000, 1000000] | 1 |
| make_plpr_CP2025 | idx_a | [0, 0] | 3 |
| make_plpr_CP2025 | idx_b | [1, 1] | 3 |
| make_plpr_CP2025 | n_obs | [-1000000, 1000000] | 1 |
| make_plpr_CP2025 | theta | [-1000000, 1000000] | 1 |
| make_plr_CCDDHNR2018 | j | [-1, 0] | 18 |
| make_plr_CCDDHNR2018 | s | [0, 0] | 3 |
| make_plr_turrell2018 | j | [-1, 0] | 18 |
| make_plr_turrell2018 | s | [0, 0] | 3 |
| make_simple_plr_data | n | [-1000000, 1000000] | 1 |
| make_simple_plr_data | p | [2, 2] | 1 |
| nn_residual | nn_tol_eps | [1.4901161193847656, 1.4901161193847656] | 1 |
| policy_tree_build | best | [-9.999999999999998e+307, -9.999999999999998e+307] | 1 |
| predict_isotonic | n_fit | [0, 64] | 1 |
| predict_isotonic | n_new | [0, 64] | 1 |
| rdd_local_side_count | h | [-1000000, 1000000] | 1 |
| reg_mean_one_weights | n | [-1000000, 1000000] | 1 |
| repeated_kfold | n_folds | [-1000000, 1000000] | 1 |
| robustness_value | theta | [-1000000, 1000000] | 1 |
| romano_wolf_p_adjust | j | [0, 1] | 6 |
| romano_wolf_p_adjust | n | [0, 64] | 1 |
| solve_normal_eqs | ridge | [-1000000, 1000000] | 1 |
| sort_rows_by_id_time | j | [0, 1] | 6 |
| stratified_kfold | n_obs | [0, 64] | 1 |
| tune_score_outcome | sse | [0, 0] | 1 |
| v096_meat_leverage | acc | [0, 0] | 1 |
| v107_plpr_data | n_units | [60, 60] | 1 |
| v110_rdd_data | y_scale~ | [-1000000, 1000000] | 1 |
| v115_exact_quadratic | n | [-1000000, 1000000] | 1 |
| v120_check_ridge | worst | [0, 0] | 1 |
| v120_rel_diff | expected | [-1000000, 1000000] | 1 |
| v128_cs_data | n_periods | [3, 3] | 1 |
| v128_cs_fit_nrep | n_rep | [-1000000, 1000000] | 1 |
| v130_cs_data | n_periods | [3, 3] | 1 |
| v1440_plr_fixture | seed | [-1000000, 1000000] | 1 |
| v1500_no_base_period | n | [540, 540] | 1 |
| v1500_no_base_period | p | [2, 2] | 1 |
| v1550_score_gate_dgp | n | [-1000000, 1000000] | 1 |
| zz_gate_y_variant | data | [-1000000, 1000000] | 1 |
| DoubleMLAPO | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLAPO | new | [-1000000, 1000000] | 1 |
| DoubleMLAPO | tune | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | new | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | tune | [-1000000, 1000000] | 1 |
| DoubleMLBLP | basis | [-1000000, 1000000] | 1 |
| DoubleMLBLP | fit | [0, 0] | 1 |
| DoubleMLBLP | hac_se | [0, 0] | 2 |
| DoubleMLBLP | hac_se | [0, 0] | 4 |
| DoubleMLBLP | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLBLP | var_y | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | coef | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | new | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | tune | [-1000000, 1000000] | 1 |
| DoubleMLDID | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLDID | new | [-1000000, 1000000] | 1 |
| DoubleMLDID | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | fit | [0, 0] | 1 |
| DoubleMLDIDCS | fit | [0, 0] | 1 |
| DoubleMLDIDCS | fit | [0, 0] | 1 |
| DoubleMLDIDCS | fit | [0, 0] | 1 |
| DoubleMLDIDCS | fit | [0, 0] | 1 |
| DoubleMLDIDCS | fit | [0, 0] | 1 |
| DoubleMLDIDCS | fit | [0, 0] | 1 |
| DoubleMLDIDCS | fit | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | new | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | coef | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | new | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | tune | [-1000000, 1000000] | 1 |
| DoubleMLIRM | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLIRM | new | [-1000000, 1000000] | 1 |
| DoubleMLIRM | tune | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | coef | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | confint | [1.959963984540054, 1.959963984540054] | 1 |
| DoubleMLLPLR | new | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | tune | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | coef | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | new | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | tune | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | coef | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | confint | [1.959963984540054, 1.959963984540054] | 1 |
| DoubleMLPLPR | new | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | new | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | tune | [-1000000, 1000000] | 1 |
| DoubleMLPLR | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLPLR | new | [-1000000, 1000000] | 1 |
| DoubleMLPLR | tune | [-1000000, 1000000] | 1 |
| DoubleMLQTE | coefs | [-1000000, 1000000] | 1 |
| DoubleMLQTE | confint | [0, 0] | 2 |
| DoubleMLQTE | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLQTE | tune | [-1000000, 1000000] | 1 |
| DoubleMLRDD | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tune | [-1000000, 1000000] | 1 |
| DoubleMLSSM | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLSSM | new | [-1000000, 1000000] | 1 |
| DoubleMLSSM | psi_a | [-1000000, 1000000] | 1 |
| DoubleMLSSM | psi_b | [-1000000, 1000000] | 1 |
| DoubleMLSSM | tune | [-1000000, 1000000] | 1 |
| GBClassifier | new | [-1000000, 1000000] | 1 |
| GBLearner | new | [-1000000, 1000000] | 1 |
| Matrix | from_rows | [0, 64] | 1 |
| RFClassifier | new | [-1000000, 1000000] | 1 |
| RFLearner | new | [-1000000, 1000000] | 1 |
| aggregate_time | n_groups | [0, 64] | 1 |
| bh_step_up_sorted | alpha | [-1000000, 1000000] | 1 |
| bootstrap_indices | n_obs | [-1000000, 1000000] | 1 |
| build_bootstrap_dgp | row | [0, 0] | 3 |
| build_clustered_dgp | row | [0, 0] | 3 |
| build_lzz2020_dgp | alpha | [-1000000, 1000000] | 1 |
| build_panel_dgp | n_units | [-1000000, 1000000] | 1 |
| build_row_dgp | n_periods | [-1000000, 1000000] | 1 |
| cart_fit | best_threshold | [0, 0] | 1 |
| compute_score | mean_d0t0 | [0, 0] | 1 |
| compute_score | mean_d0t1 | [0, 0] | 1 |
| compute_score | mean_d1t0 | [0, 0] | 1 |
| compute_score | mean_d1t1 | [0, 0] | 1 |
| crossfit_nuisance | n_rep | [-1000000, 1000000] | 1 |
| cs_bin_panel_subset | n_c | [0, 1000001] | 7 |
| cs_bin_panel_subset | n_g | [0, 1000001] | 7 |
| cs_bin_score_obs | mean_d | [0, 0] | 1 |
| cs_bin_score_obs | mean_t | [0, 0] | 1 |
| cvar_ipw_score | quantile | [-1000000, 1000000] | 1 |
| discover_groups_times | n | [0, 64] | 1 |
| enet_objective | l1_ratio | [-1000000, 1000000] | 1 |
| expand_v086_ref_hc0 | acc | [0, 0] | 1 |
| expand_v087_ref_hc0 | acc | [0, 0] | 1 |
| expand_v089_ref_hc0 | acc | [0, 0] | 1 |
| expand_v090_near_zero | x | [-1000000, 1000000] | 1 |
| expand_v091_iivm_data | n | [-1000000, 1000000] | 1 |
| expand_v091_iivm_data | p | [-1000000, 1000000] | 1 |
| expand_v092_lplr_data | n | [-1000000, 1000000] | 1 |
| expand_v092_lplr_data | p | [-1000000, 1000000] | 1 |
| expand_v100_psi_b_row | j | [-1000000, 1000000] | 1 |
| expand_v100_psi_b_row | m | [-1000000, 1000000] | 1 |
| expand_v100_psi_b_row | n | [-1000000, 1000000] | 1 |
| gaussian_kde_weighted | h | [-1000000, 1000000] | 1 |
| gaussian_kde_weighted | n | [0, 64] | 1 |
| gaussian_kde_weighted | x | [-1000000, 1000000] | 1 |
| irm_style_sensitivity | n | [0, 64] | 1 |
| isotonic_calibrate_cv | n | [0, 64] | 1 |
| joint_sensitivity | alpha | [-1000000, 1000000] | 1 |
| make_did_CS2021 | n_units | [-250000, 250000] | 1 |
| make_did_SZ2020 | n_units | [-500000, 500000] | 1 |
| make_did_cs_CS2021 | seed | [-1000000, 1000000] | 1 |
| make_lplr_LZZ2020 | alpha | [-1000000, 1000000] | 1 |
| make_lplr_LZZ2020 | idx_a | [0, 0] | 2 |
| make_lplr_LZZ2020 | idx_b | [1, 1] | 2 |
| make_pliv_CHS2015 | dim_x | [-1000000, 1000000] | 1 |
| make_pliv_CHS2015 | idx_a | [0, 0] | 3 |
| make_pliv_CHS2015 | idx_b | [1, 1] | 3 |
| make_pliv_CHS2015 | n_obs | [-1000000, 1000000] | 1 |
| make_pliv_CHS2015 | theta | [-1000000, 1000000] | 1 |
| make_plpr_CP2025 | half_a | [-124999, 125000] | 1 |
| make_plpr_CP2025 | half_b | [2, 2] | 1 |
| make_plpr_CP2025 | half_n | [-499999, 500000] | 1 |
| make_plpr_CP2025 | half_z | [-1073741823, 1073741823] | 1 |
| make_plpr_CP2025 | true_n | [-1000000, 1000000] | 1 |
| outcome_indicator | theta | [-1000000, 1000000] | 1 |
| policy_tree_build | depth | [-1000000, 1000000] | 1 |
| policy_tree_predict | row | [-1000000, 1000000] | 1 |
| preprocess_did_binary | i | [0, 1000000] | 4 |
| preprocess_did_binary | j | [1, 1000005] | 18 |
| rdd_kernel_weights | data | [-1000000, 1000000] | 1 |
| rdd_nn_matched_sigma4 | a | [-1000001, 999999] | 12 |
| rdd_nn_matched_sigma4 | b | [0, 1000004] | 12 |
| rdd_pilot_stage | nnmatch | [-1000000, 1000000] | 1 |
| romano_wolf_p_adjust | cv | [0, 0] | 10 |
| sandwich_variance | n_obs | [-1000000, 1000000] | 1 |
| solve_ipw_root | quantile | [-1000000, 1000000] | 1 |
| solve_pq | widen_attempts | [0, 20] | 6 |
| v106_build_panel | theta0 | [-1000000, 1000000] | 1 |
| v109_drawn_reps | n_folds | [-1000000, 1000000] | 1 |
| v120_max_abs_diff | worst | [0, 0] | 1 |
| v121_max_abs_diff | worst | [0, 0] | 1 |
| v1440_plr_fit | data_seed | [-1000000, 1000000] | 1 |
| v1500_conforming_data | n | [800, 800] | 1 |
| v1500_conforming_data | p | [3, 3] | 1 |
| var_est_cluster | n_folds | [-1000000, 1000000] | 1 |
| var_est_cluster | n_units | [0, 64] | 1 |
| var_est_with_jacobian | n | [0, 64] | 1 |
| zz_gate_y_variant | scale | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | coefs | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | confint | [0, 0] | 2 |
| DoubleMLAPOS | new | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | tune | [-1000000, 1000000] | 1 |
| DoubleMLBLP | hac_se | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | new | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | fit | [0, 1000001] | 18 |
| DoubleMLDIDCS | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSData | new | [0, 64] | 1 |
| DoubleMLData | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | new | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | tune | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | new | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | tune | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | new | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | tune | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | new | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | tune | [-1000000, 1000000] | 1 |
| DoubleMLPQ | confint | [-1000000, 1000000] | 1 |
| DoubleMLPQ | new | [-1000000, 1000000] | 1 |
| DoubleMLRDD | hac_se | [-1000000, 1000000] | 1 |
| DoubleMLRDD | kernel | [-1000000, 1000000] | 1 |
| DoubleMLRDD | new | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc | [-1000000, 1000000] | 1 |
| FitCache | from_fit | [-1000000, 1000000] | 1 |
| FitCache | from_fit | [-1000000, 1000000] | 1 |
| FitCache | is_valid | [-1000000, 1000000] | 1 |
| FitCache | is_valid | [-1000000, 1000000] | 1 |
| Matrix | from_array | [-1000000, 1000000] | 1 |
| Matrix | from_array | [-1000000, 1000000] | 1 |
| PSProcessor | adjust_ps | [0, 64] | 1 |
| aggregate_event | n_groups | [0, 64] | 1 |
| aggregate_group | n_groups | [0, 64] | 1 |
| aggregate_time | n_periods | [0, 64] | 1 |
| bias_corrected_theta | acc | [0, 0] | 1 |
| build_irm_tune_data | seed | [-1000000, 1000000] | 1 |
| build_iv_clustered_dgp | n | [-2147483648, 2147483647] | 1 |
| build_iv_clustered_dgp | p | [3, 3] | 1 |
| cs_bin_panel_subset | data | [-1000000, 1000000] | 1 |
| cvar_inner_crossfit | seed | [-1000000, 1000000] | 1 |
| enet_fit_tail | self_alpha | [-1000000, 1000000] | 1 |
| expand_v087_ssm_data | idx | [-2147483648, 2147483647] | 2 |
| expand_v100_didcs_data | n | [800, 800] | 1 |
| expand_v100_didcs_data | p | [3, 3] | 1 |
| expand_v100_live_cells | f | [-1000000, 1000000] | 1 |
| kfold_stratified | n_folds | [-1000000, 1000000] | 1 |
| make_did_CS2021 | n_groups | [4, 4] | 1 |
| make_did_SZ2020 | n_groups | [2, 2] | 1 |
| make_did_cs_CS2021 | dim_x | [-1000000, 1000000] | 1 |
| make_did_cs_CS2021 | idx_a | [0, 0] | 4 |
| make_did_cs_CS2021 | idx_b | [1, 1] | 4 |
| make_did_cs_CS2021 | n_obs | [-1000000, 1000000] | 1 |
| make_did_cs_CS2021 | theta | [-1000000, 1000000] | 1 |
| make_pliv_CHS2015 | half_n | [-499999, 500000] | 1 |
| make_pliv_CHS2015 | half_z | [-1073741823, 1073741823] | 1 |
| make_plpr_CP2025 | n_units | [-250000, 250000] | 1 |
| make_plr_CCDDHNR2018 | a_0 | [1, 1] | 1 |
| make_plr_CCDDHNR2018 | a_1 | [0.25, 0.25] | 1 |
| make_plr_CCDDHNR2018 | acc | [-700000, 700000] | 18 |
| make_plr_CCDDHNR2018 | b_0 | [1, 1] | 1 |
| make_plr_CCDDHNR2018 | b_1 | [0.25, 0.25] | 1 |
| make_plr_CCDDHNR2018 | s_1 | [1, 1] | 1 |
| make_plr_CCDDHNR2018 | s_2 | [1, 1] | 1 |
| make_plr_turrell2018 | acc | [-500000, 500000] | 18 |
| make_simple_rdd_dgp | half | [-499999, 500000] | 1 |
| make_simple_rdd_dgp | seed | [-1000000, 1000000] | 1 |
| newton_solve_score | theta | [-1000000, 1000000] | 1 |
| prelim_beta_per_fold | den | [0, 0] | 1 |
| prelim_beta_per_fold | num | [0, 0] | 1 |
| qte_leverage_divisor | eps | [1, 1] | 1 |
| rdd_nn_matched_sigma4 | hi | [-1, 1000000] | 14 |
| rdd_nn_matched_sigma4 | lo | [0, 1000001] | 14 |
| rdd_pilot_bandwidth | data | [-1000000, 1000000] | 1 |
| romano_wolf_p_adjust | p_k | [-999999, 1000001] | 12 |
| single_psi_sensitivity | n | [0, 64] | 1 |
| stratified_kfold | n_folds | [-1000000, 1000000] | 1 |
| v085_dbl_array_close | tol | [-1000000, 1000000] | 1 |
| v098_leaf_index_walk | row | [-1000000, 1000000] | 1 |
| v106_build_panel | n_units | [-1000000, 1000000] | 1 |
| v107_plpr_data | n_periods | [4, 4] | 1 |
| v1500_no_base_period | row | [0, 0] | 3 |
| weighted_xtx_transpose | s | [0, 0] | 3 |
| DoubleMLAPO | confint | [-1000000, 1000000] | 1 |
| DoubleMLAPO | new | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | fitted | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | fitted | [-1000000, 1000000] | 1 |
| DoubleMLDID | confint | [-1000000, 1000000] | 1 |
| DoubleMLDID | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | confint | [0, 0] | 2 |
| DoubleMLDIDCS | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | se_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | tune | [-1000000, 1000000] | 1 |
| DoubleMLIRM | confint | [-1000000, 1000000] | 1 |
| DoubleMLIRM | new | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | confint | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | new | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | fit | [0, 0] | 2 |
| DoubleMLPLPR | fit | [0, 0] | 2 |
| DoubleMLPLR | confint | [-1000000, 1000000] | 1 |
| DoubleMLPLR | new | [-1000000, 1000000] | 1 |
| DoubleMLPQ | new | [-1000000, 1000000] | 1 |
| DoubleMLQTE | confint | [-1000000, 1000000] | 1 |
| DoubleMLQTE | new | [-1000000, 1000000] | 1 |
| DoubleMLQTE | psi_row | [-1000000, 1000000] | 1 |
| DoubleMLRDD | confint | [-1000000, 1000000] | 1 |
| DoubleMLRDD | n_local | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_se | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_se | [-1000000, 1000000] | 1 |
| DoubleMLSSM | confint | [-1000000, 1000000] | 1 |
| DoubleMLSSM | new | [-1000000, 1000000] | 1 |
| ElasticNet | new | [-1000000, 1000000] | 1 |
| ElasticNet | new | [-1000000, 1000000] | 1 |
| GBLearner | new | [-1000000, 1000000] | 1 |
| GBLearner | new | [-1000000, 1000000] | 1 |
| LogisticRegression | fit | [0, 0] | 6 |
| RFLearner | new | [-1000000, 1000000] | 1 |
| aggregate_event | n_periods | [0, 64] | 1 |
| aggregate_group | n_periods | [0, 64] | 1 |
| aggregate_time | sum_w2_se2 | [0, 0] | 2 |
| build_bootstrap_dgp | y_val | [0, 0] | 3 |
| build_cross_section_dgp | n | [-1000000, 1000000] | 1 |
| build_cross_section_dgp | p | [-1000000, 1000000] | 1 |
| build_panel_dgp | n_periods | [-1000000, 1000000] | 1 |
| cart_fit | min_samples_leaf | [-1000000, 1000000] | 1 |
| crossfit_nuisance | n_folds | [-1000000, 1000000] | 1 |
| expand_v086_ref_hc0 | m_val | [-1000000, 1000000] | 1 |
| expand_v086_ref_hc0 | n_obs | [-1000000, 1000000] | 1 |
| expand_v087_ref_hc0 | m_val | [-1000000, 1000000] | 1 |
| expand_v087_ref_hc0 | n_obs | [-1000000, 1000000] | 1 |
| expand_v089_ref_cluster | n | [0, 64] | 1 |
| expand_v089_ref_hc0 | m_val | [-1000000, 1000000] | 1 |
| expand_v089_ref_hc0 | n_obs | [-1000000, 1000000] | 1 |
| expand_v091_cluster_ids | n | [-1000000, 1000000] | 1 |
| expand_v091_iivm_data | idx | [-2147483648, 2147483647] | 3 |
| expand_v092_cluster_ids | n | [-1000000, 1000000] | 1 |
| expand_v093_cluster_ids | n | [-1000000, 1000000] | 1 |
| expand_v093_lpq_data | need | [-2000000, 2000000] | 1 |
| expand_v094_cluster_ids | n | [-1000000, 1000000] | 1 |
| expand_v095_cluster_ids | n | [-1000000, 1000000] | 1 |
| expand_v095_qte_data | need | [-2000000, 2000000] | 1 |
| expand_v100_cluster_ids | n | [-1000000, 1000000] | 1 |
| expand_v100_didcs_close | x | [-1000000, 1000000] | 1 |
| expand_v100_didcs_close | y | [-1000000, 1000000] | 1 |
| expand_v101_cluster_ids | n | [-1000000, 1000000] | 1 |
| expand_v101_qte_data | seed | [-1000000, 1000000] | 1 |
| gaussian_kde_weighted | acc | [0, 0] | 1 |
| make_did_CS2021 | n_periods | [4, 4] | 1 |
| make_did_CS2021 | panel_row | [0, 0] | 3 |
| make_did_SZ2020 | n_periods | [2, 2] | 1 |
| make_did_SZ2020 | panel_row | [0, 0] | 3 |
| make_did_cs_CS2021 | half_a | [-249999, 250000] | 1 |
| make_did_cs_CS2021 | half_n | [-499999, 500000] | 1 |
| make_did_cs_CS2021 | half_z | [-1073741823, 1073741823] | 1 |
| make_did_cs_CS2021 | true_n | [-1000000, 1000000] | 1 |
| make_irm_data | n_normals_x | [-2147483648, 2147483647] | 1 |
| make_plr_CCDDHNR2018 | seed | [-1000000, 1000000] | 1 |
| make_plr_turrell2018 | seed | [-1000000, 1000000] | 1 |
| make_simple_plr_data | seed | [-1000000, 1000000] | 1 |
| make_simple_rdd_dgp | idx_a | [0, 0] | 2 |
| make_simple_rdd_dgp | idx_b | [1, 1] | 2 |
| make_simple_rdd_dgp | n_obs | [-1000000, 1000000] | 1 |
| make_simple_rdd_dgp | theta | [-1000000, 1000000] | 1 |
| make_ssm_data | n_normals_x | [-2147483648, 2147483647] | 1 |
| pq_score_orthogonal | theta | [-1000000, 1000000] | 1 |
| rdd_hac_require_df | n_left | [-1000000, 1000000] | 1 |
| rdd_kernel_weights | cutoff | [-1000000, 1000000] | 1 |
| rdd_local_side_count | data | [-1000000, 1000000] | 1 |
| rdd_local_side_count | side | [-1000000, 1000000] | 1 |
| rdd_nn_matched_sigma4 | acc | [0, 0] | 1 |
| rdd_nn_matched_sigma4 | mid | [0, 1000000] | 12 |
| rdd_nn_matched_sigma4 | n_l | [0, 64] | 1 |
| rdd_nn_matched_sigma4 | n_r | [0, 64] | 1 |
| rdd_nn_matched_sigma4 | sum | [0, 0] | 2 |
| sandwich_variance_hc0 | acc | [0, 0] | 1 |
| sandwich_variance_hc2 | acc | [0, 0] | 1 |
| sandwich_variance_hc2 | eps | [1, 1] | 1 |
| sandwich_variance_hc3 | acc | [0, 0] | 1 |
| sandwich_variance_hc3 | eps | [1, 1] | 1 |
| sort_indices_by_feature | j | [-1, 0] | 6 |
| sort_indices_by_feature | n | [0, 64] | 1 |
| v115_exact_quadratic | jump | [-1000000, 1000000] | 1 |
| v125_lpq_floor_dominant | n | [500, 500] | 1 |
| v128_cs_data | cohort_count | [3, 3] | 1 |
| v128_cs_data | n_per_cohort | [-1000000, 1000000] | 1 |
| v130_cs_data | cohort_count | [3, 3] | 1 |
| v130_cs_data | n_per_cohort | [-1000000, 1000000] | 1 |
| v1500_conforming_data | row | [0, 0] | 3 |
| ConstantLearner | new | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | confint | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | new | [-1000000, 1000000] | 1 |
| DoubleMLBLP | leverage | [-1000000, 1000000] | 1 |
| DoubleMLBLP | n_params | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | confint | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | se | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | fit | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | new | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | confint | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | new | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | confint | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | new | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | new | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | confint | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | new | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | confint | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | new | [-1000000, 1000000] | 1 |
| DoubleMLPQ | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPQ | confint | [-1000000, 1000000] | 1 |
| DoubleMLPQ | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLPQ | learner_l | [-1000000, 1000000] | 1 |
| DoubleMLPQ | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLPQ | m_inv_1x1 | [-1000000, 1000000] | 1 |
| DoubleMLPQ | new | [-1000000, 1000000] | 1 |
| DoubleMLRDD | leverage | [-1000000, 1000000] | 1 |
| FitCache | from_fit | [-1000000, 1000000] | 1 |
| FitCache | is_valid | [-1000000, 1000000] | 1 |
| GBClassifier | new | [-1000000, 1000000] | 1 |
| GainStatsSource | new | [-1000000, 1000000] | 1 |
| GainStatsSource | new | [-1000000, 1000000] | 1 |
| RFClassifier | new | [-1000000, 1000000] | 1 |
| aggregate_group | sum_w2_se2 | [0, 0] | 2 |
| aggregate_time | sum_w_theta | [0, 0] | 2 |
| bias_corrected_theta | acc_c | [0, 0] | 1 |
| build_bootstrap_dgp | cohort | [0, 0] | 2 |
| build_bootstrap_dgp | theta0 | [1, 1] | 1 |
| build_clustered_dgp | theta0 | [-1000000, 1000000] | 1 |
| build_iv_clustered_dgp | row | [0, 0] | 3 |
| build_row_unit_map | n_units | [0, 64] | 1 |
| compute_score | mean_d0t0_pw | [0, 0] | 1 |
| compute_score | mean_d0t1_pw | [0, 0] | 1 |
| compute_sensitivity_bias | n | [0, 64] | 1 |
| cs_bin_crossfit_nuisance | n | [0, 64] | 1 |
| cs_bin_crossfit_nuisance | p | [-1000000, 1000000] | 1 |
| cs_bin_score_obs | mean_d0t0 | [0, 0] | 1 |
| cs_bin_score_obs | mean_d0t1 | [0, 0] | 1 |
| cs_bin_score_obs | mean_d1t0 | [0, 0] | 1 |
| cs_bin_score_obs | mean_d1t1 | [0, 0] | 1 |
| cvar_inner_crossfit | q_comp | [-999999, 1000001] | 1 |
| did_bootstrap_t_stat | n_obs | [-1000000, 1000000] | 1 |
| enet_coordinate_descent | ym | [-1000000, 1000000] | 1 |
| enet_soft_threshold | thresh | [-1000000, 1000000] | 1 |
| expand_gt_keyword | n_groups | [0, 64] | 1 |
| expand_v088_pinned_close | x | [-1000000, 1000000] | 1 |
| expand_v088_pinned_close | y | [-1000000, 1000000] | 1 |
| expand_v089_ref_cluster | m2 | [-1000000000000, 1000000000000] | 1 |
| expand_v092_lplr_data | need | [-2147483648, 2147483647] | 1 |
| expand_v100_didcs_data | row | [0, 0] | 3 |
| fit_g_subset_predict | sub_n | [0, 1000001] | 6 |
| holm_bonferroni_p_adjust | n | [0, 64] | 1 |
| irm_style_sensitivity | cf_d | [-1000000, 1000000] | 1 |
| irm_style_sensitivity | cf_y | [-1000000, 1000000] | 1 |
| joint_sensitivity | joint_rv | [1.0000000000000002e+300, 1.0000000000000002e+300] | 1 |
| make_confounded_plr_data | j | [-1, 0] | 18 |
| make_confounded_plr_data | s | [0, 0] | 3 |
| make_did_CS2021 | half_alpha | [-124999, 125000] | 1 |
| make_did_cs_CS2021 | n_units | [-500000, 500000] | 1 |
| make_iivm_data | n_normals_x | [-2147483648, 2147483647] | 1 |
| make_irm_confounded_data | j | [-1, 0] | 18 |
| make_irm_confounded_data | s | [0, 0] | 3 |
| make_plpr_CP2025 | n_periods | [4, 4] | 1 |
| make_plr_CCDDHNR2018 | dim_x | [-1000000, 1000000] | 1 |
| make_plr_CCDDHNR2018 | idx_a | [0, 0] | 4 |
| make_plr_CCDDHNR2018 | idx_b | [1, 1] | 4 |
| make_plr_CCDDHNR2018 | n_obs | [-1000000, 1000000] | 1 |
| make_plr_CCDDHNR2018 | theta | [-1000000, 1000000] | 1 |
| make_plr_turrell2018 | dim_x | [20, 20] | 1 |
| make_plr_turrell2018 | idx_a | [0, 0] | 3 |
| make_plr_turrell2018 | idx_b | [1, 1] | 3 |
| make_plr_turrell2018 | n_obs | [-1000000, 1000000] | 1 |
| make_plr_turrell2018 | theta | [-1000000, 1000000] | 1 |
| policy_tree_cache_decode | b | [-5000000, 5000000] | 1 |
| policy_tree_leaf_index | acc | [-1000000, 1000000] | 1 |
| policy_tree_leaf_index | row | [-1000000, 1000000] | 1 |
| preprocess_did_binary | data | [-1000000, 1000000] | 1 |
| qte_leverage_divisor | n_obs | [-1000000, 1000000] | 1 |
| rdd_hac_require_df | n_right | [-1000000, 1000000] | 1 |
| rdd_local_side_count | count | [0, 1000001] | 6 |
| reg_mean_one_weights | total | [0, 0] | 1 |
| sandwich_variance | n_params | [-1000000, 1000000] | 1 |
| stratified_half_split | seed | [-1000000, 1000000] | 1 |
| trim_predictions | threshold | [-1000000, 1000000] | 1 |
| v106_build_panel | n_periods | [-1000000, 1000000] | 1 |
| DoubleMLAPO | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLAPO | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLAPO | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLAPO | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLBLP | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLBLP | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLBLP | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | new | [-1000000, 1000000] | 1 |
| DoubleMLDID | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDID | confint | [-1000000, 1000000] | 1 |
| DoubleMLDID | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLDID | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLDID | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | fit | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | coef_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | confint | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | fit | [0, 1000004] | 11 |
| DoubleMLDIDCS | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDData | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | confint | [0, 0] | 2 |
| DoubleMLDIDMulti | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | tune | [-1000000, 1000000] | 1 |
| DoubleMLIRM | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLIRM | confint | [-1000000, 1000000] | 1 |
| DoubleMLIRM | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLIRM | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLIRM | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | warnings | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | confint | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | m_inv_1x1 | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | new | [-1000000, 1000000] | 1 |
| DoubleMLPLR | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPLR | confint | [-1000000, 1000000] | 1 |
| DoubleMLPLR | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLPQ | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPQ | fit_cluster | [0, 0] | 2 |
| DoubleMLPQ | n_features | [-1000000, 1000000] | 1 |
| DoubleMLQTE | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLQTE | confint | [-1000000, 1000000] | 1 |
| DoubleMLQTE | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLQTE | learner_l | [-1000000, 1000000] | 1 |
| DoubleMLQTE | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLRDD | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLRDD | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLRDD | new | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_se | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_se | [-1000000, 1000000] | 1 |
| DoubleMLRDDData | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLSSM | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLSSM | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLSSM | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLSSM | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLSSMData | n_obs | [-1000000, 1000000] | 1 |
| aggregate_group | sum_w_theta | [0, 0] | 2 |
| bh_step_up_sorted | rejectmax | [-1, 0] | 3 |
| build_bootstrap_dgp | n_units | [240, 240] | 1 |
| build_clustered_dgp | n_units | [-1000000, 1000000] | 1 |
| build_cross_section_dgp | att | [-1000000, 1000000] | 1 |
| cluster_sandwich_variance | n | [0, 64] | 1 |
| cs_bin_panel_subset | g_value | [-1000000, 1000000] | 1 |
| cvar_inner_crossfit | n_folds | [-1000000, 1000000] | 1 |
| draw_bootstrap_weights | seed | [-1000000, 1000000] | 1 |
| enet_coordinate_descent | l1n | [0, 0] | 5 |
| enet_coordinate_descent | l2n | [0, 0] | 5 |
| enet_coordinate_descent | rho | [0, 0] | 10 |
| enet_coordinate_descent | rss | [0, 0] | 5 |
| enet_coordinate_descent | tol | [-1000000, 1000000] | 1 |
| enet_coordinate_descent | yn2 | [0, 0] | 1 |
| enet_fit_tail | self_max_iter | [-1000000, 1000000] | 1 |
| expand_gt_keyword | n_periods | [0, 64] | 1 |
| expand_unit_folds_to_rows | n | [0, 64] | 1 |
| expand_v087_ref_leverage | m2 | [-1000000000000, 1000000000000] | 1 |
| expand_v089_ref_cluster | acc | [0, 0] | 1 |
| expand_v089_ref_leverage | m2 | [-1000000000000, 1000000000000] | 1 |
| expand_v090_hc_identities | n | [-1000000, 1000000] | 1 |
| expand_v095_qte_data_wide | n | [-1000000, 1000000] | 1 |
| expand_v100_didmulti_cell | m | [-1000000, 1000000] | 1 |
| expand_v100_didmulti_data | n | [800, 800] | 1 |
| expand_v100_didmulti_data | p | [3, 3] | 1 |
| irm_style_sensitivity | theta | [-1000000, 1000000] | 1 |
| make_did_CS2021 | n_normals_x | [-2147483648, 2147483647] | 1 |
| make_did_CS2021 | x_dot_gamma | [0, 0] | 3 |
| make_did_SZ2020 | n_normals_x | [-2147483648, 2147483647] | 1 |
| make_did_SZ2020 | x_dot_gamma | [0, 0] | 3 |
| make_did_cs_CS2021 | n_groups | [2, 2] | 1 |
| make_plr_CCDDHNR2018 | half_n | [-499999, 500000] | 1 |
| make_plr_CCDDHNR2018 | half_z | [-1073741823, 1073741823] | 1 |
| make_plr_turrell2018 | half_n | [-499999, 500000] | 1 |
| make_plr_turrell2018 | half_z | [-9999999, 10000000] | 1 |
| policy_tree_build | threshold | [0, 0] | 2 |
| rdd_local_side_count | cutoff | [-1000000, 1000000] | 1 |
| rdd_nn_matched_sigma4 | taken | [0, 1000001] | 12 |
| sandwich_variance_hc0 | acc_c | [0, 0] | 1 |
| sandwich_variance_hc0 | n_obs | [-1000000, 1000000] | 1 |
| sandwich_variance_hc1 | n_obs | [-1000000, 1000000] | 1 |
| sandwich_variance_hc2 | acc_c | [0, 0] | 1 |
| sandwich_variance_hc2 | n_obs | [-1000000, 1000000] | 1 |
| sandwich_variance_hc3 | acc_c | [0, 0] | 1 |
| sandwich_variance_hc3 | n_obs | [-1000000, 1000000] | 1 |
| single_psi_sensitivity | cf_d | [-1000000, 1000000] | 1 |
| single_psi_sensitivity | cf_y | [-1000000, 1000000] | 1 |
| v098_leaf_means_match_raw | f | [-1000000, 1000000] | 1 |
| v1500_conforming_data | theta | [1, 1] | 1 |
| v1500_conforming_data | y_val | [0, 0] | 3 |
| v1500_no_base_period | cohort | [0, 0] | 2 |
| var_est_with_jacobian | gamma | [0, 0] | 1 |
| DoubleMLAPO | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLAPO | n_features | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | boot_seed | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | confint | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLBLP | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | new | [-1000000, 1000000] | 1 |
| DoubleMLDID | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | coef | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinaryData | new | [0, 64] | 1 |
| DoubleMLDIDCS | group_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | n_groups | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | se | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | new | [-1, -1] | 1 |
| DoubleMLDIDMulti | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | tune | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | confint | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | learner_r | [-1000000, 1000000] | 1 |
| DoubleMLIIVMData | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLIRM | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLIRM | n_features | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | n_features | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | confint | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLPLIVData | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLPLR | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPLR | n_features | [-1000000, 1000000] | 1 |
| DoubleMLPQ | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLPQ | fit_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPQ | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | fit | [-1000000, 1000000] | 1 |
| DoubleMLQTE | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLQTE | fit_cluster | [0, 0] | 4 |
| DoubleMLQTE | n_features | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bandwidth_mse | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLRDD | hac_se | [0, 0] | 1 |
| DoubleMLRDD | n_features | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_se_rb | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_se_rb | [-1000000, 1000000] | 1 |
| DoubleMLSSM | bootstrap | [-1000000, 1000000] | 1 |
| FitCache | from_fit | [-1000000, 1000000] | 1 |
| FitCache | is_valid | [-1000000, 1000000] | 1 |
| GBClassifier | new | [-1000000, 1000000] | 1 |
| GBClassifier | new | [-1000000, 1000000] | 1 |
| LinearRegression | new | [-1000000, 1000000] | 1 |
| LogisticRegression | fit | [0, 0] | 5 |
| LogisticRegression | fit | [0, 1000001] | 6 |
| LogisticRegression | fit | [-1000000, 1000000] | 1 |
| RFClassifier | new | [-1000000, 1000000] | 1 |
| build_panel_dgp | alpha_scale~ | [-1000000, 1000000] | 1 |
| check_sample_splitting | n_obs | [-1000000, 1000000] | 1 |
| compute_sensitivity_bias | nu2 | [-1000000, 1000000] | 1 |
| cvar_inner_crossfit | quantile | [-1000000, 1000000] | 1 |
| draw_bootstrap_weights | n_obs | [-1000000, 1000000] | 1 |
| enet_coordinate_descent | iter | [0, 1000001] | 6 |
| enet_coordinate_descent | w_l1 | [0, 0] | 5 |
| expand_v087_cs_binary_data | p | [-1000000, 1000000] | 1 |
| expand_v087_ref_leverage | acc | [0, 0] | 1 |
| expand_v087_ref_leverage | eps | [1, 1] | 1 |
| expand_v089_ref_leverage | acc | [0, 0] | 1 |
| expand_v089_ref_leverage | eps | [1, 1] | 1 |
| expand_v094_pq_data_scaled | n | [-1000000, 1000000] | 1 |
| expand_v100_didcs_data | y_val | [0, 0] | 3 |
| expand_v100_didmulti_cell | gi | [-1, 0] | 3 |
| expand_v100_didmulti_cell | pi | [-1, 0] | 3 |
| fit_g_subset_predict | d_value | [-1000000, 1000000] | 1 |
| fit_g_subset_predict | n_train | [0, 64] | 1 |
| fit_g_subset_predict | t_value | [-1000000, 1000000] | 1 |
| joint_sensitivity | joint_rv_q | [1.0000000000000002e+300, 1.0000000000000002e+300] | 1 |
| make_confounded_plr_data | acc | [-700000, 700000] | 18 |
| make_did_CS2021 | n_per_cohort | [-62500, 62500] | 1 |
| make_did_SZ2020 | n_per_cohort | [-250000, 250000] | 1 |
| make_did_cs_CS2021 | n_periods | [2, 2] | 1 |
| make_did_cs_CS2021 | panel_row | [0, 0] | 3 |
| make_irm_confounded_data | acc | [-700000, 700000] | 18 |
| make_pliv_multiway_cluster | j | [-1, 0] | 18 |
| make_pliv_multiway_cluster | s | [0, 0] | 3 |
| make_plpr_CP2025 | n_normals_x | [-2147483648, 2147483647] | 1 |
| newton_solve_score | max_iter~ | [-1000000, 1000000] | 1 |
| single_psi_sensitivity | theta | [-1000000, 1000000] | 1 |
| single_psi_sensitivity | y_sum | [0, 0] | 1 |
| tune_score_grid | n_folds_tune | [-1000000, 1000000] | 1 |
| v097_dgp_constant_leverage | n | [-1000000, 1000000] | 1 |
| v123_ssm_selection_extreme | n | [400, 400] | 1 |
| v1500_conforming_data | cohort | [0, 0] | 2 |
| v1500_no_base_period | n_units | [180, 180] | 1 |
| DoubleMLAPO | bootstrap | [0, 0] | 1 |
| DoubleMLAPO | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLAPO | fit_cluster | [0, 0] | 1 |
| DoubleMLAPO | fit_cluster | [-1000000, 1000000] | 1 |
| DoubleMLAPO | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | n_rep_boot | [-1000000, 1000000] | 1 |
| DoubleMLBLP | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLBLP | orth_signal | [-1000000, 1000000] | 1 |
| DoubleMLBLP | predictions | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | n_features | [-1000000, 1000000] | 1 |
| DoubleMLDID | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLDID | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | confint | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | n_periods | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | period_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | fit | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | new | [0, 0] | 1 |
| DoubleMLData | n_features | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLIRM | bootstrap | [0, 0] | 1 |
| DoubleMLIRM | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLIRM | fit_cluster | [0, 0] | 1 |
| DoubleMLIRM | fit_cluster | [-1000000, 1000000] | 1 |
| DoubleMLIRM | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPLR | bootstrap | [0, 0] | 1 |
| DoubleMLPLR | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLPLR | fit_cluster | [0, 0] | 1 |
| DoubleMLPLR | fit_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLR | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLPLR | tune_result | [-1000000, 1000000] | 1 |
| DoubleMLQTE | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLQTE | fit_cluster | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bootstrap | [0, 0] | 1 |
| DoubleMLRDD | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLRDD | fit | [0, 0] | 1 |
| DoubleMLRDD | hac_se | [0, 0] | 1 |
| DoubleMLRDD | kernel_weights | [-1000000, 1000000] | 1 |
| DoubleMLSSM | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLSSM | sandwich_se | [-1000000, 1000000] | 1 |
| GBLearner | fit_weighted | [0, 0] | 1 |
| GBLearner | new | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp | [-1000000, 1000000] | 1 |
| JointSensitivityInput | new | [-1000000, 1000000] | 1 |
| build_bootstrap_dgp | n_periods | [4, 4] | 1 |
| build_clustered_dgp | n_periods | [-1000000, 1000000] | 1 |
| build_iv_clustered_dgp | theta0 | [-1000000, 1000000] | 1 |
| cluster_causal_param_and_se | n | [0, 64] | 1 |
| cluster_sandwich_variance | acc | [0, 0] | 1 |
| cross_fit_did | propensity_clip | [-1000000, 1000000] | 1 |
| cs_bin_crossfit_nuisance | seed | [-1000000, 1000000] | 1 |
| cs_bin_score_obs | mean_d0t0_pw | [0, 0] | 1 |
| cs_bin_score_obs | mean_d0t1_pw | [0, 0] | 1 |
| cvar_inner_crossfit | treatment | [-1000000, 1000000] | 1 |
| did_bootstrap_t_stat | n_thetas | [-1000000, 1000000] | 1 |
| double_cross_fit_predict | seed | [-1000000, 1000000] | 1 |
| expand_v089_did_binary_data | n | [-2000000, 2000000] | 1 |
| expand_v089_did_binary_data | p | [-1000000, 1000000] | 1 |
| expand_v089_ref_cluster | m_val | [-1000000, 1000000] | 1 |
| expand_v093_lpq_data_scaled | n | [-1000000, 1000000] | 1 |
| expand_v100_didcs_data | cohort | [0, 0] | 2 |
| expand_v100_didcs_data | theta0 | [1, 1] | 1 |
| expand_v100_didmulti_cell | idx | [-1000000, 1000000] | 1 |
| expand_v100_didmulti_data | row | [0, 0] | 3 |
| generic_bootstrap_t_stat | coef | [-1000000, 1000000] | 1 |
| generic_bootstrap_t_stat | seed | [-1000000, 1000000] | 1 |
| joint_sensitivity | joint_lower | [0, 0] | 1 |
| joint_sensitivity | joint_upper | [0, 0] | 1 |
| lplr_initial_theta | beta_start | [-1000000, 1000000] | 1 |
| make_confounded_plr_data | seed | [-1000000, 1000000] | 1 |
| make_irm_confounded_data | seed | [-1000000, 1000000] | 1 |
| make_irm_heterogeneous_data | j | [-1, 0] | 18 |
| make_irm_heterogeneous_data | s | [0, 0] | 3 |
| make_pliv_CHS2015 | n_normals_x | [-2147483648, 2147483647] | 1 |
| newton_solve_score | tol_theta~ | [-1000000, 1000000] | 1 |
| policy_tree_cache_decode | slot | [-1000000, 1000000] | 1 |
| policy_tree_cache_encode | slot | [0, 12] | 1 |
| policy_tree_ints_to_doubles | n | [0, 64] | 1 |
| preprocess_did_binary | g_value | [-1000000, 1000000] | 1 |
| preprocess_did_binary | pre_idx | [-1, -1] | 3 |
| rdd_nn_matched_sigma4 | nnmatch | [-1000000, 1000000] | 1 |
| single_psi_sensitivity | mb_sum | [0, 0] | 1 |
| solve_ipw_root | widen_attempts | [0, 20] | 6 |
| v1500_conforming_data | n_units | [200, 200] | 1 |
| var_est_with_jacobian | gamma_c | [0, 0] | 1 |
| DoubleMLAPOS | boot_method | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | se_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | coef | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | bootstrap | [-1, 0] | 6 |
| DoubleMLDIDMulti | bootstrap | [-1, 0] | 6 |
| DoubleMLDIDMulti | confint | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | se_at_idx | [-1, 0] | 3 |
| DoubleMLDIDMulti | se_at_idx | [-1, 0] | 3 |
| DoubleMLDIDMulti | t_stats | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | bootstrap | [0, 0] | 1 |
| DoubleMLIIVM | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | fit_cluster | [0, 0] | 1 |
| DoubleMLIIVM | fit_cluster | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLIRM | fit | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | bootstrap | [0, 0] | 1 |
| DoubleMLPLIV | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | fit_cluster | [0, 0] | 1 |
| DoubleMLPLIV | fit_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLPLR | fit | [-1000000, 1000000] | 1 |
| DoubleMLPQ | tune | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | new | [-1000000, 1000000] | 1 |
| DoubleMLQTE | m_inv_1x1_at | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_se_rb | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_se_rb | [-1000000, 1000000] | 1 |
| GBClassifier | fit_weighted | [1, 1] | 1 |
| GBLearner | new | [-1000000, 1000000] | 1 |
| JointSensitivityInput | new | [-1000000, 1000000] | 1 |
| LogisticRegression | fit | [-1000000, 1000000] | 1 |
| RFLearner | new | [-1000000, 1000000] | 1 |
| bias_corrected_theta | theta_hat | [-1000000, 1000000] | 1 |
| build_iv_clustered_dgp | n_units | [-1000000, 1000000] | 1 |
| cs_bin_crossfit_nuisance | n_rep | [-1000000, 1000000] | 1 |
| did_multi_inner_cell_at_idx | gi | [-1, 0] | 3 |
| did_multi_inner_cell_at_idx | pi | [-1, 0] | 3 |
| enet_coordinate_descent | l1_reg | [-1000000, 1000000] | 1 |
| enet_coordinate_descent | l2_reg | [-1000000, 1000000] | 1 |
| enet_coordinate_descent | n_iter | [0, 1000001] | 6 |
| expand_v087_cs_binary_data | row | [0, 0] | 3 |
| expand_v087_ref_leverage | m_val | [-1000000, 1000000] | 1 |
| expand_v087_ref_leverage | n_obs | [-1000000, 1000000] | 1 |
| expand_v087_ref_leverage | power | [-1000000, 1000000] | 1 |
| expand_v089_ref_leverage | m_val | [-1000000, 1000000] | 1 |
| expand_v089_ref_leverage | n_obs | [-1000000, 1000000] | 1 |
| expand_v089_ref_leverage | power | [-1000000, 1000000] | 1 |
| expand_v091_old_accumulator | m2 | [-1000000000000, 1000000000000] | 1 |
| expand_v095_qte_data_wide | need | [-2000000, 2000000] | 1 |
| expand_v100_didcs_data | n_units | [200, 200] | 1 |
| generic_bootstrap_t_stat | n_obs | [0, 64] | 1 |
| make_confounded_plr_data | dim_x | [-1000000, 1000000] | 1 |
| make_confounded_plr_data | idx_a | [0, 0] | 3 |
| make_confounded_plr_data | idx_b | [1, 1] | 3 |
| make_confounded_plr_data | n_obs | [-1000000, 1000000] | 1 |
| make_confounded_plr_data | theta | [-1000000, 1000000] | 1 |
| make_did_CS2021 | unit_in_cohort | [0, 62499] | 2 |
| make_did_SZ2020 | unit_in_cohort | [0, 249999] | 2 |
| make_did_cs_CS2021 | n_normals_x | [-2147483648, 2147483647] | 1 |
| make_did_cs_CS2021 | x_dot_gamma | [0, 0] | 3 |
| make_irm_confounded_data | dim_x | [-1000000, 1000000] | 1 |
| make_irm_confounded_data | idx_a | [0, 0] | 3 |
| make_irm_confounded_data | idx_b | [1, 1] | 3 |
| make_irm_confounded_data | n_obs | [-1000000, 1000000] | 1 |
| make_irm_confounded_data | theta | [-1000000, 1000000] | 1 |
| make_irm_discrete_treatments | j | [-1, 0] | 18 |
| make_irm_discrete_treatments | s | [0, 0] | 3 |
| make_pliv_multiway_cluster | acc | [-700000, 700000] | 18 |
| newton_solve_score | theta_start | [-1000000, 1000000] | 1 |
| preprocess_did_binary | eval_idx | [-1, -1] | 3 |
| sandwich_variance_hc0 | n_params | [-1000000, 1000000] | 1 |
| sandwich_variance_hc1 | n_params | [-1000000, 1000000] | 1 |
| sandwich_variance_hc2 | n_params | [-1000000, 1000000] | 1 |
| sandwich_variance_hc3 | n_params | [-1000000, 1000000] | 1 |
| single_psi_sensitivity | nu2_sum | [0, 0] | 1 |
| v120_check_l1_ratio_zero | total | [0, 0] | 1 |
| v120_check_l1_ratio_zero | worst | [0, 0] | 1 |
| v1500_no_base_period | n_periods | [3, 3] | 1 |
| var_est_with_jacobian | jacobian | [-1000000, 1000000] | 1 |
| DoubleMLAPO | predictions_g | [-1000000, 1000000] | 1 |
| DoubleMLAPO | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLAPO | tune | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | boot_t_stats | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | m_inv_1x1_at | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | psi_a_row_at | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | psi_b_row_at | [-1000000, 1000000] | 1 |
| DoubleMLBLP | cluster_hac_se | [0, 0] | 2 |
| DoubleMLBLP | cluster_hac_se | [0, 0] | 3 |
| DoubleMLBLP | confint_joint | [-1000000, 1000000] | 1 |
| DoubleMLDID | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLDID | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | confint | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | se_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | psi_a | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | psi_b | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | confint | [1.959963984540054, 1.959963984540054] | 1 |
| DoubleMLDIDMulti | p_adjust | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | p_values | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | se_at_idx | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | fit | [-1000000, 1000000] | 1 |
| DoubleMLIRM | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLIRM | tune | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | fit | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | fit | [-1000000, 1000000] | 1 |
| DoubleMLPLR | predictions_l | [-1000000, 1000000] | 1 |
| DoubleMLPLR | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLPLR | tune | [-1000000, 1000000] | 1 |
| DoubleMLPQ | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLQTE | tune | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bandwidth_mse | [-1000000, 1000000] | 1 |
| DoubleMLRDD | cluster_hac_se | [0, 0] | 1 |
| DoubleMLRDD | tune | [-1000000, 1000000] | 1 |
| DoubleMLSSM | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLSSM | tune | [-1000000, 1000000] | 1 |
| JointSensitivityInput | new | [-1000000, 1000000] | 1 |
| JointSensitivityInput | new | [-1000000, 1000000] | 1 |
| JointSensitivityInput | new | [-1000000, 1000000] | 1 |
| LearnerDispatch | constant | [-1000000, 1000000] | 1 |
| cluster_sandwich_variance | acc_c | [0, 0] | 1 |
| compute_sensitivity_bias | sigma2 | [-1000000, 1000000] | 1 |
| cs_bin_panel_subset | t_value_pre | [-1000000, 1000000] | 1 |
| did_bootstrap_t_stat | n_rep_boot | [-1000000, 1000000] | 1 |
| did_multi_inner_cell_at_idx | est | [-1000000, 1000000] | 1 |
| did_multi_inner_cell_at_idx | idx | [-1000000, 1000000] | 1 |
| expand_v089_did_binary_data | row | [0, 0] | 3 |
| expand_v089_ref_cluster | max_cid | [-1, -1] | 1 |
| expand_v091_old_accumulator | acc | [0, 0] | 1 |
| expand_v094_pq_data_scaled | need | [-2000000, 2000000] | 1 |
| expand_v100_didcs_cluster_ids | n | [-1000000, 1000000] | 1 |
| expand_v100_didmulti_data | y_val | [0, 0] | 3 |
| expand_v100_didmulti_live_idx | m | [-1000000, 1000000] | 1 |
| generic_bootstrap_t_stat | ss_psi | [0, 0] | 1 |
| irm_style_sensitivity_cluster | n | [0, 64] | 1 |
| make_confounded_plr_data | half_n | [-499999, 500000] | 1 |
| make_confounded_plr_data | half_z | [-1073741823, 1073741823] | 1 |
| make_did_cs_CS2021 | n_per_cohort | [-250000, 250000] | 1 |
| make_irm_confounded_data | half_n | [-499999, 500000] | 1 |
| make_irm_confounded_data | half_z | [-1073741823, 1073741823] | 1 |
| make_irm_heterogeneous_data | acc | [-700000, 700000] | 18 |
| make_pliv_multiway_cluster | seed | [-1000000, 1000000] | 1 |
| policy_tree_ints_from_doubles | n | [0, 64] | 1 |
| sort_indices_by_feature | feature | [-1000000, 1000000] | 1 |
| v1500_conforming_data | n_periods | [4, 4] | 1 |
| DoubleMLAPO | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLAPO | fit_cluster | [0, 0] | 1 |
| DoubleMLAPO | fit_cluster | [0, 0] | 1 |
| DoubleMLAPOS | tune | [-1000000, 1000000] | 1 |
| DoubleMLBLP | cluster_hac_se | [-1000000, 1000000] | 1 |
| DoubleMLBLP | confint_joint | [0, 0] | 2 |
| DoubleMLBLP | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | predictions_g | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | tune | [-1000000, 1000000] | 1 |
| DoubleMLDID | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLDID | predictions_g0 | [-1000000, 1000000] | 1 |
| DoubleMLDID | predictions_g1 | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | fit | [0, 0] | 1 |
| DoubleMLDIDCS | cell_flat_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | coef_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | m_inv_1x1_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | fitted | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | se | [-1000000, 1000000] | 1 |
| DoubleMLDIDData | n_features | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | coef_at_idx | [-1, 0] | 3 |
| DoubleMLDIDMulti | coef_at_idx | [-1, 0] | 3 |
| DoubleMLDIDMulti | confint | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | se_at_idx | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | tune | [-1000000, 1000000] | 1 |
| DoubleMLIRM | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLIRM | fit_cluster | [0, 0] | 1 |
| DoubleMLIRM | fit_cluster | [0, 0] | 1 |
| DoubleMLIRM | predictions_g0 | [-1000000, 1000000] | 1 |
| DoubleMLIRM | predictions_g1 | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | new | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | predictions_a | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | predictions_t | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | tune | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | predictions_g0 | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | predictions_g1 | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | predictions_l | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | predictions_r | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | tune | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | predictions_l | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | tune | [-1000000, 1000000] | 1 |
| DoubleMLPLR | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLPLR | fit_cluster | [0, 0] | 1 |
| DoubleMLPLR | fit_cluster | [0, 0] | 1 |
| DoubleMLPQ | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLPQ | fit_cluster | [0, 0] | 1 |
| DoubleMLPQ | new | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | fit | [0, 0] | 1 |
| DoubleMLPolicyTree | leaf_se | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | predict | [-1000000, 1000000] | 1 |
| DoubleMLQTE | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLQTE | joint_covariance | [1, 1] | 1 |
| DoubleMLQTE | sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLRDD | cluster_hac_se | [-1000000, 1000000] | 1 |
| DoubleMLRDD | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLRDD | kernel_weights | [-1000000, 1000000] | 1 |
| DoubleMLRDD | n_local_params | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_collapsed | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_collapsed | [-1000000, 1000000] | 1 |
| DoubleMLSSM | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLSSM | predictions_pi | [-1000000, 1000000] | 1 |
| DoubleMLSSMData | n_features | [-1000000, 1000000] | 1 |
| GBClassifier | fit_weighted | [0, 0] | 1 |
| GBClassifier | new | [-1000000, 1000000] | 1 |
| GBLearner | new | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp_cv | [-1000000, 1000000] | 1 |
| RFLearner | new | [-1000000, 1000000] | 1 |
| assert_bootstrap_finite | n_finite | [0, 1000001] | 6 |
| build_bootstrap_dgp | cohort_count | [4, 4] | 1 |
| build_bootstrap_dgp | n_per_cohort | [60, 60] | 1 |
| build_iv_clustered_dgp | n_periods | [-1000000, 1000000] | 1 |
| cs_bin_crossfit_nuisance | n_folds | [0, 64] | 1 |
| cs_bin_panel_subset | t_value_eval | [-1000000, 1000000] | 1 |
| double_cross_fit_predict | n_inner | [-1000000, 1000000] | 1 |
| enet_coordinate_descent | max_iter | [-1000000, 1000000] | 1 |
| expand_v088_derived_leverage | hc0 | [-1000000, 1000000] | 1 |
| expand_v088_derived_leverage | hc2 | [-1000000, 1000000] | 1 |
| expand_v090_hc_identities | se_hc0 | [-1000000, 1000000] | 1 |
| expand_v090_hc_identities | se_hc1 | [-1000000, 1000000] | 1 |
| expand_v090_hc_identities | se_hc2 | [-1000000, 1000000] | 1 |
| expand_v090_hc_identities | se_hc3 | [-1000000, 1000000] | 1 |
| expand_v093_lpq_data_scaled | need | [-2000000, 2000000] | 1 |
| expand_v094_pq_data_scaled | width | [-1000000, 1000000] | 1 |
| expand_v100_didcs_data | n_periods | [4, 4] | 1 |
| expand_v100_didmulti_data | cohort | [0, 0] | 2 |
| expand_v100_didmulti_data | theta0 | [1, 1] | 1 |
| hash_hyperparams | propensity_clip | [-1000000, 1000000] | 1 |
| make_irm_discrete_treatments | acc | [-700000, 700000] | 18 |
| make_irm_discrete_treatments | d_i | [0, 3] | 10 |
| make_irm_heterogeneous_data | seed | [-1000000, 1000000] | 1 |
| make_pliv_multiway_cluster | dim_x | [-1000000, 1000000] | 1 |
| make_pliv_multiway_cluster | idx_a | [0, 0] | 3 |
| make_pliv_multiway_cluster | idx_b | [1, 1] | 3 |
| make_pliv_multiway_cluster | n_obs | [-1000000, 1000000] | 1 |
| make_pliv_multiway_cluster | theta | [-1000000, 1000000] | 1 |
| make_plr_CCDDHNR2018 | n_normals_x | [-2147483648, 2147483647] | 1 |
| make_plr_turrell2018 | n_normals_x | [-20000000, 20000000] | 1 |
| policy_tree_honest_leaf_se | n_est | [0, 64] | 1 |
| DoubleMLAPO | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLAPO | new | [-1000000, 1000000] | 1 |
| DoubleMLAPO | new | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLBLP | blp_hat_diagonal | [0, 0] | 2 |
| DoubleMLBLP | cluster_hac_se | [0, 0] | 2 |
| DoubleMLBLP | confint_joint | [-1000000, 1000000] | 1 |
| DoubleMLBLP | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLDID | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLDID | fit | [0, 0] | 1 |
| DoubleMLDID | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | confint | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinaryData | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | coef_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | fit | [-1, 0] | 6 |
| DoubleMLDIDCS | group_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | confint | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | g_value | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | fit | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | coef_at_idx | [-1000000, 1000000] | 1 |
| DoubleMLData | n_cluster_vars | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | fit_cluster | [0, 0] | 1 |
| DoubleMLIIVM | fit_cluster | [0, 0] | 1 |
| DoubleMLIIVM | predictions_g0 | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | predictions_g1 | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | predictions_r0 | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | predictions_r1 | [-1000000, 1000000] | 1 |
| DoubleMLIIVMData | n_features | [-1000000, 1000000] | 1 |
| DoubleMLIRM | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLIRM | new | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | new | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | fit_cluster | [0, 0] | 1 |
| DoubleMLPLIV | fit_cluster | [0, 0] | 1 |
| DoubleMLPLIVData | n_features | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLPLR | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLPQ | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPQ | fit_cluster | [0, 0] | 1 |
| DoubleMLPQ | sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLQTE | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLQTE | fit_cluster | [0, 0] | 2 |
| DoubleMLQTE | joint_covariance | [0, 0] | 3 |
| DoubleMLQTE | new | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bandwidth_mse | [-1000000, 1000000] | 1 |
| DoubleMLRDD | cluster_hac_se | [0, 0] | 1 |
| DoubleMLRDD | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLRDD | pilot_bandwidth | [-1000000, 1000000] | 1 |
| DoubleMLSSM | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLSSM | new | [-1000000, 1000000] | 1 |
| GBClassifier | new | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp_hc0 | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp_hc0 | [0, 0] | 4 |
| LinearRegression | sandwich_se | [0, 0] | 2 |
| LinearRegression | sandwich_se | [0, 0] | 4 |
| LogisticRegression | fit | [-1000000, 1000000] | 1 |
| RFClassifier | new | [-1000000, 1000000] | 1 |
| assert_bootstrap_t_stat_basic | sum | [0, 0] | 1 |
| cluster_sandwich_variance | max_cid | [-1, -1] | 1 |
| crossfit_nuisance | propensity_clip | [-1000000, 1000000] | 1 |
| draw_bootstrap_weights | n_rep_boot | [-1000000, 1000000] | 1 |
| expand_v087_cs_binary_data | n_rows | [-6000000, 6000000] | 1 |
| expand_v091_old_accumulator | m_val | [-1000000, 1000000] | 1 |
| expand_v091_old_accumulator | n_obs | [-1000000, 1000000] | 1 |
| expand_v093_lpq_data_scaled | width | [-1000000, 1000000] | 1 |
| expand_v100_didmulti_data | n_units | [200, 200] | 1 |
| generic_bootstrap_psi_matrix | seed | [-1000000, 1000000] | 1 |
| generic_bootstrap_single_psi | seed | [-1000000, 1000000] | 1 |
| make_did_cs_CS2021 | unit_in_cohort | [0, 249999] | 2 |
| make_irm_discrete_treatments | seed | [-1000000, 1000000] | 1 |
| make_irm_heterogeneous_data | dim_x | [-1000000, 1000000] | 1 |
| make_irm_heterogeneous_data | idx_a | [0, 0] | 3 |
| make_irm_heterogeneous_data | idx_b | [1, 1] | 3 |
| make_irm_heterogeneous_data | n_obs | [-1000000, 1000000] | 1 |
| make_pliv_multiway_cluster | half_n | [-499999, 500000] | 1 |
| make_pliv_multiway_cluster | half_z | [-1073741823, 1073741823] | 1 |
| make_pliv_multiway_cluster | max_ca | [25, 25] | 1 |
| make_pliv_multiway_cluster | max_cb | [25, 25] | 1 |
| preprocess_did_binary | t_value_pre | [-1000000, 1000000] | 1 |
| single_psi_sensitivity | sigma2_sum | [0, 0] | 1 |
| v1500_no_base_period | cohort_count | [3, 3] | 1 |
| v1500_no_base_period | n_per_cohort | [60, 60] | 1 |
| DoubleMLAPO | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLAPO | sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | causal_contrast | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | new | [-1000000, 1000000] | 1 |
| DoubleMLBLP | blp_hat_diagonal | [-1000000, 1000000] | 1 |
| DoubleMLBLP | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | new | [-1000000, 1000000] | 1 |
| DoubleMLDID | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDID | sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | n_features | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | psi_a_long | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | psi_b_long | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | coef | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSectionData | new | [0, 64] | 1 |
| DoubleMLDIDMulti | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | coef_at_idx | [-1000000, 1000000] | 1 |
| DoubleMLData | is_cluster_data | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | new | [-1000000, 1000000] | 1 |
| DoubleMLIRM | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLIRM | sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLPLR | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPLR | sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | is_honest | [-1000000, 1000000] | 1 |
| DoubleMLQTE | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLQTE | fit_cluster | [0, 0] | 2 |
| DoubleMLQTE | joint_covariance | [-1000000, 1000000] | 1 |
| DoubleMLQTE | sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bandwidth_sigma4 | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_collapsed | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_collapsed | [-1000000, 1000000] | 1 |
| DoubleMLRDD | tau_bc_se_rb | [-1000000, 1000000] | 1 |
| DoubleMLSSM | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLSSM | predictions_g_d0 | [-1000000, 1000000] | 1 |
| DoubleMLSSM | predictions_g_d1 | [-1000000, 1000000] | 1 |
| DoubleMLSSM | sample_splitting | [-1000000, 1000000] | 1 |
| FitCache | from_fit | [-1000000, 1000000] | 1 |
| FitCache | is_valid | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp_cv | [1, 1] | 1 |
| GainStatsSource | from_blp_cv | [-1000000, 1000000] | 1 |
| build_iv_clustered_dgp | iv_strength | [-1000000, 1000000] | 1 |
| cluster_sandwich_variance | n_params | [-1000000, 1000000] | 1 |
| double_cross_fit_predict | rng_state | [-1000000, 1000004] | 7 |
| enet_coordinate_descent | max_change | [0, 0] | 5 |
| expand_v087_cs_binary_data | n_units | [-2000000, 2000000] | 1 |
| expand_v100_didmulti_cluster_ids | n | [-1000000, 1000000] | 1 |
| generic_bootstrap_psi_matrix | n_obs | [-1000000, 1000000] | 1 |
| generic_bootstrap_single_psi | n_obs | [0, 64] | 1 |
| irm_style_sensitivity_cluster | cf_d | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_cluster | cf_y | [-1000000, 1000000] | 1 |
| make_irm_discrete_treatments | dim_x | [-1000000, 1000000] | 1 |
| make_irm_discrete_treatments | idx_a | [0, 0] | 3 |
| make_irm_discrete_treatments | idx_b | [1, 1] | 3 |
| make_irm_discrete_treatments | n_obs | [-1000000, 1000000] | 1 |
| make_irm_discrete_treatments | theta | [-1000000, 1000000] | 1 |
| make_irm_heterogeneous_data | half_n | [-499999, 500000] | 1 |
| make_irm_heterogeneous_data | half_z | [-1073741823, 1073741823] | 1 |
| preprocess_did_binary | t_value_eval | [-1000000, 1000000] | 1 |
| v1500_conforming_data | cohort_count | [4, 4] | 1 |
| v1500_conforming_data | n_per_cohort | [50, 50] | 1 |
| DoubleMLAPOS | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | treatment_levels | [-1000000, 1000000] | 1 |
| DoubleMLBLP | cluster_hac_se | [-1, -1] | 1 |
| DoubleMLBLP | confint_joint | [0, 0] | 2 |
| DoubleMLCVAR | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | inner_psi_a | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | inner_psi_b | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | period_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sensitivity_nu2 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | confint | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | psi_a | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | psi_b | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | tune | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | leaf_psi_a | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | leaf_psi_a | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | min_leaf_n | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | new | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | new | [-1000000, 1000000] | 1 |
| DoubleMLQTE | joint_covariance | [0, 0] | 3 |
| DoubleMLQTE | psi_row | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bandwidth_mse | [-1000000, 1000000] | 1 |
| DoubleMLRDD | cluster_hac_se | [-1, -1] | 1 |
| DoubleMLRDD | optimal_bandwidth | [-1000000, 1000000] | 1 |
| FitCache | from_fit | [-1000000, 1000000] | 1 |
| FitCache | from_fit | [-1000000, 1000000] | 1 |
| FitCache | is_valid | [-1000000, 1000000] | 1 |
| FitCache | is_valid | [-1000000, 1000000] | 1 |
| GBClassifier | new | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp_cv | [0, 0] | 1 |
| GainStatsSource | from_blp_hc0 | [0, 0] | 2 |
| GainStatsSource | from_blp_hc0 | [1, 1] | 1 |
| GainStatsSource | from_blp_hc0 | [1, 1] | 1 |
| GainStatsSource | from_blp_hc0 | [-1000000, 1000000] | 1 |
| JointSensitivityInput | new | [-1000000, 1000000] | 1 |
| RFClassifier | new | [-1000000, 1000000] | 1 |
| expand_v089_did_binary_data | n_units | [-1000000, 1000000] | 1 |
| expand_v090_hc_identities | se_pooled | [-1000000, 1000000] | 1 |
| expand_v100_didcs_data | cohort_count | [4, 4] | 1 |
| expand_v100_didcs_data | n_per_cohort | [50, 50] | 1 |
| expand_v100_didmulti_data | n_periods | [4, 4] | 1 |
| generic_bootstrap_ols_per_coef | m_xi | [0, 0] | 3 |
| generic_bootstrap_ols_per_coef | seed | [-1000000, 1000000] | 1 |
| generic_bootstrap_single_psi | ss_psi | [0, 0] | 1 |
| generic_bootstrap_t_stat | n_rep_boot | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_cluster | theta | [-1000000, 1000000] | 1 |
| make_irm_discrete_treatments | half_n | [-499999, 500000] | 1 |
| make_irm_discrete_treatments | half_z | [-1073741823, 1073741823] | 1 |
| policy_tree_honest_leaf_se | n_leaves | [0, 64] | 1 |
| var_est_cluster | n_folds_per_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | n_obs_subset | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | n_c_subset | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | n_g_subset | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | tune | [-1000000, 1000000] | 1 |
| DoubleMLPQ | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLPQ | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | est_indices | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | policy_value | [0, 0] | 1 |
| DoubleMLPolicyTree | set_min_leaf_n | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | split_value | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bandwidth_sigma4 | [-1000000, 1000000] | 1 |
| DoubleMLRDD | optimal_bandwidth | [2, 2] | 1 |
| DoubleMLRDD | optimal_bandwidth | [0.5, 0.5] | 1 |
| GainStatsSource | from_blp_hc0 | [0, 0] | 2 |
| assert_bootstrap_finite | expected_len | [-1000000, 1000000] | 1 |
| expand_v087_cs_binary_data | n_periods | [3, 3] | 1 |
| irm_style_sensitivity_cluster | mb_sum | [0, 0] | 1 |
| make_confounded_plr_data | n_normals_x | [-2147483648, 2147483647] | 1 |
| make_irm_confounded_data | n_normals_x | [-2147483648, 2147483647] | 1 |
| DoubleMLAPO | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLAPO | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | n_treatment_levels | [-1000000, 1000000] | 1 |
| DoubleMLBLP | sensitivity_analysis | [0, 0] | 3 |
| DoubleMLDID | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLDID | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | cell_flat_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | cell_psi_a_row_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | cell_psi_b_row_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | m_inv_1x1_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sensitivity_folds | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | n_obs_panel | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | t_value_pre | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | confint | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | aggregate_time | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | n_combinations | [-1000000, 1000000] | 1 |
| DoubleMLData | is_instrument_data | [-1000000, 1000000] | 1 |
| DoubleMLIIVMData | n_cluster_vars | [-1000000, 1000000] | 1 |
| DoubleMLIRM | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLIRM | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLPLIVData | n_cluster_vars | [-1000000, 1000000] | 1 |
| DoubleMLPLR | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLPLR | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLPQ | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPQ | set_sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | policy_value | [-1000000, 1000000] | 1 |
| DoubleMLRDD | optimal_bandwidth | [50, 50] | 1 |
| DoubleMLSSM | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLSSM | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp_cv | [-1000000, 1000000] | 1 |
| cluster_causal_param_and_se | n_folds_u | [-1000000, 1000000] | 1 |
| generic_bootstrap_psi_matrix | n_thetas | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_cluster | max_cid | [-1, -1] | 1 |
| irm_style_sensitivity_from_elements | n | [0, 64] | 1 |
| make_irm_heterogeneous_data | theta_sum | [0, 0] | 1 |
| sensitivity_from_variance_baselines | n | [-1000000, 1000000] | 1 |
| DoubleMLAPO | fit_cluster | [-1000000, 1000000] | 1 |
| DoubleMLAPO | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLAPO | set_sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLBLP | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLDID | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDID | set_sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | predictions_g0 | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | predictions_g1 | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinaryData | n_features | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | cell_flat_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | m_inv_1x1_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sensitivity_sigma2 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | t_value_eval | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | aggregate_event | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | aggregate_group | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLIIVMData | is_cluster_data | [-1000000, 1000000] | 1 |
| DoubleMLIRM | fit_cluster | [-1000000, 1000000] | 1 |
| DoubleMLIRM | propensity_score_raw | [-1000000, 1000000] | 1 |
| DoubleMLIRM | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLIRM | set_sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLPLIVData | is_cluster_data | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLPLR | fit_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLR | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPLR | set_sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLPQ | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPQ | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | policy_value_se | [0, 0] | 1 |
| DoubleMLPolicyTree | split_feature | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | split_indices | [-1000000, 1000000] | 1 |
| DoubleMLQTE | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLQTE | set_sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bandwidth_sigma4 | [-1000000, 1000000] | 1 |
| DoubleMLRDD | bandwidth_variance_term | [-1000000, 1000000] | 1 |
| DoubleMLRDD | optimal_bias_bandwidth | [-1000000, 1000000] | 1 |
| DoubleMLRDD | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLSSM | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLSSM | set_sample_splitting | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp_hc0 | [-1000000, 1000000] | 1 |
| assert_bootstrap_t_stat_basic | n_finite | [0, 1000001] | 6 |
| double_cross_fit_predict_dispatch | seed | [-1000000, 1000000] | 1 |
| expand_gt_keyword | anticipation_periods | [-1000000, 1000000] | 1 |
| expand_v090_hc_identities | se_singleton | [-1000000, 1000000] | 1 |
| expand_v100_didmulti_data | cohort_count | [4, 4] | 1 |
| expand_v100_didmulti_data | n_per_cohort | [50, 50] | 1 |
| irm_style_sensitivity_cluster | ss_psi_a | [0, 0] | 1 |
| irm_style_sensitivity_cluster | ss_resid | [0, 0] | 1 |
| make_pliv_multiway_cluster | n_normals_x | [-2147483648, 2147483647] | 1 |
| v120_check_unpenalised_intercept | plain | [0, 0] | 1 |
| DoubleMLAPO | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLAPO | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | set_sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLBLP | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLBLP | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | set_sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLDID | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDID | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | predictions_g_d0_t0 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | predictions_g_d0_t1 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | predictions_g_d1_t0 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | predictions_g_d1_t1 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sensitivity_psi_nu2 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | confint | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | has_cache | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | learner_g | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | learner_m | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSectionData | n_obs | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | fit_cluster | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | set_sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLIRM | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLIRM | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | set_sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | fit_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | set_sample_splitting | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPLR | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPLR | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPLR | sensitivity_analysis | [0, 0] | 1 |
| DoubleMLPolicyTree | enable_honesty | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | leaf_influence | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | leaf_influence | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | set_min_leaf_n | [-1000000, 1000000] | 1 |
| DoubleMLQTE | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLQTE | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLRDD | optimal_bandwidth | [1.0000000000000002e+300, 1.0000000000000002e+300] | 1 |
| DoubleMLRDD | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLRDD | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLSSM | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLSSM | sensitivity_analysis | [-1000000, 1000000] | 1 |
| expand_v087_cs_binary_data | n_per_cohort | [-1000000, 1000000] | 1 |
| generic_bootstrap_psi_matrix | n_rep_boot | [-1000000, 1000000] | 1 |
| generic_bootstrap_single_psi | n_rep_boot | [-1000000, 1000000] | 1 |
| make_irm_heterogeneous_data | n_normals_x | [-2147483648, 2147483647] | 1 |
| make_pliv_multiway_cluster | n_clusters_a | [50, 50] | 1 |
| make_pliv_multiway_cluster | n_clusters_b | [50, 50] | 1 |
| sensitivity_from_variance_baselines | nu2 | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | sandwich_se_at_idx | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | policy_value_se | [-1000000, 1000000] | 1 |
| DoubleMLQTE | bias_corrected_coef_at | [-1000000, 1000000] | 1 |
| DoubleMLQTE | cluster_joint_covariance | [1, 1] | 1 |
| DoubleMLQTE | cluster_sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLQTE | m_inv_1x1_at | [-1000000, 1000000] | 1 |
| DoubleMLRDD | optimal_bias_bandwidth | [-1000000, 1000000] | 1 |
| assert_bootstrap_t_stat_basic | n_rep_boot | [-1000000, 1000000] | 1 |
| cross_fit_predict_conditional_dispatch | n | [0, 64] | 1 |
| cs_bin_crossfit_nuisance | propensity_clip | [-1000000, 1000000] | 1 |
| cs_bin_panel_subset | anticipation_periods | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_cluster_multi | cf_d | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_cluster_multi | cf_y | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_from_elements | cf_d | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_from_elements | cf_y | [-1000000, 1000000] | 1 |
| make_irm_discrete_treatments | n_normals_x | [-2147483648, 2147483647] | 1 |
| resolve_ps_processor | trimming_threshold~ | [-1000000, 1000000] | 1 |
| sensitivity_from_variance_baselines | cf_d | [-1000000, 1000000] | 1 |
| sensitivity_from_variance_baselines | cf_y | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | bias_corrected_coef_at | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | cluster_sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sensitivity_riesz_rep | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | bootstrap | [0, 0] | 1 |
| DoubleMLDIDCrossSection | clear_cache | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | sandwich_se_at_idx | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | sensitivity_analysis | [-1, 0] | 6 |
| DoubleMLDIDMulti | sensitivity_analysis | [-1, 0] | 6 |
| DoubleMLPolicyTree | leaf_se_reliable | [-1000000, 1000000] | 1 |
| DoubleMLQTE | cluster_joint_covariance | [0, 0] | 3 |
| DoubleMLRDD | bandwidth_variance_term | [-1000000, 1000000] | 1 |
| DoubleMLRDD | optimal_bias_bandwidth | [2, 2] | 1 |
| DoubleMLRDD | optimal_bias_bandwidth | [0.5, 0.5] | 1 |
| GainStatsSource | from_blp_cv | [0, 0] | 1 |
| GainStatsSource | from_blp_cv_repeated | [-1000000, 1000000] | 1 |
| PSProcessorConfig | new | [-1000000, 1000000] | 1 |
| double_cross_fit_predict_dispatch | n_inner | [-1000000, 1000000] | 1 |
| generic_bootstrap_ols_per_coef | n_rep_boot | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_from_elements | theta | [-1000000, 1000000] | 1 |
| sensitivity_from_variance_baselines | theta | [-1000000, 1000000] | 1 |
| DoubleMLAPO | sensitivity_nu2_elements | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | m_inv_1x1_at | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | psi_a_row_at | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | psi_b_row_at | [-1000000, 1000000] | 1 |
| DoubleMLDID | sensitivity_nu2_elements | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | bias_corrected_coef_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | cell_psi_a_row_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | cell_psi_b_row_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | cluster_sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sensitivity_psi_sigma2 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLIRM | sensitivity_nu2_elements | [-1000000, 1000000] | 1 |
| DoubleMLPLR | sensitivity_analysis | [0, 0] | 1 |
| DoubleMLPolicyTree | enable_split_seed | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | enable_split_seed | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | unreliable_leaves | [-1000000, 1000000] | 1 |
| DoubleMLQTE | cluster_joint_covariance | [-1000000, 1000000] | 1 |
| DoubleMLQTE | sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLRDD | optimal_bias_bandwidth | [50, 50] | 1 |
| GainStatsSource | from_blp_hc0 | [0, 0] | 1 |
| LinearRegression | sandwich_se_weighted | [0, 0] | 2 |
| LinearRegression | sandwich_se_weighted | [0, 0] | 4 |
| PSProcessorConfig | new | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_from_elements | mb_sum | [0, 0] | 1 |
| irm_style_sensitivity_from_elements | ss_nu2 | [0, 0] | 1 |
| preprocess_did_binary | anticipation_periods | [-1000000, 1000000] | 1 |
| sensitivity_from_variance_baselines | mb_sum | [0, 0] | 1 |
| sensitivity_from_variance_baselines | sigma2 | [-1000000, 1000000] | 1 |
| DoubleMLDID | sensitivity_nu2_elements | [0, 0] | 1 |
| DoubleMLDIDBinary | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | cell_psi_a_row_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | cell_psi_b_row_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | predictions_m | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | tune | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLQTE | cluster_joint_covariance | [0, 0] | 3 |
| DoubleMLRDD | bandwidth_variance_term | [-1000000, 1000000] | 1 |
| DoubleMLRDD | require_hac_preconditions | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp_cv_repeated | [1, 1] | 1 |
| GainStatsSource | from_blp_cv_repeated | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | enable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSectionData | n_features | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | smallest_leaf_count | [-1000000, 1000000] | 1 |
| DoubleMLRDD | optimal_bias_bandwidth | [1.0000000000000002e+300, 1.0000000000000002e+300] | 1 |
| DoubleMLRDD | optimal_bias_bandwidth | [-1000000, 1000000] | 1 |
| LinearRegression | covariance_diagonal | [-1000000, 1000000] | 1 |
| LogisticRegression | predict_class | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_cluster_multi | n_thetas | [0, 64] | 1 |
| irm_style_sensitivity_from_elements | ss_resid | [0, 0] | 1 |
| DoubleMLBLP | sensitivity_analysis_cluster | [0, 0] | 3 |
| DoubleMLDIDBinary | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | predictions_g_d0_t0 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | predictions_g_d0_t1 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | predictions_g_d1_t0 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | predictions_g_d1_t1 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | disable_memoize | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | new | [-1000000, 1000000] | 1 |
| DoubleMLPQ | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLQTE | cluster_joint_covariance | [-1, -1] | 1 |
| DoubleMLRDD | bandwidth_variance_term | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_cluster_from_elements | n | [0, 64] | 1 |
| DoubleMLAPO | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLBLP | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDID | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDID | sensitivity_nu2_elements | [0, 0] | 1 |
| DoubleMLDIDCSBinary | new | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | bootstrap | [-1000000, 1000000] | 1 |
| DoubleMLIRM | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLR | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPQ | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPQ | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPQ | sensitivity_analysis_cluster | [0, 0] | 1 |
| DoubleMLPolicyTree | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLQTE | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLRDD | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLSSM | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp_cv_repeated | [-1000000, 1000000] | 1 |
| DoubleMLAPO | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLAPO | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLBLP | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLBLP | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDID | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDID | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | bias_corrected_coef_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | cluster_sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLIRM | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLIRM | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLLPQ | sensitivity_analysis_cluster | [0, 0] | 1 |
| DoubleMLPLIV | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLR | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLR | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLR | sensitivity_analysis_cluster | [0, 0] | 1 |
| DoubleMLQTE | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLQTE | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLQTE | sensitivity_analysis_cluster | [0, 0] | 1 |
| DoubleMLRDD | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLRDD | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLSSM | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLSSM | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| cluster_causal_param_and_se | n_folds_per_cluster | [-1000000, 1000000] | 1 |
| resolve_ps_processor_config | trimming_threshold~ | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLCVAR | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | bias_corrected_coef_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | cluster_sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | bias_corrected_coef_at_idx | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | cluster_sandwich_se_at_idx | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLIIVM | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLLPLR | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLIV | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPLPR | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLPolicyTree | smallest_leaf_count | [-1, -1] | 1 |
| GainStatsSource | from_blp_cv_repeated | [0, 0] | 2 |
| GainStatsSource | from_blp_cv_repeated | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_cluster_from_elements | cf_d | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_cluster_from_elements | cf_y | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDCS | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | bias_corrected_coef | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | cluster_sandwich_se | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | predictions_g_d0_t0 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | predictions_g_d0_t1 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | predictions_g_d1_t0 | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | predictions_g_d1_t1 | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | bias_corrected_coef_at_idx | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | cluster_sandwich_se_at_idx | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | sensitivity_analysis_cluster | [-1, 0] | 6 |
| DoubleMLDIDMulti | sensitivity_analysis_cluster | [-1, 0] | 6 |
| DoubleMLPLR | sensitivity_analysis_cluster | [-1, -1] | 1 |
| irm_style_sensitivity_cluster_from_elements | ss_rr | [0, 0] | 1 |
| irm_style_sensitivity_cluster_from_elements | theta | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLPLR | sensitivity_analysis_cluster | [0, 0] | 1 |
| DoubleMLQTE | bias_corrected_coef_at | [-1000000, 1000000] | 1 |
| DoubleMLQTE | cluster_sandwich_se_at | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp_cv_repeated | [0, 0] | 2 |
| irm_style_sensitivity_cluster_from_elements | mb_sum | [0, 0] | 1 |
| irm_style_sensitivity_cluster_from_elements | ss_nu2 | [0, 0] | 1 |
| DoubleMLDIDCrossSection | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | sensitivity_analysis | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| irm_style_sensitivity_cluster_from_elements | max_cid | [-1, -1] | 1 |
| DoubleMLAPOS | bias_corrected_coef_at | [-1000000, 1000000] | 1 |
| DoubleMLAPOS | cluster_sandwich_se_at | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDMulti | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| GainStatsSource | from_blp_cv_repeated | [0, 0] | 1 |
| irm_style_sensitivity_cluster_from_elements | ss_resid | [0, 0] | 1 |
| DoubleMLDIDBinary | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDBinary | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | cs_bin_sensitivity_residuals | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | cs_bin_sensitivity_nu2_elements | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | cs_bin_sensitivity_nu2_elements | [0, 0] | 1 |
| DoubleMLDIDCSBinary | cs_bin_sensitivity_nu2_elements | [0, 0] | 1 |
| DoubleMLDIDCrossSection | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDCrossSection | sensitivity_analysis_cluster | [-1000000, 1000000] | 1 |
| DoubleMLDIDCSBinary | cs_bin_sensitivity_nu2_elements | [0, 0] | 1 |
| DoubleMLDIDCSBinary | cs_bin_sensitivity_nu2_elements | [0, 0] | 1 |
| DoubleMLDIDCSBinary | cs_bin_sensitivity_nu2_elements | [0, 0] | 1 |
| DoubleMLDIDCSBinary | cs_bin_sensitivity_nu2_elements | [0, 0] | 1 |

## 7. Program slicing

### backward slice on `theta_hat@aggregate_coef_se`

```mermaid
flowchart TD
  classDef sliceNode fill:#e3f2fd,stroke:#1565c0
  s0["stmt L53: let theta_hat = coefs_sorted[n / 2]"]:::sliceNode
  s1["stmt L51: let coefs_sorted = coefs.copy()"]:::sliceNode
  s2["stmt L48: let n = coefs.length()"]:::sliceNode
  s3["src L33: require(coefs.length() == ses.length())"]:::sliceNode
  s1 -->|data| s0
  s2 -->|data| s0
  s3 -->|data| s1
  s3 -->|data| s2
```

| Line | Kind | Statement | Site |
| --- | --- | --- | --- |
| 53 | def | `let theta_hat = coefs_sorted[n / 2]` | aggregator.mbt |
| 51 | def | `let coefs_sorted = coefs.copy()` | aggregator.mbt |
| 48 | def | `let n = coefs.length()` | aggregator.mbt |
| 33 | source | `require(coefs.length() == ses.length())` | aggregator.mbt |

## 8. Contracts and verification conditions (L3)

Deductive verification is WP-style: each contract becomes verification conditions (postconditions at every `return`, plus safety obligations for every index, allocation size, division and assertion). A condition is `proved` only when the preconditions entail it by interval reasoning; otherwise it is `failed` or `unknown`. This is not a substitute for an SMT-backed WP: `unknown` is an honest third state.

| Metric | Value |
| --- | --- |
| Functions with a contract | 0 |
| Functions checked | 0 |
| VCs proved | 0 |
| VCs failed | 0 |
| VCs unknown | 0 |

_No verification condition generated._

Specification gaps (escalated, no `//@ requires`/`//@ ensures`): `DoubleMLAPO::new (apo.mbt:101)`, `DoubleMLAPO::coef (apo.mbt:196)`, `DoubleMLAPO::se (apo.mbt:207)`, `DoubleMLAPO::confint (apo.mbt:218)`, `DoubleMLAPO::predictions_g (apo.mbt:229)`, `DoubleMLAPO::predictions_m (apo.mbt:240)`, `indicator_level (apo.mbt:251)`, `cross_fit_apo (apo.mbt:275)`, `DoubleMLAPO::fit (apo.mbt:337)`, `DoubleMLAPO::fit_cluster (apo.mbt:549)`, `DoubleMLAPO::sandwich_se (apo.mbt:766)`, `DoubleMLAPO::cluster_sandwich_se (apo.mbt:799)`, `DoubleMLAPO::bias_corrected_coef (apo.mbt:858)`, `DoubleMLAPO::bootstrap (apo.mbt:895)`, `DoubleMLAPO::tune (apo.mbt:968)`, `DoubleMLAPOS::tune (apo.mbt:1024)`, `DoubleMLAPO::sensitivity_nu2_elements (apo.mbt:1094)`, `DoubleMLAPO::sensitivity_analysis (apo.mbt:1127)`, `DoubleMLAPO::sensitivity_analysis_cluster (apo.mbt:1157)`, `DoubleMLAPOS::new (apo.mbt:1282)`, `DoubleMLAPOS::fit (apo.mbt:1379)`, `DoubleMLAPOS::coefs (apo.mbt:1693)`, `DoubleMLAPOS::ses (apo.mbt:1704)`, `DoubleMLAPOS::psi_b_row_at (apo.mbt:1808)`, `DoubleMLAPOS::psi_a_row_at (apo.mbt:1838)`, `DoubleMLAPOS::m_inv_1x1_at (apo.mbt:1868)`, `DoubleMLAPOS::sandwich_se_at (apo.mbt:1919)`, `DoubleMLAPOS::cluster_sandwich_se_at (apo.mbt:1965)`, `DoubleMLAPOS::bias_corrected_coef_at (apo.mbt:2019)`, `DoubleMLAPOS::bootstrap (apo.mbt:2045)`, `DoubleMLAPOS::confint (apo.mbt:2094)`, `DoubleMLAPOS::boot_t_stats (apo.mbt:2148)`, `DoubleMLAPOS::causal_contrast (apo.mbt:2200)`, `DoubleMLAPOS::sensitivity_analysis (apo.mbt:2266)`, `DoubleMLAPOS::sensitivity_analysis_cluster (apo.mbt:2314)`, `DoubleMLDIDData::new (did.mbt:31)`, `DoubleMLDID::new (did.mbt:252)`, `DoubleMLDID::coef (did.mbt:345)`, `DoubleMLDID::se (did.mbt:356)`, `DoubleMLDID::confint (did.mbt:369)`, `cross_fit_did (did.mbt:433)`, `DoubleMLDID::fit (did.mbt:483)`, `DoubleMLDID::bootstrap (did.mbt:793)`, `DoubleMLDID::sensitivity_nu2_elements (did.mbt:873)`, `DoubleMLDID::sensitivity_analysis (did.mbt:940)`, `DoubleMLDID::sensitivity_analysis_cluster (did.mbt:975)`, `DoubleMLDID::sandwich_se (did.mbt:1027)`, `DoubleMLDID::cluster_sandwich_se (did.mbt:1057)`, `DoubleMLDID::bias_corrected_coef (did.mbt:1114)`, `DoubleMLDID::tune (did.mbt:1196)`, `GBLearner::fit_weighted (gbl.mbt:125)`, `predict (gbl.mbt:249)`, `DoubleMLIRM::new (irm.mbt:109)`, `DoubleMLIRM::coef (irm.mbt:184)`, `DoubleMLIRM::se (irm.mbt:195)`, `DoubleMLIRM::confint (irm.mbt:209)`, `filter_indices (irm.mbt:314)`, `clip_vec (irm.mbt:327)`, `cross_fit_irm (irm.mbt:352)`, `DoubleMLIRM::fit (irm.mbt:462)`, `DoubleMLIRM::fit_cluster (irm.mbt:730)`, `DoubleMLIRM::bootstrap (irm.mbt:935)`, `DoubleMLIRM::tune (irm.mbt:1014)`, `DoubleMLIRM::sensitivity_nu2_elements (irm.mbt:1089)`, `DoubleMLIRM::sensitivity_analysis (irm.mbt:1116)`, `DoubleMLIRM::sensitivity_analysis_cluster (irm.mbt:1154)`, `DoubleMLIRM::sandwich_se (irm.mbt:1197)`, `DoubleMLIRM::cluster_sandwich_se (irm.mbt:1238)`, `DoubleMLIRM::bias_corrected_coef (irm.mbt:1296)`, `silverman_bandwidth (kde.mbt:14)`, `sample_sd (kde.mbt:32)`, `percentile_sorted (kde.mbt:65)`, `gaussian_kde (kde.mbt:88)`, `gaussian_kde_weighted (kde.mbt:125)`, `DoubleMLLPQData::new (lpq.mbt:14)`, `lpq_score (lpq.mbt:37)`, `lpq_score_ipw (lpq.mbt:68)`, `DoubleMLLPQ::new (lpq.mbt:178)`, `DoubleMLLPQ::fit (lpq.mbt:236)`, `DoubleMLLPQ::bootstrap (lpq.mbt:536)`, `DoubleMLLPQ::sensitivity_analysis (lpq.mbt:580)`, `DoubleMLLPQ::sensitivity_analysis_cluster (lpq.mbt:608)`, `DoubleMLLPQ::confint (lpq.mbt:655)`, `DoubleMLLPQ::coef (lpq.mbt:677)`, `DoubleMLLPQ::se (lpq.mbt:688)`, `DoubleMLLPQ::predictions_g0 (lpq.mbt:701)`, `DoubleMLLPQ::predictions_g1 (lpq.mbt:714)`, `DoubleMLLPQ::predictions_m (lpq.mbt:727)`, `DoubleMLLPQ::m_inv_1x1 (lpq.mbt:838)`, `DoubleMLLPQ::sandwich_se (lpq.mbt:872)`, `DoubleMLLPQ::cluster_sandwich_se (lpq.mbt:911)`, `DoubleMLLPQ::bias_corrected_coef (lpq.mbt:956)`, `DoubleMLPLR::new (plr.mbt:98)`, `DoubleMLPLR::coef (plr.mbt:158)`, `DoubleMLPLR::se (plr.mbt:171)`, `DoubleMLPLR::confint (plr.mbt:187)`, `plr_score_elements (plr.mbt:348)`, `DoubleMLPLR::fit (plr.mbt:414)`, `DoubleMLPLR::fit_cluster (plr.mbt:673)`, `DoubleMLPLR::bootstrap (plr.mbt:976)`, `DoubleMLPLR::sensitivity_analysis (plr.mbt:1086)`, `DoubleMLPLR::sensitivity_analysis_cluster (plr.mbt:1129)`, `DoubleMLPLR::sandwich_se (plr.mbt:1179)`, `DoubleMLPLR::cluster_sandwich_se (plr.mbt:1214)`, `DoubleMLPLR::bias_corrected_coef (plr.mbt:1271)`, `DoubleMLRDDData::new (rdd.mbt:15)`, `DoubleMLRDD::new (rdd.mbt:160)`, `weighted_xtx_transpose (rdd.mbt:405)`, `DoubleMLRDD::fit (rdd.mbt:663)`, `DoubleMLRDD::coef (rdd.mbt:1001)`, `DoubleMLRDD::se (rdd.mbt:1012)`, `DoubleMLRDD::confint (rdd.mbt:1023)`, `DoubleMLRDD::leverage (rdd.mbt:1194)`, `rdd_hac_require_df (rdd.mbt:1261)`, `DoubleMLRDD::hac_se (rdd.mbt:1321)`, `DoubleMLRDD::cluster_hac_se (rdd.mbt:1462)`, `DoubleMLRDD::sensitivity_analysis (rdd.mbt:1556)`, `DoubleMLRDD::sensitivity_analysis_cluster (rdd.mbt:1593)`, `DoubleMLRDD::bootstrap (rdd.mbt:1720)`, `DoubleMLRDD::tune (rdd.mbt:1831)`, `DoubleMLRDD::bias (rdd.mbt:2089)`, `DoubleMLRDD::tau_bc (rdd.mbt:2228)`, `DoubleMLRDD::tau_bc_collapsed (rdd.mbt:2290)`, `DoubleMLRDD::tau_bc_se (rdd.mbt:2343)`, `DoubleMLRDD::bandwidth_mse (rdd.mbt:2414)`, `DoubleMLRDD::bandwidth_variance_term (rdd.mbt:2487)`, `rdd_pilot_stage (rdd.mbt:2580)`, `rdd_nn_matched_sigma4 (rdd.mbt:2658)`, `nn_residual (rdd.mbt:2806)`, `rdd_rb_side (rdd.mbt:2982)`, `DoubleMLRDD::tau_bc_se_rb (rdd.mbt:3199)`, `bootstrap_indices (rfl.mbt:150)`, `cart_fit (rfl.mbt:202)`, `cart_leaf_value (rfl.mbt:495)`, `RFLearner::fit_weighted (rfl.mbt:610)`, `predict (rfl.mbt:677)`, `DoubleMLSSMData::new (ssm.mbt:18)`, `DoubleMLSSM::new (ssm.mbt:152)`, `DoubleMLSSM::coef (ssm.mbt:286)`, `DoubleMLSSM::se (ssm.mbt:297)`, `DoubleMLSSM::confint (ssm.mbt:308)`, `DoubleMLSSM::bootstrap (ssm.mbt:356)`, `DoubleMLSSM::tune (ssm.mbt:438)`, `DoubleMLSSM::psi_a (ssm.mbt:469)`, `DoubleMLSSM::psi_b (ssm.mbt:480)`, `DoubleMLSSM::sensitivity_analysis (ssm.mbt:498)`, `DoubleMLSSM::sensitivity_analysis_cluster (ssm.mbt:526)`, `augment_one_col (ssm.mbt:553)`, `filter_two_values (ssm.mbt:570)`, `cross_fit_ssm (ssm.mbt:600)`, `DoubleMLSSM::fit (ssm.mbt:692)`, `DoubleMLSSM::sandwich_se (ssm.mbt:957)`, `DoubleMLSSM::cluster_sandwich_se (ssm.mbt:988)`, `DoubleMLSSM::bias_corrected_coef (ssm.mbt:1047)`, `DoubleMLCVAR::new (cvar.mbt:128)`, `DoubleMLCVAR::coef (cvar.mbt:280)`, `DoubleMLCVAR::se (cvar.mbt:292)`, `DoubleMLCVAR::confint (cvar.mbt:304)`, `DoubleMLCVAR::predictions_g (cvar.mbt:317)`, `DoubleMLCVAR::predictions_m (cvar.mbt:333)`, `DoubleMLCVAR::sensitivity_analysis (cvar.mbt:376)`, `DoubleMLCVAR::sensitivity_analysis_cluster (cvar.mbt:431)`, `stratified_half_split (cvar.mbt:465)`, `cvar_ipw_score (cvar.mbt:535)`, `solve_ipw_root (cvar.mbt:573)`, `cvar_inner_crossfit (cvar.mbt:668)`, `DoubleMLCVAR::fit (cvar.mbt:841)`, `DoubleMLCVAR::tune (cvar.mbt:1213)`, `DoubleMLCVAR::bootstrap (cvar.mbt:1265)`, `DoubleMLCVAR::sandwich_se (cvar.mbt:1328)`, `DoubleMLCVAR::cluster_sandwich_se (cvar.mbt:1356)`, `DoubleMLCVAR::bias_corrected_coef (cvar.mbt:1414)`, `DoubleMLData::new (data.mbt:42)`, `DoubleMLIIVMData::new (iivm.mbt:18)`, `DoubleMLIIVM::new (iivm.mbt:178)`, `DoubleMLIIVM::coef (iivm.mbt:292)`, `DoubleMLIIVM::se (iivm.mbt:303)`, `DoubleMLIIVM::confint (iivm.mbt:316)`, `filter_by_value (iivm.mbt:400)`, `cross_fit_iivm (iivm.mbt:434)`, `DoubleMLIIVM::fit (iivm.mbt:550)`, `DoubleMLIIVM::fit_cluster (iivm.mbt:817)`, `DoubleMLIIVM::bootstrap (iivm.mbt:1035)`, `DoubleMLIIVM::tune (iivm.mbt:1111)`, `DoubleMLIIVM::sensitivity_analysis (iivm.mbt:1156)`, `DoubleMLIIVM::sensitivity_analysis_cluster (iivm.mbt:1181)`, `DoubleMLIIVM::sandwich_se (iivm.mbt:1230)`, `DoubleMLIIVM::cluster_sandwich_se (iivm.mbt:1258)`, `DoubleMLIIVM::bias_corrected_coef (iivm.mbt:1315)`, `DoubleMLBinaryData::new (lplr.mbt:46)`, `prelim_beta_per_fold (lplr.mbt:76)`, `lplr_score_at (lplr.mbt:184)`, `newton_solve_score (lplr.mbt:236)`, `DoubleMLLPLR::new (lplr.mbt:354)`, `DoubleMLLPLR::coef (lplr.mbt:530)`, `DoubleMLLPLR::se (lplr.mbt:541)`, `DoubleMLLPLR::confint (lplr.mbt:552)`, `DoubleMLLPLR::predictions_t (lplr.mbt:565)`, `DoubleMLLPLR::predictions_m (lplr.mbt:578)`, `DoubleMLLPLR::predictions_a (lplr.mbt:593)`, `concat_d_x (lplr.mbt:608)`, `DoubleMLLPLR::fit (lplr.mbt:661)`, `DoubleMLLPLR::bootstrap (lplr.mbt:1452)`, `DoubleMLLPLR::tune (lplr.mbt:1535)`, `cross_fit_predict_inner (lplr.mbt:1618)`, `predict (lplr.mbt:1687)`, `DoubleMLLPLR::sensitivity_analysis (lplr.mbt:1750)`, `DoubleMLLPLR::sensitivity_analysis_cluster (lplr.mbt:1782)`, `DoubleMLLPLR::sandwich_se (lplr.mbt:1886)`, `DoubleMLLPLR::cluster_sandwich_se (lplr.mbt:1922)`, `DoubleMLLPLR::bias_corrected_coef (lplr.mbt:1968)`, `DoubleMLPLIVData::new (pliv.mbt:23)`, `DoubleMLPLIV::new (pliv.mbt:155)`, `DoubleMLPLIV::coef (pliv.mbt:206)`, `DoubleMLPLIV::se (pliv.mbt:217)`, `DoubleMLPLIV::confint (pliv.mbt:230)`, `DoubleMLPLIV::fit (pliv.mbt:310)`, `DoubleMLPLIV::fit_cluster (pliv.mbt:539)`, `DoubleMLPLIV::bootstrap (pliv.mbt:733)`, `DoubleMLPLIV::tune (pliv.mbt:811)`, `DoubleMLPLIV::sensitivity_analysis (pliv.mbt:875)`, `DoubleMLPLIV::sensitivity_analysis_cluster (pliv.mbt:897)`, `DoubleMLPLIV::sandwich_se (pliv.mbt:943)`, `DoubleMLPLIV::cluster_sandwich_se (pliv.mbt:971)`, `DoubleMLPLIV::bias_corrected_coef (pliv.mbt:1028)`, `DoubleMLPanelData::new (plpr.mbt:51)`, `sort_rows_by_id_time (plpr.mbt:95)`, `unit_means (plpr.mbt:116)`, `unique_units (plpr.mbt:172)`, `est_coef_cluster (plpr.mbt:198)`, `var_est_cluster (plpr.mbt:252)`, `transform_panel (plpr.mbt:319)`, `DoubleMLPLPR::new (plpr.mbt:554)`, `DoubleMLPLPR::coef (plpr.mbt:655)`, `DoubleMLPLPR::se (plpr.mbt:666)`, `DoubleMLPLPR::confint (plpr.mbt:677)`, `DoubleMLPLPR::predictions_l (plpr.mbt:690)`, `DoubleMLPLPR::predictions_m (plpr.mbt:703)`, `DoubleMLPLPR::sensitivity_analysis (plpr.mbt:763)`, `DoubleMLPLPR::fit (plpr.mbt:801)`, `DoubleMLPLPR::bootstrap (plpr.mbt:1181)`, `DoubleMLPLPR::tune (plpr.mbt:1277)`, `DoubleMLPLPR::sensitivity_analysis_cluster (plpr.mbt:1330)`, `DoubleMLPLPR::sandwich_se (plpr.mbt:1401)`, `DoubleMLPLPR::cluster_sandwich_se (plpr.mbt:1437)`, `DoubleMLPLPR::bias_corrected_coef (plpr.mbt:1495)`, `tune_score_outcome (tune.mbt:175)`, `tune_argmin (tune.mbt:215)`, `tune_score_grid (tune.mbt:278)`, `DoubleMLPLR::tune (tune.mbt:352)`, `GBClassifier::fit_weighted (gbclf.mbt:163)`, `predict (gbclf.mbt:302)`, `kahan_sum (kahan.mbt:58)`, `Fold::new (kfold.mbt:225)`, `check_sample_splitting (kfold.mbt:288)`, `kfold_stratified (kfold.mbt:346)`, `kfold (kfold.mbt:439)`, `slice_matrix_rows (kfold.mbt:487)`, `slice_vector (kfold.mbt:501)`, `expand_unit_folds_to_rows (kfold.mbt:536)`, `build_row_unit_map (kfold.mbt:584)`, `cluster_causal_param_and_se (kfold.mbt:640)`, `cross_fit_predict (kfold.mbt:675)`, `double_cross_fit_predict (kfold.mbt:731)`, `RFClassifier::fit_weighted (rfclf.mbt:148)`, `predict (rfclf.mbt:212)`, `DoubleMLDIDCSData::new (did_cs.mbt:37)`, `discover_groups_times (did_cs.mbt:85)`, `DoubleMLDIDCS::new (did_cs.mbt:322)`, `DoubleMLDIDCS::coef_at (did_cs.mbt:446)`, `DoubleMLDIDCS::se_at (did_cs.mbt:491)`, `DoubleMLDIDCS::group_at (did_cs.mbt:774)`, `DoubleMLDIDCS::period_at (did_cs.mbt:789)`, `DoubleMLDIDCS::cell_flat_at (did_cs.mbt:941)`, `DoubleMLDIDCS::cell_psi_a_row_at (did_cs.mbt:969)`, `DoubleMLDIDCS::cell_psi_b_row_at (did_cs.mbt:995)`, `DoubleMLDIDCS::m_inv_1x1_at (did_cs.mbt:1030)`, `DoubleMLDIDCS::sandwich_se_at (did_cs.mbt:1092)`, `DoubleMLDIDCS::cluster_sandwich_se_at (did_cs.mbt:1161)`, `DoubleMLDIDCS::fit (did_cs.mbt:1244)`, `DoubleMLDIDCS::bootstrap (did_cs.mbt:1871)`, `DoubleMLDIDCS::sensitivity_analysis (did_cs.mbt:1953)`, `DoubleMLDIDCS::confint (did_cs.mbt:1999)`, `DoubleMLDIDCS::sensitivity_analysis_cluster (did_cs.mbt:2071)`, `DoubleMLDIDCS::tune (did_cs.mbt:2201)`, `cholesky (linalg.mbt:12)`, `solve_spd (linalg.mbt:74)`, `add_ridge (linalg.mbt:120)`, `inv_spd (linalg.mbt:141)`, `LinearRegression::coefficients (linear.mbt:46)`, `LinearRegression::fit (linear.mbt:96)`, `LinearRegression::xtwx_inv_diag (linear.mbt:134)`, `LinearRegression::covariance_diagonal (linear.mbt:163)`, `LinearRegression::fit_weighted (linear.mbt:197)`, `LinearRegression::predict (linear.mbt:257)`, `LinearRegression::sandwich_se_weighted (linear.mbt:287)`, `LinearRegression::sandwich_se (linear.mbt:350)`, `predict (linear.mbt:438)`, `Matrix::zeros (matrix.mbt:20)`, `Matrix::ones (matrix.mbt:27)`, `Matrix::from_array (matrix.mbt:35)`, `Matrix::copy (matrix.mbt:85)`, `Matrix::from_rows (matrix.mbt:109)`, `matmul (matrix.mbt:135)`, `matvec (matrix.mbt:167)`, `matvec_t (matrix.mbt:192)`, `dot (matrix.mbt:220)`, `mean (matrix.mbt:245)`, `make_irm_data (dgp_irm.mbt:41)`, `make_ssm_data (dgp_ssm.mbt:38)`, `predict (learner.mbt:83)`, `predict (learner.mbt:132)`, `gather_rows (learner.mbt:350)`, `cross_fit_predict_conditional_dispatch (learner.mbt:383)`, `var_est (var_est.mbt:24)`, `var_est_with_jacobian (var_est.mbt:76)`, `count_eq (apo_test.mbt:22)`, `make_iivm_data (dgp_iivm.mbt:40)`, `make_lplr_LZZ2020 (dgp_lplr.mbt:37)`, `make_pliv_CHS2015 (dgp_pliv.mbt:28)`, `make_plpr_CP2025 (dgp_plpr.mbt:42)`, `LogisticRegression::coefficients (logistic.mbt:31)`, `LogisticRegression::fit (logistic.mbt:105)`, `LogisticRegression::predict (logistic.mbt:218)`, `LogisticRegression::predict_class (logistic.mbt:251)`, `argsort_asc (p_adjust.mbt:91)`, `romano_wolf_p_adjust (p_adjust.mbt:128)`, `holm_bonferroni_p_adjust (p_adjust.mbt:223)`, `bonferroni_p_adjust (p_adjust.mbt:254)`, `bh_fdr_p_adjust (p_adjust.mbt:287)`, `by_fdr_p_adjust (p_adjust.mbt:331)`, `bh_step_up_sorted (p_adjust.mbt:388)`, `tsbh_p_adjust (p_adjust.mbt:484)`, `storey_m0_hat (p_adjust.mbt:543)`, `tsby_p_adjust (p_adjust.mbt:609)`, `array_min (quantile.mbt:7)`, `array_max (quantile.mbt:26)`, `outcome_indicator (quantile.mbt:40)`, `cross_fit_conditional (quantile.mbt:77)`, `pq_score_ipw (quantile.mbt:116)`, `pq_score_orthogonal (quantile.mbt:156)`, `fit_propensity (quantile.mbt:191)`, `solve_pq (quantile.mbt:236)`, `DoubleMLPQ::new (quantile.mbt:479)`, `DoubleMLPQ::fit (quantile.mbt:536)`, `DoubleMLPQ::fit_cluster (quantile.mbt:759)`, `DoubleMLPQ::coef (quantile.mbt:913)`, `DoubleMLPQ::se (quantile.mbt:924)`, `DoubleMLPQ::confint (quantile.mbt:976)`, `DoubleMLPQ::bootstrap (quantile.mbt:1006)`, `DoubleMLPQ::sensitivity_analysis (quantile.mbt:1050)`, `DoubleMLPQ::sensitivity_analysis_cluster (quantile.mbt:1072)`, `DoubleMLPQ::m_inv_1x1 (quantile.mbt:1176)`, `DoubleMLPQ::sandwich_se (quantile.mbt:1217)`, `DoubleMLPQ::cluster_sandwich_se (quantile.mbt:1258)`, `DoubleMLPQ::bias_corrected_coef (quantile.mbt:1303)`, `DoubleMLPQ::tune (quantile.mbt:1342)`, `DoubleMLQTE::fit (quantile.mbt:1575)`, `DoubleMLQTE::fit_cluster (quantile.mbt:1848)`, `DoubleMLQTE::confint (quantile.mbt:2075)`, `DoubleMLQTE::bootstrap (quantile.mbt:2137)`, `DoubleMLQTE::sensitivity_analysis (quantile.mbt:2215)`, `DoubleMLQTE::sensitivity_analysis_cluster (quantile.mbt:2271)`, `DoubleMLQTE::m_inv_1x1_at (quantile.mbt:2442)`, `DoubleMLQTE::psi_row (quantile.mbt:2470)`, `DoubleMLQTE::sandwich_se_at (quantile.mbt:2536)`, `DoubleMLQTE::cluster_sandwich_se_at (quantile.mbt:2574)`, `DoubleMLQTE::bias_corrected_coef_at (quantile.mbt:2628)`, `DoubleMLQTE::joint_covariance (quantile.mbt:2740)`, `DoubleMLQTE::cluster_joint_covariance (quantile.mbt:2814)`, `DoubleMLQTE::tune (quantile.mbt:2901)`, `psi_at (sandwich.mbt:215)`, `sandwich_variance_hc0 (sandwich.mbt:273)`, `sandwich_variance_hc1 (sandwich.mbt:317)`, `sandwich_variance_hc2 (sandwich.mbt:366)`, `sandwich_variance_hc3 (sandwich.mbt:416)`, `cluster_sandwich_variance (sandwich.mbt:534)`, `bias_corrected_theta (sandwich.mbt:646)`, `did_bootstrap_t_stat (bootstrap.mbt:66)`, `DoubleMLDIDMulti::new (did_multi.mbt:83)`, `expand_gt_keyword (did_multi.mbt:211)`, `DoubleMLDIDMulti::coef_at_idx (did_multi.mbt:305)`, `DoubleMLDIDMulti::se_at_idx (did_multi.mbt:337)`, `did_multi_inner_cell_at_idx (did_multi.mbt:381)`, `DoubleMLDIDMulti::sandwich_se_at_idx (did_multi.mbt:459)`, `DoubleMLDIDMulti::cluster_sandwich_se_at_idx (did_multi.mbt:515)`, `DoubleMLDIDMulti::bias_corrected_coef_at_idx (did_multi.mbt:560)`, `DoubleMLDIDMulti::tune (did_multi.mbt:682)`, `DoubleMLDIDMulti::bootstrap (did_multi.mbt:732)`, `DoubleMLDIDMulti::t_stats (did_multi.mbt:826)`, `DoubleMLDIDMulti::p_values (did_multi.mbt:856)`, `DoubleMLDIDMulti::p_adjust (did_multi.mbt:942)`, `DoubleMLDIDMulti::confint (did_multi.mbt:1029)`, `draw_bootstrap_weights (did_multi.mbt:1126)`, `DoubleMLDIDMulti::aggregate_group (did_multi.mbt:1175)`, `DoubleMLDIDMulti::aggregate_time (did_multi.mbt:1196)`, `DoubleMLDIDMulti::aggregate_event (did_multi.mbt:1217)`, `DoubleMLDIDMulti::sensitivity_analysis (did_multi.mbt:1263)`, `DoubleMLDIDMulti::sensitivity_analysis_cluster (did_multi.mbt:1333)`, `build_lzz2020_dgp (lplr_test.mbt:21)`, `build_panel_dgp (plpr_test.mbt:12)`, `aggregate_coef_se (aggregator.mbt:33)`, `DoubleMLBLP::new (blp_policy.mbt:68)`, `DoubleMLBLP::fit (blp_policy.mbt:106)`, `DoubleMLBLP::coef (blp_policy.mbt:356)`, `DoubleMLBLP::se (blp_policy.mbt:367)`, `DoubleMLBLP::n_obs (blp_policy.mbt:379)`, `DoubleMLBLP::bootstrap (blp_policy.mbt:409)`, `DoubleMLBLP::rss (blp_policy.mbt:462)`, `DoubleMLBLP::sensitivity_analysis (blp_policy.mbt:498)`, `DoubleMLBLP::sensitivity_analysis_cluster (blp_policy.mbt:564)`, `DoubleMLBLP::var_y (blp_policy.mbt:620)`, `DoubleMLBLP::orth_signal (blp_policy.mbt:635)`, `DoubleMLBLP::basis (blp_policy.mbt:650)`, `DoubleMLBLP::predictions (blp_policy.mbt:670)`, `DoubleMLBLP::confint_joint (blp_policy.mbt:721)`, `DoubleMLBLP::blp_hat_diagonal (blp_policy.mbt:922)`, `DoubleMLBLP::leverage (blp_policy.mbt:958)`, `blp_hac_require_df (blp_policy.mbt:986)`, `DoubleMLBLP::hac_se (blp_policy.mbt:1032)`, `DoubleMLBLP::cluster_hac_se (blp_policy.mbt:1175)`, `policy_tree_build (blp_policy.mbt:1276)`, `DoubleMLPolicyTree::new (blp_policy.mbt:1585)`, `policy_tree_ints_to_doubles (blp_policy.mbt:1707)`, `policy_tree_ints_from_doubles (blp_policy.mbt:1721)`, `policy_tree_cache_decode (blp_policy.mbt:1782)`, `policy_tree_honest_leaf_se (blp_policy.mbt:1840)`, `DoubleMLPolicyTree::fit (blp_policy.mbt:1870)`, `DoubleMLPolicyTree::set_min_leaf_n (blp_policy.mbt:2227)`, `DoubleMLPolicyTree::predict (blp_policy.mbt:2289)`, `DoubleMLPolicyTree::split_feature (blp_policy.mbt:2307)`, `DoubleMLPolicyTree::split_value (blp_policy.mbt:2318)`, `DoubleMLPolicyTree::leaf_se (blp_policy.mbt:2408)`, `DoubleMLPolicyTree::leaf_se_reliable (blp_policy.mbt:2438)`, `DoubleMLPolicyTree::unreliable_leaves (blp_policy.mbt:2459)`, `DoubleMLPolicyTree::smallest_leaf_count (blp_policy.mbt:2483)`, `DoubleMLPolicyTree::policy_value (blp_policy.mbt:2537)`, `DoubleMLPolicyTree::policy_value_se (blp_policy.mbt:2605)`, `DoubleMLPolicyTree::leaf_influence (blp_policy.mbt:2668)`, `DoubleMLPolicyTree::leaf_psi_a (blp_policy.mbt:2709)`, `DoubleMLPolicyTree::sensitivity_analysis (blp_policy.mbt:2785)`, `DoubleMLDIDBinaryData::new (did_binary.mbt:30)`, `preprocess_did_binary (did_binary.mbt:111)`, `DoubleMLDIDBinary::new (did_binary.mbt:355)`, `DoubleMLDIDBinary::coef (did_binary.mbt:515)`, `DoubleMLDIDBinary::se (did_binary.mbt:527)`, `DoubleMLDIDBinary::confint (did_binary.mbt:541)`, `DoubleMLDIDBinary::predictions_m (did_binary.mbt:558)`, `DoubleMLDIDBinary::predictions_g0 (did_binary.mbt:572)`, `DoubleMLDIDBinary::predictions_g1 (did_binary.mbt:586)`, `DoubleMLDIDBinary::sandwich_se (did_binary.mbt:655)`, `DoubleMLDIDBinary::cluster_sandwich_se (did_binary.mbt:681)`, `DoubleMLDIDBinary::bias_corrected_coef (did_binary.mbt:703)`, `DoubleMLDIDBinary::psi_a_long (did_binary.mbt:724)`, `DoubleMLDIDBinary::psi_b_long (did_binary.mbt:744)`, `DoubleMLDIDBinary::inner_psi_a (did_binary.mbt:767)`, `DoubleMLDIDBinary::inner_psi_b (did_binary.mbt:782)`, `DoubleMLDIDBinary::fit (did_binary.mbt:806)`, `DoubleMLDIDBinary::bootstrap (did_binary.mbt:951)`, `DoubleMLDIDBinary::sensitivity_analysis (did_binary.mbt:980)`, `DoubleMLDIDBinary::sensitivity_analysis_cluster (did_binary.mbt:1000)`, `DoubleMLDIDBinary::tune (did_binary.mbt:1080)`, `stratified_kfold (resampling.mbt:19)`, `repeated_kfold (resampling.mbt:130)`, `matrix_predict (vectorized.mbt:50)`, `vector_subtract (vectorized.mbt:77)`, `vector_add (vectorized.mbt:96)`, `vector_scale (vectorized.mbt:115)`, `vector_multiply (vectorized.mbt:135)`, `vector_divide (vectorized.mbt:165)`, `reg_fit_means (regularized.mbt:119)`, `reg_mean_one_weights (regularized.mbt:152)`, `enet_coordinate_descent (regularized.mbt:200)`, `Ridge::coefficients (regularized.mbt:381)`, `Ridge::intercept (regularized.mbt:393)`, `Ridge::fit_weighted (regularized.mbt:421)`, `Ridge::predict (regularized.mbt:479)`, `predict (regularized.mbt:508)`, `Lasso::coefficients (regularized.mbt:576)`, `Lasso::intercept (regularized.mbt:588)`, `Lasso::fit_weighted (regularized.mbt:612)`, `Lasso::predict (regularized.mbt:650)`, `predict (regularized.mbt:677)`, `ElasticNet::coefficients (regularized.mbt:749)`, `ElasticNet::intercept (regularized.mbt:761)`, `ElasticNet::fit_weighted (regularized.mbt:784)`, `ElasticNet::predict (regularized.mbt:828)`, `predict (regularized.mbt:855)`, `enet_objective (regularized.mbt:879)`, `irm_style_sensitivity (sensitivity.mbt:31)`, `irm_style_sensitivity_from_elements (sensitivity.mbt:78)`, `sensitivity_from_variance_baselines (sensitivity.mbt:149)`, `irm_style_sensitivity_cluster_from_elements (sensitivity.mbt:233)`, `irm_style_sensitivity_cluster (sensitivity.mbt:317)`, `empirical_quantile (sensitivity.mbt:402)`, `irm_style_sensitivity_cluster_multi (sensitivity.mbt:448)`, `single_psi_sensitivity (sensitivity.mbt:489)`, `compute_sensitivity_bias (sensitivity.mbt:566)`, `gain_statistics (sensitivity.mbt:689)`, `GainStatsSource::new (sensitivity.mbt:859)`, `GainStatsSource::from_blp (sensitivity.mbt:905)`, `GainStatsSource::from_blp_cv (sensitivity.mbt:974)`, `GainStatsSource::from_blp_cv_repeated (sensitivity.mbt:1094)`, `GainStatsSource::from_blp_hc0 (sensitivity.mbt:1220)`, `median_sorted (sensitivity.mbt:1342)`, `joint_sensitivity (sensitivity.mbt:1516)`, `make_apo_data (v063_wbtest.mbt:16)`, `build_irm_tune_data (v065_wbtest.mbt:67)`, `build_dgp_data (v066_wbtest.mbt:21)`, `PSProcessorConfig::new (ps_processor.mbt:38)`, `PSProcessor::adjust_ps (ps_processor.mbt:248)`, `folds_to_cv_partition (ps_processor.mbt:331)`, `pava (ps_processor.mbt:440)`, `pool_tied_x (ps_processor.mbt:541)`, `fit_isotonic (ps_processor.mbt:581)`, `predict_isotonic (ps_processor.mbt:654)`, `isotonic_calibrate_cv (ps_processor.mbt:748)`, `normalize_ipw (ps_processor.mbt:910)`, `cs_bin_panel_subset (did_cs_binary.mbt:97)`, `cs_bin_crossfit_nuisance (did_cs_binary.mbt:219)`, `fit_cs_bin_g (did_cs_binary.mbt:391)`, `cs_bin_score_obs (did_cs_binary.mbt:441)`, `DoubleMLDIDCSBinary::new (did_cs_binary.mbt:718)`, `DoubleMLDIDCSBinary::coef (did_cs_binary.mbt:807)`, `DoubleMLDIDCSBinary::se (did_cs_binary.mbt:819)`, `DoubleMLDIDCSBinary::confint (did_cs_binary.mbt:832)`, `DoubleMLDIDCSBinary::predictions_g_d0_t0 (did_cs_binary.mbt:939)`, `DoubleMLDIDCSBinary::predictions_g_d0_t1 (did_cs_binary.mbt:954)`, `DoubleMLDIDCSBinary::predictions_g_d1_t0 (did_cs_binary.mbt:969)`, `DoubleMLDIDCSBinary::predictions_g_d1_t1 (did_cs_binary.mbt:984)`, `DoubleMLDIDCSBinary::predictions_m (did_cs_binary.mbt:1000)`, `DoubleMLDIDCSBinary::psi_a (did_cs_binary.mbt:1015)`, `DoubleMLDIDCSBinary::psi_b (did_cs_binary.mbt:1028)`, `DoubleMLDIDCSBinary::bootstrap (did_cs_binary.mbt:1193)`, `DoubleMLDIDCSBinary::cs_bin_sensitivity_nu2_elements (did_cs_binary.mbt:1263)`, `DoubleMLDIDCSBinary::cs_bin_sensitivity_residuals (did_cs_binary.mbt:1382)`, `DoubleMLDIDCSBinary::sensitivity_analysis_cluster (did_cs_binary.mbt:1465)`, `DoubleMLDIDCSBinary::sandwich_se (did_cs_binary.mbt:1521)`, `DoubleMLDIDCSBinary::cluster_sandwich_se (did_cs_binary.mbt:1554)`, `DoubleMLDIDCSBinary::bias_corrected_coef (did_cs_binary.mbt:1612)`, `DoubleMLDIDCSBinary::tune (did_cs_binary.mbt:1704)`, `mean_at (logistic_test.mbt:23)`, `make_did_CS2021 (dgp_did_CS2021.mbt:43)`, `make_did_SZ2020 (dgp_did_SZ2020.mbt:19)`, `make_simple_rdd_dgp (dgp_simple_rdd.mbt:42)`, `make_plr_CCDDHNR2018 (dgp_plr_CCDDHNR.mbt:45)`, `make_plr_turrell2018 (dgp_plr_turrell.mbt:20)`, `aggregate_group (did_aggregation.mbt:41)`, `aggregate_time (did_aggregation.mbt:107)`, `aggregate_event (did_aggregation.mbt:168)`, `generic_bootstrap_t_stat (bootstrap_helper.mbt:47)`, `generic_bootstrap_single_psi (bootstrap_helper.mbt:104)`, `generic_bootstrap_ols_per_coef (bootstrap_helper.mbt:165)`, `make_irm_discrete_treatments (dgp_irm_discrete.mbt:24)`, `make_pliv_multiway_cluster (dgp_pliv_cluster.mbt:35)`, `v085_int_array_eq (expand_v085_test.mbt:77)`, `v085_dbl_array_close (expand_v085_test.mbt:94)`, `expand_v086_psi (expand_v086_test.mbt:72)`, `expand_v086_ref_hc0 (expand_v086_test.mbt:96)`, `expand_v087_psi (expand_v087_test.mbt:99)`, `expand_v087_ref_hc0 (expand_v087_test.mbt:133)`, `expand_v087_ref_leverage (expand_v087_test.mbt:166)`, `expand_v087_ssm_data (expand_v087_test.mbt:207)`, `expand_v087_cs_binary_data (expand_v087_test.mbt:260)`, `expand_v088_input_a (expand_v088_test.mbt:74)`, `expand_v089_psi (expand_v089_test.mbt:86)`, `expand_v089_ref_hc0 (expand_v089_test.mbt:111)`, `expand_v089_ref_leverage (expand_v089_test.mbt:137)`, `expand_v089_ref_cluster (expand_v089_test.mbt:171)`, `expand_v089_did_binary_data (expand_v089_test.mbt:222)`, `expand_v089_apo_data (expand_v089_test.mbt:273)`, `expand_v090_data (expand_v090_test.mbt:85)`, `expand_v091_data (expand_v091_test.mbt:92)`, `expand_v091_iivm_data (expand_v091_test.mbt:119)`, `expand_v091_cluster_ids (expand_v091_test.mbt:166)`, `expand_v091_old_accumulator (expand_v091_test.mbt:183)`, `expand_v092_lplr_data (expand_v092_test.mbt:74)`, `expand_v092_cluster_ids (expand_v092_test.mbt:135)`, `expand_v093_lpq_data (expand_v093_test.mbt:83)`, `expand_v093_cluster_ids (expand_v093_test.mbt:132)`, `expand_v093_lpq_data_scaled (expand_v093_test.mbt:381)`, `expand_v094_pq_data_scaled (expand_v094_test.mbt:82)`, `expand_v094_cluster_ids (expand_v094_test.mbt:126)`, `expand_v095_qte_data (expand_v095_test.mbt:105)`, `expand_v095_row (expand_v095_test.mbt:159)`, `expand_v095_cluster_ids (expand_v095_test.mbt:170)`, `expand_v095_qte_data_wide (expand_v095_test.mbt:928)`, `v096_dgp (expand_v096_test.mbt:85)`, `v096_dgp_lopsided (expand_v096_test.mbt:124)`, `v096_side_wls (expand_v096_test.mbt:166)`, `v096_meat (expand_v096_test.mbt:246)`, `v096_meat_leverage (expand_v096_test.mbt:262)`, `v097_dgp (expand_v097_test.mbt:28)`, `v097_dgp_constant_leverage (expand_v097_test.mbt:50)`, `v097_reference (expand_v097_test.mbt:79)`, `v097_hc_se (expand_v097_test.mbt:160)`, `v098_dbl_array_eq_nan_aware (expand_v098_test.mbt:121)`, `v098_dgp (expand_v098_test.mbt:172)`, `v098_int_array_eq (expand_v098_test.mbt:457)`, `v098_leaf_means_match_raw (expand_v098_test.mbt:474)`, `v099_dgp (expand_v099_test.mbt:61)`, `v099_identical (expand_v099_test.mbt:84)`, `expand_v101_qte_data (expand_v101_test.mbt:53)`, `expand_v101_cluster_ids (expand_v101_test.mbt:86)`, `expand_v101_row (expand_v101_test.mbt:99)`, `v106_build_panel (expand_v106_test.mbt:52)`, `v106_singletons (expand_v106_test.mbt:92)`, `v107_ssm_dgp (expand_v107_test.mbt:26)`, `v108_dgp (expand_v108_test.mbt:51)`, `v109_plr_data (expand_v109_test.mbt:44)`, `v110_rdd_data (expand_v110_test.mbt:45)`, `v115_rdd_data (expand_v115_test.mbt:76)`, `v115_exact_quadratic (expand_v115_test.mbt:335)`, `v116_assert_exact (expand_v116_test.mbt:134)`, `v117_threshold_data (expand_v117_test.mbt:39)`, `v117_xor_data (expand_v117_test.mbt:54)`, `v117_prob_dev (expand_v117_test.mbt:82)`, `v118_data (expand_v118_test.mbt:70)`, `v118_weights (expand_v118_test.mbt:84)`, `v118_mean (expand_v118_test.mbt:94)`, `v118_clf_data (expand_v118_test.mbt:114)`, `v120_max_abs_diff (expand_v120_test.mbt:54)`, `v120_means (expand_v120_test.mbt:87)`, `v120_expect (expand_v120_test.mbt:160)`, `v120_kfold_folds (expand_v120_test.mbt:6692)`, `v120_check_ridge (expand_v120_test.mbt:6717)`, `v120_check_enet (expand_v120_test.mbt:6749)`, `v121_max_abs_diff (expand_v121_test.mbt:50)`, `v121_expect (expand_v121_test.mbt:72)`, `v122_expect_bool (expand_v122_test.mbt:257)`, `v127_panel (expand_v127_test.mbt:40)`, `v127_raw (expand_v127_test.mbt:85)`, `v128_cs_data (expand_v128_test.mbt:31)`, `v128_xs_data (expand_v128_test.mbt:404)`, `v130_cs_data (expand_v130_test.mbt:36)`, `zz_gate_y_variant (expand_v130_test.mbt:485)`, `v1316_did_data (expand_v131_test.mbt:18)`, `v1317_data (expand_v131_test.mbt:177)`, `v1320_dgp (expand_v132_test.mbt:43)`, `v1330_data (expand_v133_test.mbt:37)`, `v1340_data (expand_v134_test.mbt:49)`, `v1350_data (expand_v135_test.mbt:42)`, `v1380_data (expand_v138_test.mbt:99)`, `v1390_data (expand_v139_test.mbt:78)`, `v1390_changed_steps (expand_v139_test.mbt:102)`, `v1440_plr_fixture (expand_v144_test.mbt:22)`, `v1480_corr (expand_v148_test.mbt:57)`, `v1480_cell_fit (expand_v148_test.mbt:87)`, `v1510_dot (expand_v151_test.mbt:41)`, `v1510_center (expand_v151_test.mbt:50)`, `v1510_resid_after (expand_v151_test.mbt:79)`, `v1510_corr (expand_v151_test.mbt:250)`, `v1550_score_gate_dgp (expand_v155_test.mbt:36)`, `v1590_data (expand_v159_test.mbt:131)`, `build_clustered_dgp (plr_cluster_test.mbt:10)`, `build_row_dgp (plr_cluster_test.mbt:57)`, `make_did_cs_CS2021 (dgp_did_cs_CS2021.mbt:56)`, `DoubleMLDIDCrossSectionData::new (did_cross_section.mbt:35)`, `DoubleMLDIDCrossSection::new (did_cross_section.mbt:188)`, `DoubleMLDIDCrossSection::psi_a (did_cross_section.mbt:252)`, `DoubleMLDIDCrossSection::psi_b (did_cross_section.mbt:286)`, `DoubleMLDIDCrossSection::predictions_g_d0_t0 (did_cross_section.mbt:301)`, `DoubleMLDIDCrossSection::predictions_g_d0_t1 (did_cross_section.mbt:316)`, `DoubleMLDIDCrossSection::predictions_g_d1_t0 (did_cross_section.mbt:331)`, `DoubleMLDIDCrossSection::predictions_g_d1_t1 (did_cross_section.mbt:346)`, `DoubleMLDIDCrossSection::predictions_m (did_cross_section.mbt:363)`, `DoubleMLDIDCrossSection::coef (did_cross_section.mbt:377)`, `DoubleMLDIDCrossSection::se (did_cross_section.mbt:389)`, `DoubleMLDIDCrossSection::confint (did_cross_section.mbt:451)`, `crossfit_nuisance (did_cross_section.mbt:519)`, `fit_g_subset_predict (did_cross_section.mbt:630)`, `norm_ppf (did_cross_section.mbt:711)`, `compute_score (did_cross_section.mbt:738)`, `DoubleMLDIDCrossSection::tune (did_cross_section.mbt:1143)`, `DoubleMLDIDCrossSection::bootstrap (did_cross_section.mbt:1191)`, `DoubleMLDIDCrossSection::sensitivity_analysis (did_cross_section.mbt:1291)`, `DoubleMLDIDCrossSection::sensitivity_analysis_cluster (did_cross_section.mbt:1323)`, `DoubleMLDIDCrossSection::sandwich_se (did_cross_section.mbt:1400)`, `DoubleMLDIDCrossSection::cluster_sandwich_se (did_cross_section.mbt:1436)`, `DoubleMLDIDCrossSection::bias_corrected_coef (did_cross_section.mbt:1510)`, `build_iv_clustered_dgp (pliv_cluster_test.mbt:10)`, `make_irm_confounded_data (dgp_irm_confounded.mbt:30)`, `make_confounded_plr_data (dgp_plr_confounded.mbt:25)`, `plr_iv_test_dgp (plr_iv_type_wbtest.mbt:41)`, `make_simple_plr_data (bootstrap_v061_wbtest.mbt:19)`, `assert_bootstrap_t_stat_basic (bootstrap_v061_wbtest.mbt:42)`, `make_irm_heterogeneous_data (dgp_irm_heterogeneous.mbt:31)`, `expand_v100_psi_b_row (expand_v100_apos_test.mbt:124)`, `expand_v100_cluster_ids (expand_v100_apos_test.mbt:139)`, `expand_v100_square (expand_v100_apos_test.mbt:697)`, `expand_v100_didcs_cluster_ids (expand_v100_didcs_test.mbt:247)`, `expand_v100_didmulti_cluster_ids (expand_v100_didmulti_test.mbt:239)`

## 9. Method summary

| Capability | Engine | Precision statement |
| --- | --- | --- |
| CFG + dead/unreachable | static (syntax-directed) | sound relative to the parsed subset; parser gaps are reported |
| Path coverage | dynamic (trace) | exact for executed trials; no guarantee for unexecuted paths |
| Taint (L1) | dynamic + symbolic labels | flow-sensitive within a trial; container field sensitivity is coarse |
| Taint (L2) | abstract interpretation | may-analysis over the input abstraction; loop widening loses precision |
| Ranges (L1) | dynamic sampling | union of observed values; not a proof |
| Ranges (L2) | interval / value-set domain | over-approximation at widening; sound relative to the abstract semantics |
| Contracts (L3) | WP-style VC + interval decision | `proved` only from entailed preconditions; `unknown` when facts are insufficient |
| Evolved value analysis (L2-EVA) | the same fixpoint, asking what a value is USED FOR | may-analysis; a hit means the abstract state cannot exclude the defect, and the classes MoonBit cannot express are RESERVED and never fire |
| Foreign address space (L2-FFI) | static model of the C boundary | the C side is invisible; the checks are about the MoonBit side of the contract, and the report says which ones cannot be checked at all |
| Memory layout (L2-memory) | static model of the module's globals | a collection that only grows is reported when the analyzer can PROVE the growth is unbounded: a loop it cannot bound, and no removal anywhere in the module |
| Concurrency (L2-CONC) | interleaving model over the tasks | MoonBit tasks run on one thread (measured), so the defect class is interleaving sensitivity; a hit means the read-modify-write is not atomic with its read |
| Slicing | dynamic dependence graph | exact for the recorded trace; not a static closure |

## 10. Reproduction

```text
LunaFlow analyze riantr/moonbit_doubleML@latest --out reports/ --funnel
```

The findings tables above are bounded, so this report may not carry every finding. The ones it does not carry are in the `_findings.jsonl` sidecar beside this file -- one JSON object per finding, with the family, the severity, the function, the file, the line, the message, the method and the confidence. The sidecar holds EVERY finding the report rendered, so nothing is lost to the bound.

Full method description, comparison with Frama-C/TIS, Joern, CodeQL, SVF and Soot, and the acceptance tests are in `docs/design.md`.
