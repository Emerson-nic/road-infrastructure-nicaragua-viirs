'''
Created on Sun 05 12:33:18 2026

Aqui se obtiene los coeficientes poisson de cada municipio 

@author: emer
'''

''' Esto hay que ingresarlo a la terminal si no se tiene los paquetes
pip install pandas statsmodels scipy 
'''

# %% cargar librerias
import numpy as np
import pandas as pd
import statsmodels.api as sm
import statsmodels.formula.api as smf
from scipy.stats import norm


# %% variables
df = pd.read_csv("csv/panel_final.csv")

df['log_imae'] = np.log(df['imae'])
df['interaccion_log'] = df['densid_vial'].apply(lambda x: np.log(x) if x > 0 else 0) * df['log_imae']
df['interaccion_area'] = np.log(df['area_km2']) * df['log_imae']

# %% modelo
#modelo lineal mixto generalizado (GLIMMIX) Poisson
modelo_poi = smf.mixedlm(
    "luces_nocturnas ~ interaccion_log + interaccion_area", 
    data=df, 
    groups=df["municipio"], 
    re_formula="~interaccion_log + interaccion_area"
)

resultado_poi = modelo_poi.fit(method=["lbfgs"])

# %% blips
#efectos fijos globales promedio
fe_vial = resultado_poi.fe_params["interaccion_log"]
fe_area = resultado_poi.fe_params["interaccion_area"]

#efectos aleatorios por municipio (las desviaciones de cada uno)
re_municipios = resultado_poi.random_effects

lineas_csv = []
for municipio, de_df in re_municipios.items():
    #coeficiente total = efecto fijo global + desviacion aleatoria municipal blup
    coef_vial_mun = fe_vial + de_df["interaccion_log"]
    coef_area_mun = fe_area + de_df["interaccion_area"]
    
    cov_condicional = resultado_poi.random_effects_cov[municipio]
    se_vial_mun = np.sqrt(cov_condicional.loc["interaccion_log", "interaccion_log"])
    se_area_mun = np.sqrt(cov_condicional.loc["interaccion_area", "interaccion_area"])

    #wald 
    z_vial_consolidado = coef_vial_mun / se_vial_mun
    z_area_consolidado = coef_area_mun / se_area_mun
    
    p_vial_real = 2 * (1 - norm.cdf(abs(z_vial_consolidado)))
    p_area_real = 2 * (1 - norm.cdf(abs(z_area_consolidado)))

    #intervalo de confianza al 95%
    ci_vial_inf = coef_vial_mun - (1.96 * se_vial_mun)
    ci_vial_sup = coef_vial_mun + (1.96 * se_vial_mun)
    
    ci_area_inf = coef_area_mun - (1.96 * se_area_mun)
    ci_area_sup = coef_area_mun + (1.96 * se_area_mun)
    
    lineas_csv.append({
        "municipio": municipio,
        "coef_vial": coef_vial_mun,
        "se_vial": se_vial_mun,
        "p_vial": p_vial_real,
        "ci_vial_inf": ci_vial_inf,
        "ci_vial_sup": ci_vial_sup,
        "coef_area": coef_area_mun,
        "se_area": se_area_mun,
        "p_area": p_area_real,
        "ci_area_inf": ci_area_inf,
        "ci_area_sup": ci_area_sup
    })

df_exportar = pd.DataFrame(lineas_csv)
df_exportar.to_csv("csv/blups_poisson_municipales.csv", index=False)

# %% buscar quienes son los significativos
print("densidad vial(p < 0.05)")
#filtro
df_vial_sig = df_exportar[df_exportar['p_vial'] < 0.05].copy()
#orden de menor a mayor
df_vial_sig = df_vial_sig.sort_values(by='coef_vial', ascending=True)

print(f"{'Municipio':<32} | {'Beta (Coef)':<12} | {'Std. Error':<12} | {'p-value':<9} | {'[IC 95% Puros]':<20}")
for _, row in df_vial_sig.iterrows():
    intervalo = f"[{row['ci_vial_inf']:>.4f}, {row['ci_vial_sup']:>.4f}]"
    print(f"{row['municipio']:<32} | {row['coef_vial']:>11.4f} | {row['se_vial']:>11.4f} | {row['p_vial']:>8.4f} | {intervalo:<20}")


print("Area municipal (p < 0.05)")

df_area_sig = df_exportar[df_exportar['p_area'] < 0.05].copy()

df_area_sig = df_area_sig.sort_values(by='coef_area', ascending=False)

print(f"{'Municipio':<32} | {'Beta (Coef)':<12} | {'Std. Error':<12} | {'p-value':<9} | {'[IC 95% Puros]':<20}")
for _, row in df_area_sig.iterrows():
    intervalo = f"[{row['ci_area_inf']:>.4f}, {row['ci_area_sup']:>.4f}]"
    print(f"{row['municipio']:<32} | {row['coef_area']:>11.4f} | {row['se_area']:>11.4f} | {row['p_area']:>8.4f} | {intervalo:<20}")

# %% csv 
reporte_vial = pd.DataFrame({
    "Variable": "Densidad_Vial",
    "Municipio": df_vial_sig['municipio'],
    "Beta(Coef)": df_vial_sig['coef_vial'],
    "Std_Error": df_vial_sig['se_vial'],
    "p-value": df_vial_sig['p_vial'],
    "IC_95%": df_vial_sig.apply(lambda r: f"[{r['ci_vial_inf']:.4f}, {r['ci_vial_sup']:.4f}]", axis=1)
})

reporte_area = pd.DataFrame({
    "Variable": "Area)",
    "Municipio": df_area_sig['municipio'],
    "Beta(Coef)": df_area_sig['coef_area'],
    "Std_Error": df_area_sig['se_area'],
    "p-value": df_area_sig['p_area'],
    "IC_95%": df_area_sig.apply(lambda r: f"[{r['ci_area_inf']:.4f}, {r['ci_area_sup']:.4f}]", axis=1)
})

#concatenar unir
reporte_final_csv = pd.concat([reporte_vial, reporte_area], ignore_index=True)
betas_municipios = pd.DataFrame(reporte_final_csv)
betas_municipios.to_csv("csv/betas_municipales.csv", index=True)


#%% agrgar el imae desagragado
df['log_imae_pri'] = np.log(df['imae_primario'])
df['log_imae_sec'] = np.log(df['imae_secundario'])
df['log_imae_ter'] = np.log(df['imae_terciario'])

df['interaccion_log_pri'] = df['densid_vial'].apply(lambda x: np.log(x) if x > 0 else 0) * df['log_imae_pri']
df['interaccion_log_sec'] = df['densid_vial'].apply(lambda x: np.log(x) if x > 0 else 0) * df['log_imae_sec']
df['interaccion_log_ter'] = df['densid_vial'].apply(lambda x: np.log(x) if x > 0 else 0) * df['log_imae_ter']

df['interaccion_area_pri'] = np.log(df['area_km2']) * df['log_imae_pri']
df['interaccion_area_sec'] = np.log(df['area_km2']) * df['log_imae_sec']
df['interaccion_area_ter'] = np.log(df['area_km2']) * df['log_imae_ter']

sectores = {
    "Primario": ("interaccion_log_pri", "interaccion_area_pri"),
    "Secundario": ("interaccion_log_sec", "interaccion_area_sec"),
    "Terciario": ("interaccion_log_ter", "interaccion_area_ter")
}

lineas_reporte = []

# %% estimacion imae degragrado
for sector, (var_vial, var_area) in sectores.items():
    print(f"Estimando modelo Poisson GLMM para Sector: {sector}...")
    
    modelo = smf.mixedlm(
        f"luces_nocturnas ~ {var_vial} + {var_area}", 
        data=df, groups=df["municipio"], re_formula=f"~{var_vial} + {var_area}"
    )
    resultado = modelo.fit(method=["lbfgs"])
    
    fe_vial = resultado.fe_params[var_vial]
    fe_area = resultado.fe_params[var_area]
    re_municipios = resultado.random_effects
    
    for municipio, de_df in re_municipios.items():
        coef_vial = fe_vial + de_df[var_vial]
        coef_area = fe_area + de_df[var_area]
        
        cov_c = resultado.random_effects_cov[municipio]
        se_vial = np.sqrt(cov_c.loc[var_vial, var_vial])
        se_area = np.sqrt(cov_c.loc[var_area, var_area])
        
        #wald
        z_vial_consolidado = coef_vial / se_vial
        z_area_consolidado = coef_area / se_area
        p_vial = 2 * (1 - norm.cdf(abs(z_vial_consolidado)))
        p_area = 2 * (1 - norm.cdf(abs(z_area_consolidado)))
        
        #intervalos de confianza al 95%
        ci_vial_inf = coef_vial - (1.96 * se_vial)
        ci_vial_sup = coef_vial + (1.96 * se_vial)
        ci_area_inf = coef_area - (1.96 * se_area)
        ci_area_sup = coef_area + (1.96 * se_area)
        
        lineas_reporte.append({
            "municipio": municipio,
            "sector": sector,
            "coef_vial": coef_vial,
            "se_vial": se_vial,
            "p_vial": p_vial,
            "ci_vial_inf": ci_vial_inf,
            "ci_vial_sup": ci_vial_sup,
            "coef_area": coef_area,
            "se_area": se_area,
            "p_area": p_area,
            "ci_area_inf": ci_area_inf,
            "ci_area_sup": ci_area_sup
        })

df_exportar = pd.DataFrame(lineas_reporte)

# %% guardar
df_exportar.to_csv("csv/blups_poisson_sectores.csv", index=False)

lista_reportes_vial = []
lista_reportes_area = []

# %% filtro
for sector in ["Primario", "Secundario", "Terciario"]:
    df_sector_actual = df_exportar[df_exportar['sector'] == sector]

    print(f"\ndensidad vial (p < 0.05) - sector{sector.upper()} ")
    df_vial_sig = df_sector_actual[df_sector_actual['p_vial'] < 0.05].copy()
    df_vial_sig = df_vial_sig.sort_values(by='coef_vial', ascending=True)
    
    print(f"{'Municipio':<32} | {'Beta (Coef)':<12} | {'Std. Error':<12} | {'p-value':<9} | {'[IC 95% Puros]':<20}")
    print("-"*105)
    for _, row in df_vial_sig.iterrows():
        intervalo = f"[{row['ci_vial_inf']:.4f}, {row['ci_vial_sup']:.4f}]"
        print(f"{row['municipio']:<32} | {row['coef_vial']:>11.4f} | {row['se_vial']:>11.4f} | {row['p_vial']:>8.4f} | {intervalo:<20}")
    
    if not df_vial_sig.empty:
        reporte_vial_sec = pd.DataFrame({
            "Sector": sector,
            "Variable": "Densidad_Vial",
            "Municipio": df_vial_sig['municipio'],
            "Beta(Coef)": df_vial_sig['coef_vial'],
            "Std_Error": df_vial_sig['se_vial'],
            "p-value": df_vial_sig['p_vial'],
            "IC_95%": df_vial_sig.apply(lambda r: f"[{r['ci_vial_inf']:.4f}, {r['ci_vial_sup']:.4f}]", axis=1)
        })
        lista_reportes_vial.append(reporte_vial_sec)

    print(f"\narea municipal (p < 0.05) - sector {sector.upper()}")
    df_area_sig = df_sector_actual[df_sector_actual['p_area'] < 0.05].copy()
    df_area_sig = df_area_sig.sort_values(by='coef_area', ascending=False)
    
    print(f"{'Municipio':<32} | {'Beta (Coef)':<12} | {'Std. Error':<12} | {'p-value':<9} | {'[IC 95% Puros]':<20}")
    print("-"*105)
    for _, row in df_area_sig.iterrows():
        intervalo = f"[{row['ci_area_inf']:.4f}, {row['ci_area_sup']:.4f}]"
        print(f"{row['municipio']:<32} | {row['coef_area']:>11.4f} | {row['se_area']:>11.4f} | {row['p_area']:>8.4f} | {intervalo:<20}")
        
    if not df_area_sig.empty:
        reporte_area_sec = pd.DataFrame({
            "Sector": sector,
            "Variable": "Area",
            "Municipio": df_area_sig['municipio'],
            "Beta(Coef)": df_area_sig['coef_area'],
            "Std_Error": df_area_sig['se_area'],
            "p-value": df_area_sig['p_area'],
            "IC_95%": df_area_sig.apply(lambda r: f"[{r['ci_area_inf']:.4f}, {r['ci_area_sup']:.4f}]", axis=1)
        })
        lista_reportes_area.append(reporte_area_sec)

reporte_total_vial = pd.concat(lista_reportes_vial, ignore_index=True) if lista_reportes_vial else pd.DataFrame()
reporte_total_area = pd.concat(lista_reportes_area, ignore_index=True) if lista_reportes_area else pd.DataFrame()

reporte_final_csv = pd.concat([reporte_total_vial, reporte_total_area], ignore_index=True)
betas_municipios = pd.DataFrame(reporte_final_csv)

betas_municipios.to_csv("csv/betas_municipales.csv", index=True)
