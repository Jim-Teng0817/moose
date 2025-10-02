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
class INSADMassAdditionBoundaryBC : public ADNodalBC
{
public:
  static InputParameters validParams();

  INSADMassAdditionBoundaryBC(const InputParameters & parameters);

protected:
  virtual ADReal computeQpResidual() override;

  const Real & _u_old;        // previous mesh displacement component
  const ADVariableValue & _T; // temperature
  const Real _v_dep;          // deposition speed (m/s)
  const Real _T_act;          // activation temperature (K)
  const Real _smooth_w;       // smoothing width for Heaviside (K)
};
