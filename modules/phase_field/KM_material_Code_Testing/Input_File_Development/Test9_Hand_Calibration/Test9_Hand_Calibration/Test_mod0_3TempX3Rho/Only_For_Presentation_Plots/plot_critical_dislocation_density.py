from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import LogFormatterSciNotation, LogLocator


# -----------------------------------------------------------------------------
# Physical parameters
# -----------------------------------------------------------------------------
# These values reproduce approximately:
#   r = 40 nm -> Delta rho_crit = 8.7e15 m^-2
#   r = 80 nm -> Delta rho_crit = 4.4e15 m^-2
GAMMA_GB = 0.5          # Grain-boundary energy, J/m^2
SHEAR_MODULUS = 32.7e9  # Shear modulus, Pa
BURGERS_VECTOR = 2.96e-10  # Burgers-vector magnitude, m

# For the current 2D circular-nucleus balance, the capillary penalty is gamma/r.
# Set CURVATURE_FACTOR = 2.0 for a 3D spherical capillary pressure of 2*gamma/r.
CURVATURE_FACTOR = 1.0

REFERENCE_RHO = 1.0e16  # Reference dislocation-density contrast, m^-2
RADIUS_MIN_NM = 10.0
RADIUS_MAX_NM = 320.0


def critical_delta_rho(radius_nm: np.ndarray | float) -> np.ndarray:
    """Return the critical dislocation-density contrast in m^-2.

    The criterion is

        0.5 * mu * b^2 * Delta_rho_crit = CURVATURE_FACTOR * gamma / r

    so

        Delta_rho_crit = 2 * CURVATURE_FACTOR * gamma / (mu * b^2 * r).
    """
    radius_m = np.asarray(radius_nm, dtype=float) * 1.0e-9

    if np.any(radius_m <= 0.0):
        raise ValueError("Nucleus radius must be greater than zero.")

    return (
        2.0
        * CURVATURE_FACTOR
        * GAMMA_GB
        / (SHEAR_MODULUS * BURGERS_VECTOR**2 * radius_m)
    )


def main() -> None:
    radius_nm = np.linspace(RADIUS_MIN_NM, RADIUS_MAX_NM, 800)
    delta_rho_crit = critical_delta_rho(radius_nm)

    selected_radii_nm = np.array([40.0, 80.0])
    selected_delta_rho = critical_delta_rho(selected_radii_nm)

    # Fixed limits make the shaded regions stable and presentation-ready.
    y_min = 8.0e14
    y_max = 6.0e16

    plt.rcParams.update(
        {
            "font.size": 13,
            "axes.titlesize": 17,
            "axes.labelsize": 15,
            "legend.fontsize": 11,
            "xtick.labelsize": 12,
            "ytick.labelsize": 12,
        }
    )

    fig, ax = plt.subplots(figsize=(10.0, 6.0), constrained_layout=True)

    # Shade the two physical regimes.
    ax.fill_between(
        radius_nm,
        delta_rho_crit,
        y_max,
        alpha=0.14,
        zorder=0,
    )
    ax.fill_between(
        radius_nm,
        y_min,
        delta_rho_crit,
        alpha=0.14,
        zorder=0,
    )

    # Critical curve.
    ax.plot(
        radius_nm,
        delta_rho_crit,
        linewidth=2.8,
        label=r"Critical condition, $\Delta\rho_{\mathrm{crit}}$",
        zorder=3,
    )

    # Reference density.
    ax.axhline(
        REFERENCE_RHO,
        linestyle="--",
        linewidth=2.0,
        label=r"Reference: $10^{16}\ \mathrm{m}^{-2}$",
        zorder=2,
    )

    # Selected nucleus radii.
    ax.scatter(
        selected_radii_nm,
        selected_delta_rho,
        s=90,
        zorder=5,
        label="Selected nucleus radii",
    )

    # Point annotations.
    annotation_text = [
        (
            r"$r=40\ \mathrm{nm}$"
            "\n"
            r"$\Delta\rho_{\mathrm{crit}}\approx8.7\times10^{15}\ \mathrm{m}^{-2}$"
        ),
        (
            r"$r=80\ \mathrm{nm}$"
            "\n"
            r"$\Delta\rho_{\mathrm{crit}}\approx4.4\times10^{15}\ \mathrm{m}^{-2}$"
        ),
    ]

    annotation_positions = [
        (58.0, 2.25e16),
        (108.0, 5.8e15),
    ]

    for x, y, text, text_position in zip(
        selected_radii_nm,
        selected_delta_rho,
        annotation_text,
        annotation_positions,
    ):
        ax.annotate(
            text,
            xy=(x, y),
            xytext=text_position,
            textcoords="data",
            arrowprops={"arrowstyle": "->", "linewidth": 1.2},
            bbox={"boxstyle": "round,pad=0.35", "alpha": 0.82},
            ha="left",
            va="center",
            zorder=6,
        )

    # Region labels.
    ax.text(
        220.0,
        2.0e16,
        "Stored-energy-favorable",
        ha="center",
        va="center",
        fontweight="bold",
    )
    ax.text(
        220.0,
        1.15e15,
        "Curvature-dominated",
        ha="center",
        va="center",
        fontweight="bold",
    )

    # Axes and formatting.
    ax.set_yscale("log")
    ax.set_xlim(RADIUS_MIN_NM, RADIUS_MAX_NM)
    ax.set_ylim(y_min, y_max)
    ax.set_xticks([10, 20, 40, 80, 120, 160, 240, 320])
    ax.set_xlabel("Nucleus radius, $r$ (nm)")
    ax.set_ylabel(
        r"Critical dislocation-density contrast, "
        r"$\Delta\rho_{\mathrm{crit}}$ (m$^{-2}$)"
    )
    ax.set_title("Critical Dislocation-Density Contrast for Nucleus Growth")

    ax.yaxis.set_major_locator(LogLocator(base=10.0))
    ax.yaxis.set_major_formatter(LogFormatterSciNotation(base=10.0))
    ax.grid(True, which="both", linewidth=0.7, alpha=0.35)
    ax.legend(loc="upper right", frameon=True)

    output_dir = Path.cwd()
    png_path = output_dir / "critical_dislocation_density_vs_radius.png"
    pdf_path = output_dir / "critical_dislocation_density_vs_radius.pdf"

    fig.savefig(png_path, dpi=300, bbox_inches="tight")
    fig.savefig(pdf_path, bbox_inches="tight")

    print("Selected critical values:")
    for radius, delta_rho in zip(selected_radii_nm, selected_delta_rho):
        print(f"  r = {radius:5.1f} nm -> Delta rho_crit = {delta_rho:.4e} m^-2")

    print(f"\nSaved PNG: {png_path}")
    print(f"Saved PDF: {pdf_path}")

    plt.show()


if __name__ == "__main__":
    main()
