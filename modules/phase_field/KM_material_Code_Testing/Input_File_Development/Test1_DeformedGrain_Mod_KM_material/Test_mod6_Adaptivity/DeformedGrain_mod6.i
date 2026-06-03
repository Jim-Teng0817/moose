# This example tests the implementation of PolycrstalStoredEnergy kernels that assigns excess stored energy to grains with dislocation density

# adaptivity
mesh_adaptivity_level = 3 # 2 3
coarsen_i = 0.06
refine_i = 0.20


[Mesh]
  type = GeneratedMesh
  dim = 2
  nx = 32
  ny = 32
  nz = 0
  xmin = 0
  xmax = 64
  ymin = 0
  ymax = 64
[]

[GlobalParams]
  op_num = 2                        # 4 -> 2
  deformed_grain_num = 2            # 4 -> 2
  var_name_base = gr
  grain_num = 2                     # 4 -> 2
  grain_tracker = grain_tracker
  time_scale = 1e-2
  length_scale = 1e-8
[]

[Variables]
  [./PolycrystalVariables]
  [../]
[]

[AuxVariables]
  [./bnds]
    order = FIRST
    family = LAGRANGE
  [../]
[]

[UserObjects]
  [./voronoi]
    type = PolycrystalVoronoi
    rand_seed = 81
    coloring_algorithm = bt
  [../]
  [./dislocation_density_file]
    type = DislocationDensityFileReader
    file_name = test.txt
    lines_to_skip = 0
  [../]
  [./grain_tracker]
    # GrainTrackerDislocations is required by DeformedGrainMaterial to supply
    # per-grain dislocation data via getData().
    type = GrainTrackerDislocations
    threshold = 0.2
    connecting_threshold = 0.08
    compute_var_to_feature_map = true
    flood_entity_type = elemental
    execute_on = 'initial timestep_begin'
    outputs = none
    dislocation_density_reader = dislocation_density_file
    polycrystal_ic_uo = voronoi
    tolerate_failure = true
  [../]
[]

[ICs]
  [./PolycrystalICs]
    [./PolycrystalColoringIC]
      polycrystal_ic_uo = voronoi
    [../]
  [../]
[]

[BCs]
  # [./Periodic]                  # Removed for zero flux on the boundaries of the block
  #   [./all]
  #     auto_direction = 'x y'
  #   [../]
  # [../]
  # [./bcs]                       # Don't need this
  #   #zero flux BC
  #   type = NeumannBC
  #   value = 0
  #   variable = gr0
  #   boundary = '0 1 2 3'
  # [../]
[]

[Kernels]
  [./PolycrystalKernel]
  [../]
  [./PolycrystalStoredEnergy]
  [../]
[]

[AuxKernels]
  [./BndsCalc]
    type = BndsCalcAux
    variable = bnds
    execute_on = timestep_end
  [../]
[]

[Materials]
  [./deformed]
    type = DeformedGrainMaterial
    wGB = 4.0
    GBenergy = 0.708
    GBMobility = 2.5e-14
    T = 300
    output_properties = 'beta disloc_den_i rho_eff deformation_energy'
    outputs = exodus
  [../]
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
  nl_rel_tol = 1.0e-8
  start_time = 0.0
  num_steps = 500
  nl_abs_tol = 1e-8
  dt = 0.20
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
  exodus = true
  time_step_interval = 1
  show = bnds
  perf_graph = true
[]
