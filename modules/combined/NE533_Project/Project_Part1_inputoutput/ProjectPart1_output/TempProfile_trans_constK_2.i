[Mesh]
  [./rectangle]
    type = GeneratedMeshGenerator  # Create a line, square, or cube mesh with uniformly spaced or biased elements.
    dim = 2
    nx = 1000
    ny = 100
    xmin = 0
    ymin = 0
    xmax = 0.605  # X direction boundary
    ymax = 1  # Y direction boundary
  [../]

  [./fuelandGap]
    type = SubdomainBoundingBoxGenerator  #Changes the subdomain ID of elements either (XOR) inside or outside the specified box to the specified ID.
    input = rectangle
    bottom_left = '0 0 0'
    top_right = '0.505 1.0 0'
    block_id = 1
    #block_name = 'fuel_strip'
    #location = INSIDE
  [../]

  [./fuel]
    type = SubdomainBoundingBoxGenerator
    input = fuelandGap
    bottom_left = '0 0 0'
    top_right = '0.500 1.0 0'
    block_id = 2
    #block_name = 'gap_strip'
    #location = INSIDE
  [../]

  #[./cladding_strip]
    #type = SubdomainBoundingBoxGenerator
    #input = gap_strip
    #bottom_left = '0.505 0 0'
    #top_right = '0.605 1.0 0'
    #block_id = 3
    #block_name = 'cladding_strip'
    #location = INSIDE
  #[../]

  coord_type = RZ  # Compute a small strain in an Axisymmetric geometry
  #rz_coord_axis = Y  # The axis along which the RZ coordinates are oriented. In this case, Y-axis
[] # Mesh

[Functions]
  [./linear_heat_rate]
     type = ParsedFunction
     expression = (250*exp(-((t-20)^2)/10)+150)/(pi*0.5^2)
  [../]
[]    

[Variables]
  [./temperature]
    initial_condition = 550
  [../]
[]


[Kernels]
  [./total_heat_conduction]
    type = HeatConduction
    variable = temperature
    block = '0 1 2'
  [../]
  [./fuel_heat]
    type = HeatSource
    function = linear_heat_rate
    variable = temperature
    #value = 1.0
    block = 2
  [../]
  [./heat_conduction_time_derivative]
    type = SpecificHeatConductionTimeDerivative
    variable = temperature
    specific_heat = specific_heat
    density = density
    block = '0 1 2'
  [../]
[]


[BCs]
  [outlet_temperature]
    type = DirichletBC
    variable = temperature
    boundary = right
    value = 550 # (K)   # The T_co value
  []
  [inlet_temperature]
    type = NeumannBC
    variable = temperature
    boundary = left
    value = 0 # (K)
  []
    
[]

[Materials]
  [uotwo]
      type = HeatConductionMaterial
      block = 2
      thermal_conductivity = 0.03
      specific_heat = 0.33
  []
  [helium]
      type = HeatConductionMaterial
      block = 1
      thermal_conductivity = 0.002556
      specific_heat = 5.188
  []
  [zirc]
      type = HeatConductionMaterial
      block = 0
      thermal_conductivity = 0.17
      specific_heat = 0.35
  []
  [uod]
      type = GenericConstantMaterial
      block = 2
      prop_names =  'density'
      prop_values = '10.98' 
  []
  [hed]
      type = GenericConstantMaterial
      block = 1
      prop_names =  'density'
      prop_values = '0.178e-3' 
  []
  [claddd]
      type = GenericConstantMaterial
      block = 0
      prop_names =  'density'
      prop_values = '6.5' 
  []
[]


[Problem]
  type = FEProblem  # A normal (default) Problem object that contains a single NonlinearSystem and a single AuxiliarySystem object.
  
[]

[Executioner]
  type = Transient  # Transient State
  #Preconditioned JFNK (default)
  solve_type = 'NEWTON'  # Newton or Preconditioned Jacobian Free Newton Krylov
  start_time = 0.0
  dt = 1
  end_time = 100  # As given, t = 100. Due to the divergence at t = 53, we take t = 52
  nl_rel_tol = 1e-10
  nl_abs_tol = 1e-10
  petsc_options_iname = '-pc_type -pc_hypre_type'
  petsc_options_value = 'hypre boomeramg'
[] # Executioner

[Postprocessors]

[]

[Outputs]
  exodus = true
[] # Outputs