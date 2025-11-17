# For Ti-6Al-4V (Ti64)

period = 600e-6 # Period of the laser motion  # 1.25e-3  5.00e-1 10.6e-1  Dwell time = 160 mus, simulation time = 320 mus   800e-6
endtime = ${period} # Total simulation time (Simulation end time)
timestep = 10e-6 # Time step size  # 1.25e-5 10e-6
# surfacetemp = 300 # Surface temperature in K
sb = 5.67e-8  # Stefan-Boltzmann constant (in kg s^-3 K^-4)
# Power = 600.00   # Laser Power in W  159.96989792079225
# EBeam_Absorption_Efficiency = 0.9  # EBeam Absorption Coefficient (Assumed 90%)


[Mesh]
  [gen] 
    type = GeneratedMeshGenerator
    dim = 3
    xmin = 0e-3
    xmax = 1.0e-3 # 1.5e-3  5.0e-3  10.0e-3
    ymin = 0e-3
    ymax = 1.0e-3 # 0.5e-3   1.5e-3  9.0e-3
    zmin = 0e-3
    zmax = 5.0e-4 # 0.5e-3   1.5e-3  4.5e-3 
    nx = 10  # 2
    ny = 10 # 6
    nz = 5  # 2
  []
  # displacements = 'disp_x disp_y disp_z'
  uniform_refine = 2
[]

[Problem]
  # type = FEProblem
  error_on_jacobian_nonzero_reallocation = false
[]

[Variables] # primary variables for temperature and mesh displacements
  [T]
  []
  # [disp_x]
  # []
  # [disp_y]
  # []
  # [disp_z]
  # []
[]

[AuxVariables]  # aux variables for velocity and pressure
  # [vel] 
  #   family = LAGRANGE_VEC
  # []
  # [p]
  # []
  [temperature_dt]
    family = MONOMIAL
    order = CONSTANT
  []
[]


[AuxKernels]
  [T_derivative]
    type = TimeDerivativeAux
    variable = temperature_dt
    functor = T
    factor = 1
    execute_on = 'TIMESTEP_END'
  []
[]

[ICs]
  [T]
    type = FunctionIC
    variable = T
    function = '773'   # '(${surfacetemp} - 300) / .7e-3 * z + ${surfacetemp}'
  []
[]

# [Materials]   # material for diffusivity used in mesh displacement kernels (not sure yet)
#   [Dc]   
#     type = GenericConstantMaterial
#     prop_names = Du
#     prop_values = '1'
#   []
# []

[Kernels]
  # [disp_x]
  #   type = MatDiffusion
  #   variable = disp_x
  #   diffusivity = Du   # use a material property for diffusivity (not sure yet)
  # []
  # [disp_y]
  #   type = MatDiffusion
  #   variable = disp_y
  #   diffusivity = Du
  # []
  # [disp_z]
  #   type = MatDiffusion
  #   variable = disp_z
  #   diffusivity = Du
  # []
  # [temperature_time]  # kernel for time derivative of temperature
  #   type = INSADHeatConductionTimeDerivative
  #   variable = T
  #   use_displaced_mesh = true
  # []
  # [temperature_advection]  # kernel for advection due to fluid velocity (not sure yet)
  #   type = INSADEnergyAdvection
  #   variable = T
  #   use_displaced_mesh = true
  # []
  # [temperature_mesh_advection]  # kernel for advection due to mesh motion
  #   type = INSADEnergyMeshAdvection
  #   variable = T
  #   disp_x = disp_x
  #   disp_y = disp_y
  #   disp_z = disp_z
  #   use_displaced_mesh = true
  # []
  [temperature_conduction]  # kernel for heat conduction
    type = ADHeatConduction
    variable = T
    thermal_conductivity = thermal_conductivity
    use_displaced_mesh = true
  []

  [time]
    type = ADHeatConductionTimeDerivative
    variable = T
  []
[]

[BCs]
  # [x_no_disp]  # boundary condition to fix displacement in x direction at the back (z=0) boundary
  #   type = DirichletBC
  #   variable = disp_x
  #   boundary = 'back' # In 3D (By Paraview), back (lower z) = 0, bottom (lower y) = 1, right (higher x) = 2, top (higher y) = 3, left (lower x) = 4, front (higher z) = 5
  #   value = 0
  # []
  # [y_no_disp]  # boundary condition to fix displacement in y direction at the back (z=0) boundary
  #   type = DirichletBC
  #   variable = disp_y
  #   boundary = 'back'
  #   value = 0
  # []
  # [z_no_disp]  # boundary condition to fix displacement in z direction at the back (z=0) boundary
  #   type = DirichletBC
  #   variable = disp_z
  #   boundary = 'back'
  #   value = 0
  # []
  # [T_cold]  # boundary condition to set temperature at the back (z=0) boundary
  #   type = DirichletBC
  #   variable = T
  #   boundary = 'back'
  #   value = 300
  # []

  ## Radiative Heat Flux
  # [radiation_flux]  # boundary condition for radiation heat loss at the front (z=max) boundary
  #   type = FunctionRadiativeBC
  #   variable = T
  #   boundary = 'front'
  #   emissivity_function = '1'
  #   Tinfinity = 300
  #   stefan_boltzmann_constant = ${sb}
  #   use_displaced_mesh = true
  # []
  
  # # Radiative Heat Flux
  # [radiation_top_1] # currently in use
  #   type = FunctionRadiativeBC
  #   variable = T
  #   boundary = 'front' 
  #   # htc/(stefan-boltzmann*4*T_inf^3)
  #   emissivity_function = '0.2' # '3/(5.670367e-8*4*300*300*300)'    0.20   0.8  # stefan boltzmann constant = 5.670367e-8 W/m^2K^4
  #   # Using previous default
  #   Tinfinity = 300
  #   stefan_boltzmann_constant = ${sb}
  #   use_displaced_mesh = true
  # []

  # # Convective Heat Flux
  # [convection_top_1] # currently in use
  #   type = ConvectiveFluxFunction
  #   variable = T
  #   boundary = 'front'  
  #   T_infinity = 300.0
  #   coefficient = 300.0 # 20.0 1e5 # 10  300
  #   # Natural convection, 5 ~ 25 W/(m^2 * K). Forced convection: 20 ~ 300 W/(m^2 * K)
  #   use_displaced_mesh = true
  # []

  # [weld_flux]  # boundary condition for laser heat flux at the front (z=max) boundary
  #   type = GaussianEnergyFluxBC 
  #   variable = T
  #   boundary = 'front'                    # the boundary where the laser is applied
  #   P0 = power_function                 # Reference the new power function instead of a constant value
  #   R = 1.00e-4                           # The radius at which the beam intensity falls to 1/e^2 of its axis value in m
  #   x_beam_coord = path_x              # x coordinate of the laser beam center (moving in x direction over time)
  #   y_beam_coord = path_y              # y coordinate of the laser beam center (fixed in y direction)
  #   z_beam_coord = path_z              # z coordinate of the laser beam center (fixed in z direction)
  # []
  [weld_flux_on]
    type = GaussianEnergyFluxBC
    variable = T
    boundary = 'front'
    P0 = 528.0                 #  660 * 80% = 528
    R = 1.00e-4
    x_beam_coord = path_x
    y_beam_coord = path_y
    z_beam_coord = path_z
  []
  [weld_flux_off]
    type = GaussianEnergyFluxBC
    variable = T
    boundary = 'front'
    P0 = 0.0
    R = 1.00e-4
    x_beam_coord = path_x
    y_beam_coord = path_y
    z_beam_coord = path_z
  []

  # [displace_z_top]
  #   type = INSADMassAdditionBoundaryBC
  #   boundary = 'front'
  #   variable = 'disp_z'
  #   temperature = 'T'
  #   deposition_velocity = 5e-3        # 150e-3 
  #   activation_temperature = 1708.00   # 2500 1708.00
  #   smooth_param = 800                 # 200
  # []
  # [displace_x_top_dummy]
  #   type = INSADDummyDisplaceBoundaryIntegratedBC
  #   boundary = 'front'
  #   variable = 'disp_x'
  #   velocity = 'vel'
  #   temperature = 'T'
  #   component = 0
  # []
  # [displace_y_top_dummy]
  #   type = INSADDummyDisplaceBoundaryIntegratedBC
  #   boundary = 'front'
  #   variable = 'disp_y'
  #   velocity = 'vel'
  #   temperature = 'T'
  #   component = 1
  # []
  # [displace_z_top_dummy]
  #   type = INSADDummyDisplaceBoundaryIntegratedBC
  #   boundary = 'front'
  #   variable = 'disp_z'
  #   velocity = 'vel'
  #   temperature = 'T'
  #   component = 2
  # []
  # [displace_x_top_dummy2]
  #   type = INSADDummyDisplaceBoundaryIntegratedBC
  #   boundary = 'top'
  #   variable = 'disp_x'
  #   velocity = 'vel'
  #   temperature = 'T'
  #   component = 0
  # []
  # [displace_y_top_dummy2]
  #   type = INSADDummyDisplaceBoundaryIntegratedBC
  #   boundary = 'top'
  #   variable = 'disp_y'
  #   velocity = 'vel'
  #   temperature = 'T'
  #   component = 1
  # []
[]

[Materials]
  # [ins_mat]
  #   type = INSADStabilized3Eqn
  #   velocity = vel
  #   pressure = p
  #   temperature = T
  #   use_displaced_mesh = true
  # []
  # [steel]
  #   type = LaserWeld316LStainlessSteel            # AriaLaserWeld304LStainlessSteel
  #   temperature = T
  #   # beta = 1e7                                  # For AriaLaserWeld304LStainlessSteel
  #   use_displaced_mesh = true
  # []
  # [steel_boundary]
  #   type = LaserWeld316LStainlessSteelBoundary    # AriaLaserWeld304LStainlessSteelBoundary
  #   boundary = 'front'
  #   temperature = T
  #   use_displaced_mesh = true
  # []

  [density]
    type = ADGenericConstantMaterial
    prop_names = 'density'
    prop_values = 4050 # kg/m^3  Ti-6Al-4V density 4430   4050(for solid from Nandwana_2020)  # Stainless steel density 7609 kg/m^3  
  []
  [heat]
    type = ADHeatConductionMaterial
    specific_heat_temperature_function = 750 #  J/kg·K specific heat capacity of Ti-6Al-4V 560 J/kg·K  750 J/kg·K (for solid from Nandwana_2020)   # specific heat capacity of Stainless steel 500 J/kg·K
    thermal_conductivity_temperature_function = 27 # W/m·K thermal conductivity of Ti-6Al-4V 6.7 to 7.5 W/m·K (Room Temp.)   15~20 W/m·K (773 K)  27 W/m·K (for solid from Nandwana_2020) # thermal conductivity of Stainless steel 25 W/m·K
    temp = T
  []

  [const]
    type = GenericConstantMaterial
    prop_names = 'abs sb_constant'
    prop_values = '1 ${sb}'
    use_displaced_mesh = true
  []
[]

[Functions]
  # [power_function]
  #   type = PiecewiseLinear
  #   # Define the power transition:
  #   # 0s: Full Power (e.g., 5W)
  #   # 160e-6s: Full Power
  #   # 160.1e-6s: Power ramps to 0 W (smooth transition over 0.1us)
  #   # ${endtime} (480e-6s): 0 W
  #   t = '0.0 160e-6 160.1e-6 ${endtime}'
  #   y = '5.0 5.0 0.0 0.0'
  # []

  [path_x]
    type = ParsedFunction
    expression = "5e-4" # 2*cos(2.0*pi*t) 8.47e-3*t  6.35e-3*t  10.58e-3*t  "8.47e-3*t + 0.01"  "8.47e-3*t + 2.1175e-3"
  []
  [path_y]
    type = ParsedFunction
    expression = "5e-4" # 2*sin(2.0*pi*t)   0  0.0012  
  []
  [path_z]
    type = ParsedFunction
    expression = "5e-4" # 1 0.001 0.0012 0.0008 0.00115 0.00125  0.01025
  []
[]

[Controls]
  [flux_control]
    type = TimePeriod
    start_time = 0.0
    end_time = 0.4e-3
    enable_objects = 'BCs/weld_flux_on'
    disable_objects = 'BCs/weld_flux_off'
  []
  [flux_control_off]
    type = TimePeriod
    start_time = 0.4e-3
    end_time = ${endtime}
    enable_objects = 'BCs/weld_flux_off'
    disable_objects = 'BCs/weld_flux_on'
  []
[]

# [Times], [Controls] blocks removed as they are no longer necessary

[Preconditioning]
  [SMP]
    type = SMP
    full = true
    petsc_options_iname = '-pc_type -pc_factor_shift_type -pc_factor_mat_solver_type'
    petsc_options_value = 'lu       NONZERO               superlu_dist'
  []
[]

[Executioner]
  type = Transient
  end_time = ${endtime}
  dtmin = 1e-8
  dtmax = ${timestep}
  petsc_options = '-snes_converged_reason -ksp_converged_reason -options_left'
  solve_type = 'NEWTON'
  line_search = 'none'
  nl_max_its = 12
  l_max_its = 100
  [TimeStepper]
    type = IterationAdaptiveDT
    optimal_iterations = 7
    dt = ${timestep}
    linear_iteration_ratio = 1e6
    growth_factor = 1.5
  []
[]

[Outputs]
  [exodus]
    type = Exodus
    output_material_properties = true
    show_material_properties = 'mu'
  []
  checkpoint = true
  perf_graph = true
[]

[Debug]
  show_var_residual_norms = true
[]

[Adaptivity]
  marker = combo
  max_h_level = 4

  [Indicators]
    [error_T]
      type = GradientJumpIndicator
      variable = T
    []
    # [error_dispz]
    #   type = GradientJumpIndicator
    #   variable = disp_z
    # []
  []

  [Markers]
    [errorfrac_T]
      type = ErrorFractionMarker
      refine = 0.4
      coarsen = 0.2
      indicator = error_T
    []
    # [errorfrac_dispz]
    #   type = ErrorFractionMarker
    #   refine = 0.4
    #   coarsen = 0.2
    #   indicator = error_dispz
    # []
    [combo]
      type = ComboMarker
      markers = 'errorfrac_T'  # markers = 'errorfrac_T errorfrac_dispz'
    []
  []
[]

[Postprocessors]
  # [num_dofs]
  #   type = NumDOFs
  #   system = 'NL'
  # []
  # [nl]
  #   type = NumNonlinearIterations
  # []
  # [tot_nl]
  #   type = CumulativeValuePostprocessor
  #   postprocessor = 'nl'
  # []

  [avg_temp]
    type = ElementAverageValue
    variable = T
  []
  [max_temp]
    type = ElementExtremeValue
    variable = T
    value_type = max
  []
  [min_temp]
    type = ElementExtremeValue
    variable = T
    value_type = min
  []
[]

