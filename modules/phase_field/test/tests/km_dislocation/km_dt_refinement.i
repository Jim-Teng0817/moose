# Test 5 of plan §7: dt-refinement / first-order convergence (km_dt_refinement.i)
# Same setup as Test 2 (static decay). Default dt = 1.0; the tests spec
# overrides via cli_args = 'Executioner/dt=0.1' and 'Executioner/dt=0.01'
# to drive the three sub-runs (cleaner than three near-duplicate .i files).

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
[]

[Executioner]
  type = Transient
  # dt = 1.0 chosen so Test 5 can override via cli_args = 'Executioner/dt=0.1' etc.
  dt = 1.0
  end_time = 100.0
[]

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]
