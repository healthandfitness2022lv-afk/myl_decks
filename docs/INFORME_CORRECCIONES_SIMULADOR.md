# Informe de correcciones del simulador

Registro de lo que se corrigió a partir de los reportes que Héctor deja en el tablero (botón del bicho).
Lo actualiza el agente horario «Corregir reportes del simulador (cada hora)». Lo más nuevo va arriba.

Cómo funciona: el worker copia cada 10 minutos los reportes de Firestore a `simulator/cache/reportes/`.
El agente revisa los nuevos (`python -m myl_sim.buzon_reportes pendientes`), reproduce la mesa, corrige el motor
con un test y deja aquí una fila por reporte. Si cambió el código, hay que reiniciar el worker.

## 19/11/2026 22:57 (primera ejecución del agente)

- Se activó el buzón: 630 reportes copiados (46 desafíos y 94 simulaciones). Ninguno nuevo desde el último arreglo.

## 19/11/2026 00:15 (arreglo manual, antes del agente)

| Reporte | Carta | Qué pasaba | Qué se hizo | Archivo y test |
|---|---|---|---|---|
| IQVB T2 | Sir Agravain | Robaba 2 estando solo, aunque pide «otro Aliado Caballero» | Al jugarla, la propia carta ya no cuenta para su condición | `habilidades.py`, `test_sir_agravain_solo_no_roba` |
| dmwP T11 y P3Cy T18 | Magia Amatista | Dejaba robar sin destruir una copia en juego | El robo solo va si destruyó (nueva relación `si_anterior`, «si lo haces») | `datos.py`, `habilidades.py`, `test_magia_amatista_*` |
| dmwP T1 | Marmita Druida | Robaba sin mostrar un Druida de la mano | Ahora muestra un Druida y luego roba | `datos.py`, `test_marmita_druida_muestra_un_druida_para_robar` |
| dmwP T3 | Tadg | La carta tomada quedaba oculta aunque solo puede ser Oro o Aliado Druida | Se muestra la carta para probar que cumple | `habilidades.py`, `test_tadg_muestra_la_carta_que_toma` |
| gYcs T7 | Damarchus | No se podía activar en la Guerra de Talismanes | Se habilitó su activación en esa fase | `test_damarchus_se_activa_en_la_guerra_de_talismanes` |
