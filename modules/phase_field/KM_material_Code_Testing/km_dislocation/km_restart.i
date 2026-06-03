# Test 7 of plan §7 (Stage A): static-recovery run with checkpoint output.
# Drives 100 steps from rho_init = 1e12; Outputs/checkpoint enabled. Stage B
# restarts from this run and is encoded in km_restart_restart.i (per the
# restart/new_dt style reference, which uses two .i files).
# Acceptance for the pair: rel_err < 1e-12 between Stage A and Stage B at the
# comparison step (NOT bit-identity).

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
[]

[Executioner]
  type = Transient
  dt = 1.0
  num_steps = 100
[]

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []
  checkpoint = true
[]
