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

  params.addRequiredParam<Real>("powder_feeding_rate", "Powder feeding rate (g/min)");        // Added for ALE Mod. PFR (Jim Nov. 17, 2025)
  params.addRequiredParam<Real>("laser_scan_velocity", "Laser scan velocity (m/s)");          // Added for ALE Mod. PFR (Jim Nov. 17, 2025)

  // params.addRequiredParam<Real>("deposition_velocity", "Deposition velocity (m/s)");       // Removed for ALE Mod. PFR (Jim Nov. 17, 2025)
  params.addParam<Real>("deposition_velocity", 0.0, "Deposition velocity (m/s)");             // Added for ALE Mod. PFR (Jim Nov. 17, 2025)

  params.addParam<Real>("activation_temperature", 1708.0, "Activation temperature (K)");
  params.addParam<Real>("smooth_param", 40.0, "Smooth step width (K)");
  return params;
}

INSADMassAdditionBoundaryBC::INSADMassAdditionBoundaryBC(const InputParameters & parameters)
  : ADNodalBC(parameters),
    _u_old(_var.nodalValueOld()),
    _T(adCoupledValue("temperature")),
    _v_dep(getParam<Real>("deposition_velocity")),

    _F(getParam<Real>("powder_feeding_rate")),                // Added for ALE Mod. PFR (Jim Nov. 17, 2025)
    _v_s(getParam<Real>("laser_scan_velocity")),              // Added for ALE Mod. PFR (Jim Nov. 17, 2025)

    _T_act(getParam<Real>("activation_temperature")),
    _smooth_w(getParam<Real>("smooth_param"))
{
}

// ADReal                                                                              // Removed for ALE Mod. PFR (Jim Nov. 17, 2025)
// INSADMassAdditionBoundaryBC::computeQpResidual()
// {
//   // smooth Heaviside:  H ~ 0.5*(1 + tanh((T - T_act)/w))
//   const ADReal heaviside = 0.5 * (1.0 + std::tanh((_T[0] - _T_act) / _smooth_w));
//   const ADReal new_height = _u_old + this->_dt * _v_dep * heaviside;
//   return _u - new_height;
// }

ADReal                                                                                 // Addeded for ALE Mod. PFR (Jim Nov. 17, 2025)
INSADMassAdditionBoundaryBC::computeQpResidual()
{
    // Smooth Heaviside activation:  H ~ 0.5*(1 + tanh((T - T_act)/w))
    const ADReal heaviside = 0.5 * (1.0 + tanh((_T[0] - _T_act) / _smooth_w));

    // Effective deposition velocity (top surface only)
    const ADReal v_dep_top = _v_dep * (_F/_v_s);  // simple linear scaling with powder rate
    const ADReal new_height = _u_old + _dt * v_dep_top * heaviside;

    return _u - new_height;
}
