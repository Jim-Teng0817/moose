# -----------------------------------------------------------------------------
# AUTO-GENERATED CASEWISE CALIBRATION INPUT
# stage          = 03_probability
# parameter_set  = factor_baseline_1
# case_name      = factor_baseline_1p0_T_1273p0_gdot_100p0
# Submit from the package root with:
#   sbatch submit_one_case.slurm cases/03_probability/factor_baseline_1p0_T_1273p0_gdot_100p0/input.i
# -----------------------------------------------------------------------------

# Test 9 of plan §7: end-to-end rho_var path (km_with_deformed_grain_material.i)
# 2-grain bicrystal with constant OPs (no phase-field evolution). KocksMecking
# rho -> MaterialRealAux -> aux variable rho_grain -> DeformedGrainMaterial.rho_var.
# Acceptance: at t=dt, Def_Eng from DeformedGrainMaterial equals beta * rho_avg
# where rho_avg comes from the KocksMecking material directly.

# # adaptivity
# mesh_adaptivity_level = 3 # 2 3
# coarsen_i = 0.00  # 0.06
# refine_i = 0.20

# time
# time_scale_i = '${units 0.001 s}'    # in default, 1e-9 s = 1 ns      1   1e-9  0.001
# time_scale_i = '${units 1 s}'

# time_scale_i = 1e-2         # 1e-6
# # time_scale_i = 1e-0         
# dt_i = 1e0                 # 2e-1
# dt_nuc_i = 5e-3
# hold_time_i = 3e-3          # 0

time_scale_i = 1
dt_i = 5e-05
dt_nuc_i = 5e-05
hold_time_i = 0.001

# end_time_i = '${fparse 1000 * (1/time_scale_i)}'    # 10

# Strain Rate
strain_rate_i = 100
total_strain_i = 2
end_time_i = 0.02
# sync_times_i = '${fparse 1800 * (1/time_scale_i)}'   # represent the 1800 s = 30 min

# length
length_scale_i = '${units 1e-9 m}'   # in default, 1e-9 m = 1 nm    1e-6   1e-9

# Initial Dislocation Input Text File
# input_text_file = ../../../test_e-2
input_text_file = ../../../test_e-2_uniform
# input_text_file = ../../../test_e-2_uniform_2Point5

# Filename
Folder_name = 'cases/03_probability/factor_baseline_1p0_T_1273p0_gdot_100p0'
mod_num = factor_baseline_1p0_T_1273p0_gdot_100p0

# nucleation                      # Added for Nucleation (Jim June 17, 2026)
# initial_op_num_i = 4        # original deformed grains / active initial OPs
# reserve_op_num_i = 1        # one staging OP for nuclei
# total_op_num_i = 5          # initial_op_num_i + reserve_op_num_i
initial_grain_num_i = 4       # actual initial grains
initial_ic_op_num_i = 4       # OPs used by initial Voronoi IC

# normal_op_num_i = 8           # gr0-gr7 are available for real grains
reserve_op_num_i = 1          # gr10 is staging only  # gr8 is staging only 
total_op_num_i = 11            # normal_op_num_i + reserve_op_num_i
# active_op_num_i = ${fparse total_op_num_i - reserve_op_num_i}

# first-pass nucleation tuning    # Added for Nucleation (Jim June 17, 2026)
nuc_radius_i = 60
# rho_crit_i = 5e14           # m^-2; tune after checking rho_grain output. # 5.0e14 5e-4 # if target is 5e14 m^-2 = 5e-4 nm^-2     
# rho_crit_i = 5e-6           # nm^-2  5e-4 5e-5 5e-6
bnds_min_i = 0.55
bnds_max_i = 0.85
nuc_prob_i = 0.002

# # set to -1.0 for first debug run so nucleation can occur anywhere.
# # later use something like 0.05-0.20 to restrict to grain boundaries using bnds.
# bnds_crit_i = 0.10          # Added for Nucleation (Jim June 17, 2026) # -1.0 

# For k_1
burger_i = 2.96e-10           # Added for Nucleation (Jim June 17, 2026) # 2004_J Rest  # in m
# burger_i = ${fparse 2.96e-10 / length_scale_i}  # 0.296 in simulation length units, i.e. nm
G_shear_i = 32.7e9            # Added for Nucleation (Jim June 17, 2026) # 2024_Sourabh B. Kadambi  # in Pa
theta_0_i = 0.1635e9          # Added for Nucleation (Jim June 17, 2026) # in Pa
M_taylor_i = 2.75             # Added for Nucleation (Jim June 17, 2026) 
alpha_taylor_i = 0.3          # Added for Nucleation (Jim June 17, 2026)
rho_init_i = 1e+16

# Nucleation Force
nuc_strength_i = 1000

# Nucleated Grain Width
int_width_i = 10

GBenergy_i = 0.5             # GB energy in J m^-2    # 0.708 0.5
# GBMobility_i = 6.1995e-14    # GB Mobility in m^4 J^-1 s^-1   # 2.5e-14 6.1995e-14 1.8634e-28 (393K)
wGB_i = 25.0                 # GB width for initial grains (in length scale) # 4.0 40.0 10.0 25.0
molar_volume_i = 1.21e-5     # Molar volume in m^3/mol, needed for temperature gradient driving force
GBmob0_i = 1.532e-5          # Pre-factor for Grain Growth based mobility # 1.532e-5 1.532e-8
Q_GG_act_i = 1.7867          # Activation Energy in eV for Grain Growth based mobility. 1.724e5 J/mol = 1.7867 eV/particale
# R_gas_const = 8.3144626181532# Gas constant in J K^-1 mol^-1
T_i = 1273

# For k_2_dyn
# n_exp_i = 5.0              # 1 / Stress-Strain Rate Sensitivity exponent  # 5.0  m=0.22=>n_exp=4.545
m_i = 0.22                   # Stress-Strain Rate Sensitivity exponent
k20_i = 10                   # Prefactor for k_2_dyn (Assumed)
Q_dyn_i = 1.0426             # 0.5 eV,  1.006e5 J/mol ~= 1.0426 eV
Q_units_i = 'eV'


# nucleation probability from dislocation stored energy (in a function of dislocation density)
# f_disloc = 0.5 * G * b^2 * rho
# f_subgrain = sigma / (2 * r_subgrain)

# subgrain/nucleus radius in physical meters
r_subgrain_i = 6e-08
# Convert rho_grain to m^-2 if needed.
# If rho_eff is already in m^-2, keep this as 1.0. 1.0e18 for rho_eff is in nm^-2
rho_scale_i = 1.0e18           # 1 1.0e18
# Reference rho used only to keep the rate easy to tune.
# Set this close to the typical rho_grain value where you expect nucleation.
rho_ref_i = 1
# Reference strain rate used by the rate-scaled nucleation law.
gdot_ref_i = 1
# Global nucleation scale; overridden by the calibration Slurm array.
factor_n_i = 1
# Write one Exodus state every N accepted time steps.
exodus_interval_i = 20

[Mesh]
  type = GeneratedMesh
  dim = 2
  nx = 32             # 16 32 24
  ny = 32             # 16 32 24
  xmin = 0.0
  xmax = 1250.0         # 64 320 1250
  ymin = 0.0
  ymax = 1250.0         # 64 320 1250
  uniform_refine = 2 # Initial uniform refinement of the mesh. # 2
[]

[GlobalParams]
  # op_num = 4                    # Removed for Nucleation (Jim June 17, 2026)
  op_num = ${total_op_num_i}      # Added for Nucleation (Jim June 17, 2026)

  var_name_base = gr

  # deformed_grain_num = 4        # Removed for Nucleation (Jim June 17, 2026)
  # grain_num = 4                 # Removed for Nucleation (Jim June 17, 2026)

  # Only the original grain IDs 0-3 are deformed.
  # New grain IDs >= 4 should be recrystallized / low-rho.
  deformed_grain_num = ${initial_grain_num_i}    # Modified for Nucleation (Jim June 19, 2026)

  grain_tracker = grain_tracker
  time_scale = ${time_scale_i}
  length_scale = ${length_scale_i}
[]

[Variables]
  # [gr10]
  #   initial_condition = 0.0
  # []
  # [gr0]                                    # Removed for DeformedGrain (Jim June 5, 2026)
  #   [InitialCondition]
  #     type = FunctionIC
  #     function = 'if(x<0.5, 1, 0)'
  #   []
  # []
  # [gr1]                                    # Removed for DeformedGrain (Jim June 5, 2026)
  #   [InitialCondition]
  #     type = FunctionIC
  #     function = '1 - if(x<0.5, 1, 0)'
  #   []
  # []
  [PolycrystalVariables]                     # Added for DeformedGrain (Jim June 5, 2026)
  []
[]

[AuxVariables]
  [gamma_dot]
    initial_condition = ${strain_rate_i}   # 1.0e-3 1e-1
  []
  [T]
    initial_condition = ${T_i}    # 1073.0 393
  []
  [rho_grain]
    family = MONOMIAL
    order = CONSTANT
  []
  [bnds]
    order = FIRST
    family = LAGRANGE
  []

  [nuc_map_aux]
    family = MONOMIAL
    order = CONSTANT
  []
[]

[AuxKernels]
  [rho_grain_aux]
    type = MaterialRealAux
    variable = rho_grain
    property = rho
    # execute_on = 'INITIAL TIMESTEP_END'
    execute_on = 'INITIAL TIMESTEP_BEGIN TIMESTEP_END'
  []
  [BndsCalc]
    type = BndsCalcAux
    variable = bnds
    # execute_on = timestep_end           # Removed for Nucleation (Jim June 17, 2026)
    # execute_on = 'INITIAL TIMESTEP_END'   # Added for Nucleation (Jim June 17, 2026)
    execute_on = 'INITIAL TIMESTEP_BEGIN TIMESTEP_END'
  []

  [nuc_map_aux]
    type = DiscreteNucleationAux

    variable = nuc_map_aux
    map = nuc_map

    no_nucleus_value = 0.0
    nucleus_value = 1.0

    execute_on = 'TIMESTEP_END'
  []
[]

[Kernels]
  [PolycrystalKernel]                     # Added for DeformedGrain (Jim June 5, 2026)
  []
  # [PolycrystalStoredEnergy]               # Added for DeformedGrain (Jim June 5, 2026)
  #   grain_tracker = grain_tracker
  # []
  [PolycrystalStoredEnergy]               # Added for Hexagonal IC (Jim June 18, 2026)
    grain_tracker = grain_tracker
    # deformed_grain_num = 3
    # op_num = 4
    var_name_base = gr

    # Some MOOSE versions/branches require this for the action.
    # If your local version says T is unused, remove only this line.
    T = T
  []

  # # Insert nuclei into reserved OP gr4.
  # [nuc_force_gr4]                         # Added for Nucleation (Jim June 17, 2026)
  #   type = DiscreteNucleationForce
  #   variable = gr4
  #   map = nuc_map
  #   no_nucleus_value = 0
  #   nucleus_value = 1
  # []

  # [nuc_reaction_gr4]                      # Added for Nucleation (Jim June 17, 2026)
  #   type = Reaction
  #   variable = gr4
  # []

  # # Insert nuclei into reserved OP gr8.
  # [nuc_force_gr8]                         # Added for Nucleation (Jim June 17, 2026)
  #   type = DiscreteNucleationForce
  #   variable = gr8
  #   map = nuc_map
  #   # no_nucleus_value = 0
  #   # nucleus_value = 1

  #   # Use same value as Reaction rate below.
  #   # This keeps the target gr8 value near 1,
  #   # but makes the forcing much stronger.
  #   nucleus_value = ${nuc_strength_i}
  # []
  # [nuc_reaction_gr8]                      # Added for Nucleation (Jim June 19, 2026)
  #   type = Reaction
  #   variable = gr8

  #   # Stronger relaxation toward the nucleation map.
  #   rate = ${nuc_strength_i}
  # []

  # Insert nuclei into reserved OP gr10.
  [nuc_force_gr10]                         # Added for Nucleation (Jim June 17, 2026)
    type = DiscreteNucleationForce
    variable = gr10
    map = nuc_map
    # no_nucleus_value = 0
    # nucleus_value = 1

    # Use same value as Reaction rate below.
    # This keeps the target gr10 value near 1,
    # but makes the forcing much stronger.
    nucleus_value = ${nuc_strength_i}
  []
  [nuc_reaction_gr10]                      # Added for Nucleation (Jim June 19, 2026)
    type = Reaction
    variable = gr10

    # Stronger relaxation toward the nucleation map.
    rate = ${nuc_strength_i}
  []
[]

[UserObjects]
  [voronoi]                               # Added for DeformedGrain (Jim June 5, 2026)
    type = PolycrystalVoronoi

    grain_num = ${initial_grain_num_i}    # Modified for Nucleation (Jim June 19, 2026)
    op_num = ${initial_ic_op_num_i}       # Modified for Nucleation (Jim June 19, 2026)

    rand_seed = 81
    coloring_algorithm = bt
  []

  # [hex_ic]                                  # Added for Hexagonal IC (Jim June 18, 2026)
  #   type = PolycrystalHex
  #   grain_num = 4
  #   coloring_algorithm = bt

  #   # Use the unperturbed regular hex pattern.
  #   perturbation_percent = 0.0

  #   # MOOSE's own 4-grain hex example uses x_offset = .5.
  #   x_offset = 0.5

  #   # Useful while checking the OP-to-grain assignment.
  #   output_adjacency_matrix = true
  # []

  [dislocation_density_file]              # To make it run (Jim June 5, 2026)
    type = DislocationDensityFileReader
    file_name = '${input_text_file}.txt'
    lines_to_skip = 0
  []
  [grain_tracker]
    type = GrainTrackerDislocations
    # threshold = 0.05                       # 0.2
    # connecting_threshold = 0.02           # 0.08

    threshold = 0.1
    connecting_threshold = 0.05
  
    compute_var_to_feature_map = true
    flood_entity_type = elemental
    # execute_on = 'initial timestep_begin'
    # execute_on = 'INITIAL TIMESTEP_END'
    execute_on = 'INITIAL TIMESTEP_BEGIN TIMESTEP_END'
    outputs = none

    reserve_op = ${reserve_op_num_i}      # Added for Nucleation (Jim June 17, 2026)
    # reserve_op_threshold = 0.05            # 0.50           # Added for Nucleation (Jim June 17, 2026)
    reserve_op_threshold = 0.5 

    dislocation_density_reader = dislocation_density_file # To make it run (Jim June 5, 2026)
    polycrystal_ic_uo = voronoi                           # Add and deleted To make it run (Jim June 5, 2026) # Added for DeformedGrain (Jim June 5, 2026)
    # polycrystal_ic_uo = hex_ic                              # Added for Hexagonal IC (Jim June 18, 2026)
    tolerate_failure = true

    remap_grains = true                   # Added for Nucleation (Jim June 17, 2026)
    add_default_density_grains = true     # Added for Nucleation (Jim June 17, 2026)
    default_density = 0.0                 # Added for Nucleation (Jim June 17, 2026)
  []

  [nuc_inserter]                          # Added for Nucleation (Jim June 17, 2026)
    type = DiscreteNucleationInserter
    probability = P_nuc
    radius = ${nuc_radius_i}              # initial radius of the nucli
    hold_time = ${hold_time_i}            # 0
    # For debugging, make probability scale with dt.
    # After stable behavior is confirmed, you can return to false if physically needed.
    # time_dependent_statistics = false
    time_dependent_statistics = true
    seed = 12345
    execute_on = TIMESTEP_END
  []

  [nuc_map]                               # Added for Nucleation (Jim June 17, 2026)
    type = DiscreteNucleationMap
    inserter = nuc_inserter
    # periodic = gr0                        # Modified for Nucleation (Jim June 19, 2026)  # gr4
    int_width = ${int_width_i}              # 2.0
    # execute_on = TIMESTEP_BEGIN
  []
[]

[ICs]                                      # Add and deleted To make it run (Jim June 5, 2026)
  [PolycrystalICs]                         # Added for DeformedGrain (Jim June 5, 2026)
    [PolycrystalColoringIC]
      polycrystal_ic_uo = voronoi
      op_num = ${initial_ic_op_num_i}      # Added for Nucleation (Jim June 17, 2026)
      var_name_base = gr                   # Added for Nucleation (Jim June 17, 2026)
    []
  []

  # [PolycrystalICs]                                      # Added for Hexagonal IC (Jim June 18, 2026)
  #   [PolycrystalColoringIC]
  #     polycrystal_ic_uo = hex_ic
  #   []
  # []
[]

# [BCs]                                                   # Added for Hexagonal IC (Jim June 18, 2026)
#   [Periodic]
#     [all]
#       auto_direction = 'x y'
#     []
#   []
# []

[Materials]
  [km]
    type = KocksMeckingDislocation
    gamma_dot = gamma_dot
    T = T
    enable_storage = true
    enable_dynamic_recovery = true
    enable_static_recovery = false
    k1_name = k1
    # mu = 4.2e10
    # b = 2.56e-10
    # L_obs = 1.0e-6
    k20 = ${k20_i}
    Q_dyn = ${Q_dyn_i}
    Q_units = ${Q_units_i}
    # n_exp = ${n_exp_i}                    # 5.0 # 1 / Stress-Strain Rate Sensitivity
    m = ${m_i}                              # Stress-Strain Rate Sensitivity
    # gdot_ref = 1.0
    rho_init = ${rho_init_i}

    time_scale = ${time_scale_i}

    outputs = exodus
  []
  [deformed]
    type = DeformedGrainMaterial
    grain_tracker = grain_tracker
    rho_var = rho_grain
    wGB = ${wGB_i}                       # 4.0
    GBenergy = ${GBenergy_i}             # 0.708
    # GBMobility = ${GBMobility_i}         # 2.5e-14
    T = T                                # Unify with the temperature in both of the two material blocks
    molar_volume = ${molar_volume_i}
    GBmob0 = '${GBmob0_i}'               # 2.5e-6 #m^4 / (Js) hand calculated for U-10Mo from 2017_Frazier et. al. - Short communication on Kinetics of grain growth and particle pinning in U-10 wt.% Mo
    Q = '${Q_GG_act_i}'    
    outputs = exodus
  []

  # [nucleation_probability]             # Added for Nucleation (Jim June 17, 2026)
  #   type = ParsedMaterial
  #   property_name = P_nuc
  #   # coupled_variables = 'rho_grain bnds'
  #   # bnds is usually an AuxVariable / nonlinear variable, so keep it here
  #   coupled_variables = 'bnds'
  #   # rho_eff is a material property produced by DeformedGrainMaterial
  #   material_property_names = 'rho_eff'
  #   constant_names = 'rho_crit bnds_max P0'
  #   constant_expressions = '${rho_crit_i} ${bnds_max_i} ${nuc_prob_i}'

  #   # Kocks-Mecking rho criterion:
  #   # Nucleate where rho_grain > rho_crit.
  #   # bnds = sum_i eta_i^2
  #   # grain interior: bnds ~ 1, so 1-bnds ~ 0
  #   # grain boundary: bnds < 1, so 1-bnds > 0
  #   expression = 'if(rho_eff > rho_crit, if(bnds < bnds_max, P0, 0), 0)'

  #   outputs = exodus
  # []

  [nucleation_probability]
    type = ParsedMaterial
    property_name = P_nuc
    coupled_variables = 'bnds gamma_dot'
    material_property_names = 'rho_eff'
    constant_names = 'G b sigma r_subgrain bnds_min bnds_max P0 rho_scale rho_ref factor_n gdot_ref'
    constant_expressions = '${G_shear_i} ${burger_i} ${GBenergy_i} ${r_subgrain_i} ${bnds_min_i} ${bnds_max_i} ${nuc_prob_i} ${rho_scale_i} ${rho_ref_i} ${factor_n_i} ${gdot_ref_i}'

    # The energy inequality determines whether nucleation is admissible.
    # gamma_dot/gdot_ref makes the expected stochastic exposure comparable
    # per unit accumulated strain when time_dependent_statistics = true.
    expression = 'if(0.5 * G * b * b * rho_eff * rho_scale < sigma / r_subgrain, 0, if(bnds > bnds_min, if(bnds < bnds_max, P0 * factor_n * (rho_eff / rho_ref) * (gamma_dot / gdot_ref), 0), 0))'
    outputs = exodus
  []

  [nuc_drive_ratio]
    type = ParsedMaterial
    property_name = nuc_drive_ratio
    material_property_names = 'rho_eff'
    constant_names = 'G b sigma r_subgrain rho_scale'
    constant_expressions = '${G_shear_i} ${burger_i} ${GBenergy_i} ${r_subgrain_i} ${rho_scale_i}'
    expression = '(0.5 * G * b * b * rho_eff * rho_scale) / (sigma / r_subgrain)'
    outputs = exodus
  []

  # [op_active_count]
  #   type = ParsedMaterial
  #   property_name = op_active_count

  #   coupled_variables = 'gr0 gr1 gr2 gr3 gr4 gr5 gr6 gr7 gr8 gr9'

  #   constant_names = 'eta_thr'
  #   constant_expressions = '0.10'

  #   expression = 'if(gr0 > eta_thr, 1, 0) + if(gr1 > eta_thr, 1, 0) + if(gr2 > eta_thr, 1, 0) + if(gr3 > eta_thr, 1, 0) + if(gr4 > eta_thr, 1, 0) + if(gr5 > eta_thr, 1, 0) + if(gr6 > eta_thr, 1, 0) + if(gr7 > eta_thr, 1, 0) + if(gr8 > eta_thr, 1, 0) + if(gr9 > eta_thr, 1, 0)'

  #   outputs = exodus
  # []
  # [nucleation_probability]
  #   type = ParsedMaterial
  #   property_name = P_nuc

  #   coupled_variables = 'bnds'
  #   material_property_names = 'op_active_count'

  #   constant_names = 'bnds_min bnds_max P0'
  #   constant_expressions = '${bnds_min_i} ${bnds_max_i} ${nuc_prob_i}'

  #   expression = 'if(op_active_count > 1.5, if(op_active_count < 2.5, if(bnds > bnds_min, if(bnds < bnds_max, P0, 0), 0), 0), 0)'

  #   outputs = exodus
  # []

  [k1]
    type = ParsedMaterial
    property_name = k1
    # coupled_variables = 'rho_grain bnds'
    constant_names = 'b G theta_0 M_taylor alpha_taylor length_scale'
    constant_expressions = '${burger_i} ${G_shear_i} ${theta_0_i} ${M_taylor_i} ${alpha_taylor_i} ${length_scale_i}'
    expression = '2 * theta_0 / (M_taylor * alpha_taylor * G * b)'
    # expression = '2 * theta_0 / (M_taylor * alpha_taylor * G * b * length_scale)'       # Convert unit of b from m to nm
    block = 0
    outputs = exodus
  []      

  [k2dyn_t_diag]
    type = ParsedMaterial
    property_name = k2dyn_t_diag
    coupled_variables = 'gamma_dot T'
    constant_names = 'k20 m Q kB'
    constant_expressions = '${k20_i} ${m_i} ${Q_dyn_i} 8.617333262e-5'
    expression = 'k20 * pow(gamma_dot, 1.0 - m) * exp(-m * Q / (kB * T))'
    outputs = exodus
  []

  [stored_energy_density]
    type = ParsedMaterial
    property_name = stored_energy_density

    material_property_names = 'rho_eff'

    constant_names = 'G b rho_scale'
    constant_expressions = '${G_shear_i} ${burger_i} ${rho_scale_i}'

    expression = '0.5 * G * b * b * rho_eff * rho_scale'

    outputs = exodus
  []

  [curvature_penalty]
    type = ParsedMaterial
    property_name = curvature_penalty

    constant_names = 'sigma r_subgrain'
    constant_expressions = '${GBenergy_i} ${r_subgrain_i}'

    expression = 'sigma / r_subgrain'

    outputs = exodus
  []

  [energy_margin]
    type = ParsedMaterial
    property_name = energy_margin

    material_property_names = 'stored_energy_density curvature_penalty'

    expression = 'stored_energy_density - curvature_penalty'

    outputs = exodus
  []

  [energy_preferred]
    type = ParsedMaterial
    property_name = energy_preferred

    material_property_names = 'nuc_drive_ratio'

    # 1 means stored energy exceeds the curvature penalty.
    expression = 'if(nuc_drive_ratio >= 1.0, 1.0, 0.0)'

    outputs = exodus
  []

  [eligible_nucleation_region]
    type = ParsedMaterial
    property_name = eligible_nucleation_region

    coupled_variables = 'bnds'
    material_property_names = 'nuc_drive_ratio'

    constant_names = 'bnds_min bnds_max'
    constant_expressions = '${bnds_min_i} ${bnds_max_i}'

    # Both the energetic and GB-location criteria must be satisfied.
    expression = 'if(nuc_drive_ratio >= 1.0, if(bnds > bnds_min, if(bnds < bnds_max, 1.0, 0.0), 0.0), 0.0)'

    outputs = exodus
  []

  [P_nuc_unfavorable]
    type = ParsedMaterial
    property_name = P_nuc_unfavorable

    material_property_names = 'P_nuc nuc_drive_ratio'

    # This should always be zero.
    expression = 'if(nuc_drive_ratio < 1.0, P_nuc, 0.0)'

    outputs = exodus
  []
[]

[Postprocessors]
  [rho_avg]
    type = ElementAverageMaterialProperty
    mat_prop = rho
  []
  [tau_avg]
    type = ElementAverageMaterialProperty
    mat_prop = tau_flow
  []
  [Def_Eng]
    type = ElementAverageMaterialProperty
    mat_prop = deformation_energy
  []
  [beta_avg]
    type = ElementAverageMaterialProperty
    mat_prop = beta
  []

  [nuc_count]                         # Added for Nucleation (Jim June 17, 2026)
    type = DiscreteNucleationData
    inserter = nuc_inserter
    value = COUNT
  []
  [nuc_rate]                          # Added for Nucleation (Jim June 17, 2026)
    type = DiscreteNucleationData
    inserter = nuc_inserter
    value = RATE
  []

  [nuc_insertions]
  type = DiscreteNucleationData
  inserter = nuc_inserter
  value = INSERTIONS
  []
  [nuc_deletions]
    type = DiscreteNucleationData
    inserter = nuc_inserter
    value = DELETIONS
  []
  [nuc_update]
    type = DiscreteNucleationData
    inserter = nuc_inserter
    value = UPDATE
  []

  [gdot_avg]
    type = ElementAverageValue
    variable = gamma_dot
  []
  [k2dyn_t_avg]
    type = ElementAverageMaterialProperty
    mat_prop = k2dyn_t_diag
  []

  [T_avg]
    type = ElementAverageValue
    variable = T
  []
  [rho_eff_avg]
    type = ElementAverageMaterialProperty
    mat_prop = rho_eff
  []
  [P_nuc_avg]
    type = ElementAverageMaterialProperty
    mat_prop = P_nuc
  []
  [nuc_drive_ratio_avg]
    type = ElementAverageMaterialProperty
    mat_prop = nuc_drive_ratio
  []
  [dt_actual]
    type = TimestepSize
  []

  [dtnuc]                             # Added for Nucleation (Jim June 17, 2026)
    type = DiscreteNucleationTimeStep
    inserter = nuc_inserter
    # p2nucleus = 0.001
    p2nucleus = 0.10                 # 0.05 0.10
    # Must be smaller than the regular dt.
    dt_max = ${dt_nuc_i}
  []

  # Add this: average grain area in 2D
  [avg_grain_area]
    type = AverageGrainVolume
    feature_counter = grain_tracker
    execute_on = 'INITIAL TIMESTEP_END'
  []

  # Add this: total grain-boundary length in 2D
  [gb_length]
    type = GrainBoundaryArea
    grains_per_side = 2
    execute_on = 'INITIAL TIMESTEP_END'
  []

  # Detect small/incipient grains as soon as an OP becomes active.
  [grain_count_early]
    type = FeatureFloodCount

    variable = 'gr0 gr1 gr2 gr3 gr4 gr5 gr6 gr7 gr8 gr9 gr10'

    threshold = 0.10
    connecting_threshold = 0.05

    # The grain OP is active where eta > threshold.
    use_less_than_threshold_comparison = false

    # Consolidate features found across all OP variables into one count.
    use_single_map = true

    flood_entity_type = ELEMENTAL
    execute_on = 'INITIAL TIMESTEP_END'
  []

  # Count only more fully established grains.
  [grain_count_established]
    type = FeatureFloodCount

    variable = 'gr0 gr1 gr2 gr3 gr4 gr5 gr6 gr7 gr8 gr9 gr10'

    threshold = 0.50
    connecting_threshold = 0.20

    use_less_than_threshold_comparison = false
    use_single_map = true

    flood_entity_type = ELEMENTAL
    execute_on = 'INITIAL TIMESTEP_END'
  []

#   [ngrains]
#     type = FeatureFloodCount
#     variable = bnds
#     threshold = 0.8
#   []
  [grain_count_bnds_070]
    type = FeatureFloodCount
    variable = bnds
    threshold = 0.70
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [grain_count_bnds_080]
    type = FeatureFloodCount
    variable = bnds
    threshold = 0.80
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [grain_count_bnds_090]
    type = FeatureFloodCount
    variable = bnds
    threshold = 0.90
    execute_on = 'INITIAL TIMESTEP_END'
  []
[]

[VectorPostprocessors]
  [grain_features]
    type = FeatureVolumeVectorPostprocessor
    flood_counter = grain_tracker

    # Available when periodic boundaries are not used.
    output_centroids = true

    execute_on = 'INITIAL TIMESTEP_END'
  []
[]
[Preconditioning]
  [./SMP]
    type = SMP
    full = true
  [../]
[]

# [Executioner]
#   type = Transient
#   nl_max_its = 15
#   scheme = bdf2
#   solve_type = PJFNK
#   petsc_options_iname = -pc_type
#   petsc_options_value = asm
#   l_max_its = 15
#   l_tol = 1.0e-3
#   start_time = 0.0
#   num_steps = 205
#   # end_time = '${end_time_i}'             # end time (Jim June 3, 2026)
#   # nl_abs_tol = 1e-8
#   nl_abs_tol = 1.0e-10
#   nl_rel_tol = 1.0e-8
#   # dt = 0.20
#   [TimeStepper]                          # TimeStepper (Jim June 3, 2026)
#     type = IterationAdaptiveDT
#     dt = '${dt_i}' # Initial time step.  In this simulation it changes.
#     optimal_iterations = 6 # Time step will adapt to maintain this number of nonlinear iterations
#     timestep_limiting_postprocessor = dtnuc # Added for Nucleation (Jim June 17, 2026)
#   []
# []

[Executioner]
  type = Transient
  scheme = bdf2
  solve_type = PJFNK

  nl_max_its = 50
  nl_abs_tol = 1.0e-10
  nl_rel_tol = 1.0e-8

  l_max_its = 200
  l_tol = 1.0e-4

  petsc_options_iname = '-pc_type'
  petsc_options_value = 'asm'

  start_time = 0.0
  # num_steps = 150
  end_time = '${end_time_i}'  

  [TimeStepper]
    type = IterationAdaptiveDT
    dt = '${dt_i}'
    optimal_iterations = 8
    growth_factor = 2.0                      # 1.2 2.0
    cutback_factor = 0.5
    timestep_limiting_postprocessor = dtnuc
  []
[]

# [Adaptivity]                                            # Adaptivity at Grain Boundaries (Jim June 3, 2026)
#   initial_steps = ${fparse mesh_adaptivity_level-1}

#   initial_marker = errorfrac

#   max_h_level = ${mesh_adaptivity_level}

#   # # Do not adapt every step during debugging
#   # interval = 50

#   marker = combined
#   # marker = errorfrac # combined
#   cycles_per_step = 1
#   recompute_markers_during_cycles = true

#   [Indicators]
#     [error]
#       type = GradientJumpIndicator
#       variable = bnds
#     []
#   []

#   [Markers]
#     [errorfrac]
#       type = ErrorFractionMarker
#       # coarsen = ${coarsen_i}
#       indicator = error
#       refine = ${refine_i}
#     []

#     [nuc_refine]
#       type = DiscreteNucleationMarker
#       map = nuc_map
#     []

#     [combined]
#       type = ComboMarker
#       markers = 'errorfrac nuc_refine'
#     []
#   []
# []

[Outputs]
  [csv]
    type = CSV
    execute_on = 'INITIAL TIMESTEP_END'
  []
  [exodus]
    type = Exodus
    interval = ${exodus_interval_i}
  []
  file_base = ${Folder_name}/result
[]
