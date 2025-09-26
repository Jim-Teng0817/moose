# This simulates spinodal decomposition in a binary alloy using a template for phase-field model B
# with a regular solution free energy
# regular solution parameters
omega = 0.3
R = 8.314e-3
T_l = 12  # low temperature
T_h = 120 # high temperature

C_0 = 0.50
# C_0 must be inside the unstable spinodal region (0.218<c<0.787)
# kappa_c is the gradient coefficient
kappa_c = 1.0
M = 1.0 # Cahn-Hilliard mobility (here constant)
n_elem = 128 # Number of Elements
X = 128 #  Domain length
x_c = ${fparse X/2} # particle center (X/2.0)
r = 32 # particle's radius
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
  [./T]
  [../]
[]
[Functions]
  [./Temperature]
    type = ParsedFunction
    # expression = 'if((x-${x_c})^2+(y-${x_c})^2<=${r}^2,${T_l},${T_h})'
    expression = 'if((x-${x_c})^2+(y-${x_c})^2<=${r}^2,${T_h},${T_l})'    # Flip the temperature field
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
  [./T]
    type = FunctionIC
    function = Temperature
    variable = T
  [../]
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
    coupled_variables = 'c T'
    property_name = F
    # regular solution free energy
    expression = '${omega}*c*(1.0-c)+${R}*T*(c*log(c)+(1.0-c)*log(1.0-c))'
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
  num_steps = 230
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
  file_base = model_b_decomposition_coupled_to_temperature/model_b_decomposition_coupled_to_temperature_c=${C_0}
[]
