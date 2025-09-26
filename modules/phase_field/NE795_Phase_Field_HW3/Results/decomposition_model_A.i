# This simulates decomposition in Model A (Non-conserved dynamics)

# kappa is the gradient coefficient
kappa = 0.10
# A is the constant in the double well bulk_free_energy (it controls the height of the well (A/16) )
A = 0.10
# The driving force for decomposition/nucleation and grwoth (it tilts the double well, making one phase more stable than the other)
B = 0.0350
# if B<A/3 eta=0 is metastable (transform by nucleation)/ if B>A/3 eta=0 is unstable (transform by decomposition)
# Here B>A/3
# Here we use moose built-in Allen-Cahn kernels from the phase-field module
# this is the "traditional" way of implementing a phase-field model A
n_elem = 256 # Number of Elements
X = 256 #  Domain length
L = 1.0 # Alen-Cahn mobility
[Mesh]
  type = GeneratedMesh
  dim = 2
  nx = '${n_elem}'
  ny = '${n_elem}'
  nz = 0
  xmin = 0
  xmax = '${X}'
  ymin = 0
  ymax = '${X}'
  zmax = 0
  elem_type = QUAD4
[]
[Variables]
  [./eta]
    order = FIRST
    family =  LAGRANGE
  [../]
[]

[AuxVariables]
  [./total_free_energy]
    order = CONSTANT
    family = MONOMIAL
  [../]
[]
[AuxKernels]
  [./total_free_energy]
    type = TotalFreeEnergy
    variable = total_free_energy
    kappa_names = kappa
    interfacial_vars = eta
    execute_on = 'INITIAL TIMESTEP_END'
  [../]

[]

[ICs]
  [./eta] # small variation around the metastable phase (eta=0)
    type = RandomIC
    variable = 'eta'
     min = -0.00010
     max = 0.00015
     seed = 198532
  # if you change the seed (for the random generator), a different nucleation sequence of events will occur! 
  [../]
[]

[BCs]
  [./Periodic]
    [./all]
      auto_direction = 'x y'
      variable = 'eta'
    [../]
  [../]
[]

[Kernels]
    [./AC_bulk]
      type = AllenCahn
      variable = 'eta'
      f_name = F # the name of the materials object that defines the bulk free energy (the non-gradient term(s))
      mob_name = mobility # the name of Allen-Cahn mobility
    [../]
    [./AC_int]
      type = ACInterface
      variable = 'eta'
      kappa_name = kappa # the name of the Allen-Cahn gradient coefficient
      mob_name = mobility
    [../]
    [./eta_dot]
      type = TimeDerivative
      variable = 'eta'
    [../]
[]

[Materials]

  [./Bulk_Free_Eng]
# if B<A/3 eta=0 is metastable (transform by nucleation)/ if B>A/3 eta=0 is unstable (transform by decomposition)
# Here B>A/3
    type = DerivativeParsedMaterial
    coupled_variables = 'eta'
    expression = ${A}*(eta^2*(1.0-eta)^2)+${B}*(2.0*eta^3-3.0*eta^2)
    derivative_order = 2
  [../]
    [./const]
      type = GenericConstantMaterial
      prop_names = 'kappa mobility'
      prop_values = '${kappa} ${L}'
  [../]

[]

[Postprocessors]
  [./total_free_energy]
    type = ElementIntegralVariablePostprocessor
    variable = total_free_energy
    execute_on = 'INITIAL TIMESTEP_END'
  [../]
  [./daughter_phase_area_fraction]
    type = ElementAverageValue
    variable = eta
    execute_on = 'INITIAL TIMESTEP_END'
  [../]

[]

[Executioner]
     scheme = bdf2
    type = Transient
    nl_max_its = 15
    solve_type = NEWTON
    petsc_options_iname = '-pc_type'
    petsc_options_value = 'asm'
    l_max_its = 15
    l_tol = 1.0e-4
    nl_rel_tol = 1.0e-8
    start_time = 0.0
    num_steps = 50
    nl_abs_tol = 1e-11
    [./TimeStepper]
      type = IterationAdaptiveDT
      dt = 1.0
      growth_factor = 1.2
      cutback_factor = 0.75
      optimal_iterations = 6
    [../]
[]

[Outputs]
  file_base = decomposition_model_A/decomposition_model_A
  exodus = true
  csv = true
  interval = 1
[]
