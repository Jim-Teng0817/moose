
# The reference example of this input file is from the MOOSE website:
# https://mooseframework.inl.gov/modules/combined/tutorials/introduction/step02.html

[GlobalParams]
  displacements = 'disp_x disp_y'
  block = '0 1'
[]

[Problem]
  type = FEProblem
[]

[Mesh]
  # inner cylinder
  [fuel_rod]
    type = GeneratedMeshGenerator
    dim = 2
    nx = 120
    ny = 1000
    xmin = 0
    xmax = 0.500
    ymin = 0
    ymax = 100
    boundary_name_prefix = fuel
  []

  # shell with subdomain ID 1
  [cladding_strip]
    type = GeneratedMeshGenerator
    dim = 2
    nx = 24
    ny = 1000
    xmin = 0.505
    xmax = 0.605
    ymin = 0
    ymax = 100
    boundary_name_prefix = clad
    boundary_id_offset = 4
  []
  [cladding]
    type = SubdomainIDGenerator
    input = cladding_strip
    subdomain_id = 1
  []

  [collect_meshes]
    type = MeshCollectionGenerator
    inputs = 'fuel_rod cladding'
  []
  coord_type = RZ
  patch_update_strategy = iteration
[]

[Variables]
  # temperature field variable (first order Lagrange by default)
  [T]
  []
  # temperature lagrange multipliers
  [Tlm]
    block = 'gap_secondary_subdomain'
  []
[]

[Functions]
  [axial_heat]
    type = ParsedFunction
    expression = '(1/(pi*0.5^2))*350'     # For this part, I used constant LHR (without varying axially) for the fuel heat source.
    # Convert LHR to Q (Q=LHR/(pi*R_fuel^2)), which is the value really in governing equation # Heat Generation Rate (Linear Heat Rate, LHR) in W/(cm*K)
  []
  
  #[coolant_temp]   # Assume the coolant temperature = the temperature of the outside of the cladding
    #type = ParsedFunction
    #expression = '500+(1/(1.2))*((50*350)/(0.25*4200))*(sin(1.2)+sin(1.2*((y/50)-1)))'  
    ## T_in = 500 K, Z_0 = 100 cm, C_pw = 4200 J/kg-K, mdot = 0.25 kg/s-rod
  #[]

  [cladding_outer_temp]
    type = ParsedFunction
    expression = '(500+(1/(1.2))*((50*350)/(0.25*4200))*(sin(1.2)+sin(1.2*((y/50)-1)))) + ((350)/(2*pi*0.5*2.65))'
    # For this part, I used constant LHR (without varying axially) for the fuel heat source.
    # h_cool = 2.65 W/(cm^3 * K)
  []
[]

[Kernels]
  [total_heat_conduction] 
    type = HeatConduction
    variable = T
  []
  [fuel_heat]
    type = HeatSource
    variable = T
    function = axial_heat
    block = 0
  []
  [heat_conduction_time_derivative]
    type = HeatConductionTimeDerivative
    variable = T
  []
[]

[Physics/SolidMechanics/QuasiStatic]
  [all]
    add_variables = true
    strain = FINITE
    eigenstrain_names = 'thermal swelling'
    generate_output = 'vonmises_stress stress_xx strain_xx stress_yy strain_yy'
    volumetric_locking_correction = true
    temperature = T
  []
[]

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
  [gap]
    primary = clad_left
    secondary = fuel_right
    model = frictionless
    formulation = mortar
    c_normal = 1e+06
  []
[]

[Constraints]
  # thermal contact constraint
  [Tlm]
    type = GapConductanceConstraint
    variable = Tlm
    secondary_variable = T
    use_displaced_mesh = true
    k = 0.002556
    primary_boundary = clad_left
    primary_subdomain = gap_secondary_subdomain
    secondary_boundary = fuel_right
    secondary_subdomain = gap_primary_subdomain
  []
[]

[BCs]
  [outside_temperature]
    type = FunctionDirichletBC
    variable = T
    boundary = 'clad_right'
    function = cladding_outer_temp
  []
  [center_temp]
    type = NeumannBC
    variable = T
    boundary = 'fuel_left'
    value = 0
  []
  [axis_fixed]
    type = DirichletBC
    variable = disp_x
    boundary = 'fuel_left'
    value = 0
  []
  [bottom_top_fixed_y]
    type = DirichletBC
    variable = disp_y
    boundary = 'fuel_bottom clad_bottom fuel_top clad_top'
    value = 0
  []
[]

[Materials]
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

  [stress]
      type = ComputeFiniteStrainElasticStress
      #block = 2
  []

  # thermal properties
  # From Lec3
  [fuel]    # Fuel Material UO2
    type = HeatConductionMaterial
    temp = T
    thermal_conductivity_temperature_function = '(1/(3.8+0.0217*t))'   #In W/(cm*K), Temperature Dependent K for fuel_strip
    block = 0
    specific_heat = 0.33
  []
  [cladding]    # Cladding Material Zr
    type = HeatConductionMaterial
    block = 1
    thermal_conductivity = 0.17     #In W/(cm*K), remain constant
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
  [expansion_fuel]
    type = ComputeThermalExpansionEigenstrain
    block = 0
    eigenstrain_name = thermal
    temperature = T
    thermal_expansion_coeff = 11e-6   # in 1/K
    stress_free_temperature = 300     # Assume T_ref = 300 K
  []
  [expansion_cladding]
    type = ComputeThermalExpansionEigenstrain
    block = 1
    eigenstrain_name = thermal
    temperature = T
    thermal_expansion_coeff = 7.1e-6
    stress_free_temperature = 300     # Assume T_ref = 300 K
  []
  [combined_swelling]
    type = ParsedMaterial
    property_name = combined_swelling
    coupled_variables = 'T'
    # expression = '1.747e-30*(2800-T)^(11.73)*exp(-0.0162*(2800-T))*exp(-17.8*0.059)+(3.14998e-2)'
    # Assume no densification, so we only consider the strain from solid fission product and gas fission product
    # delta_rho = 0.01, beta_D(burnup of Desification) = 0.005 (FIMA), beta(burnup) = 9.87*10^-4 = Fission Rate * time/N_u
    # Fission Rate = 2e13 f/(cm^3 * s), time = 2 (weeks), N_u(number density of U) = 2.45*10^22 (U/cm^3)
    # density of UO2 Fuel = 10.97 (g/cm^3)
    expression = '4.763*10^-33*((2800-T)^11.73) * (exp(-0.016*(2800-T)))+ (6.038*10^-4)'
    # Assume no densification take higher burnup to time = 2 years, beta(burnup) = 5.149*10^-2
  []
  [volumetric_eigenstrain]
    type = ComputeVolumetricEigenstrain
    volumetric_materials = combined_swelling
    eigenstrain_name = swelling
    args = ''
  []
[]

[Preconditioning]
  [smp]
    type = SMP
    full = true
  []
[]


[Executioner]
  type = Transient
  solve_type = PJFNK
  line_search = none
  automatic_scaling = true
  petsc_options_iname = '-pc_type -pc_factor_shift_type'
  petsc_options_value = 'lu       nonzero              '
  snesmf_reuse_base = false

  end_time = 40
  dt = 1

  steady_state_detection = true
  steady_state_tolerance = 1e-4
  nl_rel_tol = 1e-6
  nl_abs_tol = 1e-10

  # [Predictor]
  #   type = SimplePredictor
  #   scale = 0.5
  # []
[]

[Outputs]
  exodus = true
[]
