[GlobalParams]
  displacements = 'disp_x disp_y'
[]

[Mesh]
  [./Plate_w_hole]
    type = FileMeshGenerator
    file = NE795_Midterm_2D_newrefined.msh
  []
[]

[Physics]
  [SolidMechanics]
    [QuasiStatic]
      [sample]
        new_system = true
        add_variables = true
        strain = SMALL
        formulation = TOTAL
        generate_output = 'cauchy_stress_xx cauchy_stress_yy cauchy_stress_zz cauchy_stress_xy cauchy_stress_xz cauchy_stress_yz mechanical_strain_xx mechanical_strain_yy mechanical_strain_zz mechanical_strain_xy mechanical_strain_xz mechanical_strain_yz'
        additional_generate_output = 'vonmises_cauchy_stress'
      []
    []
  []
[]

[BCs]
  [bottom_y]
    type = DirichletBC
    variable = disp_y
    boundary = 'bottom'    
    value = 0
  []

  [left_x]
    type = DirichletBC
    variable = disp_x
    boundary = 'left'      
    value = 0
  []
  [Pressure]
    [top]
      boundary = 'top'    
      factor = '-100e3'  
    []
  []
[]

[Materials]
  [elasticity]
    type = ComputeIsotropicElasticityTensor
    youngs_modulus = 200e9
    poissons_ratio = 0.3
  []
  [stress]
    type = ComputeLagrangianLinearElasticStress
  []
[]

# consider all off-diagonal Jacobians for preconditioning
[Preconditioning]
  [SMP]
    type = SMP
    full = true
  []
[]

[Executioner]
	type = Steady
	solve_type = NEWTON
[]

[Outputs]
  exodus = true
[]
