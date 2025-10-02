//* This file is part of the MOOSE framework
//* https://mooseframework.inl.gov
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

#include "INSADMassAdditionBoundaryBC.h"
#include "SystemBase.h"
#include "ImplicitEuler.h"

registerMooseObject("NavierStokesApp", INSADMassAdditionBoundaryBC);

InputParameters
INSADMassAdditionBoundaryBC::validParams()
{
  InputParameters params = ADNodalBC::validParams();
  params.addClassDescription("Boundary condition for displacing a boundary");
  params.addRequiredCoupledVar("temperature", "The temperature variable");
  params.addRequiredParam<Real>("deposition_velocity", "Deposition velocity (m/s)");
  params.addParam<Real>("activation_temperature", 1700.0, "Activation temperature (K)");
  params.addParam<Real>("smooth_param", 40.0, "Smooth step width (K)");
  return params;
}

INSADMassAdditionBoundaryBC::INSADMassAdditionBoundaryBC(const InputParameters & parameters)
  : ADNodalBC(parameters),
    _u_old(_var.nodalValueOld()),
    _T(adCoupledValue("temperature")),
    _v_dep(getParam<Real>("deposition_velocity")),
    _T_act(getParam<Real>("activation_temperature")),
    _smooth_w(getParam<Real>("smooth_param"))
{
}

ADReal
INSADMassAdditionBoundaryBC::computeQpResidual()
{
  // smooth Heaviside:  H ~ 0.5*(1 + tanh((T - T_act)/w))
  const ADReal heaviside = 0.5 * (1.0 + std::tanh((_T[0] - _T_act) / _smooth_w));
  const ADReal new_height = _u_old + this->_dt * _v_dep * heaviside;
  return _u - new_height;
}
