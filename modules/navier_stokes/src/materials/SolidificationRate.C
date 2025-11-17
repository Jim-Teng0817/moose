//* This file is part of the MOOSE framework
//* https://mooseframework.inl.gov
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

// Navier-Stokes includes
#include "SolidificationRate.h"

registerMooseObject("NavierStokesApp", SolidificationRate);

InputParameters
SolidificationRate::validParams()
{
  InputParameters params = Material::validParams();
  params.addRequiredCoupledVar("temperature", "Temperature Variable");
  params.addRequiredParam<Real>("solidus_temperature", "Solidus temperature.");
  params.addRequiredParam<Real>("liquidus_temperature", "Liquidus temperature.");
  return params;
}

SolidificationRate::SolidificationRate(const InputParameters & parameters)
  : Material(parameters),
    _solidus_temperature(getParam<Real>("solidus_temperature")),
    _liquidus_temperature(getParam<Real>("liquidus_temperature")),
    // _thermal_conductivity(getADMaterialProperty<Real>("thermal_conductivity")),
    _temp_grad(adCoupledGradient("temperature")),
    _temp(adCoupledValue("temperature")),
    _temp_old(coupledValueOld("temperature")),
    _temp_gradient(declareProperty<Real>("temperature_gradient")),
    _cooling_rate(declareProperty<Real>("cooling_rate")),

    _temp_dot(adCoupledDot("temperature")),         // Time derivative of Temperature   // Added for instantaneous cooling rate (by Jim 20251021)

    _solidification_rate(declareProperty<Real>("solidification_rate")),
    _liquidus_time(declareProperty<Real>("liquidus_time")),
    _liquidus_time_old(getMaterialPropertyOld<Real>("liquidus_time")),
    _solidus_time(declareProperty<Real>("solidus_time")),
    _solidus_time_old(getMaterialPropertyOld<Real>("solidus_time"))
{
}

void
SolidificationRate::initQpStatefulProperties()
{
  _solidus_time[_qp] = 0.0;
  _liquidus_time[_qp] = 0.0;
}

void
SolidificationRate::computeQpProperties()
{
  if (MetaPhysicL::raw_value(_temp[_qp]) > _liquidus_temperature &&
      _liquidus_time_old[_qp] < 1.0e-8)
    _liquidus_time[_qp] = _t;
  else
    _liquidus_time[_qp] = _liquidus_time_old[_qp];

  if ((_liquidus_time_old[_qp] > 0.0 &&
       MetaPhysicL::raw_value(_temp[_qp]) < _solidus_temperature) &&
      _solidus_time_old[_qp] < 1.0e-8)
    _solidus_time[_qp] = _t;
  else
    _solidus_time[_qp] = _solidus_time_old[_qp];

  // if (_liquidus_time[_qp] > 1.0e-8 && _solidus_time[_qp] > 1.0e-8)
  //   _cooling_rate[_qp] = std::abs((_liquidus_temperature - _solidus_temperature) /
  //                                 (_liquidus_time[_qp] - _solidus_time[_qp]));
  // else
  //   _cooling_rate[_qp] = 0.0;

  // _temp_gradient[_qp] = MetaPhysicL::raw_value(_temp_grad[_qp].norm() / _thermal_conductivity[_qp]);
  _temp_gradient[_qp] = MetaPhysicL::raw_value(_temp_grad[_qp].norm());

  // _solidification_rate[_qp] = 1.0 / _temp_gradient[_qp] * _cooling_rate[_qp];

  // _cooling_rate[_qp] = MetaPhysicL::raw_value(_temp_dot[_qp]);   // Modified for instantaneous signed cooling rate (by Jim 20251021)
  _cooling_rate[_qp] = std::abs(MetaPhysicL::raw_value(_temp_dot[_qp]));   // Modified for instantaneous unsigned cooling rate (by Jim 20251021)

  // if (_liquidus_time[_qp] > 1.0e-8 && _solidus_time[_qp] > 1.0e-8)
  //   _solidification_rate[_qp] = 1.0 / _temp_gradient[_qp] * std::abs( _cooling_rate[_qp] );
  // else
  //   _solidification_rate[_qp] = 0.0;

  if (_liquidus_time[_qp] > 1.0e-8 &&
     MetaPhysicL::raw_value(_temp[_qp]) < _liquidus_temperature &&
    _solidus_time[_qp] < 1.0e-8)
    _solidification_rate[_qp] = 1.0 / _temp_gradient[_qp] * std::abs( _cooling_rate[_qp] );
  else
    _solidification_rate[_qp] = 0.0;
}
