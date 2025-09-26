
[Mesh]
  [2D_annular]
    type = AnnularMeshGenerator
    rmax = 0.004
    rmin = 0
    nr = 40
    nt = 100
  []
  [sideline]
    type = ExtraNodesetGenerator
    input = 2D_annular
    new_boundary = sideline
    coord = '0.004 0 0'
  []
  [centerline]
    type = ExtraNodesetGenerator
    input = sideline
    new_boundary = centerline
    coord = '0 0 0'
  []

[]

[Variables]
  # We solve for the temperature and the displacements
  [./T]
    initial_condition = 700
    family = LAGRANGE
    order = FIRST
  [../]
[]

[AuxVariables]
  [./thermal_conductivity]
    order = CONSTANT
    family = MONOMIAL
  [../]
  [./analytical_soln]
    order = FIRST
    family = MONOMIAL
  [../]
[]

[AuxKernels]
    [./thermal_conductivity]
    type =  MaterialRealAux
    variable = thermal_conductivity
    property = k
  [../]
  [./analytical_soln]
    type = ParsedAux
    variable = analytical_soln
    expression = '3.98e8/(4*2.8)*0.004^2*(1-(x^2+y^2)/0.004^2)+700'
    use_xyzt =  true
  [../]
[]

[Kernels]

  [./symbolic_diffusion_kernel]
    type = MatDiffusion   # evaluate the divergence of a flux
    variable = T
    diffusivity = k
    # the thermal_conductivity/ diffusion_coefficient and their derivatives
    # can be symbolically evaluated form a DerivativeParsedMaterial
    # to be defined under the Materials block if temperature-dependent
  [../]
  [./heat_source]
    type = HeatSource
    variable = T
    value = 7.56e1 
  [../]
  [./time_Derivative]
    type = TimeDerivative
    variable = T
  [../]
[]
[BCs]

[./side_T] #Temperature on outer edge 
  type = DirichletBC
  #preset = false
  variable = T
  value = 700
  boundary = rmax
[../]

[]

[Materials]
  [./thermal_conductivity]
    type = DerivativeParsedMaterial
    property_name = k
    expression = 2.8/5265600
    derivative_order = 1
    #expression = 'a0:=0.1148;a1:=0.0035;b0:=0.0002474;b1:=-8e-7;c:=0.0132;d:=0.00188; ((1/((a0+a1*75)+(b0+b1*75)*(T-273.15))+c*exp(d*(T-273.15))))/5265600' 
    #coupled_variables = 'T'
  [../]
[]

[Preconditioning]
  [./smp]
    type = SMP
    full = true
  [../]
[]

[Postprocessors]
  [./temperature]
    type = ElementAverageValue
    variable = T
  [../]
[]


[Executioner]
  type = Transient
  solve_type = PJFNK
  petsc_options_iname = '-pc_type -pc_factor_mat_solving_package'
  petsc_options_value = 'lu superlu_dist'
  nl_rel_tol = 1e-7
  nl_abs_tol = 1e-8
  l_tol = 1e-3
  l_max_its = 30
  nl_max_its = 10

  [./TimeStepper]
    type = IterationAdaptiveDT
    dt = 1e-4
    growth_factor = 1.1
    cutback_factor = 0.7
    optimal_iterations = 7
  [../]
  num_steps = 2000
[]

[Outputs]
  file_base = uo2thermal_transient
  exodus = true
  #csv = true
  #interval = 2

[]
