import pandas as pd

def procesar_panel():
    archivo_entrada = "csv/panel_final.csv" 
    archivo_salida = "csv/panel_final_limpio.csv"

    
    try:
        #csv
        df = pd.read_csv(archivo_entrada)
    except FileNotFoundError:
        print(f"no se encontro '{archivo_entrada}' cargar csv del github o no esta en la carpeta padre")
        return

    #fecha
    df['fecha'] = pd.to_datetime(df['fecha'])
    
    #estrato
    media_luz = df.groupby("municipio")["luces_nocturnas"].transform("mean")
    df["categoria"] = pd.qcut(
        media_luz, 3, labels=["Estrato Bajo", "Estrato Medio", "Estrato Alto"]
    )

    #ordenar
    df = df.sort_values(by=['municipio', 'fecha']).reset_index(drop=True)
    
    #exportar
    df.to_csv(archivo_salida, index=False)
    print(f"dimensinoes: {df.shape[0]} filas y {df.shape[1]} columnas")

if __name__ == "__main__":
    procesar_panel()
