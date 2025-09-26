n_elem = 100 # Number of Elements (try 100)
thermal_conductivity = 1.0 # Value of the constant thermal conductivity
T_l = 1.0 # Temperature at the left boundary
T_r = 2.0 # Temperature at the right boundary
L = 1.0 # Domain/Bar length

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
  [./T] # Temperature
  order = FIRST
  family = LAGRANGE
  [../]
[]

[Functions]
  [./analytic_solution]
    type =  ParsedFunction
    # Simple linear solution in 1D
   expression = '${T_l}+(${T_r}-${T_l})/${L}*x'
  [../]
[]
[AuxVariables] # auxiliary varaibles that do not appear directly in the PDE

  # the temperature gradient
  [./dTdx]
    order = CONSTANT
    family = MONOMIAL
  [../]
  # the heat flux
  [./jx]
    order = CONSTANT
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
    expression = '-${thermal_conductivity}*dTdx'
  [../]

[]
[Kernels] # the terms that appear in the PDE
  [./heat_diffusion]  # evaluate the Laplacian of temperature
    type = HeatConduction
    variable = T
# This Kernel will look for a material property called thermal_conductivity to get its value
  [../]
[]

[Materials]

[./constant_thermal_conductivity]
  type = GenericConstantMaterial
  prop_names = 'thermal_conductivity'
  prop_values = '${thermal_conductivity}'
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

[Postprocessors]
  [./error] # difference between numerical and analtical solutions (L2 norm)
    type = ElementL2Error
    variable = T
    function = analytic_solution
  [../]
  [./h] # Element size for each run.
    type = AverageElementSize
  [../]
  [./jx_r] # side averaged flux at the right boundary
    type = SideAverageValue
    variable = jx
    boundary = right
  [../]
  [./jx_l] # side averaged flux at the left boundary
    type = SideAverageValue
    variable = jx
    boundary = left
  [../]
[]
[VectorPostprocessors]
  # The numerical values of the variables/auxvariables across the centerline
  # You can also get that directly from ParaView
  [./x_direction]
   type =  LineValueSampler
    start_point = '0 0 0'
    end_point = '${L} 0 0'
    variable = 'T jx dTdx'
    num_points = '${n_elem}'
    sort_by =  id
  [../]
[]
[Executioner] # Solver options
type = Steady
solve_type = NEWTON
petsc_options_iname = '-pc_type'# Direct solver for the linear system #
petsc_options_value = 'lu'
l_max_its = 50
l_tol = 1.0e-6
nl_max_its = 10
nl_rel_tol = 1.0e-8
[]
[Outputs]
  # file_base = Output_folder_name/Output_file_name
  file_base = 1D_linear_heat_conduction/1D_linear_heat_conduction_n_elem=${n_elem}
  # the file name with a suffix to generate a different output file for each run with a different n_elem
  # A folder named 1D_linear_heat_conduction will be created to save the output files

  [exodus] # the mesh (.e) file to be visualized with ParaView
    type = Exodus
  []
  [csv] # the CSV (.csv) file with post-processors values to be visualized with Excel or Python
    type = CSV
  []
[]
