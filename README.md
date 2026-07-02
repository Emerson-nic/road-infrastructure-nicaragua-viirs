Ecuación del Modelo

El moodelo final en `fixest::feols` se ve así:

$$\text{Luces}_{i,t} = \beta_1 (\text{DensidadVial}_i \times \text{IMAE}_t) + \alpha_i + \delta_t + \varepsilon_{i,t}$$

$\text{Luces}_{i,t}$: variable dependiente (Y).

$\beta_1$: Mide cuánto cambia el brillo del municipio ante cambios en la economía nacional (IMAE), condicionado a qué tanta densidad vial tiene.

$\alpha_i$ (Efecto Fijo de Municipio): Controla por todo lo que hace que un municipio sea brillante o oscuro de forma permanente (topografía, cultura, clima, tamaño poblacional inicial)

.$\delta_t$ (Efecto Fijo de Fecha/Mes): Controla por todo lo que afecta a toda Nicaragua en un mes específico (ej. un shock de precios, una política fiscal nacional, una temporada de huracanes, o el efecto Navidad).
