"""Infografía detallada y verificable de la bitácora del 14/11/2026."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "bitacora" / "fondo.png"
OUTPUT = ROOT / "assets" / "bitacora" / "2026-11-14.png"
W, H = 1600, 2600

art = Image.open(SOURCE).convert("RGB")
art = art.resize((W, 2000), Image.Resampling.LANCZOS)
base = Image.new("RGBA", (W, H), (10, 14, 20, 255))
base.paste(art.convert("RGBA"), (0, 0))
shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
sd = ImageDraw.Draw(shade)
for y in range(H):
    alpha = 60 if y < 250 else min(205, 70 + y // 32)
    sd.line((0, y, W, y), fill=(7, 11, 18, alpha))
base = Image.alpha_composite(base, shade)
layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)

GOLD = (241, 212, 139, 255)
GOLD2 = (217, 163, 35, 255)
WHITE = (247, 246, 241, 255)
MUTED = (197, 204, 211, 255)
BLUE = (112, 195, 237, 255)
GREEN = (122, 214, 161, 255)
PANEL = (15, 19, 26, 235)
FONT_DIR = Path(r"C:\Windows\Fonts")


def font(size, bold=False):
    return ImageFont.truetype(
        str(FONT_DIR / ("segoeuib.ttf" if bold else "segoeui.ttf")), size
    )


def txt(x, y, value, size=30, color=WHITE, bold=False):
    d.text((x, y), value, font=font(size, bold), fill=color)


def lines(value, max_width, size, bold=False):
    out = []
    for paragraph in value.split("\n"):
        current = ""
        for word in paragraph.split():
            attempt = f"{current} {word}".strip()
            if d.textbbox((0, 0), attempt, font=font(size, bold))[2] <= max_width:
                current = attempt
            else:
                if current:
                    out.append(current)
                current = word
        if current:
            out.append(current)
    return out


def card(y0, title, subtitle, items, accent=GOLD, body_size=28):
    x0, x1 = 76, W - 76
    item_lines = [lines(item, x1 - x0 - 128, body_size) for item in items]
    line_h = body_size + 15
    row_heights = [max(60, len(parts) * line_h + 12) for parts in item_lines]
    height = 130 + sum(row_heights) + 23
    d.rounded_rectangle(
        (x0, y0, x1, y0 + height), radius=26,
        fill=PANEL, outline=(241, 212, 139, 98), width=2,
    )
    d.rounded_rectangle((x0 + 27, y0 + 28, x0 + 34, y0 + 98), radius=3, fill=accent)
    txt(x0 + 59, y0 + 25, title, 38, WHITE, True)
    txt(x0 + 61, y0 + 80, subtitle, 23, accent, True)
    yy = y0 + 130
    for parts, row_h in zip(item_lines, row_heights):
        d.ellipse((x0 + 41, yy + 17, x0 + 51, yy + 27), fill=accent)
        for line in parts:
            txt(x0 + 72, yy, line, body_size, MUTED)
            yy += line_h
        yy += row_h - len(parts) * line_h
    return y0 + height


# Heading
txt(80, 72, "MYL MAZOS  /  NEXUS", 29, GOLD, True)
d.line((80, 119, 1030, 119), fill=(241, 212, 139, 130), width=2)
txt(77, 138, "FIXES DEL DÍA", 82, WHITE, True)
txt(82, 244, "SÁBADO 14 DE NOVIEMBRE DE 2026", 32, GOLD, True)
txt(82, 299, "Arreglos de cartas, motor, tablero y análisis de partidas", 31, WHITE)

y = 385
y = card(y, "01  ·  CARTAS Y REGLAS", "Habilidades, objetivos y condiciones", [
    "Morir de Pie: ya no se ofrece sin 2 Aliados de la misma raza.",
    "Bereber, Sir Erec, Dario III y Anand: ahora eliges la habilidad por nombre.",
    "Nacimiento de Pegaso: pregunta si dejar la carta arriba o enviarla al fondo.",
    "Afrodita: nombras el tipo antes de mirar; ella e Idmon avisan si fallan.",
    "Sir Bedivere: solo ofrece Aliados de la raza rival y filtra por nombre.",
    "Ptah: eliges tú las cartas del Cementerio; Renpet y Estrella ocultan lo privado.",
    "Milano Negro: eliges la raza; Escudo Miliciano funciona también al bloquear.",
    "Corona Faraónica: el objetivo único se toma solo; el pago de Oros inválido se completa.",
    "Oros pagados: disparan Caldero de Corff y Gaitas como corresponde.",
    "Mut, Fuego Pascual y Castillo en 0: efectos, objetivos y derrota corregidos.",
    "Olas, Rhiannon, Magia Amatista y Salmón: uso y ventanas ajustados al texto.",
], GOLD, body_size=27)

y += 31
y = card(y, "02  ·  DESAFÍO IA", "Correcciones del tablero y la experiencia de juego", [
    "Atacar requiere arrastrar; tocar un Aliado ya no lo manda al ataque.",
    "Las Armas portadas se pueden tocar; las cartas se amplían en la mesa.",
    "La franja central muestra todas las opciones sin tapar objetivos rivales.",
    "El pago de Oros se elige dentro de la mesa, con opciones visibles.",
    "Se quitaron las jugadas imaginarias que aparecían durante la búsqueda de IA.",
    "Las fases vacías avanzan solas; la IA deja tiempo para anular sus jugadas.",
    "Se añadieron reportes en vivo, aviso de turno y registro privado correcto.",
    "Las imágenes web se precargan y reintentan; las cartas se ven más grandes.",
    "Reserva, Oros pagados y virtuales muestran contadores y restricciones.",
], BLUE, body_size=27)

y += 31
y = card(y, "03  ·  ANÁLISIS Y REPRODUCCIÓN", "Errores corregidos en los informes de partidas", [
    "La revisión de IA ya no se limita a partidas perdidas ni devuelve siempre «sin error claro».",
    "Cuando dos jugadas ganan, el análisis distingue la que cierra antes.",
    "Las partidas con «No usar» vuelven a reproducirse y analizarse correctamente.",
    "Se eliminaron las marcas del registro privado de la narración pública.",
    "La comparación ya no muestra jugadas iguales ni llena el informe de «parejo».",
    "El reanálisis de partidas viejas usa las reglas con que fueron jugadas.",
], GREEN, body_size=27)

txt(82, H - 70, "Fuente: BITACORA.md · 14/11/2026", 24, MUTED)
txt(W - 312, H - 70, "MYL  /  NEXUS", 24, GOLD, True)

if y > H - 110:
    raise RuntimeError(f"El contenido sobrepasa el lienzo: {y} > {H - 110}")

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
Image.alpha_composite(base, layer).convert("RGB").save(OUTPUT, quality=95)
print(OUTPUT, "contenido hasta", y)
