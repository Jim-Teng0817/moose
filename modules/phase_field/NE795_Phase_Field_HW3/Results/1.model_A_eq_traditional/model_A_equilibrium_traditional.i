# This is a simple example to calculate the equilibrium properties for Model A
# surface energy = 0.2357 (see the analytical derivation of the surface energy in terms of the model parameters)
# surface energy = sqrt(Kappa*A)/(3*sqrt(2))
# kappa is the gradient coefficient
kappa = 4.0 # 1.0
# A is the constant in the double well bulk_free_energy (it controls the height of the well (A/16) )
A = 0.25  # 1.0
# Here we use moose built-in Allen-Cahn kernels from the phase-field module
# this is the "traditional" way of implementing a phase-field model A
n_elem = 600 # Number of Elements
X = 50 # Half of the Domain/Bar length
L = 1.0 # Alen-Cahn mobility
[Mesh]
  type = GeneratedMesh
  dim = 1
  nx = '${n_elem}'
  ny = 0
  nz = 0
  xmin = '-${X}'
  xmax = '${X}'
  elem_type = EDGE2 # 1st order 1D element (2 Nodes)
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
  kappa_names = kappa # the name of the gradient coefficient.
  interfacial_vars = eta
  f_name = F # the name of the materials object that defines the bulk free energy (the non-gradient term(s))
  execute_on = 'INITIAL TIMESTEP_END'
  [../]
[]
[Functions]
  [./analytic_solution] # expected equilibrium profile
    type = ParsedFunction
    expression = '0.50*(1.0+tanh(x*sqrt(${A}/(2.0*${kappa}))))'
    # execute_on = 'INITIAL TIMESTEP_END'       # No need (Jim Nov. 4, 2024)
  [../]
[]
# At equilibrium, this is a steady-state problem, we do not really need an IC.
# it acts here as an intial guess of the solution (instead of moose default of a zero initial guess)
# it will still converges if we do not provide a good inital guess but it would be slower.
[ICs]
  [./InitialCondition]
    type = FunctionIC
    function = analytic_solution
    variable = eta
  [../]
[]

[BCs]
  [./eta_left]
    type = DirichletBC
    variable = 'eta'
    boundary = 'left'
    value = 0.0
    preset = false
  [../]
  [./eta_right]
    type = DirichletBC
    variable = 'eta'
    boundary = 'right'
    value = 1.0
    preset = false
  [../]
[]

[Kernels]
  # moose built-in Allen-Cahn kernels from the phase-field module
  [./AC_bulk]
    type = AllenCahn
    variable = 'eta'
    f_name = F # the name of the materials object that defines the bulk free energy (the non-gradient term(s))
    mob_name = mobility # the name of Allen-Cahn mobility

  [../]
  [./AC_int]
    type = ACInterface
    variable = 'eta'
     kappa_name = kappa # the name of the Allen-Cahn gradient coefficient
      mob_name = mobility
  [../]
[]

[Materials]
  [./bulk_free_energy]
    type = DerivativeParsedMaterial
    coupled_variables = 'eta'
    property_name = F
    expression = ${A}*(eta^2*(eta-1.0)^2)
    derivative_order = 2
  [../]
    [./const] # names and values of Allen-Cahn gradient coefficient and mobility
      type = GenericConstantMaterial
      prop_names = 'kappa mobility'
      prop_values = '${kappa} ${L}'
  [../]
[]

[Postprocessors]
  [./total_free_energy]
    type = ElementIntegralVariablePostprocessor
    variable = total_free_energy
    execute_on = 'INITIAL TIMESTEP_END'
    # this will give the excess/interface energy
  [../]
  [./error] # difference between numerical and analtical solutions (L2 norm)
    type = ElementL2Error
    variable = eta
    function = analytic_solution
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
[]

[VectorPostprocessors]
  [free_energy_exact]
    type = LineFunctionSampler
    functions = analytic_solution
    start_point = '-50 0 0'
    end_point = '50 0 0'
    num_points = 200
    sort_by = x
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [free_energy_simulation]
    type = LineValueSampler
    variable = total_free_energy
    start_point = '-50 0 0'
    end_point = '50 0 0'
    num_points = 200
    sort_by = x
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]

[Executioner]
  type = Steady # we are solving for the equilibrium/steady profile.
  nl_max_its = 15
  solve_type = NEWTON
  petsc_options_iname = '-pc_type'
  petsc_options_value = 'lu'
  l_max_its = 15
  l_tol = 1.0e-6
  nl_rel_tol = 1.0e-9
  nl_abs_tol = 1e-11
[]

[Outputs]
  file_base = model_A_eq_traditional/model_A_eq_1D_${A}_${n_elem}
  exodus = true
  csv = true
[]
