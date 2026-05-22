# Test 2 of plan §7: static-recovery hold (km_static_recovery.i)
# gamma_dot = 0 and T = 873 K held. rho0 = 1e14. Expect log-linear decay
# governed by k2_stat(873). end_time covers at least one decade ln(10)/k2_stat.

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
    initial_condition = 0.0
  []
  [T]
    initial_condition = 873.0
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
    rho_init = 1.0e14
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
  [log_rho]
    type = ParsedPostprocessor
    expression = 'log(rho_avg)'
    pp_names = 'rho_avg'
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
