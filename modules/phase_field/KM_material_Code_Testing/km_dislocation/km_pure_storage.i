# Test 3 of plan §7: pure-storage limit (km_pure_storage.i)
# Disable both dynamic and static recovery; expect linear growth in sqrt(rho)
# under constant gamma_dot = 1, rho0 = 1e10.

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
    initial_condition = 1.0
  []
  [T]
    initial_condition = 600.0
  []
[]

[Materials]
  [km]
    type = KocksMeckingDislocation
    gamma_dot = gamma_dot
    T = T
    enable_storage = true
    enable_dynamic_recovery = false
    enable_static_recovery = false
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
  dt = 0.1
  end_time = 1.0
[]

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]
