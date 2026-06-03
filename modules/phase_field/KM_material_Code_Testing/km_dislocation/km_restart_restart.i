# Test 7 of plan §7 (Stage B): restart leg of the km_restart pair.
# Picks up the checkpoint produced by km_restart.i at step 50 and runs the
# remaining 50 steps. The plan also requires that initQpStatefulProperties
# is NOT called on the restart leg; that is checked indirectly by setting a
# different rho_init here (1.0e8) and confirming the restart value is used.

[Mesh]
  file = km_restart_out_cp/0050-mesh.cpa.gz
[]

[Problem]
  restart_file_base = km_restart_out_cp/0050
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
    # Intentionally different from Stage A; should be ignored on restart.
    rho_init = 1.0e8
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
  dt = 1.0
  num_steps = 50
  start_time = 50.0
[]

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]
