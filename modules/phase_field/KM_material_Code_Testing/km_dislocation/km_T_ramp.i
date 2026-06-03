# Test 4 of plan §7: T-ramp static recovery (km_T_ramp.i)
# gamma_dot = 0, storage and dynamic recovery disabled. Temperature linearly
# ramped 300 -> 900 K over 1000 s, driving k2_stat(T). Catches a sign error
# on Q_climb that a constant-T test cannot detect.

[Mesh]
  type = GeneratedMesh
  dim = 1
  nx = 1
  xmax = 1.0
[]

[Problem]
  solve = false
[]

[Functions]
  [T_ramp]
    type = ParsedFunction
    expression = '300.0 + 0.6 * t'
  []
[]

[AuxVariables]
  [gamma_dot]
    initial_condition = 0.0
  []
  [T]
    family = LAGRANGE
    order = FIRST
  []
[]

[AuxKernels]
  [set_T]
    type = FunctionAux
    variable = T
    function = T_ramp
    execute_on = 'INITIAL TIMESTEP_BEGIN'
  []
[]

[Materials]
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
    rho_init = 1.0e12
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
  [T_avg]
    type = ElementAverageValue
    variable = T
  []
[]

[Executioner]
  type = Transient
  dt = 1.0
  end_time = 1000.0
[]

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]
