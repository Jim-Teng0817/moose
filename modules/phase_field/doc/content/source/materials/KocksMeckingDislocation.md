# KocksMeckingDislocation / ADKocksMeckingDislocation

!syntax description /Materials/KocksMeckingDislocation

## Overview

`KocksMeckingDislocation` is a per-quadrature-point, stateful material that evolves the total
dislocation density $\rho$ via a Kocks-Mecking-Estrin ordinary differential equation with
optional static (thermal) recovery. The equation is integrated locally with a backward-Euler
Newton solve at every time step. Two material properties are produced: `rho`
(stateful, $\mathrm{m}^{-2}$) and the Taylor flow stress `tau_flow` (Pa).

The material sits between the imposed plastic activity, supplied as a coupled
strain-rate variable, and the polycrystal stored-energy chain. The natural downstream
consumer is [DeformedGrainMaterial.md], which reads $\rho$ through its
[!param](/Materials/DeformedGrainMaterial/rho_var) coupled variable and forms the deformation
energy that drives [PolycrystalStoredEnergy](PolycrystalStoredEnergy.md) kernels.
`KocksMeckingDislocation` is the single source of truth for $\rho$ in the recrystallization
workflow; it supersedes the per-grain `UserObject` and `AuxKernel` pair that earlier designs
used to populate `rho_grain` from a grain-indexed vector.

## Theory

### Evolution equation

`KocksMeckingDislocation` solves

\begin{equation}
\frac{d\rho}{dt} = k_1 \, |\dot{\gamma}| \, \sqrt{\rho}
                 - k_{2,\text{dyn}} \, |\dot{\gamma}| \, \rho
                 - k_{2,\text{stat}} \, \rho
\label{eq:km-ode}
\end{equation}

where each of the three terms can be independently disabled through
[!param](/Materials/KocksMeckingDislocation/enable_storage),
[!param](/Materials/KocksMeckingDislocation/enable_dynamic_recovery), and
[!param](/Materials/KocksMeckingDislocation/enable_static_recovery). The storage
coefficient follows the classical Kocks-Mecking-Estrin form

\begin{equation}
k_1 = \frac{\mu \, b}{2 \pi \, L_{\text{obs}}}
\label{eq:k1}
\end{equation}

with shear modulus $\mu$, Burgers vector magnitude $b$, and obstacle spacing $L_{\text{obs}}$.

### Dynamic-recovery coefficient (Estrin-Mecking form)

The dynamic-recovery coefficient uses the strain-rate- and temperature-sensitive
Estrin-Mecking form [!citep](estrin1996dislocation, kocks2003physics)

\begin{equation}
k_{2,\text{dyn}} = k_{20} \, \left(\frac{\dot{\gamma}_\text{ref}}{|\dot{\gamma}|}\right)^{1/n}
                   \exp\!\left( -\frac{Q_\text{dyn}}{n \, k_B \, T} \right)
\label{eq:k2dyn}
\end{equation}

with strain-rate sensitivity exponent $n$, reference strain rate $\dot{\gamma}_\text{ref}$, and
activation energy $Q_\text{dyn}$. This form is required to reproduce the experimentally
observed trend that the saturation dislocation density rises with strain rate. The product
that controls dynamic-recovery throughput is

\begin{equation}
|\dot{\gamma}| \, k_{2,\text{dyn}}
  = k_{20} \, |\dot{\gamma}|^{(n-1)/n} \, \dot{\gamma}_\text{ref}^{1/n} \,
    \exp\!\left( -\frac{Q_\text{dyn}}{n \, k_B \, T} \right)
\label{eq:gdot-k2dyn}
\end{equation}

which *grows* with $|\dot{\gamma}|$ for $n>1$. The earlier inverse-$\dot{\gamma}$
parameterization gave the opposite trend and is not used here.

### Static-recovery coefficient

Static recovery is a thermally activated Arrhenius rate

\begin{equation}
k_{2,\text{stat}} = k_\text{stat,0} \, \exp\!\left( -\frac{Q_\text{climb}}{k_B \, T} \right)
\label{eq:k2stat}
\end{equation}

where $Q_\text{climb}$ is the activation energy for the climb / annihilation process. For
pure Cu the default vacancy-migration value $Q_\text{climb} \approx 1.5\ \mathrm{eV}$
[!citep](balluffi1978vacancy) is used; the lattice self-diffusion value
$\approx 2.1\ \mathrm{eV}$ becomes more appropriate above $\approx 0.5\,T_m$. Boltzmann's
constant $k_B = 1.380649 \times 10^{-23}\ \mathrm{J\,K^{-1}}$ is hard-coded.
[!param](/Materials/KocksMeckingDislocation/Q_units) selects whether $Q_\text{dyn}$ and
$Q_\text{climb}$ are supplied in $\mathrm{J}$ (default) or $\mathrm{eV}$.

### Flow stress

The Taylor relation [!citep](taylor1934mechanism)

\begin{equation}
\tau_\text{flow} = \tau_0 + M \, \alpha \, \mu \, b \, \sqrt{\rho}
\label{eq:taylor}
\end{equation}

is reported as the diagnostic property `tau_flow`. It is not used internally; mechanical
closure is left to whatever `tensor_mechanics` model the user couples in.

### Saturation density

At constant $T$ and constant $|\dot{\gamma}|>0$ the steady-state solution of
[eq:km-ode] is

\begin{equation}
\rho_\text{sat} = \left[ \frac{k_1}
   {k_{2,\text{dyn}} + k_{2,\text{stat}}/|\dot{\gamma}|} \right]^{2}
\label{eq:rho-sat}
\end{equation}

Because $|\dot{\gamma}| \, k_{2,\text{dyn}}$ in [eq:gdot-k2dyn] grows with $|\dot{\gamma}|$
for $n>1$, $\rho_\text{sat}$ rises with strain rate, recovering the expected
experimental trend. For $|\dot{\gamma}| \rightarrow 0$ the static-recovery branch dominates
and $\rho \rightarrow 0$.

### Local Newton solve

A backward-Euler step yields the residual

\begin{equation}
F(\rho) = \rho - \rho_\text{old} - \Delta t \left[
    \mathbb{1}_{\text{stor}} \, k_1 \, |\dot{\gamma}| \, \sqrt{\rho}
  - \mathbb{1}_{\text{dyn}}  \, k_{2,\text{dyn}} \, |\dot{\gamma}| \, \rho
  - \mathbb{1}_{\text{stat}} \, k_{2,\text{stat}} \, \rho \right]
\label{eq:newton-residual}
\end{equation}

and is driven to zero by a Newton iteration that compares the post-clamp increment against
the post-clamp magnitude, ensuring the convergence test is unaffected by the $\rho$-floor.
A $\rho$-floor ([!param](/Materials/KocksMeckingDislocation/rho_min)) and a temperature floor
guard $\sqrt{\rho}$ and the Arrhenius exponentials respectively. Because $F$ is monotone in
$\rho$ over $[\rho_\text{min}, \infty)$ for non-negative coefficients and $\Delta t > 0$, no
line search is required.

### AD variant

The material is implemented as a templated class `KocksMeckingDislocationTempl<is_ad>` that
provides both the standard (`KocksMeckingDislocation`) and automatic-differentiation
(`ADKocksMeckingDislocation`) instantiations. The local Newton solve runs in plain
`Real`; the converged $\rho^\star$ is then promoted to an `ADReal` whose seed derivatives
with respect to the coupled $\dot{\gamma}$ and $T$ are assembled from the implicit-function
theorem applied to [eq:newton-residual]. AD chain-rule therefore propagates correctly
through downstream consumers that use $\rho$ in a Jacobian-sensitive way.

## Numerical considerations

Backward Euler is unconditionally stable on the linear static-recovery branch but is only
first-order accurate. Two regimes warrant attention:

- *Stiff static-recovery regime.* When $k_{2,\text{stat}} \, \Delta t \gg 1$ a single step
  decays $\rho$ to nearly zero. The result is stable but inaccurate; refine $\Delta t$ if the
  time-resolved trajectory matters.
- *Fast dynamic-recovery regime.* Accuracy degrades when $|\dot{\gamma}| \, k_{2,\text{dyn}}
  \, \Delta t \gtrsim 0.5$. An `IterationAdaptiveDT` schedule that grows $\Delta t$ from a
  small value during loading is recommended.

$\rho$ is a stateful material property; on `--recover` or `RecoverFileBase` restart the
stored value is loaded from the checkpoint and `initQpStatefulProperties` is bypassed, so
the trajectory continues without re-initializing.

## Coupling with [DeformedGrainMaterial.md]

The recommended wiring uses a `MaterialRealAux` to project `rho` onto an auxiliary variable
that is consumed by [DeformedGrainMaterial.md] through its
[!param](/Materials/DeformedGrainMaterial/rho_var) parameter. This producer-consumer pattern
keeps the field-valued $\rho$ as the single source of truth: the same $\rho$ feeds the
deformation energy and any nucleation probability material that reads `rho_grain`.

`KocksMeckingDislocation` reports $\rho$ in SI units ($\mathrm{m}^{-2}$).
[DeformedGrainMaterial.md] rescales internally by its own length scale, so the SI default is
the correct setting in the typical pipeline. The
[!param](/Materials/KocksMeckingDislocation/output_length_scale) parameter is provided only
for downstream consumers that do not rescale; leave it at $1.0$ when feeding
[DeformedGrainMaterial.md].

## Interaction with the discrete nucleation system

When `KocksMeckingDislocation` is paired with a rho-thresholded
[DiscreteNucleation.md] gate (`probability $\propto$ (rho > rho_crit) $\cdot$ (E_def >
E_crit)`), double counting between static recovery and nucleation insertion is avoided by two
mechanisms:

1. *Single $\rho$ field.* The same stateful property feeds both the deformation energy in
   [DeformedGrainMaterial.md] and the nucleation probability that reads `rho_grain`. There is
   no second $\rho$ source to disagree with.
2. *Grain-id gate.* When
   [!param](/Materials/KocksMeckingDislocation/gate_by_grain_id) is enabled (default `false`),
   the material queries the `GrainTrackerDislocations` UserObject and forces $\rho = 0$ in
   elements whose dominant grain has index $\geq$
   [!param](/Materials/KocksMeckingDislocation/deformed_grain_num). Already-recrystallized
   grains are therefore removed from the eligible nucleation set, matching the zeroing
   convention used in [DeformedGrainMaterial.md].

A nucleation cooldown on the nucleation probability material is recommended for runs in which
$\rho_\text{crit}$ is close to $\rho_\text{sat}$, but cooldown logic is outside the scope of
this material.

## Initial conditions

Three IC sources are supported, resolved in precedence order at every quadrature point:

1. *Constant.* [!param](/Materials/KocksMeckingDislocation/rho_init) supplies a single scalar
   $\rho_0$ applied uniformly to every element. This is the default.
2. *Coupled variable.* [!param](/Materials/KocksMeckingDislocation/rho_init_var) consumes a
   spatially varying auxiliary variable. Useful with `FunctionIC` or an EBSD-fed
   `AuxVariable`.
3. *Material property.* [!param](/Materials/KocksMeckingDislocation/rho_init_prop) accepts a
   `MaterialPropertyName` produced by another material. The typical use is an
   EBSD-derived per-element $\rho_0$ supplied by an `EBSDReaderMaterial` that has carried a
   `rho0` column through the Neper $\rightarrow$ `microstructure.txt` pipeline.

In every case the returned IC is clamped from below by
[!param](/Materials/KocksMeckingDislocation/rho_min).

## Example Input Syntax

A minimal use with scalar constant IC, internal coefficients, all three mechanisms active:

```
[Materials]
  [km]
    type = KocksMeckingDislocation
    gamma_dot = gdot
    T = T
    rho_init = 1.0e12
    mu = 42.0e9
    b = 2.56e-10
    L = 1.0e-6
    k20 = 1.0e1
    Q_dyn = 1.5
    n_exp = 5.0
    gdot_ref = 1.0
    ks0 = 1.0e4
    Q_climb = 1.5
    Q_units = eV
    tau0 = 0.0
    M = 3.06
    alpha = 0.3
  []
[]
```

A polycrystal use with EBSD-derived per-element IC, grain-id gating, and downstream
[DeformedGrainMaterial.md]:

```
[AuxVariables]
  [rho_grain]
    family = MONOMIAL
    order  = CONSTANT
  []
[]

[AuxKernels]
  [rho_grain_aux]
    type = MaterialRealAux
    property = rho
    variable = rho_grain
    execute_on = 'INITIAL TIMESTEP_BEGIN'
  []
[]

[Materials]
  [km]
    type = KocksMeckingDislocation
    gamma_dot = gdot
    T = T
    rho_init_prop = ebsd_rho
    gate_by_grain_id = true
    grain_tracker = grain_tracker
    deformed_grain_num = 8
    # ... mechanism parameters as above
  []
  [def_grain]
    type = DeformedGrainMaterial
    rho_var = rho_grain
    grain_tracker = grain_tracker
    deformed_grain_num = 8
    GBenergy = 0.708
    GBMobility = 3.986e-6
    Op_num = 8
    deformed_grain_num = 8
    length_scale = 1.0e-9
    time_scale = 1.0
  []
[]
```

The full producer-consumer wiring, including bicrystal verification of the end-to-end
$\rho \rightarrow E_\text{def}$ path, is exercised by the dedicated
`km_with_deformed_grain_material.i` test case under
`modules/phase_field/test/tests/km_dislocation/`.

!syntax parameters /Materials/KocksMeckingDislocation

!syntax inputs /Materials/KocksMeckingDislocation

!syntax children /Materials/KocksMeckingDislocation

!bibtex bibliography
