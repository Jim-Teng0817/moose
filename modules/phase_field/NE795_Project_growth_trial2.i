# Diffusionless particle growth due to undercooling (solidification) or strain energy (recrystallization)

# # kappa is the gradient coefficient
# kappa = 1.0
# # A is the constant in the double well bulk_free_energy (it controls the height of the well (A/16))
# A = 1.0
# # surface energy = 0.2357 (see the analytical derivation of the surface energy in terms of the model parameters)
# # surface energy = sqrt(Kappa*A)/(3*sqrt(2))

# # B is the constant in the bulk_free_energy that defines the difference in the free energy of the phases (F (eta=1) - F(eta=0)= -B)
# # The driving force for grwoth (it tilts the double well, making one phase more stable than the other)
# B = 0.1
# # Here we use moose built-in Allen-Cahn kernels from the phase-field module
# # this is the "traditional" way of implementing a phase-field model A
n_elem = 85 # Number of Elements    64
X = 255 # the Domain/Bar length     128       [mm = 1e3 mu-m]
# # x_c = ${fparse X/2} # particle center (X/2.0)
# # r = 25 # initial particle's radius
# L = 1.0 # Alen-Cahn mobility

# T0=300.0 # ambient temperature T0 = 300 [K]

[Mesh]
  type = GeneratedMesh
  dim = 2
  nx = '${n_elem}'
  ny = '${n_elem}'
  nz = 0
  xmin = '0'
  xmax = '${X}'
  ymin = '0'
  ymax = '${X}'
  elem_type = QUAD4
[]  # Mesh


[GlobalParams]
  # Parameters used by several kernels that are defined globally to simplify input file
  op_num = 8 # Number of order parameters used      (Recommended: 2D->8, 3D->25)
  grain_num = 15  # Number of grains
  var_name_base = gr # Base name of grains
  int_width = 10
[]  # GlobalParams


[Modules]
  [PhaseField]
    [GrainGrowth]
      family = LAGRANGE
      order = FIRST
      # use_automatic_differentiation = true
      # L_liq = 1.9e-9          # latent heat value
      # T_liq = 1700.0         # liquidus temperature in K
    []
  []
[]  # Modules


[UserObjects]
  [./voronoi]
    type = PolycrystalVoronoi
    rand_seed = 10
    use_kdtree = true
    point_patch_size = 1
    grain_patch_size = 10
  [../]
  [./grain_tracker]
    type = GrainTracker
  [../]
[]  # UserObjects


[ICs]
  # [./eta]
  #   variable = 'eta'
  #   type = PolycrystalColoringIC
  #   polycrystal_ic_uo = voronoi
  #   grain_tracker = grain_tracker
  # [../]
  [./PolycrystalICs]
    [./PolycrystalColoringIC]
      polycrystal_ic_uo = voronoi
    [../]
  [../]
  [./bnds]
      type = BndsCalcIC
      variable = bnds
  [../]
[]  # ICs


[Variables]
  # [./eta]
  #   order = FIRST
  #   family =  LAGRANGE
  # [../]
  # [./temp]
  #   family = LAGRANGE
  #   order = FIRST
  #   initial_condition = 300.0  # Initial temperature, adjust as needed
  # [../]
  [./PolycrystalVariables]
  [../]
  # [./eta_liq]
  # [../]
[]  # Variables


[AuxVariables]
  # [./total_free_energy] # AuxVariable To store the total_free_energy density at each point.
  #   order = CONSTANT
  #   family = MONOMIAL
  # [../]

  
  # Dependent variables
  [./bnds]
    # Variable used to visualize the grain boundaries in the simulation
    order = FIRST
    family = LAGRANGE
  [../]
  [./unique_grains]
    order = CONSTANT
    family = MONOMIAL
  [../]
  [./var_indices]
    order = CONSTANT
    family = MONOMIAL
  [../]
  [./temp]
    order = FIRST
    family = LAGRANGE
  [../]
[]  # AuxVariables


[AuxKernels]
  # [./total_free_energy] # Aux Kernel To calculate the total_free_energy density at each point.
  #   type = TotalFreeEnergy
  #   variable = total_free_energy
  #   kappa_names = kappa
  #   interfacial_vars = eta
  #   f_name = F
  #   execute_on = 'INITIAL TIMESTEP_END'
  # [../]
  
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

  [./rosenthal_temperature]
    type = FunctionAux
    variable = temp
    function = rosenthal_temp
  [../]
[]  # AuxKernels


[BCs] # periodic BC in both directions.
  [./Periodic]
    [./all]
      auto_direction = 'x y'     # Makes problem periodic in the x and y directions
    [../]
  [../]

  # [./temperature_bc]
  #   type = DirichletBC
  #   variable = T
  #   boundary = 'left right top bottom'
  #   value = 300
  # [../]
  
  # [./Periodic]
  #   [./all]
  #     auto_direction = 'x y'
  #     variable = 'eta'
  #   [../]
  # [../]
[]  # BCs


# [Kernels]
#   [./AC_bulk]
#     type = AllenCahn
#     variable = 'eta'
#     f_name = F
#     mob_name = mobility
#   [../]
#   [./AC_int]
#     type = ACInterface
#     variable = 'eta'
#     kappa_name = kappa
#     mob_name = mobility
#   [../]
#   [./eta_dot]
#     type = TimeDerivative
#     variable = 'eta'
#   [../]
# []  # Kernels


[Functions]
  [./rosenthal_temp]
    type = ParsedFunction
    expression = 'T0 + (Q / (2 * pi * kappa_T)) * (1 / sqrt((x - x0 - v * t)^2 + y^2)) * exp(-v * (sqrt((x - x0 - v * t)^2 + y^2) + (x -x0 - v * t)) / (2 * alpha))'
    #Assume the heat source is on the top surface and move along x direction
    # args = 'x y t'
    symbol_names = ' T0  Q  kappa_T  v     alpha  x0'
    symbol_values = '600 25 2.75e-5  1e6   5.2e6  1'
    # params = 'T0=300 Q=25 kappa_T=2.75e-5 v=1e3 alpha=5.2e6 x0=1'
    # As given, ambient temperature T0 = 300 [K], location of heat source @ t=0 x0 =117 [mu-m] = 1 [length]
    # absorbed power from heat source Q = 25 [W], thermal conductivity kappa_T = 2.75e-5 [W*(mu-m)*K],
    # Thermal diffusivity alpha = 5.2e6 [(mu-m)^2/s] (kappa_T/(rho*c_p)​), pulling velocity of heat source v = 1e3 [(mm)/s] = 1e6 [(mu-m)/s]
  [../]
[]  # Functions


[Materials]
  # [./Bulk_Free_Eng]
  #   type = DerivativeParsedMaterial
  #   coupled_variables ='eta T'
  #   expression = ${A}*(eta^2*(1.0-eta)^2)+${B}*T*(2.0*eta^3-3.0*eta^2)
  #   derivative_order = 2
  #   property_name = F
  # [../]
  # [./const] # names and values of Allen-Cahn gradient coefficient and mobility
  #   type = GenericConstantMaterial
  #   prop_names = 'kappa mobility'
  #   prop_values = '${kappa} ${L}'
  # [../]
  
  # [./Bulk_Free_Eng]
  #   type = DerivativeParsedMaterial
  #   coupled_variables ='eta T'
  #   expression = ${A}*(eta^2*(1.0-eta)^2)+${B}*T*(2.0*eta^3-3.0*eta^2)
  #   derivative_order = 2
  #   property_name = F
  # [../]

  [./CuGrGr]
    # Material properties
    type = GBEvolution
    T = temp
    wGB = 14 # Width of the diffuse GB
    GBmob0 = 2.5e-6 #m^4(Js) for copper from schonfelder1997molecular bibtex entry
    Q = 0.23 #eV for copper from schonfelder1997molecular bibtex entry
    GBenergy = 0.708 #J/m^2 from schonfelder1997molecular bibtex entry
  [../]
  # [./TemperatureDependentMaterial]
  #   type = DerivativeParsedMaterial
  #   coupled_variables = 'T'
  #   # params = 'A=1.0'
  #   expression = 'T'
  #   # expression = 'A * T * (1 - T)'
  #   derivative_order = 2
  #   property_name = free_energy
  # [../]
[]  # Materials

[Postprocessors]
  # [./area] # eta=1 inside the particle and zero outside
  # # so its integration will give the particle area (volume in 3D)
  #   type = ElementIntegralVariablePostprocessor
  #   variable = 'eta'
  #   execute_on = 'INITIAL TIMESTEP_END'
  # [../]
  # [./radius]
  #   type = ParsedPostprocessor
  #   pp_names = 'area' # name of ther post_processor(s) to get data from
  #   function = 'sqrt(area/3.14)'   # Area = pi*R^2
  #   execute_on = 'INITIAL TIMESTEP_END'
  # [../]
  # [./total_free_energy]
  #   type = ElementIntegralVariablePostprocessor
  #   variable = total_free_energy
  #   execute_on = 'INITIAL TIMESTEP_END'
  # [../]
  # [./num_dofs]# total number of degress of freedom (unknowns)
  #   type = NumDOFs
  #   system = ALL
  #   execute_on = 'INITIAL TIMESTEP_END'
  # [../]
  
  # [unique_grains_count]
  #   type = FeatureFloodCountAux
  #   variable = unique_grains
  #   flood_counter = grain_tracker
  #   execute_on = 'initial timestep_end'
  # [../]
  # [grain_data]
  #   type = FeatureFloodData
  #   flood_counter = grain_tracker
  #   execute_on = 'initial timestep_end'
  # [../]
  [dt]
    # Outputs the current time step
    type = TimestepSize
  []
  # [./free_energy_avg]
  #   type = ElementAverageValue
  #   property = free_energy
  # [../] 
[]  # Postprocessors

[Executioner]
  type = Transient                  # Type of executioner, here it is transient with an adaptive time step
  scheme = bdf2                     # Type of time integration (2nd order backward euler), defaults to 1st order backward euler

  solve_type = PJFNK              # Preconditioned JFNK (default) or NEWTON solver

  # petsc_options_iname = '-pc_type'  # Uses newton iteration to solve the problem.
  # petsc_options_value = 'asm'
  petsc_options_iname = '-pc_type -pc_hypre_type'
  petsc_options_value = 'hypre boomeramg'      

  l_max_its = 15                    # Max number of linear iterations
  l_tol = 1.0e-3                    # Relative tolerance for linear solves
  nl_max_its = 15                   # Max number of nonlinear iterations
  nl_rel_tol = 1.0e-6
  start_time = 0.0
  num_steps = 35
  nl_abs_tol = 1e-9
  [./TimeStepper] # Time Adaptivity
    type = IterationAdaptiveDT
    dt = 1.0                        # Initial time step.  In this simulation it changes.
    growth_factor = 1.2
    cutback_factor = 0.75
    optimal_iterations = 7          # Time step will adapt to maintain this number of nonlinear iterations
  [../]
  [./Adaptivity] # Mesh Adaptivity
    # Block that turns on mesh adaptivity. Note that mesh will never coarsen beyond initial mesh (before uniform refinement)
    refine_fraction = 0.7           # Fraction of high error that will be refined
    coarsen_fraction = 0.01         # Fraction of low error that will coarsened
    max_h_level = 2                 # Max number of refinements used, starting from initial mesh (before uniform refinement)
    initial_adaptivity = 2          # Number of times mesh is adapted to initial condition
  [../]
[]  # Executioner

[Outputs]
  file_base = /home/tsu-chun/projects_moose/moose/modules/phase_field/NE795_Project_growth_trial2/test2
  exodus = true
  csv = true
  # interval = 1
[]  # Outputs
