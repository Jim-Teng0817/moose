# Test 6 of plan §7: EBSD-style non-uniform IC via rho_init_prop (km_ic_from_ebsd.i)
# 4x4 mesh. A ParsedFunction encoding a checkerboard pattern feeds a
# GenericFunctionMaterial property "rho_ic", which KocksMeckingDislocation
# consumes via rho_init_prop. One step at gamma_dot = 0, T = 600 K, dt = 100 s
# with static recovery enabled.

[Mesh]
  type = GeneratedMesh
  dim = 2
  nx = 4
  ny = 4
  xmin = 0.0
  xmax = 4.0
  ymin = 0.0
  ymax = 4.0
[]

[Problem]
  solve = false
[]

[AuxVariables]
  [gamma_dot]
    initial_condition = 0.0
  []
  [T]
    initial_condition = 600.0
  []
[]

[Functions]
  [rho_checker]
    type = ParsedFunction
    # Checkerboard: 1e14 when (floor(x)+floor(y)) is even, else 1e10
    expression = '1.0e10 + 1.0e14 * (1 - ((floor(x)+floor(y)) - 2*floor((floor(x)+floor(y))/2)))'
  []
[]

[Materials]
  [rho_ic_mat]
    type = GenericFunctionMaterial
    prop_names = 'rho_ic'
    prop_values = 'rho_checker'
  []
  [km]
    type = KocksMeckingDislocation
    gamma_dot = gamma_dot
    T = T
    enable_storage = false
    enable_dynamic_recovery = false
    enable_static_recovery = true
    ks0 = 1.0e4
    Q_climb = 1.5
    Q_units = eV
    rho_init_prop = rho_ic
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
  dt = 100.0
  end_time = 100.0
[]

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [exodus]
    type = Exodus
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]
