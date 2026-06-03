# Test 8 of plan §7: external-coefficient mode matches internal (km_external_coeff_match.i)
# Same physics as Test 1 (saturation), but k1, k2_dyn, k2_stat supplied through
# external MaterialPropertyName overrides (k1_name, k2_dyn_name, k2_stat_name).
# Constants chosen to reproduce the internal closed-form values at the fixed
# gamma_dot, T used here.

[Mesh]
  type = GeneratedMesh
  dim = 1
  nx = 1
  xmax = 1.0
[]

[Problem]
  solve = false
[]

[AuxVariables]
  [gamma_dot]
    initial_condition = 1.0e-3
  []
  [T]
    initial_condition = 873.0
  []
[]

[Materials]
  # External coefficient providers. Numerical values are placeholders; the
  # tests spec / compute_gold step will compute the matching constants from
  # mu, b, L_obs, k20, Q_dyn, n_exp, gdot_ref, ks0, Q_climb at T=873 K and
  # gamma_dot=1e-3 to enforce bit-identity vs Test 1.
  [coeffs]
    type = GenericConstantMaterial
    prop_names = 'k1_ext k2_dyn_ext k2_stat_ext'
    prop_values = '0.0 0.0 0.0'
  []

  [km]
    type = KocksMeckingDislocation
    gamma_dot = gamma_dot
    T = T
    enable_storage = true
    enable_dynamic_recovery = true
    enable_static_recovery = true
    k1_name = k1_ext
    k2_dyn_name = k2_dyn_ext
    k2_stat_name = k2_stat_ext
    # Taylor relation still uses internal mu, b for tau_flow output.
    mu = 4.2e10
    b = 2.56e-10
    rho_init = 1.0e10
  []
[]

[Postprocessors]
  [rho_avg]
    type = ElementAverageMaterialProperty
    mat_prop = rho
  []
  [tau_avg]
    type = ElementAverageMaterialProperty
    mat_prop = tau_flow
  []
[]

[Executioner]
  type = Transient
  dt = 10.0
  end_time = 1.0e5
[]

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]
