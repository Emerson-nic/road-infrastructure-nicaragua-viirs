#cargar librerias ---- 
options(repos = c(CRAN = "https://cloud.r-project.org"))
if (!require("pacman")) install.packages("pacman")

pacman::p_load(fixest,
               tidyr,
               dplyr,
               lmtest,
               usethis,
               ggplot2
               )

# importar datos si no existen en el entorno ----
if (!exists("panel_final")) {
  if (file.exists("csv/panel_final.csv")) {
    panel_final <- readr::read_csv("csv/panel_final.csv") %>%
      dplyr::mutate(fecha = as.Date(fecha))
  } else {
    source("Scripts/obtener_datos.R")
  }
}

panel_final <- panel_final %>%
  dplyr::mutate(
    log_area = log(area_km2),
    log_luces = log(luces_nocturnas), 
    log_imae  = log(imae),
    interaccion_log = densid_vial * log_imae,
    interaccion_area = log_area * log_imae
  ) 

#modelo que elimina 19 obs
modelo_twfe_log <- fixest::feols(
  log_luces ~ interaccion_log + interaccion_area | municipio + fecha,
  data = panel_final,
  cluster = ~municipio
)

summary(modelo_twfe_log)

#modelo en niveles
modelo_twfe_poisson <- fixest::fepois(
  luces_nocturnas ~ interaccion_log + interaccion_area | municipio + fecha,
  data = panel_final,
  cluster = ~municipio
)

summary(modelo_twfe_poisson)

#modelo sin cluster
modelo_twfe_base <- fixest::feols(
  log_luces ~ interaccion_log + interaccion_area | municipio + fecha,
  data = panel_final
)

#tablas comparativas para demostrar robustez
fixest::etable(
  modelo_twfe_base, 
  vcov = list(
    "iid", #errores clasicos 
    "hetero", #errores Robustos simples (solo corrige heterocedasticidad tipo White)
    ~municipio #errores clustered (corrige heterocedasticidad y autocorrelacion serial)
  ),
  headers = c("clasicos", "robustos (White)", "clustered (Arellano)")
)

#graficos de residuos vs valores ajustados
residuos_df <- data.frame(
  Ajustados = fitted(modelo_twfe_log),
  Residuos = residuals(modelo_twfe_log)
)

ggplot(residuos_df, aes(x = Ajustados, y = Residuos)) +
  geom_point(alpha = 0.2, color = "#2563EB") +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed", size = 1) +
  labs(
    title = "Distribución de Residuos del Modelo TWFE",
    subtitle = "Ausencia de patrones no lineales severos tras controlar por Efectos Fijos",
    x = "Valores Ajustados (Log Luces)",
    y = "Residuos del Modelo"
  ) +
  theme_bw()

#otro modelo para outliers mediante residuos studentizados

#corregir el desajuste de tamaños
panel_model <- panel_final %>%
  dplyr::filter(
    is.finite(log_luces),
    is.finite(interaccion_log),
    is.finite(interaccion_area)
  )

#observaciones talvez atipicas

#obtener residuos estandarizados
modelo_ols_dummies_full <- lm(
  log_luces ~ interaccion_log + interaccion_area +
    as.factor(municipio) + as.factor(fecha),
  data = panel_model
)

panel_model$rstudent <- rstudent(modelo_ols_dummies_full)

#identificar outliers
outliers <- panel_model %>% dplyr::filter(abs(rstudent) > 3)

print(outliers %>% dplyr::count(municipio, sort = TRUE))

panel_clean <- panel_model %>% dplyr::filter(abs(rstudent) <= 3)
#modelo
modelo_clean <- fixest::feols(
  log_luces ~ interaccion_log + interaccion_area | municipio + fecha,
  data = panel_clean,
  cluster = ~municipio
)
summary(modelo_clean)

#tabla de comparacion

fixest::etable(
  modelo_twfe_base, #log-lineal 
  modelo_twfe_log, #log-lineal (con cluster)
  modelo_twfe_poisson, #poisson (PPML)
  modelo_clean, #log-lineal (sin outliers)
  headers = c("OLS", "TWFE Principal", "Poisson (PPML)", "TWFE (Sin Outliers)")
)
# el mae afecta a las luces de nicaragua? ----

#filtro para los inf
panel_validacion <- panel_final %>%
  dplyr::filter(is.finite(log_luces), is.finite(log_imae))

#modelo de elasticidad
modelo_validacion_proxy <- fixest::feols(
  log_luces ~ log_imae | municipio,
  data = panel_validacion,
  cluster = ~municipio
)

summary(modelo_validacion_proxy)

#crear tendencia para ver si hay regresión espuria
panel_validacion <- panel_final %>%
  dplyr::filter(is.finite(log_luces), is.finite(log_imae)) %>%
  dplyr::mutate(
    tendencia_lineal = as.numeric(fecha) - min(as.numeric(fecha)),
    mes_del_anio = as.factor(lubridate::month(fecha))
  )

#modelo aislando la tendencia a largo plazo y estacionalidad de las luces
modelo_validacion_estricto <- fixest::feols(
  log_luces ~ log_imae + tendencia_lineal | municipio + mes_del_anio,
  data = panel_validacion,
  cluster = ~municipio 
)

summary(modelo_validacion_estricto)


#tablas comparativas
fixest::etable(
  modelo_validacion_proxy,
  modelo_validacion_estricto,
  headers = c("validacion basica", "validacion con tendencia de meses")
  #drop = "tendencia_lineal" #ocultar la tendencia para enfocarse en el imae
)
