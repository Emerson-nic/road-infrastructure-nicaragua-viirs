if(F){
  "

 mapa de nic vista nocturna desde NASA VIIRS
 producto mensual VNP46A3: diciembre 2025

  "
}

options(repos = c(CRAN = "https://cloud.r-project.org"))
if (!require("pacman")) install.packages("pacman")

pacman::p_load(blackmarbler,
               terra,
               sf,
               ggplot2,
               dplyr,
               viridis)

#limites de nicaragua
ruta_mapa <- here::here("dataset", "geoBoundaries-NIC-ADM2.geojson")
nic_sf <- sf::st_read(ruta_mapa, quiet = TRUE)
nic_union <- sf::st_union(nic_sf)

#proyectar limites a UTM 16N (pixeles uniformes)
nic_sf_utm <- sf::st_transform(nic_sf, "EPSG:32616")
nic_union_utm <- sf::st_transform(nic_union, "EPSG:32616")

#producto mensual: diciembre 2025
r <- blackmarbler::bm_raster(
  roi_sf = nic_sf,
  product_id = "VNP46A3",
  date = "2025-12-01",
  bearer = Sys.getenv("NASA_EARTHDATA_TOKEN"),
  output_dir = here::here("dataset"),
  quiet = FALSE
)

#recortes
r_nic <- terra::crop(r, terra::vect(nic_union))
r_nic <- terra::mask(r_nic, terra::vect(nic_union))

#proyectar raster a UTM 16N (pixeles cuadrados uniformes)
r_utm <- terra::project(r_nic, "EPSG:32616")

#agregar a 2km (menos pixeles -> sin grilla visible)
r_utm <- terra::aggregate(r_utm, fact = 4, fun = "mean", na.rm = TRUE)

#dataframe completo
df <- as.data.frame(r_utm, xy = TRUE, na.rm = FALSE)
names(df) <- c("x", "y", "radiancia")
df <- df %>% dplyr::filter(!is.na(radiancia))

#winsorizar al 99%
positivos <- df$radiancia[df$radiancia > 0]
if(length(positivos) > 0){
  max_val <- quantile(positivos, 0.99, na.rm = TRUE)
  df <- df %>% dplyr::mutate(radiancia = ifelse(radiancia > max_val, max_val, radiancia))
}

#grafico: sin warnings, sin grilla, sin pixelacion
p <- ggplot() +
  geom_tile(data = df, aes(x = x, y = y, fill = radiancia)) +
  scale_fill_viridis_c(
    option = "inferno",
    direction = 1,
    na.value = "white",
    name = expression(atop("Radiancia", (nW%.%cm^{-2}%.%sr^{-1})))
  ) +
  geom_sf(data = nic_sf_utm, fill = NA, color = "grey60", linewidth = 0.08) +
  geom_sf(data = nic_union_utm, fill = NA, color = "grey30", linewidth = 0.15) +
  coord_sf(expand = FALSE) +
  theme_void() +
  theme(
    panel.background = element_rect(fill = "white", color = NA),
    plot.background = element_rect(fill = "white", color = NA),
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank(),
    legend.position = "bottom",
    legend.text = element_text(color = "black", size = 8),
    legend.title = element_text(color = "black", size = 9)
  )

ggplot2::ggsave(
  here::here("Graficos", "mapa_satelital_nicaragua.pdf"),
  plot = p, width = 8, height = 6, dpi = 300
)

print(p)
