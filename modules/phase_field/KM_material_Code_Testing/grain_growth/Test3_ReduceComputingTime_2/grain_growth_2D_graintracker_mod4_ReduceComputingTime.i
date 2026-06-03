# This simulation predicts GB migration of a 2D copper polycrystal with 100 grains represented with 8 order parameters
# Mesh adaptivity and time step adaptivity are used
# An AuxVariable is used to calculate the grain boundary locations
# Postprocessors are used to record time step and the number of grains

# grain growth parameters
temperature = ${units 1773 K}          # Temperature (in K)                    
wGB_i = 5                                # 0.05 200 5 Width of the diffuse GB (in length scale)
# L_0_i = '${units 8.33e-6 m^3/(J*s)}'   # Mobility Pre-factor (in m^3 / (Js))
# Q_i = '${units 0.6 eV}'                # Grain boundary migration activation energy (in eV)
# k_b = '${units 8.617333262e-5 eV/K}'   # Boltzmann constant (in 8.617333262e-5 eV/K)
# mobility_prefactor = '${units 2.5e-6 mum^4/J/s}'
# GB_energy = '${units 0.7 J/mum^2}'
# activation_energy = '${units 0.23 eV}'
# temperature = '${units 700 K}'
# width_diffuse_GB = '${units ${fparse 1.9/5} mum}' # Width of the diffuse GB, should be x times smaller than the smallest grain

# expression = 'L_0_i * exp(-Q_i / (k_b * T)) * ((3/4) * (wGB_i))'

# Mobility Calculation
# M_GB = '${units ${fparse L_0_i * exp(-Q_i / (k_b * temperature)) * ((3/4) * (wGB_i))} m^4/(J*s)}'
K_m = 1.8e2                                     # GB mobility parameter.  # For reducing the computing time (1.8e4 -> 1.8e2) (Jim June 01, 2026)
GB_width = '${units 1e-9  m}'                   # GB width (in m)
V_atom = '${units 1.582493e-29   m^3/at}'       # Atomic volume (in m^3/atom)
b = '${units 2.74114e-10  m}'                   # Magnitude of Burgers Vector (in m)
k_B_i = '${units 1.380649e-23 J/(K*at)}'          # Gas constant (in J/K)
D_GB_0 = '${units 2.7e-5 m^2/s}'                # Self-diffusivity along GB (in m^2/s)
Q_GB_i = '${units 4e5 J/mol}'                   # Activation energy for GB mobility (in J/mol)
R_i = '${units 8.31446261815324 J/(K*mol)}'   # Boltzmann constant (in J/(K*mol))
# e = '${units 1.602176487e-19 1/J}'              # the magnitude of the elementary charge
M_GB_i = '${units ${fparse K_m * ((GB_width * V_atom)/(b^2 * k_B_i * temperature)) * D_GB_0 * exp(-Q_GB_i / (R_i * temperature))} m^4/(J*s)}'


# time
# time_scale_i = '${units 0.001 s}'    # in default, 1e-9 s = 1 ns      1   1e-9  0.001
# time_scale_i = '${units 1 s}'
time_scale_i = 1e-4         # 1e-6
dt_i = 1e1                 # 1e-2                     # For reducing the computing time (1e-5 -> 1e1) (Jim June 01, 2026)
end_time_i = '${fparse 0.072 * (1/time_scale_i)}'       # For reducing the computing time (7200 -> 0.072) (Jim June 01, 2026)
# sync_times_i = '${fparse 1800 * (1/time_scale_i)}'   # represent the 1800 s = 30 min

# length
length_scale_i = '${units 1e-8 m}'   # in default, 1e-9 m = 1 nm    1e-6   1e-9

# energy
# energy_scale_i = 0.01   # 1 0.1 10. used to scale GBEnergy value
energy_scale_i = 1 
GBEnergy_i = 9.3295
# L_0_i_scaled = '${fparse L_0_i / energy_scale_i}'
GBEnergy_scaled = '${fparse GBEnergy_i * energy_scale_i}'

Folder_name = 'New_MGB_realDim/3_test_length_scale1e-6'           
# SmallerModel4grains  LargerModel36grains   
# Debug/Convergence_10_Executioner_and_coarsen0.06refine0.20   
# LargerModel36grains/max_h_level3/623K_200hours 
# SmallerModel4grains/New_Voronoi_seed/Seed5

# adaptivity
mesh_adaptivity_level = 3 # 2 3
coarsen_i = 0.06
refine_i = 0.20

[Mesh]
  # Mesh block.  Meshes can be read in or automatically generated
  type = GeneratedMesh
  dim = 2 # Problem dimension
  nx = 44 # 220 44   Number of elements in the x-direction. # For reducing the computing time (88 -> 44) (Jim June 01, 2026)
  ny = 44 # 220 44   Number of elements in the y-direction  # For reducing the computing time (88 -> 44) (Jim June 01, 2026)
  xmax = 500 # 10000 11650 550   55e-6 m = 55000 nm = 550e-7   # 1000 # maximum x-coordinate of the mesh # For reducing the computing time (1000 -> 500) (Jim June 01, 2026)
  ymax = 500 # 10000 11650 550   55e-6 m = 55000 nm = 550e-7   # 1000 # maximum y-coordinate of the mesh # For reducing the computing time (1000 -> 500) (Jim June 01, 2026)
  elem_type = QUAD4 # Type of elements used in the mesh
  uniform_refine = 2 # Initial uniform refinement of the mesh. # 2
[]

[GlobalParams]
  # Parameters used by several kernels that are defined globally to simplify input file
  op_num = 8         # 8 # Number of order parameters used
  var_name_base = gr # Base name of grains
[]

[Modules]
  [PhaseField]
    [GrainGrowth]
    []
  []
[]

[UserObjects]
  [voronoi]
    type = PolycrystalVoronoi
    grain_num = 36    # 36  4  100 # Number of grains
    rand_seed = 10    # 10  2
    int_width = 7
  []
  [grain_tracker]
    type = GrainTracker
    compute_var_to_feature_map = true       # added for postprocessor (Jim 20250512)
  []
  # [grain_tracker]
  #   type = GrainTracker
  #   threshold = 0.2
  #   verbosity_level = 1
  #   connecting_threshold = 0.08
  #   compute_var_to_feature_map = true
  #   compute_halo_maps = true # For displaying HALO fields
  #   polycrystal_ic_uo = voronoi
  #   execute_on = 'initial timestep_end'
  # []
[]

[ICs]
  [PolycrystalICs]
    [PolycrystalColoringIC]
      polycrystal_ic_uo = voronoi
    []
  []
[]

[AuxVariables]
  # Dependent variables
  [unique_grains]
    order = CONSTANT
    family = MONOMIAL
  []
  [var_indices]
    order = CONSTANT
    family = MONOMIAL
  []
[]

[AuxKernels]
  # AuxKernel block, defining the equations used to calculate the auxvars
  [bnds_aux]
    # AuxKernel that calculates the GB term
    type = BndsCalcAux
    variable = bnds
    execute_on = 'initial timestep_end'
  []
  [unique_grains]
    type = FeatureFloodCountAux
    variable = unique_grains
    flood_counter = grain_tracker
    field_display = UNIQUE_REGION
    execute_on = 'initial timestep_end'
  []
  [var_indices]
    type = FeatureFloodCountAux
    variable = var_indices
    flood_counter = grain_tracker
    field_display = VARIABLE_COLORING
    execute_on = 'initial timestep_end'
  []
[]

[BCs]
  # Boundary Condition block
  [Periodic]
    [All]
      auto_direction = 'x y' # Makes problem periodic in the x and y directions
    []
  []
[]

[Materials]
  [Tungsten]
    # Material properties
    type = GBEvolution
    T = '${temperature}'      # 1000, 1500 K # 450 K # Constant temperature of the simulation (for mobility calculation)
    wGB = '${wGB_i}'                                 # 14 # Width of the diffuse GB # 0.5 nm = 0.005e-7 m
    GBenergy = '${GBEnergy_scaled}'                        # 0.708 #J/m^2 from schonfelder1997molecular bibtex entry
    GBMobility = '${M_GB_i}'
    # GBmob0 = '${L_0_i_scaled}'                         # 2.5e-6 #m^4 / (Js) for copper from schonfelder1997molecular bibtex entry
    # Q = '${Q_i}'                                # 0.23 #eV for copper from schonfelder1997molecular bibtex entry
    length_scale = '${length_scale_i}'     # 1e-09           # To meet the meshing scale (Jim 20250520)
    molar_volume = 9.55e-06
    time_scale = '${time_scale_i}'         # 1e-09
    outputs = exodus
  []

  # [Tungsten]
  #   # Material properties
  #   type = GBEvolution
  #   T = '${temperature}'      # 1000, 1500 K # 450 K # Constant temperature of the simulation (for mobility calculation)
  #   wGB = 5                                 # 14 # Width of the diffuse GB # 0.5 nm = 0.005e-7 m
  #   GBMobility = '${M_GB}'
  #   # GBmob0 = 2.5e-6                          # 2.5e-6 #m^4 / (Js) for copper from schonfelder1997molecular bibtex entry
  #   # Q = 0.23                                 # 0.23 #eV for copper from schonfelder1997molecular bibtex entry
  #   GBenergy = 9.3295                         # 0.708 #J/m^2 from schonfelder1997molecular bibtex entry
  #   # length_scale = 1e-07   # 1e-09 
  #   length_scale = '${length_scale_i}'           # To meet the meshing scale (Jim 20250520)
  #   molar_volume = 9.55e-06
  #   time_scale = '${time_scale_i}'         # 1e-09
  #   outputs = exodus
  # []
  # [L_GB]
  #   type = ParsedMaterial
  #   T = 450                           # Temperature (in K)
  #   wGB_i = 5                         # Width of the diffuse GB (in length scale)
  #   L_0_i = 8.33e-6                   # Mobility Pre-factor (in m^3 / (Js))
  #   Q_i = 0.6                         # Grain boundary migration activation energy in eV
  #   k_b = 8.617333262e-5              # Boltzmann constant
  #   expression = 'L_0_i * exp(-Q_i / (k_b * T)) * ((3/4) * (wGB_i))'
  # []
  # [CuGrGr]
  #   # Material properties
  #   type = GBEvolution
  #   T = 450 # Constant temperature of the simulation (for mobility calculation)
  #   wGB = 14 # Width of the diffuse GB
  #   GBmob0 = 2.5e-6 #m^4(Js) for copper from schonfelder1997molecular bibtex entry
  #   Q = 0.23 #eV for copper from schonfelder1997molecular bibtex entry
  #   GBenergy = 0.708 #J/m^2 from schonfelder1997molecular bibtex entry
  # []
[]

[Postprocessors]
  # Scalar postprocessors
  [dt]
    # Outputs the current time step
    type = TimestepSize
  []
  [avg_grain_volumes]
    type = AverageGrainVolume
    feature_counter = grain_tracker
    execute_on = 'initial timestep_end'
    # outputs = 'csv'                          # Added to not output every time step  (Jim 20250513)
  []

  # [./feature_counter]                        # Added for individual volume (Jim 20250513)
  #   type = FeatureFloodCount
  #   variable = gr0                           # gr0, gr1, gr2, gr3, gr4, gr5, gr6
  #   compute_var_to_feature_map = true
  #   execute_on = 'initial timestep_end'
  # [../]
  # [./Volume]                                 # Added for individual volume (Jim 20250513)
  #   type = VolumePostprocessor
  #   execute_on = 'initial'
  # [../]
  # [./volume_fraction]                        # Added for individual volume (Jim 20250513)
  #   type = FeatureVolumeFraction
  #   mesh_volume = Volume
  #   feature_volumes = feature_volumes
  #   execute_on = 'initial timestep_end'
  # [../]
[]

[VectorPostprocessors]                       # Added for individual volume (Jim 20250513)
  [./feature_volumes]
    type = FeatureVolumeVectorPostprocessor
    flood_counter = grain_tracker
    execute_on = 'initial timestep_end'
    # outputs = 'csv_all'
    outputs = 'vector_postproc'            # Added to not output every time step  (Jim 20250513)
  [../]
[]

[Executioner]
  type = Transient # Type of executioner, here it is transient with an adaptive time step
  scheme = bdf2 # Type of time integration (2nd order backward euler), defaults to 1st order backward euler

  #Preconditioned JFNK (default)
  solve_type = 'PJFNK'

  # Uses newton iteration to solve the problem.
  petsc_options_iname = '-pc_type -pc_hypre_type'
  petsc_options_value = 'hypre boomeramg'

  l_max_its = 20 # Max number of linear iterations
  l_tol = 1e-4 # Relative tolerance for linear solves
  nl_max_its = 10 # Max number of nonlinear iterations

  nl_rel_tol = 1e-8              # Relative tolerance for nonlinear solves
  nl_abs_tol = 1e-10             # Absolute tolerance for nonlinear solves

  automatic_scaling = true
  line_search = 'none'

  end_time = '${end_time_i}'          # 4000 200  (take smaller, Jim 20250512)

  [TimeStepper]
    type = IterationAdaptiveDT
    dt = '${dt_i}' # Initial time step.  In this simulation it changes.
    optimal_iterations = 6 # Time step will adapt to maintain this number of nonlinear iterations
  []

  # [Adaptivity]
  #   # Block that turns on mesh adaptivity. Note that mesh will never coarsen beyond initial mesh (before uniform refinement)
  #   initial_adaptivity = 2 # Number of times mesh is adapted to initial condition
  #   refine_fraction = 0.6 # Fraction of high error that will be refined   # no 0.8  0.2  0.5  0.7  0.65  0.55  0.6  
  #   coarsen_fraction = 0.4 # Fraction of low error that will coarsened   # no 0.05  0.8  0.5  0.3  0.35  0.45  0.4
  #   max_h_level = 2 # Max number of refinements used, starting from initial mesh (before uniform refinement)
  # []
[]

[Adaptivity]
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
  exodus = true # Exodus file will be outputted
  csv = true
  file_base = ${Folder_name}/mod3_6_${temperature}K_TimeScale${time_scale_i}_LengthScale_${length_scale_i}_wGB${wGB_i}_EnergyScale${energy_scale_i}_dt${dt_i}/grain_growth_2D_graintracker_mod3_6_${temperature}K_TimeScale${time_scale_i}_LengthScale_${length_scale_i}_wGB${wGB_i}_EnergyScale${energy_scale_i}_dt${dt_i}

  # [csv_all]                                      # Added to output every time step  (Jim 20250513)
  #   type = CSV
  #   execute_on = 'initial timestep_end'
  #   file_base = grain_growth_2D_graintracker_mod3_1
  # []
  [vector_postproc]                                      # Added to not output every time step  (Jim 20250513)
    type = CSV
    time_step_interval = 10
    file_base = ${Folder_name}/mod3_6_${temperature}K_TimeScale${time_scale_i}_LengthScale_${length_scale_i}_wGB${wGB_i}_EnergyScale${energy_scale_i}_dt${dt_i}/grain_growth_2D_graintracker_mod3_6_${temperature}K_TimeScale${time_scale_i}_LengthScale_${length_scale_i}_wGB${wGB_i}_EnergyScale${energy_scale_i}_dt${dt_i}_grainSize
  []
  # [vector_postproc_3]                       # Added to not output every time step  (Jim 20250513)
  #   type = CSV
  #   time_step_interval = 3
  #   file_base = grain_growth_2D_graintracker_mod3_grainSize_1
  # []
  # [vector_postproc]                          # Added to not output every time step  (Jim 20250513)
  #   type = CSV
  #   sync_times = '${fparse 0 * ${sync_times_i}} ${sync_times_i} ${fparse 2 * ${sync_times_i}} ${fparse 3 * ${sync_times_i}} ${fparse 4 * ${sync_times_i}}'                   # The time is not time step  (Jim 20250513)
  #   sync_only = true
  #   # file_base = grain_growth_2D_graintracker_mod3_grainSize_1
  #   file_base = ${Folder_name}/mod3_6_${temperature}K_TimeScale${time_scale_i}_LengthScale_${length_scale_i}_wGB${wGB_i}_EnergyScale${energy_scale_i}_dt${dt_i}/grain_growth_2D_graintracker_mod3_6_${temperature}K_TimeScale${time_scale_i}_LengthScale_${length_scale_i}_wGB${wGB_i}_EnergyScale${energy_scale_i}_dt${dt_i}_grainSize
  # []
[]

[Debug]
  show_var_residual_norms = true
[]