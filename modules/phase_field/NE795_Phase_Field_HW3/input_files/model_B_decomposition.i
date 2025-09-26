# This simulates spinodal decomposition in a binary alloy using a template for phase-field model B

# A simple fourth-order polynomial (double well)
# bulk_free_energy function = A*((c-C_m)^2*(c-C_p)^2)
# one can also use the regular solution free energy
# m:matrix, p: precipitate, C_p: Equilibrium concentration in precipitate
A   = 1.0
C_m = 0.0
C_p = 1.0

C_0 = 0.250
# C_0 must be inside the unstable spinodal region (0.218<c<0.787)
# kappa_c is the gradient coefficient
kappa_c = 1.0
M = 1.0 # Cahn-Hilliard mobility (here constant)
n_elem = 256 # Number of Elements
X = 256 #  Domain length

[Mesh]
  type = GeneratedMesh
  dim = 2
  nx = '${n_elem}'
  ny = '${n_elem}'
  nz = 0
  xmin = 0
  xmax = '${X}'
  ymin = 0
  ymax = '${X}'
  elem_type = QUAD4
[]

[Variables]
  [./c] # the concentration
  [../]
  [./w] # the chemical potential
  [../]
[]
# aux varaibles to track the free energy change (must decrease with time)
[AuxVariables]
  [./total_F]
    order = CONSTANT
    family = MONOMIAL
  [../]
[]

[ICs]
  [./c] # random variation in c inside the unstable spinodal region (0.218<c<0.787)
    type = RandomIC
    variable = 'c'
     min = ${fparse C_0-0.01}
     max = ${fparse C_0+0.01}
  [../]
  # at the lower end of the spinodal
[]

[BCs]
  [./Periodic]
    [./all]
      auto_direction = 'x y'
    [../]
  [../]
[]

[Kernels]
  # Split form of Cahn-Hilliard equation
  # w is the chemical potential

  #-----------w equation---------------#
  [./c_dot]
    type = CoupledTimeDerivative
    variable = w
    v = c
  [../]
  [./w_residual]
    # args = 'c' in case the mobility is concentration dependent
    type = SplitCHWRes
    variable = w
    mob_name = M
  [../]


  #-----------c equation---------------#
  [./c_residual]
    type = SplitCHParsed
    variable = c
    f_name = F
    kappa_name = kappa_c
    w = w
  [../]
[]

[AuxKernels]
  [./total_F]
    type = TotalFreeEnergy
    variable = total_F
    interfacial_vars = 'c'
    kappa_names = 'kappa_c'
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
[]

[Materials]
  [./Bulk_Free_Eng]
    type = DerivativeParsedMaterial
    coupled_variables ='c'
    property_name = F
    expression = ${A}*((c-${C_m})^2*(c-${C_p})^2)
    # one can also use the regular solution free energy
    derivative_order = 2
  [../]
  [./const]
    type = GenericConstantMaterial
    prop_names = 'kappa_c M'
    prop_values = '${kappa_c} ${M}'
  [../]
  [./precipitate_indicator]  # calculates the precipitate fraction
    type = ParsedMaterial
    property_name = precipitate_indicator
    expression = if(c>0.9,1.0/(${X}*${X}),0)
    coupled_variables = c
  [../]
[]

[Postprocessors]
  [./solute_average_concentration]
    type = ElementAverageValue
    variable = c
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
  [./total_F]
    type = ElementIntegralVariablePostprocessor
    variable = total_F
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
  [./precipitate_area_fraction]      # Area fraction of precipitate
    type = ElementIntegralMaterialProperty
    mat_prop = precipitate_indicator
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
[]

[Preconditioning]
  [./SMP] # to produce the complete perfect Jacobian
    type = SMP
    full = true
  [../]
[]

[Executioner]
  type = Transient
  nl_max_its = 15
  scheme = bdf2
  solve_type = NEWTON
  petsc_options_iname = -pc_type
  petsc_options_value = asm
  l_max_its = 15
  l_tol = 1.0e-3
  nl_rel_tol = 1.0e-8
  start_time = 0.0
  num_steps = 200
  nl_abs_tol = 1e-9
  [./TimeStepper]
    type = IterationAdaptiveDT
    dt = 1.0
    growth_factor = 1.2
    cutback_factor = 0.75
    optimal_iterations = 6
  [../]
[]

[Outputs]
  exodus = true
  csv = true
  interval = 1
  file_base = Model_B_Decomposition/Model_B_Decomposition_c=${C_0}
[]
