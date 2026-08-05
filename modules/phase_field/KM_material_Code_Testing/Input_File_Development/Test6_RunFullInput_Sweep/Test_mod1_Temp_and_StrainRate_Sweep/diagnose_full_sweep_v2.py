#!/usr/bin/env python3
from pathlib import Path
import re
import argparse
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def parse_number(text):
    text = str(text).replace('p', '.').replace(',', '.')
    match = re.search(r'[-+]?\d*\.?\d+(?:e[-+]?\d+)?', text)
    return np.nan if match is None else float(match.group(0))


def find_col(df, names):
    clean = {re.sub(r'[^a-zA-Z0-9]', '', c.lower()): c for c in df.columns}
    for name in names:
        key = re.sub(r'[^a-zA-Z0-9]', '', name.lower())
        if key in clean:
            return clean[key]
    return None


def read_case_settings(case_dir):
    out = {}
    path = case_dir / 'case_settings.txt'
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            out[k.strip()] = v.strip()
    return out


def metadata_from_path(path):
    T = rate = rho = np.nan
    for part in path.parts:
        low = part.lower()
        if low.startswith('t_'):
            T = parse_number(part)
        elif low.startswith('gdot_'):
            rate = parse_number(part)
        elif low.startswith('rho_'):
            rho = parse_number(part)
    return T, rate, rho


def eq_diameter(area):
    return 2.0 * np.sqrt(area / np.pi)


def load_data(root):
    files = sorted(root.rglob('result.csv'))
    if not files:
        files = sorted(root.rglob('*.csv'))
    rows = []
    skipped = []
    for csv_path in files:
        if any(part in ('logs', 'comparison_plots', 'diagnostic_plots', 'diagnostic_plots_v2') for part in csv_path.parts):
            continue
        try:
            df = pd.read_csv(csv_path)
        except Exception as exc:
            skipped.append(f'{csv_path}: read error {exc}')
            continue
        time_col = find_col(df, ['time'])
        if time_col is None:
            skipped.append(f'{csv_path}: no time column')
            continue
        settings = read_case_settings(csv_path.parent)
        T_path, rate_path, rho_path = metadata_from_path(csv_path)
        T = float(settings.get('T_i', T_path))
        rate = float(settings.get('strain_rate_i', rate_path))
        rho_init = float(settings.get('rho_init_i', rho_path)) if not pd.isna(settings.get('rho_init_i', rho_path)) else np.nan
        out = pd.DataFrame()
        out['time'] = pd.to_numeric(df[time_col], errors='coerce')
        out['T'] = T
        out['strain_rate'] = rate
        out['rho_init'] = rho_init
        out['accumulated_strain'] = out['time'] * out['strain_rate']
        out['source_file'] = str(csv_path)
        wanted = {
            'rho_avg': ['rho_avg'],
            'rho_eff_avg': ['rho_eff_avg'],
            'Def_Eng': ['Def_Eng'],
            'beta_avg': ['beta_avg'],
            'P_nuc_avg': ['P_nuc_avg'],
            'nuc_drive_ratio_avg': ['nuc_drive_ratio_avg'],
            'nuc_count': ['nuc_count'],
            'nuc_insertions': ['nuc_insertions'],
            'nuc_deletions': ['nuc_deletions'],
            'avg_grain_area': ['avg_grain_area', 'average_grain_volume'],
            'gb_length': ['gb_length', 'grain_boundary_area'],
            'grain_count': ['grain_count', 'num_grains'],
            'dt_actual': ['dt_actual'],
            'T_avg': ['T_avg'],
            'gdot_avg': ['gdot_avg'],
        }
        for out_name, names in wanted.items():
            col = find_col(df, names)
            out[out_name] = pd.to_numeric(df[col], errors='coerce') if col is not None else np.nan
        if not out['avg_grain_area'].isna().all():
            out['D_avg'] = eq_diameter(out['avg_grain_area'])
        else:
            out['D_avg'] = np.nan
        rows.append(out)
    if not rows:
        raise RuntimeError('No usable result CSV files found under ' + str(root))
    data = pd.concat(rows, ignore_index=True)
    data = data.dropna(subset=['time', 'T', 'strain_rate']).sort_values(['T', 'strain_rate', 'time'])
    if not data['D_avg'].isna().all():
        data['D0'] = data.groupby(['T', 'strain_rate'])['D_avg'].transform(lambda s: s[s > 0].iloc[0] if (s > 0).any() else np.nan)
        data['D_norm'] = data['D_avg'] / data['D0']
    return data.reset_index(drop=True), skipped


def case_summary(data):
    rows = []
    for (T, rate), g in data.groupby(['T', 'strain_rate']):
        g = g.sort_values('time')
        total_insertions = int(np.nansum(g['nuc_insertions'])) if 'nuc_insertions' in g else 0
        total_deletions = int(np.nansum(g['nuc_deletions'])) if 'nuc_deletions' in g else 0
        D_final = g['D_avg'].iloc[-1] if 'D_avg' in g else np.nan
        D_norm_final = g['D_norm'].iloc[-1] if 'D_norm' in g else np.nan
        gb_final = g['gb_length'].iloc[-1] if 'gb_length' in g else np.nan
        if total_insertions == 0:
            if np.isfinite(D_norm_final) and D_norm_final > 1.5 and np.isfinite(gb_final) and gb_final < 10:
                cls = 'curvature_coarsening_no_nucleation'
            elif np.isfinite(D_norm_final) and 0.85 <= D_norm_final <= 1.15:
                cls = 'little_change_no_nucleation'
            elif np.isfinite(D_norm_final) and D_norm_final < 0.85:
                cls = 'grain_refinement_without_recorded_insertions'
            else:
                cls = 'growth_no_nucleation'
        else:
            if np.isfinite(D_norm_final) and D_norm_final < 0.85 and np.isfinite(gb_final) and gb_final > 3000:
                cls = 'many_small_grains_limited_growth'
            elif np.isfinite(D_norm_final) and D_norm_final > 1.5 and np.isfinite(gb_final) and gb_final < 10:
                cls = 'coarsened_after_nucleation'
            elif np.isfinite(D_norm_final) and 0.85 <= D_norm_final <= 1.15:
                cls = 'nucleation_but_no_net_size_change'
            else:
                cls = 'mixed_behavior'
        rows.append({
            'T': T,
            'strain_rate': rate,
            'final_time': g['time'].iloc[-1],
            'final_accumulated_strain': g['accumulated_strain'].iloc[-1],
            'total_nuc_count_sum': int(np.nansum(g['nuc_count'])),
            'total_insertions_sum': total_insertions,
            'total_deletions_sum': total_deletions,
            'max_nuc_count_per_step': np.nanmax(g['nuc_count']),
            'D0': g['D0'].iloc[0] if 'D0' in g else np.nan,
            'D_min': np.nanmin(g['D_avg']) if 'D_avg' in g else np.nan,
            'D_final': D_final,
            'D_norm_min': np.nanmin(g['D_norm']) if 'D_norm' in g else np.nan,
            'D_norm_final': D_norm_final,
            'gb_length_max': np.nanmax(g['gb_length']) if 'gb_length' in g else np.nan,
            'gb_length_final': gb_final,
            'rho_avg_final': g['rho_avg'].iloc[-1] if 'rho_avg' in g else np.nan,
            'Def_Eng_final': g['Def_Eng'].iloc[-1] if 'Def_Eng' in g else np.nan,
            'classification': cls,
            'source_file': g['source_file'].iloc[-1],
        })
    return pd.DataFrame(rows).sort_values(['T', 'strain_rate']).reset_index(drop=True)


def safe_tag(value):
    return f'{value:g}'.replace('.', 'p').replace('-', 'm')


def plot_lines(data, y, ylabel, out_dir):
    if y not in data.columns or data[y].isna().all():
        return
    p = out_dir / f'{y}_fixed_T'
    p.mkdir(exist_ok=True, parents=True)
    for T, gT in data.groupby('T'):
        fig, ax = plt.subplots(figsize=(7, 5), dpi=150)
        for rate, c in gT.groupby('strain_rate'):
            c = c.sort_values('accumulated_strain')
            ax.plot(c['accumulated_strain'], c[y], label=f'{rate:g} 1/s')
        ax.set_xlabel('accumulated strain')
        ax.set_ylabel(ylabel)
        ax.set_title(f'{ylabel}, T = {T:g} K')
        ax.legend(title='strain rate')
        fig.tight_layout()
        fig.savefig(p / f'T_{safe_tag(T)}_{y}.png')
        plt.close(fig)


def heatmap(summary, y, ylabel, out_dir, log=False):
    if y not in summary.columns:
        return
    clean = summary.copy()
    clean[y] = pd.to_numeric(clean[y], errors='coerce').replace([np.inf, -np.inf], np.nan)
    clean = clean.dropna(subset=[y, 'T', 'strain_rate'])
    if log:
        clean = clean[clean[y] > 0]
    if clean.empty:
        return
    values_col = y
    label = ylabel
    if log:
        values_col = 'log10_' + y
        clean[values_col] = np.log10(clean[y])
        label = 'log10(' + ylabel + ')'
    pivot = clean.pivot_table(index='T', columns='strain_rate', values=values_col, aggfunc='mean').sort_index().sort_index(axis=1)
    if pivot.empty or not np.isfinite(pivot.values).any():
        return
    p = out_dir / 'heatmaps'
    p.mkdir(exist_ok=True, parents=True)
    fig, ax = plt.subplots(figsize=(8, 5), dpi=150)
    im = ax.imshow(pivot.values, origin='lower', aspect='auto')
    fig.colorbar(im, ax=ax, label=label)
    ax.set_xticks(np.arange(len(pivot.columns)))
    ax.set_xticklabels([f'{x:g}' for x in pivot.columns], rotation=45, ha='right')
    ax.set_yticks(np.arange(len(pivot.index)))
    ax.set_yticklabels([f'{x:g}' for x in pivot.index])
    ax.set_xlabel('strain rate, 1/s')
    ax.set_ylabel('temperature, K')
    ax.set_title(label)
    raw = clean.pivot_table(index='T', columns='strain_rate', values=y, aggfunc='mean').sort_index().sort_index(axis=1)
    for i in range(raw.shape[0]):
        for j in range(raw.shape[1]):
            v = raw.values[i, j]
            if np.isfinite(v):
                ax.text(j, i, f'{v:.2g}', ha='center', va='center', fontsize=8)
    fig.tight_layout()
    suffix = '_log' if log else ''
    fig.savefig(p / f'final_{y}{suffix}.png')
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', type=Path, default=Path('FullSweep_rho1e16'))
    args = ap.parse_args()
    out_dir = args.root / 'diagnostic_plots_v2'
    out_dir.mkdir(exist_ok=True, parents=True)
    data, skipped = load_data(args.root)
    summary = case_summary(data)
    data.to_csv(out_dir / 'combined_diagnostic_data_v2.csv', index=False)
    summary.to_csv(out_dir / 'corrected_case_summary_v2.csv', index=False)
    if skipped:
        (out_dir / 'skipped_files.txt').write_text('\n'.join(skipped))
    for y, ylabel in {
        'D_norm': 'normalized average grain size, D/D0',
        'D_avg': 'average equivalent diameter',
        'gb_length': 'grain-boundary length',
        'rho_avg': 'rho_avg',
        'nuc_insertions': 'nucleation insertions per output',
        'nuc_deletions': 'nucleation deletions per output',
        'P_nuc_avg': 'P_nuc_avg',
        'nuc_drive_ratio_avg': 'nuc_drive_ratio_avg',
    }.items():
        plot_lines(data, y, ylabel, out_dir)
    for y, ylabel, log in [
        ('D_norm_final', 'final D/D0', False),
        ('total_insertions_sum', 'summed nucleation insertions', False),
        ('gb_length_final', 'final grain-boundary length', True),
        ('rho_avg_final', 'final rho_avg', True),
        ('Def_Eng_final', 'final Def_Eng', True),
    ]:
        heatmap(summary, y, ylabel, out_dir, log=log)
    print('Wrote:', out_dir)
    print('Summary:', out_dir / 'corrected_case_summary_v2.csv')

if __name__ == '__main__':
    main()
