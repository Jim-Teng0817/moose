[Mesh]
  [./rectangle]
    type = GeneratedMeshGenerator  # Create a line, square, or cube mesh with uniformly spaced or biased elements.
    dim = 2
    nx = 1000
    ny = 100
    xmax = 0.605  # X direction boundary
    ymax = 1  # Y direction boundary
  [../]

  [./fuel_strip]
    type = SubdomainBoundingBoxGenerator    # Changes the subdomain ID of elements either (XOR) inside or outside the specified box to the specified ID.
    input = rectangle
    bottom_left = '0 0 0'
    top_right = '0.5 1.0 0'
    block_id = 1
    block_name = 'fuel_strip'
    location = INSIDE
  [../]

  [./gap_strip]
    type = SubdomainBoundingBoxGenerator
    input = fuel_strip
    bottom_left = '0.5 0 0'
    top_right = '0.505 1.0 0'
    block_id = 2
    block_name = 'gap_strip'
    location = INSIDE
  [../]

  [./cladding_strip]
    type = SubdomainBoundingBoxGenerator
    input = gap_strip
    bottom_left = '0.505 0 0'
    top_right = '0.605 1.0 0'
    block_id = 3
    block_name = 'cladding_strip'
    location = INSIDE
  [../]
  
  coord_type = RZ  # Compute a small strain in an Axisymmetric geometry
  rz_coord_axis = Y  # The axis along which the RZ coordinates are oriented. In this case, Y-axis
[] # Mesh

[Variables]
  [./temperature]
  [../]
[] # Variables


[Kernels]
  [./total_heat_conduction]  
    type = HeatConduction  
    variable = temperature
    block = '1 2 3'
  [../]
  [./fuel_heat]
    type = HeatSource
    value = 445.634  # Convert LHR to Q (Q=LHR/(pi*R_fuel^2)), which is the value really in governing equation # Heat Generation Rate (Linear Heat Rate, LHR) in W/(cm*K)
    variable = temperature
    block = 1
  [../]
[] # Kernels


[BCs]
  [outside_temperature]
    type = DirichletBC
    variable = temperature
    boundary = right
    value = 550  # Unit: K
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
    block = 1
  [../]
  [./gap]    # Gap Material Pure He
    type = HeatConductionMaterial     
    thermal_conductivity = 0.002556  #@ Temperature = T_ci = 615.534 K, in W/(cm*K)
    block = 2
  [../]
  [./cladding]    # Cladding Material Zr
    type = HeatConductionMaterial
    thermal_conductivity = 0.17     #In W/(cm*K)
    block = 3
  [../]
[] # Materials

[Problem]
  type = FEProblem  # A normal (default) Problem object that contains a single NonlinearSystem and a single AuxiliarySystem object.

[] # Problem

[Executioner]
  type = Steady  # Steady State
  #Preconditioned JFNK (default)  
  solve_type = 'NEWTON'  # Newton or Preconditioned Jacobian Free Newton Krylov
[] # Executioner

[Outputs]
  exodus = true
[] # Outputs