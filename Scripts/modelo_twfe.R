if(F){
  "
  
  pregunta de invetigacion: como condiciona la dotación de infraestructura vial 
  la transmision de los shocks macroeconomicos a las economias locales 
  en Nicaragua, utilizando las luces nocturnas como proxy de actividad?
  
  hipotesis: Los municipios con mayor densidad vial presentan una mayor 
  elasticidad de sus luces nocturnas respecto al IMAE, es decir, reaccionan más
  intensamente a los ciclos macro
  
  "
}


#cargar librerias ---- 
options(repos = c(CRAN = "https://cloud.r-project.org"))
if (!require("pacman")) install.packages("pacman")

pacman::p_load(fixest,
               tidyr,
               dplyr,
               lmtest,
               usethis,
               ggplot2,
               lme4,
               sf,
               viridis,
               readxl,
               stringr
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

dist_residuo_grafico <- ggplot(residuos_df, aes(x = Ajustados, y = Residuos)) +
  geom_point(alpha = 0.2, color = "#2563EB") +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed", size = 1) +
  labs(
    title = "Distribución de Residuos del Modelo TWFE",
    subtitle = "Ausencia de patrones no lineales severos tras controlar por Efectos Fijos",
    x = "Valores Ajustados (Log Luces)",
    y = "Residuos del Modelo"
  ) 

print(dist_residuo_grafico)
ggsave("Graficos/distribucion_residuos_twfe.pdf", plot = dist_residuo_grafico, width = 9, height = 4, dpi = 300)

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


#placebo permutacion de densid_vial entre municipios ----

#si el resultado es genuino entonces el coeficiente real debe estar
#en los extremos de la distribucion placebo
set.seed(42)
n_perm <- 200

panel_placebo <- panel_final %>%
  dplyr::mutate(log_imae = log(imae)) %>%
  dplyr::filter(is.finite(log_luces), is.finite(interaccion_log),
                is.finite(interaccion_area))

#mapa de municipio
mapa_densidad <- panel_placebo %>%
  dplyr::distinct(municipio, densid_vial)

#comparar coeficientes
coef_real <- stats::coef(modelo_twfe_log)["interaccion_log"]
coefs_placebo <- numeric(n_perm)

message("permutando densid_vial entre municipios (", n_perm, " iteraciones)")

for (i in seq_len(n_perm)) {

  #reasignar densid_vial al azar entre municipios
  mapa_shuffled <- mapa_densidad %>%
    dplyr::mutate(densid_vial = sample(densid_vial, replace = FALSE))

  panel_p <- panel_placebo %>%
    dplyr::select(-densid_vial) %>%
    dplyr::left_join(mapa_shuffled, by = "municipio") %>%
    dplyr::mutate(interaccion_log_p = densid_vial * log_imae)

  mod_p <- fixest::feols(
    log_luces ~ interaccion_log_p + interaccion_area | municipio + fecha,
    data = panel_p,
    cluster = ~municipio,
    warn = FALSE, notes = FALSE
  )

  coefs_placebo[i] <- stats::coef(mod_p)["interaccion_log_p"]

  if (i %% 100 == 0) message("  ", i, "/", n_perm)
}

#valor p
p_placebo <- mean(abs(coefs_placebo) >= abs(coef_real))

message("coeficiente real") 
print(round(coef_real,4))
message("media del placebo") 
print(round(mean(coefs_placebo), 4))
message("desviacion (sd)")
print(round(sd(coefs_placebo), 4))
message("valor p-value")
print(p_placebo)

#valor significativo del placebo

#modelos segmentados (estratos) por terciles de liminosidad ----


#clasificar municipios en terciles 
municipios_clasificados <- panel_final %>%
  dplyr::group_by(municipio) %>%
  dplyr::summarise(luz_historica = mean(luces_nocturnas, na.rm = TRUE), .groups = "drop") %>%
  dplyr::mutate(
    tercil = dplyr::ntile(luz_historica, 3),
    categoria = dplyr::case_when(
      tercil == 3 ~ "Estrato Alto",
      tercil == 2 ~ "Estrato Medio",
      tercil == 1 ~ "Estrato Bajo"
    )
  )

panel_estratos <- panel_model %>%
  dplyr::left_join(dplyr::select(municipios_clasificados, municipio, categoria),
                   by = "municipio")

#pre-filtrar cada estrato
panel_alto  <- dplyr::filter(panel_estratos, categoria == "Estrato Alto")
panel_medio <- dplyr::filter(panel_estratos, categoria == "Estrato Medio")
panel_bajo  <- dplyr::filter(panel_estratos, categoria == "Estrato Bajo")

modelos_estrato <- list(
  Alto  = fixest::feols(log_luces ~ interaccion_log + interaccion_area |
                          municipio + fecha,
                        data = panel_alto, cluster = ~municipio),
  Medio = fixest::feols(log_luces ~ interaccion_log + interaccion_area |
                          municipio + fecha,
                        data = panel_medio, cluster = ~municipio),
  Bajo  = fixest::feols(log_luces ~ interaccion_log + interaccion_area |
                          municipio + fecha,
                        data = panel_bajo, cluster = ~municipio)
)

#modelo de estratos
modelo_triple <- fixest::feols(
  log_luces ~ interaccion_log + interaccion_area +
    i(categoria, interaccion_log, ref = "Estrato Alto") +
    i(categoria, interaccion_area, ref = "Estrato Alto") |
    municipio + fecha,
  data = panel_estratos,
  cluster = ~municipio
)

fixest::etable(
  modelos_estrato[["Alto"]],
  modelos_estrato[["Medio"]],
  modelos_estrato[["Bajo"]],
  headers = c("Estrato Alto", "Estrato Medio", "Estrato Bajo")
)

message("como referencia el estrato alto")
summary(modelo_triple)

#analisis de robustez del placebo ----
#no hacer caso esto esta sesgado tiene autocorrelacion serial por lo que
#no es concluyente

#placebo imae adenlantado (lead t+1) 

panel_lead <- panel_model %>%
  dplyr::arrange(municipio, fecha) %>%
  dplyr::group_by(municipio) %>%
  dplyr::mutate(
    log_imae_lead = dplyr::lead(log_imae),
    interaccion_log_lead  = densid_vial * log_imae_lead,
    interaccion_area_lead = log_area * log_imae_lead
  ) %>%
  dplyr::ungroup() %>%
  tidyr::drop_na(log_imae_lead)

modelo_lead <- fixest::feols(
  log_luces ~ interaccion_log_lead + interaccion_area_lead | municipio + fecha,
  data = panel_lead,
  cluster = ~municipio
)

summary(modelo_lead)

panel_lead %>% summarise(cor = cor(log_imae, log_imae_lead, use = "complete.obs"))

# el placebo lead no es concluyente por la autocorrealcion man

fixest::etable(
  modelo_twfe_log,
  modelo_lead,
  headers = c("Modelo Original (t)", "Placebo Lead (t+1)")
)

#mapa de coeficientes municipales (pendientes aleatorias) ----

message("mapa de coeficiente municipales")
message("modelo de pendientes aleatorias con lme4...")

modelo_random <- lme4::lmer(
  log_luces ~ interaccion_log + interaccion_area +
    (1 + interaccion_log | municipio) + (1 | fecha),
  data = panel_model,
  control = lme4::lmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))
)

#se extraye BLUPs

#extraer pendientes aleatorias 
blups_municipio <- lme4::ranef(modelo_random, condVar = TRUE)$municipio
blups_municipio$municipio <- rownames(blups_municipio)

efecto_fijo_interaccion <- lme4::fixef(modelo_random)["interaccion_log"]
blups_municipio$coef_municipal <- efecto_fijo_interaccion +
  blups_municipio$`interaccion_log`

#cargar shapefile para el mapa
ruta_mapa <- here::here("dataset", "geoBoundaries-NIC-ADM2.geojson")
nic_map <- sf::st_read(ruta_mapa, quiet = TRUE) %>%
  dplyr::rename(municipio = shapeName)

#unir coeficientes
nic_map <- nic_map %>%
  dplyr::left_join(
    dplyr::select(blups_municipio, municipio, coef_municipal),
    by = "municipio"
  )

# Mapa coroplético
mapa_coef <- ggplot(nic_map) +
  geom_sf(aes(fill = coef_municipal), color = "white", size = 0.15) +
  scale_fill_viridis_c(option = "plasma",
                       name = expression(beta[1]~municipal)) +
  labs(
    title = "Sensibilidad municipal de luces al IMAE: efecto moderador vial",
    subtitle = paste0(
      "Coeficiente municipal de interaccion_log (EF fijo + BLUP). ",
      "EF fijo global: ", round(efecto_fijo_interaccion, 3)
    ),
    caption = "Fuente: VIIRS-NASA, OSM, BCN. Modelo: lmer con pendiente aleatoria."
  ) +
  theme_void(base_size = 10) +
  theme(legend.position = "bottom", plot.title = element_text(hjust = 0.5),
        plot.subtitle = element_text(hjust = 0.5, size = 8))

ggsave(here::here("Graficos", "mapa_coeficientes_municipales.pdf"),
       plot = mapa_coef, width = 8, height = 7, dpi = 300)


#sensibilidad a saturacion de luces (umbral percentil 95) ----

umbral_p95 <- quantile(panel_model$luces_nocturnas, probs = 0.95, na.rm = TRUE)
message("umbral de saturacion (P95 luces_nocturnas): ",
        round(umbral_p95, 3))

panel_nosat <- panel_model %>%
  dplyr::filter(luces_nocturnas <= umbral_p95)

message("observaciones eliminadas por saturacion: ",
        nrow(panel_model) - nrow(panel_nosat), " de ", nrow(panel_model))

modelo_nosat <- fixest::feols(
  log_luces ~ interaccion_log + interaccion_area | municipio + fecha,
  data = panel_nosat,
  cluster = ~municipio
)

summary(modelo_nosat)

#tabla de robustez
fixest::etable(
  modelo_twfe_log,
  modelo_nosat,
  modelo_lead,
  headers = c("Original", "Sin Saturación (P95)", "Placebo Lead (t+1)")
)

#analisis sectoria ----

panel_final <- panel_final %>%
  mutate(
    log_imae_primario = log(imae_primario),
    interaccion_log_primario = densid_vial * log_imae_primario,
    interaccion_area_primario = log_area * log_imae_primario,
    
    log_imae_secundario = log(imae_secundario),
    interaccion_log_secundario = densid_vial * log_imae_secundario,
    interaccion_area_secundario = log_area * log_imae_secundario,
    
    log_imae_terciario = log(imae_terciario),
    interaccion_log_terciario = densid_vial * log_imae_terciario,
    interaccion_area_terciario = log_area * log_imae_terciario
  )

panel_model <- panel_final %>%
  filter(
    is.finite(log_luces),
    is.finite(interaccion_log_primario),
    is.finite(interaccion_area_primario),
    is.finite(interaccion_log_secundario),
    is.finite(interaccion_area_secundario),
    is.finite(interaccion_log_terciario),
    is.finite(interaccion_area_terciario)
  )

#modelos
modelo_primario <- feols(
  log_luces ~ interaccion_log_primario + interaccion_area_primario | municipio + fecha,
  data = panel_model, cluster = ~municipio
)

modelo_secundario <- feols(
  log_luces ~ interaccion_log_secundario + interaccion_area_secundario | municipio + fecha,
  data = panel_model, cluster = ~municipio
)

modelo_terciario <- feols(
  log_luces ~ interaccion_log_terciario + interaccion_area_terciario | municipio + fecha,
  data = panel_model, cluster = ~municipio
)
#tabla comparativa
etable(modelo_twfe_log, #modelo con imae total
       modelo_primario, 
       modelo_secundario, 
       modelo_terciario,
       headers = c("Total", "Primario", "Secundario", "Terciario"))



