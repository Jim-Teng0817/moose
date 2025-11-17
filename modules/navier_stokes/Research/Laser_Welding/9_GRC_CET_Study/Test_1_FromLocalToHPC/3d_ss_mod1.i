period =1.06e0 # Period of the laser motion  # 1.25e-3  5.00e-1 10.6e-1
endtime = ${period} # Total simulation time (Simulation end time)
timestep = 1e-2 # Time step size  # 1.25e-5
surfacetemp = 300 # Surface temperature in K
sb = 5.67e-8  # Stefan-Boltzmann constant (in kg s^-3 K^-4)
# Power = 300.00   # Laser Power in W  159.96989792079225
# Laser_Absorption_Efficiency = 0.4  # Laser Absorption Coefficient


[Mesh]
  [gen] 
    type = GeneratedMeshGenerator
    dim = 3
    xmin = 0e-3
    xmax = 15.0e-3 # 1.5e-3  5.0e-3  10.0e-3
    ymin = 0e-3
    ymax = 4.0e-3 # 0.5e-3   1.5e-3  9.0e-3
    zmin = 0e-3
    zmax = 5.0e-3 # 0.5e-3   1.5e-3  4.5e-3 
    nx = 18  # 2  18  18
    ny = 8  # 6  12  8
    nz = 6  # 2   6  6
  []
  displacements = 'disp_x disp_y disp_z'
  uniform_refine = 0
[]

[Problem]
  error_on_jacobian_nonzero_reallocation = false
[]

[Variables] # primary variables for temperature and mesh displacements
  [T]
  []
  [disp_x]
  []
  [disp_y]
  []
  [disp_z]
  []
[]

[AuxVariables]  # aux variables for velocity and pressure
  [vel] 
    family = LAGRANGE_VEC
  []
  [p]
  []
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
    function = '(${surfacetemp} - 300) / .7e-3 * z + ${surfacetemp}'
  []
[]

[Materials]   # material for diffusivity used in mesh displacement kernels (not sure yet)
  [Dc]   
    type = GenericConstantMaterial
    prop_names = Du
    prop_values = '1'
  []
[]

[Kernels]
  [disp_x]
    type = MatDiffusion
    variable = disp_x
    diffusivity = Du   # use a material property for diffusivity (not sure yet)
  []
  [disp_y]
    type = MatDiffusion
    variable = disp_y
    diffusivity = Du
  []
  [disp_z]
    type = MatDiffusion
    variable = disp_z
    diffusivity = Du
  []
  [temperature_time]  # kernel for time derivative of temperature
    type = INSADHeatConductionTimeDerivative
    variable = T
    use_displaced_mesh = true
  []
  [temperature_advection]  # kernel for advection due to fluid velocity (not sure yet)
    type = INSADEnergyAdvection
    variable = T
    use_displaced_mesh = true
  []
  [temperature_mesh_advection]  # kernel for advection due to mesh motion
    type = INSADEnergyMeshAdvection
    variable = T
    disp_x = disp_x
    disp_y = disp_y
    disp_z = disp_z
    use_displaced_mesh = true
  []
  [temperature_conduction]  # kernel for heat conduction
    type = ADHeatConduction
    variable = T
    thermal_conductivity = 'k'  # thermal conductivity defined in material AriaLaserWeld304LStainlessSteel
    use_displaced_mesh = true
  []
[]

[BCs]
  [x_no_disp]  # boundary condition to fix displacement in x direction at the back (z=0) boundary
    type = DirichletBC
    variable = disp_x
    boundary = 'back' # In 3D (By Paraview), back (lower z) = 0, bottom (lower y) = 1, right (higher x) = 2, top (higher y) = 3, left (lower x) = 4, front (higher z) = 5
    value = 0
  []
  [y_no_disp]  # boundary condition to fix displacement in y direction at the back (z=0) boundary
    type = DirichletBC
    variable = disp_y
    boundary = 'back'
    value = 0
  []
  [z_no_disp]  # boundary condition to fix displacement in z direction at the back (z=0) boundary
    type = DirichletBC
    variable = disp_z
    boundary = 'back'
    value = 0
  []
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
  
  # Radiative Heat Flux
  [radiation_top_1] # currently in use
    type = FunctionRadiativeBC
    variable = T
    boundary = 'front' 
    # htc/(stefan-boltzmann*4*T_inf^3)
    emissivity_function = '0.2' # '3/(5.670367e-8*4*300*300*300)'    0.20   0.8  # stefan boltzmann constant = 5.670367e-8 W/m^2K^4
    # Using previous default
    Tinfinity = 300
    stefan_boltzmann_constant = ${sb}
    use_displaced_mesh = true
  []

  # Convective Heat Flux
  [convection_top_1] # currently in use
    type = ConvectiveFluxFunction
    variable = T
    boundary = 'front'  
    T_infinity = 300.0
    coefficient = 300.0 # 20.0 1e5 # 10  300
    # Natural convection, 5 ~ 25 W/(m^2 * K). Forced convection: 20 ~ 300 W/(m^2 * K)
    use_displaced_mesh = true
  []

  [weld_flux]  # boundary condition for laser heat flux at the front (z=max) boundary
    type = GaussianEnergyFluxBC 
    variable = T
    boundary = 'front'                    # the boundary where the laser is applied
    P0 = 100                               # Peak power of the laser in W  159.96989792079225  120
    R = 5.00e-4                           # The radius at which the beam intensity falls to 1/e^2 of its axis value in m  1.8257418583505537e-4   1.00e-3 = 5e-4
    x_beam_coord = '9e-3*t/${endtime} + 3e-3'  # x coordinate of the laser beam center (moving in x direction over time) Scan Speed = 4.5e-3/${endtime} '10.0e-3*t/${endtime} + 1.0e-3' 
    y_beam_coord = '2.00e-3'              # y coordinate of the laser beam center (fixed in y direction)  '0.25e-3'  '0.75e-3'
    z_beam_coord = '5.00e-3'              # z coordinate of the laser beam center (fixed in z direction)  '0.5e-3' 
    use_displaced_mesh = true             # use displaced mesh for moving boundary (=> how to distibute the Guassian flux on the deformed surface matters)
  []
  [displace_z_top]
    type = INSADMassAdditionBoundaryBC
    boundary = 'front'
    variable = 'disp_z'
    temperature = 'T'
    deposition_velocity = 5e-3        # 150e-3 
    activation_temperature = 2500.00   # 2500 1708.00
    smooth_param = 800                 # 200
  []
  [displace_x_top_dummy]
    type = INSADDummyDisplaceBoundaryIntegratedBC
    boundary = 'front'
    variable = 'disp_x'
    velocity = 'vel'
    temperature = 'T'
    component = 0
  []
  [displace_y_top_dummy]
    type = INSADDummyDisplaceBoundaryIntegratedBC
    boundary = 'front'
    variable = 'disp_y'
    velocity = 'vel'
    temperature = 'T'
    component = 1
  []
  [displace_z_top_dummy]
    type = INSADDummyDisplaceBoundaryIntegratedBC
    boundary = 'front'
    variable = 'disp_z'
    velocity = 'vel'
    temperature = 'T'
    component = 2
  []
  [displace_x_top_dummy2]
    type = INSADDummyDisplaceBoundaryIntegratedBC
    boundary = 'top'
    variable = 'disp_x'
    velocity = 'vel'
    temperature = 'T'
    component = 0
  []
  [displace_y_top_dummy2]
    type = INSADDummyDisplaceBoundaryIntegratedBC
    boundary = 'top'
    variable = 'disp_y'
    velocity = 'vel'
    temperature = 'T'
    component = 1
  []
[]

[Materials]
  [ins_mat]
    type = INSADStabilized3Eqn
    velocity = vel
    pressure = p
    temperature = T
    use_displaced_mesh = true
  []
  [steel]
    type = LaserWeld316LStainlessSteel            # AriaLaserWeld304LStainlessSteel
    temperature = T
    # beta = 1e7                                  # For AriaLaserWeld304LStainlessSteel
    use_displaced_mesh = true
  []
  [steel_boundary]
    type = LaserWeld316LStainlessSteelBoundary    # AriaLaserWeld304LStainlessSteelBoundary
    boundary = 'front'
    temperature = T
    use_displaced_mesh = true
  []
  [const]
    type = GenericConstantMaterial
    prop_names = 'abs sb_constant'
    prop_values = '1 ${sb}'
    use_displaced_mesh = true
  []

  [solidification_rate]
    type = SolidificationRate
    solidus_temperature = 1675.00
    liquidus_temperature = 1708.00
    temperature = T
    outputs = exodus
  []
[]

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
    show_material_properties = 'mu cooling_rate solidification_rate temperature_gradient'
  []
  checkpoint = true
  perf_graph = true
[]

[Debug]
  show_var_residual_norms = true
[]

[Adaptivity]
  marker = combo
  max_h_level = 3

  [Indicators]
    [error_T]
      type = GradientJumpIndicator
      variable = T
    []
    [error_dispz]
      type = GradientJumpIndicator
      variable = disp_z
    []
  []

  [Markers]
    [errorfrac_T]
      type = ErrorFractionMarker
      refine = 0.4
      coarsen = 0.2
      indicator = error_T
    []
    [errorfrac_dispz]
      type = ErrorFractionMarker
      refine = 0.4
      coarsen = 0.2
      indicator = error_dispz
    []
    [combo]
      type = ComboMarker
      markers = 'errorfrac_T errorfrac_dispz'
    []
  []
[]

[Postprocessors]
  [num_dofs]
    type = NumDOFs
    system = 'NL'
  []
  [nl]
    type = NumNonlinearIterations
  []
  [tot_nl]
    type = CumulativeValuePostprocessor
    postprocessor = 'nl'
  []
[]
