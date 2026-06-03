# DeformedGrainMaterial / ADDeformedGrainMaterial

!syntax description /Materials/DeformedGrainMaterial

## Description

`DeformedGrainMaterial` extends [GBEvolution.md] to incorporate dislocation-density-based
stored (deformation) energy into polycrystal grain growth simulations. It assigns a
dislocation density to each grain identified by the grain tracker and
computes the spatially varying deformation energy that drives preferential consumption of
deformed grains by recrystallised ones.

!alert note
The [!param](/Materials/DeformedGrainMaterial/grain_tracker) parameter must reference a
`GrainTrackerDislocations` UserObject, not a plain `GrainTracker`. `GrainTrackerDislocations`
extends `GrainTracker` with the per-grain dislocation data interface required by this material.

### Dislocation density assignment

The object supports three levels of dislocation density specification, evaluated in
priority order at every quadrature point:

1. **Per-element field** ([!param](/Materials/DeformedGrainMaterial/rho_var)): a coupled
   auxiliary variable that provides a spatially varying $\rho$ directly. Takes precedence
   over all other sources when coupled.
2. **Per-grain vector** ([!param](/Materials/DeformedGrainMaterial/dislocation_density_per_grain)):
   a vector indexed by grain ID. The dislocation density of the grain occupying the current
   element is looked up from this vector. Falls back to the uniform constant for grain IDs
   that are out of range.
3. **Uniform constant** ([!param](/Materials/DeformedGrainMaterial/dislocation_density_constant)):
   a single value applied to all deformed grains. This is the default when neither of the
   above sources is provided.

Grains with index $\geq$ [!param](/Materials/DeformedGrainMaterial/deformed_grain_num) are
treated as undeformed and assigned $\rho_i = 0$.

### Effective dislocation density

The effective dislocation density at a quadrature point is the order-parameter-squared
weighted average over all active grains:

\begin{equation}
\rho_\text{eff} = \frac{\displaystyle\sum_i \rho_i \, \eta_i^2}{\displaystyle\sum_i \eta_i^2}
\label{eq:rho-eff}
\end{equation}

where $\eta_i$ are the grain order parameters and $\rho_i$ is zero for undeformed grains.

!alert note
When the sum $\sum_i \eta_i^2$ is zero at a quadrature point (for example inside a void
region where all order parameters vanish), `rho_eff` is set to zero to avoid a
division-by-zero.

### Deformation energy

The stored energy density associated with the dislocation network is

\begin{equation}
E_\text{def} = \beta \, \rho_\text{eff}
\label{eq:e-def}
\end{equation}

where the prefactor $\beta$ combines the shear modulus $G$ and the Burgers vector
magnitude $b$:

\begin{equation}
\beta = \frac{1}{2} G \, b^2 \, C_\text{JtoeV} \, \ell
\label{eq:beta}
\end{equation}

$C_\text{JtoeV}$ is the Joule-to-eV conversion factor and $\ell$ is the length scale
inherited from [GBEvolution.md].

### Material properties produced

| Property | Description |
| :- | :- |
| `beta` | Prefactor $\beta$ |
| `disloc_den_i` | Dislocation density of the active grain in scaled units ($\mathrm{m}^{-2} \times \ell^2$) |
| `rho_eff` | Effective dislocation density weighted by $\eta_i^2$ |
| `deformation_energy` | Deformation energy density $E_\text{def}$ |
| `grain_disloc_data` | Per-grain dislocation density vector indexed by grain ID |

These properties are consumed by [PolycrystalStoredEnergy](PolycrystalStoredEnergy.md)
kernels that add the stored-energy driving force to the Allen-Cahn equations.

!alert note
`ADDeformedGrainMaterial` is the automatic-differentiation variant and should be used
with AD kernels to obtain exact Jacobians without hand-coded derivatives.

## Example Input Syntax

!alert note
The test input below uses `type = GrainTracker` in the `[UserObjects]` block. In practice,
this must be replaced with `type = GrainTrackerDislocations` so that the per-grain
dislocation data interface is available to `DeformedGrainMaterial`.

!listing modules/phase_field/test/tests//.i block=Materials

!syntax parameters /Materials/DeformedGrainMaterial

!syntax inputs /Materials/DeformedGrainMaterial

!syntax children /Materials/DeformedGrainMaterial
