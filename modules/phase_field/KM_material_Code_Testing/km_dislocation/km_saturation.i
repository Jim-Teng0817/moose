# Test 1 of plan §7: full-model saturation (km_saturation.i)
# Full ODE with k1, k2_dyn (Estrin-Mecking), k2_stat all active. Held at fixed
# gamma_dot > 0 and constant T. Run until rho approaches rho_sat.

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
  [km]
    type = KocksMeckingDislocation
    gamma_dot = gamma_dot
    T = T
    enable_storage = true
    enable_dynamic_recovery = true
    enable_static_recovery = true
    mu = 4.2e10
    b = 2.56e-10
    L_obs = 1.0e-6
    k20 = 10.0
    Q_dyn = 0.5
    Q_units = eV
    n_exp = 5.0
    gdot_ref = 1.0
    ks0 = 1.0e4
    Q_climb = 1.5
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
