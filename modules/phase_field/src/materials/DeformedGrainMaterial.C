//* This file is part of the MOOSE framework
//* https://mooseframework.inl.gov
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

#include "DeformedGrainMaterial.h"
#include "GrainTrackerDislocations.h"

registerMooseObject("PhaseFieldApp", DeformedGrainMaterial);
registerMooseObject("PhaseFieldApp", ADDeformedGrainMaterial);

template <bool is_ad>
InputParameters
DeformedGrainMaterialTempl<is_ad>::validParams()
{
  InputParameters params = GBEvolutionTempl<is_ad>::validParams();
  params.addClassDescription("Compute spatially dependent dislocation density");
  params.addRequiredCoupledVarWithAutoBuild(
      "v", "var_name_base", "op_num", "Array of coupled variables");
  params.addRequiredParam<unsigned int>("deformed_grain_num",
                                        "Number of OP representing deformed grains");
  params.addParam<Real>("dislocation_density_constant", 9.0e15, "Dislocation Density in m^-2");
  params.addCoupledVar("rho_var",
                       "Optional per-element dislocation density field (1/m^2). If supplied, "
                       "takes precedence over Disloc_Den_per_grain and Disloc_Den.");
  params.addParam<std::vector<Real>>(
      "dislocation_density_per_grain",
      std::vector<Real>(),
      "Optional per-grain dislocation density vector indexed by grain_id (1/m^2). Used when "
      "rho_var is not coupled. Falls back to dislocation_density for out-of-range grain_ids.");
  params.addParam<Real>("shear_modulus", 2.50e10, "Elastic Modulus in J/m^3");
  params.addParam<Real>("burgers_vector", 3.0e-10, "Length of Burger Vector in m");
  params.addRequiredParam<UserObjectName>("grain_tracker",
                                          "The GrainTracker UserObject to get values from.");
  return params;
}

template <bool is_ad>
DeformedGrainMaterialTempl<is_ad>::DeformedGrainMaterialTempl(const InputParameters & parameters)
  : GBEvolutionTempl<is_ad>(parameters),
    _op_num(this->coupledComponents("v")),
    _vals(this->template coupledGenericValues<is_ad>("v")),
    _dislocation_density_constant(this->template getParam<Real>("dislocation_density_constant")),
    _has_rho_var(this->isCoupled("rho_var")),
    _rho_var(_has_rho_var ? &this->template coupledGenericValue<is_ad>("rho_var") : nullptr),
    _rho_per_grain(this->template getParam<std::vector<Real>>("dislocation_density_per_grain")),
    _has_rho_per_grain(!_rho_per_grain.empty()),
    _shear_modulus(this->template getParam<Real>("shear_modulus")),
    _burgers_vector(this->template getParam<Real>("burgers_vector")),
    _beta(this->template declareGenericProperty<Real, is_ad>("beta")),
    _disloc_den_i(this->template declareGenericProperty<Real, is_ad>("disloc_den_i")),
    _rho_eff(this->template declareGenericProperty<Real, is_ad>("rho_eff")),
    _deformation_energy(this->template declareGenericProperty<Real, is_ad>("deformation_energy")),
    _deformed_grain_num(this->template getParam<unsigned int>("deformed_grain_num")),
    _grain_tracker(this->template getUserObject<GrainTrackerDislocations>("grain_tracker")),
    _grain_disloc_data(this->template declareProperty<std::vector<Real>>("grain_disloc_data")),
    _num_active_grains(0),
    _num_total_grains(0)
{
  if (_op_num == 0)
    this->paramError("op_num", "Model requires op_num > 0");

  if (_has_rho_per_grain && _rho_per_grain.size() < _deformed_grain_num)
    mooseWarning("Disloc_Den_per_grain has size ",
                 _rho_per_grain.size(),
                 " but deformed_grain_num is ",
                 _deformed_grain_num,
                 "; entries past size will fall back to Disloc_Den.");
}

template <bool is_ad>
void
DeformedGrainMaterialTempl<is_ad>::computeQpProperties()
{
  GBEvolutionTempl<is_ad>::computeQpProperties();
  // calculate effective dislocation density and assign zero dislocation densities to undeformed
  // grains
  const auto & op_to_grains = _grain_tracker.getVarToFeatureVector(this->_current_elem->id());

  _num_active_grains = _grain_tracker.getNumberActiveGrains();
  _num_total_grains = _grain_tracker.getTotalFeatureCount();

  if (_num_total_grains != _grain_disloc_data[this->_qp].size())
    _grain_disloc_data[this->_qp].resize(_num_total_grains);

  // Pick per-QP rho using priority: rho_var > Disloc_Den_per_grain[grain_id] > Disloc_Den.
  GenericReal<is_ad> rho = _dislocation_density_constant;
  if (_has_rho_var)
    rho = (*_rho_var)[this->_qp];
  else if (_has_rho_per_grain)
  {
    // grain_id lookup matches the existing loop below - reuse the same op_to_grains query.
    // Pick the first active OP at this element and index into the vector. If grain_id is
    // out of range for the vector, rho stays at _Disloc_Den (the default above).
    for (MooseIndex(op_to_grains) op_index = 0; op_index < op_to_grains.size(); ++op_index)
    {
      auto grain_id = op_to_grains[op_index];
      if (grain_id == FeatureFloodCount::invalid_id)
        continue;
      if (grain_id < _rho_per_grain.size())
      {
        rho = _rho_per_grain[grain_id];
        break;
      }
    }
  }

  _disloc_den_i[this->_qp] = rho * (this->_length_scale * this->_length_scale);

  for (unsigned int index = 0; index < _grain_disloc_data[this->_qp].size(); ++index)
  {
    _grain_disloc_data[this->_qp][index] =
        _grain_tracker.getData(index) + MetaPhysicL::raw_value(_disloc_den_i[this->_qp]);
  }

  GenericReal<is_ad> rho_i = 0.0;
  GenericReal<is_ad> rho0 = 0.0;
  GenericReal<is_ad> SumEtai2 = 0.0;
  for (unsigned int i = 0; i < _op_num; ++i)
    SumEtai2 += (*_vals[i])[this->_qp] * (*_vals[i])[this->_qp];

  // loop over active OPs
  bool one_active = false;
  for (MooseIndex(op_to_grains) op_index = 0; op_index < op_to_grains.size(); ++op_index)
  {
    auto grain_id = op_to_grains[op_index];
    if (grain_id == FeatureFloodCount::invalid_id || grain_id >= _num_total_grains)
      continue;

    one_active = true;

    // if (grain_id >= _deformed_grain_num)
    //   rho_i = 0.0;
    // else
    rho_i = _grain_disloc_data[this->_qp][grain_id];
    rho0 += rho_i * (*_vals[op_index])[this->_qp] * (*_vals[op_index])[this->_qp];
  }

  if (!one_active && this->_t_step > 0)
    mooseError("No active order parameters");

  _rho_eff[this->_qp] = rho0 / SumEtai2;

  if (_rho_eff[this->_qp] < 1e-9)
  {
    _rho_eff[this->_qp] = 0.0;
    _disloc_den_i[this->_qp] = 0.0;
  }

  _beta[this->_qp] =
      0.5 * _shear_modulus * _burgers_vector * _burgers_vector * this->_JtoeV * this->_length_scale;

  // Compute the deformation energy
  _deformation_energy[this->_qp] = _beta[this->_qp] * _rho_eff[this->_qp];
}

template class DeformedGrainMaterialTempl<false>;
template class DeformedGrainMaterialTempl<true>;