# Test 9 of plan §7: end-to-end rho_var path (km_with_deformed_grain_material.i)
# 2-grain bicrystal with constant OPs (no phase-field evolution). KocksMecking
# rho -> MaterialRealAux -> aux variable rho_grain -> DeformedGrainMaterial.rho_var.
# Acceptance: at t=dt, Def_Eng from DeformedGrainMaterial equals beta * rho_avg
# where rho_avg comes from the KocksMecking material directly.

# Purpose:
#   KM-only sensitivity study.
#   No grain growth.
#   No grain tracker.
#   No nucleation.
#   No rho_eff.
#   No text-file rho input.
#
# Output:
#   rho_avg vs time for different T, strain_rate, and rho_init.

# km_only_sensitivity.i
# Purpose:
#   KM-only sensitivity study.
#   No grain growth.
#   No grain tracker.
#   No nucleation.
#   No rho_eff.
#   No text-file rho input.
#
# Output:
#   rho_avg vs time for different T, strain_rate, and rho_init.

# -------------------------
# Study parameters
# -------------------------
time_scale_i = 1.0

T_i = 1073                     # 873, 973, 1073, 1173, 1273 K
strain_rate_i = 100.0            # 0.1, 1.0, 10.0, 100.0, 1000.0 
rho_init_i = 1.0e16            # 1e14, 1e15, 1e16, 1e17, 1e18

dt_i = 1.0e-2
end_time_i = 10.0

# out_dir = 'KM_output/rho_init_1e16/GammadotSen_Temp1073'
# case_name = 'km_Gammadot100'

# -------------------------
# KM model parameters
# -------------------------
burger_i = 2.96e-10
G_shear_i = 32.7e9
theta_0_i = 0.1635e9
M_taylor_i = 2.75
alpha_taylor_i = 0.3

m_i = 0.22
k20_i = 10
Q_dyn_i = 1.0426
Q_units_i = 'eV'

# -------------------------
# Tiny u (dummy) mesh
# -------------------------
[Mesh]
  type = GeneratedMesh
  dim = 2
  nx = 1
  ny = 1
  xmin = 0.0
  xmax = 1.0
  ymin = 0.0
  ymax = 1.0
[]

# Dummy variable only to make a simple transient solve.
# It is not part of the KM physics.
[Variables]
  [u]                              # a dummy variable
    initial_condition = 0.0
  []
[]

[Kernels]
  [u_reaction]
    type = Reaction
    variable = u
  []
[]

[AuxVariables]
  [gamma_dot]
    initial_condition = ${strain_rate_i}
  []

  [T]
    initial_condition = ${T_i}
  []
[]

[Materials]
  [k1]
    type = ParsedMaterial
    property_name = k1

    constant_names = 'b G theta_0 M_taylor alpha_taylor'
    constant_expressions = '${burger_i} ${G_shear_i} ${theta_0_i} ${M_taylor_i} ${alpha_taylor_i}'

    expression = '2 * theta_0 / (M_taylor * alpha_taylor * G * b)'
    block = 0
  []

  [km]
    type = KocksMeckingDislocation

    gamma_dot = gamma_dot
    T = T

    enable_storage = true
    enable_dynamic_recovery = true
    enable_static_recovery = false

    k1_name = k1
    k20 = ${k20_i}
    Q_dyn = ${Q_dyn_i}
    Q_units = ${Q_units_i}
    m = ${m_i}

    rho_init = ${rho_init_i}
    time_scale = ${time_scale_i}

    block = 0
  []

  [k2dyn_t_diag]
    type = ParsedMaterial
    property_name = k2dyn_t_diag

    coupled_variables = 'gamma_dot T'

    constant_names = 'k20 m Q kB'
    constant_expressions = '${k20_i} ${m_i} ${Q_dyn_i} 8.617333262e-5'

    expression = 'k20 * pow(gamma_dot, 1.0 - m) * exp(-m * Q / (kB * T))'
    block = 0
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

  [k1_avg]
    type = ElementAverageMaterialProperty
    mat_prop = k1
  []

  [k2dyn_t_avg]
    type = ElementAverageMaterialProperty
    mat_prop = k2dyn_t_diag
  []

  [gdot_avg]
    type = ElementAverageValue
    variable = gamma_dot
  []

  [T_avg]
    type = ElementAverageValue
    variable = T
  []
[]

[Executioner]
  type = Transient
  scheme = implicit-euler
  solve_type = NEWTON

  start_time = 0.0
  end_time = ${end_time_i}

  nl_abs_tol = 1.0e-12
  nl_rel_tol = 1.0e-10
  nl_max_its = 20

  [TimeStepper]
    type = ConstantDT
    dt = ${dt_i}
  []
[]

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []

  file_base = ${out_dir}/${case_name}
[]