//* This file is part of the MOOSE framework
//* https://www.mooseframework.org
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

#pragma once

#include "ACGrGrBase.h"

// Forward Declarations

/**
 * This kernel calculates the residual for grain growth for a single phase,
 * poly-crystal system. A single material property gamma_asymm is used for
 * the prefactor of the cross-terms between order parameters.
 */
class ACGrGrPoly : public ACGrGrBase
{
public:
  static InputParameters validParams();

  ACGrGrPoly(const InputParameters & parameters);

protected:
  virtual Real assignThisOp();
  virtual std::vector<Real> assignOtherOps();
  virtual Real computeDFDOP(PFFunctionType type);
  virtual Real computeQpOffDiagJacobian(unsigned int jvar);

  const MaterialProperty<Real> & _gamma;   // Gamma for asymmetric energy term  


  // // Material properties        // added and modified for NE795 Project, Latent heat term (Jim Nov. 30, 2024)
  // Real _L_liq;   // Latent heat
  // Real _T_liq;   // Liquidus temperature
  // const VariableValue & _temp;             // Coupled temperature variable
  // virtual Real computeH();
  // virtual Real computeDHDPhi(Real op, const std::vector<Real> & other_ops);

};
