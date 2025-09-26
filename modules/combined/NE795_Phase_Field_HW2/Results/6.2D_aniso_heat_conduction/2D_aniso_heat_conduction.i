# solves Heat/Diffusion Eqn in 2D with anisotropic conductivity/diffusivity tensor
n_elem = 100 # Number of Elements
L = 1.0 # Domain length
T_l = 1.0 # Temperature at the left boundary
T_r = 2.0 # Temperature at the right boundary
[Mesh]
  type = GeneratedMesh
  dim = 2
  nx = '${n_elem}'
  ny = '${n_elem}'
  nz = 0
  xmin = 0
  xmax = '${L}'
  ymin = 0
  ymax = '${L}'
  elem_type = QUAD4 # 1st order 2D Quad element (4 Nodes)
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
  [./dTdy]
    order = SECOND
    family = MONOMIAL
  [../]
  # conductivity tensor components
  [./k_xx]
    order = SECOND
    family = MONOMIAL
  [../]
  [./k_yy]
    order = SECOND
    family = MONOMIAL
  [../]
  [./k_xy]
    order = SECOND
    family = MONOMIAL
  [../]

  # the heat flux
  [./jx]
    order = SECOND
    family = MONOMIAL
  [../]
  [./jy]
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
  [./dTdy]
    type = VariableGradientComponent
    variable = dTdy
    gradient_variable = T
    component = y
  [../]
  [./k_xx]
    type = MaterialRealTensorValueAux
      property = k
       column = 0
       row = 0
      variable = k_xx
  [../]
  [./k_yy]
    type = MaterialRealTensorValueAux
      property = k
       column = 1
       row = 1
      variable = k_yy
  [../]
  [./k_xy]
    type = MaterialRealTensorValueAux
      property = k
       column = 1
       row = 0
    variable = k_xy
  [../]
  [./jx]
    type = ParsedAux
    variable = jx
    coupled_variables = 'k_xx k_xy dTdx dTdy'
    expression = '-(k_xx*dTdx+k_xy*dTdy)'
  [../]
  [./jy]
    type = ParsedAux
    variable = jy
    coupled_variables = 'k_yy k_xy dTdx dTdy'
      # "args is now deprecated, use coupled_variables instead "
    expression = '-(k_yy*dTdy+k_xy*dTdx)'
  [../]

[]

[Kernels]
  [./heat_diffusion] # with anisotropic conductivity/diffusivity tensor
    type = MatAnisoDiffusion
    diffusivity = k
    variable = T
  [../]

[]

[Materials]
  [./k] # anisotropic conductivity/diffusivity tensor
    type = ConstantAnisotropicMobility

    #original
    #tensor = '0.750 0.500 0.0    
    #          0.500 0.750 0.0
    #          0.0   0.0   0.0'
    #Case 1
    #tensor = '1.0 0.9 0.0        
    #          0.9 1.0 0.0
    #          0.0 0.0 0.0'
    #Case 2
    #tensor = '0.9 1.0 0.0        
    #          1.0 1.0 0.0
    #          0.0 0.0 0.0'
    #Case 3
    tensor = '0.75 0.25 0.0
              0.25 0.75 0.0
              0.0  0.0  0.0'
    M_name = k  # name of the mobility/conductivity tensor
  [../]
[]

[BCs]
  [./T_left]
    type = DirichletBC
    variable = 'T'
    boundary = 'left'
    value = ${T_l}
    preset = false
  [../]
  [./T_right]
    type = DirichletBC
    variable = 'T'
    boundary = 'right'
    value = ${T_r}
    preset = false
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

[]

[VectorPostprocessors]
  [./line_values]
   type =  LineValueSampler
    start_point = '0 0 0'
    end_point = '${L} 0 0'
    variable = 'T dTdx dTdy jx jy'
    num_points = ${n_elem}
    sort_by =  id
  [../]
[]
[Executioner]
  type = Steady
  solve_type = 'NEWTON'
  line_search = none
  petsc_options_iname = '-pc_type'
  petsc_options_value = 'lu'
  l_max_its = 100
  l_tol = 1.0e-6
[]

[Outputs]
  # file_base = Output_folder_name/Output_file_name
  file_base = 2D_aniso_heat_conduction/2D_aniso_heat_conduction
  exodus = true
  csv = true
[]
