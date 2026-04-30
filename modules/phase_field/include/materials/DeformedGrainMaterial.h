//* This file is part of the MOOSE framework
//* https://mooseframework.inl.gov
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

#pragma once

#include "GBEvolution.h"

// Forward Declarations
class GrainTrackerDislocations;

/**
 * Calculates The Deformation Energy associated with a specific dislocation density.
 * The rest of parameters are the same as in the grain growth model
 */
template <bool is_ad>
class DeformedGrainMaterialTempl : public GBEvolutionTempl<is_ad>
{
public:
  static InputParameters validParams();

  DeformedGrainMaterialTempl(const InputParameters & parameters);

protected:
  virtual void computeQpProperties();

  /// total number of grains
  const unsigned int _op_num;

  /// order parameter values
  const std::vector<const GenericVariableValue<is_ad> *> _vals;

  /// the average dislocation density
  const Real _dislocation_density_constant;

  /// whether an optional per-element dislocation density field is coupled
  const bool _has_rho_var;

  /// optional per-element dislocation density field (1/m^2); zero-valued reference when not coupled
  const GenericVariableValue<is_ad> * const _rho_var;

  /// optional per-grain dislocation density vector, indexed by grain_id (1/m^2)
  const std::vector<Real> _rho_per_grain;

  /// whether the per-grain dislocation density vector is non-empty
  const bool _has_rho_per_grain;

  /// the elastic modulus
  const Real _shear_modulus;

  /// the Length of Burger's Vector
  const Real _burgers_vector;

  /// the prefactor needed to calculate the deformation energy from dislocation density
  GenericMaterialProperty<Real, is_ad> & _beta;

  /// dislocation density in grain i
  GenericMaterialProperty<Real, is_ad> & _disloc_den_i;

  /// the average/effective dislocation density
  GenericMaterialProperty<Real, is_ad> & _rho_eff;

  /// the deformation energy
  GenericMaterialProperty<Real, is_ad> & _deformation_energy;

  // Constants

  /// number of deformed grains
  const unsigned int _deformed_grain_num;

  /// Grain tracker object
  const GrainTrackerDislocations & _grain_tracker;

  /// carries the information about dislocation density in each grain
  MaterialProperty<std::vector<Real>> & _grain_disloc_data;

  /// number of grains that are currently extant in the simulation
  unsigned int _num_active_grains;

  /// total number of grains that have existed/do exist in the simulation
  unsigned int _num_total_grains;
};

typedef DeformedGrainMaterialTempl<false> DeformedGrainMaterial;
typedef DeformedGrainMaterialTempl<true> ADDeformedGrainMaterial;
