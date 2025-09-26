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
  [../]
  #construct_side_list_from_node_list=true 
  coord_type = RZ  # Compute a small strain in an Axisymmetric geometry
  rz_coord_axis = Y  # The axis along which the RZ coordinates are oriented. In this case, Y-axis
[] # Mesh


[GlobalParams]
  displacements = 'disp_x disp_y'
  block = '0 2'
[]


[Variables]
  [./temperature]
  [../]
[] # Variables


[Functions]
  [./axial_heat]
    type = ParsedFunction
    expression = '(1/(pi*0.5^2))*350*cos((1.2)*((y/50)-1))'     # Convert LHR to Q (Q=LHR/(pi*R_fuel^2)), which is the value really in governing equation # Heat Generation Rate (Linear Heat Rate, LHR) in W/(cm*K)
  [../]
  
  #[./coolant_temp]   # Assume the coolant temperature = the temperature of the outside of the cladding
    #type = ParsedFunction
    #expression = '500+(1/(1.2))*((50*350)/(0.25*4200))*(sin(1.2)+sin(1.2*((y/50)-1)))'  
    ## T_in = 500 K, Z_0 = 100 cm, C_pw = 4200 J/kg-K, mdot = 0.25 kg/s-rod
  #[../]

  [./cladding_outer_temp]
    type = ParsedFunction
    expression = '(500+(1/(1.2))*((50*350)/(0.25*4200))*(sin(1.2)+sin(1.2*((y/50)-1)))) + ((350)/(2*pi*0.5*2.65))'
    # h_cool = 2.65 W/(cm^3 * K)
  [../]
[]


[Kernels]
  [./total_heat_conduction]  
    type = ADHeatConduction  
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
    gap_conductivity = 0.002556  # Assume the thermal conductivity of the gap is constant
    quadrature = true
  [../]
[]


[Contact]
  [PCMI]
    primary = fuel_outer
    secondary = cladding_inner
    model = frictionless
    formulation = mortar
  []
[] # Contact

[BCs]
  [outside_temperature]
    type = FunctionDirichletBC
    variable = temperature
    boundary = right
    function = cladding_outer_temp  # Unit: K
  []
  [inside_temp]
    type = NeumannBC
    variable = temperature
    boundary = left
    value = 0 
  []
  [./axial_fixed]
    type = DirichletBC
    variable = disp_x
    boundary = left
    value = 0
  [../]
  [./bottom_fixed_x]
    type = DirichletBC
    variable = disp_x
    boundary = bottom
    value = 0
  [../]
  [./bottom_fixed_y]
    type = DirichletBC
    variable = disp_y
    boundary = bottom
    value = 0
  [../]
  [./top_fixed_x]
    type = DirichletBC
    variable = disp_x
    boundary = top
    value = 0
  [../]
  [./top_fixed_y]
    type = DirichletBC
    variable = disp_y
    boundary = top
    value = 0
  [../]
[] # BCs


[Physics/SolidMechanics/QuasiStatic]
  [all]
    add_variables = true
    strain = SMALL    # For, Steady State solver use SMALL (fit to our problem) NOT FINITE
    automatic_eigenstrain_names = true
    generate_output = 'stress_xx stress_yy stress_zz vonmises_stress hydrostatic_stress strain_xx strain_yy strain_zz'
    decomposition_method = EigenSolution    #Necessary for exact solution
  [] 
[]


[Materials]
  [./fuel]    # Fuel Material UO2
    type = ADHeatConductionMaterial  # General-purpose material model for heat conduction
    temp = temperature
    thermal_conductivity_temperature_function = 1/(3.8+0.0217*t)   #In W/(cm*K), Temperature Dependent K for fuel_strip
    block = 2
  [../]

  [./cladding]    # Cladding Material Zr
    type = ADHeatConductionMaterial
    thermal_conductivity = 0.17     #In W/(cm*K), remain constant
    block = 0
  [../]
  
  # From Lec5
  [elasticity_fuel]
    type = ComputeIsotropicElasticityTensor
    block = 2
    youngs_modulus = 200e9
    poissons_ratio = 0.345
  []
  [elasticity_cladding]  
    type = ComputeIsotropicElasticityTensor
    block = 0
    youngs_modulus = 80e9
    poissons_ratio = 0.41
  []
  # From Lec6
  [expansion_fuel]
    type = ADComputeThermalExpansionEigenstrain
    block = 2
    temperature = temperature
    thermal_expansion_coeff = 11e-5   # in 1/K  originally 11e-6
    stress_free_temperature = 300     # Assume T_ref = 300 K
    eigenstrain_name = thermal_expansion_fuel
  []
  [expansion_cladding]
    type = ADComputeThermalExpansionEigenstrain
    block = 0
    temperature = temperature
    thermal_expansion_coeff = 7.1e-6
    stress_free_temperature = 300     # Assume T_ref = 300 K
    eigenstrain_name = thermal_expansion_cladding
  []
  [stress]
    type = ComputeLinearElasticStress    
    # For, Steady State solver use ComputeLinearElasticStress NOT ComputeFiniteStrainElasticStress
  []
  [./irrdiation-induced_swelling]
    type = ADParsedMaterial
    property_name = irraidation_swelling
    block = 2
    coupled_variables = 'temperature'

    # expression = '1.747*10^-30*((2800-temperature)^11.73) * (exp(-0.016*(2800-temperature)))+ (3.14998*10^-2)'
    # Assume no densification, so we only consider the strain from solid fission product and gas fission product
    # delta_rho = 0.01, beta_D(burnup of Desification) = 0.005 (FIMA), beta(burnup) = 9.87*10^-4 = Fission Rate * time/N_u
    # Fission Rate = 2e13 f/(cm^3 * s), time = 2 (weeks), N_u(number density of U) = 2.45*10^22 (U/cm^3)
    # density of UO2 Fuel = 10.97 (g/cm^3)

    expression = '4.763*10^-33*((2800-temperature)^11.73) * (exp(-0.016*(2800-temperature)))+ (6.038*10^-4)'
    # Assume no densification take higher burnup to time = 2 years, beta(burnup) = 5.149*10^-2

    #expression = '3.3605*10^-39*((2800-temperature)^11.73) * (exp(-0.016*(2800-temperature)))+ (0.0787494)'
    # Assume no densification take higher burnup to time = 5 years, beta(burnup) = 0.1287
  [../]
  [volumetric_eigenstrain]
    type = ADComputeVolumetricEigenstrain
    block = 2
    volumetric_materials = volumetric_change
    eigenstrain_name = eigenstrain
  []
  [volumetric_change]
    type = ADGenericFunctionMaterial
    block = 2
    prop_names = volumetric_change
    prop_values = t
  []

[] # Materials

[Problem]
  type = FEProblem  
  # A normal (default) Problem object that contains a single NonlinearSystem and a single AuxiliarySystem object.
[] # Problem


[Executioner]
  type = Steady
  solve_type = NEWTON
  petsc_options_iname = '-pc_type'
  petsc_options_value = 'lu'
  automatic_scaling = true
  #end_time = 2
  #dt = 0.2
[]

[Outputs]
  exodus = true
[] # Outputs
