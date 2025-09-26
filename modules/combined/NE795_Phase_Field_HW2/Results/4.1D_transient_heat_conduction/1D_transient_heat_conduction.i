n_elem = 100 # Number of Elements
k = 5.0e-2 # Value of the constant thermal conductivity
#T_l = 0.0 # Temperature at the left boundary
#T_r = 0.0 # Temperature at the right boundary
L = 1.0 # Domain/Bar length
A = 1.0 # The amplitude of the sinusoidal temperature profile

[Mesh]
  type = GeneratedMesh
  dim = 1
  nx = '${n_elem}'
  ny = 0
  nz = 0
  xmin = 0
  xmax = '${L}'
  elem_type = EDGE2 # 1st order 1D element (2 Nodes)
[]


[Variables]
  [./T]
    order = FIRST
    family = LAGRANGE
  [../]
[]

[Functions]
  [./T_IC] # Initial condition for T
    type = ParsedFunction
    expression = '${A}*sin(pi*x/${L})'
  [../]
  [./analytic_solution]
    type =  ParsedFunction
    # Simple time dependent solution in 1D
   expression = 't1:=${L}^2/(${k}*pi^2);${A}*sin(pi*x/${L})*exp(-t/t1)'
  [../]
[]

[ICs]
    [./InitialCondition]
      type = FunctionIC
      function = T_IC
      variable = T
    [../]
[]

[AuxVariables] # auxiliary varaibles that do not appear directly in the PDE

  # the temperature gradient
  [./dTdx]
    order = SECOND
    family = MONOMIAL
  [../]
  # the heat flux
  [./jx]
    order = SECOND
    family = MONOMIAL
  [../]
[]

[AuxKernels] # the kernels that evaluate the values of the auxvariables

  [./dTdx]
    type = VariableGradientComponent
    variable = dTdx
    gradient_variable = T
    component = x
  [../]
  [./jx]
    type = ParsedAux
    variable = jx
    coupled_variables = 'dTdx'
    expression = '-${k}*dTdx'
  [../]
[]

[Kernels] # the terms that appear in the PDE
  [./heat_diffusion]  # evaluates the Laplacian of temperature
    type = HeatConduction
    variable = T
  [../]
  [./T_dot] # evaluates the time derivative of temperature
    variable = T
    type = TimeDerivative
  [../]
[]

[BCs]
  #[./T_left] # T_l
    #type = DirichletBC
    #variable = 'T'
    #boundary = 'left'
    #value = ${T_l}
    #preset = false
  #[../]
  #[./T_right] # T_r
    #type = DirichletBC
    #variable = 'T'
    #boundary = 'right'
    #value = ${T_r}
    #preset = false
  #[../]
[]


[Materials]
  [./constant_thermal_conductivity]
    type = GenericConstantMaterial
    prop_names = 'thermal_conductivity'
    prop_values = '${k}'
  [../]
[]
[Postprocessors]
  [./jx_r]
    type = SideAverageValue
    variable = jx
    boundary = right
  [../]
  [./jx_l]
    type = SideAverageValue
    variable = jx
    boundary = left
  [../]
  [./error] # difference between numerical and analtical solutions (L2 norm)
    type = ElementL2Error
    variable = T
    function = analytic_solution
  [../]

[]
[VectorPostprocessors]
  # The numerical values of the variables/auxvariables across the centerline
  [./line_values]
   type =  LineValueSampler
   start_point = '0 0 0'
   end_point = '${L} 0 0'
   variable = 'T jx dTdx'
   num_points = '${n_elem}'
   sort_by =  id
   execute_on = 'initial TIMESTEP_END'
  [../]
[]
[Executioner] # Solver options
  type = Transient
  solve_type = NEWTON   #PJFNK or NEWTON
  petsc_options_iname = '-pc_type'# Direct solver for the linear system #
  petsc_options_value = 'lu'
  l_max_its = 50
  l_tol = 1.0e-6
  nl_max_its = 10
  nl_rel_tol = 1.0e-8
  dt = 1.0 # Constant time step.
  num_steps = 60   #11
[]
[Outputs]
  # file_base = Output_folder_name/Output_file_name
  file_base = 1D_transient_heat_conduction/1D_transient_heat_conduction_zero_flux
  exodus = true
  csv = true
[]
