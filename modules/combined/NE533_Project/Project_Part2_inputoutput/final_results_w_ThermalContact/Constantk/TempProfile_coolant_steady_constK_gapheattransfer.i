[Mesh]
  [./rectangle]
    type = GeneratedMeshGenerator  # Create a line, square, or cube mesh with uniformly spaced or biased elements.
    dim = 2
    nx = 1000
    ny = 100
    xmax = 0.605  # X direction boundary
    ymax = 100  # Y direction boundary
  [../]

  #[./cladding_strip]
    #type = SubdomainBoundingBoxGenerator
    #input = rectangle
    #bottom_left = '0 0 0'
    #top_right = '0.605 100.0 0'
    #block_id = 3
    #block_name = 'cladding_strip'
    #location = INSIDE
  #[../]

  [./gap_strip]
    type = SubdomainBoundingBoxGenerator
    input = rectangle
    bottom_left = '0 0 0'
    top_right = '0.505 100.0 0'
    block_id = 1
    block_name = 'gap_strip'
    location = INSIDE
  [../]
  
  [./fuel_strip]
    type = SubdomainBoundingBoxGenerator    # Changes the subdomain ID of elements either (XOR) inside or outside the specified box to the specified ID.
    input = gap_strip
    bottom_left = '0 0 0'
    top_right = '0.5 100.0 0'
    block_id = 2
    block_name = 'fuel_strip'
    location = INSIDE
  [../] 
  
  [./cladding_gap_sidesets]
    type = SideSetsBetweenSubdomainsGenerator
    input = fuel_strip
    primary_block = '0'
    paired_block = '1'
    new_boundary = 'cladding_inner'
  [../]
  
  [./fuel_gap_sidesets]
    type = SideSetsBetweenSubdomainsGenerator
    input = cladding_gap_sidesets
    primary_block = '2'
    paired_block = '1'
    new_boundary = 'fuel_outer'
  [../]

  [./gapdeletion]
    type = BlockDeletionGenerator
    input = fuel_gap_sidesets
    block = '1'
  []
  #construct_side_list_from_node_list=true 
  coord_type = RZ  # Compute a small strain in an Axisymmetric geometry
  rz_coord_axis = Y  # The axis along which the RZ coordinates are oriented. In this case, Y-axis
[] # Mesh
  

[Variables]
  [./temperature]
  [../]
[] # Variables
  

[Functions]
  [./axial_heat]
    type = ParsedFunction
    expression = '(1/(pi*0.5^2))*350*cos((1.2)*((y/50)-1))'     # Convert LHR to Q (Q=LHR/(pi*R_fuel^2)), which is the value really in governing equation # Heat Generation Rate (Linear Heat Rate, LHR) in W/(cm*K)
  []
  
  [./coolant_temp]   # Assume the coolant temperature = the temperature of the outside of the cladding
    type = ParsedFunction
    expression = '500+(1/(1.2))*((50*350)/(0.25*4200))*(sin(1.2)+sin(1.2*((y/50)-1)))'  # T_in = 500 K, Z_0 = 100 cm, C_pw = 4200 J/kg-K, mdot = 0.25 kg/s-rod
  []
[]
  
  
[Kernels]
  [./total_heat_conduction]  
    type = HeatConduction  
    variable = temperature
    block = '0 2'
  [../]
  [./fuel_heat]
    type = HeatSource
    function = axial_heat
    variable = temperature
    block = 2
  [../]
[] # Kernels
  

[ThermalContact]
  [./he_gap]
    type = GapHeatTransfer
    emissivity_primary = 0
    emissivity_secondary = 0
    variable = temperature
    primary = fuel_outer
    secondary = cladding_inner
    gap_conductivity = 0.002556
    quadrature = true
  [../]
[]
  

[BCs]
  [outside_temperature]
    type = FunctionDirichletBC
    variable = temperature
    boundary = right
    function = coolant_temp  # Unit: K
  []
  [inside_temp]
    type = NeumannBC
    variable = temperature
    boundary = left
    value = 0 
  []
[] # BCs
  

[Materials]
  [./fuel]    # Fuel Material UO2
    type = HeatConductionMaterial  # General-purpose material model for heat conduction
    thermal_conductivity = 0.03    #In W/(cm*K)
    block = 2
  [../]

  [./cladding]    # Cladding Material Zr
    type = HeatConductionMaterial
    thermal_conductivity = 0.17     #In W/(cm*K)
    block = 0
  [../]
[] # Materials


[Problem]
  type = FEProblem  # A normal (default) Problem object that contains a single NonlinearSystem and a single AuxiliarySystem object.
[] # Problem
  
[Executioner]
  type = Steady  # Steady State
  solve_type = 'NEWTON'  # Newton or Preconditioned Jacobian Free Newton Krylov
[] # Executioner
  
[Outputs]
  exodus = true
[] # Outputs