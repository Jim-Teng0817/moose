# Tests the AD (automatic-differentiation) variant of DeformedGrainMaterial:
# ADDeformedGrainMaterial.
#
# The setup mirrors DeformedGrain.i but replaces DeformedGrainMaterial with
# ADDeformedGrainMaterial and uses GrainTrackerDislocations (the proper
# grain-tracking UO).  Kernels are restricted to PolycrystalKernel (the
# non-stored-energy polycrystal kernels) so that no non-AD material property
# demand conflicts arise.
#
# Note: PolycrystalStoredEnergy (ACSEDGPoly) is not used here because
# ACSEDGPoly accesses the property "Disloc_Den_i" while ADDeformedGrainMaterial
# declares "disloc_den_i".  The test verifies that ADDeformedGrainMaterial
# initialises and computes deformation_energy, beta, rho_eff, and disloc_den_i
# without error.
#
# This is a run-only (RunApp) test.

[Mesh]
  type = GeneratedMesh
  dim = 2
  nx = 16
  ny = 16
  xmin = 0
  xmax = 64
  ymin = 0
  ymax = 64
[]

[GlobalParams]
  op_num = 4
  var_name_base = gr
  grain_num = 4
  grain_tracker = grain_tracker
  time_scale = 1e-2
  length_scale = 1e-8
[]

[Variables]
  [PolycrystalVariables]
  []
[]

[AuxVariables]
  [bnds]
    order = FIRST
    family = LAGRANGE
  []
[]

[UserObjects]
  [voronoi]
    type = PolycrystalVoronoi
    rand_seed = 81
    coloring_algorithm = jp
  []
  [dislocation_density_file]
    type = DislocationDensityFileReader
    file_name = test.txt
    lines_to_skip = 0
  []
  [grain_tracker]
    # GrainTrackerDislocations is required by ADDeformedGrainMaterial to supply
    # per-grain dislocation data via getData().
    type = GrainTrackerDislocations
    threshold = 0.2
    connecting_threshold = 0.08
    compute_var_to_feature_map = true
    flood_entity_type = elemental
    execute_on = 'initial timestep_begin'
    outputs = none
    dislocation_density_reader = dislocation_density_file
    polycrystal_ic_uo = voronoi
    tolerate_failure = true
  []
[]

[ICs]
  [PolycrystalICs]
    [PolycrystalColoringIC]
      polycrystal_ic_uo = voronoi
    []
  []
[]

[BCs]
  [Periodic]
    [all]
      auto_direction = 'x y'
    []
  []
[]

[Kernels]
  # PolycrystalKernel cannot be used here: it builds non-AD ACGrGrPoly /
  # ACInterface / ACGBPoly kernels that request non-AD L, mu, kappa_op,
  # whereas ADDeformedGrainMaterial (via GBEvolutionTempl<true>) declares those
  # as AD properties.  ADTimeDerivative on each order parameter is sufficient
  # to drive a residual evaluation, which is what triggers
  # ADDeformedGrainMaterial::computeQpProperties.
  [dgr0_dt]
    type = ADTimeDerivative
    variable = gr0
  []
  [dgr1_dt]
    type = ADTimeDerivative
    variable = gr1
  []
  [dgr2_dt]
    type = ADTimeDerivative
    variable = gr2
  []
  [dgr3_dt]
    type = ADTimeDerivative
    variable = gr3
  []
[]

[AuxKernels]
  [BndsCalc]
    type = BndsCalcAux
    variable = bnds
    execute_on = timestep_end
  []
[]

[Materials]
  [deformed_ad]
    type = ADDeformedGrainMaterial
    wGB = 4.0
    GBenergy = 0.708
    # Constant GB mobility avoids the temperature-dependent mobility computation.
    GBMobility = 2.5e-14
    # Constant temperature satisfying the required coupled-var in GBEvolutionBase.
    T = 300
    deformed_grain_num = 4
    dislocation_density_constant = 9.0e15
    output_properties = 'beta disloc_den_i rho_eff deformation_energy'
    outputs = exodus
  []
[]

[Preconditioning]
  [SMP]
    type = SMP
    full = true
  []
[]

[Executioner]
  type = Transient
  nl_max_its = 15
  scheme = bdf2
  solve_type = NEWTON
  petsc_options_iname = -pc_type
  petsc_options_value = asm
  l_max_its = 15
  l_tol = 1.0e-3
  nl_rel_tol = 1.0e-8
  start_time = 0.0
  num_steps = 1
  nl_abs_tol = 1e-8
  dt = 0.20
[]

[Outputs]
  exodus = true
  time_step_interval = 1
[]
