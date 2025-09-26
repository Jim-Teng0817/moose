//* This file is part of the MOOSE framework
//* https://www.mooseframework.org
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

#include "ACGrGrPoly.h"

registerMooseObject("PhaseFieldApp", ACGrGrPoly);

InputParameters
ACGrGrPoly::validParams()
{
  InputParameters params = ACGrGrBase::validParams();
  params.addClassDescription("Grain-Boundary model poly-crystalline interface Allen-Cahn Kernel");
  // params.addParam<Real>("L_liq", "Latent heat term (L_liq)");                // added and modified for NE795 Project, Latent heat term (Jim Nov. 29, 2024)
  // params.addParam<Real>("T_liq", "Liquidus temperature (T_liq)");            // added and modified for NE795 Project, Latent heat term (Jim Nov. 29, 2024)
  // params.addCoupledVar("temp", "Coupled Temperature");                       // added and modified for NE795 Project, Latent heat term (Jim Nov. 29, 2024)
  return params;                                                                        //addRequiredParam
}

ACGrGrPoly::ACGrGrPoly(const InputParameters & parameters)
  : ACGrGrBase(parameters), _gamma(getMaterialProperty<Real>("gamma_asymm")) //,
    // _L_liq(getParam<Real>("L_liq")),                                      // added and modified for NE795 Project, Latent heat term (Jim Nov. 29, 2024)
    // _T_liq(getParam<Real>("T_liq")),                                      // added and modified for NE795 Project, Latent heat term (Jim Nov. 29, 2024)
    // _temp(coupledValue("temp"))                                        // added and modified for NE795 Project, Latent heat term (Jim Nov. 29, 2024)
{ 
}

Real
ACGrGrPoly::assignThisOp()
{
  return _u[_qp];
}

std::vector<Real>
ACGrGrPoly::assignOtherOps()
{
  std::vector<Real> other_ops(_op_num);
  for (unsigned int i = 0; i < _op_num; ++i)
    other_ops[i] = (*_vals[i])[_qp];

  return other_ops;
}

Real
ACGrGrPoly::computeDFDOP(PFFunctionType type)                   // temperary close for NE795 Project, Latent heat term (Jim Nov. 30, 2024)
{
  // assign op and other_ops
  Real op = assignThisOp();
  std::vector<Real> other_ops(_op_num);
  other_ops = assignOtherOps();

  // Sum all other order parameters
  Real SumOPj = 0.0;
  for (unsigned int i = 0; i < _op_num; ++i)
    SumOPj += other_ops[i] * other_ops[i];

  // Calculate either the residual or Jacobian of the grain growth free energy
  switch (type)
  {
    case Residual:
    {
      return _mu[_qp] * (op * op * op - op + 2.0 * _gamma[_qp] * op * SumOPj);
    }

    case Jacobian:
    {
      return _mu[_qp] * (_phi[_j][_qp] * (3.0 * op * op - 1.0 + 2.0 * _gamma[_qp] * SumOPj));
    }

    default:
      mooseError("Invalid type passed in");
  }
}

Real
ACGrGrPoly::computeQpOffDiagJacobian(unsigned int jvar)            // temperary close for NE795 Project, Latent heat term (Jim Nov. 30, 2024)
{
  // assign op and other_ops
  Real op = assignThisOp();
  std::vector<Real> other_ops(_op_num);
  other_ops = assignOtherOps();

  for (unsigned int i = 0; i < _op_num; ++i)
    if (jvar == _vals_var[i])
    {
      // Derivative of Sumopj
      const Real dSumOPj = 2.0 * other_ops[i] * _phi[_j][_qp];
      const Real dDFDOP = _mu[_qp] * 2.0 * _gamma[_qp] * op * dSumOPj;

      return _L[_qp] * _test[_i][_qp] * dDFDOP;
    }

  return 0.0;
}

// Real
// ACGrGrPoly::computeH()             // added and modified for NE795 Project, Latent heat term (Jim Nov. 30, 2024)
// {
//   Real h_phi = 0.0;
//   Real sum_pi = 0.0;

//   for (unsigned int i = 0; i < _op_num; ++i)
//   {
//     Real phi_i = (*_vals[i])[_qp];
//     Real p_i = phi_i * phi_i * phi_i * (20 - 45 * phi_i + 36 * phi_i * phi_i - 10 * phi_i * phi_i * phi_i);   // Interpolation Function for each order parameters
//     sum_pi += p_i;  // Summation of all the p_i including liquid phase
//     if (i == 0) // Assuming phi_0 is the liquid phase
//       h_phi = p_i;
//   }

//   return h_phi / sum_pi;
// }


// // Real
// // ACGrGrPoly::computeDHDPhi(Real op, const std::vector<Real> & other_ops)      // added and modified for NE795 Project, Latent heat term (Jim Nov. 30, 2024)
// // {
// //   Real numerator = 0.0;
// //   Real predenominator = 0.0;
// //   Real denominator = 0.0;

// //   for (unsigned int i = 0; i < _op_num; ++i)
// //   {
// //     Real phi_i = (i == 0 ? op : other_ops[i - 1]);
// //     Real p_i = phi_i * phi_i * phi_i * (20 - 45 * phi_i + 36 * phi_i * phi_i - 10 * phi_i * phi_i * phi_i);
// //     predenominator += p_i;

// //     if (i == 0)
// //     {
// //       numerator = 3 * phi_i * phi_i * (20 - 30 * phi_i + 12 * phi_i * phi_i - 10 * phi_i * phi_i * phi_i);
// //     }
// //   }

// //   denominator = predenominator * predenominator;

// //   return -(numerator / denominator);
// // }

// Real
// ACGrGrPoly::computeDHDPhi(Real op, const std::vector<Real> & other_ops)      // Added and modified for NE795 Project, Latent heat term (Jim Nov. 30, 2024)
// {
//   Real prenumerator = 0.0;
//   Real denominator = 0.0;
//   Real predenominator = 0.0;

//   // Compute the denominator and numerator
//   for (unsigned int i = 0; i < _op_num; ++i)
//   {
//     // Get phi_i (current order parameter)
//     Real phi_i = (i == 0 ? op : other_ops[i - 1]);

//     // Compute p_i(phi_i)
//     Real p_i = phi_i * phi_i * phi_i * (20 - 45 * phi_i + 36 * phi_i * phi_i - 10 * phi_i * phi_i * phi_i);
//     predenominator += p_i;

//     // Compute the derivative p_j'(phi_j)
//     prenumerator = 3 * phi_i * phi_i * (20 - 60 * phi_i + 60 * phi_i * phi_i - 20 * phi_i * phi_i * phi_i);
//   }

//   // Compute the denominator squared
//   denominator = predenominator * predenominator;

//   // Final result: -p_0 * p_j' / (sum(p_i)^2)
//   Real p_0 = op * op * op * (20 - 45 * op + 36 * op * op - 10 * op * op * op); // p_0(phi_0)
//   return -(p_0 * prenumerator / denominator);
// }


// Real
// ACGrGrPoly::computeDFDOP(PFFunctionType type)            // added and modified for NE795 Project, Latent heat term (Jim Nov. 30, 2024)
// {
//   // assign op and other_ops
//   Real op = assignThisOp();
//   std::vector<Real> other_ops(_op_num);
//   other_ops = assignOtherOps();

//   // Sum all other order parameters
//   Real SumOPj = 0.0;
//   for (unsigned int i = 0; i < _op_num; ++i)
//     SumOPj += other_ops[i] * other_ops[i];

//   // Calculate h(phi)
//   Real h_phi = computeH();

//   // Calculate either the Residual or Jacobian of the grain growth free energy
//   switch (type)
//   {
//     case Residual:
//     {
//       return _mu[_qp] * (op * op * op - op + 2.0 * _gamma[_qp] * op * SumOPj) +
//              _L_liq * (1.0 - _temp[_qp] / _T_liq) * h_phi;
//     }

//     case Jacobian:
//     {
//       Real dh_dphi = computeDHDPhi(op, other_ops); // Define a method to compute the derivative of h
//       return _mu[_qp] * (_phi[_j][_qp] * (3.0 * op * op - 1.0 + 2.0 * _gamma[_qp] * SumOPj)) +
//              _L_liq * (1.0 - _temp[_qp] / _T_liq) * dh_dphi;
//     }

//     default:
//       mooseError("Invalid type passed in");
//   }
// }


// Real
// ACGrGrPoly::computeQpOffDiagJacobian(unsigned int jvar)   // added and modified for NE795 Project, Latent heat term (Jim Nov. 30, 2024)
// {
//   // assign op and other_ops
//   Real op = assignThisOp();
//   std::vector<Real> other_ops(_op_num);
//   other_ops = assignOtherOps();

//   for (unsigned int i = 0; i < _op_num; ++i)
//     if (jvar == _vals_var[i])
//     {
//       // Derivative of Sumopj
//       const Real dSumOPj = 2.0 * other_ops[i] * _phi[_j][_qp];
//       const Real dDFDOP = _mu[_qp] * 2.0 * _gamma[_qp] * op * dSumOPj;

//       const Real dh_dphi = computeDHDPhi(op, other_ops);
//       return _L[_qp] * _test[_i][_qp] * (dDFDOP + _L_liq * (1.0 - _temp[_qp] / _T_liq) * dh_dphi);
//     }

//   return 0.0;
// }

