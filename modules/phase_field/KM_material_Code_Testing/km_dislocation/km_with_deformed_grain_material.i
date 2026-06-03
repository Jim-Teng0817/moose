# Test 9 of plan §7: end-to-end rho_var path (km_with_deformed_grain_material.i)
# 2-grain bicrystal with constant OPs (no phase-field evolution). KocksMecking
# rho -> MaterialRealAux -> aux variable rho_grain -> DeformedGrainMaterial.rho_var.
# Acceptance: at t=dt, Def_Eng from DeformedGrainMaterial equals beta * rho_avg
# where rho_avg comes from the KocksMecking material directly.

[Mesh]
  type = GeneratedMesh
  dim = 2
  nx = 8
  ny = 8
  xmin = 0.0
  xmax = 1.0
  ymin = 0.0
  ymax = 1.0
[]

[GlobalParams]
  op_num = 2
  var_name_base = gr
  deformed_grain_num = 2
[]

[Variables]
  [gr0]
    [InitialCondition]
      type = FunctionIC
      function = 'if(x<0.5, 1, 0)'
    []
  []
  [gr1]
    [InitialCondition]
      type = FunctionIC
      function = '1 - if(x<0.5, 1, 0)'
    []
  []
[]

[AuxVariables]
  [gamma_dot]
    initial_condition = 1.0e-3
  []
  [T]
    initial_condition = 873.0
  []
  [rho_grain]
    family = MONOMIAL
    order = CONSTANT
  []
[]

[AuxKernels]
  [rho_grain_aux]
    type = MaterialRealAux
    variable = rho_grain
    property = rho
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]

[Kernels]
  [gr0_dt]
    type = TimeDerivative
    variable = gr0
  []
  [gr1_dt]
    type = TimeDerivative
    variable = gr1
  []
[]

[UserObjects]
  [grain_tracker]
    type = GrainTrackerDislocations
    threshold = 0.2
    connecting_threshold = 0.08
    compute_var_to_feature_map = true
    flood_entity_type = elemental
    execute_on = 'initial timestep_begin'
    outputs = none
    tolerate_failure = true
  []
[]

[Materials]
  [km]
    type = KocksMeckingDislocation
    gamma_dot = gamma_dot
    T = T
    enable_storage = true
    enable_dynamic_recovery = true
    enable_static_recovery = false
    mu = 4.2e10
    b = 2.56e-10
    L_obs = 1.0e-6
    k20 = 10.0
    Q_dyn = 0.5
    Q_units = eV
    n_exp = 5.0
    gdot_ref = 1.0
    rho_init = 1.0e12
  []
  [deformed]
    type = DeformedGrainMaterial
    grain_tracker = grain_tracker
    rho_var = rho_grain
    wGB = 4.0
    GBenergy = 0.708
    GBMobility = 2.5e-14
    T = 300
    length_scale = 1.0
    time_scale = 1.0
    outputs = none
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
  [Def_Eng]
    type = ElementAverageMaterialProperty
    mat_prop = deformation_energy
  []
  [beta_avg]
    type = ElementAverageMaterialProperty
    mat_prop = beta
  []
[]

[Executioner]
  type = Transient
  solve_type = PJFNK
  dt = 1.0
  num_steps = 1
  nl_abs_tol = 1.0e-10
  nl_rel_tol = 1.0e-8
[]

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]
