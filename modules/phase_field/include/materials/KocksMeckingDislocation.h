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

class GrainTrackerDislocations;

/**
 * Per-quadrature-point Kocks-Mecking dislocation density evolution:
 *
 *   dρ/dt = γ̇ (k1 √ρ - k2_dyn ρ) - k2_stat ρ
 *
 * with k2_dyn the Estrin-Mecking form and k2_stat an Arrhenius static
 * recovery term. Integrated locally with backward-Euler + Newton. Outputs a
 * stateful MaterialProperty "rho" (m^-2) and a diagnostic "tau_flow" (Pa).
 */
template <bool is_ad>
class KocksMeckingDislocationTempl : public Material
{
public:
  static InputParameters validParams();

  KocksMeckingDislocationTempl(const InputParameters & parameters);

protected:
  virtual void initQpStatefulProperties() override;
  virtual void computeQpProperties() override;

  /// Local Newton solve in plain Real for the BE residual at the current QP.
  Real solveRho(Real rho_old, Real k1, Real k2_dyn, Real k2_stat, Real gdot, Real dt) const;

  /// k2_dyn(γ̇, T) in Estrin-Mecking form. Both args are plain Real.
  Real evalK2Dyn(Real gdot, Real T) const;

  /// k2_stat(T) Arrhenius.
  Real evalK2Stat(Real T) const;

  // ---- Output properties ----
  GenericMaterialProperty<Real, is_ad> & _rho;
  const MaterialProperty<Real> & _rho_old;
  GenericMaterialProperty<Real, is_ad> & _tau_flow;

  // ---- Coupled variables ----
  const GenericVariableValue<is_ad> & _gamma_dot;
  const GenericVariableValue<is_ad> & _Temp;

  // ---- Mechanism toggles ----
  const bool _enable_storage;
  const bool _enable_dyn_recovery;
  const bool _enable_stat_recovery;

  // ---- External-coefficient overrides ----
  const bool _use_ext_k1;
  const bool _use_ext_k2_dyn;
  const bool _use_ext_k2_stat;
  const MaterialProperty<Real> * const _k1_ext;
  const MaterialProperty<Real> * const _k2_dyn_ext;
  const MaterialProperty<Real> * const _k2_stat_ext;

  // ---- k1 internal params ----
  const Real _mu;
  const Real _b;
  const Real _L_obs;

  // ---- k2_dyn internal params (Estrin-Mecking) ----
  const Real _k20;
  const Real _Q_dyn;
  const Real _n_exp;
  const Real _gdot_ref;
  const Real _gdot_min;

  // ---- k2_stat internal params ----
  const Real _ks0;
  const Real _Q_climb;

  /// Multiplier converting Q_dyn, Q_climb to SI joules (1.0 if Q_units=J, eV→J otherwise).
  const Real _Q_to_J;

  // ---- Taylor relation ----
  const Real _tau0;
  const Real _M_taylor;
  const Real _alpha;

  // ---- Initial-condition source ----
  enum class IcSource
  {
    Constant,
    CoupledVar,
    MatProp
  };
  IcSource _ic_source;
  const Real _rho_init_const;
  const VariableValue * const _rho_init_var;
  const MaterialProperty<Real> * const _rho_init_prop;

  // ---- Numerical controls ----
  const Real _rho_min;
  const Real _T_min;
  const unsigned int _max_iter;
  const Real _tol;

  // ---- Grain-id gating ----
  const bool _gate_by_grain_id;
  const unsigned int _deformed_grain_num;
  const GrainTrackerDislocations * const _grain_tracker;
  const std::vector<const GenericVariableValue<is_ad> *> _vals;
  const unsigned int _op_num;
};

typedef KocksMeckingDislocationTempl<false> KocksMeckingDislocation;
typedef KocksMeckingDislocationTempl<true> ADKocksMeckingDislocation;
