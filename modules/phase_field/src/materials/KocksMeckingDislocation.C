//* This file is part of the MOOSE framework
//* https://mooseframework.inl.gov
//*
//* All rights reserved, see COPYRIGHT for full restrictions
//* https://github.com/idaholab/moose/blob/master/COPYRIGHT
//*
//* Licensed under LGPL 2.1, please see LICENSE for details
//* https://www.gnu.org/licenses/lgpl-2.1.html

#include "KocksMeckingDislocation.h"
#include "GrainTrackerDislocations.h"
#include "FeatureFloodCount.h"

registerMooseObject("PhaseFieldApp", KocksMeckingDislocation);
registerMooseObject("PhaseFieldApp", ADKocksMeckingDislocation);

namespace
{
constexpr Real kB_SI = 1.380649e-23; // J/K
constexpr Real eV_to_J = 1.602176634e-19;
}

template <bool is_ad>
InputParameters
KocksMeckingDislocationTempl<is_ad>::validParams()
{
  InputParameters params = Material::validParams();
  params.addClassDescription(
      "Kocks-Mecking dislocation density evolution with optional Estrin-Mecking dynamic recovery "
      "and Arrhenius static recovery, integrated with backward-Euler + local Newton.");

  params.addRequiredCoupledVar("gamma_dot", "Plastic shear strain rate (1/s).");
  params.addRequiredCoupledVar("T", "Temperature in Kelvin.");

  // Mechanism toggles
  params.addParam<bool>("enable_storage", true, "Enable the k1·√ρ storage term.");
  params.addParam<bool>("enable_dynamic_recovery", true, "Enable γ̇·k2_dyn·ρ dynamic recovery.");
  params.addParam<bool>("enable_static_recovery", false, "Enable k2_stat·ρ static recovery.");

  // External coefficient sources
  params.addParam<MaterialPropertyName>(
      "k1_name", "", "Optional external material property for k1.");
  params.addParam<MaterialPropertyName>(
      "k2_dyn_name", "", "Optional external material property for k2_dyn.");
  params.addParam<MaterialPropertyName>(
      "k2_stat_name", "", "Optional external material property for k2_stat.");

  // k1 internal params
  params.addParam<Real>("mu", 4.2e10, "Shear modulus (Pa).");
  params.addParam<Real>("b", 2.56e-10, "Burgers vector magnitude (m).");
  params.addParam<Real>("L_obs", 1.0e-6, "Obstacle spacing for k1 = μb/(2π L_obs) (m).");

  // k2_dyn (Estrin-Mecking)
  params.addParam<Real>("k20", 0.0, "Prefactor for k2_dyn.");
  params.addParam<Real>("Q_dyn", 0.0, "Activation energy for dynamic recovery.");
  params.addParam<Real>("n_exp", 1.0, "Strain-rate sensitivity exponent.");
  params.addParam<Real>("gdot_ref", 1.0, "Reference strain rate in Estrin-Mecking k2_dyn (1/s).");
  params.addParam<Real>("gdot_min", 1.0e-12, "Floor on |γ̇| to keep k2_dyn finite as γ̇→0.");

  // k2_stat (Arrhenius)
  params.addParam<Real>("ks0", 0.0, "Prefactor for k2_stat (1/s).");
  params.addParam<Real>("Q_climb", 0.0, "Activation energy for static recovery (vacancy climb).");

  // Q units
  MooseEnum q_units("J eV", "J");
  params.addParam<MooseEnum>("Q_units", q_units, "Units for Q_dyn and Q_climb.");

  // Taylor flow stress
  params.addParam<Real>("tau0", 0.0, "Lattice friction stress τ0 (Pa).");
  params.addParam<Real>("M_taylor", 3.06, "Taylor factor.");
  params.addParam<Real>("alpha", 0.3, "Taylor coefficient α.");

  // Initial condition
  params.addParam<Real>("rho_init", 0.0, "Constant initial dislocation density (1/m^2).");
  params.addCoupledVar("rho_init_var",
                       "Optional coupled variable giving spatial initial ρ; overrides rho_init.");
  params.addParam<MaterialPropertyName>(
      "rho_init_prop",
      "",
      "Optional material property giving spatial initial ρ; overrides rho_init and rho_init_var.");

  // Numerical controls
  params.addParam<Real>("rho_min", 1.0e6, "Floor on ρ (1/m^2).");
  params.addParam<Real>("T_min", 1.0, "Floor on T inside Arrhenius factors (K).");
  params.addParam<unsigned int>("max_newton_iter", 50, "Maximum local Newton iterations.");
  params.addParam<Real>("newton_tol", 1.0e-10, "Relative tolerance for local Newton.");

  // output_length_scale (orig plan §2.7) is intentionally omitted: the SI
  // default is correct for the DeformedGrainMaterial consumer chain (which
  // does its own length_scale^2 rescaling) and a non-trivial value here
  // would diverge AD and non-AD paths. See revised plan §2.7 and the
  // reviewer note at plan lines 507-510.

  // Grain-id gating
  params.addParam<bool>("gate_by_grain_id",
                        false,
                        "Force ρ→0 at QPs whose dominant grain (largest η²) is recrystallized "
                        "(grain_id ≥ deformed_grain_num).");
  params.addParam<UserObjectName>("grain_tracker", "", "GrainTrackerDislocations user object.");
  params.addParam<unsigned int>(
      "deformed_grain_num", 0, "Number of OPs representing deformed grains.");
  params.addCoupledVarWithAutoBuild(
      "v", "var_name_base", "op_num", "Array of order parameter variables (for grain-id gate).");

  return params;
}

template <bool is_ad>
KocksMeckingDislocationTempl<is_ad>::KocksMeckingDislocationTempl(
    const InputParameters & parameters)
  : Material(parameters),
    _rho(this->template declareGenericProperty<Real, is_ad>("rho")),
    _rho_old(this->template getMaterialPropertyOld<Real>("rho")),
    _tau_flow(this->template declareGenericProperty<Real, is_ad>("tau_flow")),
    _gamma_dot(this->template coupledGenericValue<is_ad>("gamma_dot")),
    _Temp(this->template coupledGenericValue<is_ad>("T")),
    _enable_storage(getParam<bool>("enable_storage")),
    _enable_dyn_recovery(getParam<bool>("enable_dynamic_recovery")),
    _enable_stat_recovery(getParam<bool>("enable_static_recovery")),
    _use_ext_k1(!getParam<MaterialPropertyName>("k1_name").empty()),
    _use_ext_k2_dyn(!getParam<MaterialPropertyName>("k2_dyn_name").empty()),
    _use_ext_k2_stat(!getParam<MaterialPropertyName>("k2_stat_name").empty()),
    _k1_ext(_use_ext_k1
                ? &getMaterialPropertyByName<Real>(getParam<MaterialPropertyName>("k1_name"))
                : nullptr),
    _k2_dyn_ext(_use_ext_k2_dyn ? &getMaterialPropertyByName<Real>(
                                      getParam<MaterialPropertyName>("k2_dyn_name"))
                                : nullptr),
    _k2_stat_ext(_use_ext_k2_stat ? &getMaterialPropertyByName<Real>(
                                        getParam<MaterialPropertyName>("k2_stat_name"))
                                  : nullptr),
    _mu(getParam<Real>("mu")),
    _b(getParam<Real>("b")),
    _L_obs(getParam<Real>("L_obs")),
    _k20(getParam<Real>("k20")),
    _Q_dyn(getParam<Real>("Q_dyn")),
    _n_exp(getParam<Real>("n_exp")),
    _gdot_ref(getParam<Real>("gdot_ref")),
    _gdot_min(getParam<Real>("gdot_min")),
    _ks0(getParam<Real>("ks0")),
    _Q_climb(getParam<Real>("Q_climb")),
    _Q_to_J(getParam<MooseEnum>("Q_units") == "eV" ? eV_to_J : 1.0),
    _tau0(getParam<Real>("tau0")),
    _M_taylor(getParam<Real>("M_taylor")),
    _alpha(getParam<Real>("alpha")),
    _ic_source(IcSource::Constant),
    _rho_init_const(getParam<Real>("rho_init")),
    _rho_init_var(isCoupled("rho_init_var") ? &coupledValue("rho_init_var") : nullptr),
    _rho_init_prop(
        !getParam<MaterialPropertyName>("rho_init_prop").empty()
            ? &getMaterialPropertyByName<Real>(getParam<MaterialPropertyName>("rho_init_prop"))
            : nullptr),
    _rho_min(getParam<Real>("rho_min")),
    _T_min(getParam<Real>("T_min")),
    _max_iter(getParam<unsigned int>("max_newton_iter")),
    _tol(getParam<Real>("newton_tol")),
    _gate_by_grain_id(getParam<bool>("gate_by_grain_id")),
    _deformed_grain_num(getParam<unsigned int>("deformed_grain_num")),
    _grain_tracker(_gate_by_grain_id ? &getUserObject<GrainTrackerDislocations>("grain_tracker")
                                     : nullptr),
    _vals(this->template coupledGenericValues<is_ad>("v")),
    _op_num(this->coupledComponents("v"))
{
  // Resolve IC precedence: matprop > coupled var > constant.
  if (_rho_init_prop)
    _ic_source = IcSource::MatProp;
  else if (_rho_init_var)
    _ic_source = IcSource::CoupledVar;

  if (_n_exp <= 0.0)
    paramError("n_exp", "n_exp must be positive (got ", _n_exp, ").");
  if (_gdot_min <= 0.0)
    paramError("gdot_min", "gdot_min must be positive.");
  if (_rho_min <= 0.0)
    paramError("rho_min", "rho_min must be positive.");
  if (_gate_by_grain_id && _op_num == 0)
    paramError("v", "gate_by_grain_id=true requires the OP array 'v' to be coupled (op_num > 0).");
}

template <bool is_ad>
void
KocksMeckingDislocationTempl<is_ad>::initQpStatefulProperties()
{
  Real rho0 = _rho_init_const;
  switch (_ic_source)
  {
    case IcSource::CoupledVar:
      rho0 = (*_rho_init_var)[_qp];
      break;
    case IcSource::MatProp:
      rho0 = (*_rho_init_prop)[_qp];
      break;
    case IcSource::Constant:
    default:
      break;
  }
  _rho[_qp] = std::max(rho0, _rho_min);
  _tau_flow[_qp] = _tau0 + _M_taylor * _alpha * _mu * _b * std::sqrt(_rho[_qp]);
}

template <bool is_ad>
Real
KocksMeckingDislocationTempl<is_ad>::evalK2Dyn(Real gdot, Real T) const
{
  const Real g = std::max(std::abs(gdot), _gdot_min);
  const Real Tc = std::max(T, _T_min);
  const Real Qj = _Q_dyn * _Q_to_J;
  return _k20 * std::pow(_gdot_ref / g, 1.0 / _n_exp) * std::exp(-Qj / (_n_exp * kB_SI * Tc));
}

template <bool is_ad>
Real
KocksMeckingDislocationTempl<is_ad>::evalK2Stat(Real T) const
{
  const Real Tc = std::max(T, _T_min);
  const Real Qj = _Q_climb * _Q_to_J;
  return _ks0 * std::exp(-Qj / (kB_SI * Tc));
}

template <bool is_ad>
Real
KocksMeckingDislocationTempl<is_ad>::solveRho(
    Real rho_old, Real k1, Real k2_dyn, Real k2_stat, Real gdot, Real dt) const
{
  // Backward-Euler Newton on F(ρ) = ρ - ρ_old - dt·RHS(ρ),
  // RHS(ρ) = γ̇·k1·√ρ - γ̇·k2_dyn·ρ - k2_stat·ρ.
  // F is monotone in ρ over [rho_min, ∞), so Newton converges without line search.
  Real rho = std::max(rho_old, _rho_min);
  for (unsigned int it = 0; it < _max_iter; ++it)
  {
    const Real sqrt_rho = std::sqrt(rho);
    const Real rhs = gdot * k1 * sqrt_rho - gdot * k2_dyn * rho - k2_stat * rho;
    const Real drhs = (sqrt_rho > 0.0 ? 0.5 * gdot * k1 / sqrt_rho : 0.0) - gdot * k2_dyn - k2_stat;
    const Real F = rho - rho_old - dt * rhs;
    const Real dF = 1.0 - dt * drhs;
    if (dF == 0.0)
      break;
    const Real delta = -F / dF;
    const Real rho_new = std::max(_rho_min, rho + delta);
    if (std::abs(rho_new - rho) < _tol * std::max(rho_new, _rho_min))
    {
      rho = rho_new;
      break;
    }
    rho = rho_new;
  }
  return rho;
}

template <bool is_ad>
void
KocksMeckingDislocationTempl<is_ad>::computeQpProperties()
{
  // Grain-id gate (η²-weighted dominant OP wins, matching DeformedGrainMaterial.C:128-141).
  if (_gate_by_grain_id && _grain_tracker)
  {
    const auto & op_to_grains = _grain_tracker->getVarToFeatureVector(_current_elem->id());
    unsigned int dom_op = 0;
    Real dom_eta2 = -1.0;
    for (MooseIndex(op_to_grains) op_index = 0; op_index < op_to_grains.size(); ++op_index)
    {
      const auto gid = op_to_grains[op_index];
      if (gid == FeatureFloodCount::invalid_id)
        continue;
      if (op_index >= _op_num)
        continue;
      const Real eta = MetaPhysicL::raw_value((*_vals[op_index])[_qp]);
      const Real eta2 = eta * eta;
      if (eta2 > dom_eta2)
      {
        dom_eta2 = eta2;
        dom_op = op_index;
      }
    }
    if (dom_eta2 >= 0.0)
    {
      const auto dom_gid = op_to_grains[dom_op];
      if (dom_gid != FeatureFloodCount::invalid_id && dom_gid >= _deformed_grain_num)
      {
        _rho[_qp] = 0.0;
        _tau_flow[_qp] = _tau0;
        return;
      }
    }
  }

  const Real rho_old = _rho_old[_qp];
  const Real gdot_r = std::abs(MetaPhysicL::raw_value(_gamma_dot[_qp]));
  const Real T_r = MetaPhysicL::raw_value(_Temp[_qp]);

  const Real k1 = _enable_storage
                      ? (_use_ext_k1 ? (*_k1_ext)[_qp] : _mu * _b / (2.0 * libMesh::pi * _L_obs))
                      : 0.0;
  const Real k2_dyn =
      _enable_dyn_recovery ? (_use_ext_k2_dyn ? (*_k2_dyn_ext)[_qp] : evalK2Dyn(gdot_r, T_r)) : 0.0;
  const Real k2_stat =
      _enable_stat_recovery ? (_use_ext_k2_stat ? (*_k2_stat_ext)[_qp] : evalK2Stat(T_r)) : 0.0;

  const Real rho_star = solveRho(rho_old, k1, k2_dyn, k2_stat, gdot_r, _dt);

  if constexpr (is_ad)
  {
    using std::abs;
    using std::exp;
    using std::max;
    using std::pow;
    using std::sqrt;

    // Implicit-function-theorem assembly of dρ/dγ̇ and dρ/dT at the converged ρ*.
    // Build F(γ̇, T) as ADReal with ρ frozen at ρ*, then ρ_ad.derivatives = -F.derivatives()/F_ρ.
    const ADReal gdot_abs = abs(_gamma_dot[_qp]);
    const ADReal gdot_eff = max(gdot_abs, ADReal(_gdot_min));
    const ADReal T_eff = max(_Temp[_qp], ADReal(_T_min));
    const Real sqrt_rho_star = std::sqrt(std::max(rho_star, _rho_min));

    ADReal k1_ad = k1;
    ADReal k2_dyn_ad = k2_dyn;
    ADReal k2_stat_ad = k2_stat;
    // Only the internal closed-form k2_dyn(γ̇,T), k2_stat(T) carry AD; external matprops are Real.
    if (_enable_dyn_recovery && !_use_ext_k2_dyn)
    {
      const Real Qj = _Q_dyn * _Q_to_J;
      k2_dyn_ad =
          _k20 * pow(_gdot_ref / gdot_eff, 1.0 / _n_exp) * exp(-Qj / (_n_exp * kB_SI * T_eff));
    }
    if (_enable_stat_recovery && !_use_ext_k2_stat)
    {
      const Real Qj = _Q_climb * _Q_to_J;
      k2_stat_ad = _ks0 * exp(-Qj / (kB_SI * T_eff));
    }

    const ADReal rhs_ad =
        gdot_eff * k1_ad * sqrt_rho_star - gdot_eff * k2_dyn_ad * rho_star - k2_stat_ad * rho_star;
    const ADReal F_ad = ADReal(rho_star) - ADReal(rho_old) - _dt * rhs_ad;

    const Real drhs_drho =
        (sqrt_rho_star > 0.0 ? 0.5 * gdot_r * k1 / sqrt_rho_star : 0.0) - gdot_r * k2_dyn - k2_stat;
    const Real F_rho = 1.0 - _dt * drhs_drho;
    const Real inv_F_rho = (F_rho != 0.0 ? 1.0 / F_rho : 0.0);

    ADReal rho_ad = rho_star;
    rho_ad.derivatives() = -inv_F_rho * F_ad.derivatives();
    _rho[_qp] = rho_ad;

    _tau_flow[_qp] = _tau0 + _M_taylor * _alpha * _mu * _b * sqrt(rho_ad);
  }
  else
  {
    _rho[_qp] = rho_star;
    _tau_flow[_qp] = _tau0 + _M_taylor * _alpha * _mu * _b * std::sqrt(rho_star);
  }
}

template class KocksMeckingDislocationTempl<false>;
template class KocksMeckingDislocationTempl<true>;
