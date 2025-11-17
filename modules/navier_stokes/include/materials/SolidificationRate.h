//* This file is part of the MOOSE framework
//* https://mooseframework.inl.gov
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

#pragma once

#include "Material.h"
/**
 * This class computes delta function (derivative of the Heaviside function) given by a level set
 */
class SolidificationRate : public Material
{
public:
  static InputParameters validParams();

  SolidificationRate(const InputParameters & parameters);
  virtual void initQpStatefulProperties() override;

protected:
  void computeQpProperties() override;

  /// Solidus temperature
  const Real & _solidus_temperature;

  /// Liquidus  temperature
  const Real & _liquidus_temperature;

  // const ADMaterialProperty<Real> & _thermal_conductivity;

  const ADVectorVariableValue & _temp_grad;

 
  const ADVariableValue & _temp;
  const VariableValue & _temp_old;

  MaterialProperty<Real> & _temp_gradient;

  MaterialProperty<Real> & _cooling_rate;

  const ADVariableValue & _temp_dot;         // Time derivative of Temperature   // Added for instantaneous cooling rate (by Jim 20251021)

  MaterialProperty<Real> & _solidification_rate;

  MaterialProperty<Real> & _liquidus_time;
  const MaterialProperty<Real> & _liquidus_time_old;
  MaterialProperty<Real> & _solidus_time;
  const MaterialProperty<Real> & _solidus_time_old;
};
