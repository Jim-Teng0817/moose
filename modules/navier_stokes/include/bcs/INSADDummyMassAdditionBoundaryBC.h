//* This file is part of the MOOSE framework
//* https://mooseframework.inl.gov
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

#pragma once

#include "ADNodalBC.h"

/**
 * Increments the boundary displacement by the product of the surface velocity and the change in
 * time through an implicit Euler disretization
 */
class INSADDummyMassAdditionBoundaryBC : public ADIntegratedBC
{
public:
  static InputParameters validParams();

  INSADDummyMassAdditionBoundaryBC(const InputParameters & parameters);

protected:
  virtual ADReal computeQpResidual() override;

  const ADVariableValue & _T; // temperature
};
