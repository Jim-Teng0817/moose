
[Mesh]
  [fuel_strip]          # Default block ID = 0
    type = GeneratedMeshGenerator
    dim = 2
    nx = 150
    ny = 1000
    xmin = 0
    xmax = 0.5
    ymin = 0
    ymax = 100
    boundary_name_prefix = fuel_boundary
  []
  # [fuel]
  #   type = SubdomainIDGenerator
  #   input = fuel_strip
  #   subdomain_id = 2
  # []
  [cladding_strip]
    type = GeneratedMeshGenerator
    dim = 2
    nx = 30
    ny = 1000
    xmin = 0.505
    xmax = 0.605
    ymin = 0
    ymax = 100
    boundary_name_prefix = cladding_boundary
    boundary_id_offset = 4
  []
  [cladding]
    type = SubdomainIDGenerator
    input = cladding_strip
    subdomain_id = 1
  []
  [collect_meshes]
    type = MeshCollectionGenerator
    inputs = 'fuel_strip cladding'
  []
  patch_update_strategy = iteration
  coord_type = RZ  # Compute a small strain in an Axisymmetric geometry
  rz_coord_axis = Y  # The axis along which the RZ coordinates are oriented. In this case, Y-axis
[] # Mesh


[GlobalParams]
  displacements = 'disp_x disp_y'
  block = '0 1'
[]


[Variables]
  [temperature]
    #initial_condition = 500
  []

  [Tlm]
    block = 'PCMI_secondary_subdomain'
  []
[] # Variables


[Functions]
  [axial_heat]
    type = ParsedFunction
    expression = '(1/(pi*0.5^2))*350*cos((1.2)*((y/50)-1))'     # Convert LHR to Q (Q=LHR/(pi*R_fuel^2)), which is the value really in governing equation # Heat Generation Rate (Linear Heat Rate, LHR) in W/(cm*K)
  []
  
  #[coolant_temp]   # Assume the coolant temperature = the temperature of the outside of the cladding
    #type = ParsedFunction
    #expression = '500+(1/(1.2))*((50*350)/(0.25*4200))*(sin(1.2)+sin(1.2*((y/50)-1)))'  
    ## T_in = 500 K, Z_0 = 100 cm, C_pw = 4200 J/kg-K, mdot = 0.25 kg/s-rod
  #[]

  [cladding_outer_temp]
    type = ParsedFunction
    expression = '(500+(1/(1.2))*((50*350)/(0.25*4200))*(sin(1.2)+sin(1.2*((y/50)-1)))) + ((350)/(2*pi*0.5*2.65))'
    # h_cool = 2.65 W/(cm^3 * K)
  []
[]


[Kernels]
  [total_heat_conduction]  
    type = HeatConduction  
    variable = temperature
    #block = '0 1'
  []
  [fuel_heat]
    type = HeatSource
    function = axial_heat
    variable = temperature
    block = '0'
  []
  [heat_conduction_time_derivative]
    type = HeatConductionTimeDerivative
    variable = temperature
  []
[] # Kernels


# [ThermalContact]
#   [he_gap]
#     type = GapHeatTransfer
#     emissivity_primary = 0
#     emissivity_secondary = 0
#     variable = temperature
#     primary = fuel_outer
#     secondary = cladding_inner
#     gap_conductivity = 0.002556  # Assume the thermal conductivity of the gap is constant
#     quadrature = true
#   []
# []


[Contact]
  [PCMI]
    primary = 'cladding_boundary_left'
    secondary = 'fuel_boundary_right'
    model = frictionless
    formulation = mortar
    c_normal = 1e+10
  []
[] # Contact

[Constraints]
  # thermal contact constraint
  [Tlm]
    type = GapConductanceConstraint
    variable = Tlm
    secondary_variable = temperature
    use_displaced_mesh = true
    k = 0.002556
    primary_boundary = 'cladding_boundary_left'
    primary_subdomain = PCMI_secondary_subdomain
    secondary_boundary = 'fuel_boundary_right'
    secondary_subdomain = PCMI_primary_subdomain
  []
[] # Constraints

[BCs]
  [outside_temperature]
    type = FunctionDirichletBC
    variable = temperature
    boundary = 'cladding_boundary_right'
    function = cladding_outer_temp  # Unit: K
  []
  [center_temp]
    type = NeumannBC
    variable = temperature
    boundary = 'fuel_boundary_left'
    value = 0 
  []
  [axis_fixed]
    type = DirichletBC
    variable = disp_x
    boundary = 'fuel_boundary_left'
    value = 0
  []
  [bottom_top_fixed_y]
    type = DirichletBC
    variable = disp_y
    boundary = 'fuel_boundary_bottom cladding_boundary_bottom fuel_boundary_top cladding_boundary_top'
    value = 0
  []
  # [bottom_fixed_y]
  #   type = DirichletBC
  #   variable = disp_y
  #   boundary = 'fuel_boundary_bottom cladding_boundary_bottom'
  #   value = 0
  # []
  # [top_fixed_x]
  #   type = DirichletBC
  #   variable = disp_x
  #   boundary = 'fuel_boundary_top cladding_boundary_top'
  #   value = 0
  # []
  # [top_fixed_y]
  #   type = DirichletBC
  #   variable = disp_y
  #   boundary = 'fuel_boundary_top cladding_boundary_top'
  #   value = 0
  # []
[] # BCs


[Physics/SolidMechanics/QuasiStatic]
  [all]
    add_variables = true
    strain = FINITE   # For, Steady State solver use SMALL (fit to our problem) NOT FINITE
    eigenstrain_names = 'thermal irrswelling'
    generate_output = 'stress_xx stress_yy vonmises_stress strain_xx strain_yy'
    volumetric_locking_correction = true
    temperature = temperature
  [] 
[]


[Materials]
  # From Lec3
  [fuel]    # Fuel Material UO2
    type = HeatConductionMaterial  # General-purpose material model for heat conduction
    temp = temperature
    thermal_conductivity_temperature_function = 1/(3.8+0.0217*t)   #In W/(cm*K), Temperature Dependent K for fuel_strip
    block = 0
    specific_heat = 0.33
  []

  [cladding]    # Cladding Material Zr
    type = HeatConductionMaterial
    thermal_conductivity = 0.17     #In W/(cm*K), remain constant
    block = 1
    specific_heat = 0.35
  []

  [fuel_density]
    type = GenericConstantMaterial
    block = 0
    prop_names =  'density'
    prop_values = '10.97' 
  []

  [clad_density]
    type = GenericConstantMaterial
    block = 1
    prop_names =  'density'
    prop_values = '6.49' 
  []
  
  # From Lec5
  [elasticity_fuel]
    type = ComputeIsotropicElasticityTensor
    block = 0
    youngs_modulus = 200e9
    poissons_ratio = 0.345
  []
  [elasticity_cladding]  
    type = ComputeIsotropicElasticityTensor
    block = 1
    youngs_modulus = 80e9
    poissons_ratio = 0.41
  []
  # From Lec6
  [expansion_fuel]
    type = ComputeThermalExpansionEigenstrain
    block = 0
    eigenstrain_name = thermal
    temperature = temperature
    thermal_expansion_coeff = 11e-6   # in 1/K
    stress_free_temperature = 300     # Assume T_ref = 300 K
  []
  [expansion_cladding]
    type = ComputeThermalExpansionEigenstrain
    block = 1
    eigenstrain_name = thermal
    temperature = temperature
    thermal_expansion_coeff = 7.1e-6
    stress_free_temperature = 300     # Assume T_ref = 300 K
  []
  [stress]
    type = ComputeFiniteStrainElasticStress   
    # For, Steady State solver use ComputeLinearElasticStress NOT ComputeFiniteStrainElasticStress
  []
  [irrdiation-induced_swelling]
    type = ParsedMaterial
    property_name = irraidation_swelling
    #block = '0 1'
    coupled_variables = 'temperature'

    expression = '5.577e-2*0.059+1.96e-28*0.059*(2800-temperature)^(11.73)*exp(-0.0162*(2800-temperature))*exp(-17.8*0.059)'
    # expression = '1.747*10^-30*((2800-temperature)^11.73) * (exp(-0.016*(2800-temperature)))+ (3.14998*10^-2)'
    # Assume no densification, so we only consider the strain from solid fission product and gas fission product
    # delta_rho = 0.01, beta_D(burnup of Desification) = 0.005 (FIMA), beta(burnup) = 9.87*10^-4 = Fission Rate * time/N_u
    # Fission Rate = 2e13 f/(cm^3 * s), time = 2 (weeks), N_u(number density of U) = 2.45*10^22 (U/cm^3)
    # density of UO2 Fuel = 10.97 (g/cm^3)

    #expression = '4.763*10^-33*((2800-temperature)^11.73) * (exp(-0.016*(2800-temperature)))+ (6.038*10^-4)'
    # Assume no densification take higher burnup to time = 2 years, beta(burnup) = 5.149*10^-2
  []
  [volumetric_eigenstrain]
    type = ComputeVolumetricEigenstrain
    volumetric_materials = irraidation_swelling
    eigenstrain_name = irrswelling
    args = ''
  []
  # [volumetric_change]
  #   type = GenericFunctionMaterial
  #   block = 0
  #   prop_names = volumetric_change
  #   prop_values = t
  # []

[] # Materials

[Preconditioning]
  [smp]
    type = SMP
    full = true
  []
[] #Preconditioning


[Executioner]
  type = Transient
  solve_type = PJFNK
  line_search = none
  automatic_scaling = true
  petsc_options_iname = '-pc_type -pc_factor_shift_type'
  petsc_options_value = 'lu       nonzero              '
  snesmf_reuse_base = false
  end_time = 36
  #start_time = 0
  dt = 1
  steady_state_detection = true
  steady_state_tolerance = 1e-4
  nl_rel_tol = 1e-6
  nl_abs_tol = 1e-10
[]

[Outputs]
  exodus = true
[] # Outputs
