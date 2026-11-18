"""Perfil del mazo desde las habilidades: mismas reglas que la app (Dart)."""

import json

from myl_sim import perfil


def _destruir(**extra):
    return {"accion": "destruir", "cuando": "al_jugar", "objetivo": {"quien": "oponente", "zona": "en_juego"}, **extra}


def test_roles_de_una_carta():
    assert perfil.roles_de_carta([_destruir()]) == {"remocion": 1.0}
    medjay = perfil.roles_de_carta([
        {"accion": "imbloqueable", "cuando": "continua"},
        {"accion": "botar", "cuando": "al_atacar", "cantidad": 1, "objetivo": {"quien": "ambos"}},
    ])
    assert set(medjay) == {"presion", "dano_directo"}
    capa = perfil.roles_de_carta([{"accion": "barajar", "cuando": "oponente_juega",
                                   "objetivo": {"quien": "disparadora", "zona": "en_juego"}}])
    assert set(capa) == {"remocion", "respuesta"}
    assert perfil.roles_de_carta([]) == {}
    # Destruir lo propio no es remoción.
    assert perfil.roles_de_carta([_destruir(objetivo={"quien": "propio", "zona": "en_juego"})]) == {}


def test_peso_por_alcance_repeticion_y_costo():
    una = perfil.roles_de_carta([_destruir()])["remocion"]
    todas = perfil.roles_de_carta([_destruir(objetivo={"quien": "oponente", "zona": "en_juego",
                                                       "seleccion": "todos"})])["remocion"]
    activada = perfil.roles_de_carta([_destruir(cuando="activada")])["remocion"]
    cara = perfil.roles_de_carta([_destruir(cuando="activada", costo={"oros": 3})])["remocion"]
    assert todas > una and activada > una and cara < activada
    tope = perfil.roles_de_carta([_destruir(cuando="activada", objetivo={"quien": "oponente", "zona": "en_juego",
                                                                         "seleccion": "todos"})] * 5)
    assert tope["remocion"] == perfil.TOPE_CARTA


def test_hipergeometrica():
    assert perfil.hipergeometrica(40, 0, 8) == 0
    assert perfil.hipergeometrica(40, 40, 8) == 1
    assert abs(perfil.hipergeometrica(40, 4, 8) - 0.6065) < 1e-4


def test_indice_se_mueve_en_la_direccion_correcta():
    base = perfil.indice_velocidad(15, 15, 34, 2.4)
    assert perfil.indice_velocidad(30, 15, 34, 2.4) > base
    assert perfil.indice_velocidad(15, 35, 34, 2.4) < base
    assert perfil.indice_velocidad(15, 15, 34, 3.1) < base
    assert perfil.indice_velocidad(0, 0, 0, 0) == 50


def test_casos_compartidos_con_la_app_estan_al_dia():
    """Si falla: cambió una regla o un peso; regenerar con `python -m myl_sim.perfil casos`
    y aplicar el mismo cambio en lib/domain/analisis_mazo/analisis_mazo.dart."""
    datos = json.loads(perfil.ARCHIVO_CASOS.read_text(encoding="utf-8"))
    assert datos["casos"]
    for caso in datos["casos"]:
        entradas = [({k: v for k, v in c.items() if k != "copias"}, c["copias"]) for c in caso["cartas"]]
        assert perfil.analizar(entradas) == caso["esperado"], caso["nombre"]


def test_sin_programar_solo_cuenta_cartas_con_texto():
    r = perfil.analizar([
        ({"nombre": "Soldado", "tipo": "Aliado", "coste": 1, "fuerza": 2, "habilidades": []}, 3),
        ({"nombre": "Pendiente", "tipo": "Aliado", "coste": 2, "habilidad": "Roba una carta."}, 1),
        ({"nombre": "Oro", "tipo": "Oro"}, 6),
    ])
    assert r["sinProgramar"] == 1 and r["oros"] == 6 and r["noOros"] == 4


_NODE_PERFIL = r"""
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const a = html.indexOf('// <perfil-habilidades>'), b = html.indexOf('// </perfil-habilidades>');
if (a < 0 || b < 0) throw new Error('no se encontró el bloque perfil-habilidades');
const PERFIL = new Function(html.slice(a, b) + '\nreturn PERFIL;')();
const casos = JSON.parse(fs.readFileSync(process.argv[3], 'utf8')).casos;
const out = casos.map(caso => {
  const r = PERFIL.analizar(caso.cartas.map(c => ({
    tipo: c.tipo, coste: c.coste, copias: c.copias, roles: PERFIL.rolesDeHabilidades(c.habilidades),
  })));
  return { indice: r.indice, perfil: r.perfil, puntos: r.puntos, copiasPorRol: r.copiasPorRol,
           total: r.total, oros: r.oros };
});
process.stdout.write(JSON.stringify(out));
"""


def test_dashboard_calcula_lo_mismo_que_el_simulador(tmp_path):
    """El dashboard de ligas (JavaScript) usa las mismas reglas: se ejecuta su
    bloque `perfil-habilidades` con Node sobre los casos compartidos."""
    import shutil
    import subprocess

    import pytest

    node = shutil.which("node")
    if not node:
        pytest.skip("Node no está instalado")
    dashboard = perfil.ARCHIVO_CASOS.parents[2] / "dashboard" / "index.html"
    guion = tmp_path / "perfil.js"
    guion.write_text(_NODE_PERFIL, encoding="utf-8")
    r = subprocess.run([node, str(guion), str(dashboard), str(perfil.ARCHIVO_CASOS)],
                       capture_output=True, text=True, encoding="utf-8")
    assert r.returncode == 0, r.stderr
    casos = json.loads(perfil.ARCHIVO_CASOS.read_text(encoding="utf-8"))["casos"]
    for caso, js in zip(casos, json.loads(r.stdout), strict=True):
        e = caso["esperado"]
        assert (js["indice"], js["perfil"], js["total"], js["oros"]) == (
            e["indice"], e["perfil"], e["total"], e["oros"]), caso["nombre"]
        assert js["copiasPorRol"] == e["copiasPorRol"], caso["nombre"]
        for rol in perfil.ROLES:
            assert abs(js["puntos"][rol] - e["roles"][rol]) < 0.02, (caso["nombre"], rol)
