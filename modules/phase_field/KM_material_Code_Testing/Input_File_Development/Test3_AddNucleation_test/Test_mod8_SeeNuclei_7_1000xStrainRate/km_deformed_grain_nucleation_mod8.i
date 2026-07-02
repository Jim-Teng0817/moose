# Test 9 of plan §7: end-to-end rho_var path (km_with_deformed_grain_material.i)
# 2-grain bicrystal with constant OPs (no phase-field evolution). KocksMecking
# rho -> MaterialRealAux -> aux variable rho_grain -> DeformedGrainMaterial.rho_var.
# Acceptance: at t=dt, Def_Eng from DeformedGrainMaterial equals beta * rho_avg
# where rho_avg comes from the KocksMecking material directly.

# # adaptivity
# mesh_adaptivity_level = 3 # 2 3
# coarsen_i = 0.00  # 0.06
# refine_i = 0.20

# time
# time_scale_i = '${units 0.001 s}'    # in default, 1e-9 s = 1 ns      1   1e-9  0.001
# time_scale_i = '${units 1 s}'
time_scale_i = 1e-2         # 1e-6
dt_i = 2e-1                
# end_time_i = '${fparse 10 * (1/time_scale_i)}'    # 10
# sync_times_i = '${fparse 1800 * (1/time_scale_i)}'   # represent the 1800 s = 30 min

# length
length_scale_i = '${units 1e-8 m}'   # in default, 1e-9 m = 1 nm    1e-6   1e-9

# Initial Dislocation Input Text File
input_text_file = test_1000xRhoInitial

# Filename
Folder_name = 'Output/'
mod_num = 8

# nucleation                      # Added for Nucleation (Jim June 17, 2026)
# initial_op_num_i = 4        # original deformed grains / active initial OPs
# reserve_op_num_i = 1        # one staging OP for nuclei
# total_op_num_i = 5          # initial_op_num_i + reserve_op_num_i
initial_grain_num_i = 4       # actual initial grains
initial_ic_op_num_i = 4       # OPs used by initial Voronoi IC

# normal_op_num_i = 8           # gr0-gr7 are available for real grains
reserve_op_num_i = 1          # gr8 is staging only
total_op_num_i = 9            # normal_op_num_i + reserve_op_num_i

# first-pass nucleation tuning    # Added for Nucleation (Jim June 17, 2026)
nuc_radius_i = 6.0         # radius in mesh length units; start around one initial element  # 4.0
rho_crit_i = 5e-4           # m^-2; tune after checking rho_grain output. # 5.0e14
bnds_max_i = 0.95           # 0.95 for boundary only, 0.85 wider GB band, 0.75 moderate, 0.65 narrower, 0.55 very close to GB center
nuc_prob_i = 5.0e-4         # stochastic insertion probability/rate density   # 1.0e-4

# # set to -1.0 for first debug run so nucleation can occur anywhere.
# # later use something like 0.05-0.20 to restrict to grain boundaries using bnds.
# bnds_crit_i = 0.10          # Added for Nucleation (Jim June 17, 2026) # -1.0 

# For k_1
burger_i = 3.42e-10           # Added for Nucleation (Jim June 17, 2026) # 2004_J Rest
G_shear_i = 32.7              # Added for Nucleation (Jim June 17, 2026) # 2024_Sourabh B. Kadambi
theta_0_i = 10
M_taylor_i = 10
alpha_taylor_i = 10

[Mesh]
  type = GeneratedMesh
  dim = 2
  nx = 32             # 16
  ny = 32             # 16
  xmin = 0.0
  xmax = 64.0
  ymin = 0.0
  ymax = 64.0
  uniform_refine = 2 # Initial uniform refinement of the mesh. # 2
[]

[GlobalParams]
  # op_num = 4                    # Removed for Nucleation (Jim June 17, 2026)
  op_num = ${total_op_num_i}      # Added for Nucleation (Jim June 17, 2026)

  var_name_base = gr

  # deformed_grain_num = 4        # Removed for Nucleation (Jim June 17, 2026)
  # grain_num = 4                 # Removed for Nucleation (Jim June 17, 2026)

  # Only the original grain IDs 0-3 are deformed.
  # New grain IDs >= 4 should be recrystallized / low-rho.
  deformed_grain_num = ${initial_grain_num_i}    # Modified for Nucleation (Jim June 19, 2026)

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
    initial_condition = 1e1   # 1.0e-3  1e-1
  []
  [T]
    initial_condition = 1073.0  # 800 C ~= 1073 K
  []
  [rho_grain]
    family = MONOMIAL
    order = CONSTANT
  []
  [bnds]
    order = FIRST
    family = LAGRANGE
  []
[]

[AuxKernels]
  [rho_grain_aux]
    type = MaterialRealAux
    variable = rho_grain
    property = rho
    # execute_on = 'INITIAL TIMESTEP_END'
    execute_on = 'INITIAL TIMESTEP_BEGIN TIMESTEP_END'
  []
  [BndsCalc]
    type = BndsCalcAux
    variable = bnds
    # execute_on = timestep_end           # Removed for Nucleation (Jim June 17, 2026)
    # execute_on = 'INITIAL TIMESTEP_END'   # Added for Nucleation (Jim June 17, 2026)
    execute_on = 'INITIAL TIMESTEP_BEGIN TIMESTEP_END'
  []
[]

[Kernels]
  [PolycrystalKernel]                     # Added for DeformedGrain (Jim June 5, 2026)
  []
  [PolycrystalStoredEnergy]               # Added for DeformedGrain (Jim June 5, 2026)
    grain_tracker = grain_tracker
  []

  # # Insert nuclei into reserved OP gr4.
  # [nuc_force_gr4]                         # Added for Nucleation (Jim June 17, 2026)
  #   type = DiscreteNucleationForce
  #   variable = gr4
  #   map = nuc_map
  #   no_nucleus_value = 0
  #   nucleus_value = 1
  # []

  # [nuc_reaction_gr4]                      # Added for Nucleation (Jim June 17, 2026)
  #   type = Reaction
  #   variable = gr4
  # []

  # Insert nuclei into reserved OP gr8.
  [nuc_force_gr8]                         # Added for Nucleation (Jim June 17, 2026)
    type = DiscreteNucleationForce
    variable = gr8
    map = nuc_map
    no_nucleus_value = 0
    nucleus_value = 1
  []
  [nuc_reaction_gr8]                      # Added for Nucleation (Jim June 19, 2026)
    type = Reaction
    variable = gr8
  []
[]

[UserObjects]
  [voronoi]                               # Added for DeformedGrain (Jim June 5, 2026)
    type = PolycrystalVoronoi

    grain_num = ${initial_grain_num_i}    # Modified for Nucleation (Jim June 19, 2026)
    op_num = ${initial_ic_op_num_i}       # Modified for Nucleation (Jim June 19, 2026)

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
    # threshold = 0.05                       # 0.2
    # connecting_threshold = 0.02           # 0.08

    threshold = 0.1
    connecting_threshold = 0.05
  
    compute_var_to_feature_map = true
    flood_entity_type = elemental
    # execute_on = 'initial timestep_begin'
    # execute_on = 'INITIAL TIMESTEP_END'
    execute_on = 'INITIAL TIMESTEP_BEGIN TIMESTEP_END'
    outputs = none

    reserve_op = ${reserve_op_num_i}      # Added for Nucleation (Jim June 17, 2026)
    # reserve_op_threshold = 0.05            # 0.50           # Added for Nucleation (Jim June 17, 2026)
    reserve_op_threshold = 0.5 

    dislocation_density_reader = dislocation_density_file # To make it run (Jim June 5, 2026)
    polycrystal_ic_uo = voronoi                           # Add and deleted To make it run (Jim June 5, 2026) # Added for DeformedGrain (Jim June 5, 2026)
    tolerate_failure = true

    remap_grains = true                   # Added for Nucleation (Jim June 17, 2026)
    add_default_density_grains = true     # Added for Nucleation (Jim June 17, 2026)
    default_density = 0.0                 # Added for Nucleation (Jim June 17, 2026)
  []

  [nuc_inserter]                          # Added for Nucleation (Jim June 17, 2026)
    type = DiscreteNucleationInserter
    probability = P_nuc
    radius = ${nuc_radius_i}              # initial radius of the nucli
    hold_time = 0
    # time_dependent_statistics = false
    time_dependent_statistics = true
    seed = 12345
    execute_on = TIMESTEP_END
  []

  [nuc_map]                               # Added for Nucleation (Jim June 17, 2026)
    type = DiscreteNucleationMap
    inserter = nuc_inserter
    periodic = gr8                        # Modified for Nucleation (Jim June 19, 2026)  # gr4
    int_width = 2.0
    execute_on = TIMESTEP_BEGIN
  []
[]

[ICs]                                      # Add and deleted To make it run (Jim June 5, 2026)
  [PolycrystalICs]                         # Added for DeformedGrain (Jim June 5, 2026)
    [PolycrystalColoringIC]
      polycrystal_ic_uo = voronoi
      op_num = ${initial_ic_op_num_i}      # Added for Nucleation (Jim June 17, 2026)
      var_name_base = gr                   # Added for Nucleation (Jim June 17, 2026)
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
    k1_name = k1
    # mu = 4.2e10
    # b = 2.56e-10
    # L_obs = 1.0e-6
    k20 = 10.0
    Q_dyn = 0.5
    Q_units = eV
    n_exp = 5.0
    gdot_ref = 1.0
    # rho_init = 1.0e12
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

  [nucleation_probability]             # Added for Nucleation (Jim June 17, 2026)
    type = ParsedMaterial
    property_name = P_nuc
    coupled_variables = 'rho_grain bnds'
    constant_names = 'rho_crit bnds_max P0'
    constant_expressions = '${rho_crit_i} ${bnds_max_i} ${nuc_prob_i}'

    # Kocks-Mecking rho criterion:
    # Nucleate where rho_grain > rho_crit.
    # bnds = sum_i eta_i^2
    # grain interior: bnds ~ 1, so 1-bnds ~ 0
    # grain boundary: bnds < 1, so 1-bnds > 0
    expression = 'if(rho_grain > rho_crit, if(bnds < bnds_max, P0, 0), 0)'

    outputs = exodus
  []

  [k1]
    type = ParsedMaterial
    property_name = k1
    # coupled_variables = 'rho_grain bnds'
    constant_names = 'b G theta_0 M_taylor alpha_taylor'
    constant_expressions = '${burger_i} ${G_shear_i} ${theta_0_i} ${M_taylor_i} ${alpha_taylor_i}'
    expression = '2 * theta_0 / (M_taylor * alpha_taylor * G * b)'
    block = 0
    outputs = exodus
  []

  # [nucleation]                         # Added for Nucleation (Jim June 18, 2026)
  #   type = DiscreteNucleation
  #   op_names  = gr4
  #   op_values = 1
  #   map = nuc_map
  #   outputs = exodus
  # []
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

  [nuc_count]                         # Added for Nucleation (Jim June 17, 2026)
    type = DiscreteNucleationData
    inserter = nuc_inserter
    value = COUNT
  []
  [nuc_rate]                          # Added for Nucleation (Jim June 17, 2026)
    type = DiscreteNucleationData
    inserter = nuc_inserter
    value = RATE
  []
  [dtnuc]                             # Added for Nucleation (Jim June 17, 2026)
    type = DiscreteNucleationTimeStep
    inserter = nuc_inserter
    p2nucleus = 0.001
    dt_max = ${dt_i}
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
  num_steps = 450
  # end_time = '${end_time_i}'             # end time (Jim June 3, 2026)
  # nl_abs_tol = 1e-8
  nl_abs_tol = 1.0e-10
  nl_rel_tol = 1.0e-8
  # dt = 0.20
  [TimeStepper]                          # TimeStepper (Jim June 3, 2026)
    type = IterationAdaptiveDT
    dt = '${dt_i}' # Initial time step.  In this simulation it changes.
    optimal_iterations = 6 # Time step will adapt to maintain this number of nonlinear iterations
    timestep_limiting_postprocessor = dtnuc # Added for Nucleation (Jim June 17, 2026)
  []
[]

# [Adaptivity]                                            # Adaptivity at Grain Boundaries (Jim June 3, 2026)
#   initial_steps = ${fparse mesh_adaptivity_level-1}

#   initial_marker = errorfrac

#   max_h_level = ${mesh_adaptivity_level}

#   # # Do not adapt every step during debugging
#   # interval = 50

#   marker = combined
#   # marker = errorfrac # combined
#   cycles_per_step = 1
#   recompute_markers_during_cycles = true

#   [Indicators]
#     [error]
#       type = GradientJumpIndicator
#       variable = bnds
#     []
#   []

#   [Markers]
#     [errorfrac]
#       type = ErrorFractionMarker
#       # coarsen = ${coarsen_i}
#       indicator = error
#       refine = ${refine_i}
#     []

#     [nuc_refine]
#       type = DiscreteNucleationMarker
#       map = nuc_map
#     []

#     [combined]
#       type = ComboMarker
#       markers = 'errorfrac nuc_refine'
#     []
#   []
# []

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []
  exodus = true
  file_base = ${Folder_name}/mod${mod_num}_${input_text_file}
[]
