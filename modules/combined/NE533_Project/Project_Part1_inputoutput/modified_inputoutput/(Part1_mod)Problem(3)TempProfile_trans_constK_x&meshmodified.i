[Mesh]
  [./rectangle]
    type = GeneratedMeshGenerator  # Create a line, square, or cube mesh with uniformly spaced or biased elements.
    dim = 2
    nx = 800
    ny = 100
    xmax = 0.605  # X direction boundary
    ymax = 1  # Y direction boundary
  [../]

  [./cladding_strip]
    type = SubdomainBoundingBoxGenerator
    input = rectangle
    bottom_left = '0 0 0'
    top_right = '0.605 1.0 0'
    block_id = 3
    block_name = 'cladding_strip'
    location = INSIDE
  [../]

  [./gap_strip]
    type = SubdomainBoundingBoxGenerator
    input = cladding_strip
    bottom_left = '0 0 0'
    top_right = '0.505 1.0 0'
    block_id = 2
    block_name = 'gap_strip'
    location = INSIDE
  [../]
  
  [./fuel_strip]
    type = SubdomainBoundingBoxGenerator  #Changes the subdomain ID of elements either (XOR) inside or outside the specified box to the specified ID.
    input = gap_strip
    bottom_left = '0 0 0'
    top_right = '0.5 1.0 0'
    block_id = 1
    block_name = 'fuel_strip'
    location = INSIDE
  [../]

  
  coord_type = RZ  # Compute a small strain in an Axisymmetric geometry
  rz_coord_axis = Y  # The axis along which the RZ coordinates are oriented. In this case, Y-axis
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
    block = '1 2 3'
  [../]
  [./fuel_heat]
    type = HeatSource
    function = linear_heat_rate
    variable = temperature
    #value = 1.0
    block = 1
  [../]
  [./heat_conduction_time_derivative]
    type = SpecificHeatConductionTimeDerivative
    variable = temperature
    specific_heat = specific_heat
    density = density
    block = '1 2 3'
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
  [fuel_uo2]
      type = HeatConductionMaterial
      block = 1
      thermal_conductivity = 0.03
      specific_heat = 0.33
  []
  [gap_he]
      type = HeatConductionMaterial
      block = 2
      thermal_conductivity = 0.002556
      specific_heat = 5.193
  []
  [cladding_zr]
      type = HeatConductionMaterial
      block = 3
      thermal_conductivity = 0.17
      specific_heat = 0.27
  []
  [fuel_density]
      type = GenericConstantMaterial
      block = 1
      prop_names =  'density'
      prop_values = '10.97' 
  []
  [gap_density]
      type = GenericConstantMaterial
      block = 2
      prop_names =  'density'
      prop_values = '0.1785e-3' 
  []
  [clad_density]
      type = GenericConstantMaterial
      block = 3
      prop_names =  'density'
      prop_values = '6.49' 
  []
[]

[Problem]
  type = FEProblem  # A normal (default) Problem object that contains a single NonlinearSystem and a single AuxiliarySystem object.
  
[]

[Executioner]
  type = Transient


  #Preconditioned JFNK (default)
  solve_type = 'NEWTON'



  petsc_options_iname = '-pc_type -ksp_gmres_restart'
  petsc_options_value = 'lu       101'


  line_search = 'none'

  nl_rel_tol = 1e-4

  start_time = 0.0
  dt = 1
  end_time = 100
[] # Executioner

[Postprocessors]
  [./centerline_temp]
    type = AxisymmetricCenterlineAverageValue
    variable = temperature
    boundary = left
  [../]
[]

[Outputs]
  exodus = true
[] # Outputs
