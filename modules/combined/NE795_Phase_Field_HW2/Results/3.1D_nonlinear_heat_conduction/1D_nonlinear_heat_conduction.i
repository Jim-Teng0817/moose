# Solution of nonlinear diffusion Eqn in 1D
# DerivativeParsedMaterial is used to automatically get the required symbolic derivative to set up the Jacobian

n_elem = 100 # Number of Elements
T_l = 1.0 # Temperature at the left boundary
T_r = 2.0 # Temperature at the right boundary
L = 1.0 # Domain/Bar length
n = 1 # try n = 1,5,10
d = 1  # 1 for full perfect Jacobian (0 for imperfect Jacobian)
expression1 = (1.0+10.0*T^${n}) # the non-linear thermal conductivity
#expression2 = 1.0/${expression1}
#solve = PJFNK  # (NEWTON or PJFNK)
solve = NEWTON
expression = expression1 # (or expression2)suffix to the output file name
#expression = expression2
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
    coupled_variables = 'T dTdx'
    expression = '-${expression1}*dTdx'
    #expression = '-${expression2}*dTdx'
  [../]

[]

[Kernels] # the terms that appear in the PDE
  [./symbolic_diffusion_kernel]
    type = MatDiffusion   # evaluate the divergence of a flux
    variable = T
    diffusivity = k
    # the thermal_conductivity/ diffusion_coefficient and their derivatives
    # can be symbolically evaluated form a DerivativeParsedMaterial
    # to be defined under the Materials block
  [../]
[]

[BCs]
  [./T_left] # T_l
    type = DirichletBC
    variable = 'T'
    boundary = 'left'
    value = ${T_l}
    preset = false
  [../]
  [./T_right] # T_r
    type = DirichletBC
    variable = 'T'
    boundary = 'right'
    value = ${T_r}
    preset = false
  [../]
[]

[Materials]
  [./thermal_conductivity] # thermal_conductivity
    type = DerivativeParsedMaterial
    property_name = k
  # expression = 'a:=1.0;b:=10.0;n:=5;1.0/(a+b*T^n)'
    expression = '${expression1}'
  # expression = '${expression2}'
    coupled_variables = 'T' # (the variables that k depends on)
    derivative_order = ${d}
    output_properties = 'k'
    outputs = 'exodus' # to visulaize the value of k
    # this kernel will auotmatically generate a symbolic derivative (exact!)
    # of k w.r.t T to fill out the Jacobian Matrix
    # if derivative_order = 0, Jacobain Matrix will Not be approxiamted and a unity matrix will be used instead.
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
  [./nonlinear_iterations]  # Number of nonlinear iterations
    type =  NumNonlinearIterations
  [../]
  [./linear_iterations]  # Number of linear iterations
    type =  NumLinearIterations
  [../]
  [./Memory]
    type = MemoryUsage
    mem_type = physical_memory
    value_type = total
    # by default MemoryUsage reports the peak value for the current timestep
    # out of all samples that have been taken (at linear and non-linear iterations)
  [../]

[]

[VectorPostprocessors]
  [./line_values]
   type =  LineValueSampler
    start_point = '0 0 0'
    end_point = '${L} 0 0'
    variable = 'T jx dTdx'
    num_points = ${n_elem}
    sort_by =  id
  [../]
[]

[Executioner]
  type =  Steady
  solve_type = '${solve}'
  # try both PJFNK and NEWTON
  petsc_options_iname = '-pc_type'
  petsc_options_value = 'lu'# Direct solver for the linear system #

  l_max_its = 25
  nl_max_its = 150
  l_tol = 1.0e-3
  nl_rel_tol = 1.0e-6
  nl_abs_tol = 1e-8
[]

[Outputs]
  # file_base = Output_folder_name/Output_file_name
  file_base = 1D_nonlinear_heat_conduction/1D_nonlinear_heat_conduction_${expression}_d=${d}_${solve}
  # the file name with a suffix to generate a different output file for each run
  # A folder named 1D_nonlinear_heat_conduction will be created to save the output files
  exodus = true # the .e mesh file
  csv = true # the csv file with post-processors values
[]
