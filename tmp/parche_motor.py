import sys
f = sys.argv[1]
s = open(f, encoding="utf-8", newline="").read()
if "def _tras_guerra" in s:
    print("ya estaba"); sys.exit()
a = """        self.e.fase = "guerra_talismanes"
        self._guerra_de_talismanes(d)
        hab.expirar(self, "hasta_guerra_talismanes")
"""
nl = "\r\n" if "\r\n" in s else "\n"
a = a.replace("\n", nl)
assert s.count(a) == 1, s.count(a)
b = """        self.e.fase = "guerra_talismanes"
        self._guerra_de_talismanes(d)
        self._tras_guerra(atacantes, bloqueos, d)

    def _tras_guerra(self, atacantes: list[Instancia],
                     bloqueos: dict[int, Instancia], defensor: int) -> None:
        \"\"\"Lo que sigue a la Guerra de Talismanes: daño y destrucciones del
        combate. Separado para que la búsqueda pueda continuar desde ahí.\"\"\"
        d = defensor
        hab.expirar(self, "hasta_guerra_talismanes")
""".replace("\n", nl)
s = s.replace(a, b)
open(f, "w", encoding="utf-8", newline="").write(s)
print("ok")
