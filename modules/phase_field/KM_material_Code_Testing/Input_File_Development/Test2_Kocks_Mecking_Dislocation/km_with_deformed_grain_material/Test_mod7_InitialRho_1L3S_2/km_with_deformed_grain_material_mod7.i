# Test 9 of plan §7: end-to-end rho_var path (km_with_deformed_grain_material.i)
# 2-grain bicrystal with constant OPs (no phase-field evolution). KocksMecking
# rho -> MaterialRealAux -> aux variable rho_grain -> DeformedGrainMaterial.rho_var.
# Acceptance: at t=dt, Def_Eng from DeformedGrainMaterial equals beta * rho_avg
# where rho_avg comes from the KocksMecking material directly.

# adaptivity
mesh_adaptivity_level = 3 # 2 3
coarsen_i = 0.06
refine_i = 0.20

# time
# time_scale_i = '${units 0.001 s}'    # in default, 1e-9 s = 1 ns      1   1e-9  0.001
# time_scale_i = '${units 1 s}'
time_scale_i = 1e-2         # 1e-6
dt_i = 2e-1                
end_time_i = '${fparse 10 * (1/time_scale_i)}'    
# sync_times_i = '${fparse 1800 * (1/time_scale_i)}'   # represent the 1800 s = 30 min

# length
length_scale_i = '${units 1e-8 m}'   # in default, 1e-9 m = 1 nm    1e-6   1e-9

# Initial Dislocation Input Text File
input_text_file = test_1L3S_2

# Filename
Folder_name = 'Output/'
mod_num = 7

[Mesh]
  type = GeneratedMesh
  dim = 2
  nx = 16
  ny = 16
  xmin = 0.0
  xmax = 64.0
  ymin = 0.0
  ymax = 64.0
[]

[GlobalParams]
  op_num = 4
  var_name_base = gr
  deformed_grain_num = 4
  grain_num = 4
  grain_tracker = grain_tracker
  time_scale = ${time_scale_i}
  length_scale = ${length_scale_i}
[]

[Variables]
  # [gr0]                                    # Removed for DeformedGrain (Jim June 5, 2026)
  #   [InitialCondition]
  #     type = FunctionIC
  #     function = 'if(x<0.5, 1, 0)'
  #   []
  # []
  # [gr1]                                    # Removed for DeformedGrain (Jim June 5, 2026)
  #   [InitialCondition]
  #     type = FunctionIC
  #     function = '1 - if(x<0.5, 1, 0)'
  #   []
  # []
  [PolycrystalVariables]                     # Added for DeformedGrain (Jim June 5, 2026)
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
  [./bnds]
    order = FIRST
    family = LAGRANGE
  [../]
[]

[AuxKernels]
  [rho_grain_aux]
    type = MaterialRealAux
    variable = rho_grain
    property = rho
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [./BndsCalc]
    type = BndsCalcAux
    variable = bnds
    execute_on = timestep_end
  [../]
[]

[Kernels]
  # [gr0_dt]                              # Removed for DeformedGrain (Jim June 5, 2026)
  #   type = TimeDerivative
  #   variable = gr0
  # []
  # [gr1_dt]                              # Removed for DeformedGrain (Jim June 5, 2026)
  #   type = TimeDerivative
  #   variable = gr1
  # []
  [PolycrystalKernel]                     # Added for DeformedGrain (Jim June 5, 2026)
  []
  [PolycrystalStoredEnergy]               # Added for DeformedGrain (Jim June 5, 2026)
    grain_tracker = grain_tracker
  []
[]

[UserObjects]
  [voronoi]                               # Added for DeformedGrain (Jim June 5, 2026)
    type = PolycrystalVoronoi
    rand_seed = 81
    coloring_algorithm = bt
  []
  [dislocation_density_file]              # To make it run (Jim June 5, 2026)
    type = DislocationDensityFileReader
    file_name = '${input_text_file}.txt'
    lines_to_skip = 0
  []
  [grain_tracker]
    type = GrainTrackerDislocations
    threshold = 0.2
    connecting_threshold = 0.08
    compute_var_to_feature_map = true
    flood_entity_type = elemental
    execute_on = 'initial timestep_begin'
    outputs = none
    dislocation_density_reader = dislocation_density_file # To make it run (Jim June 5, 2026)
    polycrystal_ic_uo = voronoi                           # Add and deleted To make it run (Jim June 5, 2026) # Added for DeformedGrain (Jim June 5, 2026)
    tolerate_failure = true
  []
[]

[ICs]                                                   # Add and deleted To make it run (Jim June 5, 2026)
  [PolycrystalICs]                                    # Added for DeformedGrain (Jim June 5, 2026)
    [PolycrystalColoringIC]
      polycrystal_ic_uo = voronoi
    []
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
    outputs = exodus
  []
  [deformed]
    type = DeformedGrainMaterial
    grain_tracker = grain_tracker
    rho_var = rho_grain
    wGB = 4.0
    GBenergy = 0.708
    GBMobility = 2.5e-14
    T = T                              # Unify with the temperature in both of the two material blocks
    outputs = exodus
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

[Preconditioning]
  [./SMP]
    type = SMP
    full = true
  [../]
[]

[Executioner]
  type = Transient
  nl_max_its = 15
  scheme = bdf2
  solve_type = PJFNK
  petsc_options_iname = -pc_type
  petsc_options_value = asm
  l_max_its = 15
  l_tol = 1.0e-3
  start_time = 0.0
  # num_steps = 500
  end_time = '${end_time_i}'             # end time (Jim June 3, 2026)
  # nl_abs_tol = 1e-8
  nl_abs_tol = 1.0e-10
  nl_rel_tol = 1.0e-8
  # dt = 0.20
  [TimeStepper]                          # TimeStepper (Jim June 3, 2026)
    type = IterationAdaptiveDT
    dt = '${dt_i}' # Initial time step.  In this simulation it changes.
    optimal_iterations = 6 # Time step will adapt to maintain this number of nonlinear iterations
  []
[]

[Adaptivity]                                            # Adaptivity at Grain Boundaries (Jim June 3, 2026)
  initial_steps = ${fparse mesh_adaptivity_level-1}
  max_h_level = ${mesh_adaptivity_level}
  # marker = EFM_1
  # [Markers]
  #   [EFM_1]
  #     type = ErrorFractionMarker
  #     coarsen = 0.1
  #     refine = 0.9
  #     indicator = GJI_1
  #   []
  # []
  # [Indicators]
  #   [GJI_1]
  #    type = GradientJumpIndicator
  #    variable = bnds
  #   []
  # []

  # marker = combined 
  # marker = bound_adapt # combined
  marker = errorfrac
  [Indicators]
    [error]
      type = GradientJumpIndicator
      variable = bnds
    []
  []
  [Markers]
    # [bound_adapt]
    #   type = ValueThresholdMarker
    #   third_state = DO_NOTHING
    #   coarsen = 0.999   #1.00  0.999(PC)  0.8
    #   refine = 0.95   #0.95  0.95(PC)   0.2
    #   variable = bnds
    #   invert = true
    # []
    [errorfrac]
      type = ErrorFractionMarker
      coarsen = ${coarsen_i}
      indicator = error
      refine = ${refine_i}     # 0.07 0.15 0.20
    []
    # [combined]
    #   type = ComboMarker
    #   markers = 'bound_adapt errorfrac'
    # []
  []
[]

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []
  exodus = true
  file_base = ${Folder_name}/mod${mod_num}_${input_text_file}
[]
