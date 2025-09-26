# Diffusionless particle growth due to undercooling (solidification) or strain energy (recrystallization)

# kappa is the gradient coefficient
kappa = 1.0
# A is the constant in the double well bulk_free_energy (it controls the height of the well (A/16))
A = 1.0
# surface energy = 0.2357 (see the analytical derivation of the surface energy in terms of the model parameters)
# surface energy = sqrt(Kappa*A)/(3*sqrt(2))

# B is the constant in the bulk_free_energy that defines the difference in the free energy of the phases (F (eta=1) - F(eta=0)= -B)
# The driving force for grwoth (it tilts the double well, making one phase more stable than the other)
B = 0.1
# Here we use moose built-in Allen-Cahn kernels from the phase-field module
# this is the "traditional" way of implementing a phase-field model A
area_fraction = 0.040
rmax = 128 # the Domain Radius
r = ${fparse sqrt(area_fraction*rmax^2)} # initial particle's radius
n_elem = 64 # Number of Elements
L = 1.0 # Alen-Cahn mobility

[Mesh]
  [Circular_Mesh]
    type = AnnularMeshGenerator
    rmax = '${rmax}'
    rmin = '0'
    nr = '${n_elem}'   # number of radial elements
    nt = '${n_elem}'   # number of circumferential elements
  []
[]


[Variables]
  [./eta]
    order = FIRST
    family =  LAGRANGE
  [../]
[]

[AuxVariables]
  [./total_free_energy] # AuxVariable To store the total_free_energy density at each point.
    order = CONSTANT
    family = MONOMIAL
  [../]
[]
[AuxKernels]
  [./total_free_energy] # Aux Kernel To calculate the total_free_energy density at each point.
    type = TotalFreeEnergy
    variable = total_free_energy
    kappa_names = kappa
    interfacial_vars = eta
    f_name = F
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
[]

[ICs]
  [./eta]
    type = SpecifiedSmoothCircleIC
    variable = eta
    radii = '${r}'
    int_width = 0.0 # initially sharp interface
    x_positions = '0'
    y_positions = '0'
    z_positions = '0'
    invalue = 1.0
    outvalue = 0.0
  [../]
[]

[Kernels]
  [./AC_bulk]
    type = AllenCahn
    variable = 'eta'
    f_name = F
    mob_name = mobility
  [../]
  [./AC_int]
    type = ACInterface
    variable = 'eta'
    kappa_name = kappa
    mob_name = mobility
  [../]
  [./eta_dot]
    type = TimeDerivative
    variable = 'eta'
  [../]
[]

[Materials]
  [./Bulk_Free_Eng]
    type = DerivativeParsedMaterial
    coupled_variables ='eta'
    expression = ${A}*(eta^2*(1.0-eta)^2)+${B}*(2.0*eta^3-3.0*eta^2)
    derivative_order = 2
    property_name = F
  [../]
  [./const] # names and values of Allen-Cahn gradient coefficient and mobility
    type = GenericConstantMaterial
    prop_names = 'kappa mobility'
    prop_values = '${kappa} ${L}'
[../]
[]

[Postprocessors]
  [./area] # eta=1 inside the particle and zero outside
  # so its integration will give the particle area (volume in 3D)
    type = ElementIntegralVariablePostprocessor
    variable = 'eta'
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
  [./radius]
    type = ParsedPostprocessor
    pp_names = 'area' # name of ther post_processor(s) to get data from
    function = 'sqrt(area/3.14)'   # Area = pi*R^2
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
  [./total_free_energy]
    type = ElementIntegralVariablePostprocessor
    variable = total_free_energy
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
  [./area_fraction]
    type = ElementAverageValue
    variable = 'eta'
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
[]
[UserObjects]
  [./arnold]
    type = Terminator
    expression = 'area_fraction>0.99'
  [../]
[]

[Executioner]
  type = Transient
  nl_max_its = 15
  solve_type = NEWTON
  petsc_options_iname = '-pc_type'
  petsc_options_value = 'asm'
  l_max_its = 15
  l_tol = 1.0e-3
  nl_rel_tol = 1.0e-6
  start_time = 0.0
  num_steps = 350
  nl_abs_tol = 1e-9
  [./TimeStepper] # Time Adaptivity
    type = IterationAdaptiveDT
    dt = 1.0
    growth_factor = 1.2
    cutback_factor = 0.75
    optimal_iterations = 7
  [../]
  [./Adaptivity] # Mesh Adaptivity
    refine_fraction = 0.7
    coarsen_fraction = 0.01
    max_h_level = 2
    initial_adaptivity = 2
  [../]
[]

[Outputs]
  file_base = circular_particle_model_A_growth/circular_particle_model_A_growth
  exodus = true
  csv = true
  interval = 1
[]
