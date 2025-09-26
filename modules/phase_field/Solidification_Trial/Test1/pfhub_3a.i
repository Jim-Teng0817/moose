#
# PF-HUB
# https://pages.nist.gov/pfhub/simulations/3a.1/
#

[Mesh]
  type = GeneratedMesh
  dim = 2
  xmax = 960
  ymax = 960
  nx = 23
  ny = 23
  uniform_refine = 2
[]

[Variables]
  [./phi]
    [./InitialCondition]
      type = SmoothCircleIC
      variable = phi
      x1 = 0
      y1 = 0
      radius = 8
      invalue = 1
      outvalue = -1
      int_width = 4
    [../]
  [../]
  [./U]
    initial_condition = -0.3
    scaling = 1e6
  [../]
[]

[AuxVariables]
  [./f]
    order = CONSTANT
    family = MONOMIAL
  [../]
  [./solid]
    order = CONSTANT
    family = MONOMIAL
  [../]
[]

[Kernels]
  [./dUdt]
    type = TimeDerivative
    variable = U
  [../]
  [./Udiffusion]
    type = MatDiffusion
    variable = U
    D_name = D
  [../]
  [./Ucoupledphi]
    type = CoefCoupledTimeDerivative
    variable = U
    v = phi
    coef = -0.5
  [../]

  [./dphidt]
    type = TimeDerivative
    variable = phi
  [../]
  [./phibulk]
    type = AllenCahn
    variable = phi
    f_name = f_chem
    mob_name = tau_inv
    args = 'U'
  [../]
  [./phi_scary]
    type = ACInterfaceKobayashi1
    variable = phi
    eps_name = eps
    mob_name = tau_inv
  [../]
  [./phi_alsoscary]
    type = ACInterfaceKobayashi2
    variable = phi
    eps_name = eps
    mob_name = tau_inv
  [../]
[]

[AuxKernels]
  [./f_aux]
    type = TotalFreeEnergy
    variable = f
    kappa_names = kappa
    f_name = f_chem
    interfacial_vars = phi
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
  [./solid]
    type = ParsedAux
    variable = solid
    args = 'phi'
    function = '0.5*(phi+1)'
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
[]

[Materials]
  [./constants]
    type = GenericConstantMaterial
    prop_names = 'W0 m eps4 theta0 tau0 D'
    prop_values = '1 4 0.05      0   1 10'
  [../]
  [./lambda]
    type = ParsedMaterial
    f_name = lambda
    material_property_names = 'D tau0 W0'
    function = 'D*tau0/(0.6267*W0^2)'
  [../]
  [./f_chem]
    type = DerivativeParsedMaterial
    f_name = f_chem
    material_property_names = 'lambda'
    args = 'phi U'
    function = '-0.5*phi^2 + 0.25*phi^4 + lambda*U*phi*(1-2/3*phi^2+0.2*phi^4)'
  [../]
  [./W]
    type = InterfaceOrientationMaterial
    op = phi
    mode_number = 4
    anisotropy_strength = 0.05
    eps_bar = 1
    reference_angle = 0
  [../]
  [./tau_inv]
    type = ParsedMaterial
    f_name = tau_inv
    material_property_names = 'eps'
    constant_names = 'W0 tau0' #W0=eps_bar from material W
    constant_expressions = '1 1'
    function = 'tau:=tau0*(eps/W0)*(eps/W0); 1/tau'
  [../]
  [./kappa]
    type = ParsedMaterial
    f_name = kappa
    material_property_names = 'eps'
    function = 'eps*eps'
  [../]
[]

[Postprocessors]
  [./memory]
    type = MemoryUsage
    mem_type = physical_memory
    report_peak_value = true
    execute_on = 'LINEAR NONLINEAR TIMESTEP_END'
  [../]
  [./solid_fraction]
    type = ElementAverageValue
    variable = solid
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
  [./free_energy]
    type = ElementIntegralVariablePostprocessor
    variable = f
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
  [./tip_pos]
    type = FindValueOnLine
    start_point = '0 0 0'
    end_point = '960 0 0'
    v = phi
    target = 0
    tol = 1e-7
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
[]

[Preconditioning]
  [./SMP]
    type = SMP
    full = true
  [../]
[]

[Executioner]
  type = Transient
  scheme = bdf2
  solve_type = NEWTON
  # petsc_options_iname = '-pc_type -sub_pc_type -ksp_gmres_restart'
  # petsc_options_value = 'asm       lu           31'
  petsc_options_iname = '-pc_type -sub_pc_type'
  petsc_options_value = 'asm       ilu        '
  nl_abs_tol = 1e-08
  nl_rel_tol = 1e-07
  l_max_its = 30
  nl_max_its = 15
  end_time = 1500
  [./TimeStepper]
    type = IterationAdaptiveDT
    optimal_iterations = 6
    iteration_window = 2
    dt = 0.2
    growth_factor = 1.2
    cutback_factor = 0.8
  [../]
  [./Adaptivity]
    initial_adaptivity = 2
    refine_fraction = 0.8
    coarsen_fraction = 0.2
    max_h_level = 4
    interval = 3
  [../]
  dtmax = 5.5
[]

[Outputs]
  csv = true
  perf_graph = true
  exodus = true
  # print_linear_residuals = false

  # [./exodus]
  #   type = Exodus
  #   interval = 10
  #   execute_on = 'FINAL'
  # [../]
  # [./log]
  #   type = Console
  #   output_file = true
  #   execute_on = 'FINAL'
  # [../]
[]
