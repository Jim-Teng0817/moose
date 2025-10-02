//* This file is part of the MOOSE framework
//* https://mooseframework.inl.gov
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

#include "INSADDummyMassAdditionBoundaryBC.h"

registerMooseObject("NavierStokesApp", INSADDummyMassAdditionBoundaryBC);

InputParameters
INSADDummyMassAdditionBoundaryBC::validParams()
{
  InputParameters params = ADIntegratedBC::validParams();
  params.addClassDescription("Boundary condition for displacing a boundary");
  params.addRequiredCoupledVar("temperature", "The temperature variable");
  return params;
}

INSADDummyMassAdditionBoundaryBC::INSADDummyMassAdditionBoundaryBC(
    const InputParameters & parameters)
  : ADIntegratedBC(parameters), _T(adCoupledValue("temperature"))
{
}

ADReal
INSADDummyMassAdditionBoundaryBC::computeQpResidual()
{
  const ADReal heaviside = _T[_qp];
  const ADReal new_height = this->_dt * 10e-3 * heaviside;
  return 0.0 * (_u[_qp] - new_height);
}
